#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <syslog.h>
#include <stdarg.h>

#define LOG_TAG "BluetoothService"
#define FERALFILE_SERVICE_NAME   "FeralFile Connection"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_WIFI_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"

static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;
static GDBusNodeInfo *root_node = NULL;
static GDBusNodeInfo *service_node = NULL;
static GDBusNodeInfo *char_node = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;
static pthread_t bluetooth_thread;

typedef void (*connection_result_callback)(int);
static connection_result_callback result_callback = NULL;

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

static const gchar service_xml[] =
    "<node>"
    "  <interface name='org.freedesktop.DBus.ObjectManager'>"
    "    <method name='GetManagedObjects'>"
    "      <arg name='objects' type='a{oa{sa{sv}}}' direction='out'/>"
    "    </method>"
    "  </interface>"
    "  <node name='service0'>"
    "    <interface name='org.bluez.GattService1'>"
    "      <property name='UUID' type='s' access='read'/>"
    "      <property name='Primary' type='b' access='read'/>"
    "    </interface>"
    "    <node name='char0'>"
    "      <interface name='org.bluez.GattCharacteristic1'>"
    "        <property name='UUID' type='s' access='read'/>"
    "        <property name='Service' type='o' access='read'/>"
    "        <property name='Flags' type='as' access='read'/>"
    "        <method name='WriteValue'>"
    "          <arg name='value' type='ay' direction='in'/>"
    "          <arg name='options' type='a{sv}' direction='in'/>"
    "        </method>"
    "      </interface>"
    "    </node>"
    "  </node>"
    "</node>";

static const gchar advertisement_introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.LEAdvertisement1'>"
    "    <method name='Release'/>"
    "    <property name='Type' type='s' access='read'/>"
    "    <property name='ServiceUUIDs' type='as' access='read'/>"
    "    <property name='LocalName' type='s' access='read'/>"
    "  </interface>"
    "</node>";

static GDBusNodeInfo* find_node_by_name(GDBusNodeInfo *parent, const gchar *name) {
    GDBusNodeInfo **nodes = parent->nodes;
    while (*nodes != NULL) {
        if (g_strcmp0((*nodes)->path, name) == 0) {
            return *nodes;
        }
        nodes++;
    }
    return NULL;
}

static GVariant *service_get_property(GDBusConnection *conn,
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

static GVariant *char_get_property(GDBusConnection *conn,
                                   const gchar *sender,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *property_name,
                                   GError **error,
                                   gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) {
            return g_variant_new_string(FERALFILE_WIFI_CHAR_UUID);
        } else if (g_strcmp0(property_name, "Service") == 0) {
            return g_variant_new_object_path("/org/bluez/example/service0");
        } else if (g_strcmp0(property_name, "Flags") == 0) {
            const gchar* flags[] = {"write", NULL};
            return g_variant_new_strv(flags, -1);
        }
    }
    return NULL;
}

static void handle_write_value(GDBusConnection *conn,
                               const gchar *sender,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *method_name,
                               GVariant *parameters,
                               GDBusMethodInvocation *invocation,
                               gpointer user_data) {
    GVariant *array_variant = NULL;
    GVariant *options_variant = NULL;
    
    // Correctly extract the array and options from parameters
    g_variant_get(parameters, "(@ay@a{sv})", &array_variant, &options_variant);

    // Get the data bytes
    const guint8 *data;
    gsize n_elements;
    data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guint8));

    // Copy to buffer and ensure null termination
    char buffer[256];
    memset(buffer, 0, sizeof(buffer));
    memcpy(buffer, data, MIN(n_elements, sizeof(buffer) - 1));
    
    log_debug("[%s] WriteValue received: %s\n", LOG_TAG, buffer);

    // Clean up
    g_dbus_method_invocation_return_value(invocation, NULL);
    g_variant_unref(array_variant);
    g_variant_unref(options_variant);
}

static const GDBusInterfaceVTable service_vtable = {
    .method_call = NULL,
    .get_property = service_get_property,
    .set_property = NULL
};

static const GDBusInterfaceVTable char_vtable = {
    .method_call = handle_write_value,
    .get_property = char_get_property,
    .set_property = NULL
};

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

static void handle_get_objects(GDBusConnection *conn,
                             const gchar *sender,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *method_name,
                             GVariant *parameters,
                             GDBusMethodInvocation *invocation,
                             gpointer user_data) {
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE("a{oa{sa{sv}}}"));
    
    // Add service object
    GVariantBuilder *service_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *service_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(service_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SERVICE_UUID));
    g_variant_builder_add(service_props, "{sv}", "Primary", g_variant_new_boolean(TRUE));
    g_variant_builder_add(service_builder, "{sa{sv}}", "org.bluez.GattService1", service_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/org/bluez/example/service0", service_builder);
    
    // Add characteristic object
    GVariantBuilder *char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_WIFI_CHAR_UUID));
    g_variant_builder_add(char_props, "{sv}", "Service", g_variant_new_object_path("/org/bluez/example/service0"));
    const gchar* flags[] = {"write", NULL};
    g_variant_builder_add(char_props, "{sv}", "Flags", g_variant_new_strv(flags, -1));
    g_variant_builder_add(char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/org/bluez/example/service0/char0", char_builder);
    
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", builder));
    
    g_variant_builder_unref(builder);
    g_variant_builder_unref(service_builder);
    g_variant_builder_unref(char_builder);
    g_variant_builder_unref(service_props);
    g_variant_builder_unref(char_props);
}

static const GDBusInterfaceVTable objects_vtable = {
    .method_call = handle_get_objects,
    .get_property = NULL,
    .set_property = NULL
};

static void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);
    pthread_exit(NULL);
}

int bluetooth_init() {
    log_debug("[%s] Initializing Bluetooth\n", LOG_TAG);
    GError *error = NULL;

    connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    root_node = g_dbus_node_info_new_for_xml(service_xml, &error);
    if (!root_node || error) {
        log_debug("[%s] Failed to parse service XML: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Find the service0 node
    service_node = find_node_by_name(root_node, "service0");
    if (!service_node) {
        log_debug("[%s] service0 node not found\n", LOG_TAG);
        return -1;
    }

    // Find the char0 node
    char_node = find_node_by_name(service_node, "char0");
    if (!char_node) {
        log_debug("[%s] char0 node not found\n", LOG_TAG);
        return -1;
    }

    // Register the service object
    guint service_reg_id = g_dbus_connection_register_object(connection,
                                                             "/org/bluez/example/service0",
                                                             service_node->interfaces[0],
                                                             &service_vtable,
                                                             NULL, NULL, &error);
    if (error || !service_reg_id) {
        log_debug("[%s] Failed to register service object: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Register the characteristic object
    guint char_reg_id = g_dbus_connection_register_object(connection,
                                                          "/org/bluez/example/service0/char0",
                                                          char_node->interfaces[0],
                                                          &char_vtable,
                                                          NULL, NULL, &error);
    if (error || !char_reg_id) {
        log_debug("[%s] Failed to register characteristic object: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Register advertisement
    advertisement_introspection_data = g_dbus_node_info_new_for_xml(advertisement_introspection_xml, &error);
    if (!advertisement_introspection_data || error) {
        log_debug("[%s] Failed to parse advertisement XML: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    guint ad_reg_id = g_dbus_connection_register_object(connection,
                                                        "/org/bluez/example/advertisement0",
                                                        advertisement_introspection_data->interfaces[0],
                                                        &advertisement_vtable,
                                                        NULL, NULL, &error);
    if (error || !ad_reg_id) {
        log_debug("[%s] Failed to register advertisement object: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Register ObjectManager interface FIRST
    guint objects_reg_id = g_dbus_connection_register_object(connection,
                                                           "/org/bluez/example",
                                                           g_dbus_node_info_lookup_interface(root_node, "org.freedesktop.DBus.ObjectManager"),
                                                           &objects_vtable,
                                                           NULL, NULL, &error);
    if (error || !objects_reg_id) {
        log_debug("[%s] Failed to register ObjectManager interface: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Then register the application
    GDBusProxy *gatt_manager = g_dbus_proxy_new_sync(connection,
                                                     G_DBUS_PROXY_FLAGS_NONE,
                                                     NULL,
                                                     "org.bluez",
                                                     "/org/bluez/hci0",
                                                     "org.bluez.GattManager1",
                                                     NULL,
                                                     &error);
    if (!gatt_manager || error) {
        log_debug("[%s] Failed to get GattManager1: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    g_dbus_proxy_call_sync(gatt_manager,
                           "RegisterApplication",
                           g_variant_new("(oa{sv})", "/org/bluez/example", NULL),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           NULL,
                           &error);
    if (error) {
        log_debug("[%s] RegisterApplication failed: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Register advertisement
    GDBusProxy *advertising_manager = g_dbus_proxy_new_sync(connection,
                                                            G_DBUS_PROXY_FLAGS_NONE,
                                                            NULL,
                                                            "org.bluez",
                                                            "/org/bluez/hci0",
                                                            "org.bluez.LEAdvertisingManager1",
                                                            NULL,
                                                            &error);
    if (!advertising_manager || error) {
        log_debug("[%s] Failed to get LEAdvertisingManager1: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

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