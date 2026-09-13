package auth

import (
	"sync"
	"time"
)

// Defaults for both sign-in flows.
const (
	LoginFailureLimit = 5
	LoginLockout      = 5 * time.Minute
	LockedMessage     = "muitas tentativas para esta conta — aguarde alguns minutos"
)

// LoginThrottle slows password guessing against one account, however many
// addresses the guesses come from — the per-IP rate limit alone does not.
//
// Only failures count, and a success clears them, so someone signing in
// normally is never slowed. Accounts are keyed by the identifier typed, known
// or not, so a lock reveals nothing about who is registered. The lock is short
// on purpose: anyone can trip it for someone else's CNPJ or phone.
type LoginThrottle struct {
	mu       sync.Mutex
	accounts map[string]*loginFailures
	limit    int
	lockout  time.Duration
	now      func() time.Time
}

type loginFailures struct {
	count       int
	lastFailure time.Time
	lockedUntil time.Time
}

// NewLoginThrottle locks an account for lockout after limit failures in a row.
func NewLoginThrottle(limit int, lockout time.Duration) *LoginThrottle {
	return &LoginThrottle{
		accounts: map[string]*loginFailures{},
		limit:    limit,
		lockout:  lockout,
		now:      time.Now,
	}
}

// Locked reports whether sign-in attempts for key are refused right now.
func (t *LoginThrottle) Locked(key string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()

	record, ok := t.accounts[key]
	return ok && t.now().Before(record.lockedUntil)
}

// Fail records a failed attempt, locking the account once it hits the limit.
func (t *LoginThrottle) Fail(key string) {
	t.mu.Lock()
	defer t.mu.Unlock()

	now := t.now()
	record, ok := t.accounts[key]
	if !ok || now.Sub(record.lastFailure) > t.lockout {
		t.evictStaleLocked(now)
		record = &loginFailures{}
		t.accounts[key] = record
	}

	record.count++
	record.lastFailure = now
	if record.count >= t.limit {
		record.lockedUntil = now.Add(t.lockout)
		record.count = 0
	}
}

// Succeed forgets the account's failures.
func (t *LoginThrottle) Succeed(key string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.accounts, key)
}

// evictStaleLocked drops accounts whose failures and lock have both expired,
// so guesses at random identifiers cannot grow the map without bound.
func (t *LoginThrottle) evictStaleLocked(now time.Time) {
	for key, record := range t.accounts {
		if now.Sub(record.lastFailure) > t.lockout && now.After(record.lockedUntil) {
			delete(t.accounts, key)
		}
	}
}
