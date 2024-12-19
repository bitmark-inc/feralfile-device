// bluetooth_service.c
#include <gio/gio.h>
#include <glib.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#define LOG_TAG "BluetoothService"

static GMainLoop *main_loop = NULL;
static pthread_t bluetooth_thread;

#define FERALFILE_SERVICE_NAME    "FeralFile Connection"
#define FERALFILE_SERVICE_UUID    "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define WIFI_CREDS_CHAR_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

#define FERALFILE_APP_PATH        "/com/feralfile/device"
#define FERALFILE_SERVICE_PATH    "/com/feralfile/device/service0"
#define FERALFILE_CHAR_PATH       "/com/feralfile/device/service0/wifi_config"
#define FERALFILE_ADV_PATH        "/com/feralfile/device/advertisement0"

typedef void (*wifi_credentials_callback)(const char* ssid, const char* password);
static wifi_credentials_callback credentials_callback = NULL;

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

/* Introspection data for the GATT service and characteristic */
static const gchar service_introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.GattService1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Primary' type='b' access='read'/>"
    "  </interface>"
    "</node>";

static const gchar char_introspection_xml[] =
    "<node>"
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

static const gchar advertisement_xml[] =
    "<node>"
    "  <interface name='org.bluez.LEAdvertisement1'>"
    "    <method name='Release'/>"
    "    <property name='Type' type='s' access='read'/>"
    "    <property name='ServiceUUIDs' type='as' access='read'/>"
    "    <property name='LocalName' type='s' access='read'/>"
    "  </interface>"
    "</node>";

/* Global references */
static GDBusObjectManagerServer *manager = NULL;

/* Forward declarations */
static GVariant* handle_service_get_property(GDBusConnection *connection,
                                             const gchar *sender,
                                             const gchar *object_path,
                                             const gchar *interface_name,
                                             const gchar *property_name,
                                             GError **error,
                                             gpointer user_data);

static GVariant* handle_char_get_property(GDBusConnection *connection,
                                          const gchar *sender,
                                          const gchar *object_path,
                                          const gchar *interface_name,
                                          const gchar *property_name,
                                          GError **error,
                                          gpointer user_data);

static void handle_write_value(const guchar *value, gsize value_len);

static void handle_char_method_call(GDBusConnection *connection,
                                    const gchar *sender,
                                    const gchar *object_path,
                                    const gchar *interface_name,
                                    const gchar *method_name,
                                    GVariant *parameters,
                                    GDBusMethodInvocation *invocation,
                                    gpointer user_data);

static const GDBusInterfaceVTable service_interface_vtable = {
    .method_call = NULL,
    .get_property = handle_service_get_property,
    .set_property = NULL,
};

static const GDBusInterfaceVTable char_interface_vtable = {
    .method_call = handle_char_method_call,
    .get_property = handle_char_get_property,
    .set_property = NULL,
};

static GDBusNodeInfo *service_introspection_data = NULL;
static GDBusNodeInfo *char_introspection_data = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;

static GVariant* handle_service_get_property(GDBusConnection *connection,
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
    }
    return NULL;
}

static GVariant* handle_char_get_property(GDBusConnection *connection,
                                          const gchar *sender,
                                          const gchar *object_path,
                                          const gchar *interface_name,
                                          const gchar *property_name,
                                          GError **error,
                                          gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0)
            return g_variant_new_string(WIFI_CREDS_CHAR_UUID);
        if (g_strcmp0(property_name, "Service") == 0)
            return g_variant_new_object_path(FERALFILE_SERVICE_PATH);
        if (g_strcmp0(property_name, "Flags") == 0) {
            const gchar *flags[] = {"write-without-response", NULL};
            return g_variant_new_strv(flags, -1);
        }
    }
    return NULL;
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
        // Do not log the password in production
        if (credentials_callback) {
            credentials_callback(ssid, password);
        }
    } else {
        log_debug("[%s] Invalid credential format\n", LOG_TAG);
    }
}

static void handle_char_method_call(GDBusConnection *connection,
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

/* Advertisement handlers */
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

static void* bluetooth_handler(void* arg) {
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

    // Configure adapter
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

    // Create an ObjectManager to hold our application
    manager = g_dbus_object_manager_server_new(FERALFILE_APP_PATH);

    // Parse introspection for service
    service_introspection_data = g_dbus_node_info_new_for_xml(service_introspection_xml, &error);
    if (!service_introspection_data) {
        log_debug("[%s] Failed to parse service introspection: %s\n", LOG_TAG, error->message);
        return -1;
    }

    // Parse introspection for characteristic
    char_introspection_data = g_dbus_node_info_new_for_xml(char_introspection_xml, &error);
    if (!char_introspection_data) {
        log_debug("[%s] Failed to parse char introspection: %s\n", LOG_TAG, error->message);
        return -1;
    }

    // Create objects for service and characteristic
    GDBusObjectSkeleton *service_object = g_dbus_object_skeleton_new(FERALFILE_SERVICE_PATH);
    GDBusInterfaceSkeleton *service_iface = g_dbus_interface_skeleton_new(service_introspection_data->interfaces[0]);
    g_dbus_interface_skeleton_export(service_iface, connection, FERALFILE_SERVICE_PATH, &error);
    g_dbus_object_skeleton_add_interface(service_object, service_iface);

    GDBusObjectSkeleton *char_object = g_dbus_object_skeleton_new(FERALFILE_CHAR_PATH);
    GDBusInterfaceSkeleton *char_iface = g_dbus_interface_skeleton_new(char_introspection_data->interfaces[0]);
    g_dbus_interface_skeleton_export(char_iface, connection, FERALFILE_CHAR_PATH, &error);
    g_dbus_object_skeleton_add_interface(char_object, char_iface);

    // Set interface vtables
    g_dbus_connection_register_object(connection,
                                      FERALFILE_SERVICE_PATH,
                                      service_introspection_data->interfaces[0],
                                      &service_interface_vtable,
                                      NULL, NULL, &error);

    g_dbus_connection_register_object(connection,
                                      FERALFILE_CHAR_PATH,
                                      char_introspection_data->interfaces[0],
                                      &char_interface_vtable,
                                      NULL, NULL, &error);

    // Add objects to manager
    g_dbus_object_manager_server_export(manager, G_DBusObjectSkeleton * (service_object));
    g_dbus_object_manager_server_export(manager, G_DBusObjectSkeleton * (char_object));
    g_dbus_object_manager_server_set_connection(manager, connection);

    // Register GATT application
    GDBusProxy *gatt_manager = g_dbus_proxy_new_sync(connection,
                                                     G_DBUS_PROXY_FLAGS_NONE,
                                                     NULL,
                                                     "org.bluez",
                                                     "/org/bluez/hci0",
                                                     "org.bluez.GattManager1",
                                                     NULL,
                                                     &error);
    if (!gatt_manager) {
        log_debug("[%s] Failed to get GattManager1: %s\n", LOG_TAG, error ? error->message : "Unknown");
        return -1;
    }

    GVariant *result = g_dbus_proxy_call_sync(gatt_manager,
                                              "RegisterApplication",
                                              g_variant_new("(oa{sv})", FERALFILE_APP_PATH, NULL),
                                              G_DBUS_CALL_FLAGS_NONE,
                                              -1,
                                              NULL,
                                              &error);
    if (!result) {
        log_debug("[%s] Failed to register GATT application: %s\n", LOG_TAG, error->message);
        return -1;
    }
    g_variant_unref(result);

    // Register advertisement
    advertisement_introspection_data = g_dbus_node_info_new_for_xml(advertisement_xml, &error);
    if (!advertisement_introspection_data) {
        log_debug("[%s] Failed to parse advertisement introspection: %s\n", LOG_TAG, error->message);
        return -1;
    }

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
    if (!advertising_manager) {
        log_debug("[%s] Failed to get LEAdvertisingManager1: %s\n", LOG_TAG, error ? error->message : "Unknown");
        return -1;
    }

    result = g_dbus_proxy_call_sync(advertising_manager,
                                    "RegisterAdvertisement",
                                    g_variant_new("(oa{sv})", FERALFILE_ADV_PATH, NULL),
                                    G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    if (!result) {
        log_debug("[%s] Failed to register advertisement: %s\n", LOG_TAG, error->message);
        return -1;
    }
    g_variant_unref(result);

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