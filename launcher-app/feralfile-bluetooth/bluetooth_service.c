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
#define MAX_LOG_LINES 100
#define LOG_QUEUE_SIZE 1000

// Log message structure
typedef struct {
    char* message;
    int is_flush_request;  // Special flag to request log flushing
    int is_shutdown;       // Special flag to request thread shutdown
} LogMessage;

// Log buffer to store recent log entries
static char* log_buffer[MAX_LOG_LINES];
static int log_buffer_index = 0;
static int log_buffer_full = 0;
static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

// Log queue for asynchronous logging
static LogMessage log_queue[LOG_QUEUE_SIZE];
static int log_queue_head = 0;
static int log_queue_tail = 0;
static pthread_mutex_t queue_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t queue_cond = PTHREAD_COND_INITIALIZER;
static pthread_t log_thread;
static int log_thread_running = 0;

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

typedef void (*device_connection_callback)(const char* device_id, int connected);
static device_connection_callback connection_callback = NULL;

static FILE* log_file = NULL;
static char log_file_path[512] = {0};  // Store the log file path

static char device_name[MAX_DEVICE_NAME_LENGTH] = FERALFILE_SERVICE_NAME;
static char advertisement_path[MAX_ADV_PATH_LENGTH] = "/com/feralfile/display/advertisement0";

static int sentry_initialized = 0;

// Track notification status
static gboolean cmd_char_notify_enabled = FALSE;
static gboolean eng_char_notify_enabled = FALSE;

// Function declarations
static void setup_dbus_signal_handlers(GDBusConnection *connection);
static void handle_property_change(GDBusConnection *connection,
                                 const gchar *sender_name,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *signal_name,
                                 GVariant *parameters,
                                 gpointer user_data);
static void write_log_buffer_to_file(void);
static void* log_thread_func(void* arg);
static void enqueue_log_message(const char* message);
static void request_log_flush(void);
static void shutdown_log_thread(void);

// Initialize the log buffer
static void init_log_buffer(void) {
    pthread_mutex_lock(&log_mutex);
    for (int i = 0; i < MAX_LOG_LINES; i++) {
        log_buffer[i] = NULL;
    }
    log_buffer_index = 0;
    log_buffer_full = 0;
    pthread_mutex_unlock(&log_mutex);
}

// Free the log buffer
static void free_log_buffer(void) {
    pthread_mutex_lock(&log_mutex);
    for (int i = 0; i < MAX_LOG_LINES; i++) {
        if (log_buffer[i] != NULL) {
            free(log_buffer[i]);
            log_buffer[i] = NULL;
        }
    }
    pthread_mutex_unlock(&log_mutex);
}

// Add a message to the log buffer
static void add_to_log_buffer(const char* level, const char* timestamp, const char* message) {
    pthread_mutex_lock(&log_mutex);
    
    // Free the entry we're about to overwrite
    if (log_buffer[log_buffer_index] != NULL) {
        free(log_buffer[log_buffer_index]);
    }
    
    // Allocate and store the new log entry
    int len = strlen(timestamp) + strlen(level) + strlen(message) + 10; // Extra space for formatting
    log_buffer[log_buffer_index] = (char*)malloc(len);
    if (log_buffer[log_buffer_index] != NULL) {
        snprintf(log_buffer[log_buffer_index], len, "%s: %s: %s", timestamp, level, message);
        
        // Update buffer state
        log_buffer_index = (log_buffer_index + 1) % MAX_LOG_LINES;
        if (!log_buffer_full && log_buffer_index == 0) {
            log_buffer_full = 1;
        }
    }
    
    pthread_mutex_unlock(&log_mutex);
}

// Enqueue a log message for the logging thread
static void enqueue_log_message(const char* message) {
    pthread_mutex_lock(&queue_mutex);
    
    // Check if queue is full
    if ((log_queue_head + 1) % LOG_QUEUE_SIZE == log_queue_tail) {
        // Queue is full, discard the oldest message
        if (log_queue[log_queue_tail].message != NULL) {
            free(log_queue[log_queue_tail].message);
        }
        log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
    }
    
    // Add the new message to the queue
    log_queue[log_queue_head].message = strdup(message);
    log_queue[log_queue_head].is_flush_request = 0;
    log_queue[log_queue_head].is_shutdown = 0;
    log_queue_head = (log_queue_head + 1) % LOG_QUEUE_SIZE;
    
    // Signal the logging thread that there's work to do
    pthread_cond_signal(&queue_cond);
    pthread_mutex_unlock(&queue_mutex);
}

// Request flushing the log buffer to disk
static void request_log_flush(void) {
    pthread_mutex_lock(&queue_mutex);
    
    // Check if queue is full
    if ((log_queue_head + 1) % LOG_QUEUE_SIZE == log_queue_tail) {
        // Queue is full, discard the oldest message
        if (log_queue[log_queue_tail].message != NULL) {
            free(log_queue[log_queue_tail].message);
        }
        log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
    }
    
    // Add a flush request
    log_queue[log_queue_head].message = NULL;
    log_queue[log_queue_head].is_flush_request = 1;
    log_queue[log_queue_head].is_shutdown = 0;
    log_queue_head = (log_queue_head + 1) % LOG_QUEUE_SIZE;
    
    // Signal the logging thread
    pthread_cond_signal(&queue_cond);
    pthread_mutex_unlock(&queue_mutex);
}

// Shutdown the logging thread
static void shutdown_log_thread(void) {
    if (!log_thread_running) {
        return;
    }
    
    pthread_mutex_lock(&queue_mutex);
    
    // Check if queue is full
    if ((log_queue_head + 1) % LOG_QUEUE_SIZE == log_queue_tail) {
        // Queue is full, discard the oldest message
        if (log_queue[log_queue_tail].message != NULL) {
            free(log_queue[log_queue_tail].message);
        }
        log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
    }
    
    // Add a shutdown request
    log_queue[log_queue_head].message = NULL;
    log_queue[log_queue_head].is_flush_request = 0;
    log_queue[log_queue_head].is_shutdown = 1;
    log_queue_head = (log_queue_head + 1) % LOG_QUEUE_SIZE;
    
    // Signal the logging thread
    pthread_cond_signal(&queue_cond);
    pthread_mutex_unlock(&queue_mutex);
    
    // Wait for the logging thread to finish
    pthread_join(log_thread, NULL);
    log_thread_running = 0;
}

// The main function for the logging thread
static void* log_thread_func(void* arg) {
    LogMessage current_message;
    
    while (1) {
        // Wait for a message in the queue
        pthread_mutex_lock(&queue_mutex);
        while (log_queue_head == log_queue_tail) {
            pthread_cond_wait(&queue_cond, &queue_mutex);
        }
        
        // Get the next message
        current_message = log_queue[log_queue_tail];
        log_queue[log_queue_tail].message = NULL; // Avoid double-free
        log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
        pthread_mutex_unlock(&queue_mutex);
        
        // Check if it's a shutdown request
        if (current_message.is_shutdown) {
            // Write any remaining logs before exiting
            write_log_buffer_to_file();
            break;
        }
        
        // Check if it's a flush request
        if (current_message.is_flush_request) {
            write_log_buffer_to_file();
        } else if (current_message.message != NULL) {
            // It's a regular log message, append to file
            if (log_file != NULL) {
                fprintf(log_file, "%s\n", current_message.message);
                fflush(log_file);
            }
            free(current_message.message);
        }
    }
    
    return NULL;
}

// Write the log buffer to file
static void write_log_buffer_to_file(void) {
    if (log_file == NULL) {
        return;
    }
    
    pthread_mutex_lock(&log_mutex);
    
    // First, truncate the file
    fseek(log_file, 0, SEEK_SET);
    if (ftruncate(fileno(log_file), 0) != 0) {
        // Handle error silently - don't want to create an infinite loop with logging
        pthread_mutex_unlock(&log_mutex);
        return;
    }
    
    // Write entries to file in chronological order
    int count = log_buffer_full ? MAX_LOG_LINES : log_buffer_index;
    int start = log_buffer_full ? log_buffer_index : 0;
    
    for (int i = 0; i < count; i++) {
        int idx = (start + i) % MAX_LOG_LINES;
        if (log_buffer[idx] != NULL) {
            fprintf(log_file, "%s\n", log_buffer[idx]);
        }
    }
    
    fflush(log_file);
    pthread_mutex_unlock(&log_mutex);
}

// Start the logging thread
static void start_log_thread(void) {
    if (log_thread_running) {
        return;
    }
    
    // Clear the log queue
    pthread_mutex_lock(&queue_mutex);
    while (log_queue_head != log_queue_tail) {
        if (log_queue[log_queue_tail].message != NULL) {
            free(log_queue[log_queue_tail].message);
            log_queue[log_queue_tail].message = NULL;
        }
        log_queue_tail = (log_queue_tail + 1) % LOG_QUEUE_SIZE;
    }
    pthread_mutex_unlock(&queue_mutex);
    
    // Start the log thread
    log_thread_running = 1;
    pthread_create(&log_thread, NULL, log_thread_func, NULL);
}

void bluetooth_set_logfile(const char* path) {
    // Save the path
    strncpy(log_file_path, path, sizeof(log_file_path) - 1);
    log_file_path[sizeof(log_file_path) - 1] = '\0';
    
    // Request a flush if log thread is running
    if (log_thread_running) {
        request_log_flush();
    }
    
    // Close existing file
    if (log_file != NULL) {
        fclose(log_file);
    }
    
    // Open in write mode initially to clear it
    log_file = fopen(path, "w");
    if (log_file != NULL) {
        // Write existing buffer if we have one
        write_log_buffer_to_file();
        // Close and reopen in append mode for future writes
        fclose(log_file);
        log_file = fopen(path, "a");
    }
    
    // Start the log thread if needed
    if (!log_thread_running && log_file != NULL) {
        start_log_thread();
    }
}

static void log_info(const char* format, ...) {
    va_list args, args_copy1, args_copy2;
    va_start(args, format);
    va_copy(args_copy1, args);
    va_copy(args_copy2, args);
    
    // Get current time
    time_t now;
    time(&now);
    char timestamp[26];
    ctime_r(&now, timestamp);
    timestamp[24] = '\0'; // Remove newline
    
    // Format the message
    char message[1024];
    vsnprintf(message, sizeof(message), format, args_copy1);
    
    // Log to syslog
    vsyslog(LOG_INFO, format, args);
    
    // Log to console (stdout)
    fprintf(stdout, "%s: INFO: ", timestamp);
    vfprintf(stdout, format, args_copy2);
    fprintf(stdout, "\n");
    fflush(stdout);  // Ensure immediate output
    
    // Add to log buffer
    add_to_log_buffer("INFO", timestamp, message);
    
    // Format the complete message for the log file
    char full_message[1200];
    snprintf(full_message, sizeof(full_message), "%s: INFO: %s", timestamp, message);
    
    // Enqueue the message for the logging thread instead of writing directly
    enqueue_log_message(full_message);
    
    // Every 50 log messages, request a flush
    static int log_counter = 0;
    log_counter = (log_counter + 1) % 50;
    if (log_counter == 0) {
        request_log_flush();
    }
    
    // Add Sentry breadcrumb for info messages
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("info", message);
        sentry_value_set_by_key(crumb, "category", sentry_value_new_string("bluetooth"));
        sentry_add_breadcrumb(crumb);
    }
    #endif
    
    va_end(args_copy2);
    va_end(args_copy1);
    va_end(args);
}

static void log_error(const char* format, ...) {
    va_list args, args_copy1, args_copy2;
    va_start(args, format);
    va_copy(args_copy1, args);
    va_copy(args_copy2, args);
    
    // Get current time
    time_t now;
    time(&now);
    char timestamp[26];
    ctime_r(&now, timestamp);
    timestamp[24] = '\0'; // Remove newline
    
    // Format the message
    char message[1024];
    vsnprintf(message, sizeof(message), format, args_copy1);
    
    // Log to syslog
    vsyslog(LOG_ERR, format, args);
    
    // Log to console (stderr)
    fprintf(stderr, "%s: ERROR: ", timestamp);
    vfprintf(stderr, format, args_copy2);
    fprintf(stderr, "\n");
    fflush(stderr);  // Ensure immediate output
    
    // Add to log buffer
    add_to_log_buffer("ERROR", timestamp, message);
    
    // Format the complete message for the log file
    char full_message[1200];
    snprintf(full_message, sizeof(full_message), "%s: ERROR: %s", timestamp, message);
    
    // Enqueue the message for the logging thread
    enqueue_log_message(full_message);
    
    // Always request a flush for errors
    request_log_flush();
    
    // Capture Sentry event for error messages
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t event = sentry_value_new_message_event(
            SENTRY_LEVEL_ERROR,
            "bluetooth",
            message
        );
        sentry_capture_event(event);
    }
    #endif
    
    va_end(args_copy2);
    va_end(args_copy1);
    va_end(args);
}

static void log_warning(const char* format, ...) {
    va_list args, args_copy1, args_copy2;
    va_start(args, format);
    va_copy(args_copy1, args);
    va_copy(args_copy2, args);
    
    // Get current time
    time_t now;
    time(&now);
    char timestamp[26];
    ctime_r(&now, timestamp);
    timestamp[24] = '\0'; // Remove newline
    
    // Format the message
    char message[1024];
    vsnprintf(message, sizeof(message), format, args_copy1);
    
    // Log to syslog
    vsyslog(LOG_WARNING, format, args);
    
    // Log to console (stderr)
    fprintf(stderr, "%s: WARNING: ", timestamp);
    vfprintf(stderr, format, args_copy2);
    fprintf(stderr, "\n");
    fflush(stderr);
    
    // Add to log buffer
    add_to_log_buffer("WARNING", timestamp, message);
    
    // Format the complete message for the log file
    char full_message[1200];
    snprintf(full_message, sizeof(full_message), "%s: WARNING: %s", timestamp, message);
    
    // Enqueue the message for the logging thread
    enqueue_log_message(full_message);
    
    // Add Sentry breadcrumb for warning messages
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("warning", message);
        sentry_value_set_by_key(crumb, "category", sentry_value_new_string("bluetooth"));
        sentry_add_breadcrumb(crumb);
    }
    #endif
    
    va_end(args_copy2);
    va_end(args_copy1);
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
    
    // Add error checking for parameters
    if (!parameters) {
        log_error("[%s] (setup_char) Received NULL parameters", LOG_TAG);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    // Log the parameter type
    log_info("[%s] (setup_char) Parameter type: %s", LOG_TAG, g_variant_get_type_string(parameters));
    
    // Safely extract the parameters
    if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(aya{sv})"))) {
        log_error("[%s] (setup_char) Parameters not of expected type (aya{sv}): got %s", 
                 LOG_TAG, g_variant_get_type_string(parameters));
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    g_variant_get(parameters, "(@aya{sv})", &array_variant, &options_variant);
    
    // Check if array_variant is valid
    if (!array_variant) {
        log_error("[%s] (setup_char) Failed to extract array variant", LOG_TAG);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    // Check if array_variant is of correct type
    if (!g_variant_is_of_type(array_variant, G_VARIANT_TYPE_ARRAY)) {
        log_error("[%s] (setup_char) array_variant not of array type: %s", 
                 LOG_TAG, g_variant_get_type_string(array_variant));
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));
    
    // Check if data extraction succeeded
    if (!data) {
        log_error("[%s] (setup_char) Failed to extract data from array variant", LOG_TAG);
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

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

    // If you want to pass these bytes to your existing 'result_callback'
    if (result_callback) {
        result_callback(1, data_copy, (int)n_elements);
    }

    // Add Sentry breadcrumb
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", "Received setup data");
        sentry_value_set_by_key(crumb, "data_length", sentry_value_new_int32((int32_t)n_elements));
        sentry_add_breadcrumb(crumb);
    }
    #endif

    g_variant_unref(array_variant);
    if (options_variant) {
        g_variant_unref(options_variant);
    }
    
    g_dbus_method_invocation_return_value(invocation, NULL);
}

// ----------------------------------------------------------------------------
// Handler for cmd_char writes
// ----------------------------------------------------------------------------
static void handle_cmd_char_method(GDBusConnection *conn,
                                 const gchar *sender,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *method_name,
                                 GVariant *parameters,
                                 GDBusMethodInvocation *invocation,
                                 gpointer user_data) {
    
    log_info("[%s] Method %s called on cmd_char by %s", LOG_TAG, method_name, sender);
    
    if (g_strcmp0(method_name, "WriteValue") == 0) {
        // Handle write the same as before
        handle_command_write(conn, sender, object_path, interface_name, 
                            method_name, parameters, invocation, user_data);
    } 
    else if (g_strcmp0(method_name, "StartNotify") == 0) {
        log_info("[%s] StartNotify called for cmd_char by %s", LOG_TAG, sender);
        cmd_char_notify_enabled = TRUE;
        g_dbus_method_invocation_return_value(invocation, NULL);
    } 
    else if (g_strcmp0(method_name, "StopNotify") == 0) {
        log_info("[%s] StopNotify called for cmd_char by %s", LOG_TAG, sender);
        cmd_char_notify_enabled = FALSE;
        g_dbus_method_invocation_return_value(invocation, NULL);
    }
    else {
        // Unknown method
        log_warning("[%s] Unknown method %s called on cmd_char", LOG_TAG, method_name);
        g_dbus_method_invocation_return_error(invocation,
                                             G_DBUS_ERROR,
                                             G_DBUS_ERROR_UNKNOWN_METHOD,
                                             "Unknown method: %s", method_name);
    }
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
    
    // Add error checking for parameters
    if (!parameters) {
        log_error("[%s] (cmd_char) Received NULL parameters", LOG_TAG);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    // Log the parameter type
    log_info("[%s] (cmd_char) Parameter type: %s", LOG_TAG, g_variant_get_type_string(parameters));
    
    // Safely extract the parameters
    if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(aya{sv})"))) {
        log_error("[%s] (cmd_char) Parameters not of expected type (aya{sv}): got %s", 
                 LOG_TAG, g_variant_get_type_string(parameters));
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    g_variant_get(parameters, "(@aya{sv})", &array_variant, &options_variant);
    
    // Check if array_variant is valid
    if (!array_variant) {
        log_error("[%s] (cmd_char) Failed to extract array variant", LOG_TAG);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }
    
    // Check if array_variant is of correct type
    if (!g_variant_is_of_type(array_variant, G_VARIANT_TYPE_ARRAY)) {
        log_error("[%s] (cmd_char) array_variant not of array type: %s", 
                 LOG_TAG, g_variant_get_type_string(array_variant));
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    gsize n_elements;
    const guchar *data = g_variant_get_fixed_array(array_variant, &n_elements, sizeof(guchar));
    
    // Check if data extraction succeeded
    if (!data) {
        log_error("[%s] (cmd_char) Failed to extract data from array variant", LOG_TAG);
        g_variant_unref(array_variant);
        if (options_variant) g_variant_unref(options_variant);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

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

    // Use cmd_callback with the copied data
    if (cmd_callback) {
        cmd_callback(1, data_copy, (int)n_elements);
    }

    // Add Sentry breadcrumb
    #ifdef SENTRY_DSN
    if (sentry_initialized) {
        sentry_value_t crumb = sentry_value_new_breadcrumb("bluetooth", "Received command data");
        sentry_value_set_by_key(crumb, "data_length", sentry_value_new_int32((int32_t)n_elements));
        sentry_add_breadcrumb(crumb);
    }
    #endif

    g_variant_unref(array_variant);
    if (options_variant) {
        g_variant_unref(options_variant);
    }
    
    g_dbus_method_invocation_return_value(invocation, NULL);
}

// ----------------------------------------------------------------------------
// Handler for eng_char writes
// ----------------------------------------------------------------------------
static void handle_eng_char_method(GDBusConnection *conn,
                                 const gchar *sender,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *method_name,
                                 GVariant *parameters,
                                 GDBusMethodInvocation *invocation,
                                 gpointer user_data) {
    
    log_info("[%s] Method %s called on eng_char by %s", LOG_TAG, method_name, sender);
    
    if (g_strcmp0(method_name, "StartNotify") == 0) {
        log_info("[%s] StartNotify called for eng_char by %s", LOG_TAG, sender);
        eng_char_notify_enabled = TRUE;
        g_dbus_method_invocation_return_value(invocation, NULL);
    } 
    else if (g_strcmp0(method_name, "StopNotify") == 0) {
        log_info("[%s] StopNotify called for eng_char by %s", LOG_TAG, sender);
        eng_char_notify_enabled = FALSE;
        g_dbus_method_invocation_return_value(invocation, NULL);
    }
    else {
        // Unknown method
        log_warning("[%s] Unknown method %s called on eng_char", LOG_TAG, method_name);
        g_dbus_method_invocation_return_error(invocation,
                                             G_DBUS_ERROR,
                                             G_DBUS_ERROR_UNKNOWN_METHOD,
                                             "Unknown method: %s", method_name);
    }
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
    .method_call = handle_cmd_char_method,
    .get_property = char_get_property,
    .set_property = NULL
};

// Vtable for engineering characteristic
static const GDBusInterfaceVTable eng_char_vtable = {
    .method_call = handle_eng_char_method,
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

static int is_bluetooth_service_active() {
    FILE *fp;
    char buffer[128];
    int active = 0;

    fp = popen("systemctl is-active bluetooth", "r");
    if (fp == NULL) {
        log_error("[%s] Failed to check bluetooth service status", LOG_TAG);
        return 0;
    }

    if (fgets(buffer, sizeof(buffer), fp) != NULL) {
        active = (strncmp(buffer, "active", 6) == 0);
    }

    pclose(fp);
    return active;
}

static int wait_for_bluetooth_service() {
    int attempts = 0;
    while (attempts < MAX_RETRY_ATTEMPTS) {
        if (is_bluetooth_service_active()) {
            log_info("[%s] Bluetooth service is active", LOG_TAG);
            // Give the service a moment to fully initialize
            sleep(1);
            return 1;
        }
        
        log_info("[%s] Waiting for Bluetooth service (attempt %d/%d)...", 
                LOG_TAG, attempts + 1, MAX_RETRY_ATTEMPTS);
        sleep(RETRY_DELAY_SECONDS);
        attempts++;
    }
    
    log_error("[%s] Bluetooth service did not become active after %d attempts", 
              LOG_TAG, MAX_RETRY_ATTEMPTS);
    return 0;
}

static void setup_dbus_signal_handlers(GDBusConnection *connection) {
    g_dbus_connection_signal_subscribe(
        connection,
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

static void handle_property_change(GDBusConnection *connection,
                                 const gchar *sender_name,
                                 const gchar *object_path,
                                 const gchar *interface_name,
                                 const gchar *signal_name,
                                 GVariant *parameters,
                                 gpointer user_data) {
    GVariant *changed_properties;
    GVariant *invalidated_properties;
    const gchar *interface;
    
    g_variant_get(parameters, "(&sa{sv}as)",
                  &interface,
                  &changed_properties,
                  &invalidated_properties);

    if (g_str_equal(interface, "org.bluez.Device1")) {
        GVariantIter iter;
        const gchar *key;
        GVariant *value;
        
        g_variant_iter_init(&iter, changed_properties);
        while (g_variant_iter_next(&iter, "{&sv}", &key, &value)) {
            if (g_str_equal(key, "Connected")) {
                gboolean connected;
                g_variant_get(value, "b", &connected);
                
                // Extract device ID from the device path
                const char* device_id = strrchr(object_path, '/');
                if (device_id) {
                    device_id++; // Skip the '/'
                    if (connection_callback) {
                        connection_callback(device_id, connected ? 1 : 0);
                    }
                    
                    // Log the connection state change
                    log_info("[%s] Device %s %s", LOG_TAG, device_id, 
                            connected ? "connected" : "disconnected");
                }
            }
            g_variant_unref(value);
        }
    }
    
    g_variant_unref(changed_properties);
    g_variant_unref(invalidated_properties);
}

// Check BlueZ version and configuration
static void check_bluez_configuration() {
    FILE *fp;
    char buffer[1024];
    
    log_info("[%s] Checking BlueZ configuration...", LOG_TAG);
    
    // Check BlueZ version
    fp = popen("bluetoothd --version", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp) != NULL) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s] BlueZ version: %s", LOG_TAG, buffer);
        }
        pclose(fp);
    } else {
        log_warning("[%s] Failed to get BlueZ version", LOG_TAG);
    }
    
    // Check BlueZ daemon status
    fp = popen("systemctl status bluetooth", "r");
    if (fp) {
        log_info("[%s] BlueZ service status:", LOG_TAG);
        int line_count = 0;
        while (fgets(buffer, sizeof(buffer), fp) != NULL && line_count < 10) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s]   %s", LOG_TAG, buffer);
            line_count++;
        }
        pclose(fp);
    }
    
    // Check if notifications are enabled globally in BlueZ
    fp = popen("grep -i notification /etc/bluetooth/main.conf 2>/dev/null || echo 'No notification settings found in main.conf'", "r");
    if (fp) {
        log_info("[%s] BlueZ notification settings:", LOG_TAG);
        while (fgets(buffer, sizeof(buffer), fp) != NULL) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s]   %s", LOG_TAG, buffer);
        }
        pclose(fp);
    }
    
    // Check loaded BlueZ plugins
    fp = popen("grep -i BLUEZ_PLUGINS /etc/init.d/bluetooth 2>/dev/null || echo 'No plugin settings found'", "r");
    if (fp) {
        log_info("[%s] BlueZ plugins:", LOG_TAG);
        while (fgets(buffer, sizeof(buffer), fp) != NULL) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s]   %s", LOG_TAG, buffer);
        }
        pclose(fp);
    }
    
    // Check if D-Bus is working properly
    fp = popen("dbus-send --system --print-reply --dest=org.bluez / org.freedesktop.DBus.Introspectable.Introspect 2>&1 | head -n 10", "r");
    if (fp) {
        log_info("[%s] D-Bus introspection test:", LOG_TAG);
        int line_count = 0;
        while (fgets(buffer, sizeof(buffer), fp) != NULL && line_count < 5) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s]   %s", LOG_TAG, buffer);
            line_count++;
        }
        pclose(fp);
    }
    
    // Check system architecture
    fp = popen("uname -a", "r");
    if (fp) {
        if (fgets(buffer, sizeof(buffer), fp) != NULL) {
            buffer[strcspn(buffer, "\n")] = 0;  // Remove newline
            log_info("[%s] System: %s", LOG_TAG, buffer);
        }
        pclose(fp);
    }
    
    log_info("[%s] BlueZ configuration check completed", LOG_TAG);
}

// Then bluetooth_thread_func follows
static void* bluetooth_thread_func(void* arg) {
    GError *error = NULL;
    int retry_count = 0;

    while (retry_count < MAX_RETRY_ATTEMPTS) {
        // Check if bluetooth service is active before proceeding
        if (!is_bluetooth_service_active()) {
            log_warning("[%s] Bluetooth service not active, waiting...", LOG_TAG);
            if (!wait_for_bluetooth_service()) {
                log_error("[%s] Failed to wait for Bluetooth service", LOG_TAG);
                pthread_exit(NULL);
            }
            // Reset error state
            error = NULL;
        }

        main_loop = g_main_loop_new(NULL, FALSE);

        // Step 1: Connect to the system bus
        connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
        if (!connection) {
            log_error("[%s] Failed to connect to D-Bus: %s", LOG_TAG, error->message);
            g_error_free(error);
            error = NULL;
            
            retry_count++;
            if (retry_count < MAX_RETRY_ATTEMPTS) {
                log_info("[%s] Retrying connection (attempt %d/%d)...", 
                        LOG_TAG, retry_count + 1, MAX_RETRY_ATTEMPTS);
                sleep(RETRY_DELAY_SECONDS);
                continue;
            }
            pthread_exit(NULL);
        } else {
            setup_dbus_signal_handlers(connection);
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

        // Try to explicitly set the Notify property for the cmd_char
        log_info("[%s] Explicitly setting Notify capability for cmd_char...", LOG_TAG);
        GDBusProxy *cmd_proxy = g_dbus_proxy_new_sync(
            connection,
            G_DBUS_PROXY_FLAGS_NONE,
            NULL,
            "org.bluez",
            "/org/bluez",
            "org.freedesktop.DBus.Properties",
            NULL,
            &error
        );

        if (error || !cmd_proxy) {
            log_warning("[%s] Failed to create proxy for setting Notify capability: %s", 
                       LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
        } else {
            // Try to explicitly set Notify property
            const gchar* flags[] = {"write", "write-without-response", "notify", NULL};
            GVariant *flags_variant = g_variant_new_strv(flags, -1);
            
            g_dbus_proxy_call_sync(
                cmd_proxy,
                "Set",
                g_variant_new("(ssv)", 
                            "org.bluez.GattCharacteristic1", 
                            "Flags", 
                            flags_variant),
                G_DBUS_CALL_FLAGS_NONE,
                -1,
                NULL,
                &error
            );
            
            if (error) {
                log_warning("[%s] Failed to explicitly set Notify capability: %s", 
                           LOG_TAG, error->message);
                g_error_free(error);
            } else {
                log_info("[%s] Successfully set Notify capability", LOG_TAG);
            }
            
            g_object_unref(cmd_proxy);
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

        // If we get here, initialization was successful
        retry_count = 0;  // Reset retry count
        log_info("[%s] Bluetooth initialized successfully", LOG_TAG);

        // Check adapter and registration status
        check_bluetooth_adapter();

        // Run the main loop
        g_main_loop_run(main_loop);

        // If main loop exits, check if we should retry
        log_warning("[%s] Main loop exited, checking service status", LOG_TAG);
        
        // Cleanup before potential retry
        if (main_loop) {
            g_main_loop_unref(main_loop);
            main_loop = NULL;
        }
        if (connection) {
            g_object_unref(connection);
            connection = NULL;
        }
        
        // If service is still active, don't retry
        if (is_bluetooth_service_active()) {
            break;
        }
        
        retry_count++;
        if (retry_count < MAX_RETRY_ATTEMPTS) {
            log_info("[%s] Attempting to reinitialize (attempt %d/%d)...", 
                    LOG_TAG, retry_count + 1, MAX_RETRY_ATTEMPTS);
            sleep(RETRY_DELAY_SECONDS);
        }
    }

    pthread_exit(NULL);
    return NULL;
}

int bluetooth_init(const char* custom_device_name) {
    // Initialize log buffer
    init_log_buffer();
    
    // Start the logging thread if we have a log file
    if (log_file != NULL) {
        start_log_thread();
    }
    
    log_info("[%s] Initializing Bluetooth in background thread", LOG_TAG);
    
    // Check BlueZ configuration
    check_bluez_configuration();
    
    // First check if bluetooth service is active
    if (!is_bluetooth_service_active()) {
        log_warning("[%s] Bluetooth service not active, waiting...", LOG_TAG);
        if (!wait_for_bluetooth_service()) {
            log_error("[%s] Failed to wait for Bluetooth service", LOG_TAG);
            return -1;
        }
    }
    
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
    return 0;
}

int bluetooth_start(connection_result_callback scb, command_callback ccb, device_connection_callback dcb) {
    result_callback = scb;
    cmd_callback = ccb;
    connection_callback = dcb;
    log_info("[%s] Bluetooth service started", LOG_TAG);
    return 0;
}

void bluetooth_stop() {
    log_info("[%s] Stopping Bluetooth...", LOG_TAG);
    
    // Shutdown the logging thread
    shutdown_log_thread();
    
    // Free log buffer memory
    free_log_buffer();
    
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

    log_info("[%s] Bluetooth service stopped", LOG_TAG);
}

void bluetooth_notify(const unsigned char* data, int length) {
    // Log the hex string for debugging
    char hex_string[length * 3 + 1];
    for (size_t i = 0; i < length; i++) {
        sprintf(hex_string + (i * 3), "%02x ", data[i]);
    }
    hex_string[length * 3 - 1] = '\0';
    log_info("[%s] Notifying data: %s", LOG_TAG, hex_string);

    if (!connection) {
        log_error("[%s] Cannot send notification: no D-Bus connection", LOG_TAG);
        return;
    }
    
    GError *error = NULL;

    // Check if notifications are enabled
    if (!cmd_char_notify_enabled) {
        log_warning("[%s] Cannot send notification: notifications not enabled for cmd_char", LOG_TAG);
        
        // Try to check if characteristic is registered properly with bluez
        GDBusProxy *proxy = g_dbus_proxy_new_sync(
            connection,
            G_DBUS_PROXY_FLAGS_NONE,
            NULL,
            "org.bluez",
            "/com/feralfile/display/service0/cmd_char",
            "org.bluez.GattCharacteristic1",
            NULL,
            &error
        );
        
        if (error || !proxy) {
            log_error("[%s] Failed to get cmd_char proxy: %s", 
                     LOG_TAG, error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            return; // Can't continue if we can't verify characteristic
        } else {
            log_info("[%s] cmd_char characteristic is registered with BlueZ", LOG_TAG);
            // Force setting the cmd_char_notify_enabled to true and try notification anyway
            log_info("[%s] Forcing notification attempt even though notifications not enabled", LOG_TAG);
            cmd_char_notify_enabled = TRUE;
            g_object_unref(proxy);
        }
    }

    // Create GVariant for the notification value
    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                              data, length, sizeof(guchar));
    if (!value) {
        log_error("[%s] Failed to create notification value variant", LOG_TAG);
        return;
    }

    // Emit PropertiesChanged signal
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
    if (!builder) {
        log_error("[%s] Failed to create variant builder", LOG_TAG);
        return;
    }
    
    g_variant_builder_add(builder, "{sv}", "Value", value);

    // Log more details about the notification
    log_info("[%s] Sending notification on: /com/feralfile/display/service0/cmd_char", LOG_TAG);
    
    gboolean result = g_dbus_connection_emit_signal(connection,
        NULL,
        "/com/feralfile/display/service0/cmd_char",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        g_variant_new("(sa{sv}as)",
                     "org.bluez.GattCharacteristic1",
                     builder,
                     NULL),
        &error);

    if (!result || error) {
        log_error("[%s] Failed to emit notification signal: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) {
            g_error_free(error);
        }
    } else {
        log_info("[%s] Notification signal emitted successfully", LOG_TAG);
    }

    g_variant_builder_unref(builder);
    
    // Flush the connection to ensure signal is sent immediately
    g_dbus_connection_flush_sync(connection, NULL, &error);
    if (error) {
        log_error("[%s] Failed to flush D-Bus connection: %s", LOG_TAG, error->message);
        g_error_free(error);
    }

    // After the normal notification mechanism, try the direct method
    try_direct_notification(data, length);
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

    GError *error = NULL;
    
    // Check if notifications are enabled
    if (!eng_char_notify_enabled) {
        log_warning("[%s] Cannot send notification: notifications not enabled for eng_char", LOG_TAG);
        return;
    }

    // Create GVariant for the notification value
    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                              data, length, sizeof(guchar));
    if (!value) {
        log_error("[%s] Failed to create engineering data variant", LOG_TAG);
        return;
    }

    // Emit PropertiesChanged signal
    GVariantBuilder *builder = g_variant_builder_new(G_VARIANT_TYPE_ARRAY);
    if (!builder) {
        log_error("[%s] Failed to create variant builder for engineering data", LOG_TAG);
        return;
    }
    
    g_variant_builder_add(builder, "{sv}", "Value", value);

    // Log more details about the notification
    log_info("[%s] Sending notification on: /com/feralfile/display/service0/eng_char", LOG_TAG);
    
    gboolean result = g_dbus_connection_emit_signal(connection,
        NULL,
        "/com/feralfile/display/service0/eng_char",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged",
        g_variant_new("(sa{sv}as)",
                     "org.bluez.GattCharacteristic1",
                     builder,
                     NULL),
        &error);

    if (!result || error) {
        log_error("[%s] Failed to emit engineering notification signal: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) {
            g_error_free(error);
        }
    } else {
        log_info("[%s] Engineering notification signal emitted successfully", LOG_TAG);
    }

    g_variant_builder_unref(builder);
    
    // Flush the connection to ensure signal is sent immediately
    g_dbus_connection_flush_sync(connection, NULL, &error);
    if (error) {
        log_error("[%s] Failed to flush D-Bus connection: %s", LOG_TAG, error->message);
        g_error_free(error);
    }
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

// Check Bluetooth adapter status
static void check_bluetooth_adapter() {
    GError *error = NULL;
    
    log_info("[%s] Checking Bluetooth adapter status...", LOG_TAG);
    
    if (!connection) {
        log_error("[%s] Cannot check adapter: no D-Bus connection", LOG_TAG);
        return;
    }
    
    // Try to get adapter properties
    GDBusProxy *adapter_proxy = g_dbus_proxy_new_sync(
        connection,
        G_DBUS_PROXY_FLAGS_NONE,
        NULL,
        "org.bluez",
        "/org/bluez/hci0",
        "org.freedesktop.DBus.Properties",
        NULL,
        &error
    );
    
    if (error || !adapter_proxy) {
        log_error("[%s] Failed to create adapter proxy: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return;
    }
    
    // Get adapter powered status
    GVariant *result = g_dbus_proxy_call_sync(
        adapter_proxy,
        "Get",
        g_variant_new("(ss)", "org.bluez.Adapter1", "Powered"),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    
    if (error || !result) {
        log_error("[%s] Failed to get adapter powered state: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
    } else {
        GVariant *variant = NULL;
        g_variant_get(result, "(v)", &variant);
        gboolean powered = g_variant_get_boolean(variant);
        log_info("[%s] Adapter powered: %s", LOG_TAG, powered ? "true" : "false");
        g_variant_unref(variant);
        g_variant_unref(result);
    }
    
    // Get adapter name
    result = g_dbus_proxy_call_sync(
        adapter_proxy,
        "Get",
        g_variant_new("(ss)", "org.bluez.Adapter1", "Name"),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    
    if (error || !result) {
        log_warning("[%s] Failed to get adapter name: %s", 
                   LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
    } else {
        GVariant *variant = NULL;
        g_variant_get(result, "(v)", &variant);
        const gchar *name = g_variant_get_string(variant, NULL);
        log_info("[%s] Adapter name: %s", LOG_TAG, name);
        g_variant_unref(variant);
        g_variant_unref(result);
    }
    
    // Test if GATT service and characteristics registration was successful
    log_info("[%s] Testing characteristics registration...", LOG_TAG);
    
    // Try to get registered objects
    result = g_dbus_connection_call_sync(
        connection,
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
        NULL,
        G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    
    if (error || !result) {
        log_error("[%s] Failed to get BlueZ managed objects: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
    } else {
        GVariant *objects_dict;
        g_variant_get(result, "(@a{oa{sa{sv}}})", &objects_dict);
        
        log_info("[%s] Checking for our service and characteristics in BlueZ...", LOG_TAG);
        
        // Extract all paths
        GVariantIter iter;
        gchar *object_path;
        GVariant *interfaces_dict;
        
        g_variant_iter_init(&iter, objects_dict);
        gboolean found_service = FALSE;
        gboolean found_cmd_char = FALSE;
        gboolean found_eng_char = FALSE;
        
        while (g_variant_iter_loop(&iter, "{&o@a{sa{sv}}}", &object_path, &interfaces_dict)) {
            if (strstr(object_path, "feralfile") != NULL) {
                log_info("[%s]   Found our object: %s", LOG_TAG, object_path);
                
                if (strstr(object_path, "service0") != NULL && strstr(object_path, "char") == NULL) {
                    found_service = TRUE;
                } else if (strstr(object_path, "cmd_char") != NULL) {
                    found_cmd_char = TRUE;
                    
                    // Dump the interfaces and properties for cmd_char
                    GVariantIter iface_iter;
                    gchar *interface_name;
                    GVariant *properties;
                    
                    g_variant_iter_init(&iface_iter, interfaces_dict);
                    while (g_variant_iter_loop(&iface_iter, "{&s@a{sv}}", &interface_name, &properties)) {
                        log_info("[%s]     Interface: %s", LOG_TAG, interface_name);
                        
                        if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
                            GVariantIter prop_iter;
                            gchar *prop_name;
                            GVariant *prop_value;
                            
                            g_variant_iter_init(&prop_iter, properties);
                            while (g_variant_iter_loop(&prop_iter, "{&sv}", &prop_name, &prop_value)) {
                                if (g_strcmp0(prop_name, "Flags") == 0) {
                                    GVariantIter flag_iter;
                                    gchar *flag;
                                    gboolean has_notify = FALSE;
                                    
                                    g_variant_iter_init(&flag_iter, prop_value);
                                    log_info("[%s]       Flags:", LOG_TAG);
                                    while (g_variant_iter_loop(&flag_iter, "s", &flag)) {
                                        log_info("[%s]         %s", LOG_TAG, flag);
                                        if (g_strcmp0(flag, "notify") == 0) {
                                            has_notify = TRUE;
                                        }
                                    }
                                    
                                    if (!has_notify) {
                                        log_error("[%s] cmd_char does NOT have notify flag!", LOG_TAG);
                                    }
                                } else {
                                    gchar *value_str = g_variant_print(prop_value, TRUE);
                                    log_info("[%s]       %s: %s", LOG_TAG, prop_name, value_str);
                                    g_free(value_str);
                                }
                            }
                        }
                    }
                } else if (strstr(object_path, "eng_char") != NULL) {
                    found_eng_char = TRUE;
                }
            }
        }
        
        if (!found_service) {
            log_error("[%s] Our service was NOT found in BlueZ!", LOG_TAG);
        }
        if (!found_cmd_char) {
            log_error("[%s] cmd_char was NOT found in BlueZ!", LOG_TAG);
        }
        if (!found_eng_char) {
            log_error("[%s] eng_char was NOT found in BlueZ!", LOG_TAG);
        }
        
        g_variant_unref(objects_dict);
        g_variant_unref(result);
    }
    
    g_object_unref(adapter_proxy);
    log_info("[%s] Bluetooth adapter check completed", LOG_TAG);
}

// Try direct notification through BlueZ
static void try_direct_notification(const unsigned char* data, int length) {
    GError *error = NULL;
    
    log_info("[%s] Attempting direct notification through BlueZ...", LOG_TAG);
    
    if (!connection) {
        log_error("[%s] Cannot send direct notification: no D-Bus connection", LOG_TAG);
        return;
    }
    
    // Create value
    GVariant *value = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                            data, length, sizeof(guchar));
    if (!value) {
        log_error("[%s] Failed to create direct notification value variant", LOG_TAG);
        return;
    }
    
    // Try to get all connected devices
    GVariant *result = g_dbus_connection_call_sync(
        connection,
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
        NULL,
        G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
        G_DBUS_CALL_FLAGS_NONE,
        -1,
        NULL,
        &error
    );
    
    if (error || !result) {
        log_error("[%s] Failed to get BlueZ objects for notification: %s", 
                 LOG_TAG, error ? error->message : "Unknown error");
        if (error) g_error_free(error);
        return;
    }
    
    GVariant *objects_dict;
    g_variant_get(result, "(@a{oa{sa{sv}}})", &objects_dict);
    
    // Find connected devices
    GVariantIter iter;
    gchar *object_path;
    GVariant *interfaces_dict;
    GArray *connected_devices = g_array_new(FALSE, FALSE, sizeof(gchar*));
    
    g_variant_iter_init(&iter, objects_dict);
    while (g_variant_iter_loop(&iter, "{&o@a{sa{sv}}}", &object_path, &interfaces_dict)) {
        if (strstr(object_path, "dev_") != NULL) {
            // This is a device, check if connected
            GVariantIter iface_iter;
            gchar *interface_name;
            GVariant *properties;
            
            g_variant_iter_init(&iface_iter, interfaces_dict);
            while (g_variant_iter_loop(&iface_iter, "{&s@a{sv}}", &interface_name, &properties)) {
                if (g_strcmp0(interface_name, "org.bluez.Device1") == 0) {
                    // Check Connected property
                    GVariantIter prop_iter;
                    gchar *prop_name;
                    GVariant *prop_value;
                    
                    g_variant_iter_init(&prop_iter, properties);
                    while (g_variant_iter_loop(&prop_iter, "{&sv}", &prop_name, &prop_value)) {
                        if (g_strcmp0(prop_name, "Connected") == 0) {
                            gboolean connected = g_variant_get_boolean(prop_value);
                            if (connected) {
                                // Store the connected device path
                                gchar *device_path = g_strdup(object_path);
                                g_array_append_val(connected_devices, device_path);
                                log_info("[%s] Found connected device: %s", LOG_TAG, device_path);
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Clean up objects dict
    g_variant_unref(objects_dict);
    g_variant_unref(result);
    
    if (connected_devices->len == 0) {
        log_warning("[%s] No connected devices found for direct notification", LOG_TAG);
        g_array_free(connected_devices, TRUE);
        return;
    }
    
    // For each connected device, try to send notification directly
    for (guint i = 0; i < connected_devices->len; i++) {
        gchar *device_path = g_array_index(connected_devices, gchar*, i);
        
        // Try to get BlueZ's version of our characteristic
        gchar char_path[256];
        snprintf(char_path, sizeof(char_path), "%s/service0/char0004", device_path); // BlueZ might use a different path format
        
        log_info("[%s] Attempting direct notification to device: %s", LOG_TAG, device_path);
        log_info("[%s] Trying characteristic path: %s", LOG_TAG, char_path);
        
        // Try to get the CMD characteristic from BlueZ
        GDBusProxy *char_proxy = g_dbus_proxy_new_sync(
            connection,
            G_DBUS_PROXY_FLAGS_NONE,
            NULL,
            "org.bluez",
            char_path,
            "org.bluez.GattCharacteristic1",
            NULL,
            &error
        );
        
        if (error || !char_proxy) {
            log_warning("[%s] Failed to get direct characteristic proxy, trying to discover: %s", 
                       LOG_TAG, error ? error->message : "Unknown error");
            if (error) {
                g_error_free(error);
                error = NULL;
            }
            
            // Try to discover the actual path
            GVariant *char_result = g_dbus_connection_call_sync(
                connection,
                "org.bluez",
                "/",
                "org.freedesktop.DBus.ObjectManager",
                "GetManagedObjects",
                NULL,
                G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
                G_DBUS_CALL_FLAGS_NONE,
                -1,
                NULL,
                &error
            );
            
            if (error || !char_result) {
                log_error("[%s] Failed to get objects for characteristic discovery: %s", 
                         LOG_TAG, error ? error->message : "Unknown error");
                if (error) g_error_free(error);
            } else {
                GVariant *char_objects_dict;
                g_variant_get(char_result, "(@a{oa{sa{sv}}})", &char_objects_dict);
                
                // Find characteristic by UUID
                g_variant_iter_init(&iter, char_objects_dict);
                while (g_variant_iter_loop(&iter, "{&o@a{sa{sv}}}", &object_path, &interfaces_dict)) {
                    // Look for a path that contains the device path and might be a characteristic
                    if (strstr(object_path, device_path) != NULL && 
                        strstr(object_path, "char") != NULL) {
                        
                        log_info("[%s] Found potential characteristic: %s", LOG_TAG, object_path);
                        
                        // Check if it has the right UUID
                        GVariantIter iface_iter;
                        gchar *interface_name;
                        GVariant *properties;
                        
                        g_variant_iter_init(&iface_iter, interfaces_dict);
                        while (g_variant_iter_loop(&iface_iter, "{&s@a{sv}}", &interface_name, &properties)) {
                            if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
                                GVariantIter prop_iter;
                                gchar *prop_name;
                                GVariant *prop_value;
                                
                                g_variant_iter_init(&prop_iter, properties);
                                while (g_variant_iter_loop(&prop_iter, "{&sv}", &prop_name, &prop_value)) {
                                    if (g_strcmp0(prop_name, "UUID") == 0) {
                                        const gchar *uuid = g_variant_get_string(prop_value, NULL);
                                        if (g_ascii_strcasecmp(uuid, FERALFILE_CMD_CHAR_UUID) == 0) {
                                            // This is our characteristic!
                                            log_info("[%s] Found our CMD characteristic: %s", LOG_TAG, object_path);
                                            
                                            // Create proxy for this characteristic
                                            char_proxy = g_dbus_proxy_new_sync(
                                                connection,
                                                G_DBUS_PROXY_FLAGS_NONE,
                                                NULL,
                                                "org.bluez",
                                                object_path,
                                                "org.bluez.GattCharacteristic1",
                                                NULL,
                                                &error
                                            );
                                            
                                            if (error || !char_proxy) {
                                                log_error("[%s] Failed to get discovered characteristic proxy: %s", 
                                                         LOG_TAG, error ? error->message : "Unknown error");
                                                if (error) g_error_free(error);
                                            }
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        if (char_proxy) break; // Found and created the proxy
                    }
                }
                
                g_variant_unref(char_objects_dict);
                g_variant_unref(char_result);
            }
        }
        
        if (char_proxy) {
            // Try to send notification
            log_info("[%s] Attempting direct WriteValue call for cmd_char", LOG_TAG);
            
            // First ensure notifications are enabled
            g_dbus_proxy_call_sync(
                char_proxy,
                "StartNotify",
                NULL,
                G_DBUS_CALL_FLAGS_NONE,
                -1,
                NULL,
                &error
            );
            
            if (error) {
                log_warning("[%s] Failed to start notifications: %s", 
                           LOG_TAG, error->message);
                g_error_free(error);
                error = NULL;
            }
            
            // Try to write the value
            GVariant *notify_result = g_dbus_proxy_call_sync(
                char_proxy,
                "WriteValue",
                g_variant_new("(aya{sv})", value, NULL),
                G_DBUS_CALL_FLAGS_NONE,
                -1,
                NULL,
                &error
            );
            
            if (error) {
                log_error("[%s] Direct write failed: %s", 
                         LOG_TAG, error->message);
                g_error_free(error);
            } else {
                log_info("[%s] Direct write sent successfully", LOG_TAG);
                if (notify_result) {
                    g_variant_unref(notify_result);
                }
            }
            
            g_object_unref(char_proxy);
        } else {
            log_error("[%s] Failed to find cmd_char for direct notification", LOG_TAG);
        }
        
        g_free(device_path);
    }
    
    g_array_free(connected_devices, TRUE);
}