# Makefile

CC = gcc
CFLAGS = -Wall -fPIC -O2
LDFLAGS = -lbluetooth -pthread
TARGET = libbluetooth_service.so

all: $(TARGET)

$(TARGET): bluetooth_service.o
	$(CC) -shared -o $(TARGET) bluetooth_service.o $(LDFLAGS)

bluetooth_service.o: bluetooth_service.c bluetooth_service.h
	$(CC) $(CFLAGS) -c bluetooth_service.c

clean:
	rm -f *.o $(TARGET)