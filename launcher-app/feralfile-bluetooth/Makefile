# Makefile

CC = gcc
CFLAGS = -Wall -fPIC -O2 `pkg-config --cflags glib-2.0 gio-2.0 dbus-1` -DSENTRY_BUILD_STATIC
LDFLAGS = -lbluetooth -pthread `pkg-config --libs glib-2.0 gio-2.0 dbus-1` -lsentry -lm -ldl -lrt -lresolv -lz -lcurl
TARGET = libbluetooth_service.so

# Allow passing SENTRY_DSN from command line
ifdef SENTRY_DSN
CFLAGS += -DSENTRY_DSN=\"$(SENTRY_DSN)\"
endif

# Allow passing APP_VERSION from command line
ifdef APP_VERSION
CFLAGS += -DAPP_VERSION=\"$(APP_VERSION)\"
endif

all: $(TARGET)

$(TARGET): bluetooth_service.o
	$(CC) -shared -o $(TARGET) bluetooth_service.o $(LDFLAGS)

bluetooth_service.o: bluetooth_service.c bluetooth_service.h
	$(CC) $(CFLAGS) -c bluetooth_service.c

clean:
	rm -f *.o $(TARGET)