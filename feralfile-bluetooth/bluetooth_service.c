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

#define FERALFILE_SERVICE_NAME   "FeralFile Connection"
#define FERALFILE_SERVICE_UUID   "f7826da6-4fa2-4e98-8024-bc5b71e0893e"
#define FERALFILE_WIFI_CHAR_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  // WiFi Configuration Characteristic

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

static GVariant* handle_get_property(GDBusConnection *connection,
                                   const gchar *sender,
                                   const gchar *object_path,
                                   const gchar *interface_name,
                                   const gchar *property_name,
                                   GError **error,
                                   gpointer user_data) {
    if (g_strcmp0(interface_name, "org.bluez.GattService1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) {
            return g_variant_new_string(FERALFILE_SERVICE_UUID);
        }
        if (g_strcmp0(property_name, "Primary") == 0) {
            return g_variant_new_boolean(TRUE);
        }
    } else if (g_strcmp0(interface_name, "org.bluez.GattCharacteristic1") == 0) {
        if (g_strcmp0(property_name, "UUID") == 0) {
            return g_variant_new_string(FERALFILE_WIFI_CHAR_UUID);
        }
    }
    return NULL;
}

// Add this interface vtable structure after the handler
static const GDBusInterfaceVTable interface_vtable = {
    .method_call = handle_method_call,
    .get_property = handle_get_property,
    .set_property = NULL,
};

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
    
    // Register the D-Bus interface
    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
    if (error) {
        log_debug("[%s] Failed to connect to D-Bus: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Register both GattService1 and GattCharacteristic1 interfaces
    registration_id = g_dbus_connection_register_object(connection,
                                                      "/org/bluez/example/service0",
                                                      introspection_data->interfaces[0],
                                                      &interface_vtable,
                                                      NULL,
                                                      NULL,
                                                      &error);
    if (error) {
        log_debug("[%s] Failed to register GattService1 interface: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Register the characteristic interface
    guint char_registration_id = g_dbus_connection_register_object(connection,
                                                                 "/org/bluez/example/service0/char0",
                                                                 introspection_data->interfaces[1],
                                                                 &interface_vtable,
                                                                 NULL,
                                                                 NULL,
                                                                 &error);
    if (error) {
        log_debug("[%s] Failed to register GattCharacteristic1 interface: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    log_debug("[%s] Setting up Bluetooth device properties\n", LOG_TAG);
    system("bluetoothctl discoverable on");
    system("bluetoothctl pairable on");
    system("bluetoothctl set-alias '" FERALFILE_SERVICE_NAME "'");
    
    // Add advertisement setup
    GDBusProxy *adapter_proxy = g_dbus_proxy_new_sync(connection,
                                                     G_DBUS_PROXY_FLAGS_NONE,
                                                     NULL,
                                                     "org.bluez",
                                                     "/org/bluez/hci0",
                                                     "org.bluez.LEAdvertisingManager1",
                                                     NULL,
                                                     &error);
    if (error) {
        log_debug("[%s] Failed to create advertising manager proxy: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    // Create advertisement data
    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
    
    // Add service UUID to advertisement
    GVariantBuilder uuid_builder;
    g_variant_builder_init(&uuid_builder, G_VARIANT_TYPE("as"));
    g_variant_builder_add(&uuid_builder, "s", FERALFILE_SERVICE_UUID);
    g_variant_builder_add(&builder, "{sv}", "ServiceUUIDs",
                         g_variant_new("as", &uuid_builder));

    // Set local name
    g_variant_builder_add(&builder, "{sv}", "LocalName",
                         g_variant_new_string(FERALFILE_SERVICE_NAME));

    // Register advertisement
    GVariant *advertisement = g_variant_new("(oa{sv})", "/org/bluez/example/advertisement0", &builder);
    GVariant *result = g_dbus_proxy_call_sync(adapter_proxy,
                                             "RegisterAdvertisement",
                                             advertisement,
                                             G_DBUS_CALL_FLAGS_NONE,
                                             -1,
                                             NULL,
                                             &error);
    if (error) {
        log_debug("[%s] Failed to register advertisement: %s\n", LOG_TAG, error->message);
        g_error_free(error);
        return -1;
    }

    g_variant_unref(result);
    g_object_unref(adapter_proxy);

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