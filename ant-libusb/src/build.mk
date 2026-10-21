# libusb0.dll for Wine/Proton (x86_64): PE front-end + native Linux back-end.
#   make -f build.mk MINGW=x86_64-w64-mingw32- WINEBUILD=winebuild
MINGW     ?= x86_64-w64-mingw32-
WINEBUILD ?= winebuild
CC_UNIX   ?= cc
OUT       ?= ../build
UNIX_SRC   = unixlib.c linux.c usb.c descriptors.c error.c

all: $(OUT)/x86_64-windows/libusb0.dll $(OUT)/x86_64-unix/libusb0.so $(OUT)/placeholder/libusb0.dll

$(OUT)/x86_64-windows/libusb0.dll: libusb0_pe.c calls.h
	mkdir -p $(@D)
	$(MINGW)gcc -O2 -Wall -shared -o $@ libusb0_pe.c -Wl,--kill-at -static-libgcc
	$(WINEBUILD) --builtin $@

$(OUT)/x86_64-unix/libusb0.so: $(UNIX_SRC) calls.h usb.h
	mkdir -p $(@D)
	$(CC_UNIX) -O2 -Wall -fPIC -shared -fvisibility=hidden -Wno-format-truncation -o $@ $(UNIX_SRC)

$(OUT)/placeholder/libusb0.dll: libusb0.spec
	mkdir -p $(@D)
	$(WINEBUILD) -m64 --dll --fake-module -E libusb0.spec -o $@

clean:
	rm -rf $(OUT)
.PHONY: all clean
