#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <syslog.h>
#include <stdarg.h>
#include <time.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <sentry.h>

#define LOG_TAG "BluetoothService"
#define FERALFILE_SERVICE_NAME   "FeralFile Device"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_SETUP_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_CMD_CHAR_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_ENG_CHAR_UUID "6e400004-b5a3-f393-e0a9-e50e24dcca9e"
#define MAX_DEVICE_NAME_LENGTH 32
#define MAX_ADV_PATH_LENGTH 64

static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;
static GDBusNodeInfo *root_node = NULL;
static GDBusNodeInfo *service_node = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;

static guint objects_reg_id = 0;
static guint service_reg_id = 0;
static guint setup_char_reg_id = 0;
static guint cmd_char_reg_id = 0;
static guint ad_reg_id = 0;
static guint eng_char_reg_id = 0;

static GDBusProxy *gatt_manager = NULL;
static GDBusProxy *advertising_manager = NULL;

static pthread_t bluetooth_thread;

typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
static connection_result_callback result_callback = NULL;

typedef void (*command_callback)(int success, const unsigned char* data, int length);
static command_callback cmd_callback = NULL;

static FILE* log_file = NULL;

static char device_name[MAX_DEVICE_NAME_LENGTH] = FERALFILE_SERVICE_NAME;
static char advertisement_path[MAX_ADV_PATH_LENGTH] = "/com/feralfile/display/advertisement0";

static int sentry_initialized = 0;

typedef struct {
    char message[1024];
    int level;  // 0 for info, 1 for error
    time_t timestamp;
} LogMessage;

#define LOG_QUEUE_SIZE 100
static LogMessage log_queue[LOG_QUEUE_SIZE];
static int log_queue_head = 0;
static int log_queue_tail = 0;
static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t log_thread;
static int log_thread_running = 0;

typedef struct {
    unsigned char* data;
    int length;
    int success;
} CallbackData;

static pthread_mutex_t callback_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t callback_cond = PTHREAD_COND_INITIALIZER;
static pthread_t callback_thread;
static int callback_thread_running = 0;

#define CALLBACK_QUEUE_SIZE 20
static CallbackData callback_queue[CALLBACK_QUEUE_SIZE];
static int callback_queue_head = 0;
static int callback_queue_tail = 0;
static int callback_type_queue[CALLBACK_QUEUE_SIZE]; // 0 for setup, 1 for cmd

typedef struct {
    unsigned char* data;
    int length;
    int type;  // 0 for command, 1 for engineering
} NotifyData;

#define NOTIFY_QUEUE_SIZE 20
static NotifyData notify_queue[NOTIFY_QUEUE_SIZE];
static int notify_queue_head = 0;
static int notify_queue_tail = 0;
static pthread_mutex_t notify_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t notify_cond = PTHREAD_COND_INITIALIZER;
static pthread_t notify_thread;
static int notify_thread_running = 0;

static void* log_thread_func(void* arg) {
    while (log_thread_running) {
        LogMessage msg;
        int have_message = 0;
        
        // Get message from queue
        pthread_mutex_lock(&log_mutex);
        if (log_queue_head != log_queue_tail) {
            msg = log_queue[log_queue_tail];
            log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
            have_message = 1;
        }
        pthread_mutex_unlock(&log_mutex);
        
        if (have_message) {
            // Format timestamp
            char timestamp[26];
            ctime_r(&msg.timestamp, timestamp);
            timestamp[24] = '\0'; // Remove newline
            
            if (msg.level == 0) {  // Info
                // Write to syslog, stdout, file
                syslog(LOG_INFO, "%s", msg.message);
                fprintf(stdout, "%s: INFO: %s\n", timestamp, msg.message);
                if (log_file != NULL) {
                    fprintf(log_file, "%s: INFO: %s\n", timestamp, msg.message);
                    fflush(log_file);
                }
            } else {  // Error
                syslog(LOG_ERR, "%s", msg.message);
                fprintf(stderr, "%s: ERROR: %s\n", timestamp, msg.message);
                if (log_file != NULL) {
                    fprintf(log_file, "%s: ERROR: %s\n", timestamp, msg.message);
                    fflush(log_file);
                }
            }
        } else {
            // Sleep a bit if no messages
            usleep(10000);  // 10ms
        }
    }
    return NULL;
}

static void start_log_thread() {
    log_thread_running = 1;
    pthread_create(&log_thread, NULL, log_thread_func, NULL);
}

static void stop_log_thread() {
    log_thread_running = 0;
    pthread_join(log_thread, NULL);
}

void log_info(const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    // Format the message
    LogMessage msg;
    msg.level = 0;  // info
    time(&msg.timestamp);
    vsnprintf(msg.message, sizeof(msg.message), format, args);
    
    // Add to queue
    pthread_mutex_lock(&log_mutex);
    log_queue[log_queue_head] = msg;
    log_queue_head = (log_queue_head + 1) % LOG_QUEUE_SIZE;
    pthread_mutex_unlock(&log_mutex);
    
    // Add Sentry breadcrumb (still synchronous)
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("info", msg.message);
        sentry_value_set_by_key(crumb, "category", sentry_value_new_string("bluetooth"));
        sentry_add_breadcrumb(crumb);
    }
    #endif
    
    va_end(args);
}

static void log_error(const char* format, ...) {
    va_list args, args_copy;
    va_start(args, format);
    va_copy(args_copy, args);
    
    // Get current time
    time_t now;
    time(&now);
    char timestamp[26];
    ctime_r(&now, timestamp);
    timestamp[24] = '\0'; // Remove newline
    
    // Log to syslog
    vsyslog(LOG_ERR, format, args);
    
    // Log to console (stderr)
    fprintf(stderr, "%s: ERROR: ", timestamp);
    vfprintf(stderr, format, args_copy);
    fprintf(stderr, "\n");
    fflush(stderr);  // Ensure immediate output
    
    // Log to file if available
    if (log_file != NULL) {
        fprintf(log_file, "%s: ERROR: ", timestamp);
        vfprintf(log_file, format, args);
        fprintf(log_file, "\n");
        fflush(log_file);
    }
    
    // Capture Sentry event for error messages
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        char message[1024];
        va_list args_event;
        va_copy(args_event, args);
        vsnprintf(message, sizeof(message), format, args_event);
        va_end(args_event);
        
        sentry_value_t event = sentry_value_new_message_event(
            SENTRY_LEVEL_ERROR,
            "bluetooth",
            message
        );
        sentry_capture_event(event);
    }
    #endif
    
    va_end(args_copy);
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
    "        <method name='StartNotify'/>"
    "        <method name='StopNotify'/>"
    "      </interface>"
    "    </node>"
    "    <node name='eng_char'>"
    "      <interface name='org.bluez.GattCharacteristic1'>"
    "        <property name='UUID' type='s' access='read'/>"
    "        <property name='Service' type='o' access='read'/>"
    "        <property name='Flags' type='as' access='read'/>"
    "        <method name='StartNotify'/>"
    "        <method name='StopNotify'/>"
    "      </interface>"
    "    </node>"
    "  </node>"
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
            } else if (strstr(object_path, "eng_char") != NULL) {
                return g_variant_new_string(FERALFILE_ENG_CHAR_UUID);
            }
        } else if (g_strcmp0(property_name, "Service") == 0) {
            return g_variant_new_object_path("/com/feralfile/display/service0");
        } else if (g_strcmp0(property_name, "Flags") == 0) {
            if (strstr(object_path, "cmd_char") != NULL) {
                const gchar* flags[] = {"write", "write-without-response", "notify", NULL};
                return g_variant_new_strv(flags, -1);
            } else if (strstr(object_path, "eng_char") != NULL) {
                const gchar* flags[] = {"notify", NULL};
                return g_variant_new_strv(flags, -1);
            } else {  // setup_char
                const gchar* flags[] = {"write", NULL};
                return g_variant_new_strv(flags, -1);
            }
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

    // Create a copy of the data
    guchar *data_copy = (guchar *)malloc(n_elements);
    memcpy(data_copy, data, n_elements);

    log_info("[%s] (setup_char) Received %zu bytes of data", LOG_TAG, n_elements);
    
    // Optional hex string logging
    char hex_string[n_elements * 3 + 1];
    for (size_t i = 0; i < n_elements; i++) {
        sprintf(hex_string + (i * 3), "%02x ", data_copy[i]);
    }
    hex_string[n_elements * 3 - 1] = '\0';
    log_info("[%s] (setup_char) Data: %s", LOG_TAG, hex_string);

    // Queue the callback
    pthread_mutex_lock(&callback_mutex);
    if ((callback_queue_head + 1) % CALLBACK_QUEUE_SIZE != callback_queue_tail) {
        CallbackData *data = &callback_queue[callback_queue_head];
        data->data = data_copy;
        data->length = n_elements;
        data->success = 1;
        callback_type_queue[callback_queue_head] = 0;  // setup callback
        callback_queue_head = (callback_queue_head + 1) % CALLBACK_QUEUE_SIZE;
        pthread_cond_signal(&callback_cond);
    } else {
        // Queue full, handle error
        free(data_copy);
        log_error("[%s] Callback queue full, dropping message", LOG_TAG);
    }
    pthread_mutex_unlock(&callback_mutex);
    
    g_variant_unref(array_variant);
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

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));

    // Create a copy of the data
    guchar *data_copy = (guchar *)malloc(n_elements);
    memcpy(data_copy, data, n_elements);

    log_info("[%s] (cmd_char) Received %zu bytes of data", LOG_TAG, n_elements);

    // Optional hex string logging
    char hex_string[n_elements * 3 + 1];
    for (size_t i = 0; i < n_elements; i++) {
        sprintf(hex_string + (i * 3), "%02x ", data_copy[i]);
    }
    hex_string[n_elements * 3 - 1] = '\0';
    log_info("[%s] (cmd_char) Data: %s", LOG_TAG, hex_string);

    // Queue the callback
    pthread_mutex_lock(&callback_mutex);
    if ((callback_queue_head + 1) % CALLBACK_QUEUE_SIZE != callback_queue_tail) {
        CallbackData *data = &callback_queue[callback_queue_head];
        data->data = data_copy;
        data->length = n_elements;
        data->success = 1;
        callback_type_queue[callback_queue_head] = 1;  // cmd callback
        callback_queue_head = (callback_queue_head + 1) % CALLBACK_QUEUE_SIZE;
        pthread_cond_signal(&callback_cond);
    } else {
        // Queue full, handle error
        free(data_copy);
        log_error("[%s] Callback queue full, dropping message", LOG_TAG);
    }
    pthread_mutex_unlock(&callback_mutex);
    
    g_variant_unref(array_variant);
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

// Vtable for engineering characteristic
static const GDBusInterfaceVTable eng_char_vtable = {
    .method_call = NULL,  // No write methods needed
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
        return g_variant_new_string(device_name);
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
    const gchar* cmd_flags[] = {"write", "write-without-response", "notify", NULL};
    g_variant_builder_add(cmd_char_props, "{sv}", "Flags", g_variant_new_strv(cmd_flags, -1));
    g_variant_builder_add(cmd_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", cmd_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/cmd_char", cmd_char_builder);
    
    // Add engineering characteristic object
    GVariantBuilder *eng_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *eng_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(eng_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_ENG_CHAR_UUID));
    g_variant_builder_add(eng_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* eng_flags[] = {"notify", NULL};
    g_variant_builder_add(eng_char_props, "{sv}", "Flags", g_variant_new_strv(eng_flags, -1));
    g_variant_builder_add(eng_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", eng_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/eng_char", eng_char_builder);
    
    // Return everything
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", builder));
    
    g_variant_builder_unref(builder);
    g_variant_builder_unref(service_builder);
    g_variant_builder_unref(setup_char_builder);
    g_variant_builder_unref(cmd_char_builder);
    g_variant_builder_unref(service_props);
    g_variant_builder_unref(setup_char_props);
    g_variant_builder_unref(cmd_char_props);
    g_variant_builder_unref(eng_char_builder);
    g_variant_builder_unref(eng_char_props);
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

static void* bluetooth_thread_func(void* arg) {
    GError *error = NULL;

    main_loop = g_main_loop_new(NULL, FALSE);

    // Step 1: Connect to the system bus
    connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (!connection) {
        log_error("[%s] Failed to connect to D-Bus: %s", LOG_TAG, error->message);
        g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 2: Parse our service XML
    root_node = g_dbus_node_info_new_for_xml(service_xml, &error);
    if (!root_node || error) {
        log_error("[%s] Failed to parse service XML: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Find the service0 node
    service_node = find_node_by_name(root_node, "service0");
    if (!service_node) {
        log_error("[%s] service0 node not found", LOG_TAG);
        pthread_exit(NULL);
    }

    // Find characteristic nodes
    GDBusNodeInfo *setup_char_node = find_node_by_name(service_node, "setup_char");
    GDBusNodeInfo *cmd_char_node   = find_node_by_name(service_node, "cmd_char");
    GDBusNodeInfo *eng_char_node    = find_node_by_name(service_node, "eng_char");
    if (!setup_char_node || !cmd_char_node || !eng_char_node) {
        log_error("[%s] Characteristic nodes not found", LOG_TAG);
        pthread_exit(NULL);
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
        log_error("[%s] Failed to register ObjectManager interface: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
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
        log_error("[%s] Failed to register service object: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 5: Register your setup characteristic
    setup_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/setup_char",
        setup_char_node->interfaces[0],  // org.bluez.GattCharacteristic1
        &setup_char_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !setup_char_reg_id) {
        log_error("[%s] Failed to register setup characteristic object: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 6: Register your command characteristic
    cmd_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/cmd_char",
        cmd_char_node->interfaces[0],   // org.bluez.GattCharacteristic1
        &cmd_char_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !cmd_char_reg_id) {
        log_error("[%s] Failed to register command characteristic object: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 7: Register the engineering characteristic
    eng_char_reg_id = g_dbus_connection_register_object(
        connection,
        "/com/feralfile/display/service0/eng_char",
        eng_char_node->interfaces[0],
        &eng_char_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !eng_char_reg_id) {
        log_error("[%s] Failed to register engineering characteristic object: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 8: Get the GattManager1 interface and store it
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
        log_error("[%s] Failed to get GattManager1: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 9: Register the application
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
        log_error("[%s] RegisterApplication failed: %s",
                  LOG_TAG,
                  error->message);
        g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 10: Parse advertisement XML
    char *adv_introspection_xml = g_strdup_printf(
        "<node>"
        "  <interface name='org.bluez.LEAdvertisement1'>"
        "    <method name='Release'/>"
        "    <property name='Type' type='s' access='read'/>"
        "    <property name='ServiceUUIDs' type='as' access='read'/>"
        "    <property name='LocalName' type='s' access='read'/>"
        "  </interface>"
        "</node>"
    );
    advertisement_introspection_data =
        g_dbus_node_info_new_for_xml(adv_introspection_xml, &error);
    g_free(adv_introspection_xml);
    if (!advertisement_introspection_data || error) {
        log_error("[%s] Failed to parse advertisement XML: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error)
            g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 11: Register advertisement object
    ad_reg_id = g_dbus_connection_register_object(
        connection,
        advertisement_path,
        advertisement_introspection_data->interfaces[0],
        &advertisement_vtable,
        NULL,
        NULL,
        &error
    );
    if (error || !ad_reg_id) {
        log_error("[%s] Failed to register advertisement object: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error)
            g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 12: Get LEAdvertisingManager1 and store it
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
        log_error("[%s] Failed to get LEAdvertisingManager1: %s",
                  LOG_TAG,
                  error ? error->message : "Unknown error");
        if (error)
            g_error_free(error);
        pthread_exit(NULL);
    }

    // Step 13: Register the advertisement
    g_dbus_proxy_call_sync(
        advertising_manager,
        "RegisterAdvertisement",
        g_variant_new("(oa{sv})", advertisement_path, NULL),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    if (error) {
        log_error("[%s] Advertisement registration failed: %s",
                  LOG_TAG,
                  error->message);
        g_error_free(error);
        pthread_exit(NULL);
    }

    log_info("[%s] Bluetooth initialized successfully", LOG_TAG);

    // Run the main loop to process D-Bus events
    g_main_loop_run(main_loop);

    pthread_exit(NULL);
    return NULL;
}

int bluetooth_init(const char* custom_device_name) {
    log_info("[%s] Initializing Bluetooth in background thread", LOG_TAG);
    
    // Set custom device name if provided
    if (custom_device_name != NULL) {
        strncpy(device_name, custom_device_name, MAX_DEVICE_NAME_LENGTH - 1);
        device_name[MAX_DEVICE_NAME_LENGTH - 1] = '\0';
    }
    
    // Initialize Sentry if DSN is defined
    #ifdef SENTRY_DSN
    if (!sentry_initialized) {        
        sentry_options_t* options = sentry_options_new();
        sentry_options_set_dsn(options, SENTRY_DSN);
        
        #ifdef APP_VERSION
        log_info("[%s] Setting Sentry release to: %s", LOG_TAG, APP_VERSION);
        sentry_options_set_release(options, APP_VERSION);
        #else
        log_info("[%s] No APP_VERSION defined, not setting release", LOG_TAG);
        #endif
        
        // Set environment
        #ifdef DEBUG
        log_info("[%s] Setting Sentry environment to: development", LOG_TAG);
        sentry_options_set_environment(options, "development");
        sentry_options_set_debug(options, 1);
        #else
        log_info("[%s] Setting Sentry environment to: production", LOG_TAG);
        sentry_options_set_environment(options, "production");
        #endif
        
        // Create a temporary directory for Sentry database
        char db_path[256];
        snprintf(db_path, sizeof(db_path), "/tmp/sentry-native-%d", (int)time(NULL));
        log_info("[%s] Setting Sentry database path to: %s", LOG_TAG, db_path);
        sentry_options_set_database_path(options, db_path);
        
        int init_result = sentry_init(options);
        if (init_result == 0) {
            sentry_initialized = 1;
            
            // Set tags
            log_info("[%s] Setting Sentry tags", LOG_TAG);
            sentry_set_tag("service", "bluetooth");
            sentry_set_tag("device_name", device_name);
            
            // Add initial breadcrumb
            sentry_value_t crumb = sentry_value_new_breadcrumb("default", "Bluetooth service initialized");
            sentry_add_breadcrumb(crumb);
            
            log_info("[%s] Sentry initialized successfully", LOG_TAG);
        } else {
            log_error("[%s] Failed to initialize Sentry, error code: %d", LOG_TAG, init_result);
        }
    }
    #else
    log_info("[%s] Sentry DSN not defined, skipping initialization", LOG_TAG);
    #endif
    
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_thread_func, NULL) != 0) {
        log_error("[%s] Failed to create Bluetooth thread", LOG_TAG);
        return -1;
    }

    // Start background threads
    start_log_thread();
    start_callback_thread();
    start_notify_thread();
    
    return 0;
}

int bluetooth_start(connection_result_callback scb, command_callback ccb) {
    result_callback = scb;
    cmd_callback = ccb;
    log_info("[%s] Bluetooth service started", LOG_TAG);
    return 0;
}

void bluetooth_stop() {
    log_info("[%s] Stopping Bluetooth...", LOG_TAG);
    
    GError *error = NULL;

    // 1) Unregister the advertisement
    if (advertising_manager) {
        g_dbus_proxy_call_sync(
            advertising_manager,
            "UnregisterAdvertisement",
            g_variant_new("(o)", advertisement_path),
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            NULL,
            &error
        );
        if (error) {
            log_error("[%s] UnregisterAdvertisement failed: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        g_object_unref(advertising_manager);
        advertising_manager = NULL;
    }

    // 2) Unregister the GATT application
    if (gatt_manager) {
        g_dbus_proxy_call_sync(
            gatt_manager,
            "UnregisterApplication",
            g_variant_new("(o)", "/com/feralfile/display"),
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            NULL,
            &error
        );
        if (error) {
            log_error("[%s] UnregisterApplication failed: %s",
                      LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        // Free the GATT manager proxy
        g_object_unref(gatt_manager);
        gatt_manager = NULL;
    }

    // 3) Unregister all D-Bus objects (in the opposite order, or any order)
    if (ad_reg_id) {
        g_dbus_connection_unregister_object(connection, ad_reg_id);
        ad_reg_id = 0;
    }
    if (eng_char_reg_id) {
        g_dbus_connection_unregister_object(connection, eng_char_reg_id);
        eng_char_reg_id = 0;
    }
    if (cmd_char_reg_id) {
        g_dbus_connection_unregister_object(connection, cmd_char_reg_id);
        cmd_char_reg_id = 0;
    }
    if (setup_char_reg_id) {
        g_dbus_connection_unregister_object(connection, setup_char_reg_id);
        setup_char_reg_id = 0;
    }
    if (service_reg_id) {
        g_dbus_connection_unregister_object(connection, service_reg_id);
        service_reg_id = 0;
    }
    if (objects_reg_id) {
        g_dbus_connection_unregister_object(connection, objects_reg_id);
        objects_reg_id = 0;
    }

    // 4) Stop the main loop and join the thread
    if (main_loop) {
        g_main_loop_quit(main_loop);
    }
    pthread_join(bluetooth_thread, NULL);

    if (main_loop) {
        g_main_loop_unref(main_loop);
        main_loop = NULL;
    }

    // 5) Clean up node infos
    if (root_node) {
        g_dbus_node_info_unref(root_node);
        root_node = NULL;
    }
    if (advertisement_introspection_data) {
        g_dbus_node_info_unref(advertisement_introspection_data);
        advertisement_introspection_data = NULL;
    }

    if (connection) {
        g_object_unref(connection);
        connection = NULL;
    }

    // Close Sentry at the end
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        log_info("[%s] Closing Sentry", LOG_TAG);
        sentry_close();
        sentry_initialized = 0;
        log_info("[%s] Sentry closed successfully", LOG_TAG);
    }
    #endif

    // Stop background threads
    stop_notify_thread();
    stop_callback_thread();
    stop_log_thread();

    log_info("[%s] Bluetooth service stopped", LOG_TAG);
}

void bluetooth_notify(const unsigned char* data, int length) {
    // Create a copy of the data
    unsigned char* data_copy = malloc(length);
    if (!data_copy) {
        log_error("[%s] Failed to allocate memory for notification data", LOG_TAG);
        return;
    }
    memcpy(data_copy, data, length);
    
    // Queue the notification
    pthread_mutex_lock(&notify_mutex);
    if ((notify_queue_head + 1) % NOTIFY_QUEUE_SIZE != notify_queue_tail) {
        NotifyData *notify = &notify_queue[notify_queue_head];
        notify->data = data_copy;
        notify->length = length;
        notify->type = 0;  // command characteristic
        notify_queue_head = (notify_queue_head + 1) % NOTIFY_QUEUE_SIZE;
        pthread_cond_signal(&notify_cond);
    } else {
        // Queue full, handle error
        free(data_copy);
        log_error("[%s] Notification queue full, dropping message", LOG_TAG);
    }
    pthread_mutex_unlock(&notify_mutex);
    
    // Log still happens in the calling thread
    // Log the hex string for debugging
    char hex_string[length * 3 + 1];
    for (size_t i = 0; i < length; i++) {
        sprintf(hex_string + (i * 3), "%02x ", data[i]);
    }
    hex_string[length * 3 - 1] = '\0';
    log_info("[%s] Notifying data: %s", LOG_TAG, hex_string);
}

const char* bluetooth_get_mac_address() {
    static char mac_address[18] = {0};
    int dev_id = hci_get_route(NULL);
    int sock = hci_open_dev(dev_id);
    
    if (dev_id < 0 || sock < 0) {
        log_error("[%s] Could not get Bluetooth device info (dev_id=%d, sock=%d)", 
                 LOG_TAG, dev_id, sock);
        return NULL;
    }

    bdaddr_t bdaddr;
    if (hci_read_bd_addr(sock, &bdaddr, 1000) < 0) {
        log_error("[%s] Could not read Bluetooth address", LOG_TAG);
        close(sock);
        return NULL;
    }
    
    ba2str(&bdaddr, mac_address);
    close(sock);
    
    log_info("[%s] Bluetooth MAC address: %s", LOG_TAG, mac_address);
    return mac_address;
}

void bluetooth_free_data(unsigned char* data) {
    if (data != NULL) {
        free(data);
    }
}

void bluetooth_send_engineering_data(const unsigned char* data, int length) {
    if (!connection) {
        log_error("[%s] Cannot send engineering data: not connected", LOG_TAG);
        return;
    }

    // Log the hex string for debugging
    char hex_string[length * 3 + 1];
    for (size_t i = 0; i < length; i++) {
        sprintf(hex_string + (i * 3), "%02x ", data[i]);
    }
    hex_string[length * 3 - 1] = '\0';
    log_info("[%s] Sending engineering data: %s", LOG_TAG, hex_string);

    // Create GVariant for the notification value
    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                              data, length, sizeof(guchar));

    // Emit PropertiesChanged signal
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
    g_variant_builder_add(builder, "{sv}", "Value", value);

    g_dbus_connection_emit_signal(connection,
        NULL,
        "/com/feralfile/display/service0/eng_char",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        g_variant_new("(sa{sv}as)",
                     "org.bluez.GattCharacteristic1",
                     builder,
                     NULL),
        NULL);

    g_variant_builder_unref(builder);
}

static void* callback_thread_func(void* arg) {
    while (callback_thread_running) {
        CallbackData data;
        int type;
        int have_data = 0;
        
        // Get data from queue
        pthread_mutex_lock(&callback_mutex);
        if (callback_queue_head != callback_queue_tail) {
            data = callback_queue[callback_queue_tail];
            type = callback_type_queue[callback_queue_tail];
            callback_queue_tail = (callback_queue_tail + 1) % CALLBACK_QUEUE_SIZE;
            have_data = 1;
        } else {
            // Wait for new data
            pthread_cond_wait(&callback_cond, &callback_mutex);
        }
        pthread_mutex_unlock(&callback_mutex);
        
        if (have_data) {
            if (type == 0 && result_callback) {
                result_callback(data.success, data.data, data.length);
            } else if (type == 1 && cmd_callback) {
                cmd_callback(data.success, data.data, data.length);
            }
            
            // No need to free data here as it's managed by the caller
        }
    }
    return NULL;
}

static void start_callback_thread() {
    callback_thread_running = 1;
    pthread_create(&callback_thread, NULL, callback_thread_func, NULL);
}

static void stop_callback_thread() {
    callback_thread_running = 0;
    pthread_cond_signal(&callback_cond);  // Wake up the thread
    pthread_join(callback_thread, NULL);
}

static void* notify_thread_func(void* arg) {
    while (notify_thread_running) {
        NotifyData data;
        int have_data = 0;
        
        // Get data from queue
        pthread_mutex_lock(&notify_mutex);
        if (notify_queue_head != notify_queue_tail) {
            data = notify_queue[notify_queue_tail];
            notify_queue_tail = (notify_queue_tail + 1) % NOTIFY_QUEUE_SIZE;
            have_data = 1;
        } else {
            // Wait for new data
            pthread_cond_wait(&notify_cond, &notify_mutex);
        }
        pthread_mutex_unlock(&notify_mutex);
        
        if (have_data) {
            // Process notification
            const char* path = (data.type == 0) ? 
                "/com/feralfile/display/service0/cmd_char" : 
                "/com/feralfile/display/service0/eng_char";
                
            // Create GVariant for the notification value
            GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                                       data.data, data.length, sizeof(guchar));

            // Emit PropertiesChanged signal
            GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
            g_variant_builder_add(builder, "{sv}", "Value", value);

            g_dbus_connection_emit_signal(connection,
                NULL,
                path,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                g_variant_new("(sa{sv}as)",
                             "org.bluez.GattCharacteristic1",
                             builder,
                             NULL),
                NULL);

            g_variant_builder_unref(builder);
            free(data.data);  // Free the copied data
        }
    }
    return NULL;
}

static void start_notify_thread() {
    notify_thread_running = 1;
    pthread_create(&notify_thread, NULL, notify_thread_func, NULL);
}

static void stop_notify_thread() {
    notify_thread_running = 0;
    pthread_cond_signal(&notify_cond);  // Wake up the thread
    pthread_join(notify_thread, NULL);
}