package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func preflight(origin string) *http.Request {
	req := httptest.NewRequest(http.MethodOptions, "/mototeca.vehicle.v1.VehicleService/CreateVehicle", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	return req
}

func TestCORS(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusMethodNotAllowed)
	})

	cases := []struct {
		name      string
		allowed   []string
		origin    string
		wantAllow bool
	}{
		{"loopback allowed by default", nil, "http://localhost:53211", true},
		{"ipv4 loopback allowed by default", nil, "http://127.0.0.1:8081", true},
		{"foreign origin refused by default", nil, "https://evil.example", false},
		{"lookalike host refused", nil, "http://localhost.evil.example", false},
		{"listed origin allowed", []string{"https://app.mototeca.com.br"}, "https://app.mototeca.com.br", true},
		{"loopback refused once a list is set", []string{"https://app.mototeca.com.br"}, "http://localhost:3000", false},
		{"wildcard allows anything", []string{"*"}, "https://anywhere.example", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			CORS(tc.allowed, next).ServeHTTP(rec, preflight(tc.origin))

			got := rec.Header().Get("Access-Control-Allow-Origin")
			if tc.wantAllow {
				if got != tc.origin || rec.Code != http.StatusNoContent {
					t.Fatalf("want preflight allowed for %s, got status %d origin %q", tc.origin, rec.Code, got)
				}
				return
			}
			if got != "" {
				t.Fatalf("want %s refused, got Access-Control-Allow-Origin %q", tc.origin, got)
			}
		})
	}
}

func TestCORSPassesSameOriginRequestsThrough(t *testing.T) {
	called := false
	next := http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true })

	req := httptest.NewRequest(http.MethodPost, "/healthz", nil)
	CORS(nil, next).ServeHTTP(httptest.NewRecorder(), req)

	if !called {
		t.Fatal("a request without Origin must reach the handler")
	}
}
