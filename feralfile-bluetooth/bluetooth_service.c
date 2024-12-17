// bluetooth_service.c
#include "bluetooth_service.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <glib.h>
#include <gio/gio.h>
#include <pthread.h>
#include <syslog.h>
#include <errno.h>
#include <stdarg.h>

#define LOG_TAG "BluetoothService"

static GMainLoop *main_loop = NULL;
static GDBusNodeInfo *introspection_data = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;
static guint registration_id;
static guint char_registration_id;
static connection_result_callback result_callback = NULL;
static pthread_t bluetooth_thread;

#define FERALFILE_SERVICE_NAME   "FeralFile Connection"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_WIFI_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

// GATT Service/Characteristic introspection XML
static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.GattService1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Primary' type='b' access='read'/>"
    "  </interface>"
    "  <interface name='org.bluez.GattCharacteristic1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Service' type='o' access='read'/>"
    "    <method name='WriteValue'>"
    "      <arg name='value' type='ay' direction='in'/>"
    "      <arg name='options' type='a{sv}' direction='in'/>"
    "    </method>"
    "  </interface>"
    "</node>";

// Advertisement introspection XML
static const gchar advertisement_introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.LEAdvertisement1'>"
    "    <method name='Release'/>"
    "    <property name='Type' type='s' access='read'/>"
    "    <property name='ServiceUUIDs' type='as' access='read'/>"
    "    <property name='LocalName' type='s' access='read'/>"
    "  </interface>"
    "</node>";

// Handle incoming write values
static void handle_write_value(const guchar *value, gsize value_len) {
    log_debug("[%s] Received value of length %zu\n", LOG_TAG, value_len);

    char buffer[256] = {0};
    memcpy(buffer, value, value_len < sizeof(buffer) ? value_len : sizeof(buffer) - 1);
    log_debug("[%s] Received: %s\n", LOG_TAG, buffer);
}

// GATT property handler
static GVariant* handle_get_property(GDBusConnection *connection,
                                     const gchar *sender,
                                     const gchar *object_path,
                                     const gchar *interface_name,
                                     const gchar *property_name,
                                     GError **error,
                                     gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattService1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) return g_variant_new_string(FERALFILE_SERVICE_UUID);
        if (g_strcmp0(property_name, "Primary") == 0) return g_variant_new_boolean(TRUE);
    }
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) return g_variant_new_string(FERALFILE_WIFI_CHAR_UUID);
        if (g_strcmp0(property_name, "Service") == 0) return g_variant_new_object_path("/org/bluez/example/service0");
    }
    return NULL;
}

static const GDBusInterfaceVTable interface_vtable = {
    .method_call = NULL,  // Implement if needed
    .get_property = handle_get_property,
    .set_property = NULL
};

// BLE Advertisement property handler
static GVariant* advertisement_get_property(GDBusConnection *connection,
                                            const gchar *sender,
                                            const gchar *object_path,
                                            const gchar *interface_name,
                                            const gchar *property_name,
                                            GError **error,
                                            gpointer user_data) {
    if (g_strcmp0(property_name, "Type") == 0) return g_variant_new_string("peripheral");
    if (g_strcmp0(property_name, "ServiceUUIDs") == 0) {
        return g_variant_new_strv((const gchar*[]){FERALFILE_SERVICE_UUID, NULL}, -1);
    }
    if (g_strcmp0(property_name, "LocalName") == 0) return g_variant_new_string(FERALFILE_SERVICE_NAME);
    return NULL;
}

static const GDBusInterfaceVTable advertisement_vtable = {
    .method_call = NULL,
    .get_property = advertisement_get_property,
    .set_property = NULL,
};

void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);
    pthread_exit(NULL);
}

int bluetooth_init() {
    log_debug("[%s] Initializing Bluetooth\n", LOG_TAG);
    GError *error = NULL;

    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Register GATT service
    introspection_data = g_dbus_node_info_new_for_xml(introspection_xml, &error);
    registration_id = g_dbus_connection_register_object(connection,
                                                        "/org/bluez/example/service0",
                                                        introspection_data->interfaces[0],
                                                        &interface_vtable, NULL, NULL, &error);

    // Register advertisement
    advertisement_introspection_data = g_dbus_node_info_new_for_xml(advertisement_introspection_xml, &error);
    g_dbus_connection_register_object(connection,
                                      "/org/bluez/example/advertisement0",
                                      advertisement_introspection_data->interfaces[0],
                                      &advertisement_vtable, NULL, NULL, &error);

    // Use LEAdvertisingManager to register advertisement
    GDBusProxy *advertising_manager = g_dbus_proxy_new_sync(connection,
                                                            G_DBUS_PROXY_FLAGS_NONE,
                                                            NULL,
                                                            "org.bluez",
                                                            "/org/bluez/hci0",
                                                            "org.bluez.LEAdvertisingManager1",
                                                            NULL,
                                                            &error);

    g_dbus_proxy_call_sync(advertising_manager,
                           "RegisterAdvertisement",
                           g_variant_new("(oa{sv})", "/org/bluez/example/advertisement0", NULL),
                           G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);

    if (error) {
        log_debug("[%s] Advertisement registration failed: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    log_debug("[%s] Bluetooth initialized successfully\n", LOG_TAG);
    return 0;
}

int bluetooth_start(connection_result_callback callback) {
    result_callback = callback;
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        log_debug("[%s] Failed to start Bluetooth thread\n", LOG_TAG);
        return -1;
    }
    log_debug("[%s] Bluetooth service started\n", LOG_TAG);
    return 0;
}

void bluetooth_stop() {
    if (main_loop) {
        g_main_loop_quit(main_loop);
    }
    pthread_cancel(bluetooth_thread);
    pthread_join(bluetooth_thread, NULL);
    log_debug("[%s] Bluetooth service stopped\n", LOG_TAG);
}