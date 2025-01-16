#ifndef OVERLAY_SERVICE_H
#define OVERLAY_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the overlay service
int overlay_init();

// Move cursor to specified position (in pixels)
void overlay_move_cursor(int x, int y);

// Update screen rotation (0, 90, 180, 270 degrees)
void overlay_set_rotation(int degrees);

// Clean up resources
void overlay_cleanup();

#ifdef __cplusplus
}
#endif

#endif // OVERLAY_SERVICE_H 