#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <syslog.h>
#include <stdarg.h>
#include <time.h>

#define LOG_TAG "BluetoothService"
#define FERALFILE_SERVICE_NAME   "FeralFile Device"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_SETUP_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_CMD_CHAR_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;
static GDBusNodeInfo *root_node = NULL;
static GDBusNodeInfo *service_node = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;
static pthread_t bluetooth_thread;

typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
static connection_result_callback result_callback = NULL;

typedef void (*command_callback)(int success, const unsigned char* data, int length);
static command_callback cmd_callback = NULL;

static FILE* log_file = NULL;

void bluetooth_set_logfile(const char* path) {
    if (log_file != NULL) {
        fclose(log_file);
    }
    log_file = fopen(path, "a");
}

static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    // Get current time
    time_t now;
    time(&now);
    char timestamp[26];
    ctime_r(&now, timestamp);
    timestamp[24] = '\0'; // Remove newline
    
    // Log to syslog
    vsyslog(LOG_DEBUG, format, args);
    
    // Log to console
    printf("%s: ", timestamp);
    vprintf(format, args);
    printf("\n");
    
    // Log to file if available
    if (log_file != NULL) {
        fprintf(log_file, "%s: DEBUG: ", timestamp);
        vfprintf(log_file, format, args);
        fprintf(log_file, "\n");
        fflush(log_file);
    }
    
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
    "    <node name='setup_char'>"
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
    "    <node name='cmd_char'>"
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

// ----------------------------------------------------------------------------
// Service property getter
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// Characteristic property getter
// ----------------------------------------------------------------------------
static GVariant *char_get_property(GDBusConnection *conn,
                                   const gchar *sender,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *property_name,
                                   GError **error,
                                   gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) {
            if (strstr(object_path, "setup_char") != NULL) {
                return g_variant_new_string(FERALFILE_SETUP_CHAR_UUID);
            } else if (strstr(object_path, "cmd_char") != NULL) {
                return g_variant_new_string(FERALFILE_CMD_CHAR_UUID);
            }
        } else if (g_strcmp0(property_name, "Service") == 0) {
            return g_variant_new_object_path("/com/feralfile/display/service0");
        } else if (g_strcmp0(property_name, "Flags") == 0) {
            // If you want "write" only:
            const gchar* flags[] = {"write", NULL};
            return g_variant_new_strv(flags, -1);
        }
    }
    return NULL;
}

// ----------------------------------------------------------------------------
// Handler for setup_char writes
// ----------------------------------------------------------------------------
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
    g_variant_get(parameters, "(@aya{sv})", &array_variant, &options_variant);

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));

    log_debug("[%s] (setup_char) Received %zu bytes of data", LOG_TAG, n_elements);

    // If you want to pass these bytes to your existing 'result_callback'
    if (result_callback) {
        result_callback(1, (const char*)data);
    }

    g_variant_unref(array_variant);
    if (options_variant) g_variant_unref(options_variant);
    
    g_dbus_method_invocation_return_value(invocation, NULL);
}

// ----------------------------------------------------------------------------
// Handler for cmd_char writes
// ----------------------------------------------------------------------------
static void handle_command_write(GDBusConnection *conn,
                               const gchar *sender,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *method_name,
                               GVariant *parameters,
                               GDBusMethodInvocation *invocation,
                               gpointer user_data) {
    GVariant *array_variant = NULL;
    GVariant *options_variant = NULL;
    g_variant_get(parameters, "(@aya{sv})", &array_variant, &options_variant);

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));

    log_debug("[%s] (cmd_char) Received %zu bytes of data", LOG_TAG, n_elements);

    // Use cmd_callback for command data
    if (cmd_callback) {
        cmd_callback(1, data, (int)n_elements);
    }

    g_variant_unref(array_variant);
    if (options_variant) g_variant_unref(options_variant);
    
    g_dbus_method_invocation_return_value(invocation, NULL);
}

// ----------------------------------------------------------------------------
// VTables
// ----------------------------------------------------------------------------
static const GDBusInterfaceVTable service_vtable = {
    .method_call = NULL,
    .get_property = service_get_property,
    .set_property = NULL
};

// Separate vtable for setup characteristic
static const GDBusInterfaceVTable setup_char_vtable = {
    .method_call = handle_write_value,
    .get_property = char_get_property,
    .set_property = NULL
};

// Separate vtable for command characteristic
static const GDBusInterfaceVTable cmd_char_vtable = {
    .method_call = handle_command_write,
    .get_property = char_get_property,
    .set_property = NULL
};

// ----------------------------------------------------------------------------
// Advertisement interface property getter
// ----------------------------------------------------------------------------
static GVariant* advertisement_get_property(GDBusConnection *connection,
                                            const gchar *sender,
                                            const gchar *object_path,
                                            const gchar *interface_name,
                                            const gchar *property_name,
                                            GError **error,
                                            gpointer user_data) {
    if (g_strcmp0(property_name, "Type") == 0) {
        return g_variant_new_string("peripheral");
    } else if (g_strcmp0(property_name, "ServiceUUIDs") == 0) {
        return g_variant_new_strv((const gchar*[]){FERALFILE_SERVICE_UUID, NULL}, -1);
    } else if (g_strcmp0(property_name, "LocalName") == 0) {
        return g_variant_new_string(FERALFILE_SERVICE_NAME);
    }
    return NULL;
}

static const GDBusInterfaceVTable advertisement_vtable = {
    .method_call = NULL,
    .get_property = advertisement_get_property,
    .set_property = NULL,
};

// ----------------------------------------------------------------------------
// ObjectManager "GetManagedObjects" handling
// ----------------------------------------------------------------------------
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
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0", service_builder);
    
    // Add setup characteristic object
    GVariantBuilder *setup_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *setup_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(setup_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SETUP_CHAR_UUID));
    g_variant_builder_add(setup_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* setup_flags[] = {"write", NULL};
    g_variant_builder_add(setup_char_props, "{sv}", "Flags", g_variant_new_strv(setup_flags, -1));
    g_variant_builder_add(setup_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", setup_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/setup_char", setup_char_builder);
    
    // Add command characteristic object
    GVariantBuilder *cmd_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *cmd_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(cmd_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_CMD_CHAR_UUID));
    g_variant_builder_add(cmd_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* cmd_flags[] = {"write", NULL};
    g_variant_builder_add(cmd_char_props, "{sv}", "Flags", g_variant_new_strv(cmd_flags, -1));
    g_variant_builder_add(cmd_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", cmd_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/cmd_char", cmd_char_builder);
    
    // Return everything
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", builder));
    
    g_variant_builder_unref(builder);
    g_variant_builder_unref(service_builder);
    g_variant_builder_unref(setup_char_builder);
    g_variant_builder_unref(cmd_char_builder);
    g_variant_builder_unref(service_props);
    g_variant_builder_unref(setup_char_props);
    g_variant_builder_unref(cmd_char_props);
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

    // Step 1: Connect to the system bus
    connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n",
                  LOG_TAG,
                  error->message);
        g_error_free(error);
        return -1;
    }

    // Step 2: Parse our service XML
    root_node = g_dbus_node_info_new_for_xml(service_xml, &error);
    if (!root_node || error) {
        log_debug("[%s] Failed to parse service XML: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Find the service0 node
    service_node = find_node_by_name(root_node, "service0");
    if (!service_node) {
        log_debug("[%s] service0 node not found\n", LOG_TAG);
        return -1;
    }

    // Find characteristic nodes
    GDBusNodeInfo *setup_char_node = find_node_by_name(service_node, "setup_char");
    GDBusNodeInfo *cmd_char_node   = find_node_by_name(service_node, "cmd_char");
    if (!setup_char_node || !cmd_char_node) {
        log_debug("[%s] Characteristic nodes not found\n", LOG_TAG);
        return -1;
    }

    // Step 3: Register ObjectManager interface
    guint objects_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display",
        g_dbus_node_info_lookup_interface(root_node, "org.freedesktop.DBus.ObjectManager"),
        &objects_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !objects_reg_id) {
        log_debug("[%s] Failed to register ObjectManager interface: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 4: Register the service object
    guint service_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0",
        service_node->interfaces[0],  // org.bluez.GattService1
        &service_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !service_reg_id) {
        log_debug("[%s] Failed to register service object: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 5: Register your setup characteristic
    guint setup_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/setup_char",
        setup_char_node->interfaces[0],  // org.bluez.GattCharacteristic1
        &setup_char_vtable,             // <--- use setup_char_vtable
        NULL,
        NULL,
        &error
    );
    if (error || !setup_char_reg_id) {
        log_debug("[%s] Failed to register setup characteristic object: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 6: Register your command characteristic
    guint cmd_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/cmd_char",
        cmd_char_node->interfaces[0],   // org.bluez.GattCharacteristic1
        &cmd_char_vtable,              // <--- use cmd_char_vtable
        NULL,
        NULL,
        &error
    );
    if (error || !cmd_char_reg_id) {
        log_debug("[%s] Failed to register command characteristic object: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 7: Get the GattManager1 interface
    GDBusProxy *gatt_manager = g_dbus_proxy_new_sync(
        connection,
        G_DBUS_PROXY_FLAGS_NONE,
        NULL,
        "org.bluez",
        "/org/bluez/hci0",
        "org.bluez.GattManager1",
        NULL,
        &error
    );
    if (!gatt_manager || error) {
        log_debug("[%s] Failed to get GattManager1: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 8: Register the application
    g_dbus_proxy_call_sync(
        gatt_manager,
        "RegisterApplication",
        g_variant_new("(oa{sv})", "/com/feralfile/display", NULL),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    if (error) {
        log_debug("[%s] RegisterApplication failed: %s\n",
                  LOG_TAG,
                  error->message);
        g_error_free(error);
        return -1;
    }

    // Step 9: Parse advertisement XML
    advertisement_introspection_data =
        g_dbus_node_info_new_for_xml(advertisement_introspection_xml, &error);
    if (!advertisement_introspection_data || error) {
        log_debug("[%s] Failed to parse advertisement XML: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 10: Register advertisement object
    guint ad_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/advertisement0",
        advertisement_introspection_data->interfaces[0],  // org.bluez.LEAdvertisement1
        &advertisement_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !ad_reg_id) {
        log_debug("[%s] Failed to register advertisement object: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 11: Get LEAdvertisingManager1
    GDBusProxy *advertising_manager = g_dbus_proxy_new_sync(
        connection,
        G_DBUS_PROXY_FLAGS_NONE,
        NULL,
        "org.bluez",
        "/org/bluez/hci0",
        "org.bluez.LEAdvertisingManager1",
        NULL,
        &error
    );
    if (!advertising_manager || error) {
        log_debug("[%s] Failed to get LEAdvertisingManager1: %s\n",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 12: Register the advertisement
    g_dbus_proxy_call_sync(
        advertising_manager,
        "RegisterAdvertisement",
        g_variant_new("(oa{sv})", "/com/feralfile/display/advertisement0", NULL),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    if (error) {
        log_debug("[%s] Advertisement registration failed: %s\n",
                  LOG_TAG,
                  error->message);
        g_error_free(error);
        return -1;
    }

    log_debug("[%s] Bluetooth initialized successfully\n", LOG_TAG);
    return 0;
}

int bluetooth_start(connection_result_callback scb, command_callback ccb) {
    result_callback = scb;
    cmd_callback = ccb;
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