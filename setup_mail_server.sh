#!/bin/bash
# =============================================================================
# Vintage Device Mail Server Setup Script
# Sets up Postfix + Dovecot + Fetchmail on Raspberry Pi OS (Debian-based)
# Relays outbound mail via AOL, fetches inbound mail from AOL via fetchmail
# Serves plain POP3/IMAP on LAN for vintage devices (no SSL required)
# =============================================================================

set -e

# --- Colours ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Root check ---------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash $0"
fi

REAL_USER="${SUDO_USER:-$(logname)}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo ""
echo "=================================================="
echo "  Vintage Device Mail Server - Setup Script"
echo "=================================================="
echo ""
info "Running as root, configuring for user: $REAL_USER"
echo ""

# --- Gather information -------------------------------------------------------
info "Please provide the following details."
echo ""

read -rp "Your AOL email address (e.g. you@aol.com): " AOL_EMAIL
while [[ -z "$AOL_EMAIL" ]]; do
  warn "AOL email cannot be empty."
  read -rp "Your AOL email address: " AOL_EMAIL
done

read -rsp "Your AOL app password (input hidden): " AOL_APP_PASSWORD
echo ""
while [[ -z "$AOL_APP_PASSWORD" ]]; do
  warn "App password cannot be empty."
  read -rsp "Your AOL app password: " AOL_APP_PASSWORD
  echo ""
done

# Detect LAN subnet automatically
DETECTED_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
DETECTED_SUBNET=$(echo "$DETECTED_IP" | sed 's/\.[0-9]*\/[0-9]*/\.0\/24/')
echo ""
info "Detected subnet: $DETECTED_SUBNET"
read -rp "LAN subnet for Postfix mynetworks [$DETECTED_SUBNET]: " LAN_SUBNET
LAN_SUBNET="${LAN_SUBNET:-$DETECTED_SUBNET}"

HOSTNAME=$(hostname)
echo ""
info "Using hostname: $HOSTNAME"
echo ""

# --- Install packages ---------------------------------------------------------
info "Updating package lists and installing packages..."
apt-get update -qq
apt-get install -y postfix libsasl2-modules dovecot-core dovecot-pop3d dovecot-imapd fetchmail alpine mailutils telnet 2>&1 | grep -E "^(Setting up|Unpacking|Get:)" || true
success "Packages installed."

# --- Configure Postfix --------------------------------------------------------
info "Configuring Postfix..."

# Ensure Maildir is set as delivery method
postconf -e "home_mailbox = Maildir/"

# Inbound: no TLS required from LAN clients
postconf -e "smtpd_tls_security_level = none"
postconf -e "inet_interfaces = all"
postconf -e "mynetworks = 127.0.0.0/8 $LAN_SUBNET"

# Outbound: relay via AOL with TLS
postconf -e "relayhost = [smtp.aol.com]:587"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Sender rewriting so AOL accepts mail from local users
postconf -e "sender_canonical_maps = hash:/etc/postfix/sender_canonical"
postconf -e "smtp_generic_maps = hash:/etc/postfix/generic"

# Write AOL credentials
cat > /etc/postfix/sasl_passwd <<EOF
[smtp.aol.com]:587   ${AOL_EMAIL}:${AOL_APP_PASSWORD}
EOF
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd.db

# Write sender rewrite maps
cat > /etc/postfix/sender_canonical <<EOF
${REAL_USER}@${HOSTNAME}    ${AOL_EMAIL}
root@${HOSTNAME}             ${AOL_EMAIL}
EOF

cat > /etc/postfix/generic <<EOF
${REAL_USER}@${HOSTNAME}    ${AOL_EMAIL}
root@${HOSTNAME}             ${AOL_EMAIL}
EOF

postmap /etc/postfix/sender_canonical
postmap /etc/postfix/generic

systemctl restart postfix
success "Postfix configured and restarted."

# --- Configure Dovecot --------------------------------------------------------
info "Configuring Dovecot..."

# 10-mail.conf: fix Debian mbox defaults to maildir
MAIL_CONF="/etc/dovecot/conf.d/10-mail.conf"

# Replace the Debian defaults block
sed -i 's/^mail_driver = mbox/mail_driver = maildir/' "$MAIL_CONF"
sed -i '/^mail_path = %{home}\/mail/d' "$MAIL_CONF"
sed -i '/^mail_inbox_path = \/var\/mail\/%{user}/d' "$MAIL_CONF"

# Add mail_path after mail_driver line if not already present
if ! grep -q "^mail_path = ~/Maildir" "$MAIL_CONF"; then
  sed -i '/^mail_driver = maildir/a mail_path = ~/Maildir' "$MAIL_CONF"
fi

# Set namespace location using Dovecot 2.4 syntax
# Remove any old location/mail_location lines we may have added
sed -i '/^  location = /d' "$MAIL_CONF"
sed -i '/^  mail_location = /d' "$MAIL_CONF"
sed -i '/^mail_location = /d' "$MAIL_CONF"

# Set mail_driver and mail_path inside namespace inbox block if not already there
if ! grep -q "mail_driver = maildir" "$MAIL_CONF"; then
  sed -i '/inbox = yes/a\  mail_driver = maildir\n  mail_path = ~/Maildir' "$MAIL_CONF"
fi

# 10-ssl.conf: disable SSL (plain LAN connections only)
SSL_CONF="/etc/dovecot/conf.d/10-ssl.conf"
sed -i 's/^ssl = yes/ssl = no/' "$SSL_CONF"
sed -i 's/^ssl = required/ssl = no/' "$SSL_CONF"
if ! grep -q "^ssl = no" "$SSL_CONF"; then
  echo "ssl = no" >> "$SSL_CONF"
fi

# 10-auth.conf: allow plain auth (Dovecot 2.4 syntax)
AUTH_CONF="/etc/dovecot/conf.d/10-auth.conf"
# Remove old setting name if present
sed -i '/^disable_plaintext_auth/d' "$AUTH_CONF"
# Add correct 2.4 setting if not present
if ! grep -q "^auth_allow_cleartext" "$AUTH_CONF"; then
  echo "auth_allow_cleartext = yes" >> "$AUTH_CONF"
fi
# Ensure login mechanism is available
sed -i 's/^auth_mechanisms = plain$/auth_mechanisms = plain login/' "$AUTH_CONF"

# Create Maildir structure for the user
if [ ! -d "$REAL_HOME/Maildir" ]; then
  mkdir -p "$REAL_HOME/Maildir"/{new,cur,tmp}
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/Maildir"
  success "Created Maildir for $REAL_USER."
else
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/Maildir"
  success "Maildir already exists, ownership confirmed."
fi

systemctl restart dovecot
success "Dovecot configured and restarted."

# --- Configure Fetchmail ------------------------------------------------------
info "Configuring Fetchmail..."

FETCHMAILRC="$REAL_HOME/.fetchmailrc"

cat > "$FETCHMAILRC" <<EOF
set daemon 300

poll imap.aol.com
    proto IMAP
    port 993
    user "${AOL_EMAIL}"
    password "${AOL_APP_PASSWORD}"
    ssl
    sslcertck
    keep
    no idle
    mda "/usr/lib/dovecot/deliver -d %T"
EOF

chmod 600 "$FETCHMAILRC"
chown "$REAL_USER:$REAL_USER" "$FETCHMAILRC"

# Add fetchmail to user crontab if not already there
CRON_LINE="@reboot fetchmail"
EXISTING_CRON=$(crontab -u "$REAL_USER" -l 2>/dev/null || true)
if ! echo "$EXISTING_CRON" | grep -q "fetchmail"; then
  (echo "$EXISTING_CRON"; echo "$CRON_LINE") | crontab -u "$REAL_USER" -
  success "Added fetchmail to $REAL_USER crontab."
else
  success "Fetchmail already in crontab."
fi

success "Fetchmail configured."

# --- Configure Alpine ---------------------------------------------------------
info "Configuring Alpine..."

PINERC="$REAL_HOME/.pinerc"

if [ ! -f "$PINERC" ]; then
  touch "$PINERC"
  chown "$REAL_USER:$REAL_USER" "$PINERC"
fi

# Set inbox path to use local IMAP
if grep -q "^inbox-path=" "$PINERC"; then
  sed -i "s|^inbox-path=.*|inbox-path={localhost/imap/novalidate-cert}INBOX|" "$PINERC"
else
  echo "inbox-path={localhost/imap/novalidate-cert}INBOX" >> "$PINERC"
fi

# Set SMTP server to localhost
if grep -q "^smtp-server=" "$PINERC"; then
  sed -i "s|^smtp-server=.*|smtp-server=localhost|" "$PINERC"
else
  echo "smtp-server=localhost" >> "$PINERC"
fi

# Set sort to newest first
if grep -q "^sort-key=" "$PINERC"; then
  sed -i "s|^sort-key=.*|sort-key=Arrival/Reverse|" "$PINERC"
else
  echo "sort-key=Arrival/Reverse" >> "$PINERC"
fi

# Set mail check interval to 5 minutes
if grep -q "^mail-check-interval=" "$PINERC"; then
  sed -i "s|^mail-check-interval=.*|mail-check-interval=300|" "$PINERC"
else
  echo "mail-check-interval=300" >> "$PINERC"
fi

chown "$REAL_USER:$REAL_USER" "$PINERC"
success "Alpine configured."

# --- Start fetchmail as user --------------------------------------------------
info "Starting fetchmail daemon as $REAL_USER..."
su - "$REAL_USER" -c "fetchmail --quit 2>/dev/null || true; fetchmail" 2>/dev/null || warn "Could not start fetchmail now — it will start on next reboot via crontab."

# --- Summary ------------------------------------------------------------------
echo ""
echo "=================================================="
echo -e "${GREEN}  Setup Complete!${NC}"
echo "=================================================="
echo ""
PIIP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "  Your Pi's LAN IP : $PIIP"
echo ""
echo "  Vintage device settings:"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │ SMTP  host: $PIIP   port: 25   SSL: none   │"
echo "  │ POP3  host: $PIIP   port: 110  SSL: none   │"
echo "  │ IMAP  host: $PIIP   port: 143  SSL: none   │"
echo "  │ Username  : $REAL_USER                           │"
echo "  │ Password  : your Linux user password        │"
echo "  └─────────────────────────────────────────────┘"
echo ""
echo "  To test: run 'alpine' and press I for inbox"
echo "  To fetch mail now: fetchmail -v --daemon 0"
echo ""
echo "  See MAIL_INSTRUCTIONS.md for non-scriptable steps"
echo "  and troubleshooting guidance."
echo ""
