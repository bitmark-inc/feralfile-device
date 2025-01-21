// bluetooth_service.h
#ifndef BLUETOOTH_SERVICE_H
#define BLUETOOTH_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*connection_result_callback)(int success, const unsigned char* data, int length);
typedef void (*command_callback)(int success, const unsigned char* data, int length);

int bluetooth_init(const char* device_name);
int bluetooth_start(connection_result_callback setup_callback, command_callback cmd_callback);
void bluetooth_stop();
void bluetooth_set_logfile(const char* path);
void bluetooth_notify(const unsigned char* data, int length);

#ifdef __cplusplus
}
#endif

#endif // BLUETOOTH_SERVICE_H