# After Magisk + LindroidUI (stock Lineage)

See [install-magisk.md](install-magisk.md) for flash order.

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

Use Lindroid display; set `WAYLAND_DISPLAY` as provided by create-disp / KWin.

## Soft reboot / casefold

Telegram pin: https://t.me/linux_on_droid  
SELinux: `setenforce 0` until sepolicy lands in the Magisk module.
