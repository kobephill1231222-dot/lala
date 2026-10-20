// Rasterizes a flattened UI (from tools/lune/lib/GuiExport.luau) into a PNG, with no
// dependencies: rectangles are filled into an RGBA buffer, text is drawn with a small 5x7
// bitmap font, and the PNG is written with node:zlib. For offline previews of the pixel UI.
// Usage: node tools/pixel/rasterize.mjs <ui.json> <out.png> [scale]
import fs from "node:fs";
import zlib from "node:zlib";

const [input, output, scaleArg = "1"] = process.argv.slice(2);
const scene = JSON.parse(fs.readFileSync(input, "utf8"));
const S = Math.max(1, Math.floor(Number(scaleArg)));
const W = Math.round(scene.w * S);
const H = Math.round(scene.h * S);
const px = new Uint8Array(W * H * 4);
for (let i = 0; i < W * H; i++) px[i * 4 + 3] = 255; // opaque black

function fill(x0, y0, x1, y1, c, a = 1, clip) {
  let ax = Math.round(x0 * S), ay = Math.round(y0 * S), bx = Math.round(x1 * S), by = Math.round(y1 * S);
  if (clip) {
    ax = Math.max(ax, Math.round(clip[0] * S)); ay = Math.max(ay, Math.round(clip[1] * S));
    bx = Math.min(bx, Math.round(clip[2] * S)); by = Math.min(by, Math.round(clip[3] * S));
  }
  ax = Math.max(0, ax); ay = Math.max(0, ay); bx = Math.min(W, bx); by = Math.min(H, by);
  for (let y = ay; y < by; y++) {
    for (let x = ax; x < bx; x++) {
      const i = (y * W + x) * 4;
      px[i] = Math.round(px[i] * (1 - a) + c[0] * a);
      px[i + 1] = Math.round(px[i + 1] * (1 - a) + c[1] * a);
      px[i + 2] = Math.round(px[i + 2] * (1 - a) + c[2] * a);
    }
  }
}

const list = (v) => (Array.isArray(v) ? v : []);
for (const r of list(scene.rects)) fill(r.x, r.y, r.x + r.w, r.y + r.h, r.c, r.a ?? 1);

// 5x7 font (uppercase, digits, common punctuation). Unknown characters draw as a box.
const F = {
  A: ".###.#...##...#######...##...##...#", B: "####.#...#####.#...##...##...#####.", C: ".#####....#....#....#....#.....####",
  D: "####.#...##...##...##...##...#####.", E: "######....####.#....#....#....#####", F: "######....####.#....#....#....#....",
  G: ".####.#....#..###...##...##...#.###", H: "#...##...#######...##...##...##...#", I: "#####..#....#....#....#....#..#####",
  J: "..###...#....#....#....##...#.###..", K: "#...##..#.###..#..#.#...##...##...#", L: "#....#....#....#....#....#....#####",
  M: "#...###.###.#.##...##...##...##...#", N: "#...###..##.#.##..###...##...##...#", O: ".###.#...##...##...##...##...#.###.",
  P: "####.#...##...#####.#....#....#....", Q: ".###.#...##...##...##.#.##..#..##.#", R: "####.#...##...#####.#..#.#...##...#",
  S: ".#####....#.....###.....#....#####.", T: "#####..#....#....#....#....#....#..", U: "#...##...##...##...##...##...#.###.",
  V: "#...##...##...##...##...#.#.#...#..", W: "#...##...##...##.#.##.#.##.#.#.#.#.", X: "#...##...#.#.#...#...#.#.#...##...#",
  Y: "#...##...#.#.#...#....#....#....#..", Z: "#####....#...#...#...#...#....#####",
  0: ".###.#..###.#.###..##...##...#.###.", 1: "..#...##....#....#....#....#..#####", 2: ".###.#...#....#...#...#...#...#####",
  3: "#####...#...#.....#....##...#.###..", 4: "...#...##..#.#.#..#.#####...#....#.", 5: "######....####.....#....##...#.###.",
  6: "..##..#...#....####.#...##...#.###.", 7: "#####....#...#...#...#....#....#...", 8: ".###.#...##...#.###.#...##...#.###.",
  9: ".###.#...##...#.####....#...#..##..",
  " ": "...................................", ".": "..............................##...", ",": ".........................##...#....",
  ":": "......##....##.........##....##....", "!": "..#....#....#....#....#.........#..", "?": ".###.#...#....#...#...#.........#..",
  "$": "..#...####.#....###....#.####...#..", "/": "....#...#...#...#...#...#...#......", "-": "...............###.................",
  "+": ".......#....#..#####..#....#.......", "%": "##...##..#...#...#...#...#..##...##", "(": "...#...#...#....#....#.....#.....#.",
  ")": ".#.....#.....#....#....#...#...#...", "'": "..#....#...#.......................", "\"": ".#.#..#.#..........................",
  "·": "..............##...................", "x": "......#...#.#.#...#...#.#.#...#....", "*": ".......#.#..#..#####..#..#.#.......",
  "=": "..........#####.....#####..........", "<": "...#...#...#...#.....#.....#.....#.", ">": ".#.....#.....#.....#...#...#...#...",
  "[": ".###..#....#....#....#....#....###.", "]": ".###....#....#....#....#....#..###.", "#": ".#.#..#.#.#####.#.#.#####.#.#..#.#.",
};
function drawText(t) {
  const text = String(t.text).replace(/<[^>]+>/g, "").toUpperCase();
  const lines = text.split("\n");
  const size = Math.max(7, Math.min(t.size || 14, t.h || 1000));
  const k = Math.max(1, Math.floor(size / 8)); // font pixels per glyph pixel, in UI pixels
  const lineH = 8 * k;
  let y = t.y + Math.max(0, (t.h - lines.length * lineH) / 2);
  for (const line of lines) {
    const lw = line.length * 6 * k;
    let x = t.x;
    if (t.align === "Center") x = t.x + (t.w - lw) / 2;
    else if (t.align === "Right") x = t.x + t.w - lw;
    for (const ch of line) {
      const g = F[ch] ?? "#####" + "#...#".repeat(5) + "#####";
      for (let gy = 0; gy < 7; gy++)
        for (let gx = 0; gx < 5; gx++)
          if (g[gy * 5 + gx] === "#") fill(x + gx * k, y + gy * k, x + (gx + 1) * k, y + (gy + 1) * k, t.c, 1, t.clip);
      x += 6 * k;
    }
    y += lineH;
  }
}
for (const t of list(scene.texts)) drawText(t);

// PNG encoding
const crcTable = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
const raw = Buffer.alloc((W * 4 + 1) * H);
for (let y = 0; y < H; y++) {
  raw[y * (W * 4 + 1)] = 0;
  Buffer.from(px.buffer, y * W * 4, W * 4).copy(raw, y * (W * 4 + 1) + 1);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
fs.writeFileSync(output, Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
]));
console.log(`wrote ${output} (${W}x${H}, ${list(scene.rects).length} rects, ${list(scene.texts).length} texts)`);
