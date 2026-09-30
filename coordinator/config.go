package main

import (
	"bufio"
	"flag"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Config contiene la configuracion del coordinador.
// Precedencia por campo: flag > env (COORD_*) > archivo de config > default.
type Config struct {
	Listen           string
	PublicHost       string
	PortBase         int
	MaxRooms         int
	DefaultMax       int
	HeartbeatTimeout time.Duration
	ReadyTimeout     time.Duration
	EmptyTimeout     time.Duration
	AdminToken       string
	RateLimit        int
	ServerBin        string
	ServerArgs       []string
	ServerCmd        string
	ConfigPath       string
}

func parseConfig() Config {
	var (
		listen     = flag.String("listen", "", "direccion de escucha HTTP (default :8080)")
		publicHost = flag.String("public-host", "", "host publico devuelto a los clientes")
		portBase   = flag.Int("port-base", 0, "puerto base para las salas")
		maxRooms   = flag.Int("max-rooms", 0, "maximo de salas simultaneas")
		defaultMax = flag.Int("default-max", 0, "maximo de jugadores por defecto")
		hb         = flag.Int("heartbeat-timeout", 0, "segundos sin heartbeat antes de matar una sala")
		rt         = flag.Int("ready-timeout", 0, "segundos maximos esperando el ready")
		emptyTO    = flag.Int("empty-timeout", 0, "segundos de sala vacia antes de cerrarla (0 desactiva)")
		adminToken = flag.String("admin-token", "", "token de administrador para borrar cualquier sala")
		rateLimit  = flag.Int("rate-limit", 0, "maximo de salas creadas por IP por minuto (0 desactiva)")
		serverBin  = flag.String("server-bin", "", "ruta al ejecutable del servidor dedicado")
		serverArgs = flag.String("server-args", "", "argumentos extra antes de '--' (ej: --path /proyecto)")
		serverCmd  = flag.String("server-cmd", "", "plantilla completa (avanzado); sobreescribe --server-bin")
		cfgPath    = flag.String("config", "", "ruta del archivo de config (default coordinator.cfg junto al binario)")
	)
	flag.Parse()

	path := *cfgPath
	if path == "" {
		path = defaultConfigPath()
	}
	fileVals := loadConfigFile(path)

	c := Config{
		Listen:     pickStr(*listen, "COORD_LISTEN", "listen", fileVals, ":8080"),
		PublicHost: pickStr(*publicHost, "COORD_PUBLIC_HOST", "public_host", fileVals, "127.0.0.1"),
		PortBase:   pickInt(*portBase, "COORD_PORT_BASE", "port_base", fileVals, 4300),
		MaxRooms:   pickInt(*maxRooms, "COORD_MAX_ROOMS", "max_rooms", fileVals, 32),
		DefaultMax: pickInt(*defaultMax, "COORD_DEFAULT_MAX", "default_max", fileVals, 10),
		ServerBin:  pickStr(*serverBin, "COORD_SERVER_BIN", "server_bin", fileVals, ""),
		ServerCmd:  pickStr(*serverCmd, "COORD_SERVER_CMD", "server_cmd", fileVals, ""),
		AdminToken: pickStr(*adminToken, "COORD_ADMIN_TOKEN", "admin_token", fileVals, ""),
		RateLimit:  pickInt(*rateLimit, "COORD_RATE_LIMIT", "rate_limit", fileVals, 30),
		ConfigPath: path,
	}
	c.HeartbeatTimeout = time.Duration(pickInt(*hb, "COORD_HEARTBEAT_TIMEOUT", "heartbeat_timeout", fileVals, 20)) * time.Second
	c.ReadyTimeout = time.Duration(pickInt(*rt, "COORD_READY_TIMEOUT", "ready_timeout", fileVals, 10)) * time.Second
	c.EmptyTimeout = time.Duration(pickInt(*emptyTO, "COORD_EMPTY_TIMEOUT", "empty_timeout", fileVals, 120)) * time.Second
	c.ServerArgs = splitCommand(pickStr(*serverArgs, "COORD_SERVER_ARGS", "server_args", fileVals, ""))

	if c.ServerBin == "" && c.ServerCmd == "" {
		c.ServerBin = detectServerBin()
	}
	return c
}

// CoordinatorURL es la URL que usa la instancia para hablar con el coordinador.
func (c Config) CoordinatorURL() string {
	listen := c.Listen
	if listen == "" {
		listen = ":8080"
	}
	if listen[0] == ':' {
		return "http://127.0.0.1" + listen
	}
	return "http://" + listen
}

func defaultConfigPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "coordinator.cfg"
	}
	return filepath.Join(filepath.Dir(exe), "coordinator.cfg")
}

// detectServerBin busca darker-server(.exe) junto al ejecutable del coordinador.
func detectServerBin() string {
	dir := "."
	if exe, err := os.Executable(); err == nil {
		dir = filepath.Dir(exe)
	}
	for _, name := range []string{"darker-server.exe", "darker-server"} {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func loadConfigFile(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		i := strings.Index(line, "=")
		if i <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:i])
		val := strings.TrimSpace(line[i+1:])
		out[key] = val
	}
	return out
}

func pickStr(flagVal, envKey, cfgKey string, fileVals map[string]string, def string) string {
	if flagVal != "" {
		return flagVal
	}
	if v := os.Getenv(envKey); v != "" {
		return v
	}
	if v := fileVals[cfgKey]; v != "" {
		return v
	}
	return def
}

func pickInt(flagVal int, envKey, cfgKey string, fileVals map[string]string, def int) int {
	if flagVal != 0 {
		return flagVal
	}
	if v := os.Getenv(envKey); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	if v := fileVals[cfgKey]; v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
