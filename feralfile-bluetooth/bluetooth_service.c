// bluetooth_service.c
#include "bluetooth_service.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
#include <pthread.h>

// Global variables
static int server_sock = 0, client_sock = 0;
static struct sockaddr_rc loc_addr = { 0 }, rem_addr = { 0 };
static socklen_t opt = sizeof(rem_addr);
static connection_result_callback result_callback = NULL;
static pthread_t bluetooth_thread;

// Function to handle client connection
void* bluetooth_handler(void* arg) {
    char buffer[1024] = {0};
    int bytes_read;

    // Accept the client connection
    client_sock = accept(server_sock, (struct sockaddr*)&rem_addr, &opt);
    if (client_sock < 0) {
        perror("Accept failed");
        if (result_callback) {
            result_callback(0, "Failed to accept Bluetooth connection.");
        }
        pthread_exit(NULL);
    }

    char client_address[19] = { 0 };
    ba2str(&rem_addr.rc_bdaddr, client_address);
    printf("Accepted connection from %s\n", client_address);

    // Receive data (Wi-Fi credentials in JSON format)
    bytes_read = read(client_sock, buffer, sizeof(buffer));
    if (bytes_read > 0) {
        buffer[bytes_read] = '\0';
        printf("Received: %s\n", buffer);

        // Parse JSON to extract SSID and Password
        // For simplicity, assume the JSON is in the format: {"ssid":"Your_SSID","password":"Your_Password"}
        char ssid[256] = {0};
        char password[256] = {0};

        // Simple parsing without error checking
        sscanf(buffer, "{\"ssid\":\"%255[^\"]\",\"password\":\"%255[^\"]\"}", ssid, password);

        printf("Parsed SSID: %s\nPassword: %s\n", ssid, password);

        // Connect to Wi-Fi using nmcli
        // WARNING: Executing shell commands can be insecure. Ensure inputs are sanitized.
        char command[512];
        snprintf(command, sizeof(command), "nmcli dev wifi connect \"%s\" password \"%s\"", ssid, password);
        printf("Executing command: %s\n", command);

        int ret = system(command);
        if (ret == 0) {
            printf("Wi-Fi connected successfully.\n");
            if (result_callback) {
                result_callback(1, "Wi-Fi connected successfully.");
            }
        } else {
            printf("Failed to connect to Wi-Fi.\n");
            if (result_callback) {
                result_callback(0, "Failed to connect to Wi-Fi.");
            }
        }

        // Send result back to client
        char result_message[256];
        if (ret == 0) {
            snprintf(result_message, sizeof(result_message), "{\"success\":true,\"message\":\"Wi-Fi connected successfully.\"}");
        } else {
            snprintf(result_message, sizeof(result_message), "{\"success\":false,\"message\":\"Failed to connect to Wi-Fi.\"}");
        }
        write(client_sock, result_message, strlen(result_message));
    } else {
        printf("No data received.\n");
        if (result_callback) {
            result_callback(0, "No data received.");
        }
    }

    // Close the client socket
    close(client_sock);
    printf("Disconnected.\n");

    pthread_exit(NULL);
}

int bluetooth_init() {
    // Allocate socket
    server_sock = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
    if (server_sock < 0) {
        perror("Failed to create socket");
        return -1;
    }

    // Bind socket to the first available local Bluetooth adapter
    loc_addr.rc_family = AF_BLUETOOTH;
    loc_addr.rc_bdaddr = *BDADDR_ANY;
    loc_addr.rc_channel = (uint8_t) 1; // RFCOMM channel

    if (bind(server_sock, (struct sockaddr*)&loc_addr, sizeof(loc_addr)) < 0) {
        perror("Bind failed");
        close(server_sock);
        return -1;
    }

    // Put socket into listening mode
    if (listen(server_sock, 1) < 0) {
        perror("Listen failed");
        close(server_sock);
        return -1;
    }

    printf("Bluetooth service initialized. Listening for connections...\n");
    return 0;
}

int bluetooth_start(connection_result_callback callback) {
    result_callback = callback;

    // Start the Bluetooth handler thread
    if (pthread_create(&bluetooth_thread, NULL, bluetooth_handler, NULL) != 0) {
        perror("Failed to create Bluetooth handler thread");
        return -1;
    }

    return 0;
}

void bluetooth_stop() {
    // Close sockets
    if (client_sock > 0) {
        close(client_sock);
    }
    if (server_sock > 0) {
        close(server_sock);
    }

    // Cancel the thread
    pthread_cancel(bluetooth_thread);
    pthread_join(bluetooth_thread, NULL);

    printf("Bluetooth service stopped.\n");
}