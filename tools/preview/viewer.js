// Offline preview of Cursebound Farm geometry exported by tools/lune (bake / models).
// Approximates Roblox's dusk lighting, atmosphere, neon bloom and smooth terrain so the
// map's composition can be judged without Roblox Studio. Not used by the game itself.
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const params = new URLSearchParams(location.search);
const W = Number(params.get("w") || 1280), H = Number(params.get("h") || 720);

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.setPixelRatio(1);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = Number(params.get("exposure") || 1.05);
renderer.shadowMap.enabled = params.get("shadows") !== "0";
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(70, W / H, 0.5, 4000);

function skyTexture(top, mid, horizon) {
  const c = document.createElement("canvas"); c.width = 4; c.height = 256;
  const g = c.getContext("2d"); const grad = g.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0, top); grad.addColorStop(0.55, mid); grad.addColorStop(0.82, horizon); grad.addColorStop(1, horizon);
  g.fillStyle = grad; g.fillRect(0, 0, 4, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

const MAT_ROUGH = { Wood: 0.85, WoodPlanks: 0.85, Slate: 0.9, Cobblestone: 0.95, Rock: 0.95, Basalt: 0.9, Granite: 0.85,
  Marble: 0.4, Metal: 0.35, DiamondPlate: 0.4, Glass: 0.05, Fabric: 1, Grass: 1, LeafyGrass: 1, Sand: 1, Brick: 0.9,
  Concrete: 0.95, Pebble: 0.95, SmoothPlastic: 0.55, Plastic: 0.6, Ice: 0.1, Foil: 0.3, Ground: 1, Mud: 0.9 };

function rbxColor(c) { return new THREE.Color().setRGB(c[0] / 255, c[1] / 255, c[2] / 255, THREE.SRGBColorSpace); }

const geoms = {
  b: new THREE.BoxGeometry(1, 1, 1),
  s: new THREE.SphereGeometry(0.5, 18, 12),
  e: new THREE.SphereGeometry(0.5, 18, 12),
  c: new THREE.CylinderGeometry(0.5, 0.5, 1, 20).rotateZ(-Math.PI / 2),
};
function wedgeGeometry() {
  // Roblox WedgePart: full height at the back (+Z), slope rising from the front-bottom edge.
  const v = [
    -0.5, -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0.5, // bottom 0-3
    -0.5, 0.5, 0.5, 0.5, 0.5, 0.5, // top back edge 4-5
  ];
  const idx = [0, 2, 1, 0, 3, 2, // bottom
    3, 4, 5, 3, 5, 2, // back face
    0, 1, 5, 0, 5, 4, // slope
    0, 4, 3, // left
    1, 2, 5]; // right
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(v, 3));
  g.setIndex(idx);
  return g.toNonIndexed().computeVertexNormals() || g;
}
const wg = wedgeGeometry(); wg.computeVertexNormals();
geoms.w = wg; geoms.cw = wg;

function partMatrix(p) {
  const m = new THREE.Matrix4();
  const r = p.r;
  m.set(r[0], r[1], r[2], p.p[0], r[3], r[4], r[5], p.p[1], r[6], r[7], r[8], p.p[2], 0, 0, 0, 1);
  let sx = p.z[0], sy = p.z[1], sz = p.z[2];
  if (p.k === "s") { const d = Math.min(sx, sy, sz); sx = sy = sz = d; }
  if (p.k === "c") { const d = Math.min(sy, sz); sy = sz = d; }
  m.multiply(new THREE.Matrix4().makeScale(sx, sy, sz));
  return m;
}

function addParts(parts) {
  const groups = new Map();
  for (const p of parts) {
    const neon = p.m === "Neon";
    const glass = p.m === "Glass" || p.m === "ForceField";
    const tBucket = p.t > 0.02 || glass ? Math.round(Math.max(p.t, glass ? 0.5 : 0) * 10) / 10 : 0;
    const key = `${p.k}|${neon ? "neon" : MAT_ROUGH[p.m] ?? 0.6}|${tBucket}`;
    if (!groups.has(key)) groups.set(key, { k: p.k, neon, rough: MAT_ROUGH[p.m] ?? 0.6, metal: p.m === "Metal" ? 0.6 : 0, t: tBucket, list: [] });
    groups.get(key).list.push(p);
  }
  let count = 0;
  for (const g of groups.values()) {
    let mat;
    if (g.neon) {
      mat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: g.t > 0, opacity: 1 - g.t, depthWrite: g.t < 0.3 });
    } else {
      mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: g.rough, metalness: g.metal, transparent: g.t > 0, opacity: 1 - g.t, depthWrite: g.t < 0.3 });
    }
    const mesh = new THREE.InstancedMesh(geoms[g.k] || geoms.b, mat, g.list.length);
    g.list.forEach((p, i) => {
      mesh.setMatrixAt(i, partMatrix(p));
      const col = rbxColor(p.c);
      if (g.neon) col.multiplyScalar(2.2);
      mesh.setColorAt(i, col);
    });
    mesh.castShadow = !g.neon && g.t < 0.5;
    mesh.receiveShadow = true;
    scene.add(mesh);
    count += g.list.length;
  }
  return count;
}

// ---- Terrain: rebuild a heightfield from recorded Fill* operations -------------------------
function buildTerrain(t) {
  if (!t || !t.ops || t.ops.length === 0) return;
  const step = t.step || 2;
  const minX = t.bounds[0], minZ = t.bounds[1], maxX = t.bounds[2], maxZ = t.bounds[3];
  const nx = Math.floor((maxX - minX) / step) + 1, nz = Math.floor((maxZ - minZ) / step) + 1;
  const height = new Float32Array(nx * nz).fill(-60);
  const mat = new Array(nx * nz).fill("Rock");
  const water = new Float32Array(nx * nz).fill(-1e9);
  const colors = t.colors || {};

  function hitBox(op, x, z) {
    // Ray straight down through the oriented box (slab test in local space).
    const r = op.r, c = op.p, s = op.z;
    const ox = x - c[0], oy = 5000 - c[1], oz = z - c[2];
    // local = R^T * (o)
    const lo = [r[0] * ox + r[3] * oy + r[6] * oz, r[1] * ox + r[4] * oy + r[7] * oz, r[2] * ox + r[5] * oy + r[8] * oz];
    const ld = [-r[3], -r[4], -r[5]];
    let tmin = -Infinity, tmax = Infinity;
    for (let i = 0; i < 3; i++) {
      const h = s[i] / 2;
      if (Math.abs(ld[i]) < 1e-9) { if (lo[i] < -h || lo[i] > h) return null; continue; }
      let t1 = (-h - lo[i]) / ld[i], t2 = (h - lo[i]) / ld[i];
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2);
      if (tmin > tmax) return null;
    }
    if (op.k === "wedge") {
      // Clip by the wedge slope plane in local space: y <= z * (sy/sz) (top edge at +Z).
      const sy = s[1], sz = s[2];
      let a = null, b = null;
      const steps = 24;
      for (let i = 0; i <= steps; i++) {
        const tt = tmin + (tmax - tmin) * i / steps;
        const py = lo[1] + ld[1] * tt, pz = lo[2] + ld[2] * tt;
        if (py / sy <= pz / sz + 1e-6) { if (a === null) a = tt; b = tt; }
      }
      if (a === null) return null;
      tmin = a; tmax = b;
    }
    return [5000 - tmin, 5000 - tmax];
  }
  function hitBall(op, x, z) {
    const dx = x - op.p[0], dz = z - op.p[2];
    const d2 = dx * dx + dz * dz, r2 = op.radius * op.radius;
    if (d2 > r2) return null;
    const h = Math.sqrt(r2 - d2);
    return [op.p[1] + h, op.p[1] - h];
  }
  function hitCyl(op, x, z) {
    const dx = x - op.p[0], dz = z - op.p[2];
    if (dx * dx + dz * dz > op.radius * op.radius) return null;
    return [op.p[1] + op.height / 2, op.p[1] - op.height / 2];
  }

  for (const op of t.ops) {
    let x0, x1, z0, z1;
    if (op.k === "ball" || op.k === "cyl") {
      x0 = op.p[0] - op.radius; x1 = op.p[0] + op.radius; z0 = op.p[2] - op.radius; z1 = op.p[2] + op.radius;
    } else {
      const ext = Math.hypot(op.z[0], op.z[1], op.z[2]) / 2;
      x0 = op.p[0] - ext; x1 = op.p[0] + ext; z0 = op.p[2] - ext; z1 = op.p[2] + ext;
    }
    const i0 = Math.max(0, Math.floor((x0 - minX) / step)), i1 = Math.min(nx - 1, Math.ceil((x1 - minX) / step));
    const j0 = Math.max(0, Math.floor((z0 - minZ) / step)), j1 = Math.min(nz - 1, Math.ceil((z1 - minZ) / step));
    for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
      const x = minX + i * step, z = minZ + j * step;
      const hit = op.k === "ball" ? hitBall(op, x, z) : op.k === "cyl" ? hitCyl(op, x, z) : hitBox(op, x, z);
      if (!hit) continue;
      const [top, bottom] = hit;
      const idx = j * nx + i;
      if (op.m === "Air") {
        if (bottom < height[idx] && top >= height[idx] - 0.5) { height[idx] = Math.min(height[idx], bottom); }
        if (water[idx] > bottom) water[idx] = Math.min(water[idx], bottom);
      } else if (op.m === "Water") {
        if (top > water[idx]) water[idx] = top;
      } else {
        if (op.paint) { if (top >= height[idx] - 1.5 && bottom <= height[idx] + 0.5) mat[idx] = op.m; continue; }
        if (top >= height[idx] - 0.01 && bottom <= height[idx] + 4) { height[idx] = top; mat[idx] = op.m; }
        else if (top > height[idx]) { height[idx] = top; mat[idx] = op.m; }
      }
    }
  }
  const geo = new THREE.PlaneGeometry((nx - 1) * step, (nz - 1) * step, nx - 1, nz - 1);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position;
  const col = new Float32Array(pos.count * 3);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const v = j * nx + i;
    pos.setX(v, minX + i * step); pos.setZ(v, minZ + j * step); pos.setY(v, height[v]);
    const c = rbxColor(colors[mat[v]] || [90, 90, 90]);
    const n = 0.92 + 0.16 * Math.sin(i * 12.9898 + j * 78.233) * Math.sin(i * 0.37 + j * 0.21);
    col[v * 3] = c.r * n; col[v * 3 + 1] = c.g * n; col[v * 3 + 2] = c.b * n;
  }
  geo.setAttribute("color", new THREE.BufferAttribute(col, 3));
  geo.computeVertexNormals();
  const ground = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1 }));
  ground.receiveShadow = true; ground.castShadow = true;
  scene.add(ground);

  const wgeo = new THREE.PlaneGeometry((nx - 1) * step, (nz - 1) * step, nx - 1, nz - 1);
  wgeo.rotateX(-Math.PI / 2);
  const wp = wgeo.attributes.position;
  const keep = [];
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    const v = j * nx + i;
    wp.setX(v, minX + i * step); wp.setZ(v, minZ + j * step);
    wp.setY(v, water[v] > height[v] ? water[v] : -200);
  }
  const index = wgeo.index.array; const kept = [];
  for (let q = 0; q < index.length; q += 3) {
    const a = index[q], b = index[q + 1], c = index[q + 2];
    if (wp.getY(a) > -150 && wp.getY(b) > -150 && wp.getY(c) > -150) kept.push(a, b, c);
  }
  wgeo.setIndex(kept);
  const wc = rbxColor(t.waterColor || [40, 60, 80]);
  const wmesh = new THREE.Mesh(wgeo, new THREE.MeshStandardMaterial({ color: wc, roughness: 0.08, metalness: 0.3, transparent: true, opacity: 0.82 }));
  scene.add(wmesh);
}

const asList = (x) => (Array.isArray(x) ? x : Object.values(x || {}));

async function main() {
  const src = params.get("scene");
  const data = await (await fetch(src)).json();
  data.parts = asList(data.parts); data.lights = asList(data.lights);
  if (data.terrain) data.terrain.ops = asList(data.terrain.ops);
  const L = data.lighting || {};
  scene.background = skyTexture(L.skyTop || "#1d1630", L.skyMid || "#5a3a6e", L.skyHorizon || "#d9825a");
  const baseFog = Number(params.get("fog") || L.fogDensity || 0.0024);
  scene.fog = new THREE.FogExp2(new THREE.Color(L.fog || "#5d4870"), baseFog);
  scene.add(new THREE.HemisphereLight(new THREE.Color(L.hemiSky || "#8c7ab8"), new THREE.Color(L.hemiGround || "#3a3040"), L.hemi || 1.5));
  const sun = new THREE.DirectionalLight(new THREE.Color(L.sun || "#ffb27a"), L.sunIntensity || 1.6);
  const sd = L.sunDir || [-0.75, 0.32, 0.25];
  sun.position.set(sd[0] * 600, sd[1] * 600, sd[2] * 600);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
  const sc = sun.shadow.camera; sc.left = -380; sc.right = 380; sc.top = 380; sc.bottom = -380; sc.near = 10; sc.far = 1600;
  sun.shadow.bias = -0.0008;
  scene.add(sun);
  const n = addParts(data.parts || []);
  buildTerrain(data.terrain);

  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), 0.55, 0.5, 0.82));
  composer.addPass(new OutputPass());

  const lights = (data.lights || []).map((l) => ({ ...l, obj: null }));
  const maxLights = Number(params.get("lights") || 20);
  const pool = [];
  for (let i = 0; i < maxLights; i++) { const pl = new THREE.PointLight(0xffffff, 0, 10, 2); scene.add(pl); pool.push(pl); }

  window.renderView = (view) => {
    camera.fov = view.fov || 70; camera.updateProjectionMatrix();
    scene.fog.density = view.fog ?? baseFog;
    camera.position.set(...view.pos); camera.lookAt(new THREE.Vector3(...view.look));
    // Use the point lights closest to the camera's focus.
    const focus = new THREE.Vector3(...(view.focus || view.look));
    lights.sort((a, b) => focus.distanceToSquared(new THREE.Vector3(...a.p)) - focus.distanceToSquared(new THREE.Vector3(...b.p)));
    pool.forEach((pl, i) => {
      const l = lights[i];
      if (!l) { pl.intensity = 0; return; }
      pl.position.set(...l.p); pl.color = rbxColor(l.c); pl.distance = l.range * 1.6; pl.intensity = l.b * 22; pl.decay = 1.6;
    });
    composer.render();
    return true;
  };
  window.sceneInfo = { parts: n, lights: lights.length, ops: data.terrain ? data.terrain.ops.length : 0 };
  window.ready = true;
}
main().catch((e) => { window.renderError = String(e.stack || e); });
