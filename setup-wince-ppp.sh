#!/bin/bash
# =============================================================================
# setup-wince-ppp.sh
# Sets up a Raspberry Pi as a PPP internet gateway for a Windows CE device
# connected via serial port (USB-to-serial adapter).
#
# Tested on: Raspberry Pi OS (Debian Bookworm), HP 320LX (Windows CE)
# =============================================================================

set -euo pipefail

# --- Colour output helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# --- Must run as root ---
[[ $EUID -eq 0 ]] || die "Please run this script as root: sudo $0"

# =============================================================================
# CONFIGURATION — edit these if needed
# =============================================================================
SERIAL_PORT="${SERIAL_PORT:-ttyUSB0}"          # USB-serial adapter device
BAUD_RATE="${BAUD_RATE:-19200}"                 # Baud rate for HP 320LX
PPP_LOCAL_IP="${PPP_LOCAL_IP:-192.168.99.1}"   # Pi PPP interface IP
PPP_REMOTE_IP="${PPP_REMOTE_IP:-192.168.99.2}" # Windows CE device IP
DNS1="${DNS1:-8.8.8.8}"
DNS2="${DNS2:-8.8.4.4}"

# Detect the default outbound network interface
DEFAULT_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
if [[ -z "$DEFAULT_IFACE" ]]; then
    die "Could not detect default network interface. Set it manually in this script."
fi
info "Detected default network interface: $DEFAULT_IFACE"

# =============================================================================
# STEP 1 — Check serial device exists
# =============================================================================
info "Checking for serial device /dev/$SERIAL_PORT ..."
if [[ ! -c "/dev/$SERIAL_PORT" ]]; then
    die "/dev/$SERIAL_PORT not found. Is the USB-serial adapter plugged in?"
fi
info "Found /dev/$SERIAL_PORT"

# =============================================================================
# STEP 2 — Install required packages
# =============================================================================
info "Updating package lists ..."
apt-get update -qq || die "apt-get update failed"

info "Installing ppp and iptables-persistent ..."
# Pre-answer the iptables-persistent prompts so it doesn't block
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt-get install -y ppp iptables-persistent || die "Package installation failed"

# Disable mgetty if it is installed and running — it will conflict with pppd
if systemctl list-units --all | grep -q "mgetty@${SERIAL_PORT}.service"; then
    info "Disabling mgetty@${SERIAL_PORT} to prevent port conflicts ..."
    systemctl stop    "mgetty@${SERIAL_PORT}.service" 2>/dev/null || true
    systemctl disable "mgetty@${SERIAL_PORT}.service" 2>/dev/null || true
fi

# =============================================================================
# STEP 3 — Enable IP forwarding
# =============================================================================
info "Enabling IP forwarding ..."
SYSCTL_CONF="/etc/sysctl.d/99-ipforward.conf"
echo "net.ipv4.ip_forward=1" > "$SYSCTL_CONF"
sysctl -p "$SYSCTL_CONF" || die "Failed to apply sysctl settings"

# =============================================================================
# STEP 4 — Write the chat script
# =============================================================================
info "Writing /etc/ppp/chat-wince ..."
cat > /etc/ppp/chat-wince << 'EOF'
ABORT BUSY
ABORT ERROR
CLIENT CLIENTSERVER
EOF
chmod 644 /etc/ppp/chat-wince

# =============================================================================
# STEP 5 — Write the pppd peers file
# =============================================================================
info "Writing /etc/ppp/peers/wince ..."
cat > /etc/ppp/peers/wince << EOF
/dev/$SERIAL_PORT
$BAUD_RATE
connect "/usr/sbin/chat -v -f /etc/ppp/chat-wince"
noauth
nobsdcomp
nodeflate
novjccomp
nopcomp
noaccomp
noipv6
nodetach
ms-dns $DNS1
ms-dns $DNS2
${PPP_LOCAL_IP}:${PPP_REMOTE_IP}
nodefaultroute
debug
connect-delay 5000
passive
EOF
chmod 640 /etc/ppp/peers/wince

# =============================================================================
# STEP 6 — Configure NAT / iptables
# =============================================================================
info "Configuring iptables NAT rules ..."

# Flush any existing rules that might conflict
iptables -t nat -D POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
iptables        -D FORWARD     -i ppp0             -j ACCEPT     2>/dev/null || true

iptables -t nat -A POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE \
    || die "Failed to add MASQUERADE rule"
iptables        -A FORWARD     -i ppp0             -j ACCEPT \
    || die "Failed to add FORWARD rule"

info "Saving iptables rules ..."
netfilter-persistent save || die "Failed to save iptables rules"

# =============================================================================
# STEP 7 — Create the systemd service
# =============================================================================
info "Creating systemd service ppp-wince ..."
cat > /etc/systemd/system/ppp-wince.service << 'EOF'
[Unit]
Description=PPP Server for Windows CE
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
ExecStart=/usr/sbin/pppd call wince
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload      || die "systemctl daemon-reload failed"
systemctl enable ppp-wince   || die "Failed to enable ppp-wince service"
systemctl restart ppp-wince  || die "Failed to start ppp-wince service"

# =============================================================================
# STEP 8 — Verify service started
# =============================================================================
info "Waiting for ppp-wince service to settle ..."
sleep 3
if systemctl is-active --quiet ppp-wince; then
    info "ppp-wince service is running"
else
    error "ppp-wince service is not running. Check: journalctl -u ppp-wince"
    systemctl status ppp-wince --no-pager || true
    exit 1
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Serial port  : /dev/$SERIAL_PORT @ ${BAUD_RATE} baud"
echo "  Pi PPP IP    : $PPP_LOCAL_IP"
echo "  CE device IP : $PPP_REMOTE_IP"
echo "  NAT via      : $DEFAULT_IFACE"
echo ""
echo "  To monitor the connection:"
echo "    sudo journalctl -u ppp-wince -f"
echo ""
echo "  To test once the CE device connects:"
echo "    ping $PPP_REMOTE_IP"
echo ""
echo "  See README-HP320LX.md for instructions on configuring the HP 320LX."
echo ""
