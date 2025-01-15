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
#define FERALFILE_SERVICE_NAME       "FeralFile Device"
#define FERALFILE_SERVICE_UUID       "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_SETUP_CHAR_UUID    "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_CMD_CHAR_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;

// Keep track of all registration IDs for later cleanup
static guint objects_reg_id = 0;
static guint service_reg_id = 0;
static guint setup_char_reg_id = 0;
static guint cmd_char_reg_id = 0;
static guint ad_reg_id = 0;

// Keep track of proxies we create so we can unref them
static GDBusProxy *gatt_manager = NULL;
static GDBusProxy *advertising_manager = NULL;

// Keep track of node infos for cleanup
static GDBusNodeInfo *root_node = NULL;
static GDBusNodeInfo *service_node = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;

// For thread management
static pthread_t bluetooth_thread;
static gboolean keep_running = TRUE; // Used instead of pthread_cancel

// Callbacks
typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
static connection_result_callback result_callback = NULL;

typedef void (*command_callback)(int success, const unsigned char* data, int length);
static command_callback cmd_callback = NULL;

// Logging
static FILE* log_file = NULL;

void bluetooth_set_logfile(const char* path) {
    if (log_file != NULL) {
        fclose(log_file);
        log_file = NULL;
    }
    if (path && strlen(path) > 0) {
        FILE* f = fopen(path, "a");
        if (f) {
            log_file = f;
        } else {
            syslog(LOG_ERR, "Failed to open log file: %s", path);
        }
    }
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

// ----------------------------------------------------------------------------
// XML definitions
// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
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

const char* bluetooth_get_device_id() {
    static char device_id[18];  // MAC addresses are 17 chars + null terminator
    GError *error = NULL;

    // Get the default adapter
    GDBusProxy *adapter = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SYSTEM,
        G_DBUS_PROXY_FLAGS_NONE,
        NULL,
        "org.bluez",
        "/org/bluez/hci0",
        "org.bluez.Adapter1",
        NULL,
        &error
    );

    if (error != NULL) {
        log_debug("[%s] Failed to get adapter: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return NULL;
    }
    if (!adapter) {
        log_debug("[%s] Failed to create adapter proxy.\n", LOG_TAG);
        return NULL;
    }

    // Get the adapter's address property
    GVariant *address = g_dbus_proxy_get_cached_property(adapter, "Address");
    if (address != NULL) {
        const char *addr_str = g_variant_get_string(address, NULL);
        strncpy(device_id, addr_str, sizeof(device_id) - 1);
        device_id[sizeof(device_id) - 1] = '\0';
        g_variant_unref(address);
    } else {
        log_debug("[%s] Failed to get adapter address\n", LOG_TAG);
        g_object_unref(adapter);
        return NULL;
    }

    g_object_unref(adapter);
    return device_id;
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
        if (g_strcmp0(property_name, "UUID") == 0) {
            return g_variant_new_string(FERALFILE_SERVICE_UUID);
        } else if (g_strcmp0(property_name, "Primary") == 0) {
            return g_variant_new_boolean(TRUE);
        }
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
            // Only "write". Could add "write-without-response" or "notify" if needed.
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

    gsize n_elements = 0;
    const guchar *data = NULL;
    if (array_variant) {
        data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));
    }

    // Create a copy of the data
    guchar *data_copy = NULL;
    if (n_elements > 0 && data) {
        data_copy = (guchar *)malloc(n_elements);
        memcpy(data_copy, data, n_elements);
    }

    log_debug("[%s] (setup_char) Received %zu bytes of data", LOG_TAG, n_elements);

    // Add hex string logging
    if (data_copy) {
        char *hex_string = malloc(n_elements * 3 + 1);
        for (size_t i = 0; i < n_elements; i++) {
            sprintf(hex_string + (i * 3), "%02x ", data_copy[i]);
        }
        // Trim trailing space
        if (n_elements > 0) {
            hex_string[n_elements * 3 - 1] = '\0';
        }
        log_debug("[%s] (setup_char) Data: %s", LOG_TAG, hex_string);
        free(hex_string);
    }

    // Call the user callback
    if (result_callback && data_copy) {
        result_callback(1, (const unsigned char*)data_copy, (int)n_elements);
    }

    // Clean up
    free(data_copy);
    if (array_variant) {
        g_variant_unref(array_variant);
    }
    if (options_variant) {
        g_variant_unref(options_variant);
    }

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

    gsize n_elements = 0;
    const guchar *data = NULL;
    if (array_variant) {
        data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));
    }

    // Create a copy of the data
    guchar *data_copy = NULL;
    if (n_elements > 0 && data) {
        data_copy = (guchar *)malloc(n_elements);
        memcpy(data_copy, data, n_elements);
    }

    log_debug("[%s] (cmd_char) Received %zu bytes of data", LOG_TAG, n_elements);

    // Add hex string logging
    if (data_copy) {
        char *hex_string = malloc(n_elements * 3 + 1);
        for (size_t i = 0; i < n_elements; i++) {
            sprintf(hex_string + (i * 3), "%02x ", data_copy[i]);
        }
        if (n_elements > 0) {
            hex_string[n_elements * 3 - 1] = '\0';
        }
        log_debug("[%s] (cmd_char) Data: %s", LOG_TAG, hex_string);
        free(hex_string);
    }

    // Use cmd_callback with the copied data
    if (cmd_callback && data_copy) {
        cmd_callback(1, (const unsigned char*)data_copy, (int)n_elements);
    }

    // Clean up
    free(data_copy);
    if (array_variant) {
        g_variant_unref(array_variant);
    }
    if (options_variant) {
        g_variant_unref(options_variant);
    }

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

static const GDBusInterfaceVTable setup_char_vtable = {
    .method_call = handle_write_value,
    .get_property = char_get_property,
    .set_property = NULL
};

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

    // Cleanup
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

// ----------------------------------------------------------------------------
// Thread function
// ----------------------------------------------------------------------------
static void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);

    // Once quit, clean up the loop
    if (main_loop) {
        g_main_loop_unref(main_loop);
        main_loop = NULL;
    }
    pthread_exit(NULL);
}

// ----------------------------------------------------------------------------
// Initialization
// ----------------------------------------------------------------------------
int bluetooth_init() {
    log_debug("[%s] Initializing Bluetooth\n", LOG_TAG);
    GError *error = NULL;

    // Step 1: Connect to the system bus
    connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 2: Parse our service XML
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

    // Find characteristic nodes
    GDBusNodeInfo *setup_char_node = find_node_by_name(service_node, "setup_char");
    GDBusNodeInfo *cmd_char_node   = find_node_by_name(service_node, "cmd_char");
    if (!setup_char_node || !cmd_char_node) {
        log_debug("[%s] Characteristic nodes not found\n", LOG_TAG);
        return -1;
    }

    // Step 3: Register ObjectManager interface
    objects_reg_id = g_dbus_connection_register_object(
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
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 4: Register the service object
    service_reg_id = g_dbus_connection_register_object(
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
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 5: Register the setup characteristic
    setup_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/setup_char",
        setup_char_node->interfaces[0],
        &setup_char_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !setup_char_reg_id) {
        log_debug("[%s] Failed to register setup characteristic object: %s\n",
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 6: Register the command characteristic
    cmd_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/cmd_char",
        cmd_char_node->interfaces[0],
        &cmd_char_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !cmd_char_reg_id) {
        log_debug("[%s] Failed to register command characteristic object: %s\n",
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 7: Get the GattManager1 interface
    gatt_manager = g_dbus_proxy_new_sync(
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
                  LOG_TAG, error ? error->message : "Unknown error");
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
        log_debug("[%s] RegisterApplication failed: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Step 9: Parse advertisement XML
    advertisement_introspection_data = g_dbus_node_info_new_for_xml(advertisement_introspection_xml, &error);
    if (!advertisement_introspection_data || error) {
        log_debug("[%s] Failed to parse advertisement XML: %s\n",
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 10: Register advertisement object
    ad_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/advertisement0",
        advertisement_introspection_data->interfaces[0],
        &advertisement_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !ad_reg_id) {
        log_debug("[%s] Failed to register advertisement object: %s\n",
                  LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return -1;
    }

    // Step 11: Get LEAdvertisingManager1
    advertising_manager = g_dbus_proxy_new_sync(
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
                  LOG_TAG, error ? error->message : "Unknown error");
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
        log_debug("[%s] Advertisement registration failed: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    log_debug("[%s] Bluetooth initialized successfully\n", LOG_TAG);
    return 0;
}

// ----------------------------------------------------------------------------
// Starting & Stopping
// ----------------------------------------------------------------------------
int bluetooth_start(connection_result_callback scb, command_callback ccb) {
    result_callback = scb;
    cmd_callback = ccb;

    // Create and start the main loop thread
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        log_debug("[%s] Failed to start Bluetooth thread\n", LOG_TAG);
        return -1;
    }

    log_debug("[%s] Bluetooth service started\n", LOG_TAG);
    return 0;
}

void bluetooth_stop() {
    log_debug("[%s] Stopping Bluetooth service...\n", LOG_TAG);

    // Signal the main loop to quit
    if (main_loop) {
        g_main_loop_quit(main_loop);
    }

    // Wait for the thread to exit
    pthread_join(bluetooth_thread, NULL);

    // Now, gracefully unregister our advertisement and application
    GError *error = NULL;

    // 1. UnregisterAdvertisement
    if (advertising_manager) {
        GVariant *ret = g_dbus_proxy_call_sync(
            advertising_manager,
            "UnregisterAdvertisement",
            g_variant_new("(o)", "/com/feralfile/display/advertisement0"),
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            NULL,
            &error
        );
        if (error) {
            log_debug("[%s] UnregisterAdvertisement error: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        if (ret) {
            g_variant_unref(ret);
        }
    }

    // 2. UnregisterApplication
    if (gatt_manager) {
        GVariant *ret = g_dbus_proxy_call_sync(
            gatt_manager,
            "UnregisterApplication",
            g_variant_new("(o)", "/com/feralfile/display"),
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            NULL,
            &error
        );
        if (error) {
            log_debug("[%s] UnregisterApplication error: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        if (ret) {
            g_variant_unref(ret);
        }
    }

    // 3. Unregister all objects
    if (ad_reg_id > 0) {
        g_dbus_connection_unregister_object(connection, ad_reg_id);
        ad_reg_id = 0;
    }
    if (cmd_char_reg_id > 0) {
        g_dbus_connection_unregister_object(connection, cmd_char_reg_id);
        cmd_char_reg_id = 0;
    }
    if (setup_char_reg_id > 0) {
        g_dbus_connection_unregister_object(connection, setup_char_reg_id);
        setup_char_reg_id = 0;
    }
    if (service_reg_id > 0) {
        g_dbus_connection_unregister_object(connection, service_reg_id);
        service_reg_id = 0;
    }
    if (objects_reg_id > 0) {
        g_dbus_connection_unregister_object(connection, objects_reg_id);
        objects_reg_id = 0;
    }

    // 4. Free node info references
    if (advertisement_introspection_data) {
        g_dbus_node_info_unref(advertisement_introspection_data);
        advertisement_introspection_data = NULL;
    }
    // root_node includes the entire tree (service0, etc.)
    if (root_node) {
        g_dbus_node_info_unref(root_node);
        root_node = NULL;
        service_node = NULL;
    }

    // 5. Unref proxies
    if (advertising_manager) {
        g_object_unref(advertising_manager);
        advertising_manager = NULL;
    }
    if (gatt_manager) {
        g_object_unref(gatt_manager);
        gatt_manager = NULL;
    }

    // 6. Finally, unref the main D-Bus connection
    if (connection) {
        g_object_unref(connection);
        connection = NULL;
    }

    log_debug("[%s] Bluetooth service stopped\n", LOG_TAG);
}