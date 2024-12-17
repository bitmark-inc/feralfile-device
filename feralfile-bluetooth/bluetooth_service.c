// bluetooth_service.c
#include "bluetooth_service.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <glib.h>
#include <gio/gio.h>
#include <pthread.h>
#include <syslog.h>

// Global variables
static GMainLoop *main_loop = NULL;
static GDBusNodeInfo *introspection_data = NULL;
static guint owner_id;
static guint registration_id;
static connection_result_callback result_callback = NULL;
static pthread_t bluetooth_thread;
static int client_sock = -1;
static int server_sock = -1;

// Add after global variables
#define LOG_TAG "BluetoothService"
static void log_debug(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vsyslog(LOG_DEBUG, format, args);
    vprintf(format, args);
    va_end(args);
}

// D-Bus interface definition for BLE GATT service
static const gchar introspection_xml[] =
    "<node>"
    "  <interface name='org.bluez.GattService1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Primary' type='b' access='read'/>"
    "  </interface>"
    "  <interface name='org.bluez.GattCharacteristic1'>"
    "    <property name='UUID' type='s' access='read'/>"
    "    <property name='Service' type='o' access='read'/>"
    "    <property name='Value' type='ay' access='read'/>"
    "    <property name='Notifying' type='b' access='read'/>"
    "    <method name='ReadValue'>"
    "      <arg name='options' type='a{sv}' direction='in'/>"
    "      <arg name='value' type='ay' direction='out'/>"
    "    </method>"
    "    <method name='WriteValue'>"
    "      <arg name='value' type='ay' direction='in'/>"
    "      <arg name='options' type='a{sv}' direction='in'/>"
    "    </method>"
    "  </interface>"
    "</node>";

// Function to handle BLE data reception
static void handle_write_value(const guchar *value, gsize value_len) {
    log_debug("[%s] Received write value request, length: %zu\n", LOG_TAG, value_len);
    
    char buffer[1024] = {0};
    memcpy(buffer, value, value_len < sizeof(buffer) ? value_len : sizeof(buffer) - 1);
    log_debug("[%s] Received data: %s\n", LOG_TAG, buffer);
    
    char ssid[256] = {0};
    char password[256] = {0};
    
    int parsed = sscanf(buffer, "{\"ssid\":\"%255[^\"]\",\"password\":\"%255[^\"]\"}", ssid, password);
    log_debug("[%s] Parsed %d fields. SSID: %s\n", LOG_TAG, parsed, ssid);
    
    char command[512];
    snprintf(command, sizeof(command), "nmcli dev wifi connect \"%s\" password \"%s\"", ssid, password);
    log_debug("[%s] Executing command: nmcli dev wifi connect \"%s\" [password hidden]\n", LOG_TAG, ssid);
    
    int ret = system(command);
    log_debug("[%s] nmcli command returned: %d\n", LOG_TAG, ret);
    
    if (ret == 0) {
        log_debug("[%s] Successfully connected to WiFi\n", LOG_TAG);
        if (result_callback) {
            result_callback(1, "Wi-Fi connected successfully.");
        }
    } else {
        log_debug("[%s] Failed to connect to WiFi\n", LOG_TAG);
        if (result_callback) {
            result_callback(0, "Failed to connect to Wi-Fi.");
        }
    }
}

// D-Bus method handlers
static void handle_method_call(GDBusConnection *connection,
                             const gchar *sender,
                             const gchar *object_path,
                             const gchar *interface_name,
                             const gchar *method_name,
                             GVariant *parameters,
                             GDBusMethodInvocation *invocation,
                             gpointer user_data) {
    if (g_strcmp0(method_name, "WriteValue") == 0) {
        GVariant *value_variant;
        g_variant_get(parameters, "(@ay@a{sv})", &value_variant, NULL);
        
        gsize value_len;
        const guchar *value = g_variant_get_fixed_array(value_variant, &value_len, 1);
        
        handle_write_value(value, value_len);
        
        g_dbus_method_invocation_return_value(invocation, NULL);
        g_variant_unref(value_variant);
    }
}

// BLE service main loop
void* bluetooth_handler(void* arg) {
    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);
    pthread_exit(NULL);
}

int bluetooth_init() {
    log_debug("[%s] Initializing Bluetooth service\n", LOG_TAG);
    
    GError *error = NULL;
    introspection_data = g_dbus_node_info_new_for_xml(introspection_xml, &error);
    if (error) {
        log_debug("[%s] Failed to parse D-Bus interface: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }
    
    log_debug("[%s] Setting up Bluetooth device properties\n", LOG_TAG);
    system("bluetoothctl discoverable on");
    system("bluetoothctl pairable on");
    system("bluetoothctl set-alias 'FeralFile-WiFi'");
    
    log_debug("[%s] Bluetooth service initialized successfully\n", LOG_TAG);
    return 0;
}

int bluetooth_start(connection_result_callback callback) {
    log_debug("[%s] Starting Bluetooth service\n", LOG_TAG);
    result_callback = callback;

    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        log_debug("[%s] Failed to create Bluetooth handler thread: %s\n", LOG_TAG, strerror(errno));
        return -1;
    }

    log_debug("[%s] Bluetooth service started successfully\n", LOG_TAG);
    return 0;
}

void bluetooth_stop() {
    log_debug("[%s] Stopping Bluetooth service\n", LOG_TAG);
    
    if (client_sock > 0) {
        log_debug("[%s] Closing client socket\n", LOG_TAG);
        close(client_sock);
    }
    if (server_sock > 0) {
        log_debug("[%s] Closing server socket\n", LOG_TAG);
        close(server_sock);
    }

    log_debug("[%s] Cancelling Bluetooth handler thread\n", LOG_TAG);
    pthread_cancel(bluetooth_thread);
    pthread_join(bluetooth_thread, NULL);

    log_debug("[%s] Bluetooth service stopped successfully\n", LOG_TAG);
}