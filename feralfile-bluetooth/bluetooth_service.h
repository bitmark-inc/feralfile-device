// bluetooth_service.h
#ifndef BLUETOOTH_SERVICE_H
#define BLUETOOTH_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*connection_result_callback)(int success, const char* message);

int bluetooth_init();
int bluetooth_start(connection_result_callback callback);
void bluetooth_stop();
void bluetooth_set_logfile(const char* path);

#ifdef __cplusplus
}
#endif

#endif // BLUETOOTH_SERVICE_H