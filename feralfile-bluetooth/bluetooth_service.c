#include <gio/gio.h>
#include <glib.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "gatt-interfaces.h" // Include the generated header

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

static void on_characteristic_method_call(GattCharacteristic1 *interface,
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
        g_dbus_method_invocation_return_error(invocation,
                                              G_DBUS_ERROR,
                                              G_DBUS_ERROR_UNKNOWN_METHOD,
                                              "Unknown method: %s", method_name);
    }
}

static void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);
    pthread_exit(NULL);
}

int bluetooth_init() {
    GError *error = NULL;
    GDBusConnection *connection = NULL;
    GDBusProxy *gatt_manager = NULL;
    GattService1 *service_skeleton = NULL;
    GattCharacteristic1 *char_skeleton = NULL;
    GDBusObjectManagerServer *manager = NULL;
    GDBusObjectSkeleton *service_object = NULL;
    GDBusObjectSkeleton *char_object = NULL;
    gboolean success = FALSE;

    // Get D-Bus connection
    connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        g_clear_error(&error);
        goto cleanup;
    }

    // Set up GATT Manager
    gatt_manager = g_dbus_proxy_new_sync(connection,
                                        G_DBUS_PROXY_FLAGS_NONE,
                                        NULL,
                                        "org.bluez",
                                        "/org/bluez/hci0",
                                        "org.bluez.GattManager1",
                                        NULL,
                                        &error);
    if (!gatt_manager) {
        log_debug("[%s] Failed to get GattManager1: %s\n", LOG_TAG, error->message);
        g_clear_error(&error);
        goto cleanup;
    }

    // Create service skeleton with error checking
    service_skeleton = gatt_service1_skeleton_new();
    if (!service_skeleton) {
        log_debug("[%s] Failed to create service skeleton\n", LOG_TAG);
        goto cleanup;
    }

    // Create characteristic skeleton with error checking
    char_skeleton = gatt_characteristic1_skeleton_new();
    if (!char_skeleton) {
        log_debug("[%s] Failed to create characteristic skeleton\n", LOG_TAG);
        goto cleanup;
    }

    // Set up Object Manager
    manager = g_dbus_object_manager_server_new(FERALFILE_APP_PATH);
    if (!manager) {
        log_debug("[%s] Failed to create object manager\n", LOG_TAG);
        goto cleanup;
    }

    // Create and set up service object
    service_object = g_dbus_object_skeleton_new(FERALFILE_SERVICE_PATH);
    if (!service_object) {
        log_debug("[%s] Failed to create service object\n", LOG_TAG);
        goto cleanup;
    }

    // Create and set up characteristic object
    char_object = g_dbus_object_skeleton_new(FERALFILE_CHAR_PATH);
    if (!char_object) {
        log_debug("[%s] Failed to create characteristic object\n", LOG_TAG);
        goto cleanup;
    }

    // Set properties
    g_object_set(G_OBJECT(service_skeleton),
                 "uuid", FERALFILE_SERVICE_UUID,
                 "primary", TRUE,
                 NULL);

    g_object_set(G_OBJECT(char_skeleton),
                 "uuid", WIFI_CREDS_CHAR_UUID,
                 "service", FERALFILE_SERVICE_PATH,
                 "flags", g_variant_new_strv((const gchar*[]){"write-without-response", NULL}, -1),
                 NULL);

    // Connect signals and export objects
    g_signal_connect(char_skeleton, "handle-method-call", G_CALLBACK(on_characteristic_method_call), NULL);

    g_dbus_object_skeleton_add_interface(service_object, G_DBUS_INTERFACE_SKELETON(service_skeleton));
    g_dbus_object_skeleton_add_interface(char_object, G_DBUS_INTERFACE_SKELETON(char_skeleton));

    g_dbus_object_manager_server_export(manager, service_object);
    g_dbus_object_manager_server_export(manager, char_object);
    g_dbus_object_manager_server_set_connection(manager, connection);

    // Register application
    GVariant *result = g_dbus_proxy_call_sync(gatt_manager,
                                             "RegisterApplication",
                                             g_variant_new("(oa{sv})", FERALFILE_APP_PATH, NULL),
                                             G_DBUS_CALL_FLAGS_NONE,
                                             -1,
                                             NULL,
                                             &error);
    if (!result) {
        log_debug("[%s] Failed to register GATT application: %s\n", LOG_TAG, error->message);
        g_clear_error(&error);
        goto cleanup;
    }
    g_variant_unref(result);

    success = TRUE;
    log_debug("[%s] Bluetooth service initialized successfully\n", LOG_TAG);

cleanup:
    // Only clean up objects if initialization failed
    if (!success) {
        if (service_object) g_object_unref(service_object);
        if (char_object) g_object_unref(char_object);
        if (manager) g_object_unref(manager);
        if (service_skeleton) g_object_unref(service_skeleton);
        if (char_skeleton) g_object_unref(char_skeleton);
        if (gatt_manager) g_object_unref(gatt_manager);
        if (connection) g_object_unref(connection);
        return -1;
    }

    return 0;
}

void bluetooth_set_credentials_callback(wifi_credentials_callback callback) {
    credentials_callback = callback;
}

int bluetooth_start() {
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        log_debug("[%s] Failed to start Bluetooth thread\n", LOG_TAG);
        return -1;
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