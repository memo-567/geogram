import { useState, useRef, useEffect, useCallback } from "react";

// ============================================================
// GEOGRAM GLYPH CODE — 8-State (3 bits/cell)
// ============================================================
// 4 shapes × 2 fills = 8 symbols
//
//   000  Square solid       100  Cross solid
//   001  Square outline     101  Cross outline
//   010  Circle solid       110  Triangle solid
//   011  Circle outline     111  Triangle outline
//
// Hierarchical decode:
//   Bit 0-1 (coarse): shape family (sq/ci/cr/tr)
//   Bit 2   (fine):   solid vs outline
//
// 3 bits/cell → pack 3 cells = 9 bits → 1 byte + 1 bit overflow
// Actual packing: 8 cells = 24 bits = 3 bytes (clean alignment)
// ============================================================

const GLYPHS = {
  SQ_SOLID: 0, SQ_OUTLINE: 1,
  CI_SOLID: 2, CI_OUTLINE: 3,
  CR_SOLID: 4, CR_OUTLINE: 5,
  TR_SOLID: 6, TR_OUTLINE: 7,
};

const GLYPH_NAMES = [
  "Sq Solid", "Sq Outline", "Ci Solid", "Ci Outline",
  "Cr Solid", "Cr Outline", "Tri Solid", "Tri Outline",
];
const GLYPH_CHARS = ["■", "□", "●", "○", "✚", "⊞", "▲", "△"];
const FAMILY_NAMES = ["Square", "Circle", "Cross", "Triangle"];
const FAMILY_COLORS = ["#e88a1a", "#22c55e", "#06b6d4", "#a855f7"];

// CRC-8
const CRC8 = (() => {
  const t = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i; for (let j = 0; j < 8; j++) c = c & 0x80 ? (c << 1) ^ 0x07 : c << 1; t[i] = c & 0xff;
  }
  return d => { let c = 0; for (const b of d) c = t[(c ^ b) & 0xff]; return c; };
})();

// Interleave
function interleave(bytes, bs = 16) {
  const bl = Math.ceil(bytes.length / bs);
  const r = new Uint8Array(bl * bs);
  for (let i = 0; i < bytes.length; i++) r[(i % bl) * bs + Math.floor(i / bl)] = bytes[i];
  return r;
}
function deinterleave(bytes, len, bs = 16) {
  const bl = Math.ceil(len / bs);
  const r = new Uint8Array(len);
  for (let i = 0; i < len; i++) r[i] = bytes[(i % bl) * bs + Math.floor(i / bl)];
  return r;
}

// ============================================================
// Bit packing: bytes ↔ 3-bit symbols
// Pack 8 symbols = 24 bits = 3 bytes (clean boundary)
// ============================================================
function bytesToSymbols(bytes) {
  // Convert bytes to bit stream
  const bits = [];
  for (const b of bytes) for (let i = 7; i >= 0; i--) bits.push((b >> i) & 1);
  // Read 3 bits at a time
  const syms = [];
  for (let i = 0; i + 2 < bits.length; i += 3) {
    syms.push((bits[i] << 2) | (bits[i + 1] << 1) | bits[i + 2]);
  }
  // Handle remainder (pad with 0)
  const rem = bits.length % 3;
  if (rem > 0) {
    let val = 0;
    for (let i = bits.length - rem; i < bits.length; i++) val = (val << 1) | bits[i];
    val <<= (3 - rem);
    syms.push(val);
  }
  return syms;
}

function symbolsToBytes(syms, byteCount) {
  const bits = [];
  for (const s of syms) { bits.push((s >> 2) & 1); bits.push((s >> 1) & 1); bits.push(s & 1); }
  const bytes = [];
  for (let i = 0; i + 7 < bits.length && bytes.length < byteCount; i += 8) {
    let b = 0;
    for (let j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
    bytes.push(b);
  }
  return new Uint8Array(bytes);
}

// ============================================================
// Finder & alignment patterns
// ============================================================
const FINDER_SIZE = 5;
const FINDER = [
  [0, 0, 0, 0, 0],
  [0, 2, 2, 2, 0],
  [0, 2, 4, 2, 0],
  [0, 2, 2, 2, 0],
  [0, 0, 0, 0, 0],
];

const ALIGN_SIZE = 3;
const ALIGN = [
  [4, 3, 4],
  [3, 0, 3],
  [4, 3, 4],
];

// ============================================================
// Encoder
// ============================================================
function encode(text, dataType = 0x06) {
  const raw = new TextEncoder().encode(text);
  const crc = CRC8(raw);
  const hdr = new Uint8Array([0x01, dataType, (raw.length >> 8) & 0xff, raw.length & 0xff, crc]);
  const payload = new Uint8Array(hdr.length + raw.length);
  payload.set(hdr);
  payload.set(raw, hdr.length);

  const il = interleave(payload);
  const syms = bytesToSymbols(il);

  // Grid sizing
  const overhead = 3 * FINDER_SIZE * FINDER_SIZE + ALIGN_SIZE * ALIGN_SIZE + 80;
  const needed = syms.length + overhead;
  let gs = Math.max(21, Math.ceil(Math.sqrt(needed)) + 1);
  if (gs % 2 === 0) gs++;

  const grid = Array.from({ length: gs }, () => Array(gs).fill(-1));
  const locked = Array.from({ length: gs }, () => Array(gs).fill(false));

  const place = (r0, c0, pat) => {
    for (let r = 0; r < pat.length; r++)
      for (let c = 0; c < pat[0].length; c++)
        if (r0 + r < gs && c0 + c < gs) { grid[r0 + r][c0 + c] = pat[r][c]; locked[r0 + r][c0 + c] = true; }
  };

  place(0, 0, FINDER);
  place(0, gs - FINDER_SIZE, FINDER);
  place(gs - FINDER_SIZE, 0, FINDER);
  place(gs - ALIGN_SIZE - 2, gs - ALIGN_SIZE - 2, ALIGN);

  // Timing
  for (let i = FINDER_SIZE; i < gs - FINDER_SIZE; i++) {
    if (!locked[6][i]) { grid[6][i] = i % 2 === 0 ? 0 : 2; locked[6][i] = true; }
    if (!locked[i][6]) { grid[i][6] = i % 2 === 0 ? 0 : 2; locked[i][6] = true; }
  }

  // Separators
  for (let i = 0; i <= FINDER_SIZE && i < gs; i++) {
    if (FINDER_SIZE < gs && !locked[i][FINDER_SIZE]) { grid[i][FINDER_SIZE] = 7; locked[i][FINDER_SIZE] = true; }
    if (FINDER_SIZE < gs && !locked[FINDER_SIZE][i]) { grid[FINDER_SIZE][i] = 7; locked[FINDER_SIZE][i] = true; }
    const tc = gs - FINDER_SIZE - 1;
    if (tc >= 0 && !locked[i][tc]) { grid[i][tc] = 7; locked[i][tc] = true; }
    const br = gs - FINDER_SIZE - 1;
    if (br >= 0 && !locked[br][i]) { grid[br][i] = 7; locked[br][i] = true; }
  }

  // Serpentine
  let si = 0;
  for (let col = gs - 1; col >= 0; col -= 2) {
    if (col === 6) col = 5;
    const up = ((gs - 1 - col) / 2) % 2 === 0;
    for (let step = 0; step < gs; step++) {
      const row = up ? gs - 1 - step : step;
      for (let dc = 0; dc >= -1; dc--) {
        const c = col + dc;
        if (c < 0 || c >= gs || locked[row][c]) continue;
        grid[row][c] = si < syms.length ? syms[si++] : 7;
        locked[row][c] = true;
      }
    }
  }

  return { grid, gridSize: gs, symbolCount: syms.length, payloadBytes: payload.length };
}

// ============================================================
// Decoder
// ============================================================
function decode(grid, gs) {
  const locked = Array.from({ length: gs }, () => Array(gs).fill(false));
  const mark = (r0, c0, s) => {
    for (let r = 0; r < s; r++) for (let c = 0; c < s; c++)
      if (r0 + r < gs && c0 + c < gs) locked[r0 + r][c0 + c] = true;
  };
  mark(0, 0, FINDER_SIZE); mark(0, gs - FINDER_SIZE, FINDER_SIZE);
  mark(gs - FINDER_SIZE, 0, FINDER_SIZE);
  mark(gs - ALIGN_SIZE - 2, gs - ALIGN_SIZE - 2, ALIGN_SIZE);
  for (let i = FINDER_SIZE; i < gs - FINDER_SIZE; i++) { locked[6][i] = true; locked[i][6] = true; }
  for (let i = 0; i <= FINDER_SIZE && i < gs; i++) {
    if (FINDER_SIZE < gs) { locked[i][FINDER_SIZE] = true; locked[FINDER_SIZE][i] = true; }
    const tc = gs - FINDER_SIZE - 1; if (tc >= 0) locked[i][tc] = true;
    const br = gs - FINDER_SIZE - 1; if (br >= 0) locked[br][i] = true;
  }

  const syms = [];
  for (let col = gs - 1; col >= 0; col -= 2) {
    if (col === 6) col = 5;
    const up = ((gs - 1 - col) / 2) % 2 === 0;
    for (let step = 0; step < gs; step++) {
      const row = up ? gs - 1 - step : step;
      for (let dc = 0; dc >= -1; dc--) {
        const c = col + dc;
        if (c < 0 || c >= gs || locked[row][c]) continue;
        syms.push(grid[row][c] & 0x07);
      }
    }
  }

  // We need to figure out byte count from the header
  // First pass: decode enough symbols to read header (5 bytes = 40 bits = 14 symbols)
  const headerBytes = symbolsToBytes(syms.slice(0, 20), 10);
  if (headerBytes.length < 5) return { error: "Too few bytes" };

  // Header is interleaved, but we need total byte count to deinterleave
  // Estimate: try to deinterleave with increasing lengths
  const ver = headerBytes[0], dt = headerBytes[1];
  // Since data is interleaved, we can't read length directly from first bytes
  // Instead, decode all symbols to bytes, then deinterleave
  const totalPayloadEst = Math.floor(syms.length * 3 / 8);
  const allBytes = symbolsToBytes(syms, totalPayloadEst);

  // Try deinterleave with the full buffer, read header
  // We need to try the most likely payload size (5 + data)
  // Brute approach: try lengths from 6 to min(allBytes.length, 520)
  for (let tryLen = 6; tryLen <= Math.min(allBytes.length, 520); tryLen++) {
    try {
      const p = deinterleave(allBytes, tryLen);
      const v = p[0], d = p[1], len = (p[2] << 8) | p[3], cr = p[4];
      if (v !== 0x01 || len <= 0 || len > 512 || 5 + len !== tryLen) continue;
      const textBytes = p.slice(5, 5 + len);
      const computed = CRC8(textBytes);
      if (computed === cr) {
        return {
          version: v, dataType: d, byteCount: len,
          text: new TextDecoder().decode(textBytes),
          checksum: computed, valid: true,
        };
      }
    } catch (e) { continue; }
  }
  return { error: "Could not decode — CRC mismatch or corrupted data" };
}

// ============================================================
// Glyph Renderer
// ============================================================
function drawGlyph(ctx, glyph, x, y, size, color, highlight = false) {
  const cx = x + size / 2, cy = y + size / 2;
  const m = size * 0.1;
  const s = size - m * 2;
  const sx = x + m, sy = y + m;
  const shape = (glyph >> 1) & 0x03;  // bits 1-2: shape
  const outline = glyph & 0x01;        // bit 0: solid(0) or outline(1)

  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  const lw = Math.max(1.2, s * 0.14);

  switch (shape) {
    case 0: // Square
      if (outline) {
        ctx.lineWidth = lw;
        ctx.strokeRect(sx + lw / 2, sy + lw / 2, s - lw, s - lw);
      } else {
        ctx.fillRect(sx, sy, s, s);
      }
      break;

    case 1: // Circle
      ctx.beginPath();
      ctx.arc(cx, cy, s / 2 - (outline ? lw / 2 : 0), 0, Math.PI * 2);
      if (outline) { ctx.lineWidth = lw; ctx.stroke(); }
      else ctx.fill();
      break;

    case 2: // Cross
      if (outline) {
        const a = s * 0.28;
        ctx.lineWidth = Math.max(1, s * 0.08);
        ctx.beginPath();
        ctx.moveTo(cx - a / 2, sy); ctx.lineTo(cx + a / 2, sy);
        ctx.lineTo(cx + a / 2, cy - a / 2); ctx.lineTo(sx + s, cy - a / 2);
        ctx.lineTo(sx + s, cy + a / 2); ctx.lineTo(cx + a / 2, cy + a / 2);
        ctx.lineTo(cx + a / 2, sy + s); ctx.lineTo(cx - a / 2, sy + s);
        ctx.lineTo(cx - a / 2, cy + a / 2); ctx.lineTo(sx, cy + a / 2);
        ctx.lineTo(sx, cy - a / 2); ctx.lineTo(cx - a / 2, cy - a / 2);
        ctx.closePath();
        ctx.stroke();
      } else {
        const a = s * 0.3;
        ctx.fillRect(sx, cy - a / 2, s, a);
        ctx.fillRect(cx - a / 2, sy, a, s);
      }
      break;

    case 3: // Triangle
      const ts = s * 0.88;
      ctx.beginPath();
      ctx.moveTo(cx, cy - ts / 2);
      ctx.lineTo(cx + ts / 2, cy + ts / 2);
      ctx.lineTo(cx - ts / 2, cy + ts / 2);
      ctx.closePath();
      if (outline) { ctx.lineWidth = lw; ctx.stroke(); }
      else ctx.fill();
      break;
  }
}

function drawFullGrid(ctx, grid, gs, canvasSize, opts = {}) {
  const { showLines = false, bg = "#08080a", color = "#e88a1a" } = opts;
  const q = 2, tot = gs + q * 2, cell = canvasSize / tot, off = q * cell;

  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, canvasSize, canvasSize);

  if (showLines) {
    ctx.strokeStyle = "rgba(232,138,26,0.04)";
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= gs; i++) {
      ctx.beginPath(); ctx.moveTo(off + i * cell, off); ctx.lineTo(off + i * cell, off + gs * cell); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(off, off + i * cell); ctx.lineTo(off + gs * cell, off + i * cell); ctx.stroke();
    }
  }

  for (let r = 0; r < gs; r++) {
    for (let c = 0; c < gs; c++) {
      const g = grid[r][c];
      if (g < 0) continue;
      const inFinder = (r < FINDER_SIZE && c < FINDER_SIZE) ||
        (r < FINDER_SIZE && c >= gs - FINDER_SIZE) ||
        (r >= gs - FINDER_SIZE && c < FINDER_SIZE);
      drawGlyph(ctx, g, off + c * cell, off + r * cell, cell, inFinder ? "#ff9d2e" : color);
    }
  }

  ctx.strokeStyle = color + "22";
  ctx.lineWidth = 1;
  ctx.strokeRect(off - 1, off - 1, gs * cell + 2, gs * cell + 2);
}

// ============================================================
// Binary grid for comparison
// ============================================================
function binaryGridSize(byteCount) {
  const bits = (byteCount + 5) * 8 * 1.15; // +header +EC overhead
  return Math.max(21, Math.ceil(Math.sqrt(bits + 100)));
}

// 4-state grid for comparison
function fourStateGridSize(byteCount) {
  const cells = (byteCount + 5) * 4 * 1.15;
  return Math.max(21, Math.ceil(Math.sqrt(cells + 100)));
}

// 16-state grid for comparison
function sixteenStateGridSize(byteCount) {
  const cells = (byteCount + 5) * 2 * 1.15;
  return Math.max(21, Math.ceil(Math.sqrt(cells + 100)));
}

// ============================================================
// UI
// ============================================================
const DATA_TYPES = {
  NOSTR_PUBKEY: 0x01, MESH_NODE: 0x03, APRS_CALL: 0x04, URL: 0x05, TEXT: 0x06, GEOGRAM_ID: 0x07,
};
const DT_LABELS = { 0x01: "NOSTR Pubkey", 0x03: "Mesh Node", 0x04: "APRS Call", 0x05: "URL", 0x06: "Text", 0x07: "Geogram ID" };

const SAMPLE = `-----BEGIN GEOGRAM MESH KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7VJt3kR2
qHHpNxRSQ+4z8HdGjKm5NmPqLxYb3oJ2V9RkFzU4wTmJhXd0sNq
K8pA5e3cR7gMwB2hJ4fVtLmN9xC6QoD+3Ff5gTqRp2M4LrN8vJh
WkE7BxQa1U0yVpKdFmjA5sBzHN8qWvL4cR9fTxG2nMK6eJpL3dY
0123456789abcdef0123456789abcdef01234567
APRS:PP1BRT-7|NOSTR:npub1geogram
-----END GEOGRAM MESH KEY-----`;

export default function GeogramGlyphCode8() {
  const mainRef = useRef(null);
  const [input, setInput] = useState(SAMPLE.slice(0, 512));
  const [dt, setDt] = useState(0x03);
  const [lines, setLines] = useState(false);
  const [result, setResult] = useState(null);
  const [decoded, setDecoded] = useState(null);
  const [hover, setHover] = useState(null);
  const [cSize] = useState(600);

  const gen = useCallback(() => {
    const t = input.slice(0, 512);
    const r = encode(t, dt);
    setResult(r);
    setDecoded(decode(r.grid, r.gridSize));
  }, [input, dt]);

  useEffect(() => { gen(); }, []);

  useEffect(() => {
    if (!result || !mainRef.current) return;
    drawFullGrid(mainRef.current.getContext("2d"), result.grid, result.gridSize, cSize, { showLines: lines });
  }, [result, lines, cSize]);

  const bytes = new TextEncoder().encode(input).length;
  const counts = new Array(8).fill(0);
  if (result) for (const row of result.grid) for (const c of row) if (c >= 0 && c < 8) counts[c]++;
  const totalCells = result ? result.gridSize ** 2 : 1;

  const binGS = binaryGridSize(bytes);
  const fourGS = fourStateGridSize(bytes);
  const sixteenGS = sixteenStateGridSize(bytes);

  const onHover = (e) => {
    if (!result || !mainRef.current) return;
    const rect = mainRef.current.getBoundingClientRect();
    const scl = cSize / rect.width;
    const q = 2, tot = result.gridSize + q * 2, cell = cSize / tot, off = q * cell;
    const col = Math.floor(((e.clientX - rect.left) * scl - off) / cell);
    const row = Math.floor(((e.clientY - rect.top) * scl - off) / cell);
    if (row >= 0 && row < result.gridSize && col >= 0 && col < result.gridSize)
      setHover({ row, col, glyph: result.grid[row][col] });
    else setHover(null);
  };

  return (
    <div style={{
      minHeight: "100vh", background: "#08080a", color: "#d4d4d8",
      fontFamily: "'SF Mono', 'Cascadia Code', monospace", padding: 16,
    }}>
      <div style={{ textAlign: "center", marginBottom: 20 }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, color: "#e88a1a", letterSpacing: 4, margin: 0 }}>
          GEOGRAM GLYPH CODE — 8 STATE
        </h1>
        <p style={{ fontSize: 10, color: "#e88a1a66", letterSpacing: 2, marginTop: 4 }}>
          4 SHAPES × SOLID/OUTLINE — 3 BITS/CELL — {result ? result.gridSize + "×" + result.gridSize : ""} GRID
        </p>
      </div>

      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        {/* Glyph legend */}
        <div style={{
          display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 1,
          marginBottom: 16, background: "#1a1a2e",
        }}>
          {FAMILY_NAMES.map((fam, fi) => (
            <div key={fi} style={{ background: "#0d0d0f", padding: "8px 10px" }}>
              <div style={{
                fontSize: 9, color: FAMILY_COLORS[fi], letterSpacing: 1,
                marginBottom: 8, textAlign: "center",
              }}>
                {fam.toUpperCase()}
              </div>
              <div style={{ display: "flex", justifyContent: "center", gap: 10 }}>
                {[0, 1].map(fill => {
                  const g = (fi << 1) | fill;
                  return (
                    <div key={fill} style={{ textAlign: "center" }}>
                      <canvas width={48} height={48} ref={el => {
                        if (el) {
                          const c = el.getContext("2d");
                          c.fillStyle = "#08080a"; c.fillRect(0, 0, 48, 48);
                          drawGlyph(c, g, 4, 4, 40, FAMILY_COLORS[fi]);
                        }
                      }} style={{ width: 40, height: 40, border: `1px solid ${FAMILY_COLORS[fi]}22` }} />
                      <div style={{ fontSize: 8, color: "#71717a", marginTop: 3 }}>
                        {fill === 0 ? "solid" : "outline"}
                      </div>
                      <div style={{ fontSize: 8, color: FAMILY_COLORS[fi] + "88" }}>
                        {g.toString(2).padStart(3, "0")}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        {/* Controls */}
        <div style={{
          display: "flex", gap: 10, marginBottom: 16, flexWrap: "wrap",
          padding: 12, background: "#0d0d0f", border: "1px solid #1a1a2e",
        }}>
          <div style={{ flex: "1 1 320px" }}>
            <label style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", display: "block", marginBottom: 3 }}>
              PAYLOAD ({bytes}/512 bytes)
            </label>
            <textarea
              value={input} onChange={e => setInput(e.target.value.slice(0, 512))}
              style={{
                width: "100%", height: 72, background: "#0a0a0c", border: "1px solid #1a1a2e",
                color: "#d4d4d8", fontFamily: "inherit", fontSize: 11, padding: 8,
                resize: "none", boxSizing: "border-box", outline: "none",
              }}
            />
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 5, minWidth: 160 }}>
            <select value={dt} onChange={e => setDt(parseInt(e.target.value))} style={{
              padding: 5, background: "#0a0a0c", border: "1px solid #1a1a2e",
              color: "#d4d4d8", fontFamily: "inherit", fontSize: 10,
            }}>
              {Object.entries(DATA_TYPES).map(([k, v]) => <option key={k} value={v}>{k.replace(/_/g, " ")}</option>)}
            </select>
            <button onClick={gen} style={{
              padding: 9, background: "#e88a1a", border: "none", color: "#000",
              fontFamily: "inherit", fontSize: 12, fontWeight: 700, letterSpacing: 2, cursor: "pointer",
            }}>▶ ENCODE</button>
            <div style={{ display: "flex", gap: 4 }}>
              <button onClick={() => setLines(!lines)} style={{
                flex: 1, padding: 5, background: lines ? "#e88a1a15" : "transparent",
                border: "1px solid #1a1a2e", color: "#e88a1a", fontFamily: "inherit", fontSize: 9, cursor: "pointer",
              }}>GRID {lines ? "ON" : "OFF"}</button>
              <button onClick={() => {
                if (!mainRef.current) return;
                const a = document.createElement("a"); a.download = `geogram-8state-${bytes}b.png`;
                a.href = mainRef.current.toDataURL("image/png"); a.click();
              }} style={{
                flex: 1, padding: 5, background: "transparent", border: "1px solid #1a1a2e",
                color: "#e88a1a", fontFamily: "inherit", fontSize: 9, cursor: "pointer",
              }}>↓ PNG</button>
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: 16, flexWrap: "wrap", justifyContent: "center" }}>
          {/* Canvas */}
          <div>
            <canvas ref={mainRef} width={cSize} height={cSize}
              onMouseMove={onHover} onMouseLeave={() => setHover(null)}
              style={{
                width: Math.min(cSize, 560), height: Math.min(cSize, 560),
                cursor: "crosshair", border: "1px solid #1a1a2e",
                boxShadow: "0 0 60px rgba(232,138,26,0.06)",
              }}
            />
            <div style={{ marginTop: 4, fontSize: 10, color: "#e88a1a66", height: 16, display: "flex", justifyContent: "space-between" }}>
              {hover && hover.glyph >= 0 ? (
                <span style={{ color: FAMILY_COLORS[(hover.glyph >> 1) & 3] }}>
                  [{hover.row},{hover.col}] {GLYPH_NAMES[hover.glyph]} ({hover.glyph.toString(2).padStart(3, "0")})
                </span>
              ) : <span>Hover to inspect</span>}
              {result && <span>{result.gridSize}×{result.gridSize}</span>}
            </div>
          </div>

          {/* Stats */}
          <div style={{ flex: "1 1 260px", maxWidth: 380 }}>
            {/* Decode */}
            {decoded && (
              <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
                <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 5 }}>DECODE</div>
                {decoded.valid ? (
                  <>
                    <div style={{ color: "#22c55e", fontSize: 11, marginBottom: 3 }}>✓ VALID — CRC-8 OK</div>
                    <div style={{ fontSize: 9, color: "#71717a" }}>
                      v{decoded.version} • {DT_LABELS[decoded.dataType]} • {decoded.byteCount}B
                    </div>
                    <div style={{
                      fontSize: 9, marginTop: 4, padding: 5, background: "#0a0a0c",
                      border: "1px solid #1a1a2e", maxHeight: 48, overflow: "auto",
                      wordBreak: "break-all", color: "#a1a1aa",
                    }}>{decoded.text.slice(0, 120)}...</div>
                  </>
                ) : <div style={{ color: "#ef4444", fontSize: 11 }}>✗ {decoded.error}</div>}
              </div>
            )}

            {/* Distribution */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>GLYPH DISTRIBUTION</div>
              {[0, 1, 2, 3].map(fi => {
                const solid = counts[fi * 2];
                const outline = counts[fi * 2 + 1];
                const total = solid + outline;
                const pct = (total / totalCells * 100);
                return (
                  <div key={fi} style={{ marginBottom: 6 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", fontSize: 9, marginBottom: 2 }}>
                      <span style={{ color: FAMILY_COLORS[fi] }}>{FAMILY_NAMES[fi]}</span>
                      <span style={{ color: "#71717a" }}>{total} ({pct.toFixed(1)}%)</span>
                    </div>
                    <div style={{ display: "flex", gap: 1, height: 8 }}>
                      <div style={{
                        width: `${(solid / totalCells) * 100}%`, background: FAMILY_COLORS[fi],
                        transition: "width 0.3s",
                      }} title={`Solid: ${solid}`} />
                      <div style={{
                        width: `${(outline / totalCells) * 100}%`, background: FAMILY_COLORS[fi], opacity: 0.4,
                        transition: "width 0.3s",
                      }} title={`Outline: ${outline}`} />
                    </div>
                    <div style={{ display: "flex", justifyContent: "space-between", fontSize: 8, color: "#52525b", marginTop: 1 }}>
                      <span>■ {solid} solid</span>
                      <span>□ {outline} outline</span>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Comparison table */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>
                SIZE COMPARISON — {bytes}B PAYLOAD
              </div>
              <table style={{ width: "100%", fontSize: 10, borderCollapse: "collapse" }}>
                <thead>
                  <tr style={{ borderBottom: "1px solid #1a1a2e" }}>
                    <th style={{ textAlign: "left", padding: "4px 0", color: "#71717a", fontWeight: 400 }}>Format</th>
                    <th style={{ textAlign: "right", padding: "4px 0", color: "#71717a", fontWeight: 400 }}>Grid</th>
                    <th style={{ textAlign: "right", padding: "4px 0", color: "#71717a", fontWeight: 400 }}>Cells</th>
                    <th style={{ textAlign: "right", padding: "4px 0", color: "#71717a", fontWeight: 400 }}>@0.8mm</th>
                    <th style={{ textAlign: "right", padding: "4px 0", color: "#71717a", fontWeight: 400 }}>px/cell</th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    { name: "Binary (1b)", gs: binGS, px: 5, color: "#71717a" },
                    { name: "4-state (2b)", gs: fourGS, px: 8, color: "#71717a" },
                    { name: "8-state (3b)", gs: result?.gridSize || 0, px: 12, color: "#e88a1a", bold: true },
                    { name: "16-state (4b)", gs: sixteenGS, px: 16, color: "#71717a" },
                  ].map((row, i) => (
                    <tr key={i} style={{
                      borderBottom: "1px solid #0a0a0c",
                      background: row.bold ? "#e88a1a08" : "transparent",
                    }}>
                      <td style={{ padding: "5px 0", color: row.color, fontWeight: row.bold ? 700 : 400 }}>{row.name}</td>
                      <td style={{ textAlign: "right", padding: "5px 0", color: row.color }}>{row.gs}×{row.gs}</td>
                      <td style={{ textAlign: "right", padding: "5px 0", color: row.color }}>{row.gs ** 2}</td>
                      <td style={{ textAlign: "right", padding: "5px 0", color: row.color }}>{(row.gs * 0.8 / 10).toFixed(1)}cm</td>
                      <td style={{ textAlign: "right", padding: "5px 0", color: row.color }}>{row.px}+</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Scan reliability */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>RELIABILITY PROFILE</div>
              {[
                { label: "Shape discrimination", val: "■□●○✚⊞▲△", note: "4 shapes × very distinct contours", color: "#22c55e" },
                { label: "Fill discrimination", val: "solid vs outline", note: "Binary threshold on center fill", color: "#22c55e" },
                { label: "Ink bleed tolerance", val: "High", note: "Outline arm width >> bleed radius", color: "#22c55e" },
                { label: "Photocopy survival", val: "3-4 generations", note: "High contrast B&W shapes", color: "#22c55e" },
                { label: "Wet paper", val: "Moderate", note: "Outline fills may close — degrades to 4-state", color: "#e88a1a" },
                { label: "Coarse fallback", val: "2 bits", note: "Shape family still readable if fill lost", color: "#06b6d4" },
              ].map((row, i) => (
                <div key={i} style={{ marginBottom: 5, fontSize: 10 }}>
                  <div style={{ display: "flex", justifyContent: "space-between" }}>
                    <span style={{ color: "#a1a1aa" }}>{row.label}</span>
                    <span style={{ color: row.color }}>{row.val}</span>
                  </div>
                  <div style={{ fontSize: 8, color: "#52525b" }}>{row.note}</div>
                </div>
              ))}
            </div>

            {/* Scanner */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>DART SCANNER</div>
              <div style={{ fontSize: 9, color: "#a1a1aa", lineHeight: 2 }}>
                {[
                  ["1", "Detect finders (nested ■●✚ pattern)"],
                  ["2", "Perspective warp → cell grid"],
                  ["3", "Per cell → binarize contour"],
                  ["4", "Coarse: vertex count + circularity"],
                  ["", "  ■□ = 4 vertices, low circularity"],
                  ["", "  ●○ = high circularity (>0.07)"],
                  ["", "  ✚⊞ = 12 vertices, concave"],
                  ["", "  ▲△ = 3 vertices"],
                  ["5", "Fine: center brightness → solid/outline"],
                  ["6", "Serpentine read → 3-bit unpack → bytes"],
                ].map(([n, t], i) => (
                  <div key={i} style={{ display: "flex", gap: 6 }}>
                    <span style={{ color: "#e88a1a", minWidth: 12 }}>{n}</span><span>{t}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
