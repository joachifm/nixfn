/*
 * linux_reboot.c - unsafe halt command
 */

#include <errno.h>
#include <stdio.h>

#include <unistd.h>

#include <sys/reboot.h>
#include <linux/reboot.h>

/*
 * Halt the system.
 *
 * 'P' to power off
 * 'r' to restart
 * otherwise, halt and return to the ROM monitor (if any).
 *
 * All data not written out by a preceding sync(2) is lost.
 */
int main(int argc, char* argv[argc]) {
  int cmd = LINUX_REBOOT_CMD_HALT;
  if (argc > 1) {
    switch (argv[1][0]) {
      case 'P':
        cmd = LINUX_REBOOT_CMD_POWER_OFF;
        break;
      case 'r':
        cmd = LINUX_REBOOT_CMD_RESTART;
        break;
    }
  }
  reboot(cmd);
  fprintf(stderr, "reboot: %m\n");
  return -errno;
}
