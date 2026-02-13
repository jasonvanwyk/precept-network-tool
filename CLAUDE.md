# Site Analysis Tools

## Purpose
On-site network and connectivity assessment toolkit. Run when visiting a client
site to generate a comprehensive report covering internet quality, WiFi, LAN,
DNS, routing, and more. Reports are saved locally and can be sent to the dev
server.

## Usage

Run the full analysis (pass site name as argument):
```bash
cd ~/site-analysis-tools
sudo bash site-analysis.sh client-name
```
Sudo is needed for WiFi scanning, ARP discovery, and firewall checks. The script
handles missing sudo gracefully — those sections will just note they were skipped.

Reports are saved to `~/site-analysis-tools/reports/` as timestamped text files.
At the end, the script offers to SCP the report to the dev server at
`jason@10.0.10.21:~/site-reports/`.

## What It Collects

| Section | Tools Used | What It Captures |
|---|---|---|
| System Info | hostnamectl, uname | OS, kernel, hostname, uptime |
| Network Interfaces | ip addr, ethtool | All interfaces, IPs, MACs, link stats |
| Routing & Gateway | ip route, ip neigh | Routes, default gateway, ARP table |
| DNS | dig, resolvectl | DNS servers, resolution times to 8.8.8.8/1.1.1.1/9.9.9.9 |
| Public IP & ISP | curl, whois | Public IP, ISP name, org, location |
| Speed Test | speedtest-cli | Download, upload, ping to nearest server |
| WiFi Analysis | iw, nmcli | Signal strength, SSID, channel, frequency, all nearby networks, security |
| Latency | ping, mtr | Packet loss, jitter, latency to gateway/8.8.8.8/google.com |
| Traceroute | traceroute | Hop-by-hop path to 8.8.8.8 and google.com |
| LAN Discovery | arp-scan, nmap | Devices on local subnet, gateway services |
| Port Reachability | netcat, nmap | Common ports (80/443/53/22) outbound, gateway ports |
| DHCP | nmcli, lease files | Active connections, DHCP lease details |
| Firewall | ufw, iptables, nft | Local firewall rules |
| Bandwidth | iperf3 | Throughput to public iperf3 server |
| Connections | ss | Active connections, listening services |

## Required Packages

### Base Toolkit (all currently installed)

```bash
sudo pacman -S nmap traceroute mtr bind arp-scan tcpdump wireshark-qt \
  iperf3 wavemon networkmanager openbsd-netcat ethtool whois net-tools \
  horst speedtest-cli linssid
```

### Extended Toolkit (Windows access, discovery, monitoring)

```bash
# Official repos (all installed)
sudo pacman -S impacket freerdp masscan nbtscan lldpd fping kismet \
  aircrack-ng mdk4 ngrep iptraf-ng iftop nethogs nload bmon hping arpwatch

# AUR (installed)
yay -S netdiscover dhcpdump onesixtyone

# Failed to build from AUR — alternatives:
#   evil-winrm-py  → pipx install evil-winrm-py
#   enum4linux     → yay -S enum4linux-ng
#   yersinia       → use tshark for L2 analysis
#   sparrow-wifi   → use kismet + linssid + airodump-ng
```

### Full tool inventory with descriptions: [tools.yaml](tools.yaml)

## Dev Server

Reports are sent via SCP to: `jason@10.0.10.21:~/site-reports/`

To send a report manually:
```bash
scp reports/<report-file>.txt jason@10.0.10.21:~/site-reports/
```

## WiFi Dead Spot Survey

Interactive walk-around tool for mapping WiFi signal strength across a site.

```bash
bash ~/site-analysis-tools/wifi-survey.sh <site-name>
```

Controls:
- **m** — Mark location (details below)
- **n** — Quick note with current signal
- **s** — Stats snapshot (signal, noise, bitrate, ping stats, duration)
- **q** — Quit, show full summary with analysis, and optionally send to dev server

### Mark location flow (m)
1. Auto-captures signal stability (10 samples), noise floor, SNR, TX retries,
   all nearby SSIDs with signal/freq/channel
2. Prompts for location metadata — most are **single keypress** (no Enter):
   - **Location name** — free text + Enter
   - **Floor** — press `1`-`7` instantly: ground/1st/2nd/3rd/basement/mezzanine/roof
   - **Room type** — press `1`-`9` instantly: bedroom/bathroom/kitchen/living/office/garage/hallway/stairwell/outdoor
   - **Indoor/outdoor** — press `1` or `2` instantly
   - **Distance (m)** — type number + Enter
   - **Walls** — press `1`-`6` instantly: 0/1/2/3/4/5+
   - **Wall material** — press `1`-`6` instantly: drywall/brick/concrete/wood/glass/mixed
   - **Glass doors** — press `1`-`4` instantly: 0/1/2/3
   - **Interference** — toggle on/off with `1`-`7`, press Enter when done
   - **Notes** — free text + Enter (or just Enter to skip)
3. Shows compact summary bar — `c` to save, `1`-`9`/`0` to edit any field, `x` to cancel
4. Auto-runs quick network tests: gateway ping, internet ping, DNS resolution, HTTP TTFB
- Press `0` at any menu for custom text input
- Press `b` at any prompt to go back to previous field

Background (runs continuously):
- Signal strength, noise floor, bitrate, TX retries/failed, beacon loss logged every 2s
- Gateway ping logged every 1s (tracks packet loss and latency over time)
- Roaming detection (logs when BSSID changes — AP handoff)

Output files (all in `~/site-analysis-tools/surveys/`):
- `*_survey_*.csv` — One row per marked location with all metadata and test results
- `*_ssids_*.csv` — All SSIDs seen at each location with signal/freq/channel
- `*_timeseries_*.csv` — Continuous signal/stats samples (every 2s)
- `*_ping_*.csv` — Continuous gateway ping results (every 1s)
- `*_survey_*.log` — Human-readable log with full details

Analysis on quit:
- Location results table with signal/avg/walls/glass/floor/quality
- Continuous ping statistics (total, loss %, min/avg/max latency)
- Roaming events detected during survey
- Channel congestion analysis (2.4 GHz and 5 GHz separately)
- 2.4 GHz overlapping channel warnings (non 1/6/11)
- 2.4 GHz vs 5 GHz band comparison
- Dead spot recommendations based on distance, walls, material, and signal

Signal thresholds: excellent (>-30), good (>-50), fair (>-60), weak (>-70), dead spot (<-70)

## Windows Remote Access

See [docs/windows-remote-access.md](docs/windows-remote-access.md) for full details.

Quick workflow: use `impacket-psexec` for instant CLI access (no Windows setup
needed), then enable OpenSSH server for persistent SSH access, then RDP via
`xfreerdp` if GUI is needed.

```bash
# Instant remote shell (just need admin creds + port 445)
impacket-psexec 'WORKGROUP/Administrator:password@<ip>'

# SSH after enabling OpenSSH on Windows
ssh user@<ip>

# RDP for GUI access
xfreerdp /v:<ip> /u:user /p:password /dynamic-resolution
```

## Windows Password & PIN Reset

See [docs/windows-password-reset.md](docs/windows-password-reset.md) for all methods.

Quick options:
- **Microsoft account** → "I forgot my PIN" on lock screen, or `account.live.com`
- **Local account** → `chntpw` from Linux to blank password, or utilman.exe trick
- **Domain machine** → domain admin resets via AD

## Router Access

See [docs/router-access.md](docs/router-access.md) for the full guide — default
credentials by brand, alternative access methods (SSH, SNMP, non-standard ports),
and what to check once logged in.

```bash
# Find gateway
ip route | grep default

# Identify make/model
nmap -sV -p 80,443,8080,8443 <gateway-ip>

# SNMP query (often works without web login)
snmpwalk -v2c -c public <gateway-ip> 1.3.6.1.2.1.1
```

## Email Troubleshooting

See [docs/email-troubleshooting.md](docs/email-troubleshooting.md) for the full
guide — password recovery, mail delivery diagnosis, DNS record checks, and
common provider settings.

```bash
# Test mail server connectivity
nc -zv mail.example.com 587 && nc -zv mail.example.com 993

# Check MX + SPF + DMARC
dig MX example.com
dig TXT example.com
dig TXT _dmarc.example.com

# SMTP handshake test
openssl s_client -connect mail.example.com:587 -starttls smtp
```

## Additional Network Tools

See [docs/network-tools.md](docs/network-tools.md) for the full reference.

Key additions from Kali Linux and the broader Linux ecosystem:
- **lldpd** — identify switch/port/VLAN from a wall jack
- **iftop / nethogs** — real-time bandwidth monitoring by connection or process
- **kismet / aircrack-ng** — advanced WiFi analysis and client tracking
- **fping / masscan / nbtscan** — fast network discovery and scanning
- **arpwatch** — passive ARP anomaly detection (IP conflicts, spoofing)
- **net-snmp** — query managed switches/routers/APs via SNMP
- **hping3** — custom packet crafting for firewall testing

## Other WiFi Tools

- `wavemon` — ncurses real-time signal monitor with graph
- `linssid` — GUI WiFi scanner with signal/channel graphs
- `sudo horst -i wlan0` — raw WiFi frame monitor

## Tips for Claude

### Site Analysis & Surveys
- When asked to run a site analysis, execute: `sudo bash ~/site-analysis-tools/site-analysis.sh <site-name>`
- When asked to do a WiFi survey, the user must run it interactively: `bash ~/site-analysis-tools/wifi-survey.sh <site-name>`
- After the report is generated, read the report file and summarize key findings
- Flag any issues: high packet loss, low signal strength, DNS problems, blocked ports
- Compare results across multiple site visits if previous reports exist in the reports dir
- Survey CSV files can be parsed to identify dead spots and recommend AP placement
- The report is plain text and can be parsed section by section

### When to Use Which Tool

**"I need a shell on a Windows machine"**
→ `impacket-psexec 'WORKGROUP/user:pass@<ip>'` (nothing needed on Windows side)
→ Then enable OpenSSH for persistent access, or `xfreerdp` for GUI

**"What switch/port/VLAN is this wall jack?"**
→ `sudo systemctl start lldpd && sleep 30 && lldpcli show neighbors`

**"The internet is slow"**
→ `sudo iftop -i <iface>` (bandwidth by connection)
→ `sudo nethogs <iface>` (bandwidth by process)
→ `speedtest-cli` (raw speed test)
→ `mtr 8.8.8.8` (latency + packet loss per hop)

**"What devices are on this network?"**
→ `fping -asg <subnet>/24` (fast alive sweep)
→ `sudo arp-scan -l` (ARP-based discovery)
→ `nbtscan <subnet>/24` (Windows machines specifically)
→ `sudo nmap -sn <subnet>/24` (comprehensive ping sweep)

**"WiFi problems / dead spots"**
→ `bash wifi-survey.sh <site>` (interactive walk-around survey)
→ `wavemon` (real-time signal monitor)
→ `sudo kismet -c wlan0` (full wireless environment — all APs, all clients, hidden SSIDs)
→ `sudo airmon-ng start wlan0 && sudo airodump-ng wlan0mon` (all APs + clients, who's connected where)

**"Is there something wrong at Layer 2?"**
→ `sudo arpwatch -i <iface>` (ARP anomalies, IP conflicts, spoofing)
→ `sudo yersinia -I` (STP, CDP, DTP, VLAN issues)
→ `sudo dhcpdump -i <iface>` (watch DHCP transactions)

**"What's this managed switch/router/AP doing?"**
→ `snmpwalk -v2c -c public <ip> 1.3.6.1.2.1.1` (system info)
→ `snmpwalk -v2c -c public <ip> 1.3.6.1.2.1.2.2.1` (interface/port table)

**"Is this port/firewall blocking traffic?"**
→ `sudo hping3 -S -p <port> -c 3 <ip>` (test specific TCP port)
→ `nmap --script ssl-enum-ciphers -p 443 <ip>` (audit TLS)
→ `nmap --script vuln <ip>` (vulnerability scan)

**"I need to search live traffic for something"**
→ `sudo ngrep -d <iface> '<pattern>' port <port>` (grep network traffic)
→ `sudo iptraf-ng` (full traffic dashboard)
→ `sudo tshark -i <iface> -f '<capture filter>'` (CLI wireshark)

**"Is this ethernet cable/port OK?"**
→ `sudo ethtool --cable-test <iface>` (TDR cable test)
→ `ethtool -S <iface>` (NIC error counters — CRC errors = bad cable)
→ `ethtool <iface>` (link speed, duplex, autoneg)

**"Enumerate a Windows/SMB machine"**
→ `enum4linux -a <ip>` (users, groups, shares, policies)
→ `nbtscan <ip>` (NetBIOS info)
→ `nmap --script smb-vuln* -p 445 <ip>` (SMB vulnerabilities)

**"Client forgot their email password"**
→ Check browser saved passwords on their Windows machine (Chrome/Edge/Firefox)
→ `cmdkey /list` in Windows for Credential Manager entries
→ NirSoft Mail PassView on USB stick for Outlook/Thunderbird
→ Or just reset via provider portal / hosting panel

**"Email isn't working"**
→ `nc -zv mail.server 587` (is SMTP reachable?)
→ `nc -zv mail.server 993` (is IMAP reachable?)
→ `dig MX domain.com` (correct MX records?)
→ `dig TXT domain.com` (SPF record exists?)
→ `openssl s_client -connect mail.server:587 -starttls smtp` (TLS working?)

### Documentation
- Full Windows remote access guide: `docs/windows-remote-access.md`
- Full network tools reference: `docs/network-tools.md`
- Router access & default credentials: `docs/router-access.md`
- Email troubleshooting & password recovery: `docs/email-troubleshooting.md`
- Windows password & PIN reset: `docs/windows-password-reset.md`
- Full tool inventory with descriptions: `tools.yaml`
