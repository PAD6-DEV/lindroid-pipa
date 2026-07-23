# Usage notes after flashing Lindroid on pipa
# Source: Lindroid Telegram pin / lindroid.org

## Attach

```bash
adb shell -t lxc_attach default -- "/bin/bash -c \"source /etc/profile && exec su - root\""
```

## Create container

```bash
adb shell -t lxc_create default -t lindroid -- -f /dev/fd/4
# user: lindroid
# pass: lindroid
```

## Logs (always share these when reporting issues)

| Where | Command |
|-------|---------|
| App / graphics | `adb logcat` |
| Kernel | `adb shell dmesg` |
| KWin / create-disp (in container) | `journalctl --no-pager --boot` |

## Apt overwrite

```bash
sudo apt-get -o Dpkg::Options::="--force-overwrite" …
```

## Manual KWin (XDG hack)

```bash
export XDG_RUNTIME_DIR=/tmp/runtime-lindroid
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
```

## Wayland apps

```bash
# with XDG hack:
EGL_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0 APP

# Plasma via DM:
XDG_RUNTIME_DIR=/run/user/1000 EGL_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0 APP
```

## Soft reboot (A14+) / casefold overlayfs

Temporary workarounds are only in the Lindroid Telegram pinned message:
https://t.me/linux_on_droid
