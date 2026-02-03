# Station Server Deployment Guide

How to deploy a Geogram station server on a fresh Linux VPS.
Reference production instance: **p2p.radio**.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [DNS Setup](#3-dns-setup)
4. [Getting the Binary](#4-getting-the-binary)
5. [Server Setup](#5-server-setup)
6. [SSL/TLS with Let's Encrypt](#6-ssltls-with-lets-encrypt)
7. [Systemd Service](#7-systemd-service)
8. [Firewall](#8-firewall)
9. [Using the Deploy Script (Developers)](#9-using-the-deploy-script-developers)
10. [Verification & Testing](#10-verification--testing)
11. [Optional: Email/SMTP](#11-optional-emailsmtp)
12. [Optional: Node Station](#12-optional-node-station)
13. [Maintenance](#13-maintenance)
14. [Endpoints Reference](#14-endpoints-reference)

---

## 1. Introduction

A Geogram station server is a self-contained network node that provides:

- **NOSTR relay** — stores and forwards Nostr events (NIP-01, NIP-05)
- **WebSocket hub** — real-time messaging and P2P signaling for connected devices
- **Tile cache** — proxies and caches OpenStreetMap tiles for offline map use
- **STUN server** — RFC 5389 NAT traversal for WebRTC peer connections
- **Blossom file hosting** — file uploads and downloads with hash-addressed storage
- **Update mirror** — mirrors Geogram release binaries from GitHub
- **Optional SMTP** — send email via an upstream relay with DKIM signing

`p2p.radio` runs as a root station. A station can also run as a **node**, connecting upstream to a root station via `parentStationUrl` (see [Section 12](#12-optional-node-station)).

---

## 2. Prerequisites

| Requirement | Details |
|-------------|---------|
| **OS** | Linux (Ubuntu 22.04+ / Debian 12+ recommended) |
| **RAM** | 1 GB minimum |
| **Disk** | 20 GB minimum (tiles and blossom storage grow over time) |
| **Domain** | A domain name with an A record pointing to the server IP |
| **SSH** | Root access to the server |
| **Build machine** | Dart SDK >= 3.10 (via Flutter SDK 3.38.3+) — only needed if building from source |

### Required Ports

| Port | Protocol | Service |
|------|----------|---------|
| 80 | TCP | HTTP (required for Let's Encrypt ACME challenge) |
| 443 | TCP | HTTPS |
| 3478 | UDP | STUN server |
| 2525 | TCP | SMTP (optional) |

---

## 3. DNS Setup

### Required

Create an **A record** for your domain pointing to the server's public IP:

```
yourstation.example.com.  IN  A  203.0.113.10
```

### Optional (for email)

If you plan to enable SMTP:

```
; MX record — receive mail at the station domain
yourstation.example.com.  IN  MX  10  yourstation.example.com.

; SPF — authorize the station to send mail
yourstation.example.com.  IN  TXT  "v=spf1 a mx ~all"

; DKIM — selector "geogram"
; Generate the public key: openssl genrsa 2048 | openssl rsa -pubout -outform DER | base64 -w0
geogram._domainkey.yourstation.example.com.  IN  TXT  "v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY_HERE"

; DMARC
_dmarc.yourstation.example.com.  IN  TXT  "v=DMARC1; p=none; rua=mailto:admin@yourstation.example.com"
```

---

## 4. Getting the Binary

### Option A: Download prebuilt (recommended)

Download the prebuilt `geogram-cli` Linux x64 binary from:

**https://geogram.radio/#downloads**

```bash
# On the server
mkdir -p /root/geogram
cd /root/geogram
# Upload or download the binary here
chmod +x geogram-cli
```

### Option B: Build from source

On your **build machine** (not the server):

```bash
git clone https://github.com/geograms/geogram.git
cd geogram
./launch-cli.sh --build-only
```

The compiled binary will be at `build/geogram-cli`. Upload it to the server:

```bash
scp build/geogram-cli root@yourstation.example.com:/root/geogram/geogram-cli
```

The build script requires Dart SDK >= 3.10 (bundled with Flutter SDK). It will:
1. Check the Dart SDK version
2. Fetch dependencies (`dart pub get`)
3. Generate embedded assets
4. Compile a standalone executable (`dart compile exe bin/cli.dart`)

You can also use `server-deploy.sh` to automate the full build-and-upload cycle. Edit the variables at the top of the script to point to your server instead of the default `p2p.radio`:

```bash
# In server-deploy.sh, change these lines:
REMOTE_HOST="root@yourstation.example.com"
REMOTE_DIR="/root/geogram"
PORT=80
```

Then run `./server-deploy.sh` — it will build the binary, upload it via SCP, and run the first-time setup wizard if no configuration exists on the server yet. See [Section 9](#9-using-the-deploy-script-developers) for the full walkthrough.

---

## 5. Server Setup

SSH into the server, create the base directory, and place the binary:

```bash
ssh root@yourstation.example.com
mkdir -p /root/geogram
# Upload or copy geogram-cli here
chmod +x /root/geogram/geogram-cli
```

On first launch, `geogram-cli` runs an interactive configuration wizard that will:
- Create all required subdirectories (`ssl/`, `logs/`, `tiles/`, `devices/`)
- Generate the station's NOSTR keypair and callsign
- Prompt for station name, description, location, SSL domain, and network role
- Write `station_config.json` and `config.json` automatically

You can start the wizard manually with:

```bash
cd /root/geogram
./geogram-cli --data-dir=/root/geogram station
```

After the wizard completes, the configuration can be fine-tuned by editing `/root/geogram/station_config.json` directly.

### Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `httpPort` | int | 8080 | HTTP listening port |
| `enabled` | bool | false | Enable the station server |
| `name` | string | — | Station display name |
| `description` | string | — | Station description |
| `location` | string | — | Human-readable location |
| `latitude` | double | — | Latitude coordinate |
| `longitude` | double | — | Longitude coordinate |
| `stationRole` | string | "root" | `"root"` or `"node"` |
| `networkId` | string | — | Network identifier |
| `parentStationUrl` | string | null | Parent station URL (node only) |
| `enableCors` | bool | true | Add CORS headers to responses |
| `httpRequestTimeout` | int | 30000 | Request timeout (ms) |
| `maxConnectedDevices` | int | 100 | Max concurrent WebSocket connections |
| `tileServerEnabled` | bool | true | Enable tile caching proxy |
| `osmFallbackEnabled` | bool | true | Fall back to OSM tile servers |
| `maxZoomLevel` | int | 15 | Max tile zoom level to cache |
| `maxCacheSizeMB` | int | 500 | Tile cache size limit (MB) |
| `nostrRequireAuthForWrites` | bool | true | Require auth to post Nostr events |
| `blossomMaxStorageMb` | int | 1024 | Blossom total storage limit (MB) |
| `blossomMaxFileMb` | int | 10 | Max single file upload size (MB) |
| `stunServerEnabled` | bool | true | Enable STUN server |
| `stunServerPort` | int | 3478 | STUN UDP port |
| `enableSsl` | bool | false | Enable HTTPS |
| `sslDomain` | string | — | Domain for certificate |
| `sslEmail` | string | — | Email for Let's Encrypt notifications |
| `sslAutoRenew` | bool | true | Auto-renew certificates |
| `sslCertPath` | string | null | Custom cert path (overrides default) |
| `sslKeyPath` | string | null | Custom key path (overrides default) |
| `httpsPort` | int | 8443 | HTTPS listening port |
| `updateMirrorEnabled` | bool | true | Mirror Geogram releases from GitHub |
| `updateCheckIntervalSeconds` | int | 120 | How often to poll for new releases |
| `enableAprs` | bool | false | Enable APRS integration |
| `smtpEnabled` | bool | false | Enable email support |
| `smtpServerEnabled` | bool | false | Run SMTP server |
| `smtpPort` | int | 2525 | SMTP server port |
| `smtpRelayHost` | string | — | Upstream SMTP relay hostname |
| `smtpRelayPort` | int | 587 | SMTP relay port |
| `smtpRelayUsername` | string | — | SMTP relay auth username |
| `smtpRelayPassword` | string | — | SMTP relay auth password (encrypted) |
| `smtpRelayStartTls` | bool | true | Use STARTTLS for relay |
| `dkimPrivateKey` | string | — | DKIM RSA private key (base64 PEM) |

---

## 6. SSL/TLS with Let's Encrypt

SSL is fully automatic. No external tools (certbot, etc.) are needed. When `enableSsl` is set to `true` and a `sslDomain` is configured (both handled by the setup wizard), the station will:

1. Serve ACME challenge tokens at `/.well-known/acme-challenge/*` on port 80
2. Request a certificate from Let's Encrypt automatically on startup
3. Store `fullchain.pem` and `privkey.pem` in `{dataDir}/ssl/`
4. Start the HTTPS server on the configured `httpsPort` (default 443)
5. Auto-renew the certificate when `sslAutoRenew` is `true` (the default)

The only prerequisite is that **port 80 must be open** and the domain's A record must point to the server before starting.

---

## 7. Systemd Service

### Install the service

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

### Enable and start

```bash
systemctl daemon-reload
systemctl enable geogram-station
systemctl start geogram-station
```

### Management commands

```bash
systemctl status geogram-station       # Check status
journalctl -u geogram-station -f       # Follow logs
systemctl stop geogram-station         # Stop
systemctl restart geogram-station      # Restart
```

### CLI Flags

| Flag | Description |
|------|-------------|
| `--data-dir=/root/geogram` | Data directory for config, certs, tiles, logs |
| `--auto-station` | Start the station server automatically on launch |
| `station` | Subcommand to start station (alternative to `--auto-station`) |

---

## 8. Firewall

```bash
# Install ufw if not present
apt install -y ufw

# Allow SSH (important — do this first!)
ufw allow 22/tcp

# HTTP and HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# STUN (WebRTC NAT traversal)
ufw allow 3478/udp

# Optional: SMTP
# ufw allow 2525/tcp

# Enable the firewall
ufw enable
ufw status
```

---

## 9. Using the Deploy Script (Developers)

The repository includes shell scripts that automate deployment from a development machine. These build from source, upload, and configure the server.

> **Note:** Most users should follow the manual steps in sections 4-8 above. The deploy scripts are designed for the developer workflow.

### `server-deploy.sh` — Full deployment pipeline

Builds the binary, uploads it, and runs an interactive setup wizard on first deploy.

```bash
./server-deploy.sh
```

What it does:
1. Builds `geogram-cli` via `launch-cli.sh --build-only`
2. Stops any existing instance (systemd or screen)
3. Uploads binary and libraries via SCP
4. Runs first-time setup wizard (if no `config.json` exists):
   - Station name, description, location
   - SSL domain configuration
   - Network role (root or node)
   - NOSTR key generation
5. Creates `station_config.json` and `config.json` on the server
6. Creates required directories (`devices/`, `tiles/`, `ssl/`, `logs/`)
7. Installs and starts the systemd service
8. Tests the deployment by hitting `/api/status`

Default target: `root@p2p.radio:/root/geogram`

### `server-restart.sh` — Quick restart without rebuilding

```bash
./server-restart.sh
```

Stops the running instance and starts a new one in a screen session. Tests HTTP connectivity afterward.

### `server-monitor.sh` — Attach to server console

```bash
./server-monitor.sh
```

SSHes into the server and attaches to the screen session. Press `Ctrl+A, D` to detach.

### `start-geogram.sh` — On-server management script

The deploy script creates `/root/geogram/start-geogram.sh` on the server:

```bash
./start-geogram.sh              # Start (auto-detects systemd or screen)
./start-geogram.sh stop         # Stop
./start-geogram.sh restart      # Restart
./start-geogram.sh status       # Show status
./start-geogram.sh logs         # Tail logs
```

---

## 10. Verification & Testing

### HTTP status check

```bash
curl http://yourstation.example.com/api/status
```

Expected response (HTTP 200):
```json
{
  "station_mode": true,
  "callsign": "X3ABCD",
  "npub": "npub1...",
  "name": "My Station",
  "version": "1.15.3",
  "uptime": 3600,
  "connected_devices": 0,
  "tile_server_enabled": true,
  "stun_server_enabled": true,
  "ssl_enabled": true
}
```

### HTTPS status check

```bash
curl https://yourstation.example.com/api/status
```

### WebSocket test

```bash
# Install wscat if needed: npm install -g wscat
wscat -c wss://yourstation.example.com/
```

You should see the WebSocket connection open. The server will send a welcome/hello message.

### NIP-05 verification

```bash
curl https://yourstation.example.com/.well-known/nostr.json
```

Expected response:
```json
{
  "names": {
    "station-callsign": "hex-pubkey..."
  }
}
```

---

## 11. Optional: Email/SMTP

### Enable in `station_config.json`

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

Compatible upstream relay providers: Brevo (Sendinblue), Mailgun, Amazon SES, or any SMTP relay that supports STARTTLS on port 587.

### DKIM Key Generation

Generate an RSA keypair for DKIM signing:

```bash
openssl genrsa -out dkim-private.pem 2048
openssl rsa -in dkim-private.pem -pubout -out dkim-public.pem
```

Base64-encode the private key and add it to `station_config.json`:

```bash
base64 -w0 dkim-private.pem
```

```json
{
  "dkimPrivateKey": "BASE64_ENCODED_PRIVATE_KEY_HERE"
}
```

### DNS Records for Email

Add these DNS records (see [Section 3](#3-dns-setup)):

1. **MX record** pointing to your station domain
2. **SPF TXT record**: `"v=spf1 a mx ~all"`
3. **DKIM TXT record** at `geogram._domainkey.yourstation.example.com` with the public key
4. **DMARC TXT record** at `_dmarc.yourstation.example.com`

Extract the public key for the DKIM DNS record:

```bash
# Strip headers and join lines
grep -v "^-" dkim-public.pem | tr -d '\n'
```

### Firewall

```bash
ufw allow 2525/tcp
```

---

## 12. Optional: Node Station

A node station connects to an existing root station instead of operating independently.

In `station_config.json`, set:

```json
{
  "stationRole": "node",
  "parentStationUrl": "wss://parent.example.com"
}
```

In `config.json`, set the profile's `stationRole` to `"node"` as well.

The node will connect upstream to the parent root station via WebSocket and participate in the network.

---

## 13. Maintenance

### Viewing Logs

```bash
# Live systemd journal
journalctl -u geogram-station -f

# Application log files (one per day)
ls /root/geogram/logs/2025/
# Example: log-2025-06-15.txt

# Crash log
cat /root/geogram/logs/crash.txt
```

### Updating

1. Download the new `geogram-cli` binary from https://geogram.radio/#downloads (or build from source)
2. Upload it to `/root/geogram/geogram-cli`
3. Restart the service:

```bash
systemctl restart geogram-station
```

### Certificate Renewal

If using the cron job from [Section 6](#6-ssltls-with-lets-encrypt), renewal is automatic. To renew manually:

```bash
certbot renew
cp /etc/letsencrypt/live/yourstation.example.com/fullchain.pem /root/geogram/ssl/fullchain.pem
cp /etc/letsencrypt/live/yourstation.example.com/privkey.pem /root/geogram/ssl/privkey.pem
systemctl restart geogram-station
```

### Disk Usage

Monitor tile cache and blossom storage:

```bash
du -sh /root/geogram/tiles/
du -sh /root/geogram/blossom/
```

Tile cache is bounded by `maxCacheSizeMB` (default 500 MB). Blossom storage is bounded by `blossomMaxStorageMb` (default 1024 MB).

---

## 14. Endpoints Reference

### HTTP Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Root page / station landing |
| GET | `/api/status` | Station status (JSON) |
| GET | `/status` | Alias for `/api/status` |
| GET | `/api/geoip` | GeoIP lookup for the client's IP |
| GET | `/api/clients` | List connected devices |
| GET | `/api/devices` | Alias for `/api/clients` |
| GET | `/api/updates/latest` | Latest mirrored release info |
| GET | `/api/logs` | Recent server logs (CLI only) |
| POST | `/api/cli` | Execute CLI command (CLI only) |
| GET | `/tiles/{z}/{x}/{y}.png` | Map tile proxy/cache |
| GET | `/updates/{filename}` | Download mirrored release file |
| GET | `/.well-known/nostr.json` | NIP-05 Nostr identity verification |
| GET | `/.well-known/acme-challenge/{token}` | Let's Encrypt ACME challenge |

### Blossom (File Hosting) Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/blossom/upload` | Upload a file |
| GET | `/blossom/{hash}` | Download a file by hash |
| HEAD | `/blossom/{hash}` | Check if a file exists |
| DELETE | `/blossom/{hash}` | Delete a file (requires auth) |

### WebSocket

| Path | Description |
|------|-------------|
| `/` (WebSocket upgrade) | Main WebSocket endpoint for real-time messaging, P2P signaling, Nostr relay, and device communication |

Connect via `ws://yourstation.example.com/` (HTTP) or `wss://yourstation.example.com/` (HTTPS).

### STUN

| Port | Protocol | Description |
|------|----------|-------------|
| 3478 | UDP | STUN Binding requests (RFC 5389) — returns client's public IP:port via XOR-MAPPED-ADDRESS |

---

## Directory Structure

```
/root/geogram/
├── geogram-cli              # Station binary
├── config.json              # Station identity/profile
├── station_config.json      # Server configuration
├── station.db               # SQLite database
├── start-geogram.sh         # Management script
├── libs/                    # Bundled libraries (libsqlite3.so.0)
├── ssl/
│   ├── fullchain.pem        # SSL certificate chain
│   ├── privkey.pem          # SSL private key (or domain.key)
│   └── .well-known/
│       └── acme-challenge/  # Let's Encrypt challenge tokens
├── tiles/                   # Cached map tiles
├── devices/                 # Connected device data
├── blossom/                 # Uploaded files (hash-addressed)
└── logs/
    ├── crash.txt            # Crash log
    └── {year}/
        └── log-{date}.txt   # Daily log files
```
