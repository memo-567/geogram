import { useState, useRef, useEffect, useCallback } from "react";

// ============================================================
// GEOGRAM GLYPH CODE — 16-State Grid Encoding (4 bits/cell)
// ============================================================
// 16 glyphs = 1 nibble per cell
//
// Base shapes (coarse 2-bit classification):
//   Square family (00xx):  solid, outline, small, dot-center
//   Circle family (01xx):  solid, outline, small, dot-center
//   Cross  family (10xx):  solid, outline, small, dot-center
//   Triangle      (11xx):  up, right, down, left
//
// Hierarchical decoding:
//   Step 1: Identify base shape → 2 bits (coarse)
//   Step 2: Identify variant   → 2 bits (fine)
//   Total: 4 bits per cell
// ============================================================

const GLYPHS = {
  SQ_SOLID:   0b0000, // 0
  SQ_OUTLINE: 0b0001, // 1
  SQ_SMALL:   0b0010, // 2
  SQ_DOT:     0b0011, // 3
  CI_SOLID:   0b0100, // 4
  CI_OUTLINE: 0b0101, // 5
  CI_SMALL:   0b0110, // 6
  CI_DOT:     0b0111, // 7
  CR_SOLID:   0b1000, // 8
  CR_OUTLINE: 0b1001, // 9
  CR_SMALL:   0b1010, // 10
  CR_DOT:     0b1011, // 11
  TR_UP:      0b1100, // 12
  TR_RIGHT:   0b1101, // 13
  TR_DOWN:    0b1110, // 14
  TR_LEFT:    0b1111, // 15
};

const GLYPH_NAMES = [
  "Sq Solid", "Sq Outline", "Sq Small", "Sq Dot",
  "Ci Solid", "Ci Outline", "Ci Small", "Ci Dot",
  "Cr Solid", "Cr Outline", "Cr Small", "Cr Dot",
  "Tri Up", "Tri Right", "Tri Down", "Tri Left",
];

const FAMILY_NAMES = ["Square", "Circle", "Cross", "Triangle"];
const FAMILY_COLORS = ["#e88a1a", "#22c55e", "#06b6d4", "#a855f7"];

// CRC-8
const CRC8 = (() => {
  const t = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) c = c & 0x80 ? (c << 1) ^ 0x07 : c << 1;
    t[i] = c & 0xff;
  }
  return (data) => { let c = 0; for (const b of data) c = t[(c ^ b) & 0xff]; return c; };
})();

// Byte-level interleaving
function interleave(bytes, bs = 16) {
  const blocks = Math.ceil(bytes.length / bs);
  const r = new Uint8Array(blocks * bs);
  for (let i = 0; i < bytes.length; i++) r[(i % blocks) * bs + Math.floor(i / blocks)] = bytes[i];
  return r;
}
function deinterleave(bytes, len, bs = 16) {
  const blocks = Math.ceil(len / bs);
  const r = new Uint8Array(len);
  for (let i = 0; i < len; i++) r[i] = bytes[(i % blocks) * bs + Math.floor(i / blocks)];
  return r;
}

// ============================================================
// Finder pattern — 5×5 using glyphs (unique to Geogram)
// Uses all 4 families so finder detection can verify glyph recognition
// ============================================================
const FINDER_SIZE = 5;
const FINDER = [
  [0, 0, 0, 0, 0],       // solid squares border
  [0, 4, 4, 4, 0],       // solid circles inner
  [0, 4, 8, 4, 0],       // cross center
  [0, 4, 4, 4, 0],
  [0, 0, 0, 0, 0],
];

const ALIGN_SIZE = 3;
const ALIGN = [
  [8, 5, 8],
  [5, 0, 5],
  [8, 5, 8],
];

// ============================================================
// Encoder
// ============================================================
function encode(text, dataType = 0x06) {
  const raw = new TextEncoder().encode(text);
  const crc = CRC8(raw);
  // Header: [version][type][lenHi][lenLo][crc] = 5 bytes
  const hdr = new Uint8Array([0x02, dataType, (raw.length >> 8) & 0xff, raw.length & 0xff, crc]);
  const payload = new Uint8Array(hdr.length + raw.length);
  payload.set(hdr);
  payload.set(raw, hdr.length);

  const interleaved = interleave(payload);

  // Each byte → 2 nibbles → 2 glyphs
  const glyphs = [];
  for (const b of interleaved) {
    glyphs.push((b >> 4) & 0x0f);
    glyphs.push(b & 0x0f);
  }

  // Grid sizing
  const finderCells = 3 * FINDER_SIZE * FINDER_SIZE;
  const overhead = finderCells + 80; // timing, alignment, separators
  const needed = glyphs.length + overhead;
  let gridSize = Math.max(21, Math.ceil(Math.sqrt(needed)) + 1);
  if (gridSize % 2 === 0) gridSize++; // keep odd for symmetry

  const grid = Array.from({ length: gridSize }, () => Array(gridSize).fill(-1));
  const locked = Array.from({ length: gridSize }, () => Array(gridSize).fill(false));

  // Place finders
  const place = (r0, c0, pat) => {
    for (let r = 0; r < pat.length; r++)
      for (let c = 0; c < pat[0].length; c++)
        if (r0 + r < gridSize && c0 + c < gridSize && r0 + r >= 0 && c0 + c >= 0) {
          grid[r0 + r][c0 + c] = pat[r][c];
          locked[r0 + r][c0 + c] = true;
        }
  };

  place(0, 0, FINDER);
  place(0, gridSize - FINDER_SIZE, FINDER);
  place(gridSize - FINDER_SIZE, 0, FINDER);

  // Alignment
  const ar = gridSize - ALIGN_SIZE - 2, ac = gridSize - ALIGN_SIZE - 2;
  place(ar, ac, ALIGN);

  // Timing strips along row/col 6
  for (let i = FINDER_SIZE; i < gridSize - FINDER_SIZE; i++) {
    if (!locked[6][i]) { grid[6][i] = i % 2 === 0 ? GLYPHS.SQ_SOLID : GLYPHS.CI_SOLID; locked[6][i] = true; }
    if (!locked[i][6]) { grid[i][6] = i % 2 === 0 ? GLYPHS.SQ_SOLID : GLYPHS.CI_SOLID; locked[i][6] = true; }
  }

  // Separators (empty/dot cells around finders)
  for (let i = 0; i <= FINDER_SIZE && i < gridSize; i++) {
    const sep = GLYPHS.SQ_DOT;
    if (FINDER_SIZE < gridSize && !locked[i][FINDER_SIZE]) { grid[i][FINDER_SIZE] = sep; locked[i][FINDER_SIZE] = true; }
    if (FINDER_SIZE < gridSize && !locked[FINDER_SIZE][i]) { grid[FINDER_SIZE][i] = sep; locked[FINDER_SIZE][i] = true; }
    const tc = gridSize - FINDER_SIZE - 1;
    if (tc >= 0 && !locked[i][tc]) { grid[i][tc] = sep; locked[i][tc] = true; }
    const br = gridSize - FINDER_SIZE - 1;
    if (br >= 0 && !locked[br][i]) { grid[br][i] = sep; locked[br][i] = true; }
  }

  // Serpentine fill
  let gi = 0;
  for (let col = gridSize - 1; col >= 0; col -= 2) {
    if (col === 6) col = 5;
    const up = ((gridSize - 1 - col) / 2) % 2 === 0;
    for (let step = 0; step < gridSize; step++) {
      const row = up ? gridSize - 1 - step : step;
      for (let dc = 0; dc >= -1; dc--) {
        const c = col + dc;
        if (c < 0 || c >= gridSize || locked[row][c]) continue;
        grid[row][c] = gi < glyphs.length ? glyphs[gi++] : GLYPHS.TR_LEFT;
        locked[row][c] = true;
      }
    }
  }

  return { grid, gridSize, glyphCount: glyphs.length, payloadBytes: payload.length };
}

// ============================================================
// Decoder
// ============================================================
function decode(grid, gridSize) {
  const locked = Array.from({ length: gridSize }, () => Array(gridSize).fill(false));
  const mark = (r0, c0, s) => {
    for (let r = 0; r < s; r++) for (let c = 0; c < s; c++)
      if (r0 + r < gridSize && c0 + c < gridSize) locked[r0 + r][c0 + c] = true;
  };
  mark(0, 0, FINDER_SIZE); mark(0, gridSize - FINDER_SIZE, FINDER_SIZE);
  mark(gridSize - FINDER_SIZE, 0, FINDER_SIZE);
  mark(gridSize - ALIGN_SIZE - 2, gridSize - ALIGN_SIZE - 2, ALIGN_SIZE);
  for (let i = FINDER_SIZE; i < gridSize - FINDER_SIZE; i++) { locked[6][i] = true; locked[i][6] = true; }
  for (let i = 0; i <= FINDER_SIZE && i < gridSize; i++) {
    if (FINDER_SIZE < gridSize) { locked[i][FINDER_SIZE] = true; locked[FINDER_SIZE][i] = true; }
    const tc = gridSize - FINDER_SIZE - 1; if (tc >= 0) locked[i][tc] = true;
    const br = gridSize - FINDER_SIZE - 1; if (br >= 0) locked[br][i] = true;
  }

  const glyphs = [];
  for (let col = gridSize - 1; col >= 0; col -= 2) {
    if (col === 6) col = 5;
    const up = ((gridSize - 1 - col) / 2) % 2 === 0;
    for (let step = 0; step < gridSize; step++) {
      const row = up ? gridSize - 1 - step : step;
      for (let dc = 0; dc >= -1; dc--) {
        const c = col + dc;
        if (c < 0 || c >= gridSize || locked[row][c]) continue;
        glyphs.push(grid[row][c] & 0x0f);
      }
    }
  }

  const bytes = [];
  for (let i = 0; i + 1 < glyphs.length; i += 2)
    bytes.push(((glyphs[i] & 0x0f) << 4) | (glyphs[i + 1] & 0x0f));

  if (bytes.length < 5) return { error: "Too few bytes" };
  const all = new Uint8Array(bytes);
  const ver = all[0], dt = all[1], len = (all[2] << 8) | all[3], ecrc = all[4];
  const p = deinterleave(all, 5 + len);
  const text = new TextDecoder().decode(p.slice(5, 5 + ((p[2] << 8) | p[3])));
  const ccrc = CRC8(p.slice(5, 5 + ((p[2] << 8) | p[3])));

  return { version: p[0], dataType: p[1], text, byteCount: (p[2] << 8) | p[3], checksum: ccrc, expectedCrc: p[4], valid: ccrc === p[4] };
}

// ============================================================
// Glyph Renderer
// ============================================================
function drawGlyph(ctx, glyph, x, y, size, color, isStructural = false) {
  const cx = x + size / 2, cy = y + size / 2;
  const m = size * 0.1; // margin
  const s = size - m * 2; // shape size
  const sx = x + m, sy = y + m;
  const family = (glyph >> 2) & 0x03;
  const variant = glyph & 0x03;
  const c = isStructural ? "#ff9d2e" : color;
  const alpha = isStructural ? "cc" : "";

  ctx.fillStyle = c;
  ctx.strokeStyle = c;

  switch (family) {
    case 0: // Square
      switch (variant) {
        case 0: // solid
          ctx.fillRect(sx, sy, s, s);
          break;
        case 1: // outline
          ctx.lineWidth = Math.max(1, s * 0.15);
          ctx.strokeRect(sx + ctx.lineWidth/2, sy + ctx.lineWidth/2, s - ctx.lineWidth, s - ctx.lineWidth);
          break;
        case 2: // small
          const ss = s * 0.55;
          ctx.fillRect(cx - ss/2, cy - ss/2, ss, ss);
          break;
        case 3: // dot center
          ctx.lineWidth = Math.max(1, s * 0.12);
          ctx.strokeRect(sx + ctx.lineWidth/2, sy + ctx.lineWidth/2, s - ctx.lineWidth, s - ctx.lineWidth);
          ctx.beginPath();
          ctx.arc(cx, cy, s * 0.12, 0, Math.PI * 2);
          ctx.fill();
          break;
      }
      break;

    case 1: // Circle
      switch (variant) {
        case 0: // solid
          ctx.beginPath(); ctx.arc(cx, cy, s/2, 0, Math.PI * 2); ctx.fill();
          break;
        case 1: // outline
          ctx.lineWidth = Math.max(1, s * 0.15);
          ctx.beginPath(); ctx.arc(cx, cy, s/2 - ctx.lineWidth/2, 0, Math.PI * 2); ctx.stroke();
          break;
        case 2: // small
          ctx.beginPath(); ctx.arc(cx, cy, s * 0.28, 0, Math.PI * 2); ctx.fill();
          break;
        case 3: // dot center
          ctx.lineWidth = Math.max(1, s * 0.12);
          ctx.beginPath(); ctx.arc(cx, cy, s/2 - ctx.lineWidth/2, 0, Math.PI * 2); ctx.stroke();
          ctx.beginPath(); ctx.arc(cx, cy, s * 0.1, 0, Math.PI * 2); ctx.fill();
          break;
      }
      break;

    case 2: // Cross
      const arm = s * 0.28;
      switch (variant) {
        case 0: // solid
          ctx.fillRect(sx, cy - arm/2, s, arm);
          ctx.fillRect(cx - arm/2, sy, arm, s);
          break;
        case 1: { // outline
          const lw = Math.max(1, s * 0.1);
          ctx.lineWidth = lw;
          // Draw cross outline as a path
          const a = arm/2, hs = s/2;
          ctx.beginPath();
          ctx.moveTo(cx - a, sy); ctx.lineTo(cx + a, sy);
          ctx.lineTo(cx + a, cy - a); ctx.lineTo(sx + s, cy - a);
          ctx.lineTo(sx + s, cy + a); ctx.lineTo(cx + a, cy + a);
          ctx.lineTo(cx + a, sy + s); ctx.lineTo(cx - a, sy + s);
          ctx.lineTo(cx - a, cy + a); ctx.lineTo(sx, cy + a);
          ctx.lineTo(sx, cy - a); ctx.lineTo(cx - a, cy - a);
          ctx.closePath();
          ctx.stroke();
          break;
        }
        case 2: { // small
          const sa = arm * 0.7, ss2 = s * 0.35;
          ctx.fillRect(cx - ss2, cy - sa/2, ss2 * 2, sa);
          ctx.fillRect(cx - sa/2, cy - ss2, sa, ss2 * 2);
          break;
        }
        case 3: { // dot center
          const lw2 = Math.max(1, s * 0.08);
          ctx.lineWidth = lw2;
          const a2 = arm/2;
          ctx.beginPath();
          ctx.moveTo(cx - a2, sy); ctx.lineTo(cx + a2, sy);
          ctx.lineTo(cx + a2, cy - a2); ctx.lineTo(sx + s, cy - a2);
          ctx.lineTo(sx + s, cy + a2); ctx.lineTo(cx + a2, cy + a2);
          ctx.lineTo(cx + a2, sy + s); ctx.lineTo(cx - a2, sy + s);
          ctx.lineTo(cx - a2, cy + a2); ctx.lineTo(sx, cy + a2);
          ctx.lineTo(sx, cy - a2); ctx.lineTo(cx - a2, cy - a2);
          ctx.closePath();
          ctx.stroke();
          ctx.beginPath(); ctx.arc(cx, cy, s * 0.08, 0, Math.PI * 2); ctx.fill();
          break;
        }
      }
      break;

    case 3: // Triangle
      const triSize = s * 0.9;
      ctx.beginPath();
      switch (variant) {
        case 0: // up
          ctx.moveTo(cx, cy - triSize/2);
          ctx.lineTo(cx + triSize/2, cy + triSize/2);
          ctx.lineTo(cx - triSize/2, cy + triSize/2);
          break;
        case 1: // right
          ctx.moveTo(cx + triSize/2, cy);
          ctx.lineTo(cx - triSize/2, cy + triSize/2);
          ctx.lineTo(cx - triSize/2, cy - triSize/2);
          break;
        case 2: // down
          ctx.moveTo(cx, cy + triSize/2);
          ctx.lineTo(cx - triSize/2, cy - triSize/2);
          ctx.lineTo(cx + triSize/2, cy - triSize/2);
          break;
        case 3: // left
          ctx.moveTo(cx - triSize/2, cy);
          ctx.lineTo(cx + triSize/2, cy - triSize/2);
          ctx.lineTo(cx + triSize/2, cy + triSize/2);
          break;
      }
      ctx.closePath();
      ctx.fill();
      break;
  }
}

function drawGrid(ctx, grid, gridSize, canvasSize, opts = {}) {
  const { showLines = false, bgColor = "#08080a", color = "#e88a1a" } = opts;
  const quiet = 2;
  const total = gridSize + quiet * 2;
  const cell = canvasSize / total;
  const off = quiet * cell;

  ctx.fillStyle = bgColor;
  ctx.fillRect(0, 0, canvasSize, canvasSize);

  if (showLines) {
    ctx.strokeStyle = "rgba(232,138,26,0.04)";
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= gridSize; i++) {
      ctx.beginPath(); ctx.moveTo(off + i * cell, off); ctx.lineTo(off + i * cell, off + gridSize * cell); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(off, off + i * cell); ctx.lineTo(off + gridSize * cell, off + i * cell); ctx.stroke();
    }
  }

  for (let r = 0; r < gridSize; r++) {
    for (let c = 0; c < gridSize; c++) {
      const g = grid[r][c];
      if (g < 0) continue;
      const inFinder = (r < FINDER_SIZE && c < FINDER_SIZE) ||
        (r < FINDER_SIZE && c >= gridSize - FINDER_SIZE) ||
        (r >= gridSize - FINDER_SIZE && c < FINDER_SIZE);
      drawGlyph(ctx, g, off + c * cell, off + r * cell, cell, color, inFinder);
    }
  }

  // Border
  ctx.strokeStyle = color + "22";
  ctx.lineWidth = 1;
  ctx.strokeRect(off - 1, off - 1, gridSize * cell + 2, gridSize * cell + 2);
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

export default function GeogramGlyphCode() {
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
    drawGrid(mainRef.current.getContext("2d"), result.grid, result.gridSize, cSize, { showLines: lines });
  }, [result, lines, cSize]);

  const bytes = new TextEncoder().encode(input).length;

  // Stats
  const counts = new Array(16).fill(0);
  if (result) for (const row of result.grid) for (const c of row) if (c >= 0 && c < 16) counts[c]++;
  const totalCells = result ? result.gridSize ** 2 : 1;

  const onHover = (e) => {
    if (!result || !mainRef.current) return;
    const rect = mainRef.current.getBoundingClientRect();
    const scale = cSize / rect.width;
    const q = 2, tot = result.gridSize + q * 2, cell = cSize / tot, off = q * cell;
    const col = Math.floor(((e.clientX - rect.left) * scale - off) / cell);
    const row = Math.floor(((e.clientY - rect.top) * scale - off) / cell);
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
          GEOGRAM GLYPH CODE
        </h1>
        <p style={{ fontSize: 10, color: "#e88a1a66", letterSpacing: 2, marginTop: 4 }}>
          16-STATE ENCODING — 4 BITS/CELL — {result ? result.gridSize + "×" + result.gridSize : ""} GRID
        </p>
      </div>

      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        {/* Glyph legend */}
        <div style={{
          display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 1,
          marginBottom: 16, background: "#1a1a2e",
        }}>
          {FAMILY_NAMES.map((fam, fi) => (
            <div key={fi} style={{ background: "#0d0d0f", padding: "8px 6px" }}>
              <div style={{ fontSize: 9, color: FAMILY_COLORS[fi], letterSpacing: 1, marginBottom: 6, textAlign: "center" }}>
                {fam.toUpperCase()} ({(fi << 2).toString(2).padStart(4, "0").slice(0, 2)}xx)
              </div>
              <div style={{ display: "flex", justifyContent: "center", gap: 4 }}>
                {[0, 1, 2, 3].map(vi => {
                  const g = (fi << 2) | vi;
                  return (
                    <div key={vi} style={{ textAlign: "center" }}>
                      <canvas
                        width={40} height={40}
                        ref={el => {
                          if (el) {
                            const c = el.getContext("2d");
                            c.fillStyle = "#08080a"; c.fillRect(0, 0, 40, 40);
                            drawGlyph(c, g, 2, 2, 36, FAMILY_COLORS[fi]);
                          }
                        }}
                        style={{ width: 32, height: 32, border: `1px solid ${FAMILY_COLORS[fi]}22` }}
                      />
                      <div style={{ fontSize: 7, color: "#71717a", marginTop: 2 }}>
                        {g.toString(2).padStart(4, "0")}
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
                const a = document.createElement("a");
                a.download = `geogram-glyphcode-${bytes}b.png`;
                a.href = mainRef.current.toDataURL("image/png");
                a.click();
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
            <canvas
              ref={mainRef} width={cSize} height={cSize}
              onMouseMove={onHover} onMouseLeave={() => setHover(null)}
              style={{
                width: Math.min(cSize, 560), height: Math.min(cSize, 560),
                cursor: "crosshair", border: "1px solid #1a1a2e",
                boxShadow: "0 0 60px rgba(232,138,26,0.06)",
              }}
            />
            <div style={{ marginTop: 4, fontSize: 10, color: "#e88a1a66", height: 16, display: "flex", justifyContent: "space-between" }}>
              {hover && hover.glyph >= 0 ? (
                <span style={{ color: FAMILY_COLORS[(hover.glyph >> 2) & 3] }}>
                  [{hover.row},{hover.col}] {GLYPH_NAMES[hover.glyph]} ({hover.glyph.toString(2).padStart(4, "0")})
                </span>
              ) : <span>Hover to inspect</span>}
              {result && <span>{result.gridSize}×{result.gridSize}</span>}
            </div>
          </div>

          {/* Stats panel */}
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

            {/* Distribution by family */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>GLYPH DISTRIBUTION</div>
              {FAMILY_NAMES.map((fam, fi) => {
                const famCount = counts.slice(fi * 4, fi * 4 + 4).reduce((a, b) => a + b, 0);
                const pct = (famCount / totalCells * 100);
                return (
                  <div key={fi} style={{ marginBottom: 6 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", fontSize: 9, marginBottom: 2 }}>
                      <span style={{ color: FAMILY_COLORS[fi] }}>{fam}</span>
                      <span style={{ color: "#71717a" }}>{famCount} ({pct.toFixed(1)}%)</span>
                    </div>
                    <div style={{ display: "flex", gap: 1, height: 6 }}>
                      {[0, 1, 2, 3].map(vi => {
                        const w = totalCells > 0 ? (counts[fi * 4 + vi] / totalCells * 100) : 0;
                        return (
                          <div key={vi} style={{
                            width: `${w}%`, background: FAMILY_COLORS[fi],
                            opacity: 0.3 + vi * 0.2, transition: "width 0.3s",
                          }} title={`${GLYPH_NAMES[fi * 4 + vi]}: ${counts[fi * 4 + vi]}`} />
                        );
                      })}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Metrics */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10, marginBottom: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>METRICS</div>
              {[
                ["Encoding", "16 glyphs → 4 bits/cell"],
                ["Grid", `${result?.gridSize}×${result?.gridSize} = ${result?.gridSize ** 2} cells`],
                ["vs Binary QR", `~72×72 = 5,184 cells (${((1 - (result?.gridSize ** 2 || 0) / 5184) * 100).toFixed(0)}% reduction)`],
                ["vs 4-state", `~51×51 = 2,601 cells (${((1 - (result?.gridSize ** 2 || 0) / 2601) * 100).toFixed(0)}% reduction)`],
                ["Print @ 1.0mm/cell", `${((result?.gridSize || 0) * 1.0 / 10).toFixed(1)}cm`],
                ["Print @ 0.8mm/cell", `${((result?.gridSize || 0) * 0.8 / 10).toFixed(1)}cm`],
                ["Min px/cell (camera)", "16×16"],
                ["Coarse decode fallback", "2 bits (shape family)"],
              ].map(([k, v], i) => (
                <div key={i} style={{
                  display: "flex", justifyContent: "space-between", fontSize: 10,
                  padding: "3px 0", borderBottom: i < 7 ? "1px solid #1a1a2e" : "none",
                }}>
                  <span style={{ color: "#71717a" }}>{k}</span>
                  <span style={{ color: "#e88a1a" }}>{v}</span>
                </div>
              ))}
            </div>

            {/* Scanner pipeline */}
            <div style={{ background: "#0d0d0f", border: "1px solid #1a1a2e", padding: 10 }}>
              <div style={{ fontSize: 9, letterSpacing: 2, color: "#e88a1a66", marginBottom: 6 }}>DART SCANNER PIPELINE</div>
              <div style={{ fontSize: 9, color: "#a1a1aa", lineHeight: 1.9 }}>
                {[
                  ["1", "Detect 3 finder patterns (Sq+Ci+Cr combo)"],
                  ["2", "Perspective warp → normalized grid"],
                  ["3", "Timing strips → cell boundary map"],
                  ["4", "Per cell: binarize → contour → classify"],
                  ["", "  Coarse: vertex count + circularity → family"],
                  ["", "  Fine: area ratio + center fill → variant"],
                  ["5", "Read serpentine → nibbles → bytes"],
                  ["6", "Deinterleave → verify CRC-8"],
                ].map(([n, t], i) => (
                  <div key={i} style={{ display: "flex", gap: 6 }}>
                    <span style={{ color: "#e88a1a", minWidth: 12 }}>{n}</span>
                    <span>{t}</span>
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
