# IP Forwarding with Tailscale

Turn an **Orange Pi Zero 3** into a Tailscale subnet router so you can reach devices on your local network (for example, a Raspberry Pi web server) from anywhere.

```
 Laptop (Tailscale)                Orange Pi Zero 3                 LAN device
 100.x.x.x  ──────────────────▶   subnet router   ──────────────────▶  192.168.1.40
             Tailscale tunnel      tailscale0 / eth0                   web server
```

## Features

- Install from a **single executable file** (no clone required).
- Enable or disable IPv4 forwarding with one command.
- Automatically detects the LAN interface that matches `LAN_SUBNET`.
- Adds the required `iptables` forwarding and NAT (`MASQUERADE`) rules.
- Advertises the LAN subnet through Tailscale.
- Runs as a `systemd` service and survives reboots.
- Built-in `status` and `test` commands for troubleshooting.

## Requirements

| Requirement | Details |
| --- | --- |
| Hardware | Orange Pi Zero 3 (or any Linux machine with `systemd`) |
| OS | Linux with `systemd`, `iptables`, `iproute2`, and `sysctl` |
| Tailscale | Installed, authenticated, and connected |
| Access | Root privileges (`sudo`) |
| Network | Orange Pi and target device connected to the same LAN subnet |

## Quick Start

```bash
# 1. Download the single-file installer
curl -fsSLO https://github.com/0xBitmask/IP-Forwarding/releases/latest/download/ip-forwarding
chmod +x ip-forwarding

# 2. Install
sudo ./ip-forwarding install

# 3. Configure
sudo nano /opt/ip_forwarding/config.conf

# 4. Test and advertise
sudo ip-forwarding test
sudo ip-forwarding advertise

# 5. Enable at boot
sudo systemctl enable --now ip-forwarding
```

Then approve the advertised route in the [Tailscale admin console](https://login.tailscale.com/admin/machines) and run this on your laptop:

```bash
sudo tailscale up --accept-routes
```

## Installation

### Option 1 — Prebuilt executable (recommended)

Download [`ip-forwarding`](https://github.com/0xBitmask/IP-Forwarding/releases/latest/download/ip-forwarding) from the latest release, then:

```bash
chmod +x ip-forwarding
sudo ./ip-forwarding install
```

The installer:

- Copies the scripts to `/opt/ip_forwarding`.
- Creates `/opt/ip_forwarding/config.conf` (existing config is preserved on reinstall).
- Installs the `systemd` service.
- Creates the `ip-forwarding` command in `/usr/local/bin`.
- Enables kernel IP forwarding persistently.

Verify the checksum before installing (optional):

```bash
curl -fsSLO https://github.com/0xBitmask/IP-Forwarding/releases/latest/download/ip-forwarding.sha256
sha256sum -c ip-forwarding.sha256
```

### Option 2 — Build the executable yourself

The build script embeds all files into one portable shell executable:

```bash
git clone https://github.com/0xBitmask/IP-Forwarding.git
cd IP-Forwarding
./build.sh
sudo ./dist/ip-forwarding install
```

Output:

```text
dist/ip-forwarding
dist/ip-forwarding.sha256
```

Use a custom version if needed:

```bash
VERSION=1.2.3 ./build.sh
```

> **Why a shell executable instead of a compiled binary?**
> A native binary is tied to one CPU architecture (the Orange Pi Zero 3 is
> ARM64). The generated file is a self-contained shell executable that works on
> ARM, x86, and other Linux systems, as long as `bash` and standard utilities
> are available.

### Option 3 — Install directly from source

```bash
git clone https://github.com/0xBitmask/IP-Forwarding.git
cd IP-Forwarding
nano config.conf          # set LAN_SUBNET and TARGET_SERVER
sudo ./install.sh
```

### Finish the setup

After any installation method, complete these steps:

1. **Edit the configuration**

   ```bash
   sudo nano /opt/ip_forwarding/config.conf
   ```

2. **Test connectivity from the Orange Pi**

   ```bash
   sudo ip-forwarding test
   ```

3. **Advertise the LAN subnet**

   ```bash
   sudo ip-forwarding advertise
   ```

4. **Approve the route**

   Open the [Tailscale admin console](https://login.tailscale.com/admin/machines)
   and approve the advertised route for the Orange Pi.

5. **Enable the service at boot**

   ```bash
   sudo systemctl enable --now ip-forwarding
   ```

6. **Accept routes on your laptop**

   ```bash
   sudo tailscale up --accept-routes
   ```

   Then open the target server in your browser:

   ```text
   http://192.168.1.40
   ```

## Configuration

The installed configuration lives at `/opt/ip_forwarding/config.conf`
([source](config.conf)).

| Variable | Default | Description |
| --- | --- | --- |
| `TAILSCALE_IF` | `tailscale0` | Tailscale network interface. |
| `LAN_IF` | *(empty)* | LAN interface (`eth0`, `wlan0`, ...). Leave empty for auto-detection. |
| `LAN_SUBNET` | `192.168.1.0/24` | Subnet of the local network to expose. |
| `TARGET_SERVER` | `192.168.1.40` | Device on the LAN you want to reach (for example, a Raspberry Pi). |
| `LOG_FILE` | `/var/log/ip_forwarding.log` | Log file used by the script. |

Example:

```bash
TAILSCALE_IF="tailscale0"
LAN_IF=""
LAN_SUBNET="192.168.1.0/24"
TARGET_SERVER="192.168.1.40"
LOG_FILE="/var/log/ip_forwarding.log"
```

After changing the configuration, restart the service:

```bash
sudo systemctl restart ip-forwarding
```

## Usage

```bash
sudo ip-forwarding <command>
```

| Command | Description |
| --- | --- |
| `install` | Install files, service, and command (run from the downloaded executable). |
| `uninstall` | Remove files, service, command, and forwarding rules. |
| `enable` | Enable forwarding and add the `iptables` rules. |
| `disable` | Remove the rules and disable forwarding. |
| `status` | Show kernel, interface, `iptables`, and Tailscale status. |
| `advertise` | Advertise `LAN_SUBNET` through Tailscale. |
| `test` | Test connectivity to `TARGET_SERVER` and show next steps. |
| `version` | Show the installed version. |
| `help` | Show usage information. |

Useful `systemd` commands:

```bash
sudo systemctl start ip-forwarding      # start now
sudo systemctl stop ip-forwarding       # stop now
sudo systemctl status ip-forwarding     # check service state
sudo systemctl enable ip-forwarding     # start automatically at boot
```

## How It Works

1. **Kernel forwarding** — `net.ipv4.ip_forward=1` lets the Orange Pi route packets between interfaces.
2. **Forwarding rules** — `iptables` accepts traffic between `tailscale0` and the LAN interface in both directions.
3. **NAT** — traffic from the Tailscale range `100.64.0.0/10` is masqueraded when leaving through the LAN interface.
4. **Route advertisement** — `tailscale up --advertise-routes=...` tells Tailscale clients how to reach the LAN subnet.

The `systemd` service runs `ip_forward.sh enable` on boot and
`ip_forward.sh disable` on shutdown.

## Releases

Pushing a version tag builds the executable automatically with GitHub Actions
and attaches it to a GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow produces:

- `ip-forwarding` — single-file installer and manager.
- `ip-forwarding.sha256` — checksum for verification.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| `ip-forwarding: command not found` | Reinstall to recreate `/usr/local/bin/ip-forwarding`, or use `/opt/ip_forwarding/ip_forward.sh`. |
| `Cannot find a network interface with IP in ...` | Make sure the Orange Pi has an IP in `LAN_SUBNET`, or set `LAN_IF` explicitly. |
| Ping to the target server fails | Confirm the target is powered on and reachable from the Orange Pi: `ping 192.168.1.40`. |
| Laptop cannot reach the target | Approve the route in the Tailscale admin console and run `sudo tailscale up --accept-routes` on the laptop. |
| Service fails to start | Check `sudo systemctl status ip-forwarding` and `journalctl -u ip-forwarding -e`. |
| Rules are missing | Run `sudo ip-forwarding status` and re-enable with `sudo ip-forwarding enable`. |

Logs are written to `/var/log/ip_forwarding.log`.

```bash
sudo tail -f /var/log/ip_forwarding.log
```

## Project Structure

```text
.
├── .github/workflows/
│   └── release.yml         # Build and publish the executable on tags
├── .gitignore              # Ignore dist/ and log files
├── build.sh                # Build dist/ip-forwarding
├── config.conf             # Network and target configuration
├── install.sh              # Install directly from source
├── ip_forward.sh           # Main enable/disable/status/advertise/test script
├── ip-forwarding.service   # systemd unit
├── uninstall.sh            # Remove installed files and rules
└── README.md
```

## Uninstall

```bash
sudo ip-forwarding uninstall
```

Or, if you installed from the repository:

```bash
sudo ./uninstall.sh
```

This stops and disables the service, removes the installed files, `sysctl`
configuration, and the `ip-forwarding` command, then reloads `systemd`.
