#include "TunFD.h"

#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>

/* <sys/kern_control.h> is not part of the public iOS SDK. */
#ifndef AF_SYSTEM
#define AF_SYSTEM 32
#endif
#define ZT_CTLIOCGINFO 0xc0644e03UL
#define ZT_UTUN_CONTROL_NAME "com.apple.net.utun_control"

struct zt_ctl_info {
    u_int32_t ctl_id;
    char ctl_name[96];
};

struct zt_sockaddr_ctl {
    u_char sc_len;
    u_char sc_family;
    u_int16_t ss_sysaddr;
    u_int32_t sc_id;
    u_int32_t sc_unit;
    u_int32_t sc_reserved[5];
};

int zapret_find_tun_fd(void)
{
    struct zt_ctl_info info;
    memset(&info, 0, sizeof(info));
    strncpy(info.ctl_name, ZT_UTUN_CONTROL_NAME, sizeof(info.ctl_name) - 1);

    for (int fd = 0; fd <= 1024; fd++) {
        struct zt_sockaddr_ctl addr;
        socklen_t len = sizeof(addr);
        memset(&addr, 0, sizeof(addr));

        if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0) {
            continue;
        }
        if (addr.sc_family != AF_SYSTEM) {
            continue;
        }
        if (info.ctl_id == 0) {
            if (ioctl(fd, ZT_CTLIOCGINFO, &info) != 0) {
                continue;
            }
        }
        if (addr.sc_id == info.ctl_id) {
            return fd;
        }
    }
    return -1;
}
