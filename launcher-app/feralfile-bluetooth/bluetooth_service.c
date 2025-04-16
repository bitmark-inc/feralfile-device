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
#include <errno.h>
#include <unistd.h>

#define LOG_TAG "BluetoothService"
#define FERALFILE_SERVICE_NAME   "FeralFile Device"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_SETUP_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_CMD_CHAR_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_ENG_CHAR_UUID "6e400004-b5a3-f393-e0a9-e50e24dcca9e"
#define MAX_DEVICE_NAME_LENGTH 32
#define MAX_ADV_PATH_LENGTH 64
#define MAX_RETRY_ATTEMPTS 5
#define RETRY_DELAY_SECONDS 2
#define DBUS_TIMEOUT_MS 5000

static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;
static GDBusNodeInfo *root_node = NULL;
static GDBusNodeInfo *service_node = NULL;
static GDBusNodeInfo *advertisement_introspection_data = NULL;
static GDBusNodeInfo *agent_node_info = NULL;

static guint objects_reg_id = 0;
static guint service_reg_id = 0;
static guint setup_char_reg_id = 0;
static guint cmd_char_reg_id = 0;
static guint ad_reg_id = 0;
static guint eng_char_reg_id = 0;
static guint agent_registration_id = 0;

static GDBusProxy *gatt_manager = NULL;
static GDBusProxy *advertising_manager = NULL;
static GDBusProxy *agent_manager = NULL;

static pthread_t bluetooth_thread;
static pthread_mutex_t callback_mutex = PTHREAD_MUTEX_INITIALIZER;

typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
typedef void (*command_callback)(int success, const unsigned char* data, int length);
typedef void (*device_connection_callback)(const char* device_id, int connected);

static connection_result_callback result_callback = NULL;
static command_callback cmd_callback = NULL;
static device_connection_callback connection_callback = NULL;

static FILE* log_file = NULL;
static char device_name[MAX_DEVICE_NAME_LENGTH] = FERALFILE_SERVICE_NAME;
static char advertisement_path[MAX_ADV_PATH_LENGTH] = "/com/feralfile/display/advertisement0";
static int sentry_initialized = 0;

static void safe_free(void **ptr) {
    if (ptr && *ptr) {
        free(*ptr);
        *ptr = NULL;
    }
}

static void bluetooth_set_logfile(const char* path) {
    if (!path) return;
    pthread_mutex_lock(&callback_mutex);
    if (log_file) {
        fclose(log_file);
        log_file = NULL;
    }
    log_file = fopen(path, "a");
    if (!log_file) {
        syslog(LOG_ERR, "[%s] Failed to open log file: %s", LOG_TAG, strerror(errno));
    }
    pthread_mutex_unlock(&callback_mutex);
}

static void log_message(int level, const char* format, va_list ap) {
    va_list ap_syslog, ap_stdout, ap_file, ap_sentry;
    va_copy(ap_syslog, ap);
    va_copy(ap_stdout, ap);
    va_copy(ap_file, ap);
    va_copy(ap_sentry, ap);

    char timestamp[26];
    time_t now = time(NULL);
    ctime_r(&now, timestamp);
    timestamp[24] = '\0';

    vsyslog(level, format, ap_syslog);

    FILE *output = (level == LOG_ERR || level == LOG_WARNING) ? stderr : stdout;
    fprintf(output, "%s: %s: ", timestamp, level == LOG_ERR ? "ERROR" : level == LOG_WARNING ? "WARNING" : "INFO");
    vfprintf(output, format, ap_stdout);
    fprintf(output, "\n");
    fflush(output);

    pthread_mutex_lock(&callback_mutex);
    if (log_file) {
        fprintf(log_file, "%s: %s: ", timestamp, level == LOG_ERR ? "ERROR" : level == LOG_WARNING ? "WARNING" : "INFO");
        vfprintf(log_file, format, ap_file);
        fprintf(log_file, "\n");
        fflush(log_file);
    }
    pthread_mutex_unlock(&callback_mutex);

#ifdef SENTRY_DSN
    if (sentry_initialized) {
        char message[1024];
        vsnprintf(message, sizeof(message), format, ap_sentry);
        if (level == LOG_ERR) {
            sentry_value_t event = sentry_value_new_message_event(SENTRY_LEVEL_ERROR, "bluetooth", message);
            sentry_capture_event(event);
        } else {
            sentry_value_t crumb = sentry_value_new_breadcrumb(level == LOG_WARNING ? "warning" : "info", message);
            sentry_value_set_by_key(crumb, "category", sentry_value_new_string("bluetooth"));
            sentry_add_breadcrumb(crumb);
        }
    }
#endif

    va_end(ap_sentry);
    va_end(ap_file);
    va_end(ap_stdout);
    va_end(ap_syslog);
}

static void log_info(const char* format, ...) {
    va_list ap;
    va_start(ap, format);
    log_message(LOG_INFO, format, ap);
    va_end(ap);
}

static void log_error(const char* format, ...) {
    va_list ap;
    va_start(ap, format);
    log_message(LOG_ERR, format, ap);
    va_end(ap);
}

static void log_warning(const char* format, ...) {
    va_list ap;
    va_start(ap, format);
    log_message(LOG_WARNING, format, ap);
    va_end(ap);
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

static const gchar agent_introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.Agent1'>"
    "    <method name='Release'/>"
    "    <method name='RequestPinCode'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='pincode' type='s' direction='out'/>"
    "    </method>"
    "    <method name='DisplayPinCode'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='pincode' type='s' direction='in'/>"
    "    </method>"
    "    <method name='RequestPasskey'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='passkey' type='u' direction='out'/>"
    "    </method>"
    "    <method name='DisplayPasskey'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='passkey' type='u' direction='in'/>"
    "      <arg name='entered' type='q' direction='in'/>"
    "    </method>"
    "    <method name='RequestConfirmation'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='passkey' type='u' direction='in'/>"
    "    </method>"
    "    <method name='RequestAuthorization'>"
    "      <arg name='device' type='o' direction='in'/>"
    "    </method>"
    "    <method name='AuthorizeService'>"
    "      <arg name='device' type='o' direction='in'/>"
    "      <arg name='uuid' type='s' direction='in'/>"
    "    </method>"
    "    <method name='Cancel'/>"
    "  </interface>"
    "</node>";

static GDBusNodeInfo* find_node_by_name(GDBusNodeInfo *parent, const gchar *name) {
    if (!parent || !name) return NULL;
    for (GDBusNodeInfo **nodes = parent->nodes; nodes && *nodes; nodes++) {
        if (g_strcmp0((*nodes)->path, name) == 0) {
            return *nodes;
        }
    }
    return NULL;
}

static void agent_method_call(GDBusConnection *conn,
                              const gchar *sender,
                              const gchar *object_path,
                              const gchar *interface_name,
                              const gchar *method_name,
                              GVariant *parameters,
                              GDBusMethodInvocation *invocation,
                              gpointer user_data) {
    const char *device = g_variant_get_string(g_variant_get_child_value(parameters, 0), NULL);
    if (!device) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.InvalidArguments", "Invalid device path");
        return;
    }

    if (g_strcmp0(method_name, "Release") == 0) {
        log_info("[%s] Agent Release for device %s", LOG_TAG, device);
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "RequestPinCode") == 0 || g_strcmp0(method_name, "RequestPasskey") == 0) {
        log_info("[%s] Agent %s for device %s", LOG_TAG, method_name, device);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Rejected", "NoInputNoOutput agent cannot provide credentials");
    } else if (g_strcmp0(method_name, "RequestConfirmation") == 0 || g_strcmp0(method_name, "AuthorizeService") == 0 ||
               g_strcmp0(method_name, "RequestAuthorization") == 0) {
        log_info("[%s] Agent %s for device %s", LOG_TAG, method_name, device);
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "Cancel") == 0) {
        log_info("[%s] Agent Cancel for device %s", LOG_TAG, device);
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "DisplayPinCode") == 0 || g_strcmp0(method_name, "DisplayPasskey") == 0) {
        log_info("[%s] Agent %s for device %s", LOG_TAG, method_name, device);
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else {
        log_warning("[%s] Agent method %s not supported for device %s", LOG_TAG, method_name, device);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.NotSupported", "Method not supported");
    }
}

static const GDBusInterfaceVTable agent_vtable = {
    .method_call = agent_method_call,
    .get_property = NULL,
    .set_property = NULL
};

static GVariant *service_get_property(GDBusConnection *conn,
                                     const gchar *sender,
                                     const gchar *object_path,
                                     const gchar *interface_name,
                                     const gchar *property_name,
                                     GError **error,
                                     gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattService1") != 0) return NULL;
    if (g_strcmp0(property_name, "UUID") == 0) {
        return g_variant_new_string(FERALFILE_SERVICE_UUID);
    } else if (g_strcmp0(property_name, "Primary") == 0) {
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
    if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") != 0) return NULL;
    if (g_strcmp0(property_name, "UUID") == 0) {
        if (strstr(object_path, "setup_char")) return g_variant_new_string(FERALFILE_SETUP_CHAR_UUID);
        if (strstr(object_path, "cmd_char")) return g_variant_new_string(FERALFILE_CMD_CHAR_UUID);
        if (strstr(object_path, "eng_char")) return g_variant_new_string(FERALFILE_ENG_CHAR_UUID);
    } else if (g_strcmp0(property_name, "Service") == 0) {
        return g_variant_new_object_path("/com/feralfile/display/service0");
    } else if (g_strcmp0(property_name, "Flags") == 0) {
        if (strstr(object_path, "cmd_char")) {
            const gchar* flags[] = {"write", "write-without-response", "notify", NULL};
            return g_variant_new_strv(flags, -1);
        } else if (strstr(object_path, "eng_char")) {
            const gchar* flags[] = {"notify", NULL};
            return g_variant_new_strv(flags, -1);
        } else {
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
    g_variant_get(parameters, "(@aya{sv})", &array_variant, &options_variant);

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));
    if (!data || n_elements == 0) {
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.InvalidArguments", "No data provided");
        return;
    }

    guchar *data_copy = malloc(n_elements);
    if (!data_copy) {
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Failed", "Memory allocation failed");
        return;
    }
    memcpy(data_copy, data, n_elements);

    char hex_string[n_elements * 3 + 1];
    for (size_t i = 0; i < n_elements; i++) {
        snprintf(hex_string + (i * 3), 4, "%02x ", data_copy[i]);
    }
    hex_string[n_elements * 3 - 1] = '\0';
    log_info("[%s] (setup_char) Received %zu bytes: %s", LOG_TAG, n_elements, hex_string);

    pthread_mutex_lock(&callback_mutex);
    if (result_callback) {
        result_callback(1, data_copy, (int)n_elements);
    } else {
        free(data_copy);
    }
    pthread_mutex_unlock(&callback_mutex);

#ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", "Received setup data");
        sentry_value_set_by_key(crumb, "data_length", sentry_value_new_int32((int32_t)n_elements));
        sentry_add_breadcrumb(crumb);
    }
#endif

    g_variant_unref(array_variant);
    if (options_variant) g_variant_unref(options_variant);
    g_dbus_method_invocation_return_value(invocation, NULL);
}

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
    if (!data || n_elements == 0) {
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.InvalidArguments", "No data provided");
        return;
    }

    guchar *data_copy = malloc(n_elements);
    if (!data_copy) {
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Failed", "Memory allocation failed");
        return;
    }
    memcpy(data_copy, data, n_elements);

    char hex_string[n_elements * 3 + 1];
    for (size_t i = 0; i < n_elements; i++) {
        snprintf(hex_string + (i * 3), 4, "%02x ", data_copy[i]);
    }
    hex_string[n_elements * 3 - 1] = '\0';
    log_info("[%s] (cmd_char) Received %zu bytes: %s", LOG_TAG, n_elements, hex_string);

    pthread_mutex_lock(&callback_mutex);
    if (cmd_callback) {
        cmd_callback(1, data_copy, (int)n_elements);
    } else {
        free(data_copy);
    }
    pthread_mutex_unlock(&callback_mutex);

#ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", "Received command data");
        sentry_value_set_by_key(crumb, "data_length", sentry_value_new_int32((int32_t)n_elements));
        sentry_add_breadcrumb(crumb);
    }
#endif

    g_variant_unref(array_variant);
    if (options_variant) g_variant_unref(options_variant);
    g_dbus_method_invocation_return_value(invocation, NULL);
}

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

static const GDBusInterfaceVTable eng_char_vtable = {
    .method_call = NULL,
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
    if (g_strcmp0(property_name, "Type") == 0) {
        return g_variant_new_string("peripheral");
    } else if (g_strcmp0(property_name, "ServiceUUIDs") == 0) {
        const gchar* uuids[] = {FERALFILE_SERVICE_UUID, NULL};
        return g_variant_new_strv(uuids, -1);
    } else if (g_strcmp0(property_name, "LocalName") == 0) {
        return g_variant_new_string(device_name);
    }
    return NULL;
}

static const GDBusInterfaceVTable advertisement_vtable = {
    .method_call = NULL,
    .get_property = advertisement_get_property,
    .set_property = NULL
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
    
    GVariantBuilder *service_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *service_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(service_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SERVICE_UUID));
    g_variant_builder_add(service_props, "{sv}", "Primary", g_variant_new_boolean(TRUE));
    g_variant_builder_add(service_builder, "{sa{sv}}", "org.bluez.GattService1", service_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0", service_builder);
    
    GVariantBuilder *setup_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *setup_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(setup_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SETUP_CHAR_UUID));
    g_variant_builder_add(setup_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* setup_flags[] = {"write", NULL};
    g_variant_builder_add(setup_char_props, "{sv}", "Flags", g_variant_new_strv(setup_flags, -1));
    g_variant_builder_add(setup_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", setup_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/setup_char", setup_char_builder);
    
    GVariantBuilder *cmd_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *cmd_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(cmd_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_CMD_CHAR_UUID));
    g_variant_builder_add(cmd_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* cmd_flags[] = {"write", "write-without-response", "notify", NULL};
    g_variant_builder_add(cmd_char_props, "{sv}", "Flags", g_variant_new_strv(cmd_flags, -1));
    g_variant_builder_add(cmd_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", cmd_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/cmd_char", cmd_char_builder);
    
    GVariantBuilder *eng_char_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    GVariantBuilder *eng_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(eng_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_ENG_CHAR_UUID));
    g_variant_builder_add(eng_char_props, "{sv}", "Service", g_variant_new_object_path("/com/feralfile/display/service0"));
    const gchar* eng_flags[] = {"notify", NULL};
    g_variant_builder_add(eng_char_props, "{sv}", "Flags", g_variant_new_strv(eng_flags, -1));
    g_variant_builder_add(eng_char_builder, "{sa{sv}}", "org.bluez.GattCharacteristic1", eng_char_props);
    g_variant_builder_add(builder, "{oa{sa{sv}}}", "/com/feralfile/display/service0/eng_char", eng_char_builder);
    
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", builder));
    
    g_variant_builder_unref(builder);
    g_variant_builder_unref(service_builder);
    g_variant_builder_unref(service_props);
    g_variant_builder_unref(setup_char_builder);
    g_variant_builder_unref(setup_char_props);
    g_variant_builder_unref(cmd_char_builder);
    g_variant_builder_unref(cmd_char_props);
    g_variant_builder_unref(eng_char_builder);
    g_variant_builder_unref(eng_char_props);
}

static const GDBusInterfaceVTable objects_vtable = {
    .method_call = handle_get_objects,
    .get_property = NULL,
    .set_property = NULL
};

static int is_bluetooth_service_active(void) {
    FILE *fp = popen("systemctl is-active bluetooth", "r");
    if (!fp) {
        log_error("[%s] Failed to check bluetooth service status: %s", LOG_TAG, strerror(errno));
        return 0;
    }

    char buffer[128];
    int active = 0;
    if (fgets(buffer, sizeof(buffer), fp)) {
        active = (strncmp(buffer, "active", 6) == 0);
    }
    pclose(fp);
    return active;
}

static int wait_for_bluetooth_service(void) {
    for (int attempts = 0; attempts < MAX_RETRY_ATTEMPTS; attempts++) {
        if (is_bluetooth_service_active()) {
            log_info("[%s] Bluetooth service is active", LOG_TAG);
            sleep(1); // Allow service to stabilize
            return 1;
        }
        log_info("[%s] Waiting for Bluetooth service (attempt %d/%d)", LOG_TAG, attempts + 1, MAX_RETRY_ATTEMPTS);
        sleep(RETRY_DELAY_SECONDS);
    }
    log_error("[%s] Bluetooth service not active after %d attempts", LOG_TAG, MAX_RETRY_ATTEMPTS);
    return 0;
}

static void handle_property_change(GDBusConnection *connection,
                                  const gchar *sender_name,
                                  const gchar *object_path,
                                  const gchar *interface_name,
                                  const gchar *signal_name,
                                  GVariant *parameters,
                                  gpointer user_data) {
    const gchar *interface;
    GVariant *changed_properties, *invalidated_properties;
    g_variant_get(parameters, "(&sa{sv}as)", &interface, &changed_properties, &invalidated_properties);

    if (g_str_equal(interface, "org.bluez.Device1")) {
        GVariantIter iter;
        const gchar *key;
        GVariant *value;
        g_variant_iter_init(&iter, changed_properties);
        while (g_variant_iter_next(&iter, "{&sv}", &key, &value)) {
            if (g_str_equal(key, "Connected")) {
                gboolean connected;
                g_variant_get(value, "b", &connected);
                const char *device_id = strrchr(object_path, '/');
                if (device_id) {
                    device_id++;
                    pthread_mutex_lock(&callback_mutex);
                    if (connection_callback) {
                        connection_callback(device_id, connected);
                    }
                    pthread_mutex_unlock(&callback_mutex);
                    log_info("[%s] Device %s %s", LOG_TAG, device_id, connected ? "connected" : "disconnected");
                }
            }
            g_variant_unref(value);
        }
    }

    g_variant_unref(changed_properties);
    g_variant_unref(invalidated_properties);
}

static void setup_dbus_signal_handlers(GDBusConnection *conn) {
    g_dbus_connection_signal_subscribe(
        conn,
        "org.bluez",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        NULL,
        "org.bluez.Device1",
        G_DBUS_SIGNAL_FLAGS_NONE,
        handle_property_change,
        NULL,
        NULL);
    log_info("[%s] D-Bus signal handlers set up", LOG_TAG);
}
static void cleanup_resources(void) {
    GError *error = NULL;

    if (agent_manager) {
        g_dbus_proxy_call_sync(agent_manager, "UnregisterAgent",
                               g_variant_new("(o)", "/com/feralfile/display/agent"),
                               G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (error) {
            log_error("[%s] UnregisterAgent failed: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        g_object_unref(agent_manager);
        agent_manager = NULL;
    }

    if (advertising_manager) {
        g_dbus_proxy_call_sync(advertising_manager, "UnregisterAdvertisement",
                               g_variant_new("(o)", advertisement_path),
                               G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (error) {
            log_error("[%s] UnregisterAdvertisement failed: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        g_object_unref(advertising_manager);
        advertising_manager = NULL;
    }

    if (gatt_manager) {
        g_dbus_proxy_call_sync(gatt_manager, "UnregisterApplication",
                               g_variant_new("(o)", "/com/feralfile/display"),
                               G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (error) {
            log_error("[%s] UnregisterApplication failed: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
        }
        g_object_unref(gatt_manager);
        gatt_manager = NULL;
    }

    if (connection) {
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
        if (agent_registration_id) {
            g_dbus_connection_unregister_object(connection, agent_registration_id);
            agent_registration_id = 0;
        }
        g_object_unref(connection);
        connection = NULL;
    }

    if (main_loop) {
        g_main_loop_quit(main_loop);
        g_main_loop_unref(main_loop);
        main_loop = NULL;
    }

    if (root_node) {
        g_dbus_node_info_unref(root_node);
        root_node = NULL;
    }
    if (advertisement_introspection_data) {
        g_dbus_node_info_unref(advertisement_introspection_data);
        advertisement_introspection_data = NULL;
    }
    if (agent_node_info) {
        g_dbus_node_info_unref(agent_node_info);
        agent_node_info = NULL;
    }
}

static void* bluetooth_thread_func(void* arg) {
    GError *error = NULL;
    int retry_count = 0;

    while (retry_count < MAX_RETRY_ATTEMPTS) {
        if (!is_bluetooth_service_active()) {
            log_warning("[%s] Bluetooth service not active, waiting...", LOG_TAG);
            if (!wait_for_bluetooth_service()) {
                log_error("[%s] Failed to wait for Bluetooth service", LOG_TAG);
                pthread_exit(NULL);
            }
        }

        main_loop = g_main_loop_new(NULL, FALSE);
        if (!main_loop) {
            log_error("[%s] Failed to create main loop", LOG_TAG);
            pthread_exit(NULL);
        }

        connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
        if (!connection) {
            log_error("[%s] Failed to connect to D-Bus: %s", LOG_TAG, error->message);
            g_error_free(error);
            g_main_loop_unref(main_loop);
            main_loop = NULL;
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }
        setup_dbus_signal_handlers(connection);

        root_node = g_dbus_node_info_new_for_xml(service_xml, &error);
        if (!root_node) {
            log_error("[%s] Failed to parse service XML: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        service_node = find_node_by_name(root_node, "service0");
        if (!service_node) {
            log_error("[%s] service0 node not found", LOG_TAG);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        GDBusNodeInfo *setup_char_node = find_node_by_name(service_node, "setup_char");
        GDBusNodeInfo *cmd_char_node = find_node_by_name(service_node, "cmd_char");
        GDBusNodeInfo *eng_char_node = find_node_by_name(service_node, "eng_char");
        if (!setup_char_node || !cmd_char_node || !eng_char_node) {
            log_error("[%s] Characteristic nodes not found", LOG_TAG);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        objects_reg_id = g_dbus_connection_register_object(connection, "/com/feralfile/display",
                                                           g_dbus_node_info_lookup_interface(root_node, "org.freedesktop.DBus.ObjectManager"),
                                                           &objects_vtable, NULL, NULL, &error);
        if (!objects_reg_id) {
            log_error("[%s] Failed to register ObjectManager: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        service_reg_id = g_dbus_connection_register_object(connection, "/com/feralfile/display/service0",
                                                           service_node->interfaces[0], &service_vtable, NULL, NULL, &error);
        if (!service_reg_id) {
            log_error("[%s] Failed to register service object: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        agent_node_info = g_dbus_node_info_new_for_xml(agent_introspection_xml, &error);
        if (!agent_node_info) {
            log_error("[%s] Failed to parse agent XML: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        agent_registration_id = g_dbus_connection_register_object(connection, "/com/feralfile/display/agent",
                                                                  agent_node_info->interfaces[0], &agent_vtable, NULL, NULL, &error);
        if (!agent_registration_id) {
            log_error("[%s] Failed to register agent object: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        agent_manager = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                             "org.bluez", "/org/bluez", "org.bluez.AgentManager1", NULL, &error);
        if (!agent_manager) {
            log_error("[%s] Failed to get AgentManager1: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        GVariant *result = g_dbus_proxy_call_sync(agent_manager, "RegisterAgent",
                                                  g_variant_new("(os)", "/com/feralfile/display/agent", "NoInputNoOutput"),
                                                  G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (!result) {
            log_error("[%s] RegisterAgent failed: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }
        g_variant_unref(result);

        result = g_dbus_proxy_call_sync(agent_manager, "RequestDefaultAgent",
                                        g_variant_new("(o)", "/com/feralfile/display/agent"),
                                        G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (!result) {
            log_error("[%s] RequestDefaultAgent failed: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }
        g_variant_unref(result);

        setup_char_reg_id = g_dbus_connection_register_object(connection, "/com/feralfile/display/service0/setup_char",
                                                              setup_char_node->interfaces[0], &setup_char_vtable, NULL, NULL, &error);
        if (!setup_char_reg_id) {
            log_error("[%s] Failed to register setup characteristic: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        cmd_char_reg_id = g_dbus_connection_register_object(connection, "/com/feralfile/display/service0/cmd_char",
                                                            cmd_char_node->interfaces[0], &cmd_char_vtable, NULL, NULL, &error);
        if (!cmd_char_reg_id) {
            log_error("[%s] Failed to register command characteristic: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        eng_char_reg_id = g_dbus_connection_register_object(connection, "/com/feralfile/display/service0/eng_char",
                                                            eng_char_node->interfaces[0], &eng_char_vtable, NULL, NULL, &error);
        if (!eng_char_reg_id) {
            log_error("[%s] Failed to register engineering characteristic: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        gatt_manager = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                             "org.bluez", "/org/bluez/hci0", "org.bluez.GattManager1", NULL, &error);
        if (!gatt_manager) {
            log_error("[%s] Failed to get GattManager1: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        result = g_dbus_proxy_call_sync(gatt_manager, "RegisterApplication",
                                        g_variant_new("(oa{sv})", "/com/feralfile/display", NULL),
                                        G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (!result) {
            log_error("[%s] RegisterApplication failed: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }
        g_variant_unref(result);

        char *adv_introspection_xml = g_strdup(
            "<node>"
            "  <interface name='org.bluez.LEAdvertisement1'>"
            "    <method name='Release'/>"
            "    <property name='Type' type='s' access='read'/>"
            "    <property name='ServiceUUIDs' type='as' access='read'/>"
            "    <property name='LocalName' type='s' access='read'/>"
            "  </interface>"
            "</node>");
        if (!adv_introspection_xml) {
            log_error("[%s] Failed to allocate advertisement XML", LOG_TAG);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        advertisement_introspection_data = g_dbus_node_info_new_for_xml(adv_introspection_xml, &error);
        g_free(adv_introspection_xml);
        if (!advertisement_introspection_data) {
            log_error("[%s] Failed to parse advertisement XML: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        ad_reg_id = g_dbus_connection_register_object(connection, advertisement_path,
                                                      advertisement_introspection_data->interfaces[0],
                                                      &advertisement_vtable, NULL, NULL, &error);
        if (!ad_reg_id) {
            log_error("[%s] Failed to register advertisement object: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        advertising_manager = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                                    "org.bluez", "/org/bluez/hci0", "org.bluez.LEAdvertisingManager1", NULL, &error);
        if (!advertising_manager) {
            log_error("[%s] Failed to get LEAdvertisingManager1: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }

        result = g_dbus_proxy_call_sync(advertising_manager, "RegisterAdvertisement",
                                        g_variant_new("(oa{sv})", advertisement_path, NULL),
                                        G_DBUS_CALL_FLAGS_NONE, DBUS_TIMEOUT_MS, NULL, &error);
        if (!result) {
            log_error("[%s] RegisterAdvertisement failed: %s", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            cleanup_resources();
            retry_count++;
            sleep(RETRY_DELAY_SECONDS);
            continue;
        }
        g_variant_unref(result);

        log_info("[%s] Bluetooth initialized successfully", LOG_TAG);
        retry_count = 0;
        g_main_loop_run(main_loop);
        log_warning("[%s] Main loop exited, cleaning up", LOG_TAG);
        cleanup_resources();

        if (is_bluetooth_service_active()) {
            break;
        }
        retry_count++;
        if (retry_count < MAX_RETRY_ATTEMPTS) {
            log_info("[%s] Retrying initialization (attempt %d/%d)", LOG_TAG, retry_count + 1, MAX_RETRY_ATTEMPTS);
            sleep(RETRY_DELAY_SECONDS);
        }
    }

    log_error("[%s] Bluetooth thread exiting after %d retries", LOG_TAG, MAX_RETRY_ATTEMPTS);
    pthread_exit(NULL);
    return NULL;
}

int bluetooth_init(const char* custom_device_name) {
    log_info("[%s] Initializing Bluetooth", LOG_TAG);

    if (!is_bluetooth_service_active()) {
        log_warning("[%s] Bluetooth service not active, waiting...", LOG_TAG);
        if (!wait_for_bluetooth_service()) {
            log_error("[%s] Failed to wait for Bluetooth service", LOG_TAG);
            return -1;
        }
    }

    if (custom_device_name) {
        strncpy(device_name, custom_device_name, MAX_DEVICE_NAME_LENGTH - 1);
        device_name[MAX_DEVICE_NAME_LENGTH - 1] = '\0';
    }

#ifdef SENTRY_DSN
    if (!sentry_initialized) {
        sentry_options_t* options = sentry_options_new();
        if (!options) {
            log_error("[%s] Failed to create Sentry options", LOG_TAG);
            return -1;
        }
        sentry_options_set_dsn(options, SENTRY_DSN);

#ifdef APP_VERSION
        log_info("[%s] Setting Sentry release: %s", LOG_TAG, APP_VERSION);
        sentry_options_set_release(options, APP_VERSION);
#endif

#ifdef DEBUG
        log_info("[%s] Setting Sentry environment: development", LOG_TAG);
        sentry_options_set_environment(options, "development");
        sentry_options_set_debug(options, 1);
#else
        log_info("[%s] Setting Sentry environment: production", LOG_TAG);
        sentry_options_set_environment(options, "production");
#endif

        char db_path[256];
        snprintf(db_path, sizeof(db_path), "/tmp/sentry-native-%d", (int)time(NULL));
        log_info("[%s] Setting Sentry database path: %s", LOG_TAG, db_path);
        sentry_options_set_database_path(options, db_path);

        if (sentry_init(options) == 0) {
            sentry_initialized = 1;
            sentry_set_tag("service", "bluetooth");
            sentry_set_tag("device_name", device_name);
            sentry_value_t crumb = sentry_value_new_breadcrumb("default", "Bluetooth service initialized");
            sentry_add_breadcrumb(crumb);
            log_info("[%s] Sentry initialized successfully", LOG_TAG);
        } else {
            log_error("[%s] Failed to initialize Sentry", LOG_TAG);
            sentry_options_free(options);
            return -1;
        }
    }
#else
    log_info("[%s] Sentry DSN not defined, skipping initialization", LOG_TAG);
#endif

    if (pthread_create(&bluetooth_thread, NULL, bluetooth_thread_func, NULL) != 0) {
        log_error("[%s] Failed to create Bluetooth thread: %s", LOG_TAG, strerror(errno));
#ifdef SENTRY_DSN
        if (sentry_initialized) {
            sentry_close();
            sentry_initialized = 0;
        }
#endif
        return -1;
    }

    return 0;
}

int bluetooth_start(connection_result_callback scb, command_callback ccb, device_connection_callback dcb) {
    pthread_mutex_lock(&callback_mutex);
    result_callback = scb;
    cmd_callback = ccb;
    connection_callback = dcb;
    pthread_mutex_unlock(&callback_mutex);
    log_info("[%s] Bluetooth service started", LOG_TAG);
    return 0;
}

void bluetooth_stop(void) {
    log_info("[%s] Stopping Bluetooth service", LOG_TAG);

    cleanup_resources();

    if (bluetooth_thread) {
        pthread_join(bluetooth_thread, NULL);
        bluetooth_thread = 0;
    }

    pthread_mutex_lock(&callback_mutex);
    result_callback = NULL;
    cmd_callback = NULL;
    connection_callback = NULL;
    if (log_file) {
        fclose(log_file);
        log_file = NULL;
    }
    pthread_mutex_unlock(&callback_mutex);

#ifdef SENTRY_DSN
    if (sentry_initialized) {
        log_info("[%s] Closing Sentry", LOG_TAG);
        sentry_close();
        sentry_initialized = 0;
    }
#endif

    pthread_mutex_destroy(&callback_mutex);
    log_info("[%s] Bluetooth service stopped", LOG_TAG);
}

void bluetooth_notify(const unsigned char* data, int length) {
    if (!connection || !data || length <= 0) {
        log_error("[%s] Cannot notify: invalid state or data", LOG_TAG);
        return;
    }

    char hex_string[length * 3 + 1];
    for (int i = 0; i < length; i++) {
        snprintf(hex_string + (i * 3), 4, "%02x ", data[i]);
    }
    hex_string[length * 3 - 1] = '\0';
    log_info("[%s] Notifying data: %s", LOG_TAG, hex_string);

    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, data, length, sizeof(guchar));
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
    g_variant_builder_add(builder, "{sv}", "Value", value);

    g_dbus_connection_emit_signal(connection, NULL, "/com/feralfile/display/service0/cmd_char",
                                  "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  g_variant_new("(sa{sv}as)", "org.bluez.GattCharacteristic1", builder, NULL),
                                  NULL);

    g_variant_builder_unref(builder);
}

const char* bluetooth_get_mac_address(void) {
    static char mac_address[18] = {0};
    int dev_id = hci_get_route(NULL);
    int sock = hci_open_dev(dev_id);

    if (dev_id < 0 || sock < 0) {
        log_error("[%s] Failed to get Bluetooth device: dev_id=%d, sock=%d", LOG_TAG, dev_id, sock);
        return NULL;
    }

    bdaddr_t bdaddr;
    if (hci_read_bd_addr(sock, &bdaddr, 1000) < 0) {
        log_error("[%s] Failed to read Bluetooth address: %s", LOG_TAG, strerror(errno));
        close(sock);
        return NULL;
    }

    ba2str(&bdaddr, mac_address);
    close(sock);
    log_info("[%s] Bluetooth MAC address: %s", LOG_TAG, mac_address);
    return mac_address;
}

void bluetooth_free_data(unsigned char* data) {
    safe_free((void**)&data);
}

void bluetooth_send_engineering_data(const unsigned char* data, int length) {
    if (!connection || !data || length <= 0) {
        log_error("[%s] Cannot send engineering data: invalid state or data", LOG_TAG);
        return;
    }

    char hex_string[length * 3 + 1];
    for (int i = 0; i < length; i++) {
        snprintf(hex_string + (i * 3), 4, "%02x ", data[i]);
    }
    hex_string[length * 3 - 1] = '\0';
    log_info("[%s] Sending engineering data: %s", LOG_TAG, hex_string);

    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, data, length, sizeof(guchar));
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
    g_variant_builder_add(builder, "{sv}", "Value", value);

    g_dbus_connection_emit_signal(connection, NULL, "/com/feralfile/display/service0/eng_char",
                                  "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  g_variant_new("(sa{sv}as)", "org.bluez.GattCharacteristic1", builder, NULL),
                                  NULL);

    g_variant_builder_unref(builder);
}