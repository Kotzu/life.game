/* Trophy Room 3D — original stylized geometry only (no game assets). */
'use strict';

const T = window.THREE;
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ------------------------------------------------------------ renderer */
const canvas = document.getElementById('c');
const renderer = new T.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = T.PCFSoftShadowMap;
renderer.toneMapping = T.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.12;

const scene = new T.Scene();
scene.background = new T.Color(0x0a0908);
scene.fog = new T.Fog(0x0a0908, 14, 26);

const camera = new T.PerspectiveCamera(46, 1, 0.1, 60);

/* ------------------------------------------------------------ materials */
const GOLD = 0xc9a860;
const plastic = new T.MeshPhysicalMaterial({
  color: 0xe7e4de, roughness: 0.48, metalness: 0.02, clearcoat: 0.25, clearcoatRoughness: 0.5,
});
const suitMat  = new T.MeshStandardMaterial({ color: 0x14161a, roughness: 0.85 });
const navyMat  = new T.MeshStandardMaterial({ color: 0x1b2433, roughness: 0.8 });
const shirtMat = new T.MeshStandardMaterial({ color: 0xd9d4c8, roughness: 0.9 });
const beltMat  = new T.MeshStandardMaterial({ color: 0x0c0c0c, roughness: 0.5 });
const goldMat  = new T.MeshStandardMaterial({ color: GOLD, roughness: 0.35, metalness: 0.75 });
const trimGlow = new T.MeshStandardMaterial({ color: GOLD, emissive: GOLD, emissiveIntensity: 0.55 });
const wallMat  = new T.MeshStandardMaterial({ color: 0x171412, roughness: 0.95 });
const panelMat = new T.MeshStandardMaterial({ color: 0x1e1a16, roughness: 0.9 });
const plinthMat = new T.MeshStandardMaterial({ color: 0x232019, roughness: 0.6 });
const gunMat   = new T.MeshStandardMaterial({ color: 0x1a1c1e, roughness: 0.4, metalness: 0.6 });
const woodDark = new T.MeshStandardMaterial({ color: 0x2a2018, roughness: 0.85 });

/* procedural plank floor */
function plankTexture() {
  const c = document.createElement('canvas'); c.width = 512; c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#2c2118'; g.fillRect(0, 0, 512, 512);
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 2; col++) {
      const off = (row % 2) * 128;
      const x = col * 256 + off - 256, y = row * 64;
      const shade = 34 + Math.floor(Math.random() * 14);
      g.fillStyle = `rgb(${shade + 10},${shade - 2},${shade - 14})`;
      g.fillRect(x + 2, y + 2, 252, 60);
      g.strokeStyle = 'rgba(0,0,0,0.5)'; g.strokeRect(x + 2, y + 2, 252, 60);
      for (let i = 0; i < 40; i++) {
        g.fillStyle = `rgba(0,0,0,${Math.random() * 0.08})`;
        g.fillRect(x + Math.random() * 252, y + Math.random() * 60, 30, 1);
      }
    }
  }
  const tex = new T.CanvasTexture(c);
  tex.wrapS = tex.wrapT = T.RepeatWrapping; tex.repeat.set(3, 3);
  tex.colorSpace = T.SRGBColorSpace;
  return tex;
}

/* ------------------------------------------------------------ room shell */
const ROOM_W = 11, ROOM_D = 9, ROOM_H = 3.6;
const floor = new T.Mesh(new T.PlaneGeometry(ROOM_W, ROOM_D),
  new T.MeshStandardMaterial({ map: plankTexture(), roughness: 0.8 }));
floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);

function wall(w, h, x, y, z, ry) {
  const m = new T.Mesh(new T.PlaneGeometry(w, h), wallMat);
  m.position.set(x, y, z); m.rotation.y = ry; m.receiveShadow = true; scene.add(m);
  return m;
}
wall(ROOM_W, ROOM_H, 0, ROOM_H / 2, -ROOM_D / 2, 0);
wall(ROOM_D, ROOM_H, -ROOM_W / 2, ROOM_H / 2, 0, Math.PI / 2);
wall(ROOM_D, ROOM_H, ROOM_W / 2, ROOM_H / 2, 0, -Math.PI / 2);
const ceil = new T.Mesh(new T.PlaneGeometry(ROOM_W, ROOM_D),
  new T.MeshStandardMaterial({ color: 0x0d0b0a, roughness: 1 }));
ceil.rotation.x = Math.PI / 2; ceil.position.y = ROOM_H; scene.add(ceil);

/* gold seams on the back wall + skirting */
for (let i = -2; i <= 2; i++) {
  const seam = new T.Mesh(new T.BoxGeometry(0.025, ROOM_H - 0.4, 0.02), trimGlow);
  seam.position.set(i * 2.2, (ROOM_H - 0.4) / 2 + 0.2, -ROOM_D / 2 + 0.02);
  scene.add(seam);
}
const skirt = new T.Mesh(new T.BoxGeometry(ROOM_W, 0.08, 0.03), goldMat);
skirt.position.set(0, 0.04, -ROOM_D / 2 + 0.02); scene.add(skirt);

/* back-wall wardrobe: shelves with folded "clothes" blocks (concept nod) */
const wardrobe = new T.Group();
const shelfW = 4.6;
const frame = new T.Mesh(new T.BoxGeometry(shelfW + 0.2, 2.6, 0.35), woodDark);
frame.position.set(-2.6, 1.5, -ROOM_D / 2 + 0.2); wardrobe.add(frame);
for (let s = 0; s < 3; s++) {
  const shelf = new T.Mesh(new T.BoxGeometry(shelfW, 0.05, 0.3), panelMat);
  shelf.position.set(-2.6, 0.65 + s * 0.75, -ROOM_D / 2 + 0.24); wardrobe.add(shelf);
  for (let b = 0; b < 5; b++) {
    const hues = [0x2a2f3a, 0x3a2f2a, 0x2f2a33, 0x232823, 0x33302b];
    const stack = new T.Mesh(new T.BoxGeometry(0.55, 0.16 + Math.random() * 0.1, 0.26),
      new T.MeshStandardMaterial({ color: hues[(s + b) % 5], roughness: 0.95 }));
    stack.position.set(-4.4 + b * 0.9, 0.78 + s * 0.75, -ROOM_D / 2 + 0.24);
    wardrobe.add(stack);
  }
}
scene.add(wardrobe);

/* ------------------------------------------------------------ mannequin */
function capsule(r, len, mat) {
  const m = new T.Mesh(new T.CapsuleGeometry(r, len, 6, 14), mat);
  m.castShadow = true; return m;
}

function buildMannequin(outfit) {
  // outfit: { torso, legs, cap, belt } materials/flags — original geometry only
  const g = new T.Group();
  const torsoMat = outfit.torso || plastic;
  const legMat = outfit.legs || plastic;

  const hips = new T.Mesh(new T.SphereGeometry(0.155, 20, 14), legMat);
  hips.scale.set(1, 0.72, 0.82); hips.position.y = 0.92; hips.castShadow = true; g.add(hips);

  for (const side of [-1, 1]) {
    const leg = capsule(0.075, 0.62, legMat);
    leg.position.set(side * 0.095, 0.5, 0); g.add(leg);
    const foot = new T.Mesh(new T.BoxGeometry(0.11, 0.07, 0.26), legMat);
    foot.position.set(side * 0.095, 0.05, 0.05); foot.castShadow = true; g.add(foot);
  }

  const torso = new T.Mesh(new T.CylinderGeometry(0.16, 0.135, 0.52, 18), torsoMat);
  torso.position.y = 1.28; torso.castShadow = true; g.add(torso);
  const chest = new T.Mesh(new T.SphereGeometry(0.165, 20, 14), torsoMat);
  chest.scale.set(1, 0.78, 0.8); chest.position.y = 1.5; chest.castShadow = true; g.add(chest);

  if (outfit.shirtV) { // white shirt V under a jacket
    const v = new T.Mesh(new T.CylinderGeometry(0.06, 0.1, 0.3, 3), shirtMat);
    v.position.set(0, 1.44, 0.128); v.rotation.x = 0.12; g.add(v);
  }
  if (outfit.belt) {
    const belt = new T.Mesh(new T.TorusGeometry(0.15, 0.028, 8, 22), beltMat);
    belt.rotation.x = Math.PI / 2; belt.position.y = 1.02; g.add(belt);
    for (const a of [0.6, -0.6, 2.4]) { // pouches
      const p = new T.Mesh(new T.BoxGeometry(0.07, 0.09, 0.05), beltMat);
      p.position.set(Math.sin(a) * 0.16, 1.0, Math.cos(a) * 0.16); g.add(p);
    }
  }

  const neck = new T.Mesh(new T.CylinderGeometry(0.05, 0.06, 0.09, 14), plastic);
  neck.position.y = 1.66; g.add(neck);
  const head = new T.Mesh(new T.SphereGeometry(0.115, 22, 18), plastic);
  head.scale.set(0.88, 1.12, 0.95); head.position.y = 1.8; head.castShadow = true; g.add(head);

  if (outfit.cap) { // service cap: crown + brim
    const crown = new T.Mesh(new T.CylinderGeometry(0.115, 0.125, 0.07, 18), navyMat);
    crown.position.y = 1.9; g.add(crown);
    const top = new T.Mesh(new T.SphereGeometry(0.115, 18, 10), navyMat);
    top.scale.set(1.05, 0.4, 1.05); top.position.y = 1.93; g.add(top);
    const brim = new T.Mesh(new T.CylinderGeometry(0.11, 0.11, 0.015, 18), beltMat);
    brim.scale.set(1, 1, 1.25); brim.position.set(0, 1.87, 0.06); g.add(brim);
  }

  // arms with poses
  function arm(side, pose) {
    const shoulder = new T.Group();
    shoulder.position.set(side * 0.205, 1.56, 0);
    const upper = capsule(0.05, 0.24, torsoMat); upper.position.y = -0.15; shoulder.add(upper);
    const elbow = new T.Group(); elbow.position.y = -0.3; shoulder.add(elbow);
    const fore = capsule(0.042, 0.2, outfit.plasticHands ? plastic : torsoMat);
    fore.position.y = -0.13; elbow.add(fore);
    const hand = new T.Mesh(new T.SphereGeometry(0.05, 12, 10), plastic);
    hand.scale.set(0.8, 1.15, 0.55); hand.position.y = -0.27; elbow.add(hand);

    if (pose === 'attention') {
      shoulder.rotation.z = side * 0.1;
    } else if (pose === 'crossed') {
      shoulder.rotation.z = side * 0.55; shoulder.rotation.x = 0.35;
      elbow.rotation.x = -1.9; elbow.rotation.z = side * -0.7;
    } else if (pose === 'back') {
      shoulder.rotation.x = 0.5; shoulder.rotation.z = side * 0.18;
      elbow.rotation.x = -1.15;
    }
    return shoulder;
  }
  g.add(arm(-1, outfit.pose), arm(1, outfit.pose));
  return g;
}

/* ----------------------------------------------------- plinth + display */
const displays = [];
function plinth(x, z, ry) {
  const g = new T.Group();
  const base = new T.Mesh(new T.BoxGeometry(0.95, 0.16, 0.95), plinthMat);
  base.position.y = 0.08; base.castShadow = base.receiveShadow = true; g.add(base);
  const ring = new T.Mesh(new T.BoxGeometry(0.99, 0.02, 0.99),
    new T.MeshStandardMaterial({ color: 0xfff3d6, emissive: 0xffe9b8, emissiveIntensity: 1.4 }));
  ring.position.y = 0.02; g.add(ring);
  g.position.set(x, 0, z); g.rotation.y = ry;
  scene.add(g);
  return g;
}

function addMannequinDisplay(x, z, ry, outfit, info) {
  const p = plinth(x, z, ry);
  const man = buildMannequin(outfit);
  man.position.y = 0.16; man.scale.setScalar(1.05);
  p.add(man);
  spot(x, z, 0xffd9a0, 1);
  displays.push({ group: p, info, ringY: 0.02 });
  return p;
}

function spot(x, z, color, intensity) {
  const s = new T.SpotLight(color, 26 * intensity, 9, 0.5, 0.55, 1.6);
  s.position.set(x, ROOM_H - 0.15, z + 0.6);
  s.target.position.set(x, 0.8, z);
  s.castShadow = true; s.shadow.mapSize.set(1024, 1024); s.shadow.bias = -0.0004;
  scene.add(s, s.target);
  const halo = new T.Mesh(new T.CylinderGeometry(0.07, 0.09, 0.08, 12),
    new T.MeshStandardMaterial({ color: 0x111, emissive: color, emissiveIntensity: 0.6 }));
  halo.position.set(x, ROOM_H - 0.08, z + 0.6); scene.add(halo);
}

/* the three mannequins (front row, matching Config.DemoLayout) */
addMannequinDisplay(-1.9, -1.2, 0.15, { torso: navyMat, legs: navyMat, cap: true, belt: true, pose: 'attention', plasticHands: true, shirtV: false },
  { label: 'Uniformă patrulare', pose: 'Drepți (militar)', outfit: 'Police Uniform', tip: 'mannequin' });
addMannequinDisplay(0, -1.45, 0, { torso: suitMat, legs: suitMat, shirtV: true, pose: 'back', plasticHands: true },
  { label: 'Costum negru', pose: 'Mâini la spate', outfit: 'Black Suit', tip: 'mannequin' });
addMannequinDisplay(1.9, -1.2, -0.15, { pose: 'crossed' },
  { label: 'Manechin gol', pose: 'Brațe încrucișate', outfit: '— (plastic de bază)', tip: 'mannequin' });

/* ------------------------------------------------- weapon wall (right) */
(function weaponWall() {
  const panel = new T.Mesh(new T.BoxGeometry(0.06, 1.3, 2.2), panelMat);
  panel.position.set(ROOM_W / 2 - 0.05, 1.6, -0.4); scene.add(panel);
  const frameT = new T.Mesh(new T.BoxGeometry(0.07, 0.03, 2.24), goldMat);
  frameT.position.set(ROOM_W / 2 - 0.05, 2.26, -0.4); scene.add(frameT);
  const frameB = frameT.clone(); frameB.position.y = 0.94; scene.add(frameB);

  const rifle = new T.Group();
  const body = new T.Mesh(new T.BoxGeometry(0.09, 0.09, 0.78), gunMat);
  rifle.add(body);
  const barrel = new T.Mesh(new T.CylinderGeometry(0.02, 0.02, 0.42, 10), gunMat);
  barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0.01, -0.58); rifle.add(barrel);
  const stock = new T.Mesh(new T.BoxGeometry(0.07, 0.13, 0.3), gunMat);
  stock.position.set(0, -0.03, 0.5); rifle.add(stock);
  const mag = new T.Mesh(new T.BoxGeometry(0.05, 0.2, 0.09), gunMat);
  mag.position.set(0, -0.13, -0.08); mag.rotation.x = 0.25; rifle.add(mag);
  const scopeM = new T.Mesh(new T.CylinderGeometry(0.03, 0.03, 0.2, 10), gunMat);
  scopeM.rotation.x = Math.PI / 2; scopeM.position.set(0, 0.08, -0.15); rifle.add(scopeM);
  rifle.rotation.y = Math.PI / 2; rifle.rotation.z = -0.12;
  rifle.position.set(ROOM_W / 2 - 0.16, 1.62, -0.4);
  rifle.traverse((o) => { o.castShadow = true; });
  scene.add(rifle);
  spot(ROOM_W / 2 - 0.7, -0.4, 0xffe6c0, 0.7);
  displays.push({ group: rifle, info: {
    label: 'Armă de colecție', pose: 'Montare pe perete', outfit: 'Carabină · tint auriu', tip: 'weapon_wall' } });
})();

/* ------------------------------------------------- glass case (left) */
(function glassCase() {
  const ped = new T.Mesh(new T.BoxGeometry(0.8, 0.9, 0.8), plinthMat);
  ped.position.set(-ROOM_W / 2 + 1.3, 0.45, 0.6); ped.castShadow = true; scene.add(ped);
  const glass = new T.Mesh(new T.BoxGeometry(0.7, 0.55, 0.7),
    new T.MeshPhysicalMaterial({ color: 0xbfd4dd, transparent: true, opacity: 0.1, roughness: 0.05, metalness: 0 }));
  glass.position.set(-ROOM_W / 2 + 1.3, 1.18, 0.6); scene.add(glass);
  const edges = new T.LineSegments(new T.EdgesGeometry(glass.geometry),
    new T.LineBasicMaterial({ color: GOLD }));
  edges.position.copy(glass.position); scene.add(edges);

  const pistol = new T.Group();
  const slide = new T.Mesh(new T.BoxGeometry(0.3, 0.07, 0.05), gunMat); pistol.add(slide);
  const grip = new T.Mesh(new T.BoxGeometry(0.07, 0.16, 0.05), gunMat);
  grip.position.set(0.1, -0.1, 0); grip.rotation.z = -0.25; pistol.add(grip);
  pistol.position.set(-ROOM_W / 2 + 1.3, 1.12, 0.6); pistol.rotation.z = 0.12;
  scene.add(pistol);
  spot(-ROOM_W / 2 + 1.3, 0.6, 0xffe6c0, 0.6);
  displays.push({ group: glass, info: {
    label: 'Pistol de serviciu', pose: 'Vitrină de sticlă', outfit: 'Serial #KTZ-0001', tip: 'weapon_case' } });
})();

/* ambient fill */
scene.add(new T.AmbientLight(0x272220, 1.6));
const hemi = new T.HemisphereLight(0x2a2620, 0x0c0a08, 0.7); scene.add(hemi);

/* ------------------------------------------------------------ camera rig */
let yaw = 0.35, pitch = 0.28, dist = 6.4;
const target = new T.Vector3(0, 1.15, -0.4);
let lastInteract = -1e9;

function applyCamera() {
  pitch = Math.max(0.06, Math.min(1.1, pitch));
  dist = Math.max(3.2, Math.min(9.5, dist));
  yaw = Math.max(-1.15, Math.min(1.15, yaw)); // stay inside the open side
  camera.position.set(
    target.x + Math.sin(yaw) * Math.cos(pitch) * dist,
    target.y + Math.sin(pitch) * dist,
    target.z + Math.cos(yaw) * Math.cos(pitch) * dist);
  camera.lookAt(target);
}

let dragging = false, moved = 0, px = 0, py = 0, pinch = 0;
canvas.addEventListener('pointerdown', (e) => {
  dragging = true; moved = 0; px = e.clientX; py = e.clientY;
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', (e) => {
  if (!dragging) return;
  const dx = e.clientX - px, dy = e.clientY - py;
  moved += Math.abs(dx) + Math.abs(dy);
  px = e.clientX; py = e.clientY;
  yaw -= dx * 0.005; pitch += dy * 0.004;
  lastInteract = performance.now();
});
addEventListener('pointerup', (e) => {
  if (dragging && moved < 6) pick(e.clientX, e.clientY);
  dragging = false;
});
canvas.addEventListener('wheel', (e) => {
  e.preventDefault(); dist += e.deltaY * 0.004; lastInteract = performance.now();
}, { passive: false });
canvas.addEventListener('touchmove', (e) => {
  if (e.touches.length === 2) {
    const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX,
                         e.touches[0].clientY - e.touches[1].clientY);
    if (pinch) dist -= (d - pinch) * 0.01;
    pinch = d; lastInteract = performance.now();
  }
}, { passive: true });
canvas.addEventListener('touchend', () => { pinch = 0; });

/* ------------------------------------------------------------ picking */
const ray = new T.Raycaster();
const card = document.getElementById('card');
const chip = document.getElementById('chip');
let selected = null;

function pick(cx, cy) {
  const r = canvas.getBoundingClientRect();
  ray.setFromCamera(new T.Vector2(
    ((cx - r.left) / r.width) * 2 - 1, -((cy - r.top) / r.height) * 2 + 1), camera);
  let best = null;
  for (const d of displays) {
    const hits = ray.intersectObject(d.group, true);
    if (hits.length && (!best || hits[0].distance < best.dist)) {
      best = { d, dist: hits[0].distance };
    }
  }
  select(best ? best.d : null);
}

const TIP_RO = { mannequin: 'Manechin', weapon_wall: 'Armă pe perete', weapon_case: 'Vitrină' };
function select(d) {
  selected = d;
  if (!d) { card.classList.remove('show'); chip.classList.remove('show'); return; }
  card.querySelector('.card-type').textContent = TIP_RO[d.info.tip] || d.info.tip;
  card.querySelector('.card-title').textContent = d.info.label;
  card.querySelector('.card-pose').textContent = d.info.pose;
  card.querySelector('.card-outfit').textContent = d.info.outfit;
  card.classList.add('show');
  chip.classList.add('show');
}

const chipPos = new T.Vector3();
function placeChip() {
  if (!selected) return;
  selected.group.getWorldPosition(chipPos);
  chipPos.y += selected.info.tip === 'mannequin' ? 2.25 : 0.75;
  chipPos.project(camera);
  const r = canvas.getBoundingClientRect();
  chip.style.left = ((chipPos.x * 0.5 + 0.5) * r.width) + 'px';
  chip.style.top = ((-chipPos.y * 0.5 + 0.5) * r.height) + 'px';
}

/* ------------------------------------------------------------ loop */
function resize() {
  const w = innerWidth, h = innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h; camera.updateProjectionMatrix();
}
addEventListener('resize', resize); resize();

renderer.setAnimationLoop((t) => {
  if (!reduced && !dragging && t - lastInteract > 4000) {
    yaw = Math.sin(t * 0.00012) * 0.75; // slow showcase sweep
  }
  applyCamera();
  placeChip();
  renderer.render(scene, camera);
});
