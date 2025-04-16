// bluetooth_service.h
#ifndef BLUETOOTH_SERVICE_H
#define BLUETOOTH_SERVICE_H

#include <stddef.h> // Required for size_t

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Callback function type for handling data received on the setup characteristic.
 * @param success Non-zero if data was received successfully, 0 on error (e.g., memory allocation failed).
 * @param data Pointer to the received data buffer. The application MUST call bluetooth_free_data() on this pointer when done.
 * @param length Length of the received data in bytes.
 */
typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);

/**
 * @brief Callback function type for handling data received on the command characteristic.
 * @param success Non-zero if data was received successfully, 0 on error (e.g., memory allocation failed).
 * @param data Pointer to the received data buffer. The application MUST call bluetooth_free_data() on this pointer when done.
 * @param length Length of the received data in bytes.
 */
typedef void (*command_callback)(int success, const unsigned char* data, int length);

/**
 * @brief Callback function type for handling device connection status changes.
 * @param device_id String representing the device identifier (MAC address part, e.g., "XX_XX_XX_XX_XX_XX").
 * @param connected 1 if the device connected, 0 if the device disconnected.
 */
typedef void (*device_connection_callback)(const char* device_id, int connected);

/**
 * @brief Initializes the Bluetooth service in a background thread.
 * Checks if the system's Bluetooth service is active and waits if necessary.
 * Sets up Sentry logging if configured.
 *
 * @param custom_device_name Optional: A custom name for the Bluetooth peripheral advertisement.
 * If NULL or empty, a default name will be used.
 * The name will be truncated if longer than allowed.
 * @return 0 on successful initiation, -1 on failure (e.g., service not starting, thread creation failed).
 */
int bluetooth_init(const char* custom_device_name);

/**
 * @brief Registers the callback functions for various Bluetooth events.
 * This should typically be called after bluetooth_init().
 *
 * @param setup_cb Callback for data received on the setup characteristic.
 * @param cmd_cb Callback for data received on the command characteristic.
 * @param conn_cb Callback for device connection/disconnection events. // <-- NEW PARAMETER
 * @return 0 on success.
 */
int bluetooth_start(connection_result_callback setup_cb,
                    command_callback cmd_cb,
                    device_connection_callback conn_cb); // <-- UPDATED SIGNATURE

/**
 * @brief Stops the Bluetooth service, unregisters D-Bus objects and advertisements,
 * closes connections, stops the background thread, and cleans up resources.
 */
void bluetooth_stop();

/**
 * @brief Sets the path for the log file. If a file is already open, it's closed first.
 * Pass NULL to disable file logging. Logging to stdout/stderr and syslog continues regardless.
 * This function is thread-safe.
 *
 * @param path Absolute or relative path to the log file. It will be opened in append mode.
 */
void bluetooth_set_logfile(const char* path);

/**
 * @brief Sends a notification containing the given data on the command characteristic.
 * This is typically used to send responses or asynchronous events to a connected client
 * that has enabled notifications on the command characteristic.
 *
 * @param data Pointer to the data buffer to send.
 * @param length Length of the data in bytes.
 */
void bluetooth_notify(const unsigned char* data, int length);

/**
 * @brief Gets the MAC address of the primary local Bluetooth adapter.
 *
 * @param mac_address_buffer A caller-provided character buffer to store the MAC address string (XX:XX:XX:XX:XX:XX format).
 * @param buffer_size The size of the provided buffer. Must be at least 18 bytes.
 * @return 0 on success, -1 on failure (e.g., could not open adapter, read address, or buffer too small).
 */
int bluetooth_get_mac_address(char* mac_address_buffer, size_t buffer_size); // <-- UPDATED SIGNATURE

/**
 * @brief Frees the memory allocated for the data buffer passed to setup_data_callback or command_data_callback.
 * This MUST be called by the application after processing the received data to prevent memory leaks.
 *
 * @param data The pointer received in the callback function.
 */
void bluetooth_free_data(unsigned char* data);

/**
 * @brief Sends a notification containing the given data on the engineering characteristic.
 * Similar to bluetooth_notify, but uses the dedicated engineering characteristic.
 *
 * @param data Pointer to the data buffer to send.
 * @param length Length of the data in bytes.
 */
void bluetooth_send_engineering_data(const unsigned char* data, int length);


#ifdef __cplusplus
}
#endif

#endif // BLUETOOTH_SERVICE_H