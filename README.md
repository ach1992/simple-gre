# Simple Gre (GRE Tunnel Manager) — Multi Tunnel

A simple **menu-driven** Bash script to create and manage **multiple GRE tunnels** between servers (Debian/Ubuntu, systemd).

---

## What’s New (Multi‑Tunnel)

- ✅ **Multiple tunnels** on the same server (e.g., Iran hub → many Kharej servers)
- ✅ Per-tunnel configs:
  - `/etc/simple-gre/tunnels.d/<TUN_NAME>.conf`
- ✅ systemd **template service** per tunnel:
  - `simple-gre@<TUN_NAME>.service` (example: `simple-gre@gre2.service`)
- ✅ Safe upgrades: manager **always refreshes** systemd unit + up/down scripts to avoid stale/legacy files
- ✅ Auto-picks a free tunnel name:
  - If `gre1` already exists and you press Enter, it will select `gre2`, `gre3`, ...

---

## Features

- ✅ Interactive **menu**
  - Create / Edit / Status (one) / Status (all) / Info (COPY BLOCK) / List / Delete
- ✅ Works on **Debian / Ubuntu** (systemd)
- ✅ One-command install
- ✅ Auto generates a **PAIR CODE** (`10.X.Y`) and uses a clean `/30` tunnel IP plan
- ✅ Generates a **COPY BLOCK** to paste on the other server
- ✅ Paste workflow is safe:
  - Paste the block
  - Press **Enter twice** to finish
- ✅ Fixes common GRE issue automatically: **rp_filter** (and persists it)
- ✅ Optional: enables **IPv4 forwarding** (per tunnel config; persisted globally if any tunnel needs it)

---

## Requirements

- Debian / Ubuntu
- Root access
- Servers with **public IPv4**
- GRE must be allowed between servers (**IP protocol 47**)

> If your provider blocks GRE protocol 47, the tunnel will not work.

---

## Install & Run

There are **two supported** install modes:

### 1) Online install / update (recommended)

Use this when you want to **download the latest** installer and manager from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/ach1992/simple-gre/main/install.sh | sudo bash
sudo simple-gre
```

### 2) Offline / local install (no internet)

Use this when you already have the files locally (copied to the server).

**Folder structure**
```text
simple-gre/
├─ install.sh
├─ gre_manager.sh
└─ README.md
```

**Install**
```bash
sudo bash install.sh
sudo simple-gre
```

### Local file detected prompt (Local vs Download Latest)

If `gre_manager.sh` exists next to `install.sh`, the installer will ask:

- `[1] Use local file (offline)`
- `[2] Download latest version (online)`

Default is **[1] offline** (press Enter).

> If you run via `curl | sudo bash`, the installer runs in **online mode** automatically.

---

## What gets installed / where files go

- Main command:
  - `/usr/local/bin/simple-gre`

- Backup copy (kept for convenience):
  - `/root/simple-gre/gre_manager.sh`
  - If `install.sh` was run from a local file, it is also copied to:
    - `/root/simple-gre/install.sh`

---

## Recommended Workflow (Iran Hub → Multiple Kharej)

### 1) On the Iran server (Source)

Create one tunnel per Kharej server:

1. Run:
   ```bash
   sudo simple-gre
   ```
2. Select:
   - `1) Create tunnel (new)`
   - `1) Source (Iran)`
3. When asked for tunnel name:
   - Press **Enter** to use default (`gre1`)
   - If `gre1` is already taken, it auto-selects `gre2`, `gre3`, ...
4. Fill values (press Enter to accept defaults where available).
5. At the end, the script prints a **COPY BLOCK** for **that tunnel**.

✅ Copy the full block (including header and footer lines), for example:

```text
----- SIMPLE_GRE_COPY_BLOCK -----
PAIR_CODE=10.211.240
SOURCE_PUBLIC_IP=1.2.3.4
DEST_PUBLIC_IP=5.6.7.8
TUN_NAME=gre2
MTU=1476
TTL=255
ENABLE_FORWARDING=yes
DISABLE_RPFILTER=yes
----- END_COPY_BLOCK -----
```

Repeat for each Kharej server (each time you’ll get a different `TUN_NAME` and a different PAIR CODE unless you paste a block back).

---

### 2) On each Kharej server (Destination)

For each Kharej server, create **only its own tunnel**:

1. Run:
   ```bash
   sudo simple-gre
   ```
2. Select:
   - `1) Create tunnel (new)`
   - `2) Destination (Kharej)`
3. When it asks for paste:
   - Paste the COPY BLOCK
   - Then press **Enter twice** on empty lines to finish pasting

The script will auto-fill most values.

---

## Menu Options

- **Create tunnel (new)**: Create and persist a GRE tunnel via `simple-gre@<tun>.service`
- **Edit tunnel**: Modify an existing tunnel configuration
- **Status (one tunnel)**: Full status (systemd + interface + ping)
- **Status (all tunnels)**: Quick view for all tunnels
- **Info / COPY BLOCK (one tunnel)**: Show config + COPY BLOCK for the selected tunnel
- **List tunnels**: List configured tunnels
- **Delete tunnel**: Remove tunnel + service instance + config

---

## Files & Services

### Configs (per tunnel)
- `/etc/simple-gre/tunnels.d/<TUN_NAME>.conf`

### Sysctl (persistent tuning)
- `/etc/simple-gre/99-simple-gre.conf`
  - Sets `net.ipv4.ip_forward` to `1` if **any** tunnel has forwarding enabled
  - Sets `rp_filter=0` for `all/default` and each tunnel interface if enabled

### systemd template service
- `/etc/systemd/system/simple-gre@.service`

### Service scripts
- `/usr/local/sbin/simple-gre-up`
- `/usr/local/sbin/simple-gre-down`

### Service naming examples
- `simple-gre@gre1.service`
- `simple-gre@gre2.service`

---

## Verify the Tunnel

From the **Source (Iran)** side, ping the remote tunnel IP shown in menu Status/Info:

```bash
ping -c 3 10.X.Y.2
```

From the **Destination (Kharej)** side:

```bash
ping -c 3 10.X.Y.1
```

Useful interface checks (replace `gre2` with your tunnel name):

```bash
ip -d link show gre2
ip -4 addr show dev gre2
ip -s link show gre2
```

systemd status:

```bash
systemctl status simple-gre@gre2.service --no-pager
```

---

## Troubleshooting

### 1) Ping fails but interface is UP

Most common reason is `rp_filter` (reverse path filtering).

Check:

```bash
sysctl net.ipv4.conf.gre2.rp_filter
```

It should be `0`.  
This project can set/persist it automatically when **Disable rp_filter** is `yes`.

### 2) GRE blocked by provider

GRE uses **IP protocol 47** (not TCP/UDP). Some providers block it.

You can test by observing proto 47 packets:

```bash
tcpdump -ni any proto 47
```

Then ping the tunnel IP from the other side.  
If nothing appears, GRE is blocked in the path/provider/firewall.

> `tcpdump` is optional and not installed by default in the minimal installer.

### 3) MTU issues

If you see packet loss under load, try lowering MTU (example):

- 1476 (default)
- 1450
- 1400

Edit the tunnel via menu and apply.

---

## Security Notes

- This tool only creates the GRE interface and assigns tunnel IPs.
- It does **not** automatically configure routing/NAT for additional subnets.
- If you plan to route traffic through the tunnel, you may need extra routing rules.

---

## License

MIT (or your preferred license)

---

## Contributing

PRs and issues are welcome.  
If you want extra features (routes, NAT helpers, health-check, multiple tunnels enhancements), open an issue.
