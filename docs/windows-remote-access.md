# Windows Remote Access from Linux

How to get CLI access to client Windows machines from the Arch Linux field laptop
for network diagnostics and troubleshooting.

---

## Quick Reference

| Method | Windows Setup Needed | Ports | Shell | Best For |
|---|---|---|---|---|
| Impacket (psexec/smbexec/wmiexec) | None | 445, 135 | cmd / PowerShell | First contact — nothing to install |
| OpenSSH Server | 3 PowerShell commands | 22 | cmd / PowerShell | Persistent access, file transfer |
| Evil-WinRM | WinRM enabled | 5985/5986 | PowerShell | Domain-joined machines |
| RDP (FreeRDP) | Remote Desktop enabled | 3389 | GUI | When you need the screen |
| Telnet | Feature enable | 23 | cmd | Don't use — unencrypted, deprecated |

---

## Option 1: Impacket — Zero Config on Windows (Recommended First Step)

No setup required on the Windows machine. Just need valid local admin credentials
and SMB access (port 445). This is the go-to for first contact at a client site.

### Install

```bash
sudo pacman -S impacket
```

### Tools Included

| Tool | How It Works |
|---|---|
| `impacket-psexec` | Uploads a service binary via SMB, executes it — full interactive shell |
| `impacket-smbexec` | Creates a temp service, no binary upload — stealthier |
| `impacket-wmiexec` | Uses WMI over port 135/445 — semi-interactive shell |
| `impacket-atexec` | Schedules a task via the Task Scheduler service |

### Usage

```bash
# Full interactive shell via SMB (most reliable)
impacket-psexec 'WORKGROUP/Administrator:password@192.168.1.100'

# No binary uploaded to disk
impacket-smbexec 'WORKGROUP/Administrator:password@192.168.1.100'

# Uses WMI — different service, useful if SMB exec is blocked
impacket-wmiexec 'WORKGROUP/Administrator:password@192.168.1.100'
```

### Requirements

- Local admin credentials on the Windows machine
- SMB port 445 reachable (and port 135 for wmiexec)
- File and Printer Sharing enabled (usually on by default)

### Notes

- All methods require administrative rights on the remote system
- Some AV/EDR products may flag impacket activity
- psexec leaves traces (service binary on disk); smbexec and wmiexec are lighter
- Supports pass-the-hash if you have NTLM hashes instead of passwords

---

## Option 2: OpenSSH Server on Windows (Best Persistent Access)

Built into Windows 10 (build 1809+), Windows 11, and Windows Server 2019+.
Windows Server 2025 has it installed by default.

### Enable on Windows (Run PowerShell as Admin)

```powershell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start the service
Start-Service sshd

# Set to start automatically on boot
Set-Service -Name sshd -StartupType Automatic
```

The firewall rule for port 22 is created automatically during installation.

### Connect from Linux

```bash
# Basic connection (drops into cmd.exe by default)
ssh user@192.168.1.100

# Copy files to Windows
scp localfile.txt user@192.168.1.100:C:/Users/user/Desktop/

# Copy files from Windows
scp user@192.168.1.100:C:/Users/user/Documents/file.txt ./
```

### Change Default Shell to PowerShell (Optional)

Run on Windows in an admin PowerShell:
```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -PropertyType String -Force
```

### Bootstrap via Impacket

If you can't get to the Windows machine physically, use impacket first, then
enable SSH remotely:

```bash
# Get a shell via impacket
impacket-psexec 'WORKGROUP/Administrator:password@192.168.1.100'

# Then run these in the remote shell:
powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
powershell -Command "Start-Service sshd"
powershell -Command "Set-Service -Name sshd -StartupType Automatic"
```

Now you can SSH in directly.

---

## Option 3: Evil-WinRM (PowerShell Remoting)

Uses WinRM (Windows Remote Management) on port 5985 (HTTP) or 5986 (HTTPS).
WinRM is often already enabled on domain-joined business machines.

### Install

```bash
yay -S evil-winrm-py
```

### Enable WinRM on Windows (If Not Already)

Run PowerShell as Admin:
```powershell
Enable-PSRemoting -Force
```

### Usage

```bash
evil-winrm -i 192.168.1.100 -u Administrator -p 'password'
```

### Features

- Full PowerShell environment
- File upload/download built-in
- Load and execute PowerShell scripts remotely
- Command history and colorized output
- Supports NTLM, Kerberos, and certificate authentication

---

## Option 4: RDP via FreeRDP (GUI Fallback)

When you need to see the Windows desktop — run GUI diagnostics, access Device
Manager, check Windows Event Viewer, etc.

### Install

```bash
sudo pacman -S freerdp
```

### Usage

```bash
# Basic connection
xfreerdp /v:192.168.1.100 /u:Administrator /p:password

# With dynamic resolution (resizes with your window)
xfreerdp /v:192.168.1.100 /u:Administrator /p:password /dynamic-resolution

# Fullscreen
xfreerdp /v:192.168.1.100 /u:Administrator /p:password /f

# Share a local folder with the Windows machine
xfreerdp /v:192.168.1.100 /u:Administrator /p:password /drive:share,/tmp/transfer
```

### Enable RDP on Windows

Settings > System > Remote Desktop > Enable Remote Desktop

Or via PowerShell:
```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

---

## Option 5: Direct Ethernet Connection

When connecting your laptop directly to the client's Windows machine with an
ethernet cable (no switch/network in between).

### Setup

**Option A: Static IPs (recommended — faster, more reliable)**

On your laptop:
```bash
# Find your ethernet interface name
ip link show

# Assign a static IP
sudo ip addr add 192.168.99.1/24 dev enp0s25
sudo ip link set enp0s25 up
```

On Windows:
- Open Network Connections (ncpa.cpl)
- Right-click the ethernet adapter > Properties > IPv4
- Set IP: `192.168.99.2`, Subnet: `255.255.255.0`

**Option B: Link-local (automatic, no config)**

Both machines auto-assign `169.254.x.x` addresses if no DHCP is available.
Check with `ip addr` (Linux) and `ipconfig` (Windows). This takes 30-60 seconds
to negotiate.

### Then Use Any Method Above

```bash
# Impacket over direct link
impacket-psexec 'WORKGROUP/Administrator:password@192.168.99.2'

# SSH over direct link
ssh user@192.168.99.2

# RDP over direct link
xfreerdp /v:192.168.99.2 /u:Administrator /p:password
```

This bypasses all network firewalls and infrastructure — you're on a private
point-to-point link.

---

## Recommended Field Workflow

```
1. Connect to same network (or direct ethernet cable)
         │
         ▼
2. impacket-psexec with creds ──── instant CLI, no Windows setup
         │
         ▼
3. Enable OpenSSH server ──── persistent SSH access from now on
         │
         ▼
4. SSH + SCP for ongoing work ──── encrypted, file transfer, familiar
         │
         ▼
5. RDP if GUI needed ──── Device Manager, Event Viewer, etc.
```

---

## Windows Diagnostic Commands (Once Connected)

Useful commands to run once you have a shell on the Windows machine:

```cmd
:: Network info
ipconfig /all
netsh interface show interface
netsh wlan show interfaces
netsh wlan show networks mode=bssid

:: DNS
nslookup google.com
ipconfig /displaydns
netsh interface ip show dns

:: Connectivity
ping 8.8.8.8
ping google.com
tracert 8.8.8.8
pathping google.com

:: Routing
route print
netstat -rn

:: Active connections
netstat -ano
netstat -b

:: Firewall
netsh advfirewall show allprofiles
netsh advfirewall firewall show rule name=all

:: DHCP
ipconfig /all | findstr "DHCP Lease"

:: System
systeminfo
wmic os get caption,version,buildnumber
wmic nic get name,speed,macaddress

:: WiFi profiles and passwords
netsh wlan show profiles
netsh wlan show profile name="SSID" key=clear

:: Services
sc query | findstr "SERVICE_NAME"
net start

:: Event log (recent errors)
wevtutil qe System /c:20 /f:text /rd:true
wevtutil qe Application /c:20 /f:text /rd:true
```

---

## Packages to Install

```bash
# Official repos
sudo pacman -S impacket freerdp

# AUR (optional, for WinRM access)
yay -S evil-winrm-py
```
