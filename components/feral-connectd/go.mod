module github.com/Feral-File/feralfile-device/components/feral-connectd

go 1.23.5

require github.com/gorilla/websocket v1.5.3

require (
	github.com/cenkalti/backoff/v4 v4.3.0
	github.com/coreos/go-systemd/v22 v22.5.0
	github.com/feral-file/godbus v0.0.1
	github.com/godbus/dbus/v5 v5.1.0
	github.com/natefinch/lumberjack v2.0.0+incompatible
	go.uber.org/zap v1.27.0
)

require (
	github.com/BurntSushi/toml v1.5.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)
