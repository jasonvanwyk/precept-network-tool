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

```bash
sudo pacman -S nmap traceroute mtr bind arp-scan tcpdump wireshark-qt \
  iperf3 wavemon networkmanager openbsd-netcat ethtool whois net-tools \
  horst speedtest-cli linssid
```

All packages are currently installed.

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

## Other WiFi Tools

- `wavemon` — ncurses real-time signal monitor with graph
- `linssid` — GUI WiFi scanner with signal/channel graphs
- `sudo horst -i wlan0` — raw WiFi frame monitor

## Tips for Claude

- When asked to run a site analysis, execute: `sudo bash ~/site-analysis-tools/site-analysis.sh <site-name>`
- When asked to do a WiFi survey, the user must run it interactively: `bash ~/site-analysis-tools/wifi-survey.sh <site-name>`
- After the report is generated, read the report file and summarize key findings
- Flag any issues: high packet loss, low signal strength, DNS problems, blocked ports
- Compare results across multiple site visits if previous reports exist in the reports dir
- Survey CSV files can be parsed to identify dead spots and recommend AP placement
- The report is plain text and can be parsed section by section
