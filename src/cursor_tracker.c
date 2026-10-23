#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>

static volatile sig_atomic_t g_running = 1;

static void handle_sig(int sig) {
    (void)sig;
    g_running = 0;
}

int main(void) {
    signal(SIGTERM, handle_sig);
    signal(SIGINT, handle_sig);
    signal(SIGPIPE, SIG_IGN);

    char *runtime = getenv("XDG_RUNTIME_DIR");
    char *sig = getenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (!runtime || !sig) {
        fprintf(stderr, "cursor_tracker: missing XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE\n");
        return 1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/hypr/%s/.socket.sock", runtime, sig);

    char last[64] = "";
    char buf[64];

    // Disable stdout buffering for immediate QML pipe delivery
    setvbuf(stdout, NULL, _IONBF, 0);

    while (g_running) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd >= 0) {
            if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                if (write(fd, "cursorpos", 9) == 9) {
                    ssize_t n = read(fd, buf, sizeof(buf) - 1);
                    if (n > 0) {
                        buf[n] = '\0';
                        if (strcmp(buf, last) != 0) {
                            snprintf(last, sizeof(last), "%s", buf);
                            int x = 0, y = 0;
                            if (sscanf(buf, "%d, %d", &x, &y) == 2) {
                                printf("%d %d\n", x, y);
                            }
                        }
                    }
                }
            }
            close(fd);
        }
        usleep(8000); // 120Hz polling interval (~8.3ms)
    }

    return 0;
}
