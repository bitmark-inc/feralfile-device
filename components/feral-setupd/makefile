.PHONY: sync
sync:
	@echo "📡 Syncing to X4..."
	@./scripts/sync-to-x4.sh . /home/feralfile/$(notdir $(PWD))

.PHONY: sync-connectd
sync-connectd:
	@echo "📡 Syncing connectd..."
	@./scripts/sync-to-x4.sh ../feral-connectd /home/feralfile/feral-connectd

.PHONY: sync-sys-monitord
sync-sys-monitord:
	@echo "📡 Syncing sys-monitord..."
	@./scripts/sync-to-x4.sh ../feral-sys-monitord /home/feralfile/feral-sys-monitord

.PHONY: sync-launcher-ui
sync-launcher-ui:
	@echo "📡 Syncing launcher-ui..."
	@./scripts/sync-to-x4.sh ../launcher-ui /opt/feral/ui/launcher/

.PHONY: fresh-debug
fresh-debug: restart-bluetooth
	@echo "🔍 Running fresh debug build..."
	@./scripts/fresh-debug.sh

.PHONY: resume-debug
resume-debug: restart-bluetooth
	@echo "🔍 Running resume debug build..."
	@./scripts/resume-debug.sh

.PHONY: fresh-release
fresh-release: restart-bluetooth
	@echo "🔍 Running fresh release build..."
	@./scripts/fresh-release.sh

.PHONY: resume-release
resume-release:
	@echo "🔍 Running resume release build..."
	@./scripts/resume-release.sh

.PHONY: restart-bluetooth
restart-bluetooth:
	@echo "🔄 Restarting bluetooth service..."
	@./scripts/restart-bluetooth.sh

# ───────────────────────────────────────────────────────────────────────────────
# Paths
ROOT             := /home/feralfile
CONNECTD_DIR     := $(ROOT)/feral-connectd
SETUPD_DIR       := $(ROOT)/feral-setupd
MONITORD_DIR     := $(ROOT)/feral-sys-monitord
LOGDIR           := $(CURDIR)/logs

# ───────────────────────────────────────────────────────────────────────────────
.PHONY: start-silent stop-silent

start-silent:
	@mkdir -p $(LOGDIR)

	@echo "Building & starting feral-sys-monitord…"
	@cd $(MONITORD_DIR) && go build
	@nohup $(MONITORD_DIR)/feral-sys-monitord \
	    >>$(LOGDIR)/feral-sys-monitord.log 2>&1 & \
	    echo "  ↳ PID $$!"

	@echo "Building & starting feral-connectd…"
	@cd $(CONNECTD_DIR) && go build
	@nohup $(CONNECTD_DIR)/feral-connectd \
	    >>$(LOGDIR)/feral-connectd.log 2>&1 & \
	    echo "  ↳ PID $$!"

	@echo "Building & starting feral-setupd…"
	@sleep 2
	@cd $(SETUPD_DIR) && cargo build --quiet
	@nohup $(SETUPD_DIR)/target/debug/feral-setupd \
	    >>$(LOGDIR)/feral-setupd.log 2>&1 & \
	    echo "  ↳ PID $$!"

stop-silent:
	@echo "Stopping all feral-* processes…"
	@pkill -f '^feral-' || true
	@echo "Done."