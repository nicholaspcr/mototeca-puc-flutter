package auth

import (
	"testing"
	"time"
)

func newTestThrottle(limit int, lockout time.Duration) (*LoginThrottle, *time.Time) {
	now := time.Unix(0, 0)
	throttle := NewLoginThrottle(limit, lockout)
	throttle.now = func() time.Time { return now }
	return throttle, &now
}

func TestLoginThrottleLocksAfterTheLimit(t *testing.T) {
	throttle, _ := newTestThrottle(3, time.Minute)

	for range 2 {
		throttle.Fail("11222333000181")
	}
	if throttle.Locked("11222333000181") {
		t.Fatal("locked before reaching the limit")
	}

	throttle.Fail("11222333000181")
	if !throttle.Locked("11222333000181") {
		t.Fatal("expected the account to be locked at the limit")
	}
	if throttle.Locked("11444555000149") {
		t.Error("another account must not be locked")
	}
}

func TestLoginThrottleUnlocksAfterTheLockout(t *testing.T) {
	throttle, now := newTestThrottle(1, time.Minute)
	throttle.Fail("key")

	*now = now.Add(time.Minute + time.Second)

	if throttle.Locked("key") {
		t.Error("expected the lock to expire")
	}
}

func TestLoginThrottleSuccessClearsFailures(t *testing.T) {
	throttle, _ := newTestThrottle(2, time.Minute)

	throttle.Fail("key")
	throttle.Succeed("key")
	throttle.Fail("key")

	if throttle.Locked("key") {
		t.Error("a success in between must reset the count")
	}
}

func TestLoginThrottleForgetsOldFailures(t *testing.T) {
	throttle, now := newTestThrottle(2, time.Minute)

	throttle.Fail("key")
	*now = now.Add(2 * time.Minute)
	throttle.Fail("key")

	if throttle.Locked("key") {
		t.Error("failures further apart than the lockout must not add up")
	}
}

func TestLoginThrottleEvictsStaleAccounts(t *testing.T) {
	throttle, now := newTestThrottle(5, time.Minute)
	throttle.Fail("old")

	*now = now.Add(10 * time.Minute)
	throttle.Fail("new")

	throttle.mu.Lock()
	defer throttle.mu.Unlock()
	if _, exists := throttle.accounts["old"]; exists {
		t.Error("a stale account should have been swept")
	}
}
