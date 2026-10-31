# LinuxZwiftLauncher.exe

A small Windows program (69 lines of C, `zwift-start.c`) that starts `ZwiftApp.exe` the way Zwift's own
launcher does: it reads the sign-in token that `zwift-auth.py` wrote, deletes that file, and starts the
game with `"ZwiftApp.exe" --launcher_version=<v> --token=<token JSON>`. It runs inside Wine, in the game
folder, and does nothing else: no network access, and the token file is the only file it touches.

Its name matters: ZwiftApp.exe only accepts a parent process whose path contains `ZwiftLauncher.exe`.

## Two ways to get it

**Prebuilt (default).** `install.sh` installs `LinuxZwiftLauncher.exe` from this folder. Its checksum is
in `SHA256SUMS`:

```bash
cd zwift-start && sha256sum -c SHA256SUMS
```

**Built from source.** Read `zwift-start.c`, then let the installer compile it for you:

```bash
./install.sh --build-starter        # or ZWIFT_BUILD_STARTER=1 ./install.sh
```

This needs the MinGW-w64 cross compiler (`x86_64-w64-mingw32-gcc`):

| Distro | Package |
| --- | --- |
| Arch / CachyOS / Manjaro | `mingw-w64-gcc` |
| Fedora | `mingw64-gcc` |
| Debian / Ubuntu | `gcc-mingw-w64-x86-64` |
| openSUSE | `mingw64-cross-gcc` |

Or build it by hand with the same command the installer uses:

```bash
x86_64-w64-mingw32-gcc -municode -O2 -s -Wl,--subsystem,windows -o LinuxZwiftLauncher.exe zwift-start.c
```

A build made with a different compiler version won't have the same checksum as the prebuilt file. That's
expected: compare the source, not the bytes. `-Wl,--subsystem,windows` makes it a GUI program, so Wine
opens no console window next to the game.
