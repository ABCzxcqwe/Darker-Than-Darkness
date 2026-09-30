package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os/exec"
	"sync"
	"time"
)

const (
	StatusStarting = "starting"
	StatusReady    = "ready"
	StatusStale    = "stale"
)

var (
	ErrMaxRooms  = errors.New("maximo de salas alcanzado")
	ErrNoCommand = errors.New("servidor no configurado (server-bin/server-cmd)")
)

// Room es el estado publico de una sala.
type Room struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Host      string    `json:"host"`
	Map       string    `json:"map"`
	Mode      string    `json:"mode"`
	Max       int       `json:"max"`
	Port      int       `json:"port"`
	Status    string    `json:"status"`
	Players   int       `json:"players"`
	Phase     string    `json:"phase"`
	CreatedAt time.Time `json:"created_at"`
	LastSeen  time.Time `json:"last_seen"`
}

type roomEntry struct {
	Room
	cmd        *exec.Cmd
	token      string
	emptySince time.Time
}

// Registry mantiene las salas activas y sus procesos.
type Registry struct {
	mu       sync.Mutex
	rooms    map[string]*roomEntry
	usedPort map[int]bool
	cfg      Config
	nextID   int
}

func NewRegistry(cfg Config) *Registry {
	return &Registry{
		rooms:    make(map[string]*roomEntry),
		usedPort: make(map[int]bool),
		cfg:      cfg,
	}
}

// Create reserva puerto, lanza la instancia y registra la sala. Devuelve
// tambien el token secreto de la sala, que solo el creador y la instancia
// conocen y que autoriza el heartbeat y el borrado.
func (r *Registry) Create(name, host, mapID, mode string, maxPlayers int) (Room, string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.cfg.ServerCmd == "" && r.cfg.ServerBin == "" {
		return Room{}, "", ErrNoCommand
	}
	if len(r.rooms) >= r.cfg.MaxRooms {
		return Room{}, "", ErrMaxRooms
	}
	if maxPlayers <= 0 {
		maxPlayers = r.cfg.DefaultMax
	}

	port := r.allocPort()
	r.nextID++
	id := fmt.Sprintf("r%d", r.nextID)
	token := newToken()

	repl := map[string]string{
		"port":        fmt.Sprintf("%d", port),
		"max":         fmt.Sprintf("%d", maxPlayers),
		"map":         mapID,
		"mode":        mode,
		"name":        name,
		"room_id":     id,
		"room_token":  token,
		"coordinator": r.cfg.CoordinatorURL(),
	}
	bin, args := r.buildSpawn(repl)
	if bin == "" {
		delete(r.usedPort, port)
		return Room{}, "", ErrNoCommand
	}

	now := time.Now()
	entry := &roomEntry{
		Room: Room{
			ID:        id,
			Name:      name,
			Host:      host,
			Map:       mapID,
			Mode:      mode,
			Max:       maxPlayers,
			Port:      port,
			Status:    StatusStarting,
			CreatedAt: now,
			LastSeen:  now,
		},
		token:      token,
		emptySince: now,
	}

	cmd, err := startProcess(bin, args)
	if err != nil {
		delete(r.usedPort, port)
		return Room{}, "", err
	}
	entry.cmd = cmd
	r.rooms[id] = entry

	go func() {
		cmd.Wait()
		r.removeIfExited(id, cmd)
	}()

	fmt.Printf("[coordinator] sala %s creada en puerto %d (max %d, mapa '%s')\n", id, port, maxPlayers, mapID)
	return entry.Room, token, nil
}

// TokenFor devuelve el token secreto de una sala (para autorizar requests).
func (r *Registry) TokenFor(id string) (string, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.rooms[id]
	if !ok {
		return "", false
	}
	return entry.token, true
}

func newToken() string {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

func (r *Registry) Get(id string) (Room, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.rooms[id]
	if !ok {
		return Room{}, false
	}
	return entry.Room, true
}

func (r *Registry) List() []Room {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]Room, 0, len(r.rooms))
	for _, entry := range r.rooms {
		out = append(out, entry.Room)
	}
	return out
}

func (r *Registry) Heartbeat(id, status string, players int, phase string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.rooms[id]
	if !ok {
		return false
	}
	if status != "" {
		entry.Status = status
	}
	entry.Players = players
	if phase != "" {
		entry.Phase = phase
	}
	entry.LastSeen = time.Now()
	// Registrar desde cuando la sala esta vacia para poder cerrarla por inactividad.
	if players > 0 {
		entry.emptySince = time.Time{}
	} else if entry.emptySince.IsZero() {
		entry.emptySince = time.Now()
	}
	return true
}

func (r *Registry) Delete(id string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.removeLocked(id, true)
}

func (r *Registry) removeIfExited(id string, cmd *exec.Cmd) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.rooms[id]
	if !ok || entry.cmd != cmd {
		return
	}
	delete(r.rooms, id)
	delete(r.usedPort, entry.Port)
	fmt.Printf("[coordinator] sala %s finalizada (proceso salio)\n", id)
}

func (r *Registry) removeLocked(id string, kill bool) bool {
	entry, ok := r.rooms[id]
	if !ok {
		return false
	}
	if kill && entry.cmd != nil && entry.cmd.Process != nil {
		entry.cmd.Process.Kill()
	}
	delete(r.rooms, id)
	delete(r.usedPort, entry.Port)
	return true
}

// buildSpawn arma el comando de la instancia. Usa la plantilla avanzada si
// esta configurada; si no, ServerBin + args estandar + placeholders.
func (r *Registry) buildSpawn(repl map[string]string) (string, []string) {
	if r.cfg.ServerCmd != "" {
		return buildCommand(r.cfg.ServerCmd, repl)
	}
	if r.cfg.ServerBin == "" {
		return "", nil
	}
	args := make([]string, 0, len(r.cfg.ServerArgs)+14)
	args = append(args, r.cfg.ServerArgs...)
	args = append(args,
		"--headless", "--",
		"--server",
		"--port="+repl["port"],
		"--max="+repl["max"],
		"--map="+repl["map"],
		"--mode="+repl["mode"],
		"--name="+repl["name"],
		"--room-id="+repl["room_id"],
		"--room-token="+repl["room_token"],
		"--coordinator="+repl["coordinator"],
	)
	return r.cfg.ServerBin, args
}

func (r *Registry) allocPort() int {
	for p := r.cfg.PortBase; ; p++ {
		if !r.usedPort[p] {
			r.usedPort[p] = true
			return p
		}
	}
}

// Reap limpia salas cuyo proceso murio o que dejaron de latir.
func (r *Registry) Reap() {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	for id, entry := range r.rooms {
		if entry.cmd != nil && entry.cmd.ProcessState != nil && entry.cmd.ProcessState.Exited() {
			r.removeLocked(id, false)
			continue
		}
		silent := now.Sub(entry.LastSeen)
		if silent > 2*r.cfg.HeartbeatTimeout {
			fmt.Printf("[coordinator] sala %s sin heartbeat (%s); cerrando\n", id, silent.Round(time.Second))
			r.removeLocked(id, true)
			continue
		}
		if silent > r.cfg.HeartbeatTimeout && entry.Status == StatusReady {
			entry.Status = StatusStale
		}
		// Cerrar salas que llevan demasiado tiempo sin jugadores (salvo starting,
		// que aun da margen al creador para conectarse).
		if r.cfg.EmptyTimeout > 0 && entry.Status != StatusStarting {
			if entry.Players > 0 {
				entry.emptySince = time.Time{}
			} else {
				if entry.emptySince.IsZero() {
					entry.emptySince = now
				}
				if idle := now.Sub(entry.emptySince); idle > r.cfg.EmptyTimeout {
					fmt.Printf("[coordinator] sala %s vacia por %s; cerrando\n", id, idle.Round(time.Second))
					r.removeLocked(id, true)
				}
			}
		}
	}
}

// Shutdown mata todos los procesos hijos.
func (r *Registry) Shutdown() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, entry := range r.rooms {
		if entry.cmd != nil && entry.cmd.Process != nil {
			entry.cmd.Process.Kill()
		}
	}
}
