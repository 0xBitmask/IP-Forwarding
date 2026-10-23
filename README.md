# IP Forwarding with Tailscale

Turn an **Orange Pi Zero 3** into a Tailscale subnet router so you can reach devices on your local network (for example, a Raspberry Pi web server) from anywhere.

```
 Laptop (Tailscale)                Orange Pi Zero 3                 LAN device
 100.x.x.x  ──────────────────▶   subnet router   ──────────────────▶  192.168.1.40
             Tailscale tunnel      tailscale0 / eth0                   web server
```

## Features

- Enable or disable IPv4 forwarding with a single command.
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

## Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/0xBitmask/IP-Forwarding.git
   cd IP-Forwarding
   ```

2. **Edit the configuration**

   ```bash
   nano config.conf
   ```

   At minimum, set `LAN_SUBNET` and `TARGET_SERVER`.

3. **Install**

   ```bash
   sudo ./install.sh
   ```

   The installer copies everything to `/opt/ip_forwarding`, registers the
   `systemd` service, and enables kernel IP forwarding persistently.

4. **Verify connectivity from the Orange Pi**

   ```bash
   sudo /opt/ip_forwarding/ip_forward.sh test
   ```

5. **Advertise the LAN subnet to Tailscale**

   ```bash
   sudo /opt/ip_forwarding/ip_forward.sh advertise
   ```

6. **Approve the route**

   Open the [Tailscale admin console](https://login.tailscale.com/admin/machines)
   and approve the advertised route for the Orange Pi.

7. **Enable the service at boot**

   ```bash
   sudo systemctl enable --now ip-forwarding
   ```

8. **Accept routes on your laptop**

   ```bash
   sudo tailscale up --accept-routes
   ```

   Then open the target server in your browser:

   ```text
   http://192.168.1.40
   ```

> **Tip:** If you edit `config.conf` after installing, edit the copy at
> `/opt/ip_forwarding/config.conf` and restart the service, or edit the repo
> copy and run `sudo ./install.sh` again.

## Configuration

All settings live in [`config.conf`](config.conf).

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

## Usage

```bash
sudo /opt/ip_forwarding/ip_forward.sh <command>
```

| Command | Description |
| --- | --- |
| `enable` | Enable forwarding and add the `iptables` rules. |
| `disable` | Remove the rules and disable forwarding. |
| `status` | Show kernel, interface, `iptables`, and Tailscale status. |
| `advertise` | Advertise `LAN_SUBNET` through Tailscale. |
| `test` | Test connectivity to `TARGET_SERVER` and show next steps. |

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

## Troubleshooting

| Problem | Solution |
| --- | --- |
| `Cannot find a network interface with IP in ...` | Make sure the Orange Pi has an IP in `LAN_SUBNET`, or set `LAN_IF` explicitly. |
| Ping to the target server fails | Confirm the target is powered on and reachable from the Orange Pi: `ping 192.168.1.40`. |
| Laptop cannot reach the target | Approve the route in the Tailscale admin console and run `sudo tailscale up --accept-routes` on the laptop. |
| Service fails to start | Check `sudo systemctl status ip-forwarding` and `journalctl -u ip-forwarding -e`. |
| Rules are missing | Run `sudo /opt/ip_forwarding/ip_forward.sh status` and re-enable with `enable`. |

Logs are written to `/var/log/ip_forwarding.log`.

```bash
sudo tail -f /var/log/ip_forwarding.log
```

## Project Structure

```text
.
├── config.conf             # Network and target configuration
├── install.sh              # Install files and register the systemd service
├── ip_forward.sh           # Main enable/disable/status/advertise/test script
├── ip-forwarding.service   # systemd unit
├── uninstall.sh            # Remove installed files and rules
└── README.md
```

## Uninstall

```bash
sudo ./uninstall.sh
```

This stops and disables the service, removes the installed files and
`sysctl` configuration, and reloads `systemd`.
