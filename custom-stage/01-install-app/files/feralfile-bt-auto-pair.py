#!/usr/bin/env python3

import dbus
import dbus.exceptions
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BLUEZ_SERVICE_NAME = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_PATH = "/test/auto_agent"
ADAPTER_PATH = "/org/bluez/hci0"
CAPABILITY = "NoInputNoOutput"


def remove_device_if_exists(device_path):
    """
    Remove a bonded device if it exists. This ensures that
    if the device was previously bonded, we remove the old record
    before re-pairing.
    """
    bus = dbus.SystemBus()
    adapter = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, ADAPTER_PATH),
        "org.bluez.Adapter1",
    )
    try:
        adapter.RemoveDevice(device_path)
        print(f"[Agent] Removed existing bond for {device_path}")
    except dbus.exceptions.DBusException as e:
        # If it doesn't exist or can't be removed, just log and continue
        if "Does Not Exist" not in str(e):
            print(f"[Agent] Could not remove device {device_path}: {str(e)}")


class AutoPairAgent(dbus.service.Object):
    """
    A custom BlueZ agent that auto-accepts pairing ("Just Works"),
    removes old bonds automatically, and returns default passkeys
    when requested.
    """

    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self):
        print("[Agent] Release - called by BlueZ to deactivate agent")

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        """
        Called when a remote device (identified by device path)
        requests to connect to a service UUID.
        We simply authorize automatically.
        """
        print(f"[Agent] AuthorizeService ({device}, {uuid}) -> authorized")
        remove_device_if_exists(device)  # Ensure no old bond
        return

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def Cancel(self, device):
        """
        Called to cancel a previous request (e.g., pairing canceled by remote).
        """
        print(f"[Agent] Cancel pairing {device}")

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestPinCode(self, device):
        """
        Called when the service needs a PIN code (legacy devices).
        Return a default '0000' or any fixed code you prefer.
        """
        print(f"[Agent] RequestPinCode ({device}) -> '0000'")
        remove_device_if_exists(device)  # Ensure no old bond
        return "0000"

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestPasskey(self, device):
        """
        Called when the service needs a passkey (as a number).
        """
        print(f"[Agent] RequestPasskey ({device}) -> 0")
        remove_device_if_exists(device)  # Ensure no old bond
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        """
        Display a passkey to the user. For 'Just Works', often not used,
        but we implement to satisfy the Agent API.
        """
        print(f"[Agent] DisplayPasskey ({device}, passkey {passkey}, entered {entered})")

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestConfirmation(self, device, passkey):
        """
        Called for 'Just Works' or numeric comparison. We auto-accept,
        but also remove the device if previously bonded.
        """
        print(f"[Agent] RequestConfirmation ({device}, passkey {passkey}) -> confirmed")
        remove_device_if_exists(device)  # Ensure no old bond
        return


def disconnect_other_devices(current_path):
    """
    Disconnect any other devices that are currently connected,
    enforcing a "one device connected at a time" policy.
    """
    bus = dbus.SystemBus()
    manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, "/"),
        "org.freedesktop.DBus.ObjectManager"
    )

    objects = manager.GetManagedObjects()

    for obj_path, ifaces in objects.items():
        if "org.bluez.Device1" in ifaces and obj_path != current_path:
            dev_props = ifaces["org.bluez.Device1"]
            if dev_props.get("Connected", False):
                # This is another connected device - disconnect it
                dev_obj = bus.get_object(BLUEZ_SERVICE_NAME, obj_path)
                dev_methods = dbus.Interface(dev_obj, "org.bluez.Device1")
                try:
                    dev_methods.Disconnect()
                    print(f"[Agent] Disconnected previous device at {obj_path}")
                except Exception as e:
                    print(f"[Agent] Error disconnecting {obj_path}: {str(e)}")


def on_properties_changed(interface, changed, invalidated, path):
    """
    Callback to handle the PropertiesChanged signal for org.bluez.Device1.
    We use it to detect when a device connects so we can enforce only
    one connected device at a time.
    """
    if interface != "org.bluez.Device1":
        return

    if "Connected" in changed:
        connected = changed["Connected"]
        if connected:
            # A device just connected; disconnect any others
            print(f"[Agent] Device {path} connected")
            disconnect_other_devices(path)
        else:
            print(f"[Agent] Device {path} disconnected")


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    # Create our agent
    agent = AutoPairAgent(bus)

    # Register the agent with the BlueZ AgentManager
    agent_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, "/org/bluez"),
        "org.bluez.AgentManager1"
    )

    try:
        agent_manager.RegisterAgent(AGENT_PATH, CAPABILITY)
        print(f"[Agent] Registered agent on {AGENT_PATH} with capability '{CAPABILITY}'")

        agent_manager.RequestDefaultAgent(AGENT_PATH)
        print("[Agent] Set this agent as the default.")
    except dbus.exceptions.DBusException as e:
        print(f"[Agent] Failed to register agent: {str(e)}")
        return

    # Listen for PropertiesChanged signals on Device1 to handle connection events
    bus.add_signal_receiver(
        on_properties_changed,
        bus_name=BLUEZ_SERVICE_NAME,
        dbus_interface="org.freedesktop.DBus.Properties",
        signal_name="PropertiesChanged",
        path_keyword="path",
    )

    loop = GLib.MainLoop()
    print("[Agent] Agent running. Waiting for connections/pairing...")
    loop.run()


if __name__ == "__main__":
    main()