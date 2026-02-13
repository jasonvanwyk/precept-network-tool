# Network Diagnostic Tools Reference

Additional networking and troubleshooting tools beyond what ships with the base
site-analysis toolkit. Many of these come from Kali Linux and are available on
Arch Linux via pacman or AUR.

---

## Already Installed (Base Toolkit)

```
nmap, traceroute, mtr, dig (bind), arp-scan, tcpdump, wireshark-qt (includes tshark),
iperf3, wavemon, networkmanager, openbsd-netcat, ethtool, whois, net-tools,
horst, speedtest-cli, linssid, openssh, net-snmp
```

---

## Install Commands

### Official Repos (pacman)

```bash
sudo pacman -S impacket freerdp masscan nbtscan lldpd fping kismet \
  aircrack-ng mdk4 ngrep iptraf-ng iftop nethogs nload bmon hping arpwatch
```

### AUR (installed)

```bash
yay -S netdiscover dhcpdump onesixtyone
```

### AUR (failed to build — alternatives)

```bash
# evil-winrm-py  → pipx install evil-winrm-py
# enum4linux     → yay -S enum4linux-ng
# yersinia       → orphaned, use tshark for L2 analysis
# sparrow-wifi   → use kismet + linssid + airodump-ng instead
# darkstat       → use iftop/iptraf-ng instead
```

---

## Tools by Category

### Network Discovery & Mapping

| Tool | Package | Repo | Description |
|---|---|---|---|
| **lldpd** | `lldpd` | pacman | LLDP/CDP daemon — plug into a wall jack, run `lldpcli show neighbors` to see which switch, port, and VLAN you're on. Also detects Cisco CDP. Saves hours of cable tracing. |
| **fping** | `fping` | pacman | Parallel ping — sweep an entire subnet to find live hosts. `fping -asg 192.168.1.0/24` shows all responding IPs. Much faster than sequential ping. |
| **masscan** | `masscan` | pacman | Asynchronous port scanner — scans large subnets for specific ports orders of magnitude faster than nmap. Use for rapid service inventory on /16+ networks. |
| **nbtscan** | `nbtscan` | pacman | NetBIOS scanner — discovers Windows machines, their hostnames, logged-in users, and workgroup/domain. `nbtscan 192.168.1.0/24` maps the Windows side of the LAN. |
| **netdiscover** | `netdiscover` | AUR | ARP discovery with passive mode — can silently observe ARP traffic to map hosts without generating any traffic. Useful when you don't want to trigger IDS. |

#### Key Commands

```bash
# What switch/port/VLAN am I on?
sudo systemctl start lldpd && sleep 30 && lldpcli show neighbors

# Sweep subnet for live hosts
fping -asg 192.168.1.0/24

# Fast port scan of a /24 for common services
masscan 192.168.1.0/24 -p 22,80,443,3389,445 --rate 1000

# Find all Windows machines
nbtscan 192.168.1.0/24

# Passive network discovery (listen only)
sudo netdiscover -p -i eth0
```

---

### WiFi Analysis & Troubleshooting

| Tool | Package | Repo | Description |
|---|---|---|---|
| **kismet** | `kismet` | pacman | Comprehensive wireless detector/sniffer with web UI. Passively detects all APs (including hidden SSIDs), all clients, rogue APs, and deauth attacks. Logs everything for later analysis. |
| **aircrack-ng** | `aircrack-ng` | pacman | WiFi assessment suite. `airmon-ng` manages monitor mode, `airodump-ng` shows all APs and connected clients with encryption type, signal, and data rates in real time. |
| **sparrow-wifi** | `sparrow-wifi-git` | AUR | GUI WiFi analyzer with real-time signal graphs, channel overlap visualization, and GPS heatmap support. Linux replacement for inSSIDer. |
| **mdk4** | `mdk4` | pacman | 802.11 protocol testing — verify client WIDS/WIPS systems are working. Can detect beacon floods and channel congestion. |

#### Key Commands

```bash
# Start kismet (web UI at http://localhost:2501)
sudo kismet -c wlan0

# Put WiFi card in monitor mode
sudo airmon-ng start wlan0

# See all APs and clients in real time
sudo airodump-ng wlan0mon

# Stop monitor mode
sudo airmon-ng stop wlan0mon
```

---

### Traffic Analysis & Monitoring

| Tool | Package | Repo | Description |
|---|---|---|---|
| **iftop** | `iftop` | pacman | Real-time bandwidth by connection — instantly see which connections consume the most bandwidth. The #1 tool for diagnosing "the internet is slow." |
| **nethogs** | `nethogs` | pacman | Bandwidth by process — shows which application is eating bandwidth. Like `top` but for network usage per process. |
| **iptraf-ng** | `iptraf-ng` | pacman | ncurses IP traffic monitor — TCP/UDP connection breakdown, interface stats, protocol distribution. Full dashboard view. |
| **ngrep** | `ngrep` | pacman | Network grep — regex pattern matching on packet payloads. Find specific DNS queries, HTTP requests, or any plaintext content in live traffic. |
| **nload** | `nload` | pacman | Console bandwidth monitor with ASCII graphs — incoming/outgoing traffic with current, average, min, max rates. Quick visual of link utilization. |
| **bmon** | `bmon` | pacman | Multi-interface bandwidth monitor — see traffic on all interfaces simultaneously with bar graphs. |
| **darkstat** | `darkstat` | AUR | Web-based traffic analyzer — captures traffic and serves stats via built-in HTTP server. Leave running during a site visit, show clients the results in a browser. |

#### Key Commands

```bash
# What's using the bandwidth? (by connection)
sudo iftop -i eth0

# What's using the bandwidth? (by process)
sudo nethogs eth0

# Full traffic dashboard
sudo iptraf-ng

# Search live traffic for DNS queries to a domain
sudo ngrep -d eth0 'example.com' port 53

# Simple bandwidth graph
nload eth0

# All interfaces at once
bmon

# Web dashboard (browse to http://localhost:667)
sudo darkstat -i eth0
```

---

### Network Protocol Analysis

| Tool | Package | Repo | Description |
|---|---|---|---|
| **arpwatch** | `arpwatch` | pacman | Monitors ARP traffic — detects new hosts, IP changes, MAC flip-flops (ARP spoofing), and IP conflicts. Run passively during a site visit to catch anomalies. |
| **dhcpdump** | `dhcpdump` | AUR | Human-readable DHCP packet dump — see exactly what the DHCP server is handing out (IP, gateway, DNS, lease time). Much clearer than parsing tcpdump. |
| **hping3** | `hping` | pacman | TCP/IP packet crafter — send custom TCP/UDP/ICMP packets to test firewall rules precisely, do advanced MTU discovery, measure TCP-level latency. |
| **yersinia** | `yersinia` | AUR | Layer 2 protocol analyzer — decode STP, CDP, DTP, DHCP, HSRP, 802.1Q VLAN traffic. Diagnose spanning tree issues, VLAN misconfigs, and L2 problems. |

#### Key Commands

```bash
# Monitor ARP for anomalies
sudo arpwatch -i eth0

# Watch DHCP transactions in real time
sudo dhcpdump -i eth0

# Test if a specific TCP port is filtered by firewall
sudo hping3 -S -p 443 -c 3 192.168.1.1

# MTU path discovery
sudo hping3 --tr-stop -V -1 -d 1472 google.com

# Layer 2 protocol sniffer (ncurses)
sudo yersinia -I
```

---

### SNMP & Network Management

| Tool | Package | Repo | Description |
|---|---|---|---|
| **net-snmp** | `net-snmp` | pacman | SNMP tools (snmpwalk, snmpget, snmpbulkwalk) — query managed switches, routers, and APs for port status, VLAN config, MAC tables, error counters, and traffic stats. Already installed. |
| **onesixtyone** | `onesixtyone` | AUR | Fast SNMP scanner — discovers SNMP-enabled devices on a subnet and tests for default/weak community strings. |

#### Key Commands

```bash
# Get system description from a switch
snmpwalk -v2c -c public 192.168.1.1 1.3.6.1.2.1.1

# Interface table (ports, status, speed)
snmpwalk -v2c -c public 192.168.1.1 1.3.6.1.2.1.2.2.1

# MAC address table
snmpwalk -v2c -c public 192.168.1.1 1.3.6.1.2.1.17.4.3.1

# Interface error counters
snmpwalk -v2c -c public 192.168.1.1 1.3.6.1.2.1.2.2.1.14

# Scan subnet for SNMP-enabled devices
onesixtyone -c /usr/share/doc/onesixtyone/dict.txt 192.168.1.0/24
```

---

### Windows/SMB Network Tools

| Tool | Package | Repo | Description |
|---|---|---|---|
| **impacket** | `impacket` | pacman | Python tools for SMB/WMI/DCOM — psexec, smbexec, wmiexec for remote Windows shells. smbclient for share access. No setup needed on Windows side. |
| **enum4linux** | `enum4linux` | AUR | SMB/NetBIOS enumerator — lists users, groups, shares, OS info, and password policies from Windows/Samba machines. Identifies misconfigurations. |
| **evil-winrm** | `evil-winrm-py` | AUR | WinRM shell — full PowerShell session on Windows with file upload/download. Works when WinRM is enabled (common on domain machines). |
| **freerdp** | `freerdp` | pacman | RDP client — GUI access to Windows desktops. Supports drive sharing, dynamic resolution, and clipboard. |

See [windows-remote-access.md](windows-remote-access.md) for full details and
workflow.

---

### Vulnerability & Security Assessment

| Tool | Package | Repo | Description |
|---|---|---|---|
| **nmap NSE scripts** | `nmap` | pacman | Already installed — 600+ scripts for vuln scanning, SSL auditing, service fingerprinting. Use `--script vuln`, `--script smb-vuln*`, `--script ssl-enum-ciphers`. |

#### Key Commands

```bash
# Scan for known vulnerabilities
nmap --script vuln 192.168.1.1

# Check SMB vulnerabilities (EternalBlue, etc.)
nmap --script smb-vuln* -p 445 192.168.1.0/24

# Audit SSL/TLS configuration
nmap --script ssl-enum-ciphers -p 443 192.168.1.1

# Service version detection with banners
nmap -sV --script=banner 192.168.1.0/24

# Full enumeration of a Windows machine
enum4linux -a 192.168.1.100
```

---

### Cable & Physical Layer

| Tool | Package | Repo | Description |
|---|---|---|---|
| **ethtool** | `ethtool` | pacman | Already installed — beyond basic link status, supports TDR cable testing (`--cable-test`), NIC error stats (`-S`), and driver/firmware info (`-i`). |

#### Key Commands

```bash
# TDR cable test (detect faults, measure length — requires supported NIC)
sudo ethtool --cable-test eth0

# NIC error statistics (CRC errors, frame errors, drops = physical layer problems)
ethtool -S eth0

# Link speed, duplex, autonegotiation status
ethtool eth0

# Driver and firmware info
ethtool -i eth0
```

---

## Top 10 Must-Install Tools (Priority Order)

| # | Tool | Why |
|---|---|---|
| 1 | **impacket** | Remote shell into Windows machines with zero setup on their end |
| 2 | **lldpd** | Plug into a wall jack, instantly know the switch/port/VLAN |
| 3 | **iftop** | Instant answer to "the internet is slow" — see what's using bandwidth |
| 4 | **kismet** | Most comprehensive WiFi environment assessment available |
| 5 | **freerdp** | GUI access to Windows when CLI isn't enough |
| 6 | **aircrack-ng** | See every AP and every client, who's connected where |
| 7 | **fping** | Sweep a subnet in seconds — what's alive? |
| 8 | **nbtscan** | Map all Windows machines on the LAN instantly |
| 9 | **arpwatch** | Catch IP conflicts, ARP spoofing, rogue DHCP — passive detection |
| 10 | **nethogs** | Which process is eating the bandwidth? |

---

## Quick Install — All Recommended Tools

```bash
# Official repos (all installed)
sudo pacman -S impacket freerdp masscan nbtscan lldpd fping kismet \
  aircrack-ng mdk4 ngrep iptraf-ng iftop nethogs nload bmon hping arpwatch

# AUR (installed)
yay -S netdiscover dhcpdump onesixtyone

# Failed AUR builds — alternatives:
#   evil-winrm-py  → pipx install evil-winrm-py
#   enum4linux     → yay -S enum4linux-ng
#   yersinia       → use tshark for L2 analysis
#   sparrow-wifi   → kismet + linssid + airodump-ng
#   darkstat       → iftop + iptraf-ng
```
