package main

import (
	"sync"
	"time"
)

// rateLimiter implementa una ventana deslizante simple por clave (IP).
// limita cuantas veces se puede ejecutar una accion (ej: crear sala) por minuto.
type rateLimiter struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
}

func newRateLimiter(perMinute int) *rateLimiter {
	if perMinute < 0 {
		perMinute = 0
	}
	return &rateLimiter{
		hits:   make(map[string][]time.Time),
		limit:  perMinute,
		window: time.Minute,
	}
}

func (rl *rateLimiter) enabled() bool {
	return rl != nil && rl.limit > 0
}

// allow registra un intento y devuelve true si la clave sigue dentro del limite.
func (rl *rateLimiter) allow(key string) bool {
	if !rl.enabled() {
		return true
	}
	now := time.Now()
	cutoff := now.Add(-rl.window)

	rl.mu.Lock()
	defer rl.mu.Unlock()

	kept := rl.hits[key][:0]
	for _, t := range rl.hits[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= rl.limit {
		rl.hits[key] = kept
		return false
	}
	rl.hits[key] = append(kept, now)
	return true
}
