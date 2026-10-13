#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include <cairo/cairo.h>
#include <pango/pangocairo.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#define PANEL_W_DEFAULT 1080
#define PANEL_H_DEFAULT 560
#define SPLIT_X 540

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wl_seat *seat;
static struct wl_pointer *pointer;
static struct wl_touch *touch;
static struct wl_surface *surface;
static struct zwlr_layer_surface_v1 *layer_surface;
static struct wl_buffer *buffer;
static void *buffer_data;
static size_t buffer_size;
static int buffer_busy;
static int configured;
static volatile sig_atomic_t running = 1;
static uint32_t panel_w = PANEL_W_DEFAULT, panel_h = PANEL_H_DEFAULT;
static cairo_surface_t *cairo_surface;
static cairo_t *cr;
static double ptr_x = 0, ptr_y = 0;
static struct timespec last_draw;

/* ---------- stats ---------- */
static char wifi_ssid[128] = "disconnected";
static char wifi_state[128] = "";
static int wifi_signal = -1;
static double rx_kbs, tx_kbs;
static unsigned long long last_rx_bytes, last_tx_bytes;
static struct timespec last_net_ts;
static char cpu1_name[64] = "-", cpu2_name[64] = "-";
static double cpu1_pct, cpu2_pct;
static double power_w = 0.0;
static int batt_pct = -1;
static char batt_status[64] = "";
static long batt_runtime_s = -1;

static long read_sysfs_long(const char *path)
{
char buf[128];
int fd = open(path, O_RDONLY);
if (fd < 0) return -1;
ssize_t n = read(fd, buf, sizeof(buf) - 1);
close(fd);
if (n <= 0) return -1;
buf[n] = 0;
return strtol(buf, NULL, 10);
}

static void read_sysfs_str(const char *path, char *out, size_t n)
{
int fd = open(path, O_RDONLY);
if (fd < 0) { if (n) out[0] = 0; return; }
ssize_t r = read(fd, out, n - 1);
close(fd);
if (r <= 0) { if (n) out[0] = 0; return; }
out[r] = 0;
char *nl = strchr(out, '\n');
if (nl) *nl = 0;
}

static int run_cmd(const char *cmd, char *out, size_t n)
{
out[0] = 0;
FILE *fp = popen(cmd, "r");
if (!fp) return -1;
size_t used = 0;
while (used + 1 < n && fgets(out + used, n - used, fp)) used += strlen(out + used);
pclose(fp);
while (used > 0 && (out[used - 1] == '\n' || out[used - 1] == '\r')) out[--used] = 0;
return (int)used;
}

static void update_wifi(void)
{
char conn[256] = "", state[256] = "";
FILE *fp = popen("/usr/bin/nmcli -t -f GENERAL.CONNECTION,GENERAL.STATE dev show wlan0 2>/dev/null", "r");
if (fp) {
char line[512];
while (fgets(line, sizeof(line), fp)) {
char *nl = strchr(line, '\n'); if (nl) *nl = 0;
if (!strncmp(line, "GENERAL.CONNECTION:", 19)) snprintf(conn, sizeof(conn), "%s", line + 19);
else if (!strncmp(line, "GENERAL.STATE:", 14)) snprintf(state, sizeof(state), "%s", line + 14);
}
pclose(fp);
}
if (conn[0] == 0 || !strcmp(conn, "--")) snprintf(wifi_ssid, sizeof(wifi_ssid), "disconnected");
else snprintf(wifi_ssid, sizeof(wifi_ssid), "%s", conn);
snprintf(wifi_state, sizeof(wifi_state), "%s", state);
/* pull signal strength of the connected BSS */
wifi_signal = -1;
fp = popen("/usr/bin/nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null", "r");
if (fp) {
char line[256];
while (fgets(line, sizeof(line), fp)) {
int sig = 0;
if (line[0] == '*' && sscanf(line + 1, ":%d", &sig) == 1) { wifi_signal = sig; break; }
}
pclose(fp);
}
}

static void update_net(void)
{
FILE *fp = fopen("/proc/net/dev", "r");
if (!fp) return;
char line[512];
unsigned long long rb = 0, tb = 0;
while (fgets(line, sizeof(line), fp)) {
char *colon = strchr(line, ':');
if (!colon) continue;
char ifname[64];
size_t len = colon - line;
if (len >= sizeof(ifname)) len = sizeof(ifname) - 1;
memcpy(ifname, line, len); ifname[len] = 0;
char *p = ifname; while (*p == ' ') p++;
if (strcmp(p, "wlan0")) continue;
sscanf(colon + 1, "%llu %*u %*u %*u %*u %*u %*u %*u %llu", &rb, &tb);
break;
}
fclose(fp);
struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
double dt = (now.tv_sec - last_net_ts.tv_sec) + (now.tv_nsec - last_net_ts.tv_nsec) / 1e9;
if (last_net_ts.tv_sec != 0 && dt < 0.8)
return;                 /* keep baseline until the 1 Hz panel tick */
if (last_net_ts.tv_sec && dt > 0.2) {
rx_kbs = (rb - last_rx_bytes) / 1024.0 / dt;
tx_kbs = (tb - last_tx_bytes) / 1024.0 / dt;
if (rx_kbs < 0) rx_kbs = 0;
if (tx_kbs < 0) tx_kbs = 0;
}
last_rx_bytes = rb; last_tx_bytes = tb; last_net_ts = now;
}

static int cpu_name_skip(const char *name)
{
static const char *skip[] = { "ps", "head", "awk", "sh", "pearl-panel", NULL };
for (int i = 0; skip[i]; i++) if (!strcmp(name, skip[i])) return 1;
return 0;
}

static void update_cpu(void)
{
char out[2048];
int found = 0;
cpu1_name[0] = cpu2_name[0] = 0; cpu1_pct = cpu2_pct = 0;
if (run_cmd("/usr/bin/ps -eo comm,pcpu --sort=-pcpu --no-headers 2>/dev/null | head -10", out, sizeof(out)) > 0) {
char *save = NULL;
for (char *line = strtok_r(out, "\n", &save); line && found < 2; line = strtok_r(NULL, "\n", &save)) {
char name[64]; double pct = 0;
if (sscanf(line, "%63s %lf", name, &pct) == 2 && !cpu_name_skip(name)) {
if (found == 0) { snprintf(cpu1_name, sizeof(cpu1_name), "%s", name); cpu1_pct = pct; }
else { snprintf(cpu2_name, sizeof(cpu2_name), "%s", name); cpu2_pct = pct; }
found++;
}
}
}
if (!cpu1_name[0]) snprintf(cpu1_name, sizeof(cpu1_name), "-");
if (!cpu2_name[0]) snprintf(cpu2_name, sizeof(cpu2_name), "-");
}

static void update_power(void)
{
long cap = read_sysfs_long("/sys/class/power_supply/bq28z610-0/capacity");
batt_pct = (int)cap;
read_sysfs_str("/sys/class/power_supply/bq28z610-0/status", batt_status, sizeof(batt_status));
long v = read_sysfs_long("/sys/class/power_supply/bq28z610-0/voltage_now");
long c = read_sysfs_long("/sys/class/power_supply/bq28z610-0/current_now");
if (v > 0 && c != 0) {
double cur = c < 0 ? -c : c;
power_w = (v / 1e6) * (cur / 1e6);
} else {
power_w = 0;
}
long eta = read_sysfs_long("/sys/class/power_supply/bq28z610-0/time_to_empty_now");
if (eta <= 0) eta = read_sysfs_long("/sys/class/power_supply/bq28z610-0/time_to_full_now");
if (eta <= 0 && c != 0) {
long charge = read_sysfs_long("/sys/class/power_supply/bq28z610-0/charge_now");
if (charge > 0) eta = (long)(charge * 3600.0 / (double)(c < 0 ? -c : c));
}
batt_runtime_s = eta > 0 ? eta : -1;
}

static void update_stats(void)
{
update_wifi();
update_net();
update_cpu();
update_power();
}

/* ---------- drawing ---------- */
static void draw_text(double x, double y, const char *text, const char *font, double r, double g, double b)
{
if (!cr || !text || !*text) return;
PangoLayout *layout = pango_cairo_create_layout(cr);
pango_layout_set_text(layout, text, -1);
PangoFontDescription *fd = pango_font_description_from_string(font);
pango_layout_set_font_description(layout, fd);
cairo_set_source_rgb(cr, r, g, b);
cairo_move_to(cr, x, y);
pango_cairo_show_layout(cr, layout);
pango_font_description_free(fd);
g_object_unref(layout);
}

static void format_eta(char *out, size_t n)
{
if (batt_runtime_s < 0) { snprintf(out, n, "--"); return; }
long s = batt_runtime_s;
long h = s / 3600, m = (s % 3600) / 60;
snprintf(out, n, "%ldh%02ldm", h, m);
}

static void draw_panel(void)
{
if (!cr) return;
update_stats();
cairo_set_source_rgb(cr, 0.04, 0.05, 0.07);
cairo_paint(cr);
cairo_set_source_rgb(cr, 0.16, 0.18, 0.22);
cairo_set_line_width(cr, 2);
cairo_move_to(cr, SPLIT_X, 12);
cairo_line_to(cr, SPLIT_X, panel_h - 12);
cairo_stroke(cr);

char buf[256];
/* C: Wi-Fi + traffic (clip to left half) */
cairo_save(cr);
cairo_rectangle(cr, 0, 0, SPLIT_X - 8, panel_h);
cairo_clip(cr);
draw_text(24, 16, "WiFi", "Monospace Bold 24", 0.55, 0.75, 1.0);
if (wifi_signal >= 0) snprintf(buf, sizeof(buf), "%s   %d%%", wifi_ssid, wifi_signal);
else snprintf(buf, sizeof(buf), "%s", wifi_ssid);
draw_text(24, 64, buf, "Monospace 26", 1, 1, 1);
if (wifi_state[0]) draw_text(24, 112, wifi_state, "Monospace 16", 0.6, 0.65, 0.7);
snprintf(buf, sizeof(buf), "D:%.0f KB/s  U:%.0f KB/s", rx_kbs, tx_kbs);
draw_text(24, 172, buf, "Monospace 20", 0.45, 0.95, 0.55);
snprintf(buf, sizeof(buf), "Total RX %.1f MB  TX %.1f MB", last_rx_bytes / 1048576.0, last_tx_bytes / 1048576.0);
draw_text(24, 224, buf, "Monospace 16", 0.55, 0.6, 0.65);
draw_text(24, 286, "Tap here: NetworkManager (nmtui)", "Monospace 16", 0.5, 0.55, 0.6);
cairo_restore(cr);

/* D: top CPU + power/battery (clip to right half) */
cairo_save(cr);
cairo_rectangle(cr, SPLIT_X + 8, 0, panel_w - SPLIT_X - 8, panel_h);
cairo_clip(cr);
draw_text(SPLIT_X + 24, 16, "System", "Monospace Bold 24", 1.0, 0.75, 0.4);
snprintf(buf, sizeof(buf), "CPU  %-12s %5.1f%%", cpu1_name, cpu1_pct);
draw_text(SPLIT_X + 24, 64, buf, "Monospace 22", 1, 1, 1);
snprintf(buf, sizeof(buf), "     %-12s %5.1f%%", cpu2_name, cpu2_pct);
draw_text(SPLIT_X + 24, 104, buf, "Monospace 22", 1, 1, 1);
snprintf(buf, sizeof(buf), "Power   %5.2f W", power_w);
draw_text(SPLIT_X + 24, 164, buf, "Monospace 22", 1.0, 0.55, 0.45);
if (batt_pct >= 0) {
char eta[64]; format_eta(eta, sizeof(eta));
snprintf(buf, sizeof(buf), "Battery %3d%%  %s", batt_pct, batt_status);
draw_text(SPLIT_X + 24, 214, buf, "Monospace 22", 0.5, 0.9, 1.0);
snprintf(buf, sizeof(buf), "ETA     %s", eta);
draw_text(SPLIT_X + 24, 264, buf, "Monospace 22", 0.5, 0.9, 1.0);
} else {
draw_text(SPLIT_X + 24, 214, "Battery --", "Monospace 22", 0.5, 0.9, 1.0);
}
draw_text(SPLIT_X + 24, 326, "Tap here: htop-style view", "Monospace 16", 0.5, 0.55, 0.6);
cairo_restore(cr);
cairo_surface_flush(cairo_surface);
}

/* ---------- input / spawn ---------- */
static void spawn_app(const char *title, const char *app)
{
pid_t pid = fork();
if (pid == 0) {
setsid();
char *argv[] = { "/usr/bin/kitty", "--single-instance", "--title", (char *)title, "-e", (char *)app, NULL };
execv("/usr/bin/kitty", argv);
_exit(127);
}
}

static void handle_click(double x, double y)
{
if (x < SPLIT_X) spawn_app("NetworkManager", "/usr/bin/nmtui");
else spawn_app("System", "/usr/bin/top");
}

static void pointer_enter(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t sx, wl_fixed_t sy)
{ (void)data;(void)p;(void)serial;(void)s; ptr_x = wl_fixed_to_double(sx); ptr_y = wl_fixed_to_double(sy); }
static void pointer_leave(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s)
{ (void)data;(void)p;(void)serial;(void)s; }
static void pointer_motion(void *data, struct wl_pointer *p, uint32_t t, wl_fixed_t sx, wl_fixed_t sy)
{ (void)data;(void)p;(void)t; ptr_x = wl_fixed_to_double(sx); ptr_y = wl_fixed_to_double(sy); }
static void pointer_button(void *data, struct wl_pointer *p, uint32_t serial, uint32_t t, uint32_t button, uint32_t state)
{ (void)data;(void)p;(void)serial;(void)t; if (state == WL_POINTER_BUTTON_STATE_PRESSED && button == BTN_LEFT) handle_click(ptr_x, ptr_y); }
static void pointer_axis(void *data, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v)
{ (void)data;(void)p;(void)t;(void)a;(void)v; }
static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
};

static void touch_down(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, struct wl_surface *s, int32_t id, wl_fixed_t x, wl_fixed_t y)
{ (void)data;(void)t;(void)serial;(void)time;(void)s;(void)id; handle_click(wl_fixed_to_double(x), wl_fixed_to_double(y)); }
static void touch_up(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, int32_t id)
{ (void)data;(void)t;(void)serial;(void)time;(void)id; }
static void touch_motion(void *data, struct wl_touch *t, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y)
{ (void)data;(void)t;(void)time;(void)id;(void)x;(void)y; }
static void touch_frame(void *data, struct wl_touch *t) { (void)data;(void)t; }
static void touch_cancel(void *data, struct wl_touch *t) { (void)data;(void)t; }
static void touch_shape(void *data, struct wl_touch *t, int32_t id, wl_fixed_t x, wl_fixed_t y) { (void)data;(void)t;(void)id;(void)x;(void)y; }
static void touch_orientation(void *data, struct wl_touch *t, int32_t id, wl_fixed_t o) { (void)data;(void)t;(void)id;(void)o; }
static const struct wl_touch_listener touch_listener = { touch_down, touch_up, touch_motion, touch_frame, touch_cancel, touch_shape, touch_orientation };

static void seat_capabilities(void *data, struct wl_seat *s, uint32_t caps)
{
(void)data;(void)s;
if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
pointer = wl_seat_get_pointer(seat);
wl_pointer_add_listener(pointer, &pointer_listener, NULL);
}
if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !touch) {
touch = wl_seat_get_touch(seat);
wl_touch_add_listener(touch, &touch_listener, NULL);
}
}
static void seat_name(void *data, struct wl_seat *s, const char *name) { (void)data;(void)s;(void)name; }
static const struct wl_seat_listener seat_listener = { seat_capabilities, seat_name };

/* ---------- shm buffer ---------- */
static int create_shm_file(size_t size)
{
int fd = memfd_create("pearl-panel", MFD_CLOEXEC);
if (fd < 0) return -1;
if (ftruncate(fd, size) < 0) { close(fd); return -1; }
return fd;
}

static void buffer_release(void *data, struct wl_buffer *b) { (void)data;(void)b; buffer_busy = 0; }
static const struct wl_buffer_listener buffer_listener = { buffer_release };

static int create_buffer(void)
{
if (buffer) { wl_buffer_destroy(buffer); buffer = NULL; }
if (cairo_surface) { cairo_surface_destroy(cairo_surface); cairo_surface = NULL; }
if (cr) { cairo_destroy(cr); cr = NULL; }
int stride = (int)panel_w * 4;
buffer_size = (size_t)stride * panel_h;
int fd = create_shm_file(buffer_size);
if (fd < 0) return -1;
buffer_data = mmap(NULL, buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
if (buffer_data == MAP_FAILED) { close(fd); buffer_data = NULL; return -1; }
struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int)buffer_size);
buffer = wl_shm_pool_create_buffer(pool, 0, panel_w, panel_h, stride, WL_SHM_FORMAT_ARGB8888);
wl_shm_pool_destroy(pool);
close(fd);
if (!buffer) return -1;
wl_buffer_add_listener(buffer, &buffer_listener, NULL);
cairo_surface = cairo_image_surface_create_for_data(buffer_data, CAIRO_FORMAT_ARGB32, panel_w, panel_h, stride);
cr = cairo_create(cairo_surface);
buffer_busy = 0;
return 0;
}

/* ---------- layer surface ---------- */
static void ls_configure(void *data, struct zwlr_layer_surface_v1 *ls, uint32_t serial, uint32_t width, uint32_t height)
{
(void)data;
zwlr_layer_surface_v1_ack_configure(ls, serial);
if (width > 0) panel_w = width;
if (height > 0) panel_h = height;
if (!buffer || configured == 0) { if (create_buffer() < 0) { fprintf(stderr, "buffer create failed\n"); return; } }
configured = 1;
draw_panel();
wl_surface_attach(surface, buffer, 0, 0);
wl_surface_damage(surface, 0, 0, panel_w, panel_h);
wl_surface_commit(surface);
buffer_busy = 1;
}
static void ls_closed(void *data, struct zwlr_layer_surface_v1 *ls) { (void)data;(void)ls; running = 0; }
static const struct zwlr_layer_surface_v1_listener ls_listener = { ls_configure, ls_closed };

static void registry_global(void *data, struct wl_registry *reg, uint32_t name, const char *interface, uint32_t version)
{
(void)data;
if (!strcmp(interface, wl_compositor_interface.name)) compositor = wl_registry_bind(reg, name, &wl_compositor_interface, version < 4 ? version : 4);
else if (!strcmp(interface, wl_shm_interface.name)) shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
else if (!strcmp(interface, zwlr_layer_shell_v1_interface.name)) layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4);
else if (!strcmp(interface, wl_seat_interface.name)) { seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 5 ? version : 5); wl_seat_add_listener(seat, &seat_listener, NULL); }
}
static void registry_remove(void *data, struct wl_registry *reg, uint32_t name) { (void)data;(void)reg;(void)name; }
static const struct wl_registry_listener registry_listener = { registry_global, registry_remove };

static void on_signal(int sig) { (void)sig; running = 0; }

int main(void)
{
signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
display = wl_display_connect(NULL);
if (!display) { fprintf(stderr, "no wayland display\n"); return 1; }
struct wl_registry *reg = wl_display_get_registry(display);
wl_registry_add_listener(reg, &registry_listener, NULL);
wl_display_roundtrip(display);
if (!compositor || !shm || !layer_shell) { fprintf(stderr, "missing wl globals\n"); return 1; }
surface = wl_compositor_create_surface(compositor);
layer_surface = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_TOP, "pearl-panel");
zwlr_layer_surface_v1_add_listener(layer_surface, &ls_listener, NULL);
zwlr_layer_surface_v1_set_size(layer_surface, panel_w, panel_h);
zwlr_layer_surface_v1_set_anchor(layer_surface, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
zwlr_layer_surface_v1_set_exclusive_zone(layer_surface, panel_h);
zwlr_layer_surface_v1_set_keyboard_interactivity(layer_surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
wl_surface_commit(surface);
wl_display_roundtrip(display);

while (running) {
while (wl_display_prepare_read(display) != 0) wl_display_dispatch_pending(display);
wl_display_flush(display);
struct pollfd pfd = { wl_display_get_fd(display), POLLIN, 0 };
int pr = poll(&pfd, 1, 1000);
if (pr > 0) { wl_display_read_events(display); wl_display_dispatch_pending(display); }
else { wl_display_cancel_read(display); }
struct timespec now;
clock_gettime(CLOCK_MONOTONIC, &now);
double ddraw = (now.tv_sec - last_draw.tv_sec) + (now.tv_nsec - last_draw.tv_nsec) / 1e9;
if (configured && !buffer_busy && (last_draw.tv_sec == 0 || ddraw >= 1.0)) {
last_draw = now;
update_stats();
draw_panel();
wl_surface_attach(surface, buffer, 0, 0);
wl_surface_damage(surface, 0, 0, panel_w, panel_h);
wl_surface_commit(surface);
buffer_busy = 1;
}
wl_display_dispatch_pending(display);
}
return 0;
}
