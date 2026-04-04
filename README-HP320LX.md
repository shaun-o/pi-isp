# HP 320LX — Internet via Serial Connection
## Connecting to the Raspberry Pi PPP Gateway

This guide explains how to configure your HP 320LX (Windows CE) to connect
to the internet through a Raspberry Pi using a direct serial cable connection.

---

## Prerequisites

- HP 320LX with its serial cable connected to the Raspberry Pi
- The Raspberry Pi setup script has been run successfully
- ActiveSync / PC Link disabled on the serial port (see step 1 below)

---

## Step 1 — Disable PC Link on the Serial Port

By default, Windows CE uses the serial port for ActiveSync synchronisation
with a PC. This must be disabled before the port can be used for networking.

1. Tap **Start → Programs → Communication → PC Link**
   (may also appear as **ActiveSync** depending on ROM version)
2. Find the option **Allow connection to PC when device is attached**
   (or similar wording)
3. **Uncheck / disable** this option
4. Tap **OK**

If you skip this step, the device will send ActiveSync handshake data instead
of PPP traffic and the connection will fail.

---

## Step 2 — Create a New Network Connection

1. Tap **Start → Programs → Communication → Remote Networking**
2. Double-tap **Make New Connection**
3. Give the connection a name, e.g. `Raspberry Pi`
4. For the connection type, select **Direct Connection**
5. Tap **Next**
6. Select the serial port — this will be **COM1** on the HP 320LX
7. Tap **Finish**

> **Important:** Use **Direct Connection**, not a modem dial-up connection.
> A dial-up connection will send AT modem commands which will not work
> with this setup.

---

## Step 3 — Configure the Connection

After creating the connection:

1. In the Remote Networking folder, tap and hold (long press) on your
   new connection icon
2. Select **Properties** from the menu
3. Tap **Configure** or **Port Settings**
4. Set the baud rate to **19200**
5. Set data bits to **8**, parity to **None**, stop bits to **1**
6. Tap **OK**

---

## Step 4 — Connect

1. In the Remote Networking folder, double-tap your connection icon
2. A connection dialog will appear — tap **Connect**
3. The device should show a **Connected** status after a few seconds
4. The Raspberry Pi will assign the IP address **192.168.99.2** to the device

---

## Step 5 — Configure Internet Explorer

Once connected, open Pocket Internet Explorer. Some versions of Windows CE
may need the connection configured as the default internet connection:

1. Tap **Start → Settings → Connections**
2. Set your new connection as the default dial-up or internet connection
3. Open **Pocket Internet Explorer**
4. Try browsing to a plain HTTP site — modern HTTPS sites may not work
   due to the outdated SSL/TLS support in Windows CE

---

## Troubleshooting

**"No carrier detected" or immediate disconnection**
- Make sure you selected Direct Connection, not dial-up
- Check that PC Link / ActiveSync is disabled on the serial port
- Check the serial cable contacts are clean and fully seated

**Connected but no internet**
- Verify the Raspberry Pi has internet access itself
- Check NAT is configured on the Pi: `sudo iptables -t nat -L`
- Try pinging the Pi from the CE device: ping 192.168.99.1

**Connection drops after a short time**
- This can be caused by the CE device timing out due to inactivity
- Check the Raspberry Pi logs: `sudo journalctl -u ppp-wince -f`

**HTTPS sites don't load**
- This is expected — Windows CE uses very old SSL/TLS which is rejected
  by modern websites
- Use plain HTTP sites where possible, or set up a proxy on the Pi
  to handle modern web content

---

## Network Details

| Item            | Value           |
|-----------------|-----------------|
| Raspberry Pi IP | 192.168.99.1    |
| HP 320LX IP     | 192.168.99.2    |
| DNS Server      | 8.8.8.8         |
| Baud Rate       | 19200           |
| Connection Type | Direct (PPP)    |

---

## Reconnecting

The Raspberry Pi automatically waits for a new connection whenever the
previous one drops. Simply tap your connection icon on the HP 320LX to
reconnect at any time.
