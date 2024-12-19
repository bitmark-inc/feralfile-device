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
static pthread_t bluetooth_thread;

#define FERALFILE_SERVICE_NAME    "FeralFile Connection"
#define FERALFILE_SERVICE_UUID    "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define WIFI_CREDS_CHAR_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

#define FERALFILE_SERVICE_PATH    "/com/feralfile/device/service0"
#define FERALFILE_CHAR_PATH      "/com/feralfile/device/service0/wifi_config"
#define FERALFILE_ADV_PATH       "/com/feralfile/device/advertisement0"

// Callback type for handling received WiFi credentials
typedef void (*wifi_credentials_callback)(const char* ssid, const char* password);
static wifi_credentials_callback credentials_callback = NULL;

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

// Introspection XML for GATT Service and Characteristic
static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.GattService1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Primary' type='b' access='read'/>"
    "  </interface>"
    "  <interface name='org.bluez.GattCharacteristic1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Service' type='o' access='read'/>"
    "    <property name='Flags' type='as' access='read'/>"
    "    <method name='WriteValue'>"
    "      <arg name='value' type='ay' direction='in'/>"
    "      <arg name='options' type='a{sv}' direction='in'/>"
    "    </method>"
    "  </interface>"
    "</node>";

// Advertisement introspection XML
static const gchar advertisement_xml[] =
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
    log_debug("[%s] Received WiFi credentials. Length: %zu\n", LOG_TAG, value_len);

    // Expect format: "SSID\nPASSWORD"
    char buffer[256] = {0};
    memcpy(buffer, value, value_len < sizeof(buffer) ? value_len : sizeof(buffer) - 1);

    char *ssid = buffer;
    char *password = strchr(buffer, '\n');
    
    if (password != NULL) {
        *password = '\0';  // Split the string
        password++;        // Move to start of password
        
        log_debug("[%s] Parsed SSID: %s\n", LOG_TAG, ssid);
        // Don't log the actual password in production
        
        if (credentials_callback) {
            credentials_callback(ssid, password);
        }
    } else {
        log_debug("[%s] Invalid credential format\n", LOG_TAG);
    }
}

// GATT Property Handler
static GVariant* handle_get_property(GDBusConnection *connection,
                                   const gchar *sender,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *property_name,
                                   GError **error,
                                   gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattService1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0)
            return g_variant_new_string(FERALFILE_SERVICE_UUID);
        if (g_strcmp0(property_name, "Primary") == 0)
            return g_variant_new_boolean(TRUE);
    } else if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0)
            return g_variant_new_string(WIFI_CREDS_CHAR_UUID);
        if (g_strcmp0(property_name, "Service") == 0)
            return g_variant_new_object_path(FERALFILE_SERVICE_PATH);
        if (g_strcmp0(property_name, "Flags") == 0) {
            const gchar *flags[] = {
                "write-without-response",
                NULL
            };
            return g_variant_new_strv(flags, -1);
        }
    }
    return NULL;
}

static void handle_method_call(GDBusConnection *connection,
                             const gchar *sender,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *method_name,
                             GVariant *parameters,
                             GDBusMethodInvocation *invocation,
                             gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(method_name, "WriteValue") == 0) {
            GVariant *value_variant = NULL;
            GVariant *options = NULL;
            g_variant_get(parameters, "(@ay@a{sv})", &value_variant, &options);

            gsize value_len;
            const guchar *value = g_variant_get_fixed_array(value_variant, &value_len, 1);
            
            handle_write_value(value, value_len);

            g_dbus_method_invocation_return_value(invocation, NULL);
            
            if (value_variant)
                g_variant_unref(value_variant);
            if (options)
                g_variant_unref(options);
        }
    }
}

// VTable for the GATT Characteristic
static const GDBusInterfaceVTable gatt_interface_vtable = {
    .method_call = handle_method_call,
    .get_property = handle_get_property,
    .set_property = NULL,
};

// VTable for BLE Advertisement
static GVariant* advertisement_get_property(GDBusConnection *connection,
                                          const gchar *sender,
                                          const gchar *object_path,
                                          const gchar *interface_name,
                                          const gchar *property_name,
                                          GError **error,
                                          gpointer user_data) {
    if (g_strcmp0(property_name, "Type") == 0)
        return g_variant_new_string("peripheral");
    if (g_strcmp0(property_name, "ServiceUUIDs") == 0)
        return g_variant_new_strv((const gchar*[]){FERALFILE_SERVICE_UUID, NULL}, -1);
    if (g_strcmp0(property_name, "LocalName") == 0)
        return g_variant_new_string(FERALFILE_SERVICE_NAME);
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
    GError *error = NULL;

    // Connect to system bus
    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        return -1;
    }

    // Set Bluetooth adapter properties for security
    GDBusProxy *adapter = g_dbus_proxy_new_sync(connection,
                                               G_DBUS_PROXY_FLAGS_NONE,
                                               NULL,
                                               "org.bluez",
                                               "/org/bluez/hci0",
                                               "org.bluez.Adapter1",
                                               NULL,
                                               &error);
    if (adapter) {
        // Enable Pairable and set Pairing Mode
        g_dbus_proxy_call_sync(adapter,
                              "SetProperty",
                              g_variant_new("(sv)", "Pairable", g_variant_new_boolean(TRUE)),
                              G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
        
        g_dbus_proxy_call_sync(adapter,
                              "SetProperty",
                              g_variant_new("(sv)", "PairableTimeout", g_variant_new_uint32(0)),
                              G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
    }

    // Register GATT Service and Characteristic
    introspection_data = g_dbus_node_info_new_for_xml(introspection_xml, &error);
    g_dbus_connection_register_object(connection,
                                    FERALFILE_SERVICE_PATH,
                                    introspection_data->interfaces[0],
                                    &gatt_interface_vtable,
                                    NULL, NULL, &error);
    g_dbus_connection_register_object(connection,
                                    FERALFILE_CHAR_PATH,
                                    introspection_data->interfaces[1],
                                    &gatt_interface_vtable,
                                    NULL, NULL, &error);

    // Register BLE Advertisement
    advertisement_introspection_data = g_dbus_node_info_new_for_xml(advertisement_xml, &error);
    g_dbus_connection_register_object(connection,
                                    FERALFILE_ADV_PATH,
                                    advertisement_introspection_data->interfaces[0],
                                    &advertisement_vtable,
                                    NULL, NULL, &error);

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
                          g_variant_new("(oa{sv})", FERALFILE_ADV_PATH, NULL),
                          G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);

    log_debug("[%s] Bluetooth service initialized successfully\n", LOG_TAG);
    return 0;
}

void bluetooth_set_credentials_callback(wifi_credentials_callback callback) {
    credentials_callback = callback;
}

int bluetooth_start(connection_result_callback callback) {
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        log_debug("[%s] Failed to start Bluetooth thread\n", LOG_TAG);
        if (callback) {
            callback(-1, "Failed to start Bluetooth thread");
        }
        return -1;
    }
    
    if (callback) {
        callback(0, "Bluetooth service started successfully");
    }
    return 0;
}

void bluetooth_stop() {
    if (main_loop) {
        g_main_loop_quit(main_loop);
    }
    pthread_join(bluetooth_thread, NULL);
    log_debug("[%s] Bluetooth service stopped\n", LOG_TAG);
}