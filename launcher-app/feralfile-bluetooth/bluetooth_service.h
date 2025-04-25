// bluetooth_service.h
#ifndef BLUETOOTH_SERVICE_H
#define BLUETOOTH_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
typedef void (*command_callback)(int success, const unsigned char* data, int length);
typedef void (*device_connection_callback)(const char* device_id, int connected);

int bluetooth_init(const char* custom_device_name);
int bluetooth_start(connection_result_callback setup_callback, command_callback cmd_callback, device_connection_callback dcb);
void bluetooth_stop();
void bluetooth_set_logfile(const char* path);
void bluetooth_notify(const unsigned char* data, int length);
const char* bluetooth_get_mac_address();
void bluetooth_free_data(unsigned char* data);
void bluetooth_send_engineering_data(const unsigned char* data, int length);

#ifdef __cplusplus
}
#endif

#endif // BLUETOOTH_SERVICE_H