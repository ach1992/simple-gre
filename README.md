# Simple Gre (GRE Tunnel Manager)

A simple **menu-driven** Bash script to create and manage a **GRE tunnel** between two servers (Debian/Ubuntu).

Repo: https://github.com/ach1992/simple-gre

---

## Features

- ✅ Interactive **menu**: Create / Edit / Status / Info / Delete
- ✅ Works on **Debian / Ubuntu** (systemd)
- ✅ One-command install
- ✅ Auto generates a **PAIR CODE** (`10.X.Y`) and sets a clean `/30` tunnel IP plan
- ✅ Generates a **COPY BLOCK** to paste on the other server
- ✅ Paste workflow is safe:
  - Paste the block
  - Press **Enter twice** to finish
- ✅ Fixes common GRE issue automatically: **rp_filter** (and persists it)

---

## Requirements

- Debian / Ubuntu
- Root access
- Two servers with **public IPv4**
- GRE must be allowed between servers (**IP protocol 47**)

> If your provider blocks GRE protocol 47, the tunnel will not work.

---

## Quick Install

Run this on **both servers**:

```bash
curl -fsSL https://raw.githubusercontent.com/ach1992/simple-gre/main/install.sh | sudo bash
```

Run the manager:

```bash
sudo simple-gre
```

---

## How To Use (Recommended Workflow)

### 1) On the Source server (Iran)

1. Run:
   ```bash
   sudo simple-gre
   ```
2. Select:
   - `1) Create tunnel`
   - `1) Source (Iran)`
3. Fill values (press Enter to accept defaults where available).
4. At the end, the script prints a **COPY BLOCK**.

✅ Copy the full block (including the header and footer lines), for example:

```text
----- SIMPLE_GRE_COPY_BLOCK -----
PAIR_CODE=10.211.240
SOURCE_PUBLIC_IP=1.2.3.4
DEST_PUBLIC_IP=5.6.7.8
TUN_NAME=gre1
MTU=1476
TTL=255
ENABLE_FORWARDING=yes
DISABLE_RPFILTER=yes
----- END_COPY_BLOCK -----
```

---

### 2) On the Destination server (Abroad)

1. Run:
   ```bash
   sudo simple-gre
   ```
2. Select:
   - `1) Create tunnel`
   - `2) Destination (Abroad)`
3. When it asks for paste:
   - Paste the COPY BLOCK
   - Then press **Enter twice** on empty lines to finish pasting

The script will auto-fill most values.

---

## Menu Options

- **Create tunnel**: Create and persist GRE tunnel via systemd
- **Edit tunnel**: Modify existing configuration
- **Status**: Show service state, interface info, counters, and ping test
- **Info**: Print current config + COPY BLOCK
- **Delete**: Remove tunnel + service + config

---

## Files & Service

- Config:
  - `/etc/simple-gre/gre.conf`
- Sysctl (persistent tuning):
  - `/etc/simple-gre/99-simple-gre.conf`
- systemd service:
  - `simple-gre.service`
- Service scripts:
  - `/usr/local/sbin/simple-gre-up`
  - `/usr/local/sbin/simple-gre-down`

---

## Verify The Tunnel

From the Source server:

```bash
ping -c 3 10.X.Y.2
```

From the Destination server:

```bash
ping -c 3 10.X.Y.1
```

Also useful:

```bash
ip -d link show gre1
ip -4 addr show dev gre1
ip -s link show gre1
```

---

## Troubleshooting

### 1) Ping fails but interface is UP

The most common reason is `rp_filter` (reverse path filtering).

Check:

```bash
sysctl net.ipv4.conf.gre1.rp_filter
```

It should be `0`.  
This project automatically sets it to `0` and persists it.

### 2) GRE blocked by provider

GRE uses **IP protocol 47** (not TCP/UDP). Some providers block it.

Test with tcpdump:

On destination server:

```bash
tcpdump -ni any proto 47
```

Then ping the tunnel IP from the other side.  
If nothing appears, GRE is blocked in the path/provider/firewall.

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
If you want extra features (routes, NAT helpers, multiple tunnels, WireGuard fallback), open an issue.
