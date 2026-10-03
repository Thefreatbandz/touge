# TOUGE — Graphics Ideas & Asset Sources

Research compiled 2026-10-03 for our Godot 4.7 PS1-style arcade drift racer
(sunset city, web export, iPhone 12 target). Everything below is picked for:
**gl_compatibility renderer, WebGL2, small team, no licensed IP.**

> What's already in the game (don't re-add): skid marks, neon underglow,
> chunky buildings w/ lit windows + roof edge lights, neon billboards +
> building signs, streetlight pools, rumble strips, road studs, rail markers,
> sparks on scrape, drift smoke, gantry signs, blimp, sun halo, clouds,
> skyline silhouettes, parked cars, vending machines, cones, crosswalks,
> checkered start, minimap, gap/position HUD, speed FOV kick, camera shake.

---

## 1. Visual Techniques

### Authentic PS1 look (the real recipe)
The PS1 was a 2D rasterizer, not a real 3D GPU. The signature artifacts:
- **Affine texture mapping** — no perspective correction, textures "swim"
  as polygons turn. (We use flat vertex colors, so we already dodge this;
  if we ever add textures, keep them tiny and unfiltered.)
- **Vertex wobble** — vertices snapped to a coarse pixel grid each frame.
- **Dithering** — 4×4 ordered dither pattern applied per-polygon to hide
  color banding on gradients (sky!).
- **RGB565 color quantization** — 16-bit color. Round channels to 5/6 bits.
- **Heavy distance fog** — hid the ~300m draw distance. We already do this.
- **Gouraud shading + low internal res** (320×240) — we keep our res high
  for phones but keep shading simple.

**Implementable in Godot 4 (all work on gl_compatibility):**
- **Fullscreen dither + RGB5 post shader** — one cheap canvas shader on a
  full-rect ColorRect. Use the real PS1 4×4 matrix, `round()` not `floor()`:
  ```glsl
  vec3 to_rgb5(vec3 c){ return round(clamp(c, vec3(0.0), vec3(1.0)) * 31.0) / 31.0; }
  // PS1 dither matrix (additive, ±4/255):
  // -4, 0,-3, 1,   2,-2, 3,-1,  -3, 1,-4, 0,   3,-1, 2,-2
  ```
  This will make our sunset sky gradient look *correct* (no banding) and
  instantly more PS1. Sources:
  - https://jettelly.com/blog/recreating-the-ps1-s-rendering-quirks-in-godot/
  - https://github.com/wisdomabeladah/summer/blob/HEAD/library/skills/psx-retro-rendering/SKILL.md
  - https://github.com/ka1ne/godot-psx-style-demo (demo project, Godot 4)
  - https://www.youtube.com/watch?v=ETE3MrBJ1p8 (PS1 shader tutorial w/ bayer matrix)
- **Vertex-color lighting** — fake light with vertex colors instead of more
  lights (we already do this; keep it — real lights are expensive on web).
- **Prefer additive blending over alpha** for glows (cheaper + no sort issues).
  (ka1ne/godot-psx-style-demo tips)

### Godot 4 web constraints (must-know)
- Web export = **gl_compatibility ONLY** (WebGL2). These are **silently absent**:
  volumetric fog, SSR, SDFGI/VoxelGI, TAA, FSR2.
  https://github.com/lynricsy/hyperskills/blob/HEAD/skills/godot/SKILL.md
- **Triangle budgets for web** (strayspark presets): props ~6k, hero ~12k,
  environment ~10k tris; keep textures ≤1K.
  https://www.strayspark.studio/blog/meshy-tripo-to-godot-4-gltf-lod-normal-maps
- **Draw calls**: batch repeated props with MultiMeshInstance3D (we do).
  Avoid per-frame property writes on hot paths.
- **Glow/bloom works** on Compatibility (`glow_enabled`) — we use it.
  Keep it; it's our neon.

### Speed feel ("juice")
- FOV kick with speed ✓ (have it) — Ridge Racer V even widens FOV in
  replays for extra speed sensation.
- Camera lag (soft follow, not hard-parented) ✓ (have it).
- Camera shake: violent but rare (impacts), subtle at top speed ✓ (have it).
- **Speed lines**: thin white streak quads at screen edges, opacity ∝ speed.
  Cheap CanvasLayer overlay. Not yet in game.
- Motion-blur feel without real MB: stretch FOV + shake + lines is enough.
  https://hackread.com/the-juice-factor-designing-game-feel/

### Synthwave / Outrun palette (for future night mode or menus)
- Hot pink `#FF2D95`, electric cyan `#00FFFF`, deep violet `#2D0052`,
  chrome yellow sun `#FFD700`, laser orange `#FF6B00`.
- Scanline sun, neon grid floor, chrome text.
- https://github.com/paolomoz/skills/blob/HEAD/skills/sumi/references/styles/synthwave.md
- Playable reference (runs on GitHub Pages!): https://tetsu.github.io/neon-drive/
  (source: https://github.com/tetsu/neon-drive)
- Three.js synthwave racer w/ light trails: https://github.com/githubutsav/polarity-racing

---

## 2. Asset Sources (free, check license per item)

### 3D packs — CC0, Godot-ready
| Source | What | License | URL |
|---|---|---|---|
| Kenney — City Kit (Roads) | roads, traffic lights, signs, barriers | CC0 | https://kenney.nl/assets/city-kit-roads |
| Kenney — Racing Kit | race cars, barriers, gantries, billboards, pit garage, start markers | CC0 | https://kenney.nl/assets/racing-kit |
| Kenney — Car Kit | 45+ cars/vans + separate wheels | CC0 | https://kenney.nl/assets/car-kit |
| RGS_Dev — Low Poly Vehicles | 20+ cars (police, muscle, taxi…), separated wheels | CC0 | https://rgsdev.itch.io/free-low-poly-vehicles-pack |
| IceMaan — Low Poly Car | 3 body kits, 4 rims, 2 spoilers, multi-material | CC0 | https://icemaan.itch.io/free-low-poly-car3-3-body-kits-4-rims |
| IceMaan — Free Car Low Poly | coupe + compatible wheels | CC0 (verify page) | https://icemaan.itch.io/free-car-low-poly |
| Eclair Assets — Car Kit GLB | 50 GLBs repackaged from Kenney | CC0 | https://eclair-assets.itch.io/car-kit-glb-pack-50-free-cc0-3d-models |
| boggle — PSX Style Cars | PS1-aesthetic low-poly cars | verify page | search itch.io "PSX Style Cars boggle" |
| Quaternius | cute low-poly cars/props | CC0 | search itch.io "Quaternius" |
| itch.io car tag | browsable list, filter by license | varies — check badge | https://itch.io/game-assets/tag-car/tag-low-poly |
| eracoon — Vehicles Assets | 84 low-poly vehicles | CC0 | search opengameart.org "Vehicles Assets pt1" |
| Poly Haven | high-quality models (few cars, good props) | CC0 | https://polyhaven.com/models |

> Import note: `.glb` imports headless in Godot (`--import`). Prefer GLB
> over FBX/OBJ. Keep each car < 12k tris for web.

### Fonts (Google Fonts, all OFL — free for commercial)
- **Orbitron** — display/logo, geometric sci-fi (TOUGE title!)
- **Rajdhani** — HUD/headings, condensed technical, tabular numbers
- **Share Tech Mono** — timers/leaderboards, monospace, no jitter
- **Audiowide** — rounded retro-future accent
- Get TTFs from https://fonts.google.com, drop in `assets/fonts/`,
  load as `FontFile` in Godot. Tabular figures prevent timer jitter.

### Shaders / VFX code
- godot-psx-style-demo (dither/banding viewport shader):
  https://github.com/ka1ne/godot-psx-style-demo
- WeatherFX addon (12 animated 2D weather shaders incl. **rain**,
  works on Compatibility renderer, no particles needed):
  https://github.com/spyridon-pikoulas/godot-weather-fx-free/blob/HEAD/addons/weather_fx/README.md
- GODOT-VFX-LIBRARY (35+ particle effects, rain/sparks/dust):
  https://github.com/yuzhi9257/godot-vfx-library
- TCA Weather System (heavy — volumetric clouds etc.; probably too much
  for our web build, listed for reference):
  https://github.com/kS222138/TCA_Weather_System

### Reference material
- Ridge Racer retrospective (what made it sing):
  https://www.eurogamer.net/ridge-racer-retrospective
- Ridge Racer Type 4 aesthetics thread (Gouraud shading, draw distance):
  https://www.resetera.com/threads/ridge-racer-type-4-the-most-beautiful-and-aesthetically-pleasing-3d-game-of-the-32-64-bit-era.763343/

---

## 3. Concrete Ideas for TOUGE (prioritized)

### Quick wins (hours each, all web-safe)
1. **PS1 dither + RGB5 post shader** — fullscreen ColorRect shader, kills
   sky banding, instant authenticity. See code sketch in §1.
2. **Light trails** — reuse the skid-mark ribbon system, but vertical
   emissive ribbons at the taillights while drifting (Tron-style).
   Additive material, fade like skids.
3. **Speed lines** — CanvasLayer with ~12 thin white quads at screen
   edges, modulate alpha by `spd_ratio`. Zero 3D cost.
4. **Headlight cones** — additive cone meshes from the headlights
   (visible "volume" at dusk). One quad-cone per car, cheap.
5. **Confetti burst at finish** — one-shot CPUParticles3D, colored quads,
   gravity. Big payoff for 20 lines.
6. **Font swap** — Orbitron for TOUGE title + countdown, Rajdhani for
   HUD, Share Tech Mono for the timer. Immediate UI upgrade.
7. **Rain mode** (toggle per run) — CPUParticles streaks in front of
   camera + darker sky colors + grip 7.5→5.5 (spicier drifts) + splash
   particles at wheels. WeatherFX addon's rain shader also works.

### Medium (a day or two)
8. **Tunnel sections** — pick 2–3 straight-ish segments per seed, spawn
   ring segments + ceiling light strips over the road. Huge atmosphere
   win; needs clearance checks vs buildings.
9. **Nitro boost** — button + meter, refills by drifting; FOV warp
   (68→95), exhaust flame particles, speed-line burst.
10. **Ghost replay** — record player positions each run, spawn a
    translucent ghost car on next run. Pure data, no AI needed.
11. **Crowd at start/finish** — billboarded low-poly "people" (two
    crossed quads) waving (vertex wobble via shader time). Cheap life.
12. **Animated billboards** — cycle 2–3 Label3D texts or swap panel
    colors on a timer. Feels alive for free.
13. **Puddle reflections (fake)** — dark glossy quads on the road in
    rain mode with additive neon streaks. No real reflections needed.

### Bigger swings
14. **Second/third car bodies** — import a Kenney/IceMaan `.glb`,
    keep our arcade physics, swap mesh. Enables car select.
15. **Day / sunset / night variants** — palette-swap function for
    sky/fog/light/building-window colors per run. We have sunset;
    night + neon would be a second mood cheaply.
16. **Traffic cars** — slow AI cars to dodge (weave/overtake).
    Needs collision + simple lane AI. Fun but risky scope.
17. **Photo mode** — freeze + free orbit camera + hide UI. Tbandz
    would love this for screenshots.

### Deliberately skipped (bad fit for web/iPhone)
- Real-time shadows (too expensive on Compatibility/mobile)
- SSR / screen-space reflections (not available on web renderer)
- Volumetric fog / light shafts (Forward+ only)
- High-poly car imports (>12k tris)
- Texture-heavy workflows (we're vertex-color; keep it)

---

## 4. UI/HUD Inspiration

- **Ridge Racer Type 4**: huge position indicator, clean lap/time blocks,
  minimal chrome — arcade clarity first.
- **NFS Unbound**: condensed type + graffiti accents + big speed.
  Free equivalent: Rajdhani/Orbitron + amber/red accents (we're close).
- **OutRun**: "CHECKPOINT" banners, branching-path map, big timer —
  we could do checkpoint banners on our minimap.
- Rules that hold up: tabular/monospace figures for anything that
  counts (timer, speed, gap) so digits don't jitter; max 2–3 accent
  colors; touch buttons need 120px+ hit areas on phone.

---

*License discipline: verify the license badge on the exact asset page
before shipping. CC0 needs no credit (courtesy credit is nice).
OFL fonts are fine to embed. Never use anything marked NC (non-commercial)
or with no license stated.*
