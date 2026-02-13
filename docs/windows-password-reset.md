# Windows Password & PIN Reset

How to get past a forgotten Windows login when on-site at a client.

---

## Quick Reference

| Situation | Solution |
|---|---|
| Client has Microsoft account | "I forgot my PIN" on lock screen, or reset at account.live.com |
| Forgot PIN but knows password | Click "Sign-in options" on lock screen, choose Password |
| Local account, no password known | chntpw from Linux USB to blank the password |
| No access at all | Utilman.exe trick from Windows recovery/install USB |
| Domain-joined machine | Domain admin resets password via Active Directory |
| BitLocker enabled | Need recovery key first — check Microsoft account or Azure AD |

---

## Method 1: Microsoft Account Password Reset

If the Windows account is tied to a Microsoft account (most consumer machines):

1. On the lock screen, click **"I forgot my PIN"**
2. It prompts for the Microsoft account password
3. Set a new PIN

If they don't know the Microsoft account password either:
- Go to `account.live.com` on your phone/laptop
- Click "Forgot password"
- Reset via recovery email or phone number

---

## Method 2: Sign-In Options

On the Windows lock screen, click the **"Sign-in options"** icon (key shape).
Options may include:
- PIN
- Password
- Fingerprint
- Windows Hello face

Clients often remember one but not the other.

---

## Method 3: chntpw — Offline Password Reset (Local Accounts)

Resets the local account password by editing the SAM database directly from
Linux. Works when the machine uses a local account (not Microsoft account).

### Install

```bash
yay -S chntpw
```

### Usage

Boot from a Linux USB or mount the Windows drive:

```bash
# Find the Windows partition
sudo fdisk -l

# Mount it
sudo mkdir -p /mnt/win
sudo mount /dev/sda3 /mnt/win    # adjust partition as needed

# List all Windows users
sudo chntpw -l /mnt/win/Windows/System32/config/SAM

# Reset a specific user's password (blanks it)
sudo chntpw -u Administrator /mnt/win/Windows/System32/config/SAM
# Select option 1: "Clear (blank) user password"
# Then q to quit, y to save

# Unmount
sudo umount /mnt/win
```

Reboot into Windows — password is now blank. Windows will bypass PIN and fall
back to password auth (which is now empty).

---

## Method 4: Utilman.exe Trick (Windows Install/Recovery USB)

Works on local accounts. Replaces the Accessibility shortcut on the lock screen
with a command prompt.

1. Boot from a Windows install USB or recovery drive
2. Choose **Repair your computer** > **Troubleshoot** > **Command Prompt**
3. Run:
   ```cmd
   move C:\Windows\System32\utilman.exe C:\Windows\System32\utilman.exe.bak
   copy C:\Windows\System32\cmd.exe C:\Windows\System32\utilman.exe
   ```
4. Reboot normally into Windows
5. On the lock screen, click the **Accessibility icon** (bottom right corner)
   — this now opens cmd.exe
6. Reset the password:
   ```cmd
   net user Administrator NewPassword123
   net user <username> NewPassword123
   ```
7. Log in with the new password
8. Restore the original utilman:
   ```cmd
   move C:\Windows\System32\utilman.exe.bak C:\Windows\System32\utilman.exe
   ```

---

## Method 5: Domain-Joined Machines

If the machine is joined to an Active Directory domain:
- The domain admin can reset the user's password from **Active Directory Users
  and Computers** (ADUC) or PowerShell:
  ```powershell
  Set-ADAccountPassword -Identity username -Reset -NewPassword (ConvertTo-SecureString "NewPass123!" -AsPlainText -Force)
  ```
- No physical access to the machine needed

---

## BitLocker Warning

If the drive is BitLocker encrypted, you **cannot** mount the drive from Linux
or use the utilman trick without the recovery key.

**Where to find the BitLocker recovery key:**
- Client's Microsoft account: `account.microsoft.com/devices/recoverykey`
- Azure AD / Intune (business machines): IT admin can retrieve it
- Printed copy from when BitLocker was enabled
- USB drive used during BitLocker setup
- Active Directory (if configured to store keys)

Without the recovery key and BitLocker enabled, the only option is Microsoft
account password reset via `account.live.com`.

---

## WiFi Password Recovery (While You're At It)

Since you're on the Windows machine, grab the WiFi passwords too:

```cmd
:: List saved WiFi networks
netsh wlan show profiles

:: Show password for a specific network
netsh wlan show profile name="NetworkName" key=clear
```

The password is under **Key Content**.

From Linux (if system uses iwd):
```bash
sudo sh -c 'grep -H Passphrase /var/lib/iwd/*.psk'
```
