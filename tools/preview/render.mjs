// Renders preview screenshots of an exported scene with headless Chromium.
// Usage: node render.mjs <scene.json> <views.json> <outDir> [w h]
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright-core";

const [sceneFile, viewsFile, outDir, w = "1280", h = "720"] = process.argv.slice(2);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname));
const sceneAbs = path.resolve(sceneFile);
const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = url === "/scene.json" ? sceneAbs : path.join(root, url);
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
    res.end(buf);
  });
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;
const views = JSON.parse(fs.readFileSync(viewsFile, "utf8"));
fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--disable-background-networking", "--disable-component-update"],
});
const page = await browser.newPage({ viewport: { width: Number(w), height: Number(h) } });
page.on("console", (m) => { if (m.type() === "error") console.log("page:", m.text()); });
const extra = process.env.PREVIEW_PARAMS || "";
await page.goto(`http://localhost:${port}/index.html?scene=/scene.json&w=${w}&h=${h}${extra}`);
await page.waitForFunction(() => window.ready || window.renderError, null, { timeout: 240000 });
const err = await page.evaluate(() => window.renderError);
if (err) { console.error(err); process.exit(1); }
console.log("scene", JSON.stringify(await page.evaluate(() => window.sceneInfo)));
for (const view of views) {
  await page.evaluate((v) => window.renderView(v), view);
  await page.screenshot({ path: path.join(outDir, `${view.name}.png`) });
  console.log("rendered", view.name);
}
await browser.close();
server.close();
