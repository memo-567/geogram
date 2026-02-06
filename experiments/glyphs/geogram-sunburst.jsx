import { useState, useRef, useEffect, useCallback } from "react";

// ============================================================
// GEOGRAM SUNBURST CODE — Encoding Specification
// ============================================================
// Structure (radial, from center outward):
//   - Center: Geogram logo / avatar zone (decorative)
//   - Ring 0 (inner): 8 sync markers (fixed pattern for alignment)
//   - Ring 1: 16 segments — protocol version + data type (4 bits each)
//   - Ring 2: 32 segments — data length (in bytes)
//   - Ring 3-N: 32 segments each — payload data
//   - Ring N+1: 32 segments — CRC-8 checksum
//   - Outer: decorative sunburst rays
//
// Each segment is a radial "wedge" that is filled (1) or empty (0)
// Encoding: UTF-8 bytes, MSB first per ring
// ============================================================

const CRC8_TABLE = (() => {
  const table = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    let crc = i;
    for (let j = 0; j < 8; j++) {
      crc = crc & 0x80 ? (crc << 1) ^ 0x07 : crc << 1;
    }
    table[i] = crc & 0xff;
  }
  return table;
})();

function crc8(data) {
  let crc = 0;
  for (const byte of data) {
    crc = CRC8_TABLE[(crc ^ byte) & 0xff];
  }
  return crc;
}

// Data type constants
const DATA_TYPES = {
  NOSTR_PUBKEY: 0x01,
  NOSTR_NOTE: 0x02,
  MESH_NODE: 0x03,
  APRS_CALL: 0x04,
  URL: 0x05,
  TEXT: 0x06,
  GEOGRAM_ID: 0x07,
};

const DATA_TYPE_LABELS = {
  0x01: "NOSTR Pubkey",
  0x02: "NOSTR Note",
  0x03: "Mesh Node",
  0x04: "APRS Callsign",
  0x05: "URL",
  0x06: "Text",
  0x07: "Geogram ID",
};

const PROTOCOL_VERSION = 1;
const SYNC_PATTERN = [1, 0, 1, 1, 0, 1, 0, 1]; // Fixed alignment markers
const SEGMENTS_INNER = 8;
const SEGMENTS_DATA = 32;

function encodePayload(text, dataType) {
  const encoder = new TextEncoder();
  const bytes = encoder.encode(text);
  const checksum = crc8(bytes);

  const rings = [];

  // Ring 0: sync pattern (8 segments)
  rings.push([...SYNC_PATTERN]);

  // Ring 1: version (4 bits) + data type (4 bits) → 8 bits, padded to 16 segments
  const versionBits = ((PROTOCOL_VERSION & 0x0f) >>> 0)
    .toString(2)
    .padStart(4, "0")
    .split("")
    .map(Number);
  const typeBits = ((dataType & 0x0f) >>> 0)
    .toString(2)
    .padStart(4, "0")
    .split("")
    .map(Number);
  const metaRing = [...versionBits, ...typeBits];
  // Pad to 16 segments with alternating pattern for visual balance
  while (metaRing.length < 16) metaRing.push(metaRing.length % 2);
  rings.push(metaRing);

  // Ring 2: data length in bytes (32 segments = supports up to 2^32 - but realistically 0-255)
  const lenBits = (bytes.length & 0xff)
    .toString(2)
    .padStart(8, "0")
    .split("")
    .map(Number);
  const lenRing = [...lenBits];
  while (lenRing.length < SEGMENTS_DATA) lenRing.push(0);
  rings.push(lenRing);

  // Data rings: 32 segments each, 4 bytes per ring
  for (let i = 0; i < bytes.length; i += 4) {
    const ring = [];
    for (let j = 0; j < 4; j++) {
      const byte = i + j < bytes.length ? bytes[i + j] : 0;
      const bits = (byte & 0xff).toString(2).padStart(8, "0").split("").map(Number);
      ring.push(...bits);
    }
    rings.push(ring);
  }

  // Checksum ring
  const crcBits = (checksum & 0xff).toString(2).padStart(8, "0").split("").map(Number);
  const crcRing = [...crcBits];
  while (crcRing.length < SEGMENTS_DATA) crcRing.push(crcRing.length % 3 === 0 ? 1 : 0);
  rings.push(crcRing);

  return rings;
}

function decodePayload(rings) {
  if (!rings || rings.length < 4) return { error: "Not enough rings" };

  // Verify sync
  const sync = rings[0];
  for (let i = 0; i < SYNC_PATTERN.length; i++) {
    if (sync[i] !== SYNC_PATTERN[i]) return { error: "Sync pattern mismatch" };
  }

  // Read meta
  const meta = rings[1];
  const version = parseInt(meta.slice(0, 4).join(""), 2);
  const dataType = parseInt(meta.slice(4, 8).join(""), 2);

  if (version !== PROTOCOL_VERSION) return { error: `Unknown version: ${version}` };

  // Read length
  const lenBits = rings[2].slice(0, 8);
  const dataLen = parseInt(lenBits.join(""), 2);

  // Read data bytes
  const bytes = [];
  const dataRings = rings.slice(3, 3 + Math.ceil(dataLen / 4));
  for (const ring of dataRings) {
    for (let j = 0; j < 4 && bytes.length < dataLen; j++) {
      const bits = ring.slice(j * 8, j * 8 + 8);
      bytes.push(parseInt(bits.join(""), 2));
    }
  }

  // Verify checksum
  const crcRing = rings[rings.length - 1];
  const receivedCrc = parseInt(crcRing.slice(0, 8).join(""), 2);
  const computedCrc = crc8(new Uint8Array(bytes));

  if (receivedCrc !== computedCrc) {
    return { error: `CRC mismatch: got ${receivedCrc}, expected ${computedCrc}` };
  }

  const decoder = new TextDecoder();
  const text = decoder.decode(new Uint8Array(bytes));

  return { version, dataType, text, checksum: computedCrc, valid: true };
}

// ============================================================
// Sunburst Renderer
// ============================================================

function drawSunburstCode(ctx, rings, size, options = {}) {
  const {
    bgColor = "#0a0a0a",
    fillColor = "#e88a1a",
    emptyColor = "rgba(232,138,26,0.08)",
    accentColor = "#ff9d2e",
    glowColor = "rgba(232,138,26,0.3)",
    centerImage = null,
  } = options;

  const cx = size / 2;
  const cy = size / 2;
  const maxRadius = size * 0.44;
  const centerRadius = size * 0.1;

  // Background
  ctx.fillStyle = bgColor;
  ctx.fillRect(0, 0, size, size);

  // Outer decorative glow
  const outerGlow = ctx.createRadialGradient(cx, cy, maxRadius * 0.8, cx, cy, maxRadius * 1.2);
  outerGlow.addColorStop(0, "rgba(232,138,26,0.05)");
  outerGlow.addColorStop(1, "transparent");
  ctx.fillStyle = outerGlow;
  ctx.fillRect(0, 0, size, size);

  // Decorative outer sunburst rays
  const numRays = 64;
  for (let i = 0; i < numRays; i++) {
    const angle = (i / numRays) * Math.PI * 2 - Math.PI / 2;
    const isLong = i % 4 === 0;
    const isMed = i % 2 === 0;
    const rayStart = maxRadius + 4;
    const rayEnd = isLong ? maxRadius + 20 : isMed ? maxRadius + 12 : maxRadius + 7;
    const rayWidth = isLong ? 2.5 : isMed ? 1.5 : 0.8;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(angle);
    ctx.beginPath();
    ctx.moveTo(rayStart, 0);
    ctx.lineTo(rayEnd, 0);
    ctx.strokeStyle = isLong ? accentColor : glowColor;
    ctx.lineWidth = rayWidth;
    ctx.lineCap = "round";
    ctx.stroke();
    ctx.restore();

    // Dots at end of long rays
    if (isLong) {
      const dotX = cx + Math.cos(angle) * (rayEnd + 6);
      const dotY = cy + Math.sin(angle) * (rayEnd + 6);
      ctx.beginPath();
      ctx.arc(dotX, dotY, 2.5, 0, Math.PI * 2);
      ctx.fillStyle = accentColor;
      ctx.fill();
    }
  }

  // Draw data rings
  const ringGap = 2;
  const ringWidth = (maxRadius - centerRadius - rings.length * ringGap) / rings.length;

  rings.forEach((ring, ringIdx) => {
    const segments = ring.length;
    const innerR = centerRadius + ringIdx * (ringWidth + ringGap);
    const outerR = innerR + ringWidth;
    const segmentGap = 0.008; // radians

    ring.forEach((bit, segIdx) => {
      const startAngle = (segIdx / segments) * Math.PI * 2 - Math.PI / 2 + segmentGap;
      const endAngle = ((segIdx + 1) / segments) * Math.PI * 2 - Math.PI / 2 - segmentGap;

      ctx.beginPath();
      ctx.arc(cx, cy, outerR, startAngle, endAngle);
      ctx.arc(cx, cy, innerR, endAngle, startAngle, true);
      ctx.closePath();

      if (bit === 1) {
        // Filled segment with slight gradient
        const grad = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR);
        grad.addColorStop(0, fillColor);
        grad.addColorStop(1, accentColor);
        ctx.fillStyle = grad;
        ctx.fill();

        // Subtle glow
        ctx.shadowColor = glowColor;
        ctx.shadowBlur = 3;
        ctx.fill();
        ctx.shadowBlur = 0;
      } else {
        ctx.fillStyle = emptyColor;
        ctx.fill();
      }
    });
  });

  // Center circle
  ctx.beginPath();
  ctx.arc(cx, cy, centerRadius + 2, 0, Math.PI * 2);
  ctx.fillStyle = bgColor;
  ctx.fill();

  ctx.beginPath();
  ctx.arc(cx, cy, centerRadius, 0, Math.PI * 2);
  const centerGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, centerRadius);
  centerGrad.addColorStop(0, "#1a1a1a");
  centerGrad.addColorStop(1, "#0d0d0d");
  ctx.fillStyle = centerGrad;
  ctx.fill();
  ctx.strokeStyle = fillColor;
  ctx.lineWidth = 2;
  ctx.stroke();

  // Geogram logo text in center
  ctx.fillStyle = fillColor;
  ctx.font = `bold ${centerRadius * 0.55}px monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("GEO", cx, cy - centerRadius * 0.15);
  ctx.font = `${centerRadius * 0.35}px monospace`;
  ctx.fillStyle = accentColor;
  ctx.fillText("GRAM", cx, cy + centerRadius * 0.3);

  // Corner markers (alignment references for camera scanning)
  const markerSize = 8;
  const markerOffset = 15;
  const corners = [
    [markerOffset, markerOffset],
    [size - markerOffset, markerOffset],
    [markerOffset, size - markerOffset],
    [size - markerOffset, size - markerOffset],
  ];
  corners.forEach(([x, y]) => {
    ctx.beginPath();
    ctx.arc(x, y, markerSize, 0, Math.PI * 2);
    ctx.fillStyle = fillColor;
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x, y, markerSize - 3, 0, Math.PI * 2);
    ctx.fillStyle = bgColor;
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x, y, 2, 0, Math.PI * 2);
    ctx.fillStyle = fillColor;
    ctx.fill();
  });
}

// ============================================================
// Simulated Scanner (reads from canvas pixel data)
// ============================================================

function scanFromCanvas(sourceCanvas, size) {
  const ctx = sourceCanvas.getContext("2d");
  const cx = size / 2;
  const cy = size / 2;
  const maxRadius = size * 0.44;
  const centerRadius = size * 0.1;

  // We need to figure out ring count by sampling
  // For the demo, we'll re-derive from known structure
  // In real implementation, this would use image processing

  const rings = [];
  const possibleRingCounts = [8, 16, 32];
  const ringGap = 2;

  // Try to detect rings by sampling at known positions
  // First, estimate total rings by sampling radially
  const testAngles = [0, Math.PI / 4, Math.PI / 2, Math.PI];
  let detectedRings = 0;

  for (let r = centerRadius + 5; r < maxRadius - 5; r += 3) {
    const px = Math.round(cx + r);
    const py = Math.round(cy);
    if (px >= 0 && px < size && py >= 0 && py < size) {
      const pixel = ctx.getImageData(px, py, 1, 1).data;
      const brightness = (pixel[0] + pixel[1] + pixel[2]) / 3;
      if (brightness > 80) {
        detectedRings++;
        r += 8; // skip ahead past this ring
      }
    }
  }

  return null; // In real implementation, this would return decoded rings
}

// ============================================================
// React UI
// ============================================================

const THEMES = {
  amber: {
    fillColor: "#e88a1a",
    accentColor: "#ff9d2e",
    glowColor: "rgba(232,138,26,0.3)",
    bgColor: "#0a0a0a",
    emptyColor: "rgba(232,138,26,0.08)",
    label: "Amber",
    uiBg: "#111",
    uiText: "#e88a1a",
    uiBorder: "#e88a1a33",
  },
  green: {
    fillColor: "#22c55e",
    accentColor: "#4ade80",
    glowColor: "rgba(34,197,94,0.3)",
    bgColor: "#0a0a0a",
    emptyColor: "rgba(34,197,94,0.08)",
    label: "Terminal Green",
    uiBg: "#0a110a",
    uiText: "#22c55e",
    uiBorder: "#22c55e33",
  },
  cyan: {
    fillColor: "#06b6d4",
    accentColor: "#22d3ee",
    glowColor: "rgba(6,182,212,0.3)",
    bgColor: "#0a0a0a",
    emptyColor: "rgba(6,182,212,0.08)",
    label: "Ice Cyan",
    uiBg: "#0a0f11",
    uiText: "#06b6d4",
    uiBorder: "#06b6d433",
  },
  red: {
    fillColor: "#ef4444",
    accentColor: "#f87171",
    glowColor: "rgba(239,68,68,0.3)",
    bgColor: "#0a0a0a",
    emptyColor: "rgba(239,68,68,0.08)",
    label: "Emergency Red",
    uiBg: "#110a0a",
    uiText: "#ef4444",
    uiBorder: "#ef444433",
  },
};

export default function GeogramSunburstCode() {
  const canvasRef = useRef(null);
  const [inputText, setInputText] = useState("npub1example...");
  const [dataType, setDataType] = useState(DATA_TYPES.NOSTR_PUBKEY);
  const [theme, setTheme] = useState("amber");
  const [encodedRings, setEncodedRings] = useState(null);
  const [decoded, setDecoded] = useState(null);
  const [showSpec, setShowSpec] = useState(false);
  const [canvasSize] = useState(440);

  const generate = useCallback(() => {
    if (!inputText.trim()) return;
    const rings = encodePayload(inputText.trim(), dataType);
    setEncodedRings(rings);
    // Immediately decode to verify roundtrip
    const result = decodePayload(rings);
    setDecoded(result);
  }, [inputText, dataType]);

  useEffect(() => {
    generate();
  }, []);

  useEffect(() => {
    if (!encodedRings || !canvasRef.current) return;
    const ctx = canvasRef.current.getContext("2d");
    const t = THEMES[theme];
    drawSunburstCode(ctx, encodedRings, canvasSize, {
      fillColor: t.fillColor,
      accentColor: t.accentColor,
      glowColor: t.glowColor,
      bgColor: t.bgColor,
      emptyColor: t.emptyColor,
    });
  }, [encodedRings, theme, canvasSize]);

  const t = THEMES[theme];

  const downloadCode = () => {
    if (!canvasRef.current) return;
    const link = document.createElement("a");
    link.download = "geogram-sunburst-code.png";
    link.href = canvasRef.current.toDataURL("image/png");
    link.click();
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: t.uiBg,
        color: t.uiText,
        fontFamily: "'Courier New', monospace",
        padding: "20px",
        transition: "all 0.3s ease",
      }}
    >
      {/* Header */}
      <div style={{ textAlign: "center", marginBottom: 24 }}>
        <h1
          style={{
            fontSize: 28,
            fontWeight: 800,
            letterSpacing: 6,
            margin: 0,
            textTransform: "uppercase",
            textShadow: `0 0 20px ${t.glowColor}`,
          }}
        >
          ⟐ GEOGRAM SUNBURST CODE ⟐
        </h1>
        <p style={{ fontSize: 12, opacity: 0.6, marginTop: 4, letterSpacing: 3 }}>
          PROPRIETARY RADIAL ENCODING — v{PROTOCOL_VERSION}.0
        </p>
      </div>

      <div
        style={{
          display: "flex",
          gap: 24,
          maxWidth: 960,
          margin: "0 auto",
          flexWrap: "wrap",
          justifyContent: "center",
        }}
      >
        {/* Left panel: Controls */}
        <div style={{ flex: "1 1 280px", maxWidth: 400 }}>
          {/* Theme selector */}
          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 10, letterSpacing: 2, opacity: 0.6, display: "block", marginBottom: 6 }}>
              COLOR SCHEME
            </label>
            <div style={{ display: "flex", gap: 6 }}>
              {Object.entries(THEMES).map(([key, val]) => (
                <button
                  key={key}
                  onClick={() => setTheme(key)}
                  style={{
                    flex: 1,
                    padding: "6px 8px",
                    background: theme === key ? val.fillColor + "22" : "transparent",
                    border: `1px solid ${theme === key ? val.fillColor : val.fillColor + "44"}`,
                    color: val.fillColor,
                    fontFamily: "inherit",
                    fontSize: 10,
                    cursor: "pointer",
                    letterSpacing: 1,
                    transition: "all 0.2s",
                  }}
                >
                  {val.label}
                </button>
              ))}
            </div>
          </div>

          {/* Data type */}
          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 10, letterSpacing: 2, opacity: 0.6, display: "block", marginBottom: 6 }}>
              DATA TYPE
            </label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
              {Object.entries(DATA_TYPES).map(([key, val]) => (
                <button
                  key={key}
                  onClick={() => setDataType(val)}
                  style={{
                    padding: "5px 10px",
                    background: dataType === val ? t.fillColor + "22" : "transparent",
                    border: `1px solid ${dataType === val ? t.fillColor : t.uiBorder}`,
                    color: dataType === val ? t.uiText : t.uiText + "88",
                    fontFamily: "inherit",
                    fontSize: 9,
                    cursor: "pointer",
                    letterSpacing: 1,
                    transition: "all 0.2s",
                  }}
                >
                  {key.replace(/_/g, " ")}
                </button>
              ))}
            </div>
          </div>

          {/* Input */}
          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 10, letterSpacing: 2, opacity: 0.6, display: "block", marginBottom: 6 }}>
              PAYLOAD DATA
            </label>
            <textarea
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              style={{
                width: "100%",
                minHeight: 80,
                background: "rgba(255,255,255,0.03)",
                border: `1px solid ${t.uiBorder}`,
                color: t.uiText,
                fontFamily: "inherit",
                fontSize: 13,
                padding: 10,
                resize: "vertical",
                boxSizing: "border-box",
                outline: "none",
              }}
              placeholder="Enter data to encode..."
            />
            <div style={{ fontSize: 10, opacity: 0.4, marginTop: 4 }}>
              {new TextEncoder().encode(inputText).length} bytes → {encodedRings ? encodedRings.length : 0} rings
            </div>
          </div>

          {/* Generate button */}
          <button
            onClick={generate}
            style={{
              width: "100%",
              padding: "12px",
              background: t.fillColor,
              border: "none",
              color: "#000",
              fontFamily: "inherit",
              fontSize: 14,
              fontWeight: 700,
              letterSpacing: 3,
              cursor: "pointer",
              marginBottom: 8,
              transition: "all 0.2s",
            }}
          >
            ▶ ENCODE
          </button>

          <button
            onClick={downloadCode}
            style={{
              width: "100%",
              padding: "10px",
              background: "transparent",
              border: `1px solid ${t.uiBorder}`,
              color: t.uiText,
              fontFamily: "inherit",
              fontSize: 11,
              letterSpacing: 2,
              cursor: "pointer",
              marginBottom: 16,
            }}
          >
            ↓ DOWNLOAD PNG
          </button>

          {/* Decode result */}
          {decoded && (
            <div
              style={{
                background: "rgba(255,255,255,0.02)",
                border: `1px solid ${t.uiBorder}`,
                padding: 12,
                marginBottom: 16,
              }}
            >
              <div style={{ fontSize: 10, letterSpacing: 2, opacity: 0.6, marginBottom: 8 }}>
                DECODE VERIFICATION
              </div>
              {decoded.valid ? (
                <div>
                  <div style={{ color: "#22c55e", fontSize: 13, marginBottom: 6 }}>✓ VALID — CRC OK</div>
                  <div style={{ fontSize: 11, opacity: 0.7 }}>
                    Version: {decoded.version} &nbsp;|&nbsp; Type: {DATA_TYPE_LABELS[decoded.dataType]}
                  </div>
                  <div
                    style={{
                      fontSize: 11,
                      marginTop: 6,
                      wordBreak: "break-all",
                      padding: "6px 8px",
                      background: "rgba(255,255,255,0.03)",
                      border: `1px solid ${t.uiBorder}`,
                    }}
                  >
                    {decoded.text}
                  </div>
                  <div style={{ fontSize: 9, opacity: 0.4, marginTop: 4 }}>
                    CRC-8: 0x{decoded.checksum.toString(16).padStart(2, "0").toUpperCase()}
                  </div>
                </div>
              ) : (
                <div style={{ color: "#ef4444" }}>✗ {decoded.error}</div>
              )}
            </div>
          )}
        </div>

        {/* Right panel: Canvas */}
        <div style={{ flex: "0 0 auto", display: "flex", flexDirection: "column", alignItems: "center" }}>
          <canvas
            ref={canvasRef}
            width={canvasSize}
            height={canvasSize}
            style={{
              border: `1px solid ${t.uiBorder}`,
              boxShadow: `0 0 40px ${t.glowColor}, inset 0 0 40px rgba(0,0,0,0.5)`,
            }}
          />

          {/* Ring legend */}
          {encodedRings && (
            <div
              style={{
                marginTop: 12,
                fontSize: 9,
                opacity: 0.5,
                textAlign: "center",
                lineHeight: 1.8,
                maxWidth: canvasSize,
              }}
            >
              RING 0: SYNC ({SEGMENTS_INNER} seg) → RING 1: META (16 seg) → RING 2: LENGTH (32 seg) →
              RINGS 3–{encodedRings.length - 2}: DATA (32 seg each) → RING {encodedRings.length - 1}: CRC-8
            </div>
          )}
        </div>
      </div>

      {/* Spec toggle */}
      <div style={{ maxWidth: 960, margin: "24px auto 0" }}>
        <button
          onClick={() => setShowSpec(!showSpec)}
          style={{
            background: "transparent",
            border: `1px solid ${t.uiBorder}`,
            color: t.uiText,
            fontFamily: "inherit",
            fontSize: 11,
            padding: "8px 16px",
            cursor: "pointer",
            letterSpacing: 2,
            width: "100%",
          }}
        >
          {showSpec ? "▼" : "▶"} ENCODING SPECIFICATION
        </button>

        {showSpec && (
          <div
            style={{
              background: "rgba(255,255,255,0.02)",
              border: `1px solid ${t.uiBorder}`,
              borderTop: "none",
              padding: 16,
              fontSize: 11,
              lineHeight: 1.8,
              opacity: 0.8,
            }}
          >
            <pre
              style={{
                margin: 0,
                whiteSpace: "pre-wrap",
                fontFamily: "inherit",
                color: t.uiText,
              }}
            >{`GEOGRAM SUNBURST CODE — ENCODING SPEC v1.0
════════════════════════════════════════════

STRUCTURE (center → outward):
┌─────────┬──────────┬─────────────────────────────────┐
│ Ring    │ Segments │ Purpose                         │
├─────────┼──────────┼─────────────────────────────────┤
│ Center  │    —     │ Logo / avatar (decorative)       │
│ Ring 0  │    8     │ Sync markers (fixed: 10110101)  │
│ Ring 1  │   16     │ Version (4b) + Type (4b) + pad  │
│ Ring 2  │   32     │ Data length in bytes             │
│ Ring 3+ │   32     │ Payload (4 bytes/ring, MSB)      │
│ Ring N  │   32     │ CRC-8 checksum                   │
│ Outer   │    —     │ Decorative sunburst rays         │
└─────────┴──────────┴─────────────────────────────────┘

ALIGNMENT:
• 4 corner bullseye markers for perspective correction
• Ring 0 sync pattern for rotational alignment
• Segment gaps (0.008 rad) for boundary detection

DATA TYPES:
  0x01  NOSTR Public Key
  0x02  NOSTR Note ID
  0x03  Mesh Node Identifier
  0x04  APRS Callsign
  0x05  URL
  0x06  Freeform Text
  0x07  Geogram User ID

INTEGRITY:
• CRC-8 (polynomial 0x07) over raw payload bytes
• Roundtrip verification on encode

SCANNING (Dart implementation):
1. Detect corner markers → compute perspective transform
2. Find center → establish polar coordinate system
3. Read Ring 0 → determine rotational offset
4. Sample segments at known radii → extract bits
5. Decode payload → verify CRC

CAPACITY:
  Max ~60 bytes per code (practical)
  ~15 rings at 32 segments = 480 bits payload
  Sufficient for: NOSTR keys, callsigns, short URLs`}</pre>
          </div>
        )}
      </div>

      {/* Dart implementation hint */}
      <div
        style={{
          maxWidth: 960,
          margin: "16px auto 0",
          padding: 12,
          border: `1px solid ${t.uiBorder}`,
          background: "rgba(255,255,255,0.02)",
          fontSize: 10,
          opacity: 0.6,
          lineHeight: 1.6,
        }}
      >
        <strong>DART IMPLEMENTATION:</strong> Encode with Canvas (CustomPainter) → Decode with camera + image
        package: detect corners (OpenCV via FFI or custom), polar transform, sample rings at known radii,
        extract bits per segment, reconstruct bytes, verify CRC-8. No external QR library needed.
      </div>
    </div>
  );
}
