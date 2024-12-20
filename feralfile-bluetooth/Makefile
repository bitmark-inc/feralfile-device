# Makefile

CC = gcc
CFLAGS = -Wall -fPIC -O2 `pkg-config --cflags glib-2.0 gio-2.0 dbus-1`
LDFLAGS = -lbluetooth -pthread `pkg-config --libs glib-2.0 gio-2.0 dbus-1`
TARGET = libbluetooth_service.so

all: $(TARGET)

$(TARGET): bluetooth_service.o
	$(CC) -shared -o $(TARGET) bluetooth_service.o $(LDFLAGS)

bluetooth_service.o: bluetooth_service.c bluetooth_service.h
	$(CC) $(CFLAGS) -c bluetooth_service.c

clean:
	rm -f *.o $(TARGET)