package server

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// fixedClock lets the test advance time without sleeping.
type fixedClock struct{ now time.Time }

func (c *fixedClock) advance(d time.Duration) { c.now = c.now.Add(d) }

func newTestLimiter(rate, burst float64) (*RateLimiter, *fixedClock) {
	clock := &fixedClock{now: time.Unix(0, 0)}
	limiter := NewRateLimiter(rate, burst)
	limiter.now = func() time.Time { return clock.now }
	return limiter, clock
}

func TestRateLimiterAllowsBurstThenBlocks(t *testing.T) {
	limiter, _ := newTestLimiter(1, 3)

	for i := range 3 {
		if !limiter.Allow("1.2.3.4") {
			t.Fatalf("request %d was blocked inside the burst allowance", i+1)
		}
	}
	if limiter.Allow("1.2.3.4") {
		t.Error("expected the request past the burst allowance to be blocked")
	}
}

func TestRateLimiterRefillsOverTime(t *testing.T) {
	limiter, clock := newTestLimiter(1, 2)

	limiter.Allow("1.2.3.4")
	limiter.Allow("1.2.3.4")
	if limiter.Allow("1.2.3.4") {
		t.Fatal("bucket should be empty")
	}

	clock.advance(time.Second)
	if !limiter.Allow("1.2.3.4") {
		t.Error("expected one token back after a second")
	}
	if limiter.Allow("1.2.3.4") {
		t.Error("expected only one token back")
	}
}

func TestRateLimiterIsPerCaller(t *testing.T) {
	limiter, _ := newTestLimiter(1, 1)

	if !limiter.Allow("1.2.3.4") {
		t.Fatal("first caller should be allowed")
	}
	if !limiter.Allow("5.6.7.8") {
		t.Error("a different caller must not be blocked by the first one's usage")
	}
}

func TestRateLimiterEvictsIdleCallers(t *testing.T) {
	limiter, clock := newTestLimiter(1, 2)
	limiter.Allow("1.2.3.4")

	// Long enough for the bucket to have fully refilled, plus the margin.
	clock.advance(10 * time.Minute)
	limiter.Allow("5.6.7.8")

	limiter.mu.Lock()
	defer limiter.mu.Unlock()
	if _, exists := limiter.buckets["1.2.3.4"]; exists {
		t.Error("an idle caller's bucket should have been swept, or the map grows without bound")
	}
}

func TestClientIPIgnoresThePort(t *testing.T) {
	cases := map[string]string{
		"203.0.113.7:51234": "203.0.113.7",
		"[2001:db8::1]:443": "2001:db8::1",
		"not-an-address":    "not-an-address",
	}
	for addr, want := range cases {
		if got := clientIP(addr); got != want {
			t.Errorf("clientIP(%q) = %q, want %q", addr, got, want)
		}
	}
}

func TestRateLimitHTTPSharesABucketAcrossConnections(t *testing.T) {
	limiter, _ := newTestLimiter(1, 2)
	handler := RateLimitHTTP(limiter, http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))

	var codes []int
	for port := range 3 {
		req := httptest.NewRequest(http.MethodPost, "/v1/service-records/x/attachments", nil)
		req.RemoteAddr = fmt.Sprintf("203.0.113.7:%d", 50000+port)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		codes = append(codes, rec.Code)
	}

	if codes[2] != http.StatusTooManyRequests {
		t.Fatalf("third request from the same IP on a new port: got %v, want the last one throttled", codes)
	}
}
