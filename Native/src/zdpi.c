/*
 * Thin wrapper that makes byedpi embeddable and restartable inside an iOS
 * process (Network Extension or the app itself for the strategy tester).
 *
 * byedpi is compiled with -Dmain=ciadpi_main, so its own main() is unused.
 * conev.c is patched (see Native/build.sh) so the event loop also checks
 * zdpi_stop_requested.
 */
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "params.h"
#include "proxy.h"
#include "zdpi.h"

extern int server_fd;
int parse_args(int argc, char **argv);
int init(void);
void clear_params(char *line, char **argv);

volatile int zdpi_stop_requested = 0;

static pthread_mutex_t zdpi_lock = PTHREAD_MUTEX_INITIALIZER;
static struct params zdpi_defaults;
static int zdpi_defaults_saved = 0;
static int zdpi_running = 0;
static int zdpi_listen_fd = -1;
static union sockaddr_u zdpi_listen_addr;

int zdpi_redirect_stderr(const char *path)
{
    if (!path) {
        return -1;
    }
    if (!freopen(path, "a", stderr)) {
        return -1;
    }
    setvbuf(stderr, NULL, _IONBF, 0);
    return 0;
}

int zdpi_is_running(void)
{
    pthread_mutex_lock(&zdpi_lock);
    int r = zdpi_running && zdpi_listen_fd >= 0;
    pthread_mutex_unlock(&zdpi_lock);
    return r;
}

static void zdpi_finish(void)
{
    pthread_mutex_lock(&zdpi_lock);
    zdpi_running = 0;
    zdpi_listen_fd = -1;
    pthread_mutex_unlock(&zdpi_lock);
}

int zdpi_run(int argc, const char **argv)
{
    pthread_mutex_lock(&zdpi_lock);
    if (zdpi_running) {
        pthread_mutex_unlock(&zdpi_lock);
        return -2;
    }
    zdpi_running = 1;
    zdpi_listen_fd = -1;
    zdpi_stop_requested = 0;

    /* Restore pristine global params so the engine can be restarted. */
    if (!zdpi_defaults_saved) {
        zdpi_defaults = params;
        zdpi_defaults_saved = 1;
    } else {
        params = zdpi_defaults;
    }
    pthread_mutex_unlock(&zdpi_lock);

    signal(SIGPIPE, SIG_IGN);

    /* Reset getopt state (BSD libc). */
    optind = 1;
    optreset = 1;
    opterr = 1;

    int status = parse_args(argc, (char **)argv);
    if (status) {
        clear_params(NULL, NULL);
        zdpi_finish();
        return -3;
    }
    if (init() < 0) {
        clear_params(NULL, NULL);
        zdpi_finish();
        return -4;
    }
    int fd = listen_socket(&params.laddr);
    if (fd < 0) {
        clear_params(NULL, NULL);
        zdpi_finish();
        return -5;
    }

    pthread_mutex_lock(&zdpi_lock);
    zdpi_listen_fd = fd;
    zdpi_listen_addr = params.laddr;
    int stop_early = zdpi_stop_requested;
    pthread_mutex_unlock(&zdpi_lock);

    if (stop_early) {
        close(fd);
        clear_params(NULL, NULL);
        zdpi_finish();
        return 0;
    }

    fprintf(stderr, "[zdpi] listening on %s:%d\n",
        inet_ntoa(params.laddr.in.sin_addr), ntohs(params.laddr.in.sin_port));

    start_event_loop(fd);

    fprintf(stderr, "[zdpi] event loop finished\n");
    clear_params(NULL, NULL);
    zdpi_finish();
    return 0;
}

void zdpi_stop(void)
{
    pthread_mutex_lock(&zdpi_lock);
    zdpi_stop_requested = 1;
    int fd = zdpi_listen_fd;
    union sockaddr_u addr = zdpi_listen_addr;
    pthread_mutex_unlock(&zdpi_lock);

    if (fd < 0) {
        return;
    }
    /* Wake up poll(): connect to our own listening socket. The loop
     * checks zdpi_stop_requested after handling the event and exits. */
    int s = socket(addr.sa.sa_family, SOCK_STREAM, 0);
    if (s >= 0) {
        int flags = fcntl(s, F_GETFL, 0);
        fcntl(s, F_SETFL, flags | O_NONBLOCK);
        connect(s, &addr.sa, SA_SIZE(&addr));
        usleep(20 * 1000);
        close(s);
    }
}
