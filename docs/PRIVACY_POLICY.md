# Geogram Privacy Policy

Last updated: January 6, 2025

## Overview

Geogram is a peer-to-peer mesh networking application designed with privacy as a core principle. We do not operate servers that collect your data, and the app is built to function without requiring trust in any central authority.

## Data Collection

**Geogram does NOT collect, store, or transmit any personal data to external servers.**

- No analytics or tracking
- No telemetry
- No user accounts on our servers
- No data sent to Geogram developers or any third party

## Local Data Storage

The app stores the following data locally on your device:

- **Identity**: Your callsign and cryptographic keys (generated locally on your device)
- **Content**: Messages, places, events, alerts, blog posts, and other data you create
- **Contacts**: Information about other users you interact with
- **Map tiles**: Cached map data for offline use
- **Connection history**: Records of devices you have connected to
- **Settings**: Your app preferences and configuration

All this data remains on your device unless you explicitly share it with other devices through peer-to-peer connections.

## Peer-to-Peer Communication

When communicating with other devices:

- Data is transmitted directly between devices via WiFi, Bluetooth, or WebRTC
- No central server processes, routes, or stores your communications
- Messages are cryptographically signed with your private key to verify sender identity
- You control which devices you connect to and what data you share

## Permissions

The app requests the following permissions:

| Permission | Purpose |
|------------|---------|
| **Location** | Display your position on maps, enable location-based features, and attach coordinates to content you create |
| **Bluetooth** | Discover nearby devices and communicate peer-to-peer when WiFi is unavailable |
| **WiFi/Network** | Communicate with devices on local networks and optionally connect to the internet |
| **Notifications** | Alert you to incoming messages and events |
| **Camera** | Capture photos to attach to messages, places, events, and other content (optional) |
| **Storage** | Store app data, cached maps, and transferred files |

You can deny any permission, though some features may be limited.

## Third-Party Services

Geogram does not use any third-party analytics, advertising, or tracking services.

**Map tiles**: When online, map tiles may be fetched from OpenStreetMap tile servers. These requests are standard HTTP requests that do not include personal information beyond your IP address. See [OpenStreetMap's privacy policy](https://wiki.osmfoundation.org/wiki/Privacy_Policy) for details.

## Data Sharing

- We do not sell, trade, or share your data with third parties
- We cannot access your data because it exists only on your device
- Data you share with other Geogram users through peer-to-peer connections is under your control

## Data Retention

All data is stored locally on your device. You can delete any data at any time through the app or by uninstalling the application. We retain no copies because we never receive your data.

## Children's Privacy

Geogram does not knowingly collect any information from children under 13. The app does not require account creation or collect personal information.

## Security

- All cryptographic keys are generated locally on your device
- Private keys never leave your device
- Messages are signed to prevent impersonation
- The app is open source, allowing independent security review

## Open Source

Geogram is open source software licensed under Apache 2.0. You can review the complete source code at:
https://github.com/geograms/geogram

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be reflected in the "Last updated" date at the top of this document and committed to the source repository.

## Contact

For privacy questions or concerns:

- **Email**: brito_pt@pm.me
- **Website**: https://geogram.radio
- **Source code**: https://github.com/geograms/geogram
