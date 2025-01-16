CC = gcc
CFLAGS = -Wall -fPIC -O2 `pkg-config --cflags x11 cairo xfixes`
LDFLAGS = `pkg-config --libs x11 cairo xfixes` -lm -pthread
TARGET = liboverlay_service.so

all: $(TARGET)

$(TARGET): overlay_service.o
	$(CC) -shared -o $(TARGET) overlay_service.o $(LDFLAGS)

overlay_service.o: overlay_service.c overlay_service.h
	$(CC) $(CFLAGS) -c overlay_service.c

clean:
	rm -f *.o $(TARGET) 