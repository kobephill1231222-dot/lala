# Studio playtest checklist

The offline playtests cover the game logic. These checks need the real engine. Use
**Test > Start** with 2 players for the multiplayer items, and the device emulator for mobile.

## First join
- [ ] Loading overlay disappears and the flyover plays once (click to skip).
- [ ] You spawn on the plaza **facing the spirit tree**; the torii approach frames it.
- [ ] Tutorial card shows Step 1 with a glowing beam to your Spirit Well.
- [ ] Your sanctuary sign shows your name; Tomo bobs on spot 1 with a beam into the well.

## Core loop
- [ ] Walking into the well collects (burst, "+60" popup, energy counter counts up).
- [ ] Summon panel shows "Travel there" when away; travelling opens the panel at the courtyard.
- [ ] Lantern Ritual x1: the reveal plays and the first result is Rare; the circle flares.
- [ ] "Place now" goes home if needed and enters placement: glowing spots, ghost preview,
      click (or tap + Confirm) places it with a light pillar.
- [ ] Talisman Shop counter prompt opens Upgrades; buying Focus Training raises the HUD rate.
- [ ] A sealed spot's prompt ("Break Seal") unlocks it once affordable.
- [ ] Allies panel: Train, Remove, Release (needs a confirm) and the Index tab all work.

## Combat
- [ ] Entering the forest shows the ability bar and a toast; leaving hides it.
- [ ] Curses wander, chase, flash red before striking, and damage you.
- [ ] Strike/Lance/Burst show effects and damage numbers; kills give energy (sometimes seals).
- [ ] The tutorial completes on your first kill (+3 seals).
- [ ] Dojo dummies wobble and show numbers when hit.
- [ ] Dying respawns you at your sanctuary entrance.

## Multiplayer and persistence (published place, API access on)
- [ ] Two players get different sanctuaries; each sees only their own prompts.
- [ ] Rejoin: units, upgrades, spots and tutorial state persist; the offline-earnings toast shows.
- [ ] Leaving resets that sanctuary to "Vacant Sanctuary".

## Look and performance
- [ ] Dusk lighting is readable everywhere (paths, forest fights, UI over bright neon).
- [ ] Ritual circle rings, tree shards and well crystals animate smoothly.
- [ ] Phone emulator (e.g. iPhone 14 landscape): HUD buttons are thumb-sized, panels fit,
      placement Confirm works, ability buttons don't overlap the jump button.
- [ ] Frame rate is acceptable on a low-end device setting (Graphics quality 1-3).
