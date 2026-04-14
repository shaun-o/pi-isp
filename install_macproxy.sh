#!/bin/bash
# Macproxy installer for Raspberry Pi OS (Bookworm)
# Sets up a vintage web proxy for old devices like the HP 320LX

set -e

echo "=== Macproxy Installer ==="

# Install system dependencies
echo "[1/5] Installing system packages..."
sudo apt install -y python3-full git

# Clone macproxy
echo "[2/5] Cloning macproxy..."
cd ~
if [ -d "macproxy" ]; then
    echo "macproxy folder already exists, pulling latest..."
    cd macproxy && git pull
else
    git clone https://github.com/rdmark/macproxy.git
    cd macproxy
fi

# Create virtual environment
echo "[3/5] Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "[4/5] Installing Python dependencies..."
pip install -r requirements.txt

deactivate

# Install systemd service
echo "[5/5] Setting up systemd service..."

# Find the main script
if [ -f "proxy.py" ]; then
    SCRIPT="proxy.py"
elif [ -f "macproxy.py" ]; then
    SCRIPT="macproxy.py"
else
    echo "ERROR: Could not find main proxy script. Check the macproxy folder contents."
    exit 1
fi

INSTALL_DIR="$(pwd)"
CURRENT_USER="$(whoami)"

sudo tee /etc/systemd/system/macproxy.service > /dev/null <<EOF
[Unit]
Description=Macproxy vintage web proxy
After=network.target

[Service]
User=${CURRENT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python3 ${SCRIPT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable macproxy
sudo systemctl start macproxy

echo ""
echo "=== Done! ==="
echo "Macproxy is running on 192.168.99.1:5001"
echo "See BROWSER_README.md for how to configure your HP 320LX."
