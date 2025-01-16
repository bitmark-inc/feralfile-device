#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xrender.h>
#include <cairo/cairo.h>
#include <cairo/cairo-xlib.h>
#include <pthread.h>
#include <unistd.h>
#include <math.h>
#include "overlay_service.h"

#define CURSOR_SIZE 20
#define ARROW_SIZE 40
#define FADE_TIMEOUT 3000  // 3 seconds in milliseconds

static Display *display = NULL;
static Window window;
static cairo_surface_t *surface = NULL;
static cairo_t *cr = NULL;
static int screen_width = 0;
static int screen_height = 0;
static int current_x = 0;
static int current_y = 0;
static int current_rotation = 0;
static pthread_t fade_thread;
static int should_show_cursor = 0;
static int should_show_arrow = 0;
static pthread_mutex_t draw_mutex = PTHREAD_MUTEX_INITIALIZER;

static void draw_cursor(cairo_t *cr, int x, int y) {
    cairo_set_source_rgba(cr, 1, 1, 1, 0.8);
    cairo_set_line_width(cr, 2);
    
    // Draw cursor arrow
    cairo_move_to(cr, x, y);
    cairo_line_to(cr, x + 12, y + 12);
    cairo_line_to(cr, x + 6, y + 12);
    cairo_line_to(cr, x + 8, y + 20);
    cairo_line_to(cr, x + 4, y + 19);
    cairo_line_to(cr, x + 2, y + 11);
    cairo_line_to(cr, x, y);
    cairo_fill(cr);
}

static void draw_ground_arrow(cairo_t *cr, int rotation) {
    int center_x = screen_width / 2;
    int center_y = screen_height / 2;
    int indicator_size = screen_height / 3; // Make the indicator 1/3 of screen height
    
    // Draw semi-transparent background overlay
    cairo_set_source_rgba(cr, 0.2, 0.2, 0.2, 0.5); // Dark gray with 50% transparency
    cairo_rectangle(cr, 0, 0, screen_width, screen_height);
    cairo_fill(cr);
    
    cairo_save(cr);
    cairo_translate(cr, center_x, center_y);
    cairo_rotate(cr, rotation * M_PI / 180);
    
    // Draw circular background
    cairo_set_source_rgba(cr, 0.3, 0.3, 0.3, 0.7); // Slightly darker gray for the circle
    cairo_arc(cr, 0, 0, indicator_size / 2, 0, 2 * M_PI);
    cairo_fill(cr);
    
    // Draw arrow
    cairo_set_source_rgba(cr, 1, 1, 1, 0.9); // White arrow with 90% opacity
    cairo_set_line_width(cr, indicator_size / 20); // Thicker lines
    
    // Draw main arrow shaft
    cairo_move_to(cr, 0, -indicator_size/3);
    cairo_line_to(cr, 0, indicator_size/3);
    
    // Draw arrow head
    int arrow_width = indicator_size / 4;
    int arrow_height = indicator_size / 4;
    cairo_move_to(cr, 0, indicator_size/3);
    cairo_line_to(cr, -arrow_width, indicator_size/3 - arrow_height);
    cairo_move_to(cr, 0, indicator_size/3);
    cairo_line_to(cr, arrow_width, indicator_size/3 - arrow_height);
    
    // Draw with rounded line caps for better appearance
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    cairo_stroke(cr);
    
    // Add "BOTTOM" text
    cairo_set_font_size(cr, indicator_size / 10);
    cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    
    // Center the text
    cairo_text_extents_t extents;
    const char *text = "BOTTOM";
    cairo_text_extents(cr, text, &extents);
    
    cairo_move_to(cr, 
                  -extents.width/2,
                  indicator_size/3 + extents.height * 2);
    cairo_show_text(cr, text);
    
    cairo_restore(cr);
}

static void clear_surface() {
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_paint(cr);
}

static void *fade_timer(void *arg) {
    while (1) {
        if (should_show_cursor || should_show_arrow) {
            usleep(FADE_TIMEOUT * 1000);
            pthread_mutex_lock(&draw_mutex);
            should_show_cursor = 0;
            should_show_arrow = 0;
            clear_surface();
            pthread_mutex_unlock(&draw_mutex);
        }
        usleep(100000);  // Sleep 100ms before next check
    }
    return NULL;
}

int overlay_init() {
    display = XOpenDisplay(NULL);
    if (!display) return -1;

    int screen = DefaultScreen(display);
    Window root = DefaultRootWindow(display);
    
    screen_width = DisplayWidth(display, screen);
    screen_height = DisplayHeight(display, screen);
    
    XVisualInfo vinfo;
    XMatchVisualInfo(display, screen, 32, TrueColor, &vinfo);
    
    XSetWindowAttributes attr;
    attr.colormap = XCreateColormap(display, root, vinfo.visual, AllocNone);
    attr.border_pixel = 0;
    attr.background_pixel = 0;
    attr.override_redirect = True;
    
    // Set window type to be always on top
    Atom window_type = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    Atom window_type_dock = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
    
    window = XCreateWindow(display, root, 0, 0, screen_width, screen_height,
                          0, vinfo.depth, InputOutput, vinfo.visual,
                          CWColormap | CWBorderPixel | CWBackPixel | CWOverrideRedirect, 
                          &attr);
    
    // Set the window type property
    XChangeProperty(display, window, window_type, XA_ATOM, 32,
                   PropModeReplace, (unsigned char *)&window_type_dock, 1);
    
    // Make sure window stays on top
    Atom window_state = XInternAtom(display, "_NET_WM_STATE", False);
    Atom window_state_above = XInternAtom(display, "_NET_WM_STATE_ABOVE", False);
    XChangeProperty(display, window, window_state, XA_ATOM, 32,
                   PropModeReplace, (unsigned char *)&window_state_above, 1);
    
    XserverRegion region = XFixesCreateRegion(display, NULL, 0);
    XFixesSetWindowShapeRegion(display, window, ShapeInput, 0, 0, region);
    XFixesDestroyRegion(display, region);
    
    surface = cairo_xlib_surface_create(display, window, vinfo.visual,
                                      screen_width, screen_height);
    cr = cairo_create(surface);
    
    XMapWindow(display, window);
    XRaiseWindow(display, window);
    
    pthread_create(&fade_thread, NULL, fade_timer, NULL);
    
    return 0;
}

void overlay_move_cursor(int x, int y) {
    pthread_mutex_lock(&draw_mutex);
    current_x = x;
    current_y = y;
    should_show_cursor = 1;
    
    clear_surface();
    draw_cursor(cr, x, y);
    
    if (should_show_arrow) {
        draw_ground_arrow(cr, current_rotation);
    }
    
    cairo_surface_flush(surface);
    XFlush(display);
    pthread_mutex_unlock(&draw_mutex);
}

void overlay_set_rotation(int degrees) {
    pthread_mutex_lock(&draw_mutex);
    current_rotation = degrees;
    should_show_arrow = 1;
    
    clear_surface();
    draw_ground_arrow(cr, degrees);
    
    if (should_show_cursor) {
        draw_cursor(cr, current_x, current_y);
    }
    
    cairo_surface_flush(surface);
    XFlush(display);
    pthread_mutex_unlock(&draw_mutex);
}

void overlay_cleanup() {
    pthread_cancel(fade_thread);
    pthread_join(fade_thread, NULL);
    
    if (cr) cairo_destroy(cr);
    if (surface) cairo_surface_destroy(surface);
    if (window) XDestroyWindow(display, window);
    if (display) XCloseDisplay(display);
} 