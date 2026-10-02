# JJK Farm: replacement plan for review

Status: **proposal, not built.** Nothing below has been implemented yet. It covers the two
things that need decisions before the next rebuild:

1. Replacing the orb conveyor (rejected), per the October 2 audit.
2. Using **Marketplace / Toolbox assets** for characters and props instead of part-built
   models (requested after the audit).

## 1. Assets: what will come from the Marketplace and Toolbox

| Need | Source | How it gets into the game |
|---|---|---|
| Sorcerer bodies, hair, faces, clothing, accessories | Marketplace avatar items (catalog asset IDs) | `HumanoidDescription` per Sorcerer, built into real R15 rigs with `Players:CreateHumanoidModelFromDescription` on the server at startup. Avatar items load in any experience; nothing has to be owned or uploaded. Templates go in ReplicatedStorage so the client can clone them for the reveal card and placement previews. |
| Idle / walk / emote animation | Roblox-owned animations (default R15 set, Roblox animation packs and emotes) | Played on the rig's Animator. Roblox-owned animations play in any experience. |
| Technique attack animations (anticipation -> contact -> recovery) | Either a Roblox-owned animation that fits, or **your own published animation** | Animations by other creators can't be played in your game. Two options: (a) I author each attack as a `KeyframeSequence` stored in the place; you publish it from the Animation Editor in one click and the game uses your ID. (b) I drive the rig's Motor6D joints from code, which needs no upload. Both are real articulated limb motion, not whole-model sliding. |
| Map props (buildings, torii, lanterns, trees, training dummies, rocks) | Toolbox models (Creator Store) | Free models from other creators **can't be loaded at runtime** (`InsertService` only loads assets owned by you or Roblox), so they're inserted at edit time and saved into the place. I'll ship an asset manifest (ID, name, creator, where it goes, scale) and a Studio command-bar or plugin script that inserts each one at its anchor with `game:GetObjects`. You run it once in Studio and save. If you connect Claude to your Studio (Claude Desktop + Roblox Studio MCP), this can be done directly in your open place instead. |
| Sounds and music | Creator Store audio | Audio IDs in `SoundConfig` (public Roblox-licensed audio). |

**Why there are no IDs in this commit:** this cloud session's network policy blocks every
Roblox domain (catalog, Toolbox API, asset delivery, thumbnails). I won't put unverified
asset IDs in the game. A wrong ID silently loads nothing or the wrong item. Two ways
forward:

- **Allow the domains** (environment settings > Network access > Custom > Allowed domains):
  `catalog.roblox.com`, `apis.roblox.com`, `economy.roblox.com`, `thumbnails.roblox.com`,
  `assetdelivery.roblox.com`, `www.roblox.com`, `create.roblox.com`. I'll then search the
  catalog and Toolbox, check every ID (type, name, creator, that it's free and on sale),
  render thumbnails so you can approve the picks, and record them in the manifest.
- **Or send me IDs** you've picked in Studio's Toolbox or the Avatar Shop. I'll wire them in.
  They'll be verified for real the first time you press Play.

**Toolbox vetting rule:** every Toolbox model goes through a script scan before use. Models
containing Scripts or LocalScripts are rejected or stripped, because free models are a
common source of backdoors. Part and triangle counts are recorded against a performance
budget.

## 2. Replacing the orb conveyor

This direction is proposed for review. It is not a confirmed Blue Lock Farm mechanic.

**Core beat:** each production slot becomes a small **training post**. A Sorcerer stands
facing a **target** (a cursed-spirit training dummy). On a fixed beat, it performs its
technique: wind-up, strike, the target recoils and flashes, a hit effect fires, and the
payout pops from the target at that moment.

**One authoritative schedule** (fixes audit bug 5). Each placed Sorcerer has a hit interval
and a value per hit. The server derives credited hits from elapsed time as
`floor((now - placedAt) / interval)` and credits them in whole hits. The client plays a hit
on exactly the same timestamps, from the replicated `placedAt` and interval. Visible hits and
credited hits are then the same events, never a separate random visual cadence. When a
Sorcerer is fast enough that drawing every hit is too much, the client shows a combo
("x3") and the popup states the combined value.

**Decision A: where rewards go.**

| Option | Loop | Pros | Cons |
|---|---|---|---|
| **A1. Collect at the farm** | Hits fill your farm's reward chest. Walk to it (or stand on its pad) to bank the Cash. | Rewards stay with the characters that earned them. No dead walking time. Simple on mobile. | Less reason to visit the plaza (only to shop). |
| **A2. Selling trip** | Hits fill a container you carry to the plaza Sell Stand (today's loop, without orbs). | Closer to the "sell full crates" loop that fan guides describe for the reference game. Brings players together in the plaza. | Repetitive walk every few minutes. The audit flags it as weaker. |

My recommendation is **A1**, but this is your call.

**Decision B: active and offline targets.** The audit is right that a 60-orb box makes the
8-hour offline cap meaningless. Proposal: measure storage in **minutes of current income**,
not item count, so it scales with progress.

- Active play: storage fills in about **5 minutes** at first, so you check in often while
  playing.
- Offline: a separate **offline vault** banks up to **2 hours** of income at start, with an
  upgrade path to **8 hours**. Still paid once per absence, using the same lease-protected
  timestamp as today.
- The Box Size upgrade becomes "Storage" (+minutes). Offline time becomes its own upgrade.

**Decision C: prototype scope** (the audit's "prove one first"). One farm, one rigged
Marketplace-item Sorcerer, one target, one technique with authored anticipation, contact
and recovery, one payout with sound. Built as its own small place, `dist/Prototype.rbxl`,
for you to review in Studio. Nothing gets duplicated six times or wired into the full
economy until you approve the look and feel.

## 3. Map direction (after the prototype)

One compact anime training courtyard instead of six repeated farms on open grass:

- A clear front-to-back view of your characters.
- Restrained materials: no sand textures on clothing or floors, neon only where something
  is interactive.
- Designed background (Toolbox buildings and trees), not giant rounded rocks.

I'll judge it from player-height screenshots in Studio, not overhead renders.

## Open questions for you

1. **Network:** will you allow the Roblox domains above, or send asset IDs yourself?
2. **Decision A:** collect at the farm (A1) or a selling trip (A2)?
3. **Decision B:** are about 5 minutes of active storage and 2 to 8 hours offline the right
   targets?
4. **Animations:** publish authored animations under your account (best quality), or
   code-driven joint animation (no upload, somewhat less polished)?
5. **Look:** any specific Marketplace items, Toolbox kits or reference images for the
   Sorcerers and the courtyard?
