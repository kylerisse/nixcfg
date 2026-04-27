#!/usr/bin/env python3
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("XApp", "1.0")

from gi.repository import GLib, Gio, Gtk, XApp  # noqa: E402

BUS_NAME = "org.gnome.SessionManager"
OBJ_PATH = "/org/gnome/SessionManager"
SM_IFACE = "org.gnome.SessionManager"
INH_IFACE = "org.gnome.SessionManager.Inhibitor"

STALE_AFTER_SECONDS = 300

ICON_IDLE = "emblem-default-symbolic"
ICON_ACTIVE = "emblem-synchronizing-symbolic"
ICON_STALE = "emblem-important-symbolic"


def now_us():
    return GLib.get_real_time()


class InhibitorsTray:
    def __init__(self):
        self.inhibitors = {}
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        self.icon = XApp.StatusIcon.new()
        self.icon.set_name("sdl-ss-inhibitors-tray")
        self.icon.set_icon_name(ICON_IDLE)
        self.icon.set_tooltip_text("No inhibitors")

        self.menu = Gtk.Menu()
        self.icon.set_primary_menu(self.menu)
        self.icon.connect("button-release-event", self._on_button_release)

        self.bus.signal_subscribe(
            BUS_NAME,
            SM_IFACE,
            "InhibitorAdded",
            OBJ_PATH,
            None,
            Gio.DBusSignalFlags.NONE,
            self._on_added,
        )
        self.bus.signal_subscribe(
            BUS_NAME,
            SM_IFACE,
            "InhibitorRemoved",
            OBJ_PATH,
            None,
            Gio.DBusSignalFlags.NONE,
            self._on_removed,
        )

        self._load_existing()
        self._refresh()
        GLib.timeout_add_seconds(30, self._tick)

    def _call(self, path, iface, method):
        try:
            return self.bus.call_sync(
                BUS_NAME,
                path,
                iface,
                method,
                None,
                None,
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            ).unpack()
        except GLib.Error:
            return None

    def _load_existing(self):
        result = self._call(OBJ_PATH, SM_IFACE, "GetInhibitors")
        if result is None:
            return
        for path in result[0]:
            self._add(path)

    def _repoll(self):
        # Reconcile local state against the bus. Preserves added_at_us for
        # entries we already knew about so the age display stays accurate.
        result = self._call(OBJ_PATH, SM_IFACE, "GetInhibitors")
        if result is None:
            return
        live_paths = set(result[0])
        for stale in set(self.inhibitors) - live_paths:
            self.inhibitors.pop(stale, None)
        for path in live_paths - set(self.inhibitors):
            self._add(path)

    def _add(self, path):
        if path in self.inhibitors:
            return
        app = self._call(path, INH_IFACE, "GetAppId")
        reason = self._call(path, INH_IFACE, "GetReason")
        flags = self._call(path, INH_IFACE, "GetFlags")
        self.inhibitors[path] = {
            "app": app[0] if app else "(unknown)",
            "reason": reason[0] if reason else "(unknown)",
            "flags": flags[0] if flags else 0,
            "added_at_us": now_us(),
        }

    def _on_added(self, _bus, _sender, _path, _iface, _signal, params):
        added_path = params.unpack()[0]
        self._add(added_path)
        self._refresh()

    def _on_removed(self, _bus, _sender, _path, _iface, _signal, params):
        removed_path = params.unpack()[0]
        self.inhibitors.pop(removed_path, None)
        self._refresh()

    def _tick(self):
        # Periodic reconcile guards against missed signals (startup races,
        # bus hiccups). Cheap — one dbus call per tick.
        self._repoll()
        self._refresh()
        return True

    def _on_button_release(self, _icon, _x, _y, button, _time, _position_type):
        if button == 3:
            self._repoll()
            self._refresh()

    def _max_age_seconds(self):
        if not self.inhibitors:
            return 0
        oldest = min(info["added_at_us"] for info in self.inhibitors.values())
        return (now_us() - oldest) // 1_000_000

    def _refresh(self):
        n = len(self.inhibitors)
        if n == 0:
            self.icon.set_icon_name(ICON_IDLE)
            self.icon.set_tooltip_text("No inhibitors")
            self.icon.set_label("")
        else:
            age = self._max_age_seconds()
            stale = age >= STALE_AFTER_SECONDS
            self.icon.set_icon_name(ICON_STALE if stale else ICON_ACTIVE)
            self.icon.set_label(str(n))
            tooltip_lines = [
                f"{n} inhibitor(s){' — STALE' if stale else ''}:",
            ]
            for info in self.inhibitors.values():
                tooltip_lines.append(f"  {info['app']}: {info['reason']}")
            self.icon.set_tooltip_text("\n".join(tooltip_lines))

        self._rebuild_menu()

    def _rebuild_menu(self):
        for child in self.menu.get_children():
            self.menu.remove(child)

        if not self.inhibitors:
            item = Gtk.MenuItem(label="No active inhibitors")
            item.set_sensitive(False)
            self.menu.append(item)
        else:
            for info in self.inhibitors.values():
                age_s = (now_us() - info["added_at_us"]) // 1_000_000
                label = f"{info['app']}: {info['reason']}  ({age_s}s)"
                item = Gtk.MenuItem(label=label)
                item.set_sensitive(False)
                self.menu.append(item)

        self.menu.append(Gtk.SeparatorMenuItem())
        refresh_item = Gtk.MenuItem(label="Refresh now")
        refresh_item.connect("activate", lambda _: (self._repoll(), self._refresh()))
        self.menu.append(refresh_item)
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda _: Gtk.main_quit())
        self.menu.append(quit_item)
        self.menu.show_all()


def main():
    InhibitorsTray()
    try:
        Gtk.main()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
