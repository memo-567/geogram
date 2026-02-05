# QR Codes Format Specification

**Version**: 1.0
**Last Updated**: 2026-02-05
**Status**: Active

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [QR Code Format](#qr-code-format)
- [Supported Code Types](#supported-code-types)
- [Content Types](#content-types)
- [Complete Examples](#complete-examples)
- [File Operations](#file-operations)
- [Validation Rules](#validation-rules)
- [Best Practices](#best-practices)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

This document specifies the JSON-based format used for storing QR codes and barcodes in the Geogram system. The QR codes app provides functionality for scanning, generating, and organizing 2D codes (QR, Data Matrix, Aztec, PDF417) and 1D barcodes (EAN, UPC, Code 128, etc.).

### Key Features

- **Dual Purpose**: Both scan existing codes and generate new ones
- **Multiple Formats**: Support for QR codes, Data Matrix, Aztec, PDF417, and common 1D barcodes
- **Self-Contained Storage**: Code images stored as base64 within JSON files
- **Organization**: Separate folders for created vs scanned codes
- **Categorization**: User-defined subfolders for organizing codes
- **Metadata**: Tags, notes, and custom properties

### Use Cases

- **WiFi Sharing**: Generate and scan WiFi credentials
- **Product Inventory**: Scan and organize product barcodes
- **Contact Exchange**: Share vCard/meCard information
- **URL Shortcuts**: Quick access to websites
- **Event Tickets**: Store and display ticket barcodes
- **Asset Tracking**: Inventory management with barcodes

## File Organization

### Directory Structure

```
{profile}/qr/
├── created/                           # User-generated codes
│   ├── 2026-02-05_10-30.json         # Auto-named by timestamp
│   ├── 2026-02-05_14-22.json
│   ├── wifi/                          # User subfolder
│   │   ├── home-network.json
│   │   └── guest-network.json
│   └── business/
│       └── company-website.json
├── scanned/                           # Codes from camera
│   ├── 2026-02-05_14-22.json
│   ├── products/                      # User subfolder
│   │   ├── item1.json
│   │   └── item2.json
│   └── receipts/
│       └── store-receipt.json
└── extra/
    └── security.json                  # App security settings
```

### File Naming

**Auto-generated**: `YYYY-MM-DD_HH-MM.json`
- Based on creation/scan timestamp
- Collision-resistant with minute precision

**User-defined**: `{name}.json`
- When user explicitly names the code
- Lowercase, hyphens for spaces
- No special characters

### Subfolder Organization

Users can create subfolders within `created/` and `scanned/` for categorization:
- `wifi/` - WiFi network credentials
- `products/` - Product barcodes
- `contacts/` - vCard/meCard codes
- `urls/` - Website links
- Custom user-defined categories

## QR Code Format

### JSON Structure

```json
{
  "version": "1.0",
  "id": "uuid-v4-string",
  "name": "Human-readable name",
  "codeType": "qr_standard",
  "format": "QR_CODE",
  "content": "The encoded data",
  "source": "created",
  "createdAt": "2026-02-05T10:30:00Z",
  "modifiedAt": "2026-02-05T10:30:00Z",
  "category": "wifi",
  "tags": ["home", "network"],
  "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
  "metadata": {
    "errorCorrection": "M",
    "notes": "Guest network QR code"
  }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Format version (currently "1.0") |
| `id` | string | Yes | Unique identifier (UUID v4) |
| `name` | string | Yes | User-friendly display name |
| `codeType` | string | Yes | Type of code (see [Supported Code Types](#supported-code-types)) |
| `format` | string | Yes | ZXing format enum string |
| `content` | string | Yes | The actual encoded data |
| `source` | string | Yes | "created" or "scanned" |
| `createdAt` | string | Yes | ISO 8601 timestamp |
| `modifiedAt` | string | Yes | ISO 8601 timestamp |
| `category` | string | No | Category/subfolder name |
| `tags` | array | No | List of user-defined tags |
| `image` | string | Yes | Base64 data URI of code image |
| `metadata` | object | No | Additional properties |

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `errorCorrection` | string | QR error correction level (L, M, Q, H) |
| `notes` | string | User notes |
| `scanLocation` | object | GPS coordinates where scanned |
| `productName` | string | For product barcodes |
| `productPrice` | string | For product barcodes |

## Supported Code Types

### 2D Codes

| Code Type | `codeType` Value | `format` Value | Description |
|-----------|------------------|----------------|-------------|
| QR Code | `qr_standard` | `QR_CODE` | Standard QR code |
| Micro QR | `qr_micro` | `QR_CODE` | Smaller QR variant |
| Data Matrix | `data_matrix` | `DATA_MATRIX` | Industrial 2D code |
| Aztec | `aztec` | `AZTEC` | Aztec code |
| PDF417 | `pdf417` | `PDF_417` | Stacked linear barcode |
| MaxiCode | `maxicode` | `MAXICODE` | Hexagonal 2D code |

### 1D Barcodes

| Code Type | `codeType` Value | `format` Value | Description |
|-----------|------------------|----------------|-------------|
| Code 39 | `barcode_code39` | `CODE_39` | Alphanumeric |
| Code 93 | `barcode_code93` | `CODE_93` | Alphanumeric |
| Code 128 | `barcode_code128` | `CODE_128` | High-density |
| Codabar | `barcode_codabar` | `CODABAR` | Numeric with special chars |
| EAN-8 | `barcode_ean8` | `EAN_8` | 8-digit product |
| EAN-13 | `barcode_ean13` | `EAN_13` | 13-digit product |
| ITF | `barcode_itf` | `ITF` | Interleaved 2 of 5 |
| UPC-A | `barcode_upca` | `UPC_A` | 12-digit product |
| UPC-E | `barcode_upce` | `UPC_E` | Compressed UPC |

## Content Types

### WiFi Credentials

```
WIFI:T:WPA;S:NetworkName;P:password123;;
```

Fields:
- `T`: Authentication type (WPA, WEP, nopass)
- `S`: Network SSID
- `P`: Password
- `H`: Hidden network (true/false, optional)

### vCard Contact

```
BEGIN:VCARD
VERSION:3.0
N:Smith;John;;;
FN:John Smith
TEL:+1-555-123-4567
EMAIL:john@example.com
END:VCARD
```

### URL

```
https://example.com/page
```

### Plain Text

```
Any arbitrary text content
```

### Email

```
mailto:user@example.com?subject=Hello&body=Message
```

### Phone

```
tel:+1-555-123-4567
```

### SMS

```
smsto:+1-555-123-4567:Message text
```

### Geolocation

```
geo:40.7128,-74.0060
```

## Complete Examples

### WiFi QR Code (Created)

```json
{
  "version": "1.0",
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "name": "Home WiFi",
  "codeType": "qr_standard",
  "format": "QR_CODE",
  "content": "WIFI:T:WPA;S:MyHomeNetwork;P:secretpass123;;",
  "source": "created",
  "createdAt": "2026-02-05T10:30:00Z",
  "modifiedAt": "2026-02-05T10:30:00Z",
  "category": "wifi",
  "tags": ["home", "network", "guest"],
  "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
  "metadata": {
    "errorCorrection": "M",
    "notes": "QR code for guests to connect to home network"
  }
}
```

### Product Barcode (Scanned)

```json
{
  "version": "1.0",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "Cereal Box",
  "codeType": "barcode_ean13",
  "format": "EAN_13",
  "content": "5901234123457",
  "source": "scanned",
  "createdAt": "2026-02-05T14:22:00Z",
  "modifiedAt": "2026-02-05T14:22:00Z",
  "category": "products",
  "tags": ["groceries", "food"],
  "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
  "metadata": {
    "productName": "Healthy Cereal",
    "productPrice": "$4.99",
    "scanLocation": {
      "lat": 40.7128,
      "lon": -74.0060
    },
    "notes": "Bought at local grocery store"
  }
}
```

### URL QR Code (Created)

```json
{
  "version": "1.0",
  "id": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
  "name": "Company Website",
  "codeType": "qr_standard",
  "format": "QR_CODE",
  "content": "https://example.com",
  "source": "created",
  "createdAt": "2026-02-05T09:00:00Z",
  "modifiedAt": "2026-02-05T09:00:00Z",
  "category": "business",
  "tags": ["work", "website"],
  "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
  "metadata": {
    "errorCorrection": "H",
    "notes": "High error correction for printing on business cards"
  }
}
```

## File Operations

### Creating a Code

1. Generate UUID for `id`
2. Set timestamps for `createdAt` and `modifiedAt`
3. Generate or capture code image
4. Encode image as base64 data URI
5. Determine filename (timestamp or user-provided)
6. Write JSON to appropriate directory (`created/` or `scanned/`)

### Reading a Code

1. Parse JSON file
2. Validate required fields
3. Decode base64 image for display
4. Return QrCode model object

### Updating a Code

1. Read existing file
2. Update `modifiedAt` timestamp
3. Update modified fields
4. If renamed, move file to new location
5. Write updated JSON

### Deleting a Code

1. Remove JSON file from filesystem
2. No separate image cleanup needed (embedded in JSON)

### Moving to Subfolder

1. Create target subfolder if needed
2. Move JSON file
3. Update `category` field in JSON

## Validation Rules

### Required Fields

- `version` must be "1.0"
- `id` must be valid UUID
- `name` must be non-empty string
- `codeType` must be valid code type
- `format` must match codeType
- `content` must be non-empty
- `source` must be "created" or "scanned"
- `createdAt` must be valid ISO 8601
- `modifiedAt` must be valid ISO 8601
- `image` must be valid base64 data URI

### Content Validation

- WiFi: Must follow `WIFI:` format
- URL: Must be valid URI
- vCard: Must start with `BEGIN:VCARD`
- Product codes: Must match expected digit count

### Image Validation

- Must be PNG or JPEG format
- Must be valid base64 encoding
- Recommended max size: 500KB

## Best Practices

### Naming Conventions

- Use descriptive names for frequently accessed codes
- Include purpose in name (e.g., "Guest WiFi", "Store Receipt")
- Keep names concise but meaningful

### Organization

- Use subfolders for related codes
- Add tags for cross-category searching
- Archive old codes to dated subfolders

### Image Quality

- Use appropriate error correction for use case
- L (7%) for digital display
- M (15%) for general use
- Q (25%) for outdoor/damaged surfaces
- H (30%) for maximum durability

### Scanning

- Save only successfully decoded codes
- Include scan location for inventory tracking
- Add product information when available

## Security Considerations

### Sensitive Data

- WiFi passwords are stored in plain text within JSON
- Consider not saving passwords for sensitive networks
- Use appropriate file system permissions

### URL Safety

- Validate URLs before opening
- Warn users about unfamiliar domains
- Don't auto-open scanned URLs

### Privacy

- Scan location data is optional
- Clear metadata before sharing codes
- Consider stripping image EXIF data

## Related Documentation

- [Contacts Format Specification](contacts-format-specification.md) - For vCard content
- [Transfer Format Specification](transfer-format-specification.md) - For sharing codes

## Change Log

### Version 1.0 (2026-02-05)

- Initial specification
- Support for QR codes and common barcodes
- Self-contained JSON format with base64 images
- Created/scanned organization structure
