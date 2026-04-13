# Vintage Device Mail Server — Setup Instructions

A guide to the manual steps, configuration reference, and troubleshooting for the Raspberry Pi mail server that serves vintage devices over plain POP3/IMAP and relays outbound mail via AOL.

---

## Before Running the Script

These steps must be completed manually before running `setup_mail_server.sh`.

### 1. Enable 2-Step Verification on your AOL Account

AOL app passwords are only available if 2-Step Verification is active.

1. Go to [login.aol.com](https://login.aol.com) and sign in
2. Click your profile icon → **Account Info**
3. Click **Security** in the left menu
4. Find **2-Step Verification** and enable it
5. Choose your preferred method (SMS, authenticator app, or security key)

### 2. Generate an AOL App Password

1. Return to **Account Info → Security**
2. Scroll down and click **Generate app password**
3. Give it a name (e.g. `raspberry-pi-mail`)
4. Copy the password immediately — **you cannot view it again**
5. Store it somewhere safe before running the script

> **Important:** The app password contains no spaces when you use it, even if it was displayed with spaces. Remove any spaces before entering it into the script.

---

## Running the Script

```bash
sudo bash setup_mail_server.sh
```

The script will ask for:
- Your full AOL email address (e.g. `yourname@aol.com`)
- Your AOL app password
- Your LAN subnet (it will detect this automatically — press Enter to accept)

---

## After Running the Script

### Verify Postfix is Relaying

Send a test email and check the log:

```bash
echo "Test" | mail -s "Test" yourname@aol.com
sudo journalctl -u postfix -n 20 --no-pager
```

Look for `status=sent` in the output. If you see `status=bounced`, check the error message — common causes are listed in the Troubleshooting section.

### Verify Dovecot is Listening

```bash
sudo ss -tlnp | grep dovecot
```

You should see ports **110** (POP3) and **143** (IMAP) listed.

### Test Dovecot IMAP Login

```bash
telnet localhost 143
```

At the prompt type:
```
a1 LOGIN yourusername yourlinuxpassword
a2 LOGOUT
```

You should see `a1 OK Logged in`.

### Verify Fetchmail is Running

```bash
ps aux | grep fetchmail
```

To trigger an immediate poll:

```bash
fetchmail --quit
fetchmail -v --daemon 0
```

Watch for `status=sent` or a message count. Then restart the daemon:

```bash
fetchmail
```

---

## Vintage Device Settings

Use these settings in your vintage device's mail client:

| Setting | Value |
|---|---|
| **SMTP server** | Your Pi's LAN IP (e.g. `192.168.1.x`) |
| **SMTP port** | `25` |
| **SMTP auth** | None |
| **SMTP SSL** | None |
| **POP3 server** | Your Pi's LAN IP |
| **POP3 port** | `110` |
| **IMAP server** | Your Pi's LAN IP |
| **IMAP port** | `143` |
| **Username** | Your Pi Linux username (e.g. `shaun`) |
| **Password** | Your Pi Linux user password |
| **SSL/TLS** | None / Disabled |

To find your Pi's LAN IP:

```bash
ip addr show | grep "inet "
```

Use the `192.168.x.x` address, not `127.0.0.1`.

---

## How the System Works

```
Vintage device
  └─► Pi:25 (plain SMTP, LAN only)
        └─► Postfix
              └─► smtp.aol.com:587 (TLS) — outbound mail

AOL inbox
  └─► Fetchmail polls every 5 min (IMAP/SSL to imap.aol.com:993)
        └─► Dovecot local delivery → ~/Maildir
              └─► Dovecot serves POP3:110 / IMAP:143 (plain, LAN only)
                    └─► Vintage devices & Alpine read mail here
```

---

## Alpine Mail Client Quick Reference

| Key | Action |
|---|---|
| `I` | Go to inbox |
| `C` | Compose new message |
| `N` | Check for new messages |
| `D` | Delete message |
| `R` | Reply |
| `F` | Forward |
| `Q` | Quit |
| `S` → `C` | Setup → Config |
| `?` | Help |

---

## Adding More Subnets for Vintage Devices

If your vintage device is on a different subnet to the Pi (e.g. Pi is on `192.168.1.x` and device is on `192.168.99.x`), add the extra subnet to Postfix:

```bash
sudo vi /etc/postfix/main.cf
```

Find the `mynetworks` line and add the additional subnet:

```
mynetworks = 127.0.0.0/8 192.168.1.0/24 192.168.99.0/24
```

Then restart Postfix:

```bash
sudo systemctl restart postfix
```

---

## Troubleshooting

### Postfix: 550 Mailbox Unavailable

AOL rejected the message because the `From:` address doesn't match your AOL account. The sender rewrite maps should fix this. Verify they are correct:

```bash
cat /etc/postfix/sender_canonical
cat /etc/postfix/generic
```

Both should map your local username to your AOL address. If you edited them, remember to re-hash:

```bash
sudo postmap /etc/postfix/sender_canonical
sudo postmap /etc/postfix/generic
sudo systemctl restart postfix
```

### Postfix: 454 Relay Access Denied

Your device's IP is not in `mynetworks`. Check which IP the device is connecting from in the Postfix log, then add its subnet as described in the Adding More Subnets section above.

### Postfix: Authentication Failed

The AOL app password is wrong or has been revoked. Generate a new one from AOL Account Security settings and update the credentials file:

```bash
sudo vi /etc/postfix/sasl_passwd
```

Update the password, then re-hash and restart:

```bash
sudo postmap /etc/postfix/sasl_passwd
sudo chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
sudo systemctl restart postfix
```

### Dovecot: Permission Denied on Mailbox

Check ownership of the Maildir:

```bash
ls -la ~ | grep Maildir
```

It should be owned by your user. If owned by root:

```bash
sudo chown -R yourusername:yourusername ~/Maildir
```

### Fetchmail: All Messages Already Seen

Fetchmail only fetches unseen messages by default. If you read the messages in AOL webmail first, fetchmail will skip them. To fetch everything including already-read messages (useful for initial setup):

Temporarily add `fetchall` to `~/.fetchmailrc`, run `fetchmail -v --daemon 0`, then remove `fetchall` before restarting the daemon.

### Fetchmail: IDLE Mode Not Polling

If fetchmail logs show `will idle after poll` and new mail isn't arriving, IDLE push mode is not working reliably with AOL. Ensure `no idle` is in your `~/.fetchmailrc` poll block so it uses timer-based polling instead.

### Mail Not Appearing in Alpine

1. Check fetchmail has actually fetched: `ls ~/Maildir/new/ ~/Maildir/cur/`
2. Press `N` in Alpine to check for new messages
3. If Alpine shows a server error, check Dovecot: `sudo journalctl -u dovecot -n 20 --no-pager`

### Checking Logs

| Service | Command |
|---|---|
| Postfix | `sudo journalctl -u postfix -n 50 --no-pager` |
| Dovecot | `sudo journalctl -u dovecot -n 50 --no-pager` |
| Live Postfix | `sudo journalctl -u postfix -f` |
| Mail queue | `mailq` |
| Fetchmail verbose | `fetchmail --quit && fetchmail -v --daemon 0` |

---

## Firewall (Recommended)

Once everything is working, lock down the mail ports so they are only accessible from your LAN and not from the internet:

```bash
sudo ufw allow from 192.168.x.0/24 to any port 25
sudo ufw allow from 192.168.x.0/24 to any port 110
sudo ufw allow from 192.168.x.0/24 to any port 143
sudo ufw deny 25
sudo ufw deny 110
sudo ufw deny 143
sudo ufw enable
```

Replace `192.168.x.0/24` with your actual subnet. If you have multiple subnets (e.g. for different vintage devices), add a `ufw allow` line for each one before the `ufw deny` lines.
