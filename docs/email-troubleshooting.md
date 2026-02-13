# Email Troubleshooting & Password Recovery

Guide for recovering client email passwords and diagnosing mail delivery issues
on-site.

---

## Quick Reference

```bash
# Test mail server connectivity
nc -zv mail.example.com 587
nc -zv mail.example.com 993

# Check MX records
dig MX example.com

# Check SPF/DKIM/DMARC
dig TXT example.com
dig TXT _dmarc.example.com

# SMTP handshake test
openssl s_client -connect mail.example.com:587 -starttls smtp
```

---

## Recovering Email Passwords

### From Browser Saved Passwords (Most Common)

Clients almost always log into webmail via a browser. The password is stored
locally and viewable in browser settings.

**If you have a shell on their Windows machine:**

```cmd
:: Check if Chrome has saved passwords
dir "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Login Data"

:: Check Edge
dir "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Login Data"

:: Check Firefox
dir "C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles\*\logins.json"
```

Then have the client open:
- **Chrome**: `chrome://settings/passwords`
- **Edge**: `edge://settings/passwords`
- **Firefox**: `about:logins`

Search for the email provider name — the password is behind the eye icon.

**Getting a shell remotely:**

```bash
# Via ethernet + impacket (no setup needed on Windows)
impacket-psexec 'WORKGROUP/Administrator:pass@<ip>'

# Or SSH if OpenSSH is enabled
ssh user@<ip>
```

### From Windows Credential Manager

Windows stores mail and web passwords in the Credential Manager:

```cmd
:: List all stored credentials (shows entries, not passwords)
cmdkey /list

:: Open Credential Manager GUI (client can see passwords here)
rundll32.exe keymgr.dll,KRShowKeyMgr

:: Or via Control Panel
control /name Microsoft.CredentialManager
```

Look under "Web Credentials" for webmail and "Windows Credentials" for
Outlook/Exchange accounts.

### From Outlook / Desktop Mail Clients

**Check if Outlook profiles exist:**

```cmd
:: Outlook 2016/2019/365
reg query "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles" /s

:: Outlook 2013
reg query "HKCU\Software\Microsoft\Office\15.0\Outlook\Profiles" /s

:: Check Outlook account settings (shows server, username — not password)
reg query "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles\Outlook\9375CFF0413111d3B88A00104B2A6676" /s
```

**Check Thunderbird:**

```cmd
:: Find Thunderbird profiles
dir "C:\Users\*\AppData\Roaming\Thunderbird\Profiles\*"
```

**NirSoft Mail PassView** (recommended field tool):
- Free, portable, no install needed
- Extracts passwords from Outlook, Thunderbird, Windows Mail, Gmail Notifier,
  and other mail clients in one click
- Download from nirsoft.net and keep on a USB stick
- Run on the client machine to reveal all stored mail passwords

### From Mobile Devices

- **iPhone**: Settings > Passwords > search for email provider
- **Android**: Settings > Passwords & Accounts, or Chrome > Settings > Password Manager
- **Samsung**: Settings > Biometrics and Security > Samsung Pass

### Password Reset (Often Fastest)

When saved credentials can't be found, just reset it:

| Provider | Reset URL | Notes |
|---|---|---|
| Gmail / Google Workspace | `accounts.google.com` > Security | Needs phone or recovery email |
| Outlook.com / Hotmail | `account.live.com` | Needs phone or recovery email |
| Microsoft 365 (business) | `portal.office.com` | Admin can reset via admin portal |
| Yahoo Mail | `login.yahoo.com` > Forgot password | Needs phone |
| cPanel hosted email | `<domain>:2083` or hosting panel | Admin resets directly — no old password needed |
| Plesk hosted email | `<domain>:8443` or hosting panel | Admin resets directly |
| On-prem Exchange | Active Directory Users & Computers | Domain admin resets password |
| Self-hosted (Postfix, etc.) | SSH into mail server | `passwd <user>` or edit virtual mailbox DB |

---

## Diagnosing Mail Delivery Issues

### Test Server Connectivity

```bash
# SMTP (sending)
nc -zv mail.example.com 25      # SMTP (server-to-server, often blocked by ISPs)
nc -zv mail.example.com 587     # SMTP submission (with STARTTLS — standard for clients)
nc -zv mail.example.com 465     # SMTPS (implicit TLS)

# IMAP (receiving — preferred)
nc -zv mail.example.com 143     # IMAP (plaintext/STARTTLS)
nc -zv mail.example.com 993     # IMAPS (implicit TLS)

# POP3 (receiving — legacy)
nc -zv mail.example.com 110     # POP3 (plaintext/STARTTLS)
nc -zv mail.example.com 995     # POP3S (implicit TLS)
```

### Check DNS Records

```bash
# MX records (where mail is delivered)
dig MX example.com

# SPF (who's allowed to send as this domain)
dig TXT example.com

# DKIM (email signing key)
dig TXT default._domainkey.example.com
dig TXT selector1._domainkey.example.com    # Microsoft 365
dig TXT google._domainkey.example.com       # Google Workspace

# DMARC (policy for failed SPF/DKIM)
dig TXT _dmarc.example.com

# Autodiscover / autoconfig (email client auto-setup)
dig CNAME autodiscover.example.com
dig SRV _autodiscover._tcp.example.com
dig A autoconfig.example.com
```

### Test SMTP Handshake

```bash
# Test SMTP with STARTTLS (port 587)
openssl s_client -connect mail.example.com:587 -starttls smtp

# Test SMTPS (port 465)
openssl s_client -connect mail.example.com:465

# Test IMAPS
openssl s_client -connect mail.example.com:993

# In the SMTP session, you can test manually:
# EHLO test.local
# AUTH LOGIN
# (base64 encoded username)
# (base64 encoded password)
```

### Check TLS Certificate

```bash
# View certificate details
openssl s_client -connect mail.example.com:993 </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates

# Check if cert matches the hostname
openssl s_client -connect mail.example.com:993 -verify_hostname mail.example.com </dev/null
```

### Common Port Blocks

Some client networks or ISPs block outbound mail ports:

```bash
# Test if ports are reachable from the client network
nc -zv -w5 smtp.gmail.com 587
nc -zv -w5 smtp.gmail.com 465
nc -zv -w5 smtp-mail.outlook.com 587

# If 25/587 are blocked, try 465 (often allowed)
# If all SMTP ports blocked, client may need to use webmail or VPN
```

### Trace Mail Path

```bash
# Traceroute to mail server
mtr mail.example.com

# Check if mail server IP is blacklisted (common cause of delivery issues)
dig +short <reverse-ip>.zen.spamhaus.org
dig +short <reverse-ip>.bl.spamcop.net

# Example: for IP 1.2.3.4, reverse is 4.3.2.1
dig +short 4.3.2.1.zen.spamhaus.org
```

---

## Common Email Issues & Solutions

| Symptom | Likely Cause | Diagnosis |
|---|---|---|
| Can't send email | Port 587/465 blocked | `nc -zv mail.server 587` — if timeout, port is blocked |
| Can't receive email | Wrong MX records | `dig MX domain.com` — verify records point to correct server |
| Email goes to spam | Missing SPF/DKIM/DMARC | `dig TXT domain.com` — check for SPF record |
| Certificate warnings | Mismatched or expired cert | `openssl s_client` — check cert dates and hostname |
| Intermittent failures | DNS issues | `dig MX domain.com @8.8.8.8` vs `@1.1.1.1` — compare results |
| Bouncebacks "relay denied" | Auth not configured | Client not authenticating on port 587 — check client settings |
| Slow email | High latency to mail server | `mtr mail.server` — check for packet loss or high hops |
| "IP blacklisted" bounces | Server IP on spam list | Check spamhaus/spamcop lookups above |

---

## Email Server Settings Quick Reference

Common provider settings for manual client configuration:

### Gmail / Google Workspace
```
IMAP: imap.gmail.com:993 (SSL)
SMTP: smtp.gmail.com:587 (STARTTLS)
```

### Microsoft 365 / Outlook.com
```
IMAP: outlook.office365.com:993 (SSL)
SMTP: smtp.office365.com:587 (STARTTLS)
```

### Yahoo Mail
```
IMAP: imap.mail.yahoo.com:993 (SSL)
SMTP: smtp.mail.yahoo.com:587 (STARTTLS)
```

### Generic cPanel Hosting
```
IMAP: mail.<domain>:993 (SSL)
SMTP: mail.<domain>:587 (STARTTLS)
```
