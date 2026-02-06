import { useState, useRef, useEffect, useCallback } from "react";

// ============================================================
// GEOGRAM RADIAL CODE — Full Encoder/Decoder
// ============================================================
//
// ENCODING SPEC:
//
// Layout (center outward):
//   Center zone: avatar/logo (no data)
//   4 bullseye markers at fixed angles (alignment, no data)
//   6 radial bands × ~52 angular positions = ~312 data slots
//   Each slot = 1 bit encoded as ray presence/absence
//   Outer decorative rays (no data, deterministic from seed)
//
// Bit mapping per slot:
//   bit=1 → ray segment drawn (style varies by position hash)
//   bit=0 → no ray segment
//
// Ray styles (deterministic from position, not data-bearing):
//   - Thick bar    (hash 0-3)
//   - Medium bar   (hash 4-6)
//   - Thin line    (hash 7-8)
//   - Dot          (hash 9-10)
//   - Short dash   (hash 11)
//
// Data structure:
//   [version 8b][type 8b][length 16b][crc8 8b][payload Nb]
//   Total header: 5 bytes = 40 bits
//   Max payload: ~34 bytes at current density (312 - 40 = 272 data bits)
//
// Alignment:
//   4 bullseye markers establish polar coordinate system
//   Angular position 0 = top (12 o'clock), clockwise
//   Band 0 = innermost, Band 5 = outermost
//
// Decode pipeline:
//   1. Find 4 bullseyes → establish center + rotation
//   2. Compute angular grid from known bullseye angles
//   3. For each slot: sample region, threshold → bit
//   4. Reconstruct bytes → verify CRC
// ============================================================

// --- CRC-8 ---
const CRC8_TABLE = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
  let c = i;
  for (let j = 0; j < 8; j++) c = c & 0x80 ? (c << 1) ^ 0x07 : c << 1;
  CRC8_TABLE[i] = c & 0xff;
}
function crc8(data) {
  let c = 0;
  for (let i = 0; i < data.length; i++) c = CRC8_TABLE[(c ^ data[i]) & 0xff];
  return c;
}

// --- Encoder ---
function encodePayload(text, dataType = 0x06) {
  const raw = new TextEncoder().encode(text);
  const crc = crc8(raw);
  const header = new Uint8Array([
    0x01,                           // version
    dataType & 0xff,                // data type
    (raw.length >> 8) & 0xff,       // length high
    raw.length & 0xff,              // length low
    crc,                            // CRC-8
  ]);
  const payload = new Uint8Array(header.length + raw.length);
  payload.set(header);
  payload.set(raw, header.length);

  // Convert to bits
  const bits = [];
  for (let i = 0; i < payload.length; i++) {
    for (let b = 7; b >= 0; b--) bits.push((payload[i] >> b) & 1);
  }
  return { bits, byteCount: payload.length, dataBytes: raw.length };
}

// --- Decoder ---
function decodeBits(bits) {
  if (bits.length < 40) return { error: "Too few bits for header" };

  // Read header bytes
  const readByte = (offset) => {
    let v = 0;
    for (let i = 0; i < 8; i++) v = (v << 1) | (bits[offset + i] || 0);
    return v;
  };

  const version = readByte(0);
  const dataType = readByte(8);
  const lenHi = readByte(16);
  const lenLo = readByte(24);
  const expectedCrc = readByte(32);
  const dataLen = (lenHi << 8) | lenLo;

  if (version !== 0x01) return { error: `Unknown version: ${version}` };
  if (dataLen <= 0 || dataLen > 256) return { error: `Invalid length: ${dataLen}` };

  const totalBits = (5 + dataLen) * 8;
  if (bits.length < totalBits) return { error: `Need ${totalBits} bits, have ${bits.length}` };

  // Read data bytes
  const data = new Uint8Array(dataLen);
  for (let i = 0; i < dataLen; i++) data[i] = readByte(40 + i * 8);

  const computedCrc = crc8(data);
  if (computedCrc !== expectedCrc) {
    return { error: `CRC mismatch: expected 0x${expectedCrc.toString(16)}, got 0x${computedCrc.toString(16)}` };
  }

  return {
    valid: true,
    version,
    dataType,
    byteCount: dataLen,
    checksum: computedCrc,
    text: new TextDecoder().decode(data),
  };
}

// --- Layout engine ---
// Defines the physical position of every data slot

const NUM_ANGLES = 60;
const NUM_BANDS = 6;
const BULLSEYE_ANGLE_INDICES = [4, 19, 34, 49]; // fixed positions in the 60-slot ring

function buildSlotMap() {
  // Pre-compute which angular positions are blocked by bullseyes
  const blocked = new Set();
  for (const bi of BULLSEYE_ANGLE_INDICES) {
    blocked.add(bi);
    blocked.add((bi - 1 + NUM_ANGLES) % NUM_ANGLES);
    blocked.add((bi + 1) % NUM_ANGLES);
  }

  // Build ordered slot list: band-major order (all angles for band 0, then band 1, etc.)
  // This ensures inner bands carry header data (more protected from edge damage)
  const slots = [];
  for (let band = 0; band < NUM_BANDS; band++) {
    for (let ai = 0; ai < NUM_ANGLES; ai++) {
      if (blocked.has(ai)) continue;
      slots.push({ angleIdx: ai, band });
    }
  }
  return slots;
}

const SLOT_MAP = buildSlotMap();
const MAX_BITS = SLOT_MAP.length; // ~312

function mapBitsToSlots(bits) {
  return SLOT_MAP.map((slot, i) => ({
    ...slot,
    bit: i < bits.length ? bits[i] : 0,
    dataIndex: i,
  }));
}

// --- Ray style hash (deterministic, not data-bearing) ---
function rayStyle(angleIdx, band) {
  const h = ((angleIdx * 7 + band * 13 + 3) * 31) % 12;
  if (h < 4) return "thick";
  if (h < 7) return "medium";
  if (h < 9) return "thin";
  if (h < 11) return "dot";
  return "dash";
}

// ============================================================
// Renderer
// ============================================================

function drawRadialCode(ctx, slots, size, opts = {}) {
  const {
    theme = "light",
    avatarText = "GEO",
    avatarSub = "",
  } = opts;

  const cx = size / 2, cy = size / 2;
  const centerR = size * 0.12;
  const innerR = size * 0.155;
  const outerR = size * 0.395;
  const bandW = (outerR - innerR) / NUM_BANDS;
  const angleStep = (Math.PI * 2) / NUM_ANGLES;

  const bg = theme === "dark" ? "#1a1a1a" : "#ffffff";
  const fg = theme === "dark" ? "#ffffff" : "#000000";

  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, size, size);

  // --- Draw data rays ---
  for (const slot of slots) {
    if (slot.bit === 0) continue;

    const angle = slot.angleIdx * angleStep - Math.PI / 2;
    const cosA = Math.cos(angle), sinA = Math.sin(angle);
    const r1 = innerR + slot.band * bandW + bandW * 0.12;
    const r2 = innerR + (slot.band + 1) * bandW - bandW * 0.12;
    const style = rayStyle(slot.angleIdx, slot.band);

    ctx.strokeStyle = fg;
    ctx.fillStyle = fg;
    ctx.lineCap = "round";

    switch (style) {
      case "thick": {
        const x1 = cx + cosA * r1, y1 = cy + sinA * r1;
        const x2 = cx + cosA * r2, y2 = cy + sinA * r2;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
        ctx.lineWidth = size * 0.014 + slot.band * 0.5;
        ctx.stroke();
        break;
      }
      case "medium": {
        const x1 = cx + cosA * r1, y1 = cy + sinA * r1;
        const x2 = cx + cosA * r2, y2 = cy + sinA * r2;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
        ctx.lineWidth = size * 0.010 + slot.band * 0.4;
        ctx.stroke();
        break;
      }
      case "thin": {
        const x1 = cx + cosA * r1, y1 = cy + sinA * r1;
        const x2 = cx + cosA * r2, y2 = cy + sinA * r2;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
        ctx.lineWidth = size * 0.007 + slot.band * 0.3;
        ctx.stroke();
        break;
      }
      case "dot": {
        const mr = (r1 + r2) / 2;
        ctx.beginPath();
        ctx.arc(cx + cosA * mr, cy + sinA * mr, size * 0.008 + slot.band * 0.5, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case "dash": {
        const mr1 = r1 + (r2 - r1) * 0.15, mr2 = r1 + (r2 - r1) * 0.85;
        ctx.beginPath();
        ctx.moveTo(cx + cosA * mr1, cy + sinA * mr1);
        ctx.lineTo(cx + cosA * mr2, cy + sinA * mr2);
        ctx.lineWidth = size * 0.009;
        ctx.stroke();
        break;
      }
    }
  }

  // --- Merge adjacent 1-bits into connected rays for visual coherence ---
  // Group by angle, find contiguous band runs
  const byAngle = {};
  for (const s of slots) {
    if (!byAngle[s.angleIdx]) byAngle[s.angleIdx] = [];
    byAngle[s.angleIdx].push(s);
  }
  for (const [ai, aSlots] of Object.entries(byAngle)) {
    const sorted = aSlots.sort((a, b) => a.band - b.band);
    let runStart = null;
    for (let i = 0; i <= sorted.length; i++) {
      const s = sorted[i];
      if (s && s.bit === 1) {
        if (runStart === null) runStart = i;
      } else {
        if (runStart !== null && i - runStart >= 2) {
          // Draw connecting line across the run
          const first = sorted[runStart], last = sorted[i - 1];
          const angle = first.angleIdx * angleStep - Math.PI / 2;
          const cosA = Math.cos(angle), sinA = Math.sin(angle);
          const rA = innerR + first.band * bandW + bandW * 0.12;
          const rB = innerR + (last.band + 1) * bandW - bandW * 0.12;
          ctx.beginPath();
          ctx.moveTo(cx + cosA * rA, cy + sinA * rA);
          ctx.lineTo(cx + cosA * rB, cy + sinA * rB);
          ctx.strokeStyle = fg;
          ctx.lineWidth = size * 0.005;
          ctx.lineCap = "round";
          ctx.globalAlpha = 0.4;
          ctx.stroke();
          ctx.globalAlpha = 1;
        }
        runStart = null;
      }
    }
  }

  // --- Decorative outer rays (deterministic, no data) ---
  for (let ai = 0; ai < NUM_ANGLES; ai++) {
    const angle = ai * angleStep - Math.PI / 2;
    const cosA = Math.cos(angle), sinA = Math.sin(angle);

    let nearBE = false;
    for (const bei of BULLSEYE_ANGLE_INDICES) {
      const diff = Math.min(Math.abs(ai - bei), NUM_ANGLES - Math.abs(ai - bei));
      if (diff < 2) { nearBE = true; break; }
    }
    if (nearBE) continue;

    const seed = ((ai * 31 + 7) % 20);
    const rStart = outerR + size * 0.008;

    if (seed < 6) {
      const rEnd = rStart + size * 0.018 + (seed / 20) * size * 0.035;
      ctx.beginPath();
      ctx.moveTo(cx + cosA * rStart, cy + sinA * rStart);
      ctx.lineTo(cx + cosA * rEnd, cy + sinA * rEnd);
      ctx.strokeStyle = fg;
      ctx.lineWidth = seed < 3 ? size * 0.010 : size * 0.007;
      ctx.lineCap = "round";
      ctx.stroke();
    } else if (seed < 10) {
      const rDot = rStart + size * 0.014 + (seed / 30) * size * 0.015;
      ctx.beginPath();
      ctx.arc(cx + cosA * rDot, cy + sinA * rDot, size * 0.005 + (seed % 3) * 0.8, 0, Math.PI * 2);
      ctx.fillStyle = fg;
      ctx.fill();
    }
  }

  // --- Bullseye markers ---
  const bullR = (innerR + outerR) * 0.52;
  const bullSize = size * 0.038;
  for (const bei of BULLSEYE_ANGLE_INDICES) {
    const angle = bei * angleStep - Math.PI / 2;
    const bx = cx + Math.cos(angle) * bullR;
    const by = cy + Math.sin(angle) * bullR;

    ctx.beginPath(); ctx.arc(bx, by, bullSize, 0, Math.PI * 2);
    ctx.fillStyle = fg; ctx.fill();
    ctx.beginPath(); ctx.arc(bx, by, bullSize * 0.65, 0, Math.PI * 2);
    ctx.fillStyle = bg; ctx.fill();
    ctx.beginPath(); ctx.arc(bx, by, bullSize * 0.35, 0, Math.PI * 2);
    ctx.fillStyle = fg; ctx.fill();
  }

  // --- Center avatar zone ---
  ctx.beginPath(); ctx.arc(cx, cy, centerR + size * 0.012, 0, Math.PI * 2);
  ctx.fillStyle = bg; ctx.fill();

  const avSize = centerR * 1.4;
  const avX = cx - avSize / 2, avY = cy - avSize / 2;
  const cr = avSize * 0.15;
  ctx.beginPath();
  ctx.moveTo(avX + cr, avY);
  ctx.lineTo(avX + avSize - cr, avY); ctx.arcTo(avX + avSize, avY, avX + avSize, avY + cr, cr);
  ctx.lineTo(avX + avSize, avY + avSize - cr); ctx.arcTo(avX + avSize, avY + avSize, avX + avSize - cr, avY + avSize, cr);
  ctx.lineTo(avX + cr, avY + avSize); ctx.arcTo(avX, avY + avSize, avX, avY + avSize - cr, cr);
  ctx.lineTo(avX, avY + cr); ctx.arcTo(avX, avY, avX + cr, avY, cr);
  ctx.closePath();

  const avGrad = ctx.createLinearGradient(avX, avY, avX + avSize, avY + avSize);
  avGrad.addColorStop(0, theme === "dark" ? "#2a2a2a" : "#f0f0f0");
  avGrad.addColorStop(1, theme === "dark" ? "#1a1a1a" : "#e0e0e0");
  ctx.fillStyle = avGrad; ctx.fill();
  ctx.strokeStyle = theme === "dark" ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)";
  ctx.lineWidth = 1; ctx.stroke();

  ctx.fillStyle = fg;
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
  if (avatarSub) {
    ctx.font = `bold ${avSize * 0.32}px -apple-system, 'Helvetica Neue', sans-serif`;
    ctx.fillText(avatarText, cx, cy - avSize * 0.1);
    ctx.font = `${avSize * 0.18}px -apple-system, 'Helvetica Neue', sans-serif`;
    ctx.fillStyle = theme === "dark" ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.4)";
    ctx.fillText(avatarSub, cx, cy + avSize * 0.2);
  } else {
    ctx.font = `bold ${avSize * 0.35}px -apple-system, 'Helvetica Neue', sans-serif`;
    ctx.fillText(avatarText, cx, cy);
  }
}

// --- Card wrapper ---
function drawCard(ctx, slots, codeSize, cardW, cardH, opts = {}) {
  const { theme = "light", label = "", sublabel = "", brandColor = "#d4a053" } = opts;
  const bg = theme === "dark" ? "#111111" : "#f8f8f8";
  const codeBg = theme === "dark" ? "#1a1a1a" : "#ffffff";
  const fg = theme === "dark" ? "#ffffff" : "#1a1a1a";

  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, cardW, cardH);

  const codeX = (cardW - codeSize) / 2, codeY = cardW * 0.06;
  const pad = codeSize * 0.03;
  ctx.fillStyle = codeBg;
  ctx.fillRect(codeX - pad, codeY - pad, codeSize + pad * 2, codeSize + pad * 2);

  ctx.save(); ctx.translate(codeX, codeY);
  drawRadialCode(ctx, slots, codeSize, opts);
  ctx.restore();

  if (label) {
    ctx.fillStyle = fg;
    ctx.font = `500 ${cardW * 0.038}px -apple-system, 'Helvetica Neue', sans-serif`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(`"${label}"`, cardW / 2, codeY + codeSize + cardW * 0.055);
  }

  const barH = cardW * 0.11;
  ctx.fillStyle = brandColor;
  ctx.fillRect(0, cardH - barH, cardW, barH);
  if (sublabel) {
    ctx.fillStyle = "#000";
    ctx.font = `600 ${cardW * 0.03}px -apple-system, 'Helvetica Neue', sans-serif`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(sublabel, cardW / 2, cardH - barH / 2);
  }
}

// ============================================================
// UI
// ============================================================

const DATA_TYPES = {
  0x01: "NOSTR Pubkey", 0x03: "Mesh Node", 0x04: "APRS Callsign",
  0x05: "URL", 0x06: "Text", 0x07: "Geogram ID",
};

const BRAND_COLORS = {
  gold: "#d4a053", green: "#4abe7b", blue: "#4a90d9",
  red: "#d94a4a", purple: "#8b5cf6",
};

export default function GeogramRadialEncoder() {
  const cardRef = useRef(null);
  const [input, setInput] = useState("npub1geogram7examplekey42nostr");
  const [dt, setDt] = useState(0x07);
  const [theme, setTheme] = useState("dark");
  const [brand, setBrand] = useState("gold");
  const [avatarText, setAvatarText] = useState("GEO");
  const [avatarSub, setAvatarSub] = useState("GRAM");
  const [label, setLabel] = useState("Geogram Node");
  const [sublabel, setSublabel] = useState("PP1BRT-7 的 Geogram 码");
  const [decoded, setDecoded] = useState(null);
  const [stats, setStats] = useState(null);

  const codeSize = 400;
  const cardW = 480;
  const cardH = cardW * 1.22;

  const generate = useCallback(() => {
    const text = input.slice(0, 256);
    const { bits, byteCount, dataBytes } = encodePayload(text, dt);

    if (bits.length > MAX_BITS) {
      setDecoded({ error: `Payload too large: ${bits.length} bits > ${MAX_BITS} capacity` });
      setStats({ bits: bits.length, maxBits: MAX_BITS, bytes: byteCount, overflow: true });
      return;
    }

    const slots = mapBitsToSlots(bits);
    const onesCount = slots.filter(s => s.bit === 1).length;

    // Draw
    if (cardRef.current) {
      const ctx = cardRef.current.getContext("2d");
      drawCard(ctx, slots, codeSize, cardW, cardH, {
        theme, label, sublabel,
        brandColor: BRAND_COLORS[brand],
        avatarText, avatarSub,
      });
    }

    // Verify roundtrip
    const recoveredBits = slots.map(s => s.bit);
    const dec = decodeBits(recoveredBits);
    setDecoded(dec);
    setStats({
      bits: bits.length, maxBits: MAX_BITS, bytes: byteCount, dataBytes,
      slots: SLOT_MAP.length, onesCount, zerosCount: slots.length - onesCount,
      density: (onesCount / slots.length * 100).toFixed(1),
      utilization: (bits.length / MAX_BITS * 100).toFixed(1),
      overflow: false,
    });
  }, [input, dt, theme, brand, avatarText, avatarSub, label, sublabel]);

  useEffect(() => { generate(); }, []);

  const bytes = new TextEncoder().encode(input).length;
  const maxBytes = Math.floor((MAX_BITS - 40) / 8); // subtract header bits

  return (
    <div style={{
      minHeight: "100vh",
      background: theme === "dark" ? "#08080a" : "#f0f0f0",
      color: theme === "dark" ? "#d4d4d8" : "#333",
      fontFamily: "-apple-system, 'Helvetica Neue', sans-serif",
      padding: 20, transition: "all 0.3s",
    }}>
      <div style={{ maxWidth: 1000, margin: "0 auto" }}>
        <div style={{ textAlign: "center", marginBottom: 20 }}>
          <h1 style={{ fontSize: 22, fontWeight: 600, margin: 0, color: theme === "dark" ? "#e88a1a" : "#333" }}>
            Geogram Radial Code Encoder
          </h1>
          <p style={{ fontSize: 11, opacity: 0.5, marginTop: 4 }}>
            {SLOT_MAP.length} data slots • {maxBytes} byte capacity • {NUM_ANGLES} angles × {NUM_BANDS} bands
          </p>
        </div>

        <div style={{ display: "flex", gap: 20, flexWrap: "wrap", justifyContent: "center" }}>
          {/* Canvas */}
          <div style={{ textAlign: "center" }}>
            <canvas ref={cardRef} width={cardW} height={cardH}
              style={{
                width: cardW, height: cardH, borderRadius: 14,
                boxShadow: theme === "dark" ? "0 8px 40px rgba(0,0,0,0.5)" : "0 8px 40px rgba(0,0,0,0.12)",
              }}
            />
            <div style={{ marginTop: 10, display: "flex", gap: 8, justifyContent: "center" }}>
              <button onClick={() => {
                if (!cardRef.current) return;
                const a = document.createElement("a");
                a.download = "geogram-radial-code.png";
                a.href = cardRef.current.toDataURL("image/png"); a.click();
              }} style={{
                padding: "8px 20px", background: BRAND_COLORS[brand], border: "none",
                borderRadius: 8, color: "#fff", fontWeight: 600, fontSize: 13, cursor: "pointer",
              }}>Download PNG</button>
              <button onClick={generate} style={{
                padding: "8px 20px",
                background: theme === "dark" ? "#222" : "#e0e0e0",
                border: "none", borderRadius: 8,
                color: theme === "dark" ? "#fff" : "#333",
                fontWeight: 600, fontSize: 13, cursor: "pointer",
              }}>Regenerate</button>
            </div>
          </div>

          {/* Controls */}
          <div style={{ flex: "1 1 280px", maxWidth: 400, display: "flex", flexDirection: "column", gap: 12 }}>
            {/* Data input */}
            <Panel title="DATA" theme={theme}>
              <textarea value={input} onChange={e => setInput(e.target.value.slice(0, 256))}
                style={{
                  ...inputStyle(theme), width: "100%", height: 64, resize: "none",
                  fontFamily: "'SF Mono', monospace", fontSize: 11,
                }}
              />
              <div style={{ display: "flex", gap: 6, marginTop: 6, alignItems: "center" }}>
                <select value={dt} onChange={e => setDt(parseInt(e.target.value))}
                  style={{ ...inputStyle(theme), flex: 1, padding: 5, fontSize: 11 }}>
                  {Object.entries(DATA_TYPES).map(([v, l]) => (
                    <option key={v} value={v}>{l}</option>
                  ))}
                </select>
                <span style={{ fontSize: 10, opacity: 0.5 }}>{bytes}/{maxBytes}B</span>
              </div>
              {bytes > maxBytes && (
                <div style={{ fontSize: 10, color: "#ef4444", marginTop: 4 }}>
                  ⚠ Payload exceeds capacity by {bytes - maxBytes} bytes
                </div>
              )}
            </Panel>

            {/* Appearance */}
            <Panel title="APPEARANCE" theme={theme}>
              <div style={{ display: "flex", gap: 6, marginBottom: 8 }}>
                {["light", "dark"].map(t => (
                  <button key={t} onClick={() => setTheme(t)} style={{
                    flex: 1, padding: "5px 10px", borderRadius: 6,
                    background: theme === t ? (t === "dark" ? "#333" : "#ddd") : "transparent",
                    border: `1px solid ${theme === "dark" ? "#333" : "#ddd"}`,
                    color: "inherit", fontSize: 11, cursor: "pointer",
                  }}>{t === "light" ? "Light" : "Dark"}</button>
                ))}
              </div>
              <div style={{ display: "flex", gap: 4 }}>
                {Object.entries(BRAND_COLORS).map(([k, v]) => (
                  <button key={k} onClick={() => setBrand(k)} style={{
                    flex: 1, height: 28, borderRadius: 6, background: v, cursor: "pointer",
                    border: brand === k ? "2px solid #fff" : "2px solid transparent",
                    opacity: brand === k ? 1 : 0.5, transition: "all 0.2s",
                  }} />
                ))}
              </div>
            </Panel>

            {/* Badge + Labels */}
            <Panel title="BADGE & LABELS" theme={theme}>
              <div style={{ display: "flex", gap: 6, marginBottom: 6 }}>
                <input value={avatarText} onChange={e => setAvatarText(e.target.value.slice(0, 6))}
                  placeholder="Title" style={{ ...inputStyle(theme), flex: 1 }} />
                <input value={avatarSub} onChange={e => setAvatarSub(e.target.value.slice(0, 10))}
                  placeholder="Subtitle" style={{ ...inputStyle(theme), flex: 1 }} />
              </div>
              <input value={label} onChange={e => setLabel(e.target.value.slice(0, 30))}
                placeholder="Code label" style={{ ...inputStyle(theme), width: "100%", marginBottom: 6, boxSizing: "border-box" }} />
              <input value={sublabel} onChange={e => setSublabel(e.target.value.slice(0, 40))}
                placeholder="Bottom bar" style={{ ...inputStyle(theme), width: "100%", boxSizing: "border-box" }} />
            </Panel>

            {/* Decode verification */}
            <Panel title="ROUNDTRIP VERIFICATION" theme={theme}>
              {decoded?.valid ? (
                <>
                  <div style={{ color: "#22c55e", fontSize: 12, fontWeight: 600, marginBottom: 4 }}>✓ CRC-8 Valid</div>
                  <div style={{ fontSize: 10, opacity: 0.6, marginBottom: 4 }}>
                    v{decoded.version} • {DATA_TYPES[decoded.dataType]} • {decoded.byteCount}B •
                    CRC 0x{decoded.checksum.toString(16).padStart(2, "0").toUpperCase()}
                  </div>
                  <div style={{
                    fontSize: 10, padding: 6, borderRadius: 6, wordBreak: "break-all",
                    background: theme === "dark" ? "#0a0a0a" : "#f5f5f5", opacity: 0.7,
                    fontFamily: "'SF Mono', monospace", maxHeight: 48, overflow: "auto",
                  }}>{decoded.text}</div>
                </>
              ) : (
                <div style={{ color: "#ef4444", fontSize: 11 }}>✗ {decoded?.error || "Not generated"}</div>
              )}
            </Panel>

            {/* Stats */}
            {stats && !stats.overflow && (
              <Panel title="ENCODING STATS" theme={theme}>
                {[
                  ["Payload", `${stats.dataBytes}B data + 5B header = ${stats.bytes}B`],
                  ["Bits used", `${stats.bits} / ${stats.maxBits} (${stats.utilization}%)`],
                  ["Slots filled", `${stats.onesCount} of ${stats.slots} (${stats.density}% density)`],
                  ["Layout", `${NUM_ANGLES} angles × ${NUM_BANDS} bands`],
                  ["Bullseyes", `4 at indices [${BULLSEYE_ANGLE_INDICES.join(", ")}]`],
                  ["Ray styles", "5 types (hash-deterministic, not data)"],
                ].map(([k, v], i) => (
                  <div key={i} style={{
                    display: "flex", justifyContent: "space-between", fontSize: 10,
                    padding: "3px 0", borderBottom: i < 5 ? `1px solid ${theme === "dark" ? "#1a1a1a" : "#eee"}` : "none",
                  }}>
                    <span style={{ opacity: 0.5 }}>{k}</span>
                    <span style={{ color: theme === "dark" ? "#e88a1a" : "#333" }}>{v}</span>
                  </div>
                ))}
              </Panel>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// --- Reusable panel component ---
function Panel({ title, theme, children }) {
  return (
    <div style={{
      padding: 12, borderRadius: 10,
      background: theme === "dark" ? "#111" : "#fff",
      border: `1px solid ${theme === "dark" ? "#222" : "#e0e0e0"}`,
    }}>
      <div style={{ fontSize: 9, fontWeight: 600, letterSpacing: 1.5, opacity: 0.4, marginBottom: 8 }}>{title}</div>
      {children}
    </div>
  );
}

function inputStyle(theme) {
  return {
    padding: 6, borderRadius: 6, outline: "none",
    border: `1px solid ${theme === "dark" ? "#333" : "#ddd"}`,
    background: "transparent", color: "inherit",
    fontFamily: "inherit", fontSize: 12,
  };
}
