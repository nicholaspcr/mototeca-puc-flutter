package server

import (
	"context"
	"errors"
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

// RateLimitInterceptor throttles the named procedures per calling address.
// Procedures absent from the map are not limited.
func RateLimitInterceptor(limiters map[string]*RateLimiter) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			limiter, ok := limiters[req.Spec().Procedure]
			if !ok {
				return next(ctx, req)
			}

			if !limiter.Allow(req.Peer().Addr) {
				return nil, connect.NewError(
					connect.CodeResourceExhausted,
					errors.New("too many requests — try again shortly"),
				)
			}
			return next(ctx, req)
		}
	}
}
