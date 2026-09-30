package main

import (
	"crypto/subtle"
	"encoding/json"
	"net"
	"net/http"
	"strings"
	"time"
)

type createRoomRequest struct {
	Name string `json:"name"`
	Host string `json:"host"`
	Map  string `json:"map"`
	Mode string `json:"mode"`
	Max  int    `json:"max"`
}

type heartbeatRequest struct {
	Status  string `json:"status"`
	Players int    `json:"players"`
	Phase   string `json:"phase"`
}

type roomResponse struct {
	ID      string `json:"room_id"`
	Host    string `json:"host"`
	Owner   string `json:"owner"`
	Port    int    `json:"port"`
	Status  string `json:"status"`
	Name    string `json:"name"`
	Map     string `json:"map"`
	Mode    string `json:"mode"`
	Max     int    `json:"max"`
	Players int    `json:"players"`
	Phase   string `json:"phase"`
	// Token solo se devuelve en la respuesta de creacion; nunca en listados.
	Token string `json:"token,omitempty"`
}

func NewHTTPHandler(reg *Registry, cfg Config) http.Handler {
	mux := http.NewServeMux()
	limiter := newRateLimiter(cfg.RateLimit)

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("POST /api/rooms", func(w http.ResponseWriter, r *http.Request) {
		if !limiter.allow(clientIP(r)) {
			writeError(w, http.StatusTooManyRequests, "demasiadas salas creadas, intenta mas tarde")
			return
		}
		var req createRoomRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "json invalido")
			return
		}
		if req.Mode == "" {
			req.Mode = "Escape"
		}
		room, token, err := reg.Create(req.Name, req.Host, req.Map, req.Mode, req.Max)
		if err != nil {
			writeError(w, http.StatusConflict, err.Error())
			return
		}

		ready := false
		deadline := time.Now().Add(cfg.ReadyTimeout)
		for time.Now().Before(deadline) {
			if cur, ok := reg.Get(room.ID); ok && cur.Status == StatusReady {
				room = cur
				ready = true
				break
			}
			time.Sleep(150 * time.Millisecond)
		}
		if !ready {
			// No dejamos salas zombis: si no quedo lista, se cierra.
			reg.Delete(room.ID)
			writeError(w, http.StatusGatewayTimeout, "el servidor de la sala no respondio a tiempo")
			return
		}
		resp := roomToResponse(room, cfg)
		resp.Token = token
		writeJSON(w, http.StatusCreated, resp)
	})

	mux.HandleFunc("GET /api/rooms", func(w http.ResponseWriter, r *http.Request) {
		rooms := reg.List()
		out := make([]roomResponse, 0, len(rooms))
		for _, room := range rooms {
			out = append(out, roomToResponse(room, cfg))
		}
		writeJSON(w, http.StatusOK, out)
	})

	mux.HandleFunc("GET /api/rooms/{id}", func(w http.ResponseWriter, r *http.Request) {
		room, ok := reg.Get(r.PathValue("id"))
		if !ok {
			writeError(w, http.StatusNotFound, "sala no encontrada")
			return
		}
		writeJSON(w, http.StatusOK, roomToResponse(room, cfg))
	})

	mux.HandleFunc("DELETE /api/rooms/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		allowed, found := authorizeRoom(reg, cfg, id, r)
		if !found {
			writeError(w, http.StatusNotFound, "sala no encontrada")
			return
		}
		if !allowed {
			writeError(w, http.StatusForbidden, "token invalido")
			return
		}
		reg.Delete(id)
		writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
	})

	mux.HandleFunc("POST /api/rooms/{id}/heartbeat", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		allowed, found := authorizeRoom(reg, cfg, id, r)
		if !found {
			writeError(w, http.StatusNotFound, "sala no encontrada")
			return
		}
		if !allowed {
			writeError(w, http.StatusForbidden, "token invalido")
			return
		}
		var req heartbeatRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		if !reg.Heartbeat(id, req.Status, req.Players, req.Phase) {
			writeError(w, http.StatusNotFound, "sala no encontrada")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	return mux
}

// authorizeRoom valida que el request traiga el token de la sala o el token de
// administrador. Devuelve (autorizado, existe).
func authorizeRoom(reg *Registry, cfg Config, id string, r *http.Request) (bool, bool) {
	token, ok := reg.TokenFor(id)
	if !ok {
		return false, false
	}
	got := bearerToken(r)
	if cfg.AdminToken != "" && constEq(got, cfg.AdminToken) {
		return true, true
	}
	if token != "" && constEq(got, token) {
		return true, true
	}
	return false, true
}

func constEq(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if h == "" {
		return ""
	}
	if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return strings.TrimSpace(h)
}

func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if i := strings.IndexByte(fwd, ','); i >= 0 {
			return strings.TrimSpace(fwd[:i])
		}
		return strings.TrimSpace(fwd)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func roomToResponse(room Room, cfg Config) roomResponse {
	host := cfg.PublicHost
	if host == "" {
		host = "127.0.0.1"
	}
	return roomResponse{
		ID:      room.ID,
		Host:    host,
		Owner:   room.Host,
		Port:    room.Port,
		Status:  room.Status,
		Name:    room.Name,
		Map:     room.Map,
		Mode:    room.Mode,
		Max:     room.Max,
		Players: room.Players,
		Phase:   room.Phase,
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}
