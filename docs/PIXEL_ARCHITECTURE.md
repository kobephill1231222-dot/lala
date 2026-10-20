# JJK Farm: pixel-art client

The game plays exactly as before (Crates -> Sorcerers -> Cursed Orbs -> Orb Box -> Collect ->
Sell -> reinvest). Only the presentation changed: **everything a player sees is 2D pixel art
drawn with UI Frames** (no Parts, models, BillboardGuis, ViewportFrames or uploaded images).

## How it fits together

- **Server (unchanged rules).** `Shared/Rules`, DataService, StateService and GameService are
  untouched. Range checks still measure from the player's (now invisible) R6 character.
  `Server/Map/MapBuilder` builds only an invisible physics world from `Shared/Config/WorldMap`:
  floor, walls where something is solid, touch pads (Collect Pads, Sell Pad), the spawn and one
  Model per farm. `FarmService` publishes what each farm holds as data:
  - `Workspace.JJKFarmMap.Farms.Farm<i>` attributes: OwnerId, OwnerName, Ops, CashRate, BoxOrbs,
    BoxValue, BoxT, BoxCap, UnlockedSlots, UnlockedPads
  - `Farm<i>.Runtime.Sorcerers.Sorcerer<slot>` (Folder): Uid, SorcererId, Level, Slot, Farm,
    Ops, OrbValue
  - `Farm<i>.Runtime.Crates.Crate<pad>` (Folder): Cid, Tier, Pad, Farm, ReadyAt
  - `Player` attributes: CarriedOrbs, CarriedValue (plus Cash, Income as before)
- **World layout.** `Shared/Config/FarmLayout` (studs, grid of 4-stud tiles) and
  `Shared/Config/WorldMap` (every static thing, in world studs). Farms 1-3 are the north row,
  4-6 the south row; the plaza band runs between them (Crate Shop west, Sell Stand centre,
  Upgrade Shop east). Screen-up is world -Z. `WorldMap.toPixels(x, z)` gives art pixels with
  the world's top-left at (0, 0); `FarmLayout.PixelsPerStud = 4`.
- **Movement.** The default Roblox controls move the invisible character. The 3D camera is
  Scriptable, straight down, north-up, above the character (only so the controls are
  camera-relative); nothing 3D is ever visible because the pixel world covers the screen.

## Pixel rules (every module)

- Integer scale `S` = screen pixels per art pixel, from the screen height
  (`max(1, floor(H / 200 + 0.5))`). Everything is positioned with `UDim2.fromOffset` at whole
  multiples of `S`. No `UDim2` scale sizes inside the pixel world, no UICorner, UIStroke,
  UIGradient, Rotation, non-integer UIScale, TextScaled or CanvasGroup.
- Text: `Font.fromEnum(Enum.Font.Arcade)` (Press Start 2P) at TextSize 8 x S (or 16 x S),
  integer positions, with a `UITextSizeConstraint` (Min = Max). Shadows are an offset copy.
- Colours come from `Shared/Pixel/Palette` (ENDESGA 32). Config colours (Sorcerer looks,
  rarities, crate tiers) are snapped with `Palette.nearest`.
- Sprites are text grids (`Shared/Pixel/Sprite.define`); procedural art draws into a
  `Shared/Pixel/Canvas` (rectangles in art pixels). Both become merged Frames.
- Budgets: about 40 rectangles or fewer per sprite frame; animation by switching prebuilt
  frames (`Sprite.frames` / `Sprite.show`), never by recreating Frames every frame.

## Art modules (`src/shared/Pixel/Art/`)

All pure (no Instances, no randomness: use a hash of coordinates for variation), testable in Lune.

### `Characters.luau`
- `Characters.Size = { w = 16, h = 20 }`; character anchors are `{ 8, 20 }` (feet, bottom middle).
- `Characters.sorcerer(id): { idle: Def, attack: Def, color: Color3 }`: drawn from the look in
  `Shared/Config/Sorcerers` (hair style, colours, accessories, hair streak), never hard-coded per
  id. `idle` has 2 frames (breathing bob); `attack` has 3 frames (wind-up, strike, follow-through)
  matching the Sorcerer's `style` (Punch, Cast, Slash, Shoot). Faces RIGHT (the renderer
  mirrors for left). Unknown ids get a generic Sorcerer. `color` is the technique colour (snapped).
- `Characters.companion(name): Def?` for Toad, Moth, Mask, Wolf, Serpent (2 idle frames, at most
  14x14, anchor bottom middle).
- `Characters.portrait(id): Def`: 24x24 head and shoulders facing front, 1 frame (UI cards, lists).
- `Characters.player(colors: { skin, shirt, pants, hair }): { down: Def, up: Def, side: Def }`:
  3 frames each (stand, walk A, walk B); `side` faces right.
- `Characters.carry: Def`: the Orb Box a player carries above their head (about 12x10, 2 frames
  glow), anchor bottom middle.

### `World.luau`
Procedural, drawing into Canvases at art-pixel rectangles from `WorldMap` (footprints converted
with `WorldMap.toPixels`):
- `World.ground(canvas, kind, x, y, w, h)` for `grass`, `plaza`, `road`, `farmFloor`.
- `World.object(low, high, object, x, y, w, h)`: a `WorldMap` object whose footprint is the art
  rectangle `(x, y, w, h)`. `low` is drawn under characters, `high` over them (tree canopies,
  roofs, the tops of lanterns and pillars). Kinds: `fence` (variant `h` / `v`), `orbBox`,
  `lantern`, `sellStand`, `pillar`, `crateShop`, `display` (variant = crate tier; the pedestal
  only), `upgradeShop`, `upgradeBoard`, `bench`, `tree` (variant `pine` / `sakura` / `maple`).
- `World.orbBoxInterior(x, y, w, h): (x, y, w, h)`: where the renderer draws the box's fill.
- `World.lane(canvas, x, y, w, h)`: the lane's bed and rails (static).
  `World.laneSlats(canvas, w, h)`: one repeat of the moving slats, `World.SlatSpacing` pixels
  tall; the renderer scrolls it.
- `World.slot(canvas, x, y, size, state)` with state `locked` / `open`;
  `World.pad(canvas, x, y, size, state)`; `World.collectPad(canvas, x, y, w, h)`;
  `World.sign(canvas, x, y, w, h)` (the farm name board; the renderer adds the text).

### `Crates.luau`
- `Crates.sprite(tier): Def`: 16x16, frames 1 closed, 2 shake left, 3 shake right, 4 open (glow).
- `Crates.lid(tier): Def`: the lid that flies off when opened.
- `Crates.icon(tier): Def`: about 10x10 for lists and buttons.
- Tiers: starter, basic, rare, epic, legendary (colours from `Shared/Config/Crates` / the old
  CrateModels look, snapped).

### `Icons.luau`
- `Icons.get(name): Def`, about 10x10: `cash`, `orb`, `lock`, `star`, `sorcerers`, `crates`,
  `crateShop`, `upgradeShop`, `home`, `settings`, `close`, `arrow`, one per upgrade id
  (`orbValue`, `slots`, `boxSize`, `openSpeed`, `pads`, `luck`, `walkSpeed`) and one gem per
  rarity (`rarity_Common` ... `rarity_Legendary`).

### `Fx.luau`
- `Fx.orb(color): Def` (6x6, 2 frames), `Fx.spark: Def` (3 frames), `Fx.coin: Def` (4-frame spin),
  `Fx.slash(color): Def` (3 frames), `Fx.bolt(color): Def`, `Fx.ring(canvas, cx, cy, r, color)`
  (a one-pixel circle outline), `Fx.pillar(canvas, cx, bottom, w, h, color)`.

## Client (`src/client`)

- `Pixel/Screen`: the full-screen world ScreenGui (`JJKWorld`, DisplayOrder below the HUD,
  ScreenInsets None), the integer scale S and its change signal, and the layers inside the
  scrolling world frame: Ground (static chunks) < Floor (slots, pads, lane) < Actors (y-sorted)
  < High (canopies, roofs) < Overlay (effects, labels, prompts).
- `Pixel/Camera2D`: follows your character; world studs <-> art pixels <-> screen pixels.
- `Controllers/WorldView`: static world, farms, Sorcerers, Crates, players and carried boxes.
- The old controllers keep their names and public APIs (StateController, UIController,
  EffectsController, ProductionController, WorldController, RevealController,
  PlacementController, TutorialController, NotificationController, SoundController,
  CameraController); their 3D drawing is replaced by pixel drawing through Screen/Camera2D.
  ProximityPrompts become pixel prompts (nearest action in range, E / R / tap / gamepad).
