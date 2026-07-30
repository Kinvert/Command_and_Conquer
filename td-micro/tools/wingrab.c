/* Capture a specific X window's pixels via XGetImage and stream raw BGRA to stdout.
 *
 * WSLg composites through Wayland, so ffmpeg's x11grab on the root window records nothing.
 * Reading the window drawable directly is a different path and may still work. This also verifies
 * the content actually changes rather than reporting success on a blank buffer.
 *
 * usage: wingrab <window-id-hex> <fps> <seconds>   (raw BGRA frames on stdout)
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char** argv)
{
    if (argc < 4) { fprintf(stderr, "usage: wingrab <winid> <fps> <secs>\n"); return 2; }
    Window win = (Window)strtoul(argv[1], NULL, 16);
    const int fps = atoi(argv[2]);
    const int secs = atoi(argv[3]);

    Display* d = XOpenDisplay(":0");
    if (!d) { fprintf(stderr, "cannot open :0\n"); return 1; }
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, win, &wa)) { fprintf(stderr, "bad window\n"); return 1; }
    fprintf(stderr, "window %lux%lu depth %d\n", (unsigned long)wa.width, (unsigned long)wa.height, wa.depth);

    const long total = (long)fps * secs;
    const long delay_ns = 1000000000L / fps;
    long nonblank = 0;
    unsigned char* prev = malloc((size_t)wa.width * wa.height * 4);
    memset(prev, 0, (size_t)wa.width * wa.height * 4);

    for (long f = 0; f < total; ++f) {
        XImage* img = XGetImage(d, win, 0, 0, wa.width, wa.height, AllPlanes, ZPixmap);
        if (!img) { fprintf(stderr, "XGetImage failed at frame %ld\n", f); break; }
        const size_t bytes = (size_t)img->bytes_per_line * img->height;
        fwrite(img->data, 1, bytes, stdout);
        if (f > 0 && memcmp(prev, img->data, bytes < (size_t)wa.width * wa.height * 4 ? bytes : (size_t)wa.width * wa.height * 4) != 0) ++nonblank;
        memcpy(prev, img->data, bytes < (size_t)wa.width * wa.height * 4 ? bytes : (size_t)wa.width * wa.height * 4);
        XDestroyImage(img);
        struct timespec ts = {0, delay_ns};
        nanosleep(&ts, NULL);
    }
    fprintf(stderr, "frames differing from previous: %ld of %ld\n", nonblank, total);
    XCloseDisplay(d);
    return 0;
}
