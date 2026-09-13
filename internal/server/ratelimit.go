package server

import (
	"context"
	"errors"
	"net"
	"net/http"
	"sync"
	"time"

	"connectrpc.com/connect"
)

// RateLimiter is a per-caller token bucket.
//
// State is in-process, so limits are per API instance rather than global. That
// is honest for a single-instance deployment and still blunts the two abuses
// that matter here: password guessing against Login, and scraping the plate
// lookup, which is public by design (ARCHITECTURE.md sections 8 and 3).
// A multi-instance deployment needs a shared store instead.
type RateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	rate    float64
	burst   float64
	now     func() time.Time
}

type bucket struct {
	tokens   float64
	lastSeen time.Time
}

// NewRateLimiter allows burst requests immediately, refilling at rate per
// second.
func NewRateLimiter(ratePerSecond, burst float64) *RateLimiter {
	return &RateLimiter{
		buckets: map[string]*bucket{},
		rate:    ratePerSecond,
		burst:   burst,
		now:     time.Now,
	}
}

// Allow consumes a token for key, reporting whether the request may proceed.
func (l *RateLimiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	b, ok := l.buckets[key]
	if !ok {
		// Sweep while we already hold the lock, so idle callers don't
		// accumulate into a memory leak.
		l.evictStaleLocked(now)
		b = &bucket{tokens: l.burst, lastSeen: now}
		l.buckets[key] = b
	}

	b.tokens = min(l.burst, b.tokens+now.Sub(b.lastSeen).Seconds()*l.rate)
	b.lastSeen = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// evictStaleLocked drops buckets that have had time to fully refill, since
// those are indistinguishable from a fresh one.
func (l *RateLimiter) evictStaleLocked(now time.Time) {
	idleUntilFull := time.Duration(l.burst/l.rate*float64(time.Second)) + time.Minute
	for key, b := range l.buckets {
		if now.Sub(b.lastSeen) > idleUntilFull {
			delete(l.buckets, key)
		}
	}
}

// RateLimitInterceptor throttles each procedure per client IP. Procedures
// absent from limiters share fallback, so no endpoint is unlimited.
func RateLimitInterceptor(limiters map[string]*RateLimiter, fallback *RateLimiter) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			limiter, ok := limiters[req.Spec().Procedure]
			if !ok {
				limiter = fallback
			}

			if !limiter.Allow(clientIP(req.Peer().Addr)) {
				return nil, connect.NewError(connect.CodeResourceExhausted, errTooManyRequests)
			}
			return next(ctx, req)
		}
	}
}

// RateLimitHTTP is RateLimitInterceptor for plain HTTP routes.
func RateLimitHTTP(limiter *RateLimiter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow(clientIP(r.RemoteAddr)) {
			writeError(w, http.StatusTooManyRequests, "resource_exhausted", errTooManyRequests.Error())
			return
		}
		next.ServeHTTP(w, r)
	})
}

var errTooManyRequests = errors.New("muitas tentativas — aguarde um pouco e tente de novo")

// clientIP drops the port: every new connection gets a fresh one, so keying on
// the full address would hand each connection its own bucket.
func clientIP(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}
