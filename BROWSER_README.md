# HP 320LX Web Browsing via Proxy

Your Raspberry Pi is running a proxy server that handles modern HTTPS
websites on behalf of your 320LX, letting you browse the web again.

## Proxy Details

| Setting  | Value         |
|----------|---------------|
| Address  | 192.168.99.1  |
| Port     | 5001          |
| Type     | HTTP          |

---

## Configuring Internet Explorer on Windows CE

1. Open **Internet Explorer**
2. Tap **View** → **Options**
3. Tap the **Connection** tab
4. Check **Access the Internet via a proxy server**
5. In the **Address** field enter: `192.168.99.1`
6. In the **Port** field enter: `5001`
7. Tap **OK**

---

## Testing It Works

Try these URLs — they are good starting points for vintage browsers:

- http://example.com — Simple test page, should load instantly
- http://frogfind.com — Search engine designed for vintage browsers
- http://68k.news — News headlines in plain HTML
- http://theoldnet.com — Retro-friendly web directory
- http://en.m.wikipedia.org — Mobile Wikipedia (simpler layout)
- http://lite.cnn.com — Lightweight CNN news

---

## Tips

- **Always use http://** not https:// in the address bar. The proxy
  handles the secure connection to the website for you.
- **Avoid JavaScript-heavy sites** like modern social media — the
  browser simply cannot run them regardless of the proxy.
- **Images may be slow** — consider turning off image loading in the
  browser options for faster browsing on text-heavy sites.
- If a page fails to load, try prefixing the URL manually:
  `http://192.168.99.1:5001/https://example.com`
  This uses the proxy's direct mode and can work when the normal
  proxy setting doesn't.

---

## Troubleshooting

**Pages won't load at all**
- Check the 320LX is connected to the same network as the Pi
- Ping 192.168.99.1 from the device if possible
- On the Pi, run: `sudo systemctl status macproxy`

**Proxy stops working after Pi reboot**
- It should start automatically. If not, run:
  `sudo systemctl start macproxy`

**Check what the proxy is doing in real time**
- SSH into the Pi and run:
  `journalctl -u macproxy -f`
  You will see each request from the 320LX as it comes in.
