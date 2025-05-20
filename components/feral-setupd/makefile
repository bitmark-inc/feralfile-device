.PHONY: sync
sync:
	@echo "📡 Syncing to X4..."
	@./scripts/sync-to-x4.sh . /home/feralfile/$(notdir $(PWD))

.PHONY: sync-connectd
sync-connectd:
	@echo "📡 Syncing connectd..."
	@./scripts/sync-to-x4.sh ../feral-connectd /home/feralfile/feral-connectd

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

