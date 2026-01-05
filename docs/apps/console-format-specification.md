# Console Format Specification

**Version**: 1.0
**Last Updated**: 2026-01-04
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Session Format](#session-format)
- [VM Configuration](#vm-configuration)
- [State Management](#state-management)
- [Mount Points](#mount-points)
- [Network Configuration](#network-configuration)
- [Station Server Distribution](#station-server-distribution)
- [Permissions and Roles](#permissions-and-roles)
- [NOSTR Integration](#nostr-integration)
- [Complete Examples](#complete-examples)
- [Parsing Implementation](#parsing-implementation)
- [File Operations](#file-operations)
- [Validation Rules](#validation-rules)
- [Best Practices](#best-practices)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

This document specifies the format for the Console app in the Geogram system. The Console app provides a virtual machine environment running Alpine Linux 3.12.0, powered by the TinyEMU/JSLinux WASM-based emulator.

### Key Features

- **Alpine Linux VM**: Lightweight Linux distribution running in browser via WASM
- **TinyEMU Emulator**: x86/RISC-V emulator compiled to WebAssembly
- **Folder Mounting**: Host folders accessible inside VM via 9P filesystem
- **Network Access**: VirtIO user-mode networking for internet and host access
- **State Persistence**: Save, load, and reset VM state
- **Station Distribution**: VM images cached by station server for clients
- **Cross-Platform**: Runs on Android, iOS, macOS, Linux, Windows, and Web

### Use Cases

- **Development**: Run command-line tools, compile code, test scripts
- **System Administration**: Practice Linux administration in sandboxed environment
- **File Processing**: Use Unix tools on geogram collection files
- **Learning**: Educational environment for learning Linux/Unix
- **Offline Computing**: Portable computing environment independent of host OS

## File Organization

### Directory Structure

```
{console_collection}/
├── sessions/
│   ├── {session_id}/
│   │   ├── session.txt           # Session metadata
│   │   ├── current.state         # Current VM memory state
│   │   ├── mounts.json           # Mount point configuration
│   │   └── saved/                # User-saved state snapshots
│   │       ├── {timestamp}.state
│   │       └── {timestamp}.state
│   └── {session_id}/
│       └── ...
└── scripts/                      # Optional shared scripts
    ├── backup.sh
    └── sync.sh
```

**Note**: The collection type is `console`, so there is no nested `console/` subfolder. Sessions and scripts are stored directly in the collection root.

### Session Folder Naming

**Pattern**: `{session_id}/`

**Session ID Generation**:
- Format: 8-character alphanumeric string
- Example: `a1b2c3d4`
- Generated using random alphanumeric characters
- Must be unique within the collection

**Examples**:
```
sessions/
├── a1b2c3d4/      # First session
├── x9y8z7w6/      # Second session
└── m5n6o7p8/      # Third session
```

### State File Naming

**Current State**: `current.state`
- Always contains the latest VM memory state
- Updated automatically when VM is paused or closed
- Binary format (TinyEMU snapshot format)

**Saved States**: `saved/{timestamp}.state`
- User-initiated snapshots
- Timestamp format: `YYYY-MM-DD_HH-MM-SS`
- Example: `saved/2026-01-04_14-30-00.state`

## Session Format

### Session Metadata File

Every session must have a `session.txt` file in the session folder.

**Complete Structure**:
```
# SESSION: Session Name

CREATED: YYYY-MM-DD HH:MM_ss
AUTHOR: CALLSIGN
VM_TYPE: alpine-x86
MEMORY: 128
NETWORK: enabled
KEEP_RUNNING: false
STATUS: stopped

Optional description of this console session.
What it's used for, any notes about configuration.

--> npub: npub1...
--> signature: hex_signature
```

### Header Section

1. **Title Line** (required)
   - **Format**: `# SESSION: <name>`
   - **Example**: `# SESSION: Development Environment`
   - **Constraints**: Any length, descriptive name

2. **Blank Line** (required)
   - Separates title from metadata

3. **Created Timestamp** (required)
   - **Format**: `CREATED: YYYY-MM-DD HH:MM_ss`
   - **Example**: `CREATED: 2026-01-04 10:00_00`
   - **Note**: Underscore before seconds

4. **Author Line** (required)
   - **Format**: `AUTHOR: <callsign>`
   - **Example**: `AUTHOR: CR7BBQ`
   - **Constraints**: Alphanumeric callsign

5. **VM Type** (required)
   - **Format**: `VM_TYPE: <type>`
   - **Values**: `alpine-x86`, `alpine-riscv64`, `buildroot-riscv64`
   - **Default**: `alpine-x86`

6. **Memory** (optional)
   - **Format**: `MEMORY: <megabytes>`
   - **Example**: `MEMORY: 128`
   - **Range**: 64-512 MB
   - **Default**: 128 MB

7. **Network** (optional)
   - **Format**: `NETWORK: <enabled|disabled>`
   - **Default**: `enabled`

8. **Keep Running** (optional)
   - **Format**: `KEEP_RUNNING: <true|false>`
   - **Default**: `false`
   - **Behavior when true**:
     - Session starts automatically when app launches
     - Session restarts automatically if it stops unexpectedly
     - Session runs in background when UI is closed

9. **Status** (system-managed)
   - **Format**: `STATUS: <running|stopped|suspended>`
   - **Values**:
     - `running`: VM is currently active
     - `stopped`: VM is shut down
     - `suspended`: VM state is saved, can resume

### Content Section

Optional description text after the header:
- Plain text format
- Multiple paragraphs allowed
- Can describe purpose, configuration, notes

### Session Metadata

Metadata appears after content:

```
--> npub: npub1abc123...
--> signature: hex_signature_string...
```

- **npub**: NOSTR public key (optional)
- **signature**: NOSTR signature, must be last if present

## Session Settings UI

### Settings Panel

Each session has a settings panel accessible via gear icon in the session list or toolbar.

**Settings Panel Sections**:

```
┌─────────────────────────────────────────────┐
│ Session Settings                        [X] │
├─────────────────────────────────────────────┤
│                                             │
│ SESSION NAME                                │
│ ┌─────────────────────────────────────────┐ │
│ │ Development Environment                 │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ MEMORY (RAM)                                │
│ ┌─────────────────────────────────────────┐ │
│ │ 128 MB                              [▼] │ │
│ └─────────────────────────────────────────┘ │
│   Options: 64 MB, 128 MB, 256 MB, 512 MB    │
│                                             │
│ NETWORK                                     │
│ ┌─────────────────────────────────────────┐ │
│ │ [✓] Enable network access               │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ KEEP RUNNING                                │
│ ┌─────────────────────────────────────────┐ │
│ │ [✓] Launch on startup                   │ │
│ │ [✓] Restart if stopped                  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
├─────────────────────────────────────────────┤
│ MOUNTED FOLDERS                     [+ Add] │
├─────────────────────────────────────────────┤
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ /mnt/projects                           │ │
│ │ → ~/geogram/collections/projects        │ │
│ │ [Read-Write]              [Edit] [Del]  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ /mnt/data                               │ │
│ │ → ~/geogram/collections/data            │ │
│ │ [Read-Only]               [Edit] [Del]  │ │
│ └─────────────────────────────────────────┘ │
│                                             │
├─────────────────────────────────────────────┤
│              [Cancel]  [Save Settings]      │
└─────────────────────────────────────────────┘
```

### Memory Configuration

| Option | Description | Use Case |
|--------|-------------|----------|
| 64 MB | Minimum | Basic shell, small scripts |
| 128 MB | Default | General use, text processing |
| 256 MB | Standard | Development, compiling |
| 512 MB | Maximum | Heavy workloads, large files |

**Note**: Higher memory increases state file size proportionally.

### Mount Folder Dialog

When adding or editing a mount:

```
┌─────────────────────────────────────────────┐
│ Mount Folder                            [X] │
├─────────────────────────────────────────────┤
│                                             │
│ VM PATH (mount point inside VM)             │
│ ┌─────────────────────────────────────────┐ │
│ │ /mnt/                                   │ │
│ └─────────────────────────────────────────┘ │
│   e.g., /mnt/data, /mnt/projects            │
│                                             │
│ HOST FOLDER                                 │
│ ┌─────────────────────────────────────────┐ │
│ │ ~/geogram/collections/...    [Browse]   │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ACCESS MODE                                 │
│ ○ Read-Write  ● Read-Only                   │
│                                             │
├─────────────────────────────────────────────┤
│                   [Cancel]  [Add Mount]     │
└─────────────────────────────────────────────┘
```

### Keep Running Options

| Option | Behavior |
|--------|----------|
| Launch on startup | Session starts when Geogram app opens |
| Restart if stopped | Session automatically restarts if VM crashes or stops |

**Background Behavior**:
- When keep running is enabled, session continues in background
- VM state is preserved even when console UI is closed
- Status indicator shows in system tray/notification area (desktop)
- Background sessions appear in session list with "running" badge

### Settings Persistence

Settings are saved to `session.txt` when the Save button is clicked:
- Session name → `# SESSION:` header
- Memory → `MEMORY:` field
- Network → `NETWORK:` field
- Keep running → `KEEP_RUNNING:` field
- Mounts → `mounts.json` file

**Note**: Changing memory requires session restart to take effect.

## VM Configuration

### TinyEMU Configuration Format

The VM is configured via JSON passed to the TinyEMU emulator.

**Generated Configuration** (`vm_config.json`):
```json
{
  "version": 1,
  "machine": "pc",
  "memory_size": 128,
  "bios": "bios.bin",
  "kernel": "vmlinuz-virt",
  "initrd": "initramfs-virt",
  "cmdline": "console=ttyS0 root=/dev/vda rw",
  "drive0": {
    "file": "alpine-x86-root.bin",
    "type": "virtio"
  },
  "net0": {
    "driver": "virtio",
    "type": "user"
  },
  "fs0": {
    "driver": "virtio",
    "type": "9p",
    "tag": "host",
    "path": "/mnt/host"
  }
}
```

### Supported VM Types

| Type | Architecture | Description |
|------|--------------|-------------|
| `alpine-x86` | x86 32-bit | Alpine Linux 3.12.0, smallest footprint |
| `alpine-riscv64` | RISC-V 64-bit | Alpine Linux for RISC-V |
| `buildroot-riscv64` | RISC-V 64-bit | Minimal Buildroot Linux |

### Memory Configuration

| Setting | RAM | Use Case |
|---------|-----|----------|
| Minimum | 64 MB | Basic shell operations |
| Default | 128 MB | General purpose |
| Standard | 256 MB | Development, compiling |
| Maximum | 512 MB | Heavy workloads |

## State Management

### State Types

1. **Current State** (`current.state`)
   - Automatically saved when VM pauses/closes
   - Automatically loaded when VM starts
   - Single file, always up-to-date

2. **Saved States** (`saved/*.state`)
   - User-initiated snapshots
   - Named by timestamp
   - Can have unlimited snapshots (disk space permitting)

### State Operations

**Save State**:
```
1. Pause VM execution
2. Serialize CPU registers, memory, device state
3. Write to saved/{timestamp}.state
4. Update session.txt with STATUS: suspended
5. Resume VM execution (optional)
```

**Load State**:
```
1. Stop current VM execution
2. Read state file
3. Deserialize CPU, memory, device state
4. Resume VM execution
5. Update session.txt with STATUS: running
```

**Reset Session**:
```
1. Stop current VM execution
2. Delete current.state
3. Clear saved/ directory (optional, with confirmation)
4. Boot fresh from root filesystem image
5. Update session.txt with STATUS: running
```

### State File Format

Binary format defined by TinyEMU:
- Header: Magic number, version, flags
- CPU state: Registers, program counter, flags
- Memory: Full RAM contents (compressed)
- Devices: VirtIO device states

**Typical Sizes**:
- 128 MB RAM session: ~20-50 MB state file (compressed)
- 256 MB RAM session: ~40-100 MB state file (compressed)

## Mount Points

### Mount Configuration File

**File**: `mounts.json`

```json
{
  "mounts": [
    {
      "host_path": "/home/user/geogram/collections/places",
      "vm_path": "/mnt/places",
      "readonly": false
    },
    {
      "host_path": "/home/user/geogram/collections/files",
      "vm_path": "/mnt/files",
      "readonly": true
    }
  ]
}
```

### Mount Point Structure

| Field | Type | Description |
|-------|------|-------------|
| `host_path` | string | Absolute path on host filesystem |
| `vm_path` | string | Mount point path inside VM |
| `readonly` | boolean | Whether mount is read-only |

### 9P Filesystem Protocol

TinyEMU uses VirtIO 9P for host folder access:

1. **Host side** (Dart/JavaScript):
   - Receives 9P protocol messages
   - Translates to host filesystem operations
   - Returns results to VM

2. **VM side** (Linux):
   - Mounts 9P filesystem: `mount -t 9p host /mnt/host`
   - Accesses files normally via mounted path

### Mount Restrictions

**Allowed Paths**:
- Geogram data directory and subdirectories
- Explicitly configured external paths
- User-selected paths via file picker

**Forbidden Paths**:
- System directories (`/`, `/etc`, `/usr`, `/bin`)
- Other users' home directories
- Sensitive application data

## Network Configuration

### VirtIO User-Mode Networking

TinyEMU provides user-mode networking similar to QEMU:

**VM Network Configuration**:
- IP Address: `10.0.2.15` (DHCP assigned)
- Gateway: `10.0.2.2`
- DNS: `10.0.2.3`
- Host Access: Via gateway IP `10.0.2.2`

### Accessing Host Services

From inside the VM, host services are accessible via `10.0.2.2`:

```bash
# Access host web server running on port 8080
curl http://10.0.2.2:8080/

# Access geogram station server
curl http://10.0.2.2:3000/api/places
```

### Network Modes

| Mode | Internet | Host Access | Description |
|------|----------|-------------|-------------|
| `enabled` | Yes | Yes | Full network access |
| `disabled` | No | No | Completely isolated |
| `host-only` | No | Yes | Access host only (future) |

## Geogram CLI Bridge

### Overview

A native `geogram` command-line tool is available inside the VM, allowing control of the host Geogram instance from within Alpine Linux. This enables shell scripting and automation of Geogram operations.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Alpine Linux VM                       │
│  ┌─────────────────────────────────────────────────┐    │
│  │  $ geogram chat send general "Hello world"      │    │
│  │  $ geogram devices list                         │    │
│  │  $ geogram backup start PROVIDER1               │    │
│  └─────────────────────────────────────────────────┘    │
│                          │                               │
│                          │ HTTP Request                  │
│                          ▼                               │
│              http://10.0.2.2:3457/api/debug             │
└─────────────────────────────────────────────────────────┘
                           │
                           │ VirtIO Network Bridge
                           ▼
┌─────────────────────────────────────────────────────────┐
│                   Host Geogram App                       │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Debug API Service                   │    │
│  │         (DebugController + HTTP endpoints)       │    │
│  └─────────────────────────────────────────────────┘    │
│                          │                               │
│                          ▼                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │  Chat    │ │ Devices  │ │  Backup  │ │  Places  │   │
│  │ Service  │ │ Service  │ │ Service  │ │ Service  │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
└─────────────────────────────────────────────────────────┘
```

### VM CLI Binary

The `geogram` binary is a lightweight native executable compiled from Dart:

**Location in VM**: `/usr/local/bin/geogram`

**Binary Details**:
- Pure Dart compiled to native Linux binary
- No Flutter dependencies
- ~5-10 MB executable size
- Communicates via HTTP to host Debug API

### Available Commands

```bash
# Navigation
geogram navigate collections    # Open collections panel
geogram navigate maps          # Open maps panel
geogram navigate devices       # Open devices panel
geogram navigate settings      # Open settings panel

# Chat
geogram chat list              # List chat rooms
geogram chat send <room> <msg> # Send message to room
geogram chat open <room>       # Open chat room in UI

# Direct Messages
geogram dm send <callsign> <message>   # Send DM
geogram dm open <callsign>             # Open DM conversation
geogram dm file <callsign> <path>      # Send file via DM

# Devices
geogram devices list           # List known devices
geogram devices scan           # Scan local network
geogram devices refresh        # Refresh all devices

# BLE
geogram ble scan               # Start BLE scan
geogram ble advertise          # Start BLE advertising

# Station
geogram station connect [url]  # Connect to station
geogram station disconnect     # Disconnect from station

# Backup
geogram backup start <provider>           # Start backup
geogram backup restore <provider> <date>  # Restore from snapshot
geogram backup status                     # Get backup status
geogram backup list <provider>            # List snapshots

# Places
geogram place like <place_id>             # Toggle like
geogram place comment <place_id> <text>   # Add comment

# Voice
geogram voice record           # Start recording
geogram voice stop             # Stop and save recording
geogram voice status           # Get recording status

# Utility
geogram toast <message>        # Show toast notification
geogram status                 # Get host Geogram status
geogram help                   # Show help
```

### Configuration

The CLI reads configuration from `/etc/geogram.conf`:

```ini
# Geogram CLI Configuration
HOST_IP=10.0.2.2
DEBUG_PORT=3457
TIMEOUT=30
```

**Environment Variables**:
```bash
export GEOGRAM_HOST=10.0.2.2
export GEOGRAM_PORT=3457
```

### Shell Scripting Examples

**Automated Backup Script** (`/mnt/host/scripts/backup.sh`):
```bash
#!/bin/sh
# Daily backup to provider

PROVIDER="BACKUP1"
DATE=$(date +%Y-%m-%d)

echo "Starting backup to $PROVIDER..."
geogram backup start $PROVIDER

# Wait for completion
while true; do
    STATUS=$(geogram backup status | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    if [ "$STATUS" = "completed" ]; then
        echo "Backup completed successfully"
        geogram toast "Backup completed: $DATE"
        break
    elif [ "$STATUS" = "failed" ]; then
        echo "Backup failed!"
        geogram toast "Backup failed: $DATE"
        exit 1
    fi
    sleep 10
done
```

**Batch File Processing** (`/mnt/host/scripts/process.sh`):
```bash
#!/bin/sh
# Process files and notify via chat

INPUT_DIR="/mnt/input"
OUTPUT_DIR="/mnt/output"

for file in "$INPUT_DIR"/*.txt; do
    # Process with Unix tools
    sed 's/foo/bar/g' "$file" > "$OUTPUT_DIR/$(basename $file)"
done

# Notify via station chat
geogram chat send general "Processed $(ls $INPUT_DIR/*.txt | wc -l) files"
```

**Device Monitor** (`/mnt/host/scripts/monitor.sh`):
```bash
#!/bin/sh
# Monitor for new devices

geogram devices scan
DEVICES=$(geogram devices list | grep -c "online")
echo "Found $DEVICES online devices"

if [ "$DEVICES" -gt 5 ]; then
    geogram toast "Alert: $DEVICES devices online"
fi
```

### API Response Format

Commands return JSON responses:

```bash
$ geogram chat send general "Hello"
{
  "success": true,
  "message": "Sending chat message",
  "room_id": "general"
}

$ geogram devices list
{
  "success": true,
  "devices": [
    {"callsign": "ALPHA1", "status": "online", "url": "http://192.168.1.10:3456"},
    {"callsign": "BRAVO2", "status": "offline", "last_seen": "2026-01-04T10:00:00Z"}
  ]
}
```

### Security Considerations

**Debug API Access**:
- Debug API must be enabled on host (`--debug-api` flag)
- Only accessible from localhost and VM gateway (10.0.2.2)
- No authentication required (trusted local environment)
- Actions are logged in host debug history

**Path Restrictions**:
- File paths in commands are validated
- Cannot access paths outside allowed directories
- Mount points provide controlled filesystem access

### Binary Distribution

The `geogram` CLI binary is distributed with the VM image:

**Station Server**:
```
{app-support}/console/vm/geogram-cli-alpine
```

**VM Installation**:
- Pre-installed in Alpine root filesystem
- Located at `/usr/local/bin/geogram`
- Executable permissions (755)

**Updates**:
- Binary version checked against manifest
- Updated when VM image is refreshed
- Backward compatible with host API

## Station Server Distribution

### VM Files Distribution

Station servers cache and distribute VM files to clients.

**Required Files**:

| File | Description | Size |
|------|-------------|------|
| `jslinux.js` | TinyEMU JavaScript runtime | ~200 KB |
| `x86emu-wasm.wasm` | x86 emulator WASM binary | ~500 KB |
| `riscv64emu-wasm.wasm` | RISC-V emulator WASM binary | ~500 KB |
| `alpine-x86.cfg` | VM configuration template | ~1 KB |
| `alpine-x86-root.bin` | Alpine root filesystem | ~50-100 MB |

**Manifest File** (`manifest.json`):
```json
{
  "version": "1.0.0",
  "updated": "2026-01-04T10:00:00Z",
  "files": [
    {
      "name": "jslinux.js",
      "size": 204800,
      "sha256": "abc123..."
    },
    {
      "name": "x86emu-wasm.wasm",
      "size": 524288,
      "sha256": "def456..."
    },
    {
      "name": "alpine-x86-root.bin",
      "size": 52428800,
      "sha256": "789ghi..."
    }
  ]
}
```

### Station Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/console/vm/manifest.json` | GET | File manifest with checksums |
| `/console/vm/{filename}` | GET | Individual VM file |

### Download Flow

```
1. Client requests /console/vm/manifest.json
2. Compare local file checksums with manifest
3. Download missing or outdated files
4. Verify checksums after download
5. Store in {data-root}/console/vm/
```

### Storage Paths

| Location | Path |
|----------|------|
| Station cache | `{app-support}/console/vm/` |
| Client storage | `{data-root}/console/vm/` |

### Upstream Sources

Station servers fetch VM files from:

1. **Primary**: `https://bellard.org/jslinux/` (official JSLinux)
2. **Mirror**: Geogram CDN (future)
3. **Fallback**: Bundled minimal assets

## Permissions and Roles

### Session Owner

The user who created the session (AUTHOR field).

**Permissions**:
- Full control over session
- Create, edit, delete session
- Save and load states
- Configure mount points
- Share session (future)

### Collection Admin

Administrator of the collection containing console sessions.

**Permissions**:
- View all sessions in collection
- Delete any session
- Set collection-wide policies
- Manage shared scripts

### Guest Access (Future)

Read-only access to shared sessions.

**Permissions**:
- View session configuration
- Cannot start or modify VM
- Cannot access mounted files

## NOSTR Integration

### Session Signing

Sessions can be cryptographically signed:

```
# SESSION: Development Environment

CREATED: 2026-01-04 10:00_00
AUTHOR: CR7BBQ
VM_TYPE: alpine-x86
MEMORY: 128

Development environment for testing scripts.

--> npub: npub1abc123...
--> signature: 0123456789abcdef...
```

### Script Signing (Future)

Shared scripts can be signed for authenticity:

```bash
#!/bin/bash
# SCRIPT: backup.sh
# AUTHOR: CR7BBQ
# SIGNED: npub1abc123...
# SIGNATURE: fedcba987654...

rsync -av /mnt/host/data /mnt/host/backup/
```

## Complete Examples

### Example 1: Basic Development Session

```
Session folder: sessions/dev01/

=== session.txt ===
# SESSION: Development Environment

CREATED: 2026-01-04 10:00_00
AUTHOR: CR7BBQ
VM_TYPE: alpine-x86
MEMORY: 256
NETWORK: enabled
KEEP_RUNNING: true
STATUS: stopped

General development environment with access to
project files. Used for running build scripts
and testing command-line tools. Configured to
start automatically and restart if stopped.

--> npub: npub1abc123...
--> signature: 0123456789abcdef...

=== mounts.json ===
{
  "mounts": [
    {
      "host_path": "/home/user/geogram/collections/projects",
      "vm_path": "/mnt/projects",
      "readonly": false
    }
  ]
}

=== Directory structure ===
dev01/
├── session.txt
├── mounts.json
├── current.state          # 45 MB
└── saved/
    ├── 2026-01-04_10-30-00.state
    └── 2026-01-04_14-45-00.state
```

### Example 2: Offline Processing Session

```
Session folder: sessions/proc01/

=== session.txt ===
# SESSION: Offline File Processor

CREATED: 2026-01-03 08:00_00
AUTHOR: X135AS
VM_TYPE: alpine-x86
MEMORY: 128
NETWORK: disabled
STATUS: suspended

Isolated session for processing sensitive files.
Network disabled for security. Uses standard
Unix tools (awk, sed, grep) for batch processing.

=== mounts.json ===
{
  "mounts": [
    {
      "host_path": "/home/user/geogram/collections/imports",
      "vm_path": "/mnt/input",
      "readonly": true
    },
    {
      "host_path": "/home/user/geogram/collections/exports",
      "vm_path": "/mnt/output",
      "readonly": false
    }
  ]
}
```

### Example 3: Learning Environment

```
Session folder: sessions/learn01/

=== session.txt ===
# SESSION: Linux Learning

CREATED: 2026-01-02 15:00_00
AUTHOR: BRAVO2
VM_TYPE: alpine-x86
MEMORY: 128
NETWORK: enabled
STATUS: stopped

Learning environment for practicing Linux commands.
Safe to experiment - can reset anytime.

No mount points configured - fully isolated.

=== mounts.json ===
{
  "mounts": []
}

=== Directory structure ===
learn01/
├── session.txt
├── mounts.json
└── current.state
```

## Parsing Implementation

### Session File Parsing

```
1. Read session.txt as UTF-8 text
2. Parse title line: "# SESSION: <name>"
3. Verify title exists
4. Parse header lines:
   - CREATED: timestamp
   - AUTHOR: callsign
   - VM_TYPE: type
   - MEMORY: megabytes (optional)
   - NETWORK: enabled|disabled (optional)
   - KEEP_RUNNING: true|false (optional)
   - STATUS: running|stopped|suspended
5. Find content start (after header blank line)
6. Read content until metadata
7. Extract metadata (npub, signature)
8. Validate signature placement (must be last)
```

### Mounts File Parsing

```
1. Read mounts.json as UTF-8 text
2. Parse as JSON
3. Validate structure:
   - mounts: array of mount objects
   - Each mount: host_path, vm_path, readonly
4. Validate paths:
   - host_path must exist and be accessible
   - vm_path must be valid Linux path
5. Check permissions for each host_path
```

### State File Handling

```
1. State files are binary, handled by TinyEMU
2. Verify file header magic number
3. Check version compatibility
4. Load/save via TinyEMU JavaScript API
```

## File Operations

### Creating a Session

```
1. Generate unique session ID (8 alphanumeric chars)
2. Create session folder: sessions/{session_id}/
3. Create session.txt with metadata
4. Create empty mounts.json: {"mounts": []}
5. Set folder permissions (755)
6. Initialize VM (no state file yet)
```

### Starting a Session

```
1. Read session.txt for configuration
2. Read mounts.json for mount points
3. Check if current.state exists:
   - If yes: Resume from saved state
   - If no: Boot fresh from root image
4. Initialize 9P filesystem bridge
5. Start TinyEMU with configuration
6. Update STATUS to running
```

### Saving Session State

```
1. Pause VM execution
2. Get state snapshot from TinyEMU
3. Write to saved/{timestamp}.state
4. Continue VM execution
5. Log snapshot creation
```

### Deleting a Session

```
1. Stop VM if running
2. Delete all state files
3. Delete mounts.json
4. Delete session.txt
5. Remove session folder
6. Update collection index
```

## Validation Rules

### Session Validation

- [x] First line must start with `# SESSION: `
- [x] Name must not be empty
- [x] CREATED line must have valid timestamp
- [x] AUTHOR line must have non-empty callsign
- [x] VM_TYPE must be valid type
- [x] MEMORY must be 64-512 if specified
- [x] NETWORK must be enabled|disabled if specified
- [x] KEEP_RUNNING must be true|false if specified
- [x] STATUS must be running|stopped|suspended
- [x] Signature must be last metadata if present

### Mount Validation

- [x] mounts must be array
- [x] Each mount must have host_path, vm_path, readonly
- [x] host_path must be absolute path
- [x] host_path must exist (when starting session)
- [x] vm_path must start with /
- [x] readonly must be boolean
- [x] No duplicate vm_path values

### State File Validation

- [x] File must have correct magic number
- [x] Version must be compatible
- [x] File size must match expected format
- [x] Checksum must validate (if present)

## Best Practices

### For Users

1. **Name sessions descriptively**: Use clear names like "Dev Environment" or "File Processing"
2. **Save states before risky operations**: Create snapshots before major changes
3. **Use read-only mounts when possible**: Protect source files from accidental modification
4. **Disable network when not needed**: Improves security and reduces attack surface
5. **Clean up unused states**: Delete old snapshots to save disk space

### For Developers

1. **Validate all paths**: Check host paths exist before mounting
2. **Handle state errors gracefully**: Corrupt states should offer reset option
3. **Implement download progress**: Large VM files need progress indication
4. **Cache VM files**: Don't re-download unchanged files
5. **Sandbox file access**: Restrict 9P bridge to allowed paths only

### For Station Operators

1. **Cache VM files locally**: Reduces bandwidth and improves client performance
2. **Verify file integrity**: Check checksums after downloading from upstream
3. **Monitor disk usage**: VM files are large, plan storage accordingly
4. **Update regularly**: Keep VM files updated for security patches

## Security Considerations

### VM Isolation

The VM runs in a sandboxed WebView/WASM environment:
- Cannot access host filesystem except via 9P mounts
- Cannot execute host binaries
- Network traffic goes through VirtIO user-mode stack
- Memory is isolated from host process

### File Access Control

**9P Bridge Security**:
- Whitelist allowed host paths
- Reject path traversal attempts (`../`)
- Validate all paths against allowed list
- Log all file access operations

### Network Security

**VirtIO Networking**:
- User-mode networking (no raw socket access)
- Cannot spoof MAC addresses
- Cannot perform ARP attacks
- Limited to TCP/UDP over IP

### State File Security

**Considerations**:
- State files contain full VM memory
- May contain sensitive data processed in VM
- Encrypt states if containing secrets (future)
- Secure delete when removing sessions

## Operational Notes: Android Native TinyEMU (2026-01-05)

- Goal: retire WebView/JSLinux on Android and run TinyEMU natively. The Flutter widget now selects the native path on Android, instantiates an xterm terminal, and copies a bundled emulator binary into `app_flutter/geogram/console/emu/temu` (or uses `libtemu.so` packaged in `jniLibs/arm64-v8a` when present). The VM config is rewritten locally (`local-alpine-x86.cfg`) to use the downloaded Alpine rootfs via 9p and to disable networking when the session requests it.
- Observed on device `C61000000004616` (Android 15): TinyEMU launches via `/system/bin/sh <temu> <cfg>` but exits immediately with code `126`. Direct CLI run with `run-as dev.geogram` shows `x86 emulator is not supported` coming from `third_party/tinyemu-2019-12-21/x86_cpu.c`, which is a stub in this release.
- Permissions were verified: the copied binary is mode `0755` and executable under the app UID. The failure is not a chmod issue; the shipped TinyEMU build simply lacks x86 support.
- Next action required: either (1) switch the Android console VM to a RISC-V image that TinyEMU supports, or (2) bundle a different emulator that implements x86 on Android (e.g., a cross-compiled `qemu-system-x86_64` or an x86-capable TinyEMU fork). Until then, Android native console cannot boot the current Alpine x86 VM.

## Related Documentation

- [Downloads Specification](../downloads.md)
- [Collection Service](../../lib/services/collection_service.dart)
- [TinyEMU Documentation](https://bellard.org/tinyemu/)
- [JSLinux](https://bellard.org/jslinux/)
- [9P Protocol](http://9p.io/documentation/91/)

## Change Log

### Version 1.1 (2026-01-05)

- Documented Android native TinyEMU migration attempt and the x86 stub limitation on device (exit code 126).
- Noted packaging of TinyEMU as `jniLibs/arm64-v8a/libtemu.so` and asset fallback.
- Added next-step options for enabling a working Android console VM.

### Version 1.0 (2026-01-04)

**Initial Specification**:
- Console app overview and architecture
- Session format with metadata
- VM configuration via TinyEMU
- State management (save/load/reset)
- Mount points via 9P filesystem
- VirtIO user-mode networking
- Station server distribution model
- Permission system
- NOSTR integration for signing
- Complete examples
- Validation rules
- Security considerations
