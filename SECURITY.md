# Security policy

zwift-linux is a set of shell scripts and small helper binaries that install and run Zwift's
Windows app under Wine/Proton. The installer runs as your user, asks for `sudo` only to add udev
rules, an AppArmor profile and to start `bluetooth.service`, and handles your Zwift sign-in
(`share/zwift-auth.py`). Bugs in those parts can matter, so please report them privately.

## Reporting a vulnerability

Please **don't open a public issue** for a security problem.

Use GitHub's private reporting instead: go to the repository's **Security** tab and choose
**Report a vulnerability** (<https://github.com/Gititwhileitshott/zwift-linux/security/advisories/new>).
Include what you found, the steps to reproduce it, and the commit or release you tested.

You should hear back within 7 days. Once a fix is out, the advisory is published and you're
credited unless you'd rather not be.

Problems in Zwift itself, Wine, Proton/GE-Proton or umu-launcher belong to those projects; if
you're unsure, report it here and it will be passed on.

## Supported versions

Only the latest commit on `main` gets fixes.

## What's in scope

- `install.sh`, `uninstall.sh`, the scripts in `share/` and `ant-libusb/ant-test.sh`
  (anything that runs commands, writes files, or uses `sudo`)
- How Zwift credentials and tokens are handled (`share/zwift-auth.py`, `tools/record-login.py`)
- The prebuilt binaries: `zwift-start/LinuxZwiftLauncher.exe` and the `ant-libusb` bridge
  (`build/*/libusb0.*`, `test/antprobe.exe`)
- Downloads the installer makes and how it verifies them

## How downloads and binaries are verified

- **umu-launcher** and **GE-Proton** are downloaded over HTTPS and checked against a pinned
  SHA-256 (umu) or the release's SHA-512 file (GE-Proton) before they're unpacked.
- The **Wine build** that `ant-libusb/ant-test.sh` downloads is checked against a pinned SHA-256.
- **ZwiftSetup.exe** comes straight from Zwift's CDN over HTTPS. It changes with every Zwift
  release, so it can't be pinned here.
- The **prebuilt binaries in this repository** are listed in `zwift-start/SHA256SUMS` and
  `ant-libusb/SHA256SUMS`. `install.sh` refuses to install them if they don't match, and CI
  fails if a binary is committed without a checksum. To verify by hand:

      (cd zwift-start && sha256sum -c SHA256SUMS)
      (cd ant-libusb && sha256sum -c SHA256SUMS)

  If you'd rather not run prebuilt code, build them yourself: `./install.sh --build-starter`
  compiles `LinuxZwiftLauncher.exe` from `zwift-start/zwift-start.c`, and `ant-libusb/README.md`
  explains how to rebuild the bridge from `ant-libusb/src`.
