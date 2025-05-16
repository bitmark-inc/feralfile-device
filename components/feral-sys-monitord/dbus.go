package main

import "github.com/feral-file/godbus"

const (
	DBUS_INTERFACE godbus.Interface = "com.feralfile.sysmonitord"
	DBUS_PATH      godbus.Path      = "/com/feralfile/sysmonitord"

	DBUS_EVENT_SYSMETRICS godbus.Member = "sysmetrics"
)
