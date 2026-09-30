package main

import (
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	cfg := parseConfig()
	if cfg.ServerCmd == "" && cfg.ServerBin == "" {
		fmt.Println("[coordinator] advertencia: sin servidor dedicado (server-bin/server-cmd); no se podran crear salas")
	}

	reg := NewRegistry(cfg)

	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			reg.Reap()
		}
	}()

	srv := &http.Server{Addr: cfg.Listen, Handler: NewHTTPHandler(reg, cfg)}

	go func() {
		fmt.Printf("[coordinator] escuchando en %s (public-host=%s, port-base=%d, max-rooms=%d)\n",
			cfg.Listen, cfg.PublicHost, cfg.PortBase, cfg.MaxRooms)
		fmt.Printf("[coordinator] server-bin=%s | config=%s\n", cfg.ServerBin, cfg.ConfigPath)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "[coordinator] error: %v\n", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	fmt.Println("[coordinator] apagando...")
	reg.Shutdown()
	os.Exit(0)
}
