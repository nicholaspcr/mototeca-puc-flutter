package server

import (
	"net/http"
	"net/url"
	"slices"
)

// Headers a Connect client sends and reads, so a browser may use them
// cross-origin.
const (
	corsAllowedHeaders = "Content-Type, Authorization, Connect-Protocol-Version, Connect-Timeout-Ms, X-User-Agent"
	corsExposedHeaders = "Connect-Protocol-Version, Grpc-Status, Grpc-Message"
)

// CORS lets browser clients call the API from another origin, which is how
// the Flutter web build runs. Without configured origins only loopback ones
// are allowed, since `flutter run -d chrome` serves from a random localhost
// port. "*" allows any origin; that is safe here because sessions travel in
// the Authorization header, never in cookies a foreign page could ride.
func CORS(allowedOrigins []string, next http.Handler) http.Handler {
	allowAny := slices.Contains(allowedOrigins, "*")

	allowed := func(origin string) bool {
		if allowAny || slices.Contains(allowedOrigins, origin) {
			return true
		}
		return len(allowedOrigins) == 0 && isLoopback(origin)
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			next.ServeHTTP(w, r)
			return
		}

		w.Header().Add("Vary", "Origin")
		if !allowed(origin) {
			next.ServeHTTP(w, r)
			return
		}

		h := w.Header()
		h.Set("Access-Control-Allow-Origin", origin)
		h.Set("Access-Control-Expose-Headers", corsExposedHeaders)

		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			h.Set("Access-Control-Allow-Methods", "GET, POST")
			h.Set("Access-Control-Allow-Headers", corsAllowedHeaders)
			h.Set("Access-Control-Max-Age", "7200")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isLoopback(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	}
	return false
}
