#!/usr/bin/env python3
"""Log what BlueZ sees for one Bluetooth LE sensor during a Zwift ride. Needs no root.

    ble-watch.py AA:BB:CC:DD:EE:FF [logfile]

Start it before Zwift and stop it with Ctrl-C after the ride. It only listens to BlueZ's
D-Bus signals and never talks to the device, so it cannot disturb the connection. It records
connection changes, BlueZ's disconnect reason, notification start/stop, and any gap of more
than 5 seconds between heart-rate notifications.
"""
import sys, time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

if len(sys.argv) < 2:
    sys.exit("usage: ble-watch.py AA:BB:CC:DD:EE:FF [logfile]  (the sensor's address, see bluetoothctl devices)")
mac = sys.argv[1].upper()
logfile = open(sys.argv[2] if len(sys.argv) > 2 else "ble-watch.log", "a", buffering=1)
dev = "dev_" + mac.replace(":", "_")
GAP = 5.0
last_value = None
values = 0


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line)
    logfile.write(line + "\n")


def on_signal(_conn, _sender, path, iface, member, params, *_):
    global last_value, values
    args = params.unpack()
    if member == "PropertiesChanged" and args[0] == "org.bluez.Adapter1":
        if "Discovering" in args[1]:
            log(f"adapter Discovering={args[1]['Discovering']}")
        return
    if dev not in path and not (member in ("InterfacesAdded", "InterfacesRemoved") and dev in str(args[0])):
        return
    if member != "PropertiesChanged":
        log(f"{member}: {args}")
        return
    props, short = args[1], path.split(dev)[-1] or "/"
    if "Value" in props:
        now = time.monotonic()
        if last_value is not None and now - last_value > GAP:
            log(f"GAP: no notification for {now - last_value:.1f}s on {short}")
        last_value = now
        values += 1
    for key in sorted(set(props) - {"Value", "RSSI", "ManufacturerData", "ServiceData", "TxPower"}):
        log(f"{short} {key}={props[key]}")


bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
bus.signal_subscribe("org.bluez", None, None, None, None, Gio.DBusSignalFlags.NONE, on_signal)
log(f"watching {mac}")
loop = GLib.MainLoop()
try:
    loop.run()
except KeyboardInterrupt:
    log(f"stopped, {values} notifications seen")
