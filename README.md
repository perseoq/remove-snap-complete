
# Complete Snap Remover for Ubuntu

A robust, secure, and user-friendly Bash script to **completely remove Snap (snapd) and all snap packages** from Ubuntu (22.04, 24.04, and later versions). It also permanently blocks snapd from being reinstalled accidentally.

## Features

- ✅ **Complete removal** – deletes every snap package, snapd itself, and all snap-related directories.
- ✅ **Graceful fallback** – if `snap remove` fails, it stops snapd and wipes directories manually.
- ✅ **Permanent blocking** – uses `apt-mark hold` and an APT preferences file to prevent snapd from ever being installed again.
- ✅ **Safe by default** – does **not** remove `gnome-software` or `ubuntu-software` unless you use `--force`.
- ✅ **Backup option** – creates a backup of all snap configurations (can be skipped with `--no-backup`).
- ✅ **Full logging** – writes a detailed log to `/var/log/remove-snap-*.log`.
- ✅ **Systemd integration** – stops and disables all snap services before removal.
- ✅ **Loop device cleanup** – unmounts all loop devices mounted by snap.
- ✅ **Residual directory cleanup** – deletes `/snap`, `/var/snap`, `/var/lib/snapd`, and user snap directories.
- ✅ **APT source cleanup** – removes any snap-related APT repositories.

## Requirements

- **Ubuntu** (tested on 22.04, 24.04, and 24.10+).
- **Root privileges** (run with `sudo`).

## Installation

1. Download the script:

   ```bash
   wget https://raw.githubusercontent.com/your-repo/remove-snap-complete.sh
   ```

   or copy the script content into a file named `remove-snap-complete.sh`.

2. Make it executable:

   ```bash
   chmod +x remove-snap-complete.sh
   ```

## Usage

### Basic (safe) removal

```bash
sudo ./remove-snap-complete.sh
```

This will remove all snap packages, snapd, and block future installations, **without** deleting GNOME Software.

### Force mode (remove GNOME Software as well)

```bash
sudo ./remove-snap-complete.sh --force
```

⚠️ Also removes `gnome-software-plugin-snap`, `ubuntu-software`, and `ubuntu-software-plugin-snap`. After this, you can reinstall GNOME Software without snap support via `sudo apt install gnome-software`.

### Skip backup

```bash
sudo ./remove-snap-complete.sh --no-backup
```

Useful if you have no snap data you care about.

### Help

```bash
./remove-snap-complete.sh -h
```

## What the script does step by step

1. **Checks root and OS** – ensures run as root and on Ubuntu.
2. **Parses arguments** – respects `--force` and `--no-backup`.
3. **Creates backup** (optional) – copies `/var/lib/snapd`, `/var/snap`, and user snap directories.
4. **Stops snap services** – `snapd.service`, `snapd.socket`, `snapd.seeded.service`, etc.
5. **Lists installed snap packages** – stores them in a temporary file.
6. **Unmounts loop devices** – all `/dev/loop*` used by snap.
7. **Removes snap packages** – for each package tries `snap remove --purge`; if that fails, falls back to manual deletion of `/snap/<pkg>` and `/var/snap/<pkg>`.
8. **Purges snapd via APT** – `apt purge snapd` and related packages. In `--force` mode additionally purges GNOME Software snap plugin.
9. **Removes residual directories** – `/snap`, `/var/snap`, `/var/lib/snapd`, `/var/cache/snapd`, `/var/log/snapd`, `/tmp/snap-*`, `/root/snap`, `/home/*/snap`, and leftover systemd mount units.
10. **Blocks snapd reinstallation** – runs `apt-mark hold snapd` and creates `/etc/apt/preferences.d/snapd-block` with `Pin-Priority: -1`.
11. **Cleans APT sources** – removes any lines containing `snapcraft.io` or `snapd` from APT source files, then runs `apt update`.
12. **Verifies removal** – checks if `snap` command still exists, if any snap mounts remain, and if `snapd` appears in dpkg.
13. **Shows summary** – reports removed packages, locations of backup and log, and recommends a reboot.

## Logging

All output is saved to `/var/log/remove-snap-<timestamp>.log`. You can review it later:

```bash
less /var/log/remove-snap-*.log
```

## Important Notes

- **Reboot is strongly recommended** after running the script to release all loop devices and reload systemd.
- If you use **Firefox** as a snap, it will be removed. Install Firefox via APT or download from Mozilla.
- Some Ubuntu flavors (like Kubuntu, Xubuntu) may have fewer snap dependencies – the script handles this gracefully.
- The script is **idempotent** – running it multiple times will not cause errors.
- If you change your mind, you can restore snapd by removing the hold and the APT preferences file:
  ```bash
  sudo apt-mark unhold snapd
  sudo rm /etc/apt/preferences.d/snapd-block
  sudo apt install snapd
  ```

## License

MIT – feel free to use, modify, and distribute.

## Contributing

Pull requests and issues are welcome. Please ensure the script remains compatible with future Ubuntu releases.
