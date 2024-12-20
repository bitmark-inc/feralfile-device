# Makefile

CC = gcc
CFLAGS = -Wall -fPIC -O2 `pkg-config --cflags glib-2.0 gio-2.0 dbus-1`
LDFLAGS = -lbluetooth -pthread `pkg-config --libs glib-2.0 gio-2.0 dbus-1`
TARGET = libbluetooth_service.so
OBJS = bluetooth_service.o gatt-interfaces.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -shared -o $(TARGET) $(OBJS) $(LDFLAGS)

bluetooth_service.o: bluetooth_service.c bluetooth_service.h gatt-interfaces.h
	$(CC) $(CFLAGS) -c bluetooth_service.c

gatt-interfaces.o: gatt-interfaces.c gatt-interfaces.h
	$(CC) $(CFLAGS) -c gatt-interfaces.c

clean:
	rm -f *.o $(TARGET)