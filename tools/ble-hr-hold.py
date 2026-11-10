#!/usr/bin/env python3
"""Keep heart-rate notifications switched on for any connected Bluetooth LE sensor.

Wine's first request to enable heart-rate notifications can fail with ATT error 0x0e, and Zwift
does not retry, so it shows the sensor as connected with no signal. While this helper holds
its own subscription, BlueZ answers later subscribers without another request to the sensor.

Start it before pairing in Zwift and leave it running. It never connects or disconnects anything.
"""
import time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

HR = "00002a37-0000-1000-8000-00805f9b34fb"
CHAR = "org.bluez.GattCharacteristic1"
DEV = "org.bluez.Device1"
bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
held = set()


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


def scan(*_):
    objs = bus.call_sync("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
                         None, None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    for path, ifaces in objs.items():
        char = ifaces.get(CHAR)
        if not char or char.get("UUID") != HR:
            continue
        dev = objs.get(char_device(path), {}).get(DEV, {})
        if not (dev.get("Connected") and dev.get("ServicesResolved")):
            if path in held:
                held.discard(path)
                log(f"released {path}")
            continue
        if path in held:
            continue
        try:
            bus.call_sync("org.bluez", path, CHAR, "StartNotify", None, None, Gio.DBusCallFlags.NONE, 8000, None)
            held.add(path)
            log(f"holding {dev.get('Name', '?')} {path}")
        except GLib.Error as err:
            log(f"StartNotify failed, retrying: {err.message}")
    held.intersection_update(p for p in objs if CHAR in objs[p])
    return True


def char_device(path):
    return "/".join(path.split("/")[:5])


def on_signal(_c, _s, path, _i, member, params, *_):
    args = params.unpack()
    if member == "PropertiesChanged" and args[0] == DEV and ("ServicesResolved" in args[1] or "Connected" in args[1]):
        scan()


bus.signal_subscribe("org.bluez", None, None, None, None, Gio.DBusSignalFlags.NONE, on_signal)
log("waiting for a connected heart-rate sensor")
GLib.timeout_add(500, scan)
scan()
GLib.MainLoop().run()
