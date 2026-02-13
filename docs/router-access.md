# Router Access Guide

How to access client routers and access points on-site for diagnostics and
configuration review.

---

## Quick Reference

```bash
# 1. Find the gateway
ip route | grep default

# 2. Identify make/model
nmap -sV -p 80,443,8080,8443 <gateway-ip>
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.1.1.0

# 3. Open admin panel
xdg-open http://<gateway-ip>

# 4. Try default credentials (see table below)
```

---

## Step 1: Find the Gateway

```bash
ip route | grep default
```

Usually `192.168.1.1`, `192.168.0.1`, or `10.0.0.1`.

---

## Step 2: Identify the Router

```bash
# Service/version detection on common admin ports
nmap -sV -p 80,443,8080,8443 <gateway-ip>

# SNMP system description (model, firmware)
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.1.1.0

# Full SNMP system info
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.1

# LLDP/CDP (if you're plugged into a managed switch behind it)
lldpcli show neighbors

# MAC address lookup — first 3 octets identify the manufacturer
ip neigh show | grep <gateway-ip>
# Then look up the OUI at https://maclookup.app/
```

---

## Step 3: Default Credentials

### Common Consumer / Small Business Routers

| Brand | Default URL | Username | Password |
|---|---|---|---|
| Generic / most routers | `http://<gateway>` | admin | admin |
| Netgear | `http://<gateway>` | admin | password |
| TP-Link | `http://192.168.0.1` or `http://tplinkwifi.net` | admin | admin |
| Linksys | `http://192.168.1.1` | admin | admin |
| D-Link | `http://192.168.0.1` | admin | *(blank)* |
| Asus | `http://192.168.1.1` or `http://router.asus.com` | admin | admin |
| Huawei | `http://192.168.1.1` | admin | admin |
| ZTE (ISP-supplied) | `http://192.168.1.1` | admin | admin |
| Belkin | `http://192.168.2.1` | *(blank)* | *(blank)* |

### Enterprise / Prosumer

| Brand | Default URL | Username | Password |
|---|---|---|---|
| Mikrotik | `http://<gateway>` | admin | *(blank)* |
| Ubiquiti UniFi | `https://<gateway>:8443` | ubnt | ubnt |
| Ubiquiti EdgeRouter | `https://<gateway>` | ubnt | ubnt |
| Cisco (consumer) | `http://192.168.1.1` | admin | admin |
| Cisco IOS (SSH/telnet) | N/A | cisco | cisco |
| FortiGate | `https://<gateway>` | admin | *(blank)* |
| pfSense | `https://<gateway>` | admin | pfsense |
| OPNsense | `https://<gateway>` | root | opnsense |
| DrayTek Vigor | `http://192.168.1.1` | admin | admin |

### ISP-Supplied Routers (South Africa)

| ISP | Common Router | Default URL | Notes |
|---|---|---|---|
| Telkom | ZTE/Huawei | `http://192.168.1.1` | Password often on sticker |
| Vumatel/Openserve ONT | Various | `http://192.168.1.1` | ONT password often on label |
| Rain | Huawei LTE | `http://192.168.8.1` | admin / admin |

**Always check the physical sticker on the router first** — many ISP-supplied
routers have a unique password printed on the bottom or back label.

---

## Step 4: Alternative Access Methods

### SSH / Telnet

Many enterprise and prosumer routers have SSH or telnet enabled:

```bash
# Check if SSH or telnet is open
nmap -sV -p 22,23 <gateway-ip>

# SSH in (Mikrotik, Ubiquiti, Cisco, FortiGate, etc.)
ssh admin@<gateway-ip>

# Telnet (older gear)
telnet <gateway-ip>
```

### Non-Standard Ports

Routers sometimes run admin interfaces on unusual ports:

```bash
# Scan all ports to find admin interfaces
nmap -sV -p- <gateway-ip>

# Common alternate ports
# 8080, 8443 — alternate HTTP/HTTPS
# 8291 — Mikrotik Winbox
# 8728/8729 — Mikrotik API
# 4343 — some Aruba APs
```

### SNMP (Read Config Without Web Login)

If SNMP is enabled (common on enterprise gear), you can pull a lot of info
without the web password:

```bash
# System info
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.1

# Interface table (ports, status, speed, errors)
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.2.2.1

# ARP/MAC table
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.4.22.1

# Routing table
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.4.21.1

# Try common community strings
snmpwalk -v2c -c public <gateway-ip>
snmpwalk -v2c -c private <gateway-ip>

# Scan for SNMP-enabled devices with default strings
onesixtyone -c /usr/share/doc/onesixtyone/dict.txt <subnet>/24
```

### Recover Password from Connected Windows Machine

If a client's Windows machine has the router password saved in a browser:

```bash
# Get a shell on their Windows machine
impacket-psexec 'WORKGROUP/Administrator:pass@<ip>'

# Check for saved browser password databases (files exist = passwords saved)
dir "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Login Data"
dir "C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles\*\logins.json"
dir "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Login Data"
```

Browser password databases are encrypted but the existence of saved entries
confirms passwords are saved. The user can open the browser's password manager
to retrieve them, or use a tool like `nirsoft` on the Windows machine.

---

## Step 5: What to Check Once You're In

### Critical Settings to Document

```
- WAN connection type (DHCP, PPPoE, static)
- WAN IP, gateway, DNS servers
- LAN IP range, subnet mask
- DHCP pool range, lease time
- DNS settings (ISP, custom, or forwarding)
- WiFi SSIDs, channels, channel width, security mode
- WiFi transmit power
- Port forwarding / NAT rules
- Firewall rules
- QoS settings
- Firmware version (check for updates)
- UPnP enabled/disabled
- Remote management enabled/disabled
- Connected client list
```

### Red Flags to Report to Client

- Remote management enabled (security risk)
- UPnP enabled (security risk)
- WEP or Open WiFi (should be WPA2/WPA3)
- Default admin password still set
- Firmware more than 1 year out of date
- DNS set to unusual/unknown servers
- Port forwarding rules they don't recognise
- WiFi on congested channel (check with `airodump-ng` or `wifi-survey.sh`)

---

## Step 6: Factory Reset (Last Resort)

Only with **explicit client approval** — this erases all configuration:

1. Find the reset pinhole on the router (usually on the back)
2. Hold for 10-15 seconds with a paperclip while powered on
3. Wait for reboot (1-2 minutes)
4. Connect to default IP with default credentials
5. Reconfigure WAN, WiFi, and all settings from scratch

**Before resetting**, try to document current settings via SNMP or screenshots
so you can restore the configuration.
