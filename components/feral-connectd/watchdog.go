package main

import (
	"context"
	"log"
	"time"

	"github.com/coreos/go-systemd/v22/daemon"
)

// Watchdog handles systemd watchdog notifications
type Watchdog struct {
	interval time.Duration
	done     chan struct{}
}

// NewWatchdog creates a new watchdog with the given interval
func NewWatchdog(interval time.Duration) *Watchdog {
	return &Watchdog{
		interval: interval,
		done:     make(chan struct{}),
	}
}

// Start starts the watchdog process
func (w *Watchdog) Start(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	log.Println("Starting watchdog with interval:", w.interval)

	for {
		select {
		case <-ticker.C:
			log.Println("Watchdog check...")
			daemon.SdNotify(false, daemon.SdNotifyWatchdog)
		case <-ctx.Done():
			log.Println("Stopping watchdog due to context cancellation")
			return
		case <-w.done:
			log.Println("Stopping watchdog")
			return
		}
	}
}

// Stop stops the watchdog process
func (w *Watchdog) Stop() {
	select {
	case <-w.done:
		// Already closed
		return
	default:
		close(w.done)
	}
}
