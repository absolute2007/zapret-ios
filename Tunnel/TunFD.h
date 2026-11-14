#ifndef ZAPRET_TUNFD_H
#define ZAPRET_TUNFD_H

/* Returns the file descriptor of the utun interface owned by this
 * NEPacketTunnelProvider process, or -1 if it was not found. */
int zapret_find_tun_fd(void);

#endif
