.PHONY: sync
sync:
	@echo "📡 Syncing to X4..."
	@./scripts/sync-to-x4.sh . /home/feralfile/$(notdir $(PWD))

.PHONY: fresh-debug
fresh-debug:
	@echo "🔍 Running fresh debug build..."
	@./scripts/fresh-debug.sh

.PHONY: resume-debug
resume-debug:
	@echo "🔍 Running resume debug build..."
	@./scripts/resume-debug.sh

.PHONY: fresh-release
fresh-release:
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

