#ifndef ZDPI_H
#define ZDPI_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Embedded byedpi ("ciadpi") engine.
 *
 * zdpi_run() parses byedpi command line arguments, binds the local SOCKS5
 * server and runs the event loop. It BLOCKS until zdpi_stop() is called or
 * the loop fails, so call it from a dedicated thread.
 *
 * Only one engine instance can run per process (byedpi keeps global state).
 *
 * Return values:
 *    0  - stopped normally
 *   -2  - engine is already running
 *   -3  - invalid arguments
 *   -4  - init failed
 *   -5  - could not bind the listening socket
 */
int zdpi_run(int argc, const char **argv);

/* Thread safe. Requests the running loop to stop and wakes it up. */
void zdpi_stop(void);

/* 1 while zdpi_run() is inside its event loop. */
int zdpi_is_running(void);

/*
 * Bind every outgoing engine socket to this interface index
 * (IP_BOUND_IF / IPV6_BOUND_IF). 0 disables binding. Takes effect for new
 * connections immediately, no restart needed. Used in proxy mode so traffic
 * of the engine is not captured again by a third-party VPN app.
 */
void zdpi_set_bound_interface(unsigned int ifindex);
unsigned int zdpi_bound_interface(void);

/* Redirect process stderr (where byedpi writes its log) to a file. */
int zdpi_redirect_stderr(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* ZDPI_H */
