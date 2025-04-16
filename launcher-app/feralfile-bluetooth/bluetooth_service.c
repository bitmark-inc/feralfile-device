#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <syslog.h>
#include <stdarg.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <stdbool.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <sentry.h>

#define LOG_TAG "BluetoothService"
#define FERALFILE_SERVICE_NAME      "FeralFile Device"
#define FERALFILE_SERVICE_UUID      "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_SETUP_CHAR_UUID   "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_CMD_CHAR_UUID     "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define FERALFILE_ENG_CHAR_UUID     "6e400004-b5a3-f393-e0a9-e50e24dcca9e"

#define MAX_DEVICE_NAME_LENGTH 32
#define MAX_ADV_PATH_LENGTH 64
#define MAX_RETRY_ATTEMPTS 5
#define RETRY_DELAY_SECONDS 2
#define MAC_ADDRESS_STR_LEN 18 // XX:XX:XX:XX:XX:XX\0

// D-Bus object paths
#define FERALFILE_DBUS_BASE_PATH "/com/feralfile/display"
#define FERALFILE_DBUS_SERVICE_PATH FERALFILE_DBUS_BASE_PATH "/service0"
#define FERALFILE_DBUS_SETUP_CHAR_PATH FERALFILE_DBUS_SERVICE_PATH "/setup_char"
#define FERALFILE_DBUS_CMD_CHAR_PATH FERALFILE_DBUS_SERVICE_PATH "/cmd_char"
#define FERALFILE_DBUS_ENG_CHAR_PATH FERALFILE_DBUS_SERVICE_PATH "/eng_char"
#define FERALFILE_DBUS_AGENT_PATH FERALFILE_DBUS_BASE_PATH "/agent"
#define FERALFILE_DBUS_ADVERTISEMENT_PATH FERALFILE_DBUS_BASE_PATH "/advertisement0"

// Bluez D-Bus definitions
#define BLUEZ_DBUS_SERVICE "org.bluez"
#define BLUEZ_DBUS_PATH "/org/bluez"
// NOTE: Hardcoding hci0 might not be robust if multiple adapters exist or the primary isn't hci0.
// A more robust solution would dynamically find the adapter path.
#define BLUEZ_DBUS_ADAPTER_PATH BLUEZ_DBUS_PATH "/hci0"
#define BLUEZ_INTF_GATT_MANAGER "org.bluez.GattManager1"
#define BLUEZ_INTF_LE_ADVERTISING_MANAGER "org.bluez.LEAdvertisingManager1"
#define BLUEZ_INTF_AGENT_MANAGER "org.bluez.AgentManager1"
#define BLUEZ_INTF_GATT_SERVICE "org.bluez.GattService1"
#define BLUEZ_INTF_GATT_CHARACTERISTIC "org.bluez.GattCharacteristic1"
#define BLUEZ_INTF_LE_ADVERTISEMENT "org.bluez.LEAdvertisement1"
#define BLUEZ_INTF_DEVICE "org.bluez.Device1"
#define BLUEZ_INTF_AGENT "org.bluez.Agent1"
#define DBUS_INTF_OBJECT_MANAGER "org.freedesktop.DBus.ObjectManager"
#define DBUS_INTF_PROPERTIES "org.freedesktop.DBus.Properties"

// --- Global Variables ---
static GMainLoop *main_loop = NULL;
static GDBusConnection *connection = NULL;
static GDBusNodeInfo *root_node_info = NULL; // Renamed for clarity
static GDBusNodeInfo *advertisement_introspection_data = NULL;
static GDBusNodeInfo *agent_introspection_data = NULL; // Renamed for clarity

static guint objects_reg_id = 0;
static guint service_reg_id = 0;
static guint setup_char_reg_id = 0;
static guint cmd_char_reg_id = 0;
static guint eng_char_reg_id = 0;
static guint ad_reg_id = 0;
static guint agent_reg_id = 0; // Renamed for clarity

static GDBusProxy *gatt_manager_proxy = NULL; // Renamed for clarity
static GDBusProxy *advertising_manager_proxy = NULL; // Renamed for clarity
static GDBusProxy *agent_manager_proxy = NULL; // Renamed for clarity

static pthread_t bluetooth_thread;
static volatile gint main_loop_running = 0; // Flag to indicate main loop status

// Callbacks (Ensure user knows these run in the D-Bus thread context)
typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
static connection_result_callback setup_data_callback = NULL; // Renamed for clarity

typedef void (*command_callback)(int success, const unsigned char* data, int length);
static command_callback command_data_callback = NULL; // Renamed for clarity

typedef void (*device_connection_callback)(const char* device_id, int connected);
static device_connection_callback connection_status_callback = NULL; // Renamed for clarity

// Logging
static FILE* log_file = NULL;
static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER; // Mutex for log file access

// Device Name & Path (Protected by mutex)
static char device_name[MAX_DEVICE_NAME_LENGTH] = FERALFILE_SERVICE_NAME;
static pthread_mutex_t device_name_mutex = PTHREAD_MUTEX_INITIALIZER;

// Sentry
static volatile int sentry_initialized = 0;

static void cmd_char_method_call(GDBusConnection *conn,
    const gchar *sender, const gchar *object_path,
    const gchar *interface_name, const gchar *method_name,
    GVariant *parameters, GDBusMethodInvocation *invocation,
    gpointer user_data);

static void eng_char_method_call(GDBusConnection *conn,
    const gchar *sender, const gchar *object_path,
    const gchar *interface_name, const gchar *method_name,
    GVariant *parameters, GDBusMethodInvocation *invocation,
    gpointer user_data);

static void advertisement_method_call(GDBusConnection *conn,
       const gchar *sender, const gchar *object_path,
       const gchar *interface_name, const gchar *method_name,
       GVariant *parameters, GDBusMethodInvocation *invocation,
       gpointer user_data);

// --- Forward Declarations ---
static void setup_dbus_signal_handlers(GDBusConnection *conn);
static void handle_property_change(GDBusConnection *connection,
                                   const gchar *sender_name,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *signal_name,
                                   GVariant *parameters,
                                   gpointer user_data);
static void cleanup_resources();
static void* bluetooth_thread_func(void* arg);

// --- Logging Functions (Thread-Safe File Logging) ---

// Utility to get timestamp string
static void get_timestamp(char *buffer, size_t len) {
    time_t now;
    struct tm result;
    time(&now);
    localtime_r(&now, &result); // Use thread-safe localtime_r
    strftime(buffer, len, "%Y-%m-%d %H:%M:%S", &result);
}

static void log_generic(int level, const char* level_str, FILE* stream, const char* format, va_list args) {
    char timestamp[30];
    get_timestamp(timestamp, sizeof(timestamp));

    // Print to stream (stderr or stdout)
    fprintf(stream, "%s: %s: [%s] ", timestamp, level_str, LOG_TAG);
    vfprintf(stream, format, args);
    fprintf(stream, "\n");
    fflush(stream);

    // Print to syslog
    // Create a temporary buffer for vsyslog as it might modify the va_list
    char syslog_buffer[2048]; // Increased buffer size
    vsnprintf(syslog_buffer, sizeof(syslog_buffer), format, args);
    syslog(level, "[%s] %s", LOG_TAG, syslog_buffer);

    // Print to file (thread-safe)
    pthread_mutex_lock(&log_mutex);
    if (log_file != NULL) {
        fprintf(log_file, "%s: %s: [%s] ", timestamp, level_str, LOG_TAG);
        vfprintf(log_file, format, args); // Use original args here
        fprintf(log_file, "\n");
        fflush(log_file);
    }
    pthread_mutex_unlock(&log_mutex);

    // Add Sentry breadcrumb (if initialized and not an error message)
    #ifdef SENTRY_DSN
    if (sentry_initialized && level != LOG_ERR) {
        char sentry_message[1024];
        // Use a copy for vsnprintf if args might be modified (safer)
        va_list args_copy_sentry;
        va_copy(args_copy_sentry, args);
        vsnprintf(sentry_message, sizeof(sentry_message), format, args_copy_sentry);
        va_end(args_copy_sentry);

        const char *sentry_level_str = (level == LOG_WARNING) ? "warning" : "info";
        sentry_value_t crumb = sentry_value_new_breadcrumb(sentry_level_str, sentry_message);
        // --- FIX: Check Sentry value correctly ---
        if (!sentry_value_is_null(crumb)) { // Check if crumb creation succeeded
            sentry_value_set_by_key(crumb, "category", sentry_value_new_string("bluetooth"));
            sentry_add_breadcrumb(crumb);
        } else {
            // Optional: Log if breadcrumb creation failed? Usually not critical.
        }
    }
    // Capture Sentry event for errors
    else if (sentry_initialized && level == LOG_ERR) {
        char sentry_message[1024];
        va_list args_copy_sentry;
        va_copy(args_copy_sentry, args);
        vsnprintf(sentry_message, sizeof(sentry_message), format, args_copy_sentry);
        va_end(args_copy_sentry);

        sentry_value_t event = sentry_value_new_message_event(
            SENTRY_LEVEL_ERROR,
            "bluetooth",
            sentry_message
        );
        // --- FIX: Check Sentry value correctly ---
        if (!sentry_value_is_null(event)) { // Check if event creation succeeded
           sentry_capture_event(event);
        } else {
            // Optional: Log if event creation failed?
        }
    }
#endif
}


void bluetooth_set_logfile(const char* path) {
    pthread_mutex_lock(&log_mutex);
    if (log_file != NULL) {
        fclose(log_file);
        log_file = NULL;
    }
    if (path != NULL) {
        log_file = fopen(path, "a");
        if (log_file == NULL) {
             // Log error to stderr/syslog since file logging failed
            char timestamp[30];
            get_timestamp(timestamp, sizeof(timestamp));
            fprintf(stderr, "%s: ERROR: [%s] Failed to open log file '%s': %s\n", timestamp, LOG_TAG, path, strerror(errno));
            syslog(LOG_ERR, "[%s] Failed to open log file '%s': %s", LOG_TAG, path, strerror(errno));
        }
    }
    pthread_mutex_unlock(&log_mutex);
}

static void log_info(const char* format, ...) {
    va_list args;
    va_start(args, format);
    // Need va_copy as log_generic uses the list multiple times
    va_list args_copy;
    va_copy(args_copy, args);
    log_generic(LOG_INFO, "INFO", stdout, format, args_copy);
    va_end(args_copy);
    va_end(args);
}

static void log_error(const char* format, ...) {
    va_list args;
    va_start(args, format);
    va_list args_copy;
    va_copy(args_copy, args);
    log_generic(LOG_ERR, "ERROR", stderr, format, args_copy);
    va_end(args_copy);
    va_end(args);
}

static void log_warning(const char* format, ...) {
    va_list args;
    va_start(args, format);
    va_list args_copy;
    va_copy(args_copy, args);
    log_generic(LOG_WARNING, "WARNING", stderr, format, args_copy);
    va_end(args_copy);
    va_end(args);
}

// --- XML Introspection Data ---
// Combined service and characteristics XML
static const gchar service_introspection_xml[] =
    "<node name='" FERALFILE_DBUS_BASE_PATH "'>" // Root path included
    "  <interface name='" DBUS_INTF_OBJECT_MANAGER "'>"
    "    <method name='GetManagedObjects'>"
    "      <arg name='objects' type='a{oa{sa{sv}}}' direction='out'/>"
    "    </method>"
    "  </interface>"
    "  <node name='service0'>" // Relative path from base
    "    <interface name='" BLUEZ_INTF_GATT_SERVICE "'>"
    "      <property name='UUID' type='s' access='read'/>"
    "      <property name='Primary' type='b' access='read'/>"
    "      "
    "      "
    "    </interface>"
    "    <node name='setup_char'>" // Relative path
    "      <interface name='" BLUEZ_INTF_GATT_CHARACTERISTIC "'>"
    "        <property name='UUID' type='s' access='read'/>"
    "        <property name='Service' type='o' access='read'/>"
    "        <property name='Flags' type='as' access='read'/>"
    "        "
    "        "
    "        <method name='WriteValue'>"
    "          <arg name='value' type='ay' direction='in'/>"
    "          <arg name='options' type='a{sv}' direction='in'/>"
    "        </method>"
    "        "
    "        "
    "        "
    "        "
    "        "
    "      </interface>"
    "    </node>"
    "    <node name='cmd_char'>" // Relative path
    "      <interface name='" BLUEZ_INTF_GATT_CHARACTERISTIC "'>"
    "        <property name='UUID' type='s' access='read'/>"
    "        <property name='Service' type='o' access='read'/>"
    "        <property name='Flags' type='as' access='read'/>"
    "        "
    "        <property name='Value' type='ay' access='read'/>"
    "        <property name='Notifying' type='b' access='read'/>"
    "        <method name='WriteValue'>"
    "          <arg name='value' type='ay' direction='in'/>"
    "          <arg name='options' type='a{sv}' direction='in'/>"
    "        </method>"
    "        <method name='StartNotify'/>"
    "        <method name='StopNotify'/>"
    "      </interface>"
    "    </node>"
    "    <node name='eng_char'>" // Relative path
    "      <interface name='" BLUEZ_INTF_GATT_CHARACTERISTIC "'>"
    "        <property name='UUID' type='s' access='read'/>"
    "        <property name='Service' type='o' access='read'/>"
    "        <property name='Flags' type='as' access='read'/>"
    "        "
    "        <property name='Value' type='ay' access='read'/>"
    "        <property name='Notifying' type='b' access='read'/>"
    "        <method name='StartNotify'/>"
    "        <method name='StopNotify'/>"
    "      </interface>"
    "    </node>"
    "  </node>"
    "</node>";

static const gchar agent_introspection_xml[] =
    "<node name='" FERALFILE_DBUS_AGENT_PATH "'>" // Agent path included
    "  <interface name='" BLUEZ_INTF_AGENT "'>"
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
    "      <arg name='entered' type='q' direction='in'/>" // uint16
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

// --- D-Bus Method Handlers & VTables ---

// Utility to find sub-node by name (relative path)
static GDBusNodeInfo* find_sub_node_by_name(GDBusNodeInfo *parent, const gchar *name) {
    if (!parent || !name || !parent->nodes) {
        return NULL;
    }
    for (guint i = 0; parent->nodes[i] != NULL; i++) {
        // Compare the node name part after the last '/' if path contains slashes
        const gchar *node_name = strrchr(parent->nodes[i]->path, '/');
        node_name = (node_name == NULL) ? parent->nodes[i]->path : node_name + 1;
        if (g_strcmp0(node_name, name) == 0) {
            return parent->nodes[i];
        }
    }
    return NULL;
}

// Agent Method Handler
static void agent_method_call(GDBusConnection *conn,
                              const gchar *sender,
                              const gchar *object_path,
                              const gchar *interface_name,
                              const gchar *method_name,
                              GVariant *parameters,
                              GDBusMethodInvocation *invocation,
                              gpointer user_data)
{
    const char *device_path = NULL;
    // Extract device path safely from parameters where applicable
    if (g_strcmp0(method_name, "Release") != 0 && g_strcmp0(method_name, "Cancel") != 0 && parameters != NULL) {
        // Most methods have device path as the first argument ('o')
         if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(o*)"))) { // Check type loosely
              GVariant *device_variant = g_variant_get_child_value(parameters, 0);
              if (g_variant_is_of_type(device_variant, G_VARIANT_TYPE_OBJECT_PATH)) {
                 device_path = g_variant_get_string(device_variant, NULL);
              }
              g_variant_unref(device_variant);
         }
    }
    const char *log_device_path = device_path ? device_path : "(unknown device)";

    log_info("Agent method call: Sender=%s, Path=%s, Interface=%s, Method=%s, Device=%s",
             sender, object_path, interface_name, method_name, log_device_path);

    if (g_strcmp0(method_name, "Release") == 0) {
        log_info("Agent released.");
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "RequestPinCode") == 0) {
        log_warning("Agent rejecting RequestPinCode for %s (NoInputNoOutput)", log_device_path);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Rejected", "NoInputNoOutput agent cannot provide PIN");
    } else if (g_strcmp0(method_name, "RequestPasskey") == 0) {
        log_warning("Agent rejecting RequestPasskey for %s (NoInputNoOutput)", log_device_path);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Rejected", "NoInputNoOutput agent cannot provide passkey");
    } else if (g_strcmp0(method_name, "RequestConfirmation") == 0) {
        guint32 passkey = 0;
        // Extract passkey safely
        if (parameters && g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ou)"))) {
            g_variant_get(parameters, "(&ou)", NULL, &passkey);
        }
        log_info("Agent accepting RequestConfirmation for %s with passkey %u (JustWorks)", log_device_path, passkey);
        // Accept the confirmation for "Just Works" pairing
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "RequestAuthorization") == 0) {
        log_info("Agent accepting RequestAuthorization for %s", log_device_path);
        // Automatically authorize connections for this simple agent
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "AuthorizeService") == 0) {
        const gchar *uuid = NULL;
        if (parameters && g_variant_is_of_type(parameters, G_VARIANT_TYPE("(os)"))) {
             g_variant_get(parameters, "(&os)", NULL, &uuid);
        }
        log_info("Agent accepting AuthorizeService for %s, UUID %s", log_device_path, uuid ? uuid : "(unknown)");
        // Automatically authorize service access
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "Cancel") == 0) {
        log_info("Agent received Cancel request.");
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else if (g_strcmp0(method_name, "DisplayPinCode") == 0 || g_strcmp0(method_name, "DisplayPasskey") == 0) {
        // No display capabilities, just acknowledge
        log_info("Agent acknowledging %s for %s (NoInputNoOutput)", method_name, log_device_path);
        g_dbus_method_invocation_return_value(invocation, NULL);
    } else {
        log_warning("Agent received unsupported method '%s' for %s", method_name, log_device_path);
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.NotSupported", "Method not supported by this agent");
    }
}

static const GDBusInterfaceVTable agent_vtable = {
    .method_call = agent_method_call,
    .get_property = NULL, // No properties defined in XML for Agent1
    .set_property = NULL
};

// GATT Service Property Getter
static GVariant *service_get_property(GDBusConnection *conn,
                                      const gchar *sender,
                                      const gchar *object_path,
                                      const gchar *interface_name,
                                      const gchar *property_name,
                                      GError **error, // Use error reporting
                                      gpointer user_data)
{
    if (g_strcmp0(interface_name, BLUEZ_INTF_GATT_SERVICE) != 0) {
         g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Invalid interface '%s' for service property", interface_name);
         return NULL;
    }

    if (g_strcmp0(property_name, "UUID") == 0) {
        return g_variant_new_string(FERALFILE_SERVICE_UUID);
    }
    if (g_strcmp0(property_name, "Primary") == 0) {
        return g_variant_new_boolean(TRUE);
    }
    // Handle 'Device' property if needed, usually requires tracking the device object path
    // if (g_strcmp0(property_name, "Device") == 0) {
    //    return g_variant_new_object_path(...);
    // }

    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "Unknown property '%s' for service", property_name);
    return NULL;
}

// GATT Characteristic Property Getter
static GVariant *char_get_property(GDBusConnection *conn,
                                   const gchar *sender,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *property_name,
                                   GError **error,
                                   gpointer user_data)
{
     if (g_strcmp0(interface_name, BLUEZ_INTF_GATT_CHARACTERISTIC) != 0) {
         g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Invalid interface '%s' for characteristic property", interface_name);
         return NULL;
    }

    if (g_strcmp0(property_name, "UUID") == 0) {
        if (g_str_has_suffix(object_path, "/setup_char")) {
            return g_variant_new_string(FERALFILE_SETUP_CHAR_UUID);
        } else if (g_str_has_suffix(object_path, "/cmd_char")) {
            return g_variant_new_string(FERALFILE_CMD_CHAR_UUID);
        } else if (g_str_has_suffix(object_path, "/eng_char")) {
            return g_variant_new_string(FERALFILE_ENG_CHAR_UUID);
        }
    } else if (g_strcmp0(property_name, "Service") == 0) {
        // Construct the service path dynamically based on the characteristic path
        // Assumes characteristic path is always "/base/serviceN/charX"
        char *service_path = g_path_get_dirname(object_path);
        if (!service_path) {
             g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Could not determine service path for '%s'", object_path);
             return NULL;
        }
        GVariant* result = g_variant_new_object_path(service_path);
        g_free(service_path);
        return result;

    } else if (g_strcmp0(property_name, "Flags") == 0) {
        if (g_str_has_suffix(object_path, "/setup_char")) {
            const gchar* flags[] = {"write", NULL}; // Only write
            return g_variant_new_strv(flags, -1);
        } else if (g_str_has_suffix(object_path, "/cmd_char")) {
            // NOTE: "write-without-response" might be preferred for commands if ack isn't needed.
            const gchar* flags[] = {"write", "write-without-response", "notify", NULL};
            return g_variant_new_strv(flags, -1);
        } else if (g_str_has_suffix(object_path, "/eng_char")) {
            const gchar* flags[] = {"notify", NULL}; // Only notify
            return g_variant_new_strv(flags, -1);
        }
    } else if (g_strcmp0(property_name, "Value") == 0) {
         // Return empty byte array if value is requested but not tracked/cached.
         // For notify characteristics, BlueZ usually handles caching when notified.
         // If you need to support ReadValue, cache the last written/notified value here.
         log_info("Read request for Value property on %s (returning empty)", object_path);
         return g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, NULL, 0, sizeof(guchar));
    } else if (g_strcmp0(property_name, "Notifying") == 0) {
        // BlueZ typically manages this state based on Start/StopNotify calls.
        // Returning false is a safe default if not actively tracking.
        log_info("Read request for Notifying property on %s (returning false)", object_path);
        return g_variant_new_boolean(FALSE);
    }

    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "Unknown property '%s' for characteristic '%s'", property_name, object_path);
    return NULL;
}

// Generic Write Handler (for setup_char and cmd_char)
static void handle_char_write(GDBusConnection *conn,
                              const gchar *sender,
                              const gchar *object_path,
                              const gchar *interface_name,
                              const gchar *method_name,
                              GVariant *parameters,
                              GDBusMethodInvocation *invocation,
                              gpointer user_data)
{
    GVariant *array_variant = NULL;
    GVariant *options_variant = NULL;
    guchar *data_copy = NULL;
    gsize n_elements = 0;
    int success = 0;
    const char *char_name = "unknown_char"; // For logging

    if (g_str_has_suffix(object_path, "/setup_char")) {
        char_name = "setup_char";
    } else if (g_str_has_suffix(object_path, "/cmd_char")) {
        char_name = "cmd_char";
    }

    // Safely unpack parameters
    // Format is (ay a{sv}) - byte array and options dictionary
    if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(aya{sv})"))) {
         log_error("[%s] (%s) Invalid parameters type for WriteValue: %s",
                   LOG_TAG, char_name, g_variant_get_type_string(parameters));
         g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.InvalidArgs",
                                                   "Invalid parameter type for WriteValue");
         return;
    }

    g_variant_get(parameters, "(@ay@a{sv})", &array_variant, &options_variant);

    if (!array_variant) {
         log_error("[%s] (%s) Failed to extract byte array from WriteValue parameters", LOG_TAG, char_name);
         g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.InvalidArgs",
                                                   "Missing byte array in WriteValue");
         if (options_variant) g_variant_unref(options_variant);
         return;
    }

    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));

    // Create a copy of the data for the callback
    // Check for malloc failure
    data_copy = (guchar *)malloc(n_elements);
    if (data_copy == NULL && n_elements > 0) {
        log_error("[%s] (%s) Failed to allocate memory (%zu bytes) for data copy", LOG_TAG, char_name, n_elements);
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.NoMemory",
                                                   "Failed to allocate memory for write operation");
        // Call callback with error if appropriate
        if (g_str_has_suffix(object_path, "/setup_char") && setup_data_callback) {
             setup_data_callback(0, NULL, 0);
        } else if (g_str_has_suffix(object_path, "/cmd_char") && command_data_callback) {
             command_data_callback(0, NULL, 0);
        }
        return;
    }
    if (data_copy) { // Only copy if allocation succeeded
       memcpy(data_copy, data, n_elements);
       success = 1; // Mark as successful for callback
    } else if (n_elements == 0) {
       success = 1; // Empty write is also success
    }


    log_info("[%s] (%s) WriteValue: Received %zu bytes from %s", LOG_TAG, char_name, n_elements, sender);

    // Optional: Log hex string (ensure buffer is large enough)
    if (n_elements > 0 && data_copy) {
        gsize hex_len = n_elements * 3 + 1;
        char *hex_string = malloc(hex_len);
        if (hex_string) {
            for (size_t i = 0; i < n_elements; i++) {
                snprintf(hex_string + (i * 3), 4, "%02x ", data_copy[i]); // Use snprintf for safety
            }
            hex_string[hex_len - 2] = '\0'; // Adjust null termination
            log_info("[%s] (%s) Data: %s", LOG_TAG, char_name, hex_string);
            free(hex_string);
        }
    }

    // --- Invoke appropriate callback ---
    // IMPORTANT: The callback now owns data_copy and MUST free it using bluetooth_free_data()
    if (g_str_has_suffix(object_path, "/setup_char") && setup_data_callback) {
        setup_data_callback(success, data_copy, (int)n_elements);
        // Callback now owns data_copy, set to NULL here to prevent double free below
        if (success) data_copy = NULL;
    } else if (g_str_has_suffix(object_path, "/cmd_char") && command_data_callback) {
        command_data_callback(success, data_copy, (int)n_elements);
        // Callback now owns data_copy, set to NULL here to prevent double free below
        if (success) data_copy = NULL;
    } else {
        // No callback registered or unknown path, free the copy if it wasn't passed
        log_warning("[%s] (%s) No callback registered for write operation.", LOG_TAG, char_name);
        if (data_copy) {
             free(data_copy);
             data_copy = NULL;
        }
    }

    // Add Sentry breadcrumb
#ifdef SENTRY_DSN
    if (sentry_initialized) {
        char crumb_msg[128];
        snprintf(crumb_msg, sizeof(crumb_msg), "Received %s data", char_name);
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", crumb_msg);
        if (!sentry_value_is_null(crumb)) {
            sentry_value_set_by_key(crumb, "data_length", sentry_value_new_int32((int32_t)n_elements));
            sentry_value_set_by_key(crumb, "characteristic", sentry_value_new_string(char_name));
            sentry_value_set_by_key(crumb, "sender", sentry_value_new_string(sender));
            sentry_add_breadcrumb(crumb);
        }
    }
#endif

    // Cleanup variants
    g_variant_unref(array_variant);
    if (options_variant) {
        g_variant_unref(options_variant);
    }

    // Free data_copy *only* if the callback failed or wasn't called
    if (data_copy != NULL) {
         free(data_copy);
    }

    // Return success to the D-Bus caller
    g_dbus_method_invocation_return_value(invocation, NULL);
}


// Generic Notify Handler (for cmd_char and eng_char Start/StopNotify)
static void handle_char_notify(GDBusConnection *conn,
                               const gchar *sender,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *method_name,
                               GVariant *parameters, // Usually NULL for Start/StopNotify
                               GDBusMethodInvocation *invocation,
                               gpointer user_data)
{
    const char *char_name = "unknown_char";
    if (g_str_has_suffix(object_path, "/cmd_char")) {
        char_name = "cmd_char";
    } else if (g_str_has_suffix(object_path, "/eng_char")) {
        char_name = "eng_char";
    }

    gboolean start_notify = (g_strcmp0(method_name, "StartNotify") == 0);

    log_info("[%s] (%s) %s request from %s", LOG_TAG, char_name,
             start_notify ? "StartNotify" : "StopNotify", sender);

    // Here you would typically store the notification state per-client (sender)
    // if you need fine-grained control or need to know who is listening.
    // For simplicity, we just acknowledge the request. BlueZ handles the
    // actual notification mechanism when PropertiesChanged is emitted.

    // Add Sentry breadcrumb
#ifdef SENTRY_DSN
    if (sentry_initialized) {
        char crumb_msg[128];
        snprintf(crumb_msg, sizeof(crumb_msg), "%s %s", start_notify ? "Started" : "Stopped", char_name);
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", crumb_msg);
         if (!sentry_value_is_null(crumb)) {
            sentry_value_set_by_key(crumb, "characteristic", sentry_value_new_string(char_name));
            sentry_value_set_by_key(crumb, "sender", sentry_value_new_string(sender));
            sentry_add_breadcrumb(crumb);
         }
    }
#endif

    g_dbus_method_invocation_return_value(invocation, NULL);
}

// Dispatcher for cmd_char methods
static void cmd_char_method_call(GDBusConnection *conn,
                                 const gchar *sender, const gchar *object_path,
                                 const gchar *interface_name, const gchar *method_name,
                                 GVariant *parameters, GDBusMethodInvocation *invocation,
                                 gpointer user_data)
{
    if (g_strcmp0(method_name, "WriteValue") == 0) {
        handle_char_write(conn, sender, object_path, interface_name, method_name, parameters, invocation, user_data);
    } else if (g_strcmp0(method_name, "StartNotify") == 0 || g_strcmp0(method_name, "StopNotify") == 0) {
        handle_char_notify(conn, sender, object_path, interface_name, method_name, parameters, invocation, user_data);
    } else {
        log_warning("[%s] (%s) Received unhandled method '%s'", LOG_TAG, "cmd_char", method_name);
        g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.UnknownMethod",
                                                   "Method not known");
    }
}

// Dispatcher for eng_char methods
static void eng_char_method_call(GDBusConnection *conn,
                                 const gchar *sender, const gchar *object_path,
                                 const gchar *interface_name, const gchar *method_name,
                                 GVariant *parameters, GDBusMethodInvocation *invocation,
                                 gpointer user_data)
{
    if (g_strcmp0(method_name, "StartNotify") == 0 || g_strcmp0(method_name, "StopNotify") == 0) {
        handle_char_notify(conn, sender, object_path, interface_name, method_name, parameters, invocation, user_data);
    } else {
        log_warning("[%s] (%s) Received unhandled method '%s'", LOG_TAG, "eng_char", method_name);
        g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.UnknownMethod",
                                                   "Method not known");
    }
}

// --- Advertisement Release Method ---
// (Make sure this function exists and is correct)
static void advertisement_release(GDBusConnection *conn,
                                  const gchar *sender,
                                  const gchar *object_path,
                                  const gchar *interface_name,
                                  const gchar *method_name,
                                  GVariant *parameters,
                                  GDBusMethodInvocation *invocation,
                                  gpointer user_data)
{
    log_info("[%s] Advertisement object released request from %s for %s", LOG_TAG, sender, object_path);
    // Perform any cleanup related to this specific advertisement if necessary
    // e.g., if you track state associated with the advertisement object path.
    g_dbus_method_invocation_return_value(invocation, NULL);
}


// Dispatcher for advertisement methods
static void advertisement_method_call(GDBusConnection *conn,
                                    const gchar *sender, const gchar *object_path,
                                    const gchar *interface_name, const gchar *method_name,
                                    GVariant *parameters, GDBusMethodInvocation *invocation,
                                    gpointer user_data)
{
    if (g_strcmp0(method_name, "Release") == 0) {
        advertisement_release(conn, sender, object_path, interface_name, method_name, parameters, invocation, user_data);
    } else {
        log_warning("[%s] Received unhandled method '%s' for advertisement %s", LOG_TAG, method_name, object_path);
        g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.UnknownMethod",
                                                   "Method not known");
    }
}

// VTables
static const GDBusInterfaceVTable service_vtable = {
    .method_call = NULL,
    .get_property = service_get_property,
    .set_property = NULL
};

static const GDBusInterfaceVTable setup_char_vtable = {
    .method_call = handle_char_write, // Only supports WriteValue
    .get_property = char_get_property,
    .set_property = NULL
};

// --- FIX: Use dispatcher function ---
static const GDBusInterfaceVTable cmd_char_vtable = {
    .method_call = cmd_char_method_call, // Points to the dispatcher
    .get_property = char_get_property,
    .set_property = NULL
};

// --- FIX: Use dispatcher function ---
static const GDBusInterfaceVTable eng_char_vtable = {
     .method_call = eng_char_method_call, // Points to the dispatcher
    .get_property = char_get_property,
    .set_property = NULL
};

// --- Advertisement ---
static GVariant* advertisement_get_property(GDBusConnection *connection,
                                            const gchar *sender,
                                            const gchar *object_path,
                                            const gchar *interface_name,
                                            const gchar *property_name,
                                            GError **error,
                                            gpointer user_data)
{
    if (g_strcmp0(interface_name, BLUEZ_INTF_LE_ADVERTISEMENT) != 0) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "Invalid interface '%s' for advertisement property", interface_name);
        return NULL;
    }

    if (g_strcmp0(property_name, "Type") == 0) {
        return g_variant_new_string("peripheral");
    } else if (g_strcmp0(property_name, "ServiceUUIDs") == 0) {
        const gchar* uuids[] = {FERALFILE_SERVICE_UUID, NULL};
        return g_variant_new_strv(uuids, -1);
    } else if (g_strcmp0(property_name, "LocalName") == 0) {
        // Read device name safely using mutex
        pthread_mutex_lock(&device_name_mutex);
        GVariant *name_variant = g_variant_new_string(device_name);
        pthread_mutex_unlock(&device_name_mutex);
        return name_variant;
    }
    // Add other properties if needed (e.g., ManufacturerData, IncludeTxPower)

    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "Unknown property '%s' for advertisement", property_name);
    return NULL;
}

static const GDBusInterfaceVTable advertisement_vtable = {
    .method_call = advertisement_method_call, // Points to the dispatcher
    .get_property = advertisement_get_property,
    .set_property = NULL,
};

// --- ObjectManager ---
static void add_object_to_managed_objects(GVariantBuilder *objects_builder,
                                          const char* path,
                                          const char* intf_name,
                                          GVariantBuilder* props_builder)
{
    GVariantBuilder *interfaces_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sa{sv}}"));
    // Add the properties under the interface name
    g_variant_builder_add(interfaces_builder, "{sa{sv}}", intf_name, props_builder); // props_builder consumed here
    // Add the interface dictionary to the main objects dictionary, keyed by path
    g_variant_builder_add(objects_builder, "{oa{sa{sv}}}", path, interfaces_builder); // interfaces_builder consumed here
    // No need to unref builders passed to g_variant_builder_add
}

static void handle_get_managed_objects(GDBusConnection *conn,
                                     const gchar *sender,
                                     const gchar *object_path, // Should be FERALFILE_DBUS_BASE_PATH
                                     const gchar *interface_name, // Should be DBUS_INTF_OBJECT_MANAGER
                                     const gchar *method_name, // Should be GetManagedObjects
                                     GVariant *parameters, // NULL
                                     GDBusMethodInvocation *invocation,
                                     gpointer user_data)
{
    if (g_strcmp0(object_path, FERALFILE_DBUS_BASE_PATH) != 0 ||
        g_strcmp0(interface_name, DBUS_INTF_OBJECT_MANAGER) != 0 ||
        g_strcmp0(method_name, "GetManagedObjects") != 0)
    {
        log_error("[%s] Incorrect parameters for GetManagedObjects handler", LOG_TAG);
        g_dbus_method_invocation_return_dbus_error(invocation,
                                                   "org.freedesktop.DBus.Error.Failed",
                                                   "Internal handler mismatch");
        return;
    }

    log_info("[%s] GetManagedObjects called by %s", LOG_TAG, sender);

    GVariantBuilder *objects_builder = g_variant_builder_new(G_VARIANT_TYPE("a{oa{sa{sv}}}"));

    // Helper function to add an object

    // Add service object
    GVariantBuilder *service_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(service_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SERVICE_UUID));
    g_variant_builder_add(service_props, "{sv}", "Primary", g_variant_new_boolean(TRUE));
    // g_variant_builder_unref(service_props); // Builder passed ownership
    add_object_to_managed_objects(objects_builder, FERALFILE_DBUS_SERVICE_PATH, BLUEZ_INTF_GATT_SERVICE, service_props);

    // Add setup characteristic object
    GVariantBuilder *setup_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(setup_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_SETUP_CHAR_UUID));
    g_variant_builder_add(setup_char_props, "{sv}", "Service", g_variant_new_object_path(FERALFILE_DBUS_SERVICE_PATH));
    const gchar* setup_flags[] = {"write", NULL};
    g_variant_builder_add(setup_char_props, "{sv}", "Flags", g_variant_new_strv(setup_flags, -1));
    // g_variant_builder_unref(setup_char_props);
    add_object_to_managed_objects(objects_builder, FERALFILE_DBUS_SETUP_CHAR_PATH, BLUEZ_INTF_GATT_CHARACTERISTIC, setup_char_props);

    // Add command characteristic object
    GVariantBuilder *cmd_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(cmd_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_CMD_CHAR_UUID));
    g_variant_builder_add(cmd_char_props, "{sv}", "Service", g_variant_new_object_path(FERALFILE_DBUS_SERVICE_PATH));
    const gchar* cmd_flags[] = {"write", "write-without-response", "notify", NULL};
    g_variant_builder_add(cmd_char_props, "{sv}", "Flags", g_variant_new_strv(cmd_flags, -1));
    g_variant_builder_add(cmd_char_props, "{sv}", "Value", g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, NULL, 0, sizeof(guchar)));
    g_variant_builder_add(cmd_char_props, "{sv}", "Notifying", g_variant_new_boolean(FALSE));
    // --- FIX: Call helper function ---
    add_object_to_managed_objects(objects_builder, FERALFILE_DBUS_CMD_CHAR_PATH, BLUEZ_INTF_GATT_CHARACTERISTIC, cmd_char_props);

    // Add engineering characteristic object
    GVariantBuilder *eng_char_props = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(eng_char_props, "{sv}", "UUID", g_variant_new_string(FERALFILE_ENG_CHAR_UUID));
    g_variant_builder_add(eng_char_props, "{sv}", "Service", g_variant_new_object_path(FERALFILE_DBUS_SERVICE_PATH));
    const gchar* eng_flags[] = {"notify", NULL};
    g_variant_builder_add(eng_char_props, "{sv}", "Flags", g_variant_new_strv(eng_flags, -1));
    g_variant_builder_add(eng_char_props, "{sv}", "Value", g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, NULL, 0, sizeof(guchar)));
    g_variant_builder_add(eng_char_props, "{sv}", "Notifying", g_variant_new_boolean(FALSE));
    // --- FIX: Call helper function ---
    add_object_to_managed_objects(objects_builder, FERALFILE_DBUS_ENG_CHAR_PATH, BLUEZ_INTF_GATT_CHARACTERISTIC, eng_char_props);

    // Return the dictionary of objects
    g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", objects_builder));

    // No need to unref builders added to other builders if using g_variant_builder_add
    // g_variant_builder_unref(objects_builder);
}

static const GDBusInterfaceVTable object_manager_vtable = { // Renamed for clarity
    .method_call = handle_get_managed_objects,
    .get_property = NULL,
    .set_property = NULL
};

// --- Bluetooth Service Management ---

// Check if bluetooth.service is active using systemctl
static int is_bluetooth_service_active() {
    // Use popen for simplicity, error handling added
    FILE *fp = popen("systemctl is-active --quiet bluetooth.service", "r");
    int status = -1;

    if (fp == NULL) {
        log_error("[%s] Failed to run 'systemctl is-active': %s", LOG_TAG, strerror(errno));
        return 0; // Assume not active if check fails
    }

    // WEXITSTATUS extracts the exit status
    status = pclose(fp);
    if (status == -1) {
         log_error("[%s] pclose failed after 'systemctl is-active': %s", LOG_TAG, strerror(errno));
         return 0;
    }

    // systemctl is-active returns 0 if active, non-zero otherwise
    return WEXITSTATUS(status) == 0;
}

// Wait for bluetooth service to become active with retries
static gboolean wait_for_bluetooth_service() {
    int attempts = 0;
    while (attempts < MAX_RETRY_ATTEMPTS) {
        if (is_bluetooth_service_active()) {
            log_info("[%s] Bluetooth service is active.", LOG_TAG);
            // Short delay to allow service to fully initialize after becoming active
            sleep(1);
            return TRUE;
        }

        attempts++;
        log_info("[%s] Bluetooth service not active, waiting %d seconds (attempt %d/%d)...",
                 LOG_TAG, RETRY_DELAY_SECONDS, attempts, MAX_RETRY_ATTEMPTS);
        sleep(RETRY_DELAY_SECONDS);
    }

    log_error("[%s] Bluetooth service did not become active after %d attempts.",
              LOG_TAG, MAX_RETRY_ATTEMPTS);
    return FALSE;
}

// --- D-Bus Signal Handling ---

// Subscribe to relevant D-Bus signals
static void setup_dbus_signal_handlers(GDBusConnection *conn) {
    if (!conn) return;

    // Monitor device property changes (Connected property)
    g_dbus_connection_signal_subscribe(
        conn,
        BLUEZ_DBUS_SERVICE,                     // sender
        DBUS_INTF_PROPERTIES,                   // interface_name
        "PropertiesChanged",                    // member
        NULL,                                   // object_path (match any object)
        BLUEZ_INTF_DEVICE,                      // arg0 (match interface being changed)
        G_DBUS_SIGNAL_FLAGS_NONE,
        handle_property_change,                 // callback
        NULL,                                   // user_data
        NULL);                                  // user_data free function

     // Optional: Monitor InterfacesAdded/Removed on ObjectManager if needed
     // g_dbus_connection_signal_subscribe(
     //    conn,
     //    BLUEZ_DBUS_SERVICE,
     //    DBUS_INTF_OBJECT_MANAGER,
     //    "InterfacesAdded",
     //    NULL, // path
     //    NULL, // arg0
     //    G_DBUS_SIGNAL_FLAGS_NONE, handle_interfaces_added, NULL, NULL);
     // g_dbus_connection_signal_subscribe(
     //    conn,
     //    BLUEZ_DBUS_SERVICE,
     //    DBUS_INTF_OBJECT_MANAGER,
     //    "InterfacesRemoved",
     //    NULL, // path
     //    NULL, // arg0
     //    G_DBUS_SIGNAL_FLAGS_NONE, handle_interfaces_removed, NULL, NULL);


    log_info("[%s] Subscribed to D-Bus PropertiesChanged signals for %s.", LOG_TAG, BLUEZ_INTF_DEVICE);
}

// Handle PropertiesChanged signals (specifically for Device connection status)
static void handle_property_change(GDBusConnection *conn,
                                   const gchar *sender_name,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *signal_name,
                                   GVariant *parameters,
                                   gpointer user_data)
{
    // Ensure the signal is for the interface we care about (redundant due to subscribe filter, but safe)
    if (g_strcmp0(interface_name, BLUEZ_INTF_DEVICE) != 0) {
        return;
    }

    GVariantIter iter;
    const gchar *property_name;
    GVariant *property_value;
    const gchar *iface_changed;
    GVariant *changed_props_dict;
    GVariant *invalidated_props_array;

    // Unpack the parameters: string (interface), dict (changed properties), array (invalidated properties)
    g_variant_get(parameters, "(&sa{sv}as)", &iface_changed, &changed_props_dict, &invalidated_props_array);

    // Iterate through the changed properties dictionary
    g_variant_iter_init(&iter, changed_props_dict);
    while (g_variant_iter_next(&iter, "{&sv}", &property_name, &property_value)) {
        if (g_strcmp0(property_name, "Connected") == 0) {
            gboolean connected = g_variant_get_boolean(property_value);

            // Extract device ID (MAC address) from the object path
            // Path format is typically /org/bluez/hciX/dev_XX_XX_XX_XX_XX_XX
            const char* device_id_part = strrchr(object_path, '/');
            if (device_id_part != NULL) {
                 device_id_part++; // Skip the '/'
                 if (strncmp(device_id_part, "dev_", 4) == 0) {
                     const char* device_mac = device_id_part + 4; // Skip "dev_"
                     // Replace underscores with colons for standard MAC format if needed,
                     // but here we just pass the raw ID part.
                     log_info("[%s] Device %s (%s) %s", LOG_TAG, device_mac, object_path,
                              connected ? "connected" : "disconnected");

                     // Call the user's connection status callback
                     if (connection_status_callback) {
                         connection_status_callback(device_mac, connected ? 1 : 0);
                     }

                     // Add Sentry breadcrumb
                     #ifdef SENTRY_DSN
                     if (sentry_initialized) {
                         char crumb_msg[128];
                         snprintf(crumb_msg, sizeof(crumb_msg), "Device %s", connected ? "connected" : "disconnected");
                         sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", crumb_msg);
                         if (!sentry_value_is_null(crumb)) {
                            sentry_value_set_by_key(crumb, "device_mac", sentry_value_new_string(device_mac));
                            sentry_value_set_by_key(crumb, "device_path", sentry_value_new_string(object_path));
                            sentry_add_breadcrumb(crumb);
                         }
                     }
                     #endif
                 } else {
                     log_warning("[%s] Unexpected device path format for connection status: %s", LOG_TAG, object_path);
                 }
            } else {
                log_warning("[%s] Could not extract device ID from path: %s", LOG_TAG, object_path);
            }
        }
        // Handle other property changes if needed (e.g., "Paired", "RSSI")

        g_variant_unref(property_value);
    }

    // Cleanup
    g_variant_unref(changed_props_dict);
    g_variant_unref(invalidated_props_array);
}

// --- Bluetooth Thread ---
// --- Bluetooth Thread ---
static void* bluetooth_thread_func(void* arg) {
    GError *error = NULL;
    int retry_count = 0;
    gboolean initialized_successfully = FALSE;

    log_info("[%s] Bluetooth thread started.", LOG_TAG);

    while (retry_count < MAX_RETRY_ATTEMPTS && !initialized_successfully) {
        error = NULL; // Reset error for this attempt

        // --- Pre-check: Ensure BlueZ service is running ---
        if (!is_bluetooth_service_active()) {
            log_warning("[%s] Bluetooth service not active, waiting...", LOG_TAG);
            if (!wait_for_bluetooth_service()) {
                log_error("[%s] Failed to wait for Bluetooth service. Exiting thread.", LOG_TAG);
                goto thread_exit_failure; // Critical failure
            }
        }

        // --- Step 1: Connect to D-Bus System Bus ---
        connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
        if (!connection || error) {
            log_error("[%s] Failed to connect to D-Bus system bus: %s. Attempt %d/%d.",
                      LOG_TAG, error ? error->message : "Unknown error", retry_count + 1, MAX_RETRY_ATTEMPTS);
            if (error) g_error_free(error);
            goto retry_or_fail;
        }
        log_info("[%s] Connected to D-Bus system bus.", LOG_TAG);

        // Setup signal handlers immediately after connection
        setup_dbus_signal_handlers(connection);


        // --- Step 2: Parse Introspection XML ---
        root_node_info = g_dbus_node_info_new_for_xml(service_introspection_xml, &error);
        if (!root_node_info || error) {
            log_error("[%s] Failed to parse service introspection XML: %s.",
                      LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
             // No need to retry XML parsing failure
            goto thread_exit_failure;
        }
         agent_introspection_data = g_dbus_node_info_new_for_xml(agent_introspection_xml, &error);
        if (!agent_introspection_data || error) {
            log_error("[%s] Failed to parse agent introspection XML: %s.",
                      LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto thread_exit_failure; // No retry
        }
        // Advertisement XML is simpler, parse later if needed or construct dynamically

        // Find specific nodes (relative to base path in XML)
        GDBusNodeInfo *service_node = find_sub_node_by_name(root_node_info, "service0");
        GDBusNodeInfo *setup_char_node = service_node ? find_sub_node_by_name(service_node, "setup_char") : NULL;
        GDBusNodeInfo *cmd_char_node = service_node ? find_sub_node_by_name(service_node, "cmd_char") : NULL;
        GDBusNodeInfo *eng_char_node = service_node ? find_sub_node_by_name(service_node, "eng_char") : NULL;

        if (!service_node || !setup_char_node || !cmd_char_node || !eng_char_node) {
             log_error("[%s] Could not find required service/characteristic nodes in XML.", LOG_TAG);
             goto thread_exit_failure; // No retry
        }


        // --- Step 3: Register D-Bus Objects ---
        // Object Manager (at base path)
        GDBusInterfaceInfo* obj_mgr_interface = g_dbus_node_info_lookup_interface(root_node_info, DBUS_INTF_OBJECT_MANAGER);
        if (!obj_mgr_interface) { log_error("[%s] ObjectManager interface not found in XML.", LOG_TAG); goto thread_exit_failure; }
        objects_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_BASE_PATH, obj_mgr_interface,
                                                           &object_manager_vtable, NULL, NULL, &error);
        if (!objects_reg_id || error) {
            log_error("[%s] Failed to register ObjectManager: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

        // Service
        GDBusInterfaceInfo* service_interface = g_dbus_node_info_lookup_interface(service_node, BLUEZ_INTF_GATT_SERVICE);
         if (!service_interface) { log_error("[%s] GattService1 interface not found in XML.", LOG_TAG); goto thread_exit_failure; }
        service_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_SERVICE_PATH, service_interface,
                                                          &service_vtable, NULL, NULL, &error);
        if (!service_reg_id || error) {
            log_error("[%s] Failed to register Service object: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

        // Setup Characteristic
         GDBusInterfaceInfo* char_interface = g_dbus_node_info_lookup_interface(setup_char_node, BLUEZ_INTF_GATT_CHARACTERISTIC); // Same interface for all chars
         if (!char_interface) { log_error("[%s] GattCharacteristic1 interface not found in XML.", LOG_TAG); goto thread_exit_failure; }
        setup_char_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_SETUP_CHAR_PATH, char_interface,
                                                             &setup_char_vtable, NULL, NULL, &error);
        if (!setup_char_reg_id || error) {
            log_error("[%s] Failed to register Setup Characteristic: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

        // Command Characteristic
        cmd_char_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_CMD_CHAR_PATH, char_interface,
                                                           &cmd_char_vtable, NULL, NULL, &error);
        if (!cmd_char_reg_id || error) {
            log_error("[%s] Failed to register Command Characteristic: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

         // Engineering Characteristic
        eng_char_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_ENG_CHAR_PATH, char_interface,
                                                           &eng_char_vtable, NULL, NULL, &error);
        if (!eng_char_reg_id || error) {
            log_error("[%s] Failed to register Engineering Characteristic: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

         // Agent
        GDBusInterfaceInfo* agent_interface = g_dbus_node_info_lookup_interface(agent_introspection_data, BLUEZ_INTF_AGENT);
        if (!agent_interface) { log_error("[%s] Agent1 interface not found in XML.", LOG_TAG); goto thread_exit_failure; }
        agent_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_AGENT_PATH, agent_interface,
                                                        &agent_vtable, NULL, NULL, &error);
        if (!agent_reg_id || error) {
            log_error("[%s] Failed to register Agent object: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

        log_info("[%s] Registered D-Bus objects successfully.", LOG_TAG);

        // --- Step 4: Get BlueZ Manager Proxies ---
        gatt_manager_proxy = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                                  BLUEZ_DBUS_SERVICE, BLUEZ_DBUS_ADAPTER_PATH, BLUEZ_INTF_GATT_MANAGER,
                                                  NULL, &error);
        if (!gatt_manager_proxy || error) {
            log_error("[%s] Failed to get GattManager1 proxy at %s: %s.",
                      LOG_TAG, BLUEZ_DBUS_ADAPTER_PATH, error ? error->message : "Proxy is NULL");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }
        advertising_manager_proxy = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                                         BLUEZ_DBUS_SERVICE, BLUEZ_DBUS_ADAPTER_PATH, BLUEZ_INTF_LE_ADVERTISING_MANAGER,
                                                         NULL, &error);
        if (!advertising_manager_proxy || error) {
            log_error("[%s] Failed to get LEAdvertisingManager1 proxy at %s: %s.",
                      LOG_TAG, BLUEZ_DBUS_ADAPTER_PATH, error ? error->message : "Proxy is NULL");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }
         agent_manager_proxy = g_dbus_proxy_new_sync(connection, G_DBUS_PROXY_FLAGS_NONE, NULL,
                                                    BLUEZ_DBUS_SERVICE, BLUEZ_DBUS_PATH, BLUEZ_INTF_AGENT_MANAGER, // Agent Manager is at root
                                                    NULL, &error);
        if (!agent_manager_proxy || error) {
            log_error("[%s] Failed to get AgentManager1 proxy at %s: %s.",
                      LOG_TAG, BLUEZ_DBUS_PATH, error ? error->message : "Proxy is NULL");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }
        log_info("[%s] Obtained BlueZ manager proxies.", LOG_TAG);

        // --- Step 5: Register Agent with BlueZ ---
        GVariant *reg_agent_params = g_variant_new("(os)", FERALFILE_DBUS_AGENT_PATH, "NoInputNoOutput");
        GVariant *ret = g_dbus_proxy_call_sync(agent_manager_proxy, "RegisterAgent", reg_agent_params,
                                               G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
        if (error) {
            log_error("[%s] Failed to call RegisterAgent: %s.", LOG_TAG, error->message);
            g_error_free(error); error = NULL; // Reset error
            // Agent registration failure might be recoverable or indicate config issues. Retry.
            goto retry_or_fail;
        }
        if (ret) g_variant_unref(ret); // Unref return value even if NULL/empty tuple

        ret = g_dbus_proxy_call_sync(agent_manager_proxy, "RequestDefaultAgent", g_variant_new("(o)", FERALFILE_DBUS_AGENT_PATH),
                                     G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
         if (error) {
            log_warning("[%s] Failed to call RequestDefaultAgent: %s. (Might already have a default agent)", LOG_TAG, error->message);
            // Don't necessarily fail/retry just for default agent failure, could be acceptable.
            g_error_free(error); error = NULL; // Reset error
        } else {
            log_info("[%s] Agent registered and set as default successfully.", LOG_TAG);
        }
        if (ret) g_variant_unref(ret);

        // --- Step 6: Register GATT Application with BlueZ ---
        // Pass empty options dictionary a{sv}
        GVariantBuilder *options_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
        GVariant* app_params = g_variant_new("(oa{sv})", FERALFILE_DBUS_BASE_PATH, options_builder);
        // g_variant_builder_unref(options_builder); // ownership passed to app_params

        ret = g_dbus_proxy_call_sync(gatt_manager_proxy, "RegisterApplication", app_params,
                                     G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
        if (error) {
            log_error("[%s] Failed to call RegisterApplication: %s.", LOG_TAG, error->message);
            g_error_free(error); error = NULL;
            goto retry_or_fail;
        }
        if (ret) g_variant_unref(ret);
        log_info("[%s] GATT Application registered successfully.", LOG_TAG);


        // --- Step 7: Register Advertisement Object & Start Advertising ---
        // Need advertisement introspection XML first (can be simple)
         const gchar adv_introspection_xml[] =
            "<node name='" FERALFILE_DBUS_ADVERTISEMENT_PATH "'>"
            "  <interface name='" BLUEZ_INTF_LE_ADVERTISEMENT "'>"
            "    <method name='Release'/>" // Required method
            "    <property name='Type' type='s' access='read'/>"
            "    <property name='ServiceUUIDs' type='as' access='read'/>"
            "    <property name='LocalName' type='s' access='read'/>"
            // Add other properties here if needed in get_property
            "  </interface>"
            "</node>";
        advertisement_introspection_data = g_dbus_node_info_new_for_xml(adv_introspection_xml, &error);
         if (!advertisement_introspection_data || error) {
            log_error("[%s] Failed to parse advertisement introspection XML: %s.",
                      LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto thread_exit_failure; // No retry
        }
        GDBusInterfaceInfo* adv_interface = g_dbus_node_info_lookup_interface(advertisement_introspection_data, BLUEZ_INTF_LE_ADVERTISEMENT);
        if (!adv_interface) { log_error("[%s] LEAdvertisement1 interface not found in XML.", LOG_TAG); goto thread_exit_failure; }

        ad_reg_id = g_dbus_connection_register_object(connection, FERALFILE_DBUS_ADVERTISEMENT_PATH, adv_interface,
                                                     &advertisement_vtable, NULL, NULL, &error);
        if (!ad_reg_id || error) {
            log_error("[%s] Failed to register Advertisement object: %s.", LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            goto retry_or_fail;
        }

        // Pass empty options dictionary a{sv} for advertisement registration
        GVariantBuilder *adv_options_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
        GVariant* adv_reg_params = g_variant_new("(oa{sv})", FERALFILE_DBUS_ADVERTISEMENT_PATH, adv_options_builder);
        // g_variant_builder_unref(adv_options_builder); // ownership passed

        ret = g_dbus_proxy_call_sync(advertising_manager_proxy, "RegisterAdvertisement", adv_reg_params,
                                     G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
        if (error) {
             // Check for specific errors like "Already Exists" which might be okay
            if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_EXISTS) || // GIO mapping
                g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_FILE_EXISTS) || // DBus error
                 strstr(error->message, "Already Exists") != NULL) { // BlueZ specific error string
                 log_warning("[%s] Advertisement already registered: %s. Continuing...", LOG_TAG, error->message);
                 g_error_free(error); error = NULL;
             } else {
                 log_error("[%s] Failed to call RegisterAdvertisement: %s.", LOG_TAG, error->message);
                 g_error_free(error); error = NULL;
                 goto retry_or_fail;
             }
        }
        if (ret) g_variant_unref(ret);
        log_info("[%s] Advertisement registered successfully.", LOG_TAG);


        // --- Step 8: Start GMainLoop ---
        log_info("[%s] Initialization complete. Starting main loop...", LOG_TAG);
        initialized_successfully = TRUE; // Mark initialization as complete
        retry_count = 0; // Reset retry count as we succeeded

        main_loop = g_main_loop_new(NULL, FALSE);
        g_atomic_int_set(&main_loop_running, 1); // Indicate loop is starting
        g_main_loop_run(main_loop); // Blocks here until g_main_loop_quit()
        g_atomic_int_set(&main_loop_running, 0); // Indicate loop has stopped

        // --- Loop Exited ---
        log_info("[%s] Main loop finished.", LOG_TAG);
        // Cleanup resources managed by this loop iteration *before* potentially retrying
        cleanup_resources(); // Perform cleanup here
        // Check if we should attempt to restart
        if (!is_bluetooth_service_active()) {
            log_warning("[%s] Bluetooth service seems to have stopped. Attempting restart...", LOG_TAG);
            initialized_successfully = FALSE; // Force re-initialization attempt
             retry_count = 0; // Reset retries for re-initialization
            sleep(RETRY_DELAY_SECONDS); // Wait before retrying
            continue; // Go back to the start of the while loop
        } else {
             log_info("[%s] Bluetooth service still active. Exiting thread normally.", LOG_TAG);
             break; // Exit the while loop, thread finishes
        }

    // --- Retry / Failure Handling ---
    retry_or_fail:
        cleanup_resources(); // Clean up anything partially initialized in this attempt
        retry_count++;
        if (retry_count < MAX_RETRY_ATTEMPTS) {
            log_info("[%s] Retrying initialization in %d seconds (attempt %d/%d)...",
                     LOG_TAG, RETRY_DELAY_SECONDS, retry_count + 1, MAX_RETRY_ATTEMPTS);
            sleep(RETRY_DELAY_SECONDS);
        } else {
            log_error("[%s] Maximum retry attempts reached (%d). Initialization failed. Exiting thread.",
                      LOG_TAG, MAX_RETRY_ATTEMPTS);
            goto thread_exit_failure;
        }
    } // End while loop

thread_exit_failure:
    log_error("[%s] Bluetooth thread exiting due to unrecoverable error.", LOG_TAG);
    // Ensure final cleanup if exiting due to failure within the loop
    cleanup_resources();
    pthread_exit((void*)-1); // Indicate failure
    return NULL; // Should not be reached

// thread_exit_success: // Label not strictly needed as successful exit is after loop break
    log_info("[%s] Bluetooth thread exiting normally.", LOG_TAG);
    pthread_exit(NULL); // Indicate success
    return NULL;
}

// --- Public API Functions ---

int bluetooth_init(const char* custom_device_name) {
    log_info("[%s] Initializing Bluetooth Service...", LOG_TAG);

     // Initialize mutexes (already statically initialized, but good practice if dynamic)
     // pthread_mutex_init(&log_mutex, NULL);
     // pthread_mutex_init(&device_name_mutex, NULL);

    // Initial check for bluetooth service
    if (!is_bluetooth_service_active()) {
        log_warning("[%s] Bluetooth service not active at init, attempting to wait...", LOG_TAG);
        if (!wait_for_bluetooth_service()) {
            log_error("[%s] Bluetooth service failed to start during init.", LOG_TAG);
            return -1; // Cannot proceed
        }
    }

    // Set custom device name if provided (thread-safe)
    if (custom_device_name != NULL && strlen(custom_device_name) > 0) {
        pthread_mutex_lock(&device_name_mutex);
        strncpy(device_name, custom_device_name, MAX_DEVICE_NAME_LENGTH - 1);
        device_name[MAX_DEVICE_NAME_LENGTH - 1] = '\0'; // Ensure null termination
        log_info("[%s] Set custom device name to: %s", LOG_TAG, device_name);
        pthread_mutex_unlock(&device_name_mutex);
    } else {
         log_info("[%s] Using default device name: %s", LOG_TAG, FERALFILE_SERVICE_NAME);
    }

    // Initialize Sentry (if DSN is defined)
#ifdef SENTRY_DSN
    if (!sentry_initialized) {
        log_info("[%s] Initializing Sentry (DSN: %s)...", LOG_TAG, SENTRY_DSN);
        sentry_options_t* options = sentry_options_new();
        if (!options) {
             log_error("[%s] Failed to create Sentry options.", LOG_TAG);
        } else {
            sentry_options_set_dsn(options, SENTRY_DSN);
            sentry_options_set_database_path(options, "/tmp/.sentry-native-bluetooth"); // Use a hidden file in /tmp
            sentry_options_set_auto_session_tracking(options, true);

            #ifdef APP_VERSION
            log_info("[%s] Setting Sentry release: %s", LOG_TAG, APP_VERSION);
            sentry_options_set_release(options, APP_VERSION);
            #else
            log_warning("[%s] APP_VERSION not defined, Sentry release not set.", LOG_TAG);
            #endif

            #ifdef DEBUG
            log_info("[%s] Setting Sentry environment: development (Debug build)", LOG_TAG);
            sentry_options_set_environment(options, "development");
            sentry_options_set_debug(options, 1);
            #else
            log_info("[%s] Setting Sentry environment: production", LOG_TAG);
            sentry_options_set_environment(options, "production");
            #endif

            int init_result = sentry_init(options); // options ownership passed to sentry_init
            if (init_result == 0) {
                sentry_initialized = 1;
                log_info("[%s] Sentry initialized successfully.", LOG_TAG);

                // Set common tags
                sentry_set_tag("service", "bluetooth");
                pthread_mutex_lock(&device_name_mutex);
                sentry_set_tag("device_name", device_name);
                pthread_mutex_unlock(&device_name_mutex);
                log_info("[%s] Sentry tags set.", LOG_TAG);

                // Add initial breadcrumb
                sentry_value_t crumb = sentry_value_new_breadcrumb("default", "Bluetooth service initializing");
                if(!sentry_value_is_null(crumb)) sentry_add_breadcrumb(crumb);
            } else {
                log_error("[%s] Failed to initialize Sentry, error code: %d", LOG_TAG, init_result);
                // Continue without Sentry if initialization fails
            }
        }
    } else {
         log_info("[%s] Sentry already initialized.", LOG_TAG);
    }
#else
    log_info("[%s] Sentry DSN not defined, Sentry integration skipped.", LOG_TAG);
#endif

    // Create and start the Bluetooth handler thread
    log_info("[%s] Creating Bluetooth background thread...", LOG_TAG);
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_thread_func, NULL) != 0) {
        log_error("[%s] Failed to create Bluetooth thread: %s", LOG_TAG, strerror(errno));
        // Cleanup any partial init (like Sentry) if needed here
        #ifdef SENTRY_DSN
        if (sentry_initialized) {
            sentry_close();
            sentry_initialized = 0;
        }
        #endif
        return -1;
    }

    log_info("[%s] Bluetooth initialization sequence initiated in background thread.", LOG_TAG);
    return 0; // Success (thread creation succeeded)
}

int bluetooth_start(connection_result_callback setup_cb, command_callback cmd_cb, device_connection_callback conn_cb) {
    log_info("[%s] Registering Bluetooth event callbacks.", LOG_TAG);
    // Store callbacks (assuming this is called after init and before significant thread activity)
    setup_data_callback = setup_cb;
    command_data_callback = cmd_cb;
    connection_status_callback = conn_cb;
    return 0;
}

// Consolidated resource cleanup function
static void cleanup_resources() {
    log_info("[%s] Cleaning up Bluetooth D-Bus resources...", LOG_TAG);
     GError *error = NULL;

    // --- Unregister BlueZ components ---
    // Unregister Agent (best effort)
    if (agent_manager_proxy && agent_reg_id > 0) {
        GVariant* agent_path_var = g_variant_new("(o)", FERALFILE_DBUS_AGENT_PATH);
        g_dbus_proxy_call_sync(agent_manager_proxy, "UnregisterAgent", agent_path_var,
                               G_DBUS_CALL_FLAGS_NONE, 500, NULL, &error); // Short timeout
        if (error) {
            log_warning("[%s] Failed to unregister agent: %s (continuing cleanup)", LOG_TAG, error->message);
            g_error_free(error); error = NULL;
        } else {
            log_info("[%s] Agent unregistered.", LOG_TAG);
        }
        // Path variant is consumed by call, no need to unref
    }
    // Unregister Advertisement (best effort)
    if (advertising_manager_proxy && ad_reg_id > 0) {
         GVariant* adv_path_var = g_variant_new("(o)", FERALFILE_DBUS_ADVERTISEMENT_PATH);
        g_dbus_proxy_call_sync(advertising_manager_proxy, "UnregisterAdvertisement", adv_path_var,
                               G_DBUS_CALL_FLAGS_NONE, 500, NULL, &error); // Short timeout
        if (error) {
            log_warning("[%s] Failed to unregister advertisement: %s (continuing cleanup)", LOG_TAG, error->message);
            g_error_free(error); error = NULL;
        } else {
             log_info("[%s] Advertisement unregistered.", LOG_TAG);
        }
    }
    // Unregister Application (best effort)
    if (gatt_manager_proxy && objects_reg_id > 0) { // Assuming app registration tied to object manager root
        GVariant* app_path_var = g_variant_new("(o)", FERALFILE_DBUS_BASE_PATH);
        g_dbus_proxy_call_sync(gatt_manager_proxy, "UnregisterApplication", app_path_var,
                               G_DBUS_CALL_FLAGS_NONE, 500, NULL, &error); // Short timeout
        if (error) {
            log_warning("[%s] Failed to unregister application: %s (continuing cleanup)", LOG_TAG, error->message);
            g_error_free(error); error = NULL;
        } else {
            log_info("[%s] GATT Application unregistered.", LOG_TAG);
        }
    }

    // --- Unregister D-Bus objects ---
    // Check connection and registration ID before unregistering
    if (connection) {
        if (ad_reg_id > 0) g_dbus_connection_unregister_object(connection, ad_reg_id);
        if (agent_reg_id > 0) g_dbus_connection_unregister_object(connection, agent_reg_id);
        if (eng_char_reg_id > 0) g_dbus_connection_unregister_object(connection, eng_char_reg_id);
        if (cmd_char_reg_id > 0) g_dbus_connection_unregister_object(connection, cmd_char_reg_id);
        if (setup_char_reg_id > 0) g_dbus_connection_unregister_object(connection, setup_char_reg_id);
        if (service_reg_id > 0) g_dbus_connection_unregister_object(connection, service_reg_id);
        if (objects_reg_id > 0) g_dbus_connection_unregister_object(connection, objects_reg_id);
    }
    ad_reg_id = agent_reg_id = eng_char_reg_id = cmd_char_reg_id = setup_char_reg_id = service_reg_id = objects_reg_id = 0;


    // --- Unref GObject resources ---
    if (agent_manager_proxy) g_object_unref(agent_manager_proxy);
    if (advertising_manager_proxy) g_object_unref(advertising_manager_proxy);
    if (gatt_manager_proxy) g_object_unref(gatt_manager_proxy);
    agent_manager_proxy = advertising_manager_proxy = gatt_manager_proxy = NULL;

    if (advertisement_introspection_data) g_dbus_node_info_unref(advertisement_introspection_data);
    if (agent_introspection_data) g_dbus_node_info_unref(agent_introspection_data);
    if (root_node_info) g_dbus_node_info_unref(root_node_info);
     advertisement_introspection_data = agent_introspection_data = root_node_info = NULL;

    // Don't unref connection here, might be needed if retrying
    log_info("[%s] D-Bus resources cleaned up.", LOG_TAG);
}

void bluetooth_stop() {
    log_info("[%s] Stopping Bluetooth Service...", LOG_TAG);

    // 1. Signal the main loop to quit if it's running
    if (g_atomic_int_get(&main_loop_running) && main_loop) {
        log_info("[%s] Requesting main loop quit...", LOG_TAG);
        g_main_loop_quit(main_loop);
    } else {
         log_info("[%s] Main loop not running or already quit.", LOG_TAG);
    }

    // 2. Join the thread (wait for it to finish cleanup and exit)
    log_info("[%s] Waiting for Bluetooth thread to exit...", LOG_TAG);
    // Note: pthread_join might block indefinitely if the thread doesn't exit.
    // Consider adding a timeout mechanism if this is a concern.
    int join_result = pthread_join(bluetooth_thread, NULL);
     if (join_result != 0) {
         log_error("[%s] Failed to join Bluetooth thread: %s", LOG_TAG, strerror(join_result));
         // Continue cleanup as much as possible even if join fails
     } else {
         log_info("[%s] Bluetooth thread joined successfully.", LOG_TAG);
     }


     // 3. Perform final cleanup (most resources should be cleaned by the thread or cleanup_resources)
    cleanup_resources(); // Call again to ensure cleanup if thread failed mid-init

    // 4. Unref the main loop *after* the thread using it has exited
    if (main_loop) {
        g_main_loop_unref(main_loop);
        main_loop = NULL;
        log_info("[%s] Main loop unreferenced.", LOG_TAG);
    }

     // 5. Unref the D-Bus connection
    if (connection) {
        // Optional: Flush connection before closing if desired
        // g_dbus_connection_flush_sync(connection, NULL, NULL);
        g_object_unref(connection);
        connection = NULL;
        log_info("[%s] D-Bus connection closed and unreferenced.", LOG_TAG);
    }

    // 6. Close log file (thread-safe)
    pthread_mutex_lock(&log_mutex);
    if (log_file != NULL) {
        fclose(log_file);
        log_file = NULL;
        log_info("[%s] Log file closed.", LOG_TAG); // Log to syslog/stderr
    }
    pthread_mutex_unlock(&log_mutex);

    // 7. Close Sentry
#ifdef SENTRY_DSN
    if (sentry_initialized) {
        log_info("[%s] Closing Sentry...", LOG_TAG); // Log to syslog/stderr
        sentry_close();
        sentry_initialized = 0;
        log_info("[%s] Sentry closed.", LOG_TAG);
    }
#endif

    // 8. Destroy mutexes (if dynamically allocated)
    // pthread_mutex_destroy(&log_mutex);
    // pthread_mutex_destroy(&device_name_mutex);

    log_info("[%s] Bluetooth service stopped.", LOG_TAG);
}

// --- Data Sending Functions ---

// Helper to emit PropertiesChanged signal for characteristic value
static void emit_char_value_changed(const char* char_path, const unsigned char* data, int length) {
     if (!connection || !g_atomic_int_get(&main_loop_running)) {
        log_error("[%s] Cannot notify/send on %s: D-Bus connection not active or main loop stopped.", LOG_TAG, char_path);
        return;
    }

    // Create GVariant for the notification value (byte array)
    GVariant *value_variant = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, data, length, sizeof(guchar));
    if (!value_variant) {
        log_error("[%s] Failed to create GVariant for notification data on %s", LOG_TAG, char_path);
        return;
    }

    // Create the dictionary of changed properties: { "Value": <byte_array> }
    GVariantBuilder *props_builder = g_variant_builder_new(G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(props_builder, "{sv}", "Value", value_variant); // value_variant ownership passed to builder

    // Create the array of invalidated properties (empty in this case)
    GVariantBuilder *invalidated_builder = g_variant_builder_new(G_VARIANT_TYPE("as"));
    // No invalidated properties, pass the empty builder

    // Emit PropertiesChanged signal
    // Signature: ( String interface_name, Dict<String,Variant> changed_properties, Array<String> invalidated_properties )
    GVariant *signal_params = g_variant_new("(sa{sv}as)",
                                            BLUEZ_INTF_GATT_CHARACTERISTIC,
                                            props_builder, // Ownership passed
                                            invalidated_builder); // Ownership passed

    GError *error = NULL;
    gboolean success = g_dbus_connection_emit_signal(connection,
                                                    NULL,       // destination bus name (broadcast)
                                                    char_path,  // object path of the characteristic
                                                    DBUS_INTF_PROPERTIES, // Properties interface
                                                    "PropertiesChanged",  // Signal name
                                                    signal_params, // Parameters (ownership passed)
                                                    &error);

    if (!success || error) {
        log_error("[%s] Failed to emit PropertiesChanged signal for %s: %s",
                  LOG_TAG, char_path, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
    } else {
        // Log hex string for debugging *after* successful emission attempt
        if (length > 0) {
            gsize hex_len = length * 3 + 1;
            char *hex_string = malloc(hex_len);
            if (hex_string) {
                for (size_t i = 0; i < length; i++) {
                    snprintf(hex_string + (i * 3), 4, "%02x ", data[i]);
                }
                hex_string[hex_len - 2] = '\0';
                log_info("[%s] Notified %d bytes on %s: %s", LOG_TAG, length, char_path, hex_string);
                free(hex_string);
            }
        } else {
             log_info("[%s] Notified 0 bytes on %s", LOG_TAG, char_path);
        }
    }

    // Builders were consumed by g_variant_new, no need to unref here
    // g_variant_builder_unref(props_builder);
    // g_variant_builder_unref(invalidated_builder);
}

// Send notification on Command Characteristic
void bluetooth_notify(const unsigned char* data, int length) {
    if (length < 0) {
        log_warning("[%s] Invalid length (%d) passed to bluetooth_notify", LOG_TAG, length);
        return;
    }
    emit_char_value_changed(FERALFILE_DBUS_CMD_CHAR_PATH, data, length);
}

// Send notification on Engineering Characteristic
void bluetooth_send_engineering_data(const unsigned char* data, int length) {
    if (length < 0) {
        log_warning("[%s] Invalid length (%d) passed to bluetooth_send_engineering_data", LOG_TAG, length);
        return;
    }
    emit_char_value_changed(FERALFILE_DBUS_ENG_CHAR_PATH, data, length);
}


// --- Utility Functions ---

// Get Bluetooth adapter MAC address safely into a provided buffer.
// Returns 0 on success, -1 on failure.
int bluetooth_get_mac_address(char* mac_address_buffer, size_t buffer_size) {
     if (mac_address_buffer == NULL || buffer_size < MAC_ADDRESS_STR_LEN) {
        log_error("[%s] Invalid buffer provided to bluetooth_get_mac_address (buffer=%p, size=%zu, required=%d)",
                  LOG_TAG, mac_address_buffer, buffer_size, MAC_ADDRESS_STR_LEN);
        return -1;
     }

    bdaddr_t bdaddr; // Bluetooth device address structure
    int dev_id = -1;
    int sock = -1;

    // Find the first available HCI device route (e.g., hci0)
    dev_id = hci_get_route(NULL);
    if (dev_id < 0) {
        log_error("[%s] Could not get default Bluetooth device route: %s (hci_get_route error %d)", LOG_TAG, strerror(errno), errno);
        return -1;
    }

    // Open a socket to the HCI device
    sock = hci_open_dev(dev_id);
    if (sock < 0) {
        log_error("[%s] Could not open HCI device %d: %s (hci_open_dev error %d)", LOG_TAG, dev_id, strerror(errno), errno);
        return -1;
    }

    // Read the local Bluetooth device address
    if (hci_read_bd_addr(sock, &bdaddr, 1000) < 0) { // 1 second timeout
        log_error("[%s] Could not read Bluetooth address from device %d: %s (hci_read_bd_addr error %d)", LOG_TAG, dev_id, strerror(errno), errno);
        close(sock);
        return -1;
    }

    // Convert the binary address to a string format (XX:XX:XX:XX:XX:XX)
    ba2str(&bdaddr, mac_address_buffer); // ba2str expects buffer of at least 18 bytes

    close(sock); // Close the socket

    log_info("[%s] Local Bluetooth MAC address: %s (Device hci%d)", LOG_TAG, mac_address_buffer, dev_id);
    return 0; // Success
}

/**
 * @brief Frees the data buffer received via setup_data_callback or command_data_callback.
 *
 * @param data Pointer to the data buffer allocated internally and passed to the callback.
 * This function MUST be called by the user application to prevent memory leaks
 * after processing the data received in the callbacks.
 */
void bluetooth_free_data(unsigned char* data) {
    if (data != NULL) {
        free(data);
    }
}