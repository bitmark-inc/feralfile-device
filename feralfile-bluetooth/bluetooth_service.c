// bluetooth_service.c
#include <gio/gio.h>
#include <glib.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "gatt-interfaces.h" // Include the generated header from gdbus-codegen

#define LOG_TAG "BluetoothService"

static GMainLoop *main_loop = NULL;
static pthread_t bluetooth_thread;

#define FERALFILE_SERVICE_NAME    "FeralFile Connection"
#define FERALFILE_SERVICE_UUID    "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define WIFI_CREDS_CHAR_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

#define FERALFILE_APP_PATH        "/com/feralfile/device"
#define FERALFILE_SERVICE_PATH    "/com/feralfile/device/service0"
#define FERALFILE_CHAR_PATH       "/com/feralfile/device/service0/wifi_config"

typedef void (*wifi_credentials_callback)(const char* ssid, const char* password);
static wifi_credentials_callback credentials_callback = NULL;

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

static void handle_write_value(const guchar *value, gsize value_len) {
    log_debug("[%s] Received WiFi credentials. Length: %zu\n", LOG_TAG, value_len);
    char buffer[256] = {0};
    memcpy(buffer, value, value_len < sizeof(buffer) ? value_len : sizeof(buffer) - 1);

    char *ssid = buffer;
    char *password = strchr(buffer, '\n');
    
    if (password != NULL) {
        *password = '\0';
        password++;
        log_debug("[%s] Parsed SSID: %s\n", LOG_TAG, ssid);
        if (credentials_callback) {
            credentials_callback(ssid, password);
        }
    } else {
        log_debug("[%s] Invalid credential format\n", LOG_TAG);
    }
}

static void on_char_method_call(OrgBluezGattCharacteristic1 *interface,
                                GDBusMethodInvocation *invocation,
                                const gchar *method_name,
                                GVariant *parameters,
                                gpointer user_data) {
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
    } else {
        g_dbus_method_invocation_return_derror(invocation,
                                               "org.bluez.Error.NotSupported",
                                               "Method not supported");
    }
}

static void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);
    pthread_exit(NULL);
}

int bluetooth_init() {
    GError *error = NULL;

    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        return -1;
    }

    GDBusProxy *adapter = g_dbus_proxy_new_sync(connection,
                                                G_DBUS_PROXY_FLAGS_NONE,
                                                NULL,
                                                "org.bluez",
                                                "/org/bluez/hci0",
                                                "org.bluez.Adapter1",
                                                NULL,
                                                &error);
    if (adapter) {
        g_dbus_proxy_call_sync(adapter,
                               "SetProperty",
                               g_variant_new("(sv)", "Pairable", g_variant_new_boolean(TRUE)),
                               G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
        
        g_dbus_proxy_call_sync(adapter,
                               "SetProperty",
                               g_variant_new("(sv)", "PairableTimeout", g_variant_new_uint32(0)),
                               G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
    }

    // Create an ObjectManager for the application
    GDBusObjectManagerServer *manager = g_dbus_object_manager_server_new(FERALFILE_APP_PATH);

    // Create and set up the GATT service skeleton
    OrgBluezGattService1 *service_iface = org_bluez_gatt_service1_skeleton_new();
    g_object_set(G_OBJECT(service_iface),
                 "uuid", FERALFILE_SERVICE_UUID,
                 "primary", TRUE,
                 NULL);

    // Create and set up the GATT characteristic skeleton
    OrgBluezGattCharacteristic1 *char_iface = org_bluez_gatt_characteristic1_skeleton_new();
    g_object_set(G_OBJECT(char_iface),
                 "uuid", WIFI_CREDS_CHAR_UUID,
                 "service", FERALFILE_SERVICE_PATH,
                 "flags", g_variant_new_strv((const gchar*[]){"write-without-response", NULL}, -1),
                 NULL);

    // Connect signal for method calls on the characteristic
    g_signal_connect(char_iface, "handle-method-call", G_CALLBACK(on_char_method_call), NULL);

    // Create object skeletons
    GDBusObjectSkeleton *service_object = g_dbus_object_skeleton_new(FERALFILE_SERVICE_PATH);
    g_dbus_object_skeleton_add_interface(service_object, G_DBUS_INTERFACE_SKELETON(service_iface));

    GDBusObjectSkeleton *char_object = g_dbus_object_skeleton_new(FERALFILE_CHAR_PATH);
    g_dbus_object_skeleton_add_interface(char_object, G_DBUS_INTERFACE_SKELETON(char_iface));

    // Export objects on the manager
    g_dbus_object_manager_server_export(manager, service_object);
    g_dbus_object_manager_server_export(manager, char_object);
    g_dbus_object_manager_server_set_connection(manager, connection);

    // Register Application with GattManager1
    GDBusProxy *gatt_manager = g_dbus_proxy_new_sync(connection,
                                                     G_DBUS_PROXY_FLAGS_NONE,
                                                     NULL,
                                                     "org.bluez",
                                                     "/org/bluez/hci0",
                                                     "org.bluez.GattManager1",
                                                     NULL,
                                                     &error);
    if (!gatt_manager) {
        log_debug("[%s] Failed to get GattManager1: %s\n", LOG_TAG, error->message);
        return -1;
    }

    GVariant *res = g_dbus_proxy_call_sync(gatt_manager,
                                           "RegisterApplication",
                                           g_variant_new("(oa{sv})", FERALFILE_APP_PATH, NULL),
                                           G_DBUS_CALL_FLAGS_NONE,
                                           -1,
                                           NULL,
                                           &error);
    if (!res) {
        log_debug("[%s] Failed to register GATT application: %s\n", LOG_TAG, error->message);
        return -1;
    }
    g_variant_unref(res);

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