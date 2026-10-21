/*
 * Linux USB support
 *
 * Copyright (c) 2000-2003 Johannes Erdfelt <johannes@erdfelt.com>
 *
 * This library is covered by the LGPL, read LICENSE for details.
 */

#include <stdlib.h>	/* getenv, etc */
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/time.h>
#include <dirent.h>
#include <pthread.h>
#include <poll.h>
#include <time.h>

#include "linux.h"
#include "usbi.h"

/* redefine linux ETIMEDOUT to match libusb-win32 ETIMEDOUT value */
#undef ETIMEDOUT
#define ETIMEDOUT 116

static char usb_path[PATH_MAX + 1] = "";

static int device_open(struct usb_device *dev)
{
  char filename[PATH_MAX + 1];
  int fd;

  snprintf(filename, sizeof(filename) - 1, "%s/%s/%s",
    usb_path, dev->bus->dirname, dev->filename);

  fd = open(filename, O_RDWR);
  if (fd < 0) {
    fd = open(filename, O_RDONLY);
    if (fd < 0)
      USB_ERROR_STR(-errno, "failed to open %s: %s",
	filename, strerror(errno));
  }

  return fd;
}

int usb_os_open(usb_dev_handle *dev)
{
  dev->fd = device_open(dev->device);

  return 0;
}

int usb_os_close(usb_dev_handle *dev)
{
  if (dev->fd < 0)
    return 0;

  if (close(dev->fd) == -1)
    /* Failing trying to close a file really isn't an error, so return 0 */
    USB_ERROR_STR(0, "tried to close device fd %d: %s", dev->fd,
	strerror(errno));

  return 0;
}

int usb_set_configuration(usb_dev_handle *dev, int configuration)
{
  int ret;

  /* detach kernel driver for windows program ( Stanson <me@stanson.ch > ) */
  usb_detach_kernel_driver_np(dev, 0);

  ret = ioctl(dev->fd, IOCTL_USB_SETCONFIG, &configuration);
  if (ret < 0)
    USB_ERROR_STR(-errno, "could not set config %d: %s", configuration,
	strerror(errno));

  dev->config = configuration;

  return 0;
}

int usb_claim_interface(usb_dev_handle *dev, int interface)
{
  int ret;

  ret = ioctl(dev->fd, IOCTL_USB_CLAIMINTF, &interface);
  if (ret < 0) {
    if (errno == EBUSY && usb_debug > 0)
      fprintf(stderr, "Check that you have permissions to write to %s/%s and, if you don't, that you set up hotplug (http://linux-hotplug.sourceforge.net/) correctly.\n", dev->bus->dirname, dev->device->filename);

    USB_ERROR_STR(-errno, "could not claim interface %d: %s", interface,
	strerror(errno));
  }

  dev->interface = interface;

  return 0;
}

int usb_release_interface(usb_dev_handle *dev, int interface)
{
  int ret;

  ret = ioctl(dev->fd, IOCTL_USB_RELEASEINTF, &interface);
  if (ret < 0)
    USB_ERROR_STR(-errno, "could not release intf %d: %s", interface,
    	strerror(errno));

  dev->interface = -1;

  return 0;
}

int usb_set_altinterface(usb_dev_handle *dev, int alternate)
{
  int ret;
  struct usb_setinterface setintf;

  if (dev->interface < 0)
    USB_ERROR(-EINVAL);

  setintf.interface = dev->interface;
  setintf.altsetting = alternate;

  ret = ioctl(dev->fd, IOCTL_USB_SETINTF, &setintf);
  if (ret < 0)
    USB_ERROR_STR(-errno, "could not set alt intf %d/%d: %s",
	dev->interface, alternate, strerror(errno));

  dev->altsetting = alternate;

  return 0;
}

/*
 * Linux usbfs has a limit of one page size for synchronous bulk read/write.
 * 4096 is the most portable maximum we can do for now.
 * Linux usbfs has a limit of 16KB for the URB interface. We use this now
 * to get better performance for USB 2.0 devices.
 */
#define MAX_READ_WRITE	(16 * 1024)

int usb_control_msg(usb_dev_handle *dev, int requesttype, int request,
	int value, int index, char *bytes, int size, int timeout)
{
  struct usb_ctrltransfer ctrl;
  int ret;

  ctrl.bRequestType = requesttype;
  ctrl.bRequest = request;
  ctrl.wValue = value;
  ctrl.wIndex = index;
  ctrl.wLength = size;

  ctrl.data = bytes;
  ctrl.timeout = timeout;

  ret = ioctl(dev->fd, IOCTL_USB_CONTROL, &ctrl);
  if (ret < 0)
    USB_ERROR_STR(-errno, "error sending control message: %s", strerror(errno));

  return ret;
}

/*
 * URB completion dispatcher (libusb0.dll bridge for Wine).
 *
 * usbfs hands back completions per file descriptor, not per caller, so with
 * several threads (e.g. ANT_DLL's receive thread blocked on an async read while
 * another thread writes a command) one thread can reap another thread's URB.
 * Every URB we submit therefore carries an owner record in usercontext; whoever
 * reaps a completion marks its owner done, and each caller waits (with a real
 * timeout) only for its own owner.
 */
struct urb_owner {
  struct usb_urb urb;
  int done;
};

static pthread_mutex_t reap_lock = PTHREAD_MUTEX_INITIALIZER;

static long long now_ms(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void reap_completed(int fd)
{
  struct usb_urb *u;

  pthread_mutex_lock(&reap_lock);
  while (ioctl(fd, IOCTL_USB_REAPURBNDELAY, &u) == 0) {
    struct urb_owner *o = u ? (struct urb_owner *)u->usercontext : NULL;
    if (o)
      __atomic_store_n(&o->done, 1, __ATOMIC_RELEASE);
  }
  pthread_mutex_unlock(&reap_lock);
}

/* timeout_ms < 0: wait forever; 0: check once; > 0: wait up to that long */
static int wait_owner(int fd, struct urb_owner *o, int timeout_ms)
{
  long long deadline = timeout_ms > 0 ? now_ms() + timeout_ms : 0;

  for (;;) {
    struct pollfd pfd;
    int slice = 10;

    reap_completed(fd);
    if (__atomic_load_n(&o->done, __ATOMIC_ACQUIRE))
      return 0;
    if (timeout_ms == 0)
      return -ETIMEDOUT;
    if (timeout_ms > 0) {
      long long left = deadline - now_ms();
      if (left <= 0)
        return -ETIMEDOUT;
      if (left < slice)
        slice = (int)left;
    }
    pfd.fd = fd;
    pfd.events = POLLOUT;
    pfd.revents = 0;
    poll(&pfd, 1, slice);
  }
}

/* discard a pending URB and wait for its (cancelled) completion */
static void discard_owner(int fd, struct urb_owner *o)
{
  if (ioctl(fd, IOCTL_USB_DISCARDURB, &o->urb) < 0 && errno != EINVAL && usb_debug >= 1)
    fprintf(stderr, "libusb0: error discarding URB: %s\n", strerror(errno));
  wait_owner(fd, o, 2000);
}

static void owner_init(struct urb_owner *o, int urbtype, int ep, char *bytes, int size)
{
  memset(o, 0, sizeof(*o));
  o->urb.type = urbtype;
  o->urb.endpoint = ep;
  o->urb.buffer = bytes;
  o->urb.buffer_length = size;
  o->urb.usercontext = o;
}

/* Reading and writing are the same except for the endpoint */
static int usb_urb_transfer(usb_dev_handle *dev, int ep, int urbtype,
	char *bytes, int size, int timeout)
{
  int bytesdone = 0;

  do {
    struct urb_owner o;
    int requested = size - bytesdone, ret;

    if (requested > MAX_READ_WRITE)
      requested = MAX_READ_WRITE;
    owner_init(&o, urbtype, ep, bytes + bytesdone, requested);

    if (ioctl(dev->fd, IOCTL_USB_SUBMITURB, &o.urb) < 0)
      USB_ERROR_STR(-errno, "error submitting URB: %s", strerror(errno));

    ret = wait_owner(dev->fd, &o, timeout > 0 ? timeout : -1);
    if (ret == -ETIMEDOUT) {
      discard_owner(dev->fd, &o);
      if (bytesdone + o.urb.actual_length > 0 && o.urb.actual_length > 0)
        return bytesdone + o.urb.actual_length;
      USB_ERROR_STR(-ETIMEDOUT, "transfer timed out after %d ms", timeout);
    }
    if (o.urb.status < 0)
      USB_ERROR_STR(o.urb.status, "URB failed: %s", strerror(-o.urb.status));

    bytesdone += o.urb.actual_length;
    if (o.urb.actual_length < requested)
      break;
  } while (bytesdone < size);

  return bytesdone;
}

int usb_bulk_write(usb_dev_handle *dev, int ep, char *bytes, int size,
	int timeout)
{
  /* Ensure the endpoint address is correct */
  return usb_urb_transfer(dev, ep, USB_URB_TYPE_BULK, bytes, size,
		timeout);
}

int usb_bulk_read(usb_dev_handle *dev, int ep, char *bytes, int size,
	int timeout)
{
  /* Ensure the endpoint address is correct */
  ep |= USB_ENDPOINT_IN;
  return usb_urb_transfer(dev, ep, USB_URB_TYPE_BULK, bytes, size,
		timeout);
}

/*
 * FIXME: Packetize large buffers here. 2.4 HCDs (atleast, haven't checked
 * 2.5 HCDs yet) don't handle multi-packet Interrupt transfers. So we need
 * to lookup the endpoint packet size and packetize appropriately here.
 */
int usb_interrupt_write(usb_dev_handle *dev, int ep, char *bytes, int size,
	int timeout)
{
  /* Ensure the endpoint address is correct */
  /* libusb-win32 lets interrupt calls drive bulk endpoints (ANT sticks do this);
   * usbfs rejects an INTERRUPT URB on a bulk endpoint but its BULK type adapts
   * to interrupt endpoints, so always submit BULK. */
  return usb_urb_transfer(dev, ep, USB_URB_TYPE_BULK, bytes, size,
		timeout);
}

int usb_interrupt_read(usb_dev_handle *dev, int ep, char *bytes, int size,
	int timeout)
{
  /* Ensure the endpoint address is correct */
  ep |= USB_ENDPOINT_IN;
  /* libusb-win32 lets interrupt calls drive bulk endpoints (ANT sticks do this);
   * usbfs rejects an INTERRUPT URB on a bulk endpoint but its BULK type adapts
   * to interrupt endpoints, so always submit BULK. */
  return usb_urb_transfer(dev, ep, USB_URB_TYPE_BULK, bytes, size,
		timeout);
}

int usb_os_find_busses(struct usb_bus **busses)
{
  struct usb_bus *fbus = NULL;
  DIR *dir;
  struct dirent *entry;

  dir = opendir(usb_path);
  if (!dir)
    USB_ERROR_STR(-errno, "couldn't opendir(%s): %s", usb_path,
	strerror(errno));

  while ((entry = readdir(dir)) != NULL) {
    struct usb_bus *bus;

    /* Skip anything starting with a . */
    if (entry->d_name[0] == '.')
      continue;

    if (!strchr("0123456789", entry->d_name[strlen(entry->d_name) - 1])) {
      if (usb_debug >= 2)
        fprintf(stderr, "usb_os_find_busses: Skipping non bus directory %s\n",
		entry->d_name);
      continue;
    }

    bus = malloc(sizeof(*bus));
    if (!bus)
      USB_ERROR(-ENOMEM);

    memset((void *)bus, 0, sizeof(*bus));

    strncpy(bus->dirname, entry->d_name, sizeof(bus->dirname) - 1);
    bus->dirname[sizeof(bus->dirname) - 1] = 0;

    LIST_ADD(fbus, bus);

    if (usb_debug >= 2)
       fprintf(stderr, "usb_os_find_busses: Found %s\n", bus->dirname);
  }

  closedir(dir);

  *busses = fbus;

  return 0;
}

int usb_os_find_devices(struct usb_bus *bus, struct usb_device **devices)
{
  struct usb_device *fdev = NULL;
  DIR *dir;
  struct dirent *entry;
  char dirpath[PATH_MAX + 1];

  snprintf(dirpath, PATH_MAX, "%s/%s", usb_path, bus->dirname);

  dir = opendir(dirpath);
  if (!dir)
    USB_ERROR_STR(-errno, "couldn't opendir(%s): %s", dirpath,
	strerror(errno));

  while ((entry = readdir(dir)) != NULL) {
    unsigned char device_desc[DEVICE_DESC_LENGTH];
    char filename[PATH_MAX + 1];
    struct usb_device *dev;
    struct usb_connectinfo connectinfo;
    int i, fd, ret;

    /* Skip anything starting with a . */
    if (entry->d_name[0] == '.')
      continue;

    dev = malloc(sizeof(*dev));
    if (!dev)
      USB_ERROR(-ENOMEM);

    memset((void *)dev, 0, sizeof(*dev));

    dev->bus = bus;

    strncpy(dev->filename, entry->d_name, sizeof(dev->filename) - 1);
    dev->filename[sizeof(dev->filename) - 1] = 0;

    snprintf(filename, sizeof(filename) - 1, "%s/%s", dirpath, entry->d_name);
    fd = open(filename, O_RDWR);
    if (fd < 0) {
      fd = open(filename, O_RDONLY);
      if (fd < 0) {
        if (usb_debug >= 2)
          fprintf(stderr, "usb_os_find_devices: Couldn't open %s\n",
                  filename);

        free(dev);
        continue;
      }
    }

    /* Get the device number */
    ret = ioctl(fd, IOCTL_USB_CONNECTINFO, &connectinfo);
    if (ret < 0) {
      if (usb_debug)
        fprintf(stderr, "usb_os_find_devices: couldn't get connect info\n");
    } else
      dev->devnum = connectinfo.devnum;

    ret = read(fd, (void *)device_desc, DEVICE_DESC_LENGTH);
    if (ret < 0) {
      if (usb_debug)
        fprintf(stderr, "usb_os_find_devices: Couldn't read descriptor\n");

      free(dev);

      goto err;
    }

    /*
     * Linux kernel converts the words in this descriptor to CPU endian, so
     * we use the undocumented W character for usb_parse_descriptor() that
     * doesn't convert endianess when parsing the descriptor
     */
    usb_parse_descriptor(device_desc, "bbWbbbbWWWbbbb", &dev->descriptor);

    LIST_ADD(fdev, dev);

    if (usb_debug >= 2)
      fprintf(stderr, "usb_os_find_devices: Found %s on %s\n",
		dev->filename, bus->dirname);

    /* Now try to fetch the rest of the descriptors */
    if (dev->descriptor.bNumConfigurations > USB_MAXCONFIG)
      /* Silent since we'll try again later */
      goto err;

    if (dev->descriptor.bNumConfigurations < 1)
      /* Silent since we'll try again later */
      goto err;

    dev->config = (struct usb_config_descriptor *)malloc(dev->descriptor.bNumConfigurations * sizeof(struct usb_config_descriptor));
    if (!dev->config)
      /* Silent since we'll try again later */
      goto err;

    memset(dev->config, 0, dev->descriptor.bNumConfigurations *
          sizeof(struct usb_config_descriptor));

    for (i = 0; i < dev->descriptor.bNumConfigurations; i++) {
      unsigned char buffer[8], *bigbuffer;
      struct usb_config_descriptor config;

      /* Get the first 8 bytes so we can figure out what the total length is */
      ret = read(fd, (void *)buffer, 8);
      if (ret < 8) {
        if (usb_debug >= 1) {
          if (ret < 0)
            fprintf(stderr, "Unable to get descriptor (%d)\n", ret);
          else
            fprintf(stderr, "Config descriptor too short (expected %d, got %d)\n", 8, ret);
        }

        goto err;
      }

      usb_parse_descriptor(buffer, "bbw", &config);

      bigbuffer = malloc(config.wTotalLength);
      if (!bigbuffer) {
        if (usb_debug >= 1)
          fprintf(stderr, "Unable to allocate memory for descriptors\n");
        goto err;
      }

      /* Read the rest of the config descriptor */
      memcpy(bigbuffer, buffer, 8);

      ret = read(fd, (void *)(bigbuffer + 8), config.wTotalLength - 8);
      if (ret < config.wTotalLength - 8) {
        if (usb_debug >= 1) {
          if (ret < 0)
            fprintf(stderr, "Unable to get descriptor (%d)\n", ret);
          else
            fprintf(stderr, "Config descriptor too short (expected %d, got %d)\n", config.wTotalLength, ret);
        }

        free(bigbuffer);
        goto err;
      }

      ret = usb_parse_configuration(&dev->config[i], bigbuffer);
      if (usb_debug >= 2) {
        if (ret > 0)
          fprintf(stderr, "Descriptor data still left\n");
        else if (ret < 0)
          fprintf(stderr, "Unable to parse descriptors\n");
      }

      free(bigbuffer);
    }

err:
    close(fd);
  }

  closedir(dir);

  *devices = fdev;

  return 0;
}

int usb_os_determine_children(struct usb_bus *bus)
{
  struct usb_device *dev, *devices[256];
  struct usb_ioctl command;
  int ret, i, i1;

  /* Create a list of devices first */
  memset(devices, 0, sizeof(devices));
  for (dev = bus->devices; dev; dev = dev->next)
    if (dev->devnum)
      devices[dev->devnum] = dev;

  /* Now fetch the children for each device */
  for (dev = bus->devices; dev; dev = dev->next) {
    struct usb_hub_portinfo portinfo;
    int fd;

    fd = device_open(dev);
    if (fd < 0)
      continue;

    /* Query the hub driver for the children of this device */
    if (dev->config && dev->config->interface && dev->config->interface->altsetting)
      command.ifno = dev->config->interface->altsetting->bInterfaceNumber;
    else
      command.ifno = 0;
    command.ioctl_code = IOCTL_USB_HUB_PORTINFO;
    command.data = &portinfo;
    ret = ioctl(fd, IOCTL_USB_IOCTL, &command);
    if (ret < 0) {
      /* errno == ENOSYS means the device probably wasn't a hub */
      if (errno != ENOSYS && usb_debug > 1)
        fprintf(stderr, "error obtaining child information: %s\n",
		strerror(errno));

      close(fd);
      continue;
    }

    dev->num_children = 0;
    for (i = 0; i < portinfo.numports; i++)
      if (portinfo.port[i])
        dev->num_children++;

    /* Free any old children first */
    free(dev->children);

    dev->children = malloc(sizeof(struct usb_device *) * dev->num_children);
    if (!dev->children) {
      if (usb_debug > 1)
        fprintf(stderr, "error allocating %zu bytes memory for dev->children\n",
                sizeof(struct usb_device *) * dev->num_children);

      dev->num_children = 0;
      close(fd);
      continue;
    }

    for (i = 0, i1 = 0; i < portinfo.numports; i++) {
      if (!portinfo.port[i])
        continue;

      dev->children[i1++] = devices[portinfo.port[i]];

      devices[portinfo.port[i]] = NULL;
    }

    close(fd);
  }

  /*
   * There should be one device left in the devices list and that should be
   * the root device
   */
  for (i = 0; i < sizeof(devices) / sizeof(devices[0]); i++) {
    if (devices[i])
      bus->root_dev = devices[i];
  }

  return 0;
}

static int check_usb_vfs(const char *dirname)
{
  DIR *dir;
  struct dirent *entry;
  int found = 0;

  dir = opendir(dirname);
  if (!dir)
    return 0;

  while ((entry = readdir(dir)) != NULL) {
    /* Skip anything starting with a . */
    if (entry->d_name[0] == '.')
      continue;

    /* We assume if we find any files that it must be the right place */
    found = 1;
    break;
  }

  closedir(dir);

  return found;
}

void usb_os_init(void)
{
  /* Find the path to the virtual filesystem */
  if (getenv("USB_DEVFS_PATH")) {
    if (check_usb_vfs(getenv("USB_DEVFS_PATH"))) {
      strncpy(usb_path, getenv("USB_DEVFS_PATH"), sizeof(usb_path) - 1);
      usb_path[sizeof(usb_path) - 1] = 0;
    } else if (usb_debug)
      fprintf(stderr, "usb_os_init: couldn't find USB VFS in USB_DEVFS_PATH\n");
  }

  if (!usb_path[0]) {
    if (check_usb_vfs("/dev/bus/usb")) {
      strncpy(usb_path, "/dev/bus/usb", sizeof(usb_path) - 1);
      usb_path[sizeof(usb_path) - 1] = 0;
    } else if (check_usb_vfs("/proc/bus/usb")) {
      strncpy(usb_path, "/proc/bus/usb", sizeof(usb_path) - 1);
      usb_path[sizeof(usb_path) - 1] = 0;
    } else
      usb_path[0] = 0;	/* No path, no USB support */
  }

  if (usb_debug) {
    if (usb_path[0])
      fprintf(stderr, "usb_os_init: Found USB VFS at %s\n", usb_path);
    else
      fprintf(stderr, "usb_os_init: No USB VFS found, is it mounted?\n");
  }
}

int usb_resetep(usb_dev_handle *dev, unsigned int ep)
{
  int ret;

  ret = ioctl(dev->fd, IOCTL_USB_RESETEP, &ep);
  if (ret)
    USB_ERROR_STR(-errno, "could not reset ep %d: %s", ep,
    	strerror(errno));

  return 0;
}

int usb_clear_halt(usb_dev_handle *dev, unsigned int ep)
{
  int ret;

  ret = ioctl(dev->fd, IOCTL_USB_CLEAR_HALT, &ep);
  if (ret)
    USB_ERROR_STR(-errno, "could not clear/halt ep %d: %s", ep,
    	strerror(errno));

  return 0;
}

int usb_reset(usb_dev_handle *dev)
{
  int ret;

  ret = ioctl(dev->fd, IOCTL_USB_RESET, NULL);
  if (ret)
     USB_ERROR_STR(-errno, "could not reset: %s", strerror(errno));

  return 0;
}

int usb_get_driver_np(usb_dev_handle *dev, int interface, char *name,
	unsigned int namelen)
{
  struct usb_getdriver getdrv;
  int ret;

  getdrv.interface = interface;
  ret = ioctl(dev->fd, IOCTL_USB_GETDRIVER, &getdrv);
  if (ret)
    USB_ERROR_STR(-errno, "could not get bound driver: %s", strerror(errno));

  strncpy(name, getdrv.driver, namelen - 1);
  name[namelen - 1] = 0;

  return 0;
}

int usb_detach_kernel_driver_np(usb_dev_handle *dev, int interface)
{
  struct usb_ioctl command;
  int ret;

  command.ifno = interface;
  command.ioctl_code = IOCTL_USB_DISCONNECT;
  command.data = NULL;

  ret = ioctl(dev->fd, IOCTL_USB_IOCTL, &command);
  if (ret)
    USB_ERROR_STR(-errno, "could not detach kernel driver from interface %d: %s",
        interface, strerror(errno));

  return 0;
}


// -------------------------------------------------------------------------------
// libusb-win32 async API on top of the completion dispatcher above.
// Semantics follow libusb-win32: usb_reap_async*() wait at most `timeout` ms and
// return -ETIMEDOUT (-116) if the request is still pending; usb_reap_async()
// then cancels it, usb_reap_async_nocancel() leaves it running.

typedef struct {
	struct urb_owner o;
	usb_dev_handle *dev;
	int submitted;
} usb_context_t;

static int _usb_setup_async(usb_dev_handle *dev, void **context,
                            int urbtype, unsigned char ep)
{
	usb_context_t *c = calloc(1, sizeof(*c));

	if (!c)
		USB_ERROR_STR(-ENOMEM, "memory allocation error: %s", strerror(ENOMEM));
	c->dev = dev;
	owner_init(&c->o, urbtype, ep, NULL, 0);
	*context = c;
	return 0;
}

int usb_bulk_setup_async(usb_dev_handle *dev, void **context, unsigned char ep)
{
	return _usb_setup_async(dev, context, USB_URB_TYPE_BULK, ep);
}

int usb_submit_async(void *context, char *bytes, int size)
{
	usb_context_t *c = (usb_context_t *)context;

	if (!c)
		return -EINVAL;
	if (c->submitted)
		USB_ERROR_STR(-EBUSY, "request already pending%s", "");
	owner_init(&c->o, c->o.urb.type, c->o.urb.endpoint, bytes, size);
	if (ioctl(c->dev->fd, IOCTL_USB_SUBMITURB, &c->o.urb) < 0)
		USB_ERROR_STR(-errno, "error submitting URB: %s", strerror(errno));
	c->submitted = 1;
	return 0;
}

static int _usb_reap_async(void *context, int timeout, int cancel)
{
	usb_context_t *c = (usb_context_t *)context;

	if (!c || !c->submitted)
		return -EINVAL;
	if (wait_owner(c->dev->fd, &c->o, timeout) == -ETIMEDOUT) {
		if (!cancel)
			return -ETIMEDOUT;
		discard_owner(c->dev->fd, &c->o);
		c->submitted = 0;
		return -ETIMEDOUT;
	}
	c->submitted = 0;
	if (c->o.urb.status < 0 && c->o.urb.actual_length == 0)
		return c->o.urb.status;
	return c->o.urb.actual_length;
}

int usb_reap_async(void *context, int timeout)
{
	return _usb_reap_async(context, timeout, 1);
}

int usb_reap_async_nocancel(void *context, int timeout)
{
	return _usb_reap_async(context, timeout, 0);
}

int usb_cancel_async(void *context)
{
	usb_context_t *c = (usb_context_t *)context;

	if (!c)
		return -EINVAL;
	if (c->submitted) {
		discard_owner(c->dev->fd, &c->o);
		c->submitted = 0;
	}
	return 0;
}

int usb_free_async(void **context)
{
	usb_context_t *c;

	if (!context || !*context)
		USB_ERROR_STR(-EINVAL, "invalid context%s", "");
	c = (usb_context_t *)*context;
	if (c->submitted)
		usb_cancel_async(c);
	free(c);
	*context = NULL;
	return 0;
}
