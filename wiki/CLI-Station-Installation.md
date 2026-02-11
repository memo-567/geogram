# CLI Station Installation

How to deploy a Geogram station server on a Linux machine.

A Geogram CLI station is a self-contained network node that provides:

- **NOSTR relay** — stores and forwards Nostr events
- **WebSocket hub** — real-time messaging and P2P signaling for connected devices
- **Tile cache** — proxies and caches OpenStreetMap tiles for offline map use
- **STUN server** — NAT traversal for WebRTC peer connections
- **Blossom file hosting** — file uploads and downloads with hash-addressed storage
- **Update mirror** — mirrors Geogram release binaries from GitHub
- **Optional SMTP** — send email via upstream relay with DKIM signing

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| OS | Linux (Ubuntu 22.04+ / Debian 12+ recommended) |
| RAM | 1 GB minimum |
| Disk | 20 GB minimum (tiles and file storage grow over time) |
| Domain | A domain name with an A record pointing to the server IP |
| SSH | Root access to the server |

### Required Ports

| Port | Protocol | Service |
|------|----------|---------|
| 80 | TCP | HTTP (required for Let's Encrypt) |
| 443 | TCP | HTTPS |
| 3478 | UDP | STUN server |
| 2525 | TCP | SMTP (optional) |

---

## 1. DNS Setup

Create an **A record** for your domain pointing to the server's public IP:

```
yourstation.example.com.  IN  A  203.0.113.10
```

If you plan to enable email, you'll also need MX, SPF, DKIM, and DMARC records — see [Optional: Email](#7-optional-email) below.

---

## 2. Get the Binary

### Option A: Download prebuilt (recommended)

Download the prebuilt `geogram-cli` Linux x64 binary from:

**https://geogram.radio/#downloads**

```bash
ssh root@yourstation.example.com
mkdir -p /root/geogram
cd /root/geogram
# Upload or download the binary here
chmod +x geogram-cli
```

### Option B: Build from source

On your build machine (requires Dart SDK >= 3.10, bundled with Flutter SDK):

```bash
git clone https://github.com/geograms/geogram.git
cd geogram
./launch-cli.sh --build-only
```

Upload the compiled binary to the server:

```bash
scp build/geogram-cli root@yourstation.example.com:/root/geogram/geogram-cli
```

---

## 3. First-Time Setup

On first launch, `geogram-cli` runs an interactive setup wizard that creates all required directories and configuration files.

```bash
cd /root/geogram
./geogram-cli --data-dir=/root/geogram station
```

The wizard will:
- Create subdirectories (`ssl/`, `logs/`, `tiles/`, `devices/`)
- Generate the station's NOSTR keypair and callsign
- Prompt for station name, description, location, SSL domain, and network role
- Write `station_config.json` and `config.json`

---

## 4. SSL/TLS (Automatic)

SSL is fully automatic — no external tools like certbot are needed. When `enableSsl` is `true` and a `sslDomain` is configured (both set during the setup wizard), the station will:

1. Serve ACME challenge tokens at `/.well-known/acme-challenge/` on port 80
2. Request a certificate from Let's Encrypt on startup
3. Store `fullchain.pem` and `privkey.pem` in the `ssl/` directory
4. Start HTTPS on port 443
5. Auto-renew the certificate

The only prerequisite is that **port 80 must be open** and the domain must point to the server before starting.

---

## 5. Systemd Service

Create `/etc/systemd/system/geogram-station.service`:

```ini
[Unit]
Description=Geogram Station Server
Documentation=https://github.com/geograms/geogram
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/geogram
ExecStart=/root/geogram/geogram-cli --data-dir=/root/geogram --auto-station

Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60

NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/root/geogram

StandardOutput=journal
StandardError=journal
SyslogIdentifier=geogram-station

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
systemctl daemon-reload
systemctl enable geogram-station
systemctl start geogram-station
```

### Management Commands

```bash
systemctl status geogram-station       # Check status
journalctl -u geogram-station -f       # Follow logs
systemctl restart geogram-station      # Restart
systemctl stop geogram-station         # Stop
```

---

## 6. Firewall

```bash
apt install -y ufw

ufw allow 22/tcp     # SSH (do this first!)
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 3478/udp   # STUN

# Optional:
# ufw allow 2525/tcp  # SMTP

ufw enable
ufw status
```

---

## 7. Optional: Email

To enable SMTP support, edit `station_config.json`:

```json
{
  "smtpEnabled": true,
  "smtpServerEnabled": true,
  "smtpPort": 2525,
  "smtpRelayHost": "smtp-relay.brevo.com",
  "smtpRelayPort": 587,
  "smtpRelayUsername": "your-api-key@smtp-relay.brevo.com",
  "smtpRelayPassword": "your-smtp-password",
  "smtpRelayStartTls": true
}
```

You'll also need DNS records for email:

```
; MX record
yourstation.example.com.  IN  MX  10  yourstation.example.com.

; SPF
yourstation.example.com.  IN  TXT  "v=spf1 a mx ~all"

; DKIM (generate key: openssl genrsa 2048 | openssl rsa -pubout -outform DER | base64 -w0)
geogram._domainkey.yourstation.example.com.  IN  TXT  "v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY"

; DMARC
_dmarc.yourstation.example.com.  IN  TXT  "v=DMARC1; p=none"
```

Open the SMTP port: `ufw allow 2525/tcp`

---

## 8. Verify the Installation

### HTTP Status

```bash
curl http://yourstation.example.com/api/status
```

Expected response:

```json
{
  "station_mode": true,
  "callsign": "X3ABCD",
  "name": "My Station",
  "version": "1.17.3",
  "connected_devices": 0,
  "tile_server_enabled": true,
  "ssl_enabled": true
}
```

### WebSocket

```bash
# Install wscat: npm install -g wscat
wscat -c wss://yourstation.example.com/
```

### NIP-05 Verification

```bash
curl https://yourstation.example.com/.well-known/nostr.json
```

---

## 9. Node Stations

A station can run as a **node** that connects upstream to a root station instead of operating independently.

In `station_config.json`:

```json
{
  "stationRole": "node",
  "parentStationUrl": "wss://parent.example.com"
}
```

The node will connect to the parent station via WebSocket and participate in the network.

---

## Configuration Reference

After the setup wizard, you can fine-tune settings by editing `/root/geogram/station_config.json`:

| Field | Default | Description |
|-------|---------|-------------|
| `httpPort` | 8080 | HTTP listening port |
| `enabled` | false | Enable the station server |
| `name` | — | Station display name |
| `description` | — | Station description |
| `location` | — | Human-readable location |
| `latitude` / `longitude` | — | Coordinates |
| `stationRole` | "root" | `"root"` or `"node"` |
| `parentStationUrl` | null | Parent station URL (node only) |
| `tileServerEnabled` | true | Enable tile caching proxy |
| `maxZoomLevel` | 15 | Max tile zoom level to cache |
| `maxCacheSizeMB` | 500 | Tile cache size limit (MB) |
| `stunServerEnabled` | true | Enable STUN server |
| `blossomMaxStorageMb` | 1024 | File storage limit (MB) |
| `blossomMaxFileMb` | 10 | Max single file size (MB) |
| `enableSsl` | false | Enable HTTPS |
| `sslDomain` | — | Domain for Let's Encrypt |
| `sslAutoRenew` | true | Auto-renew certificates |
| `updateMirrorEnabled` | true | Mirror release binaries |

---

## Directory Structure

```
/root/geogram/
├── geogram-cli              # Station binary
├── config.json              # Station identity/profile
├── station_config.json      # Server configuration
├── station.db               # SQLite database
├── libs/                    # Bundled libraries
├── ssl/
│   ├── fullchain.pem        # SSL certificate chain
│   ├── privkey.pem          # SSL private key
│   └── .well-known/
│       └── acme-challenge/
├── tiles/                   # Cached map tiles
├── devices/                 # Connected device data
├── blossom/                 # Uploaded files (hash-addressed)
└── logs/
    ├── crash.txt
    └── {year}/
        └── log-{date}.txt
```

---

## Updating

1. Download the new `geogram-cli` binary (or rebuild from source)
2. Upload it to `/root/geogram/geogram-cli`
3. Restart: `systemctl restart geogram-station`

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Station status (JSON) |
| GET | `/api/geoip` | GeoIP lookup for client IP |
| GET | `/api/clients` | List connected devices |
| GET | `/api/updates/latest` | Latest mirrored release |
| GET | `/tiles/{z}/{x}/{y}.png` | Map tile proxy/cache |
| GET | `/.well-known/nostr.json` | NIP-05 identity verification |
| POST | `/blossom/upload` | Upload a file |
| GET | `/blossom/{hash}` | Download a file by hash |
| WebSocket | `/` | Real-time messaging, NOSTR relay, P2P signaling |
| UDP 3478 | — | STUN server |
