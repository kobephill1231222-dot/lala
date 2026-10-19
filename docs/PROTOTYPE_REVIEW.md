# Training-post prototype: Studio review

`dist/Prototype.rbxl` is the proposal's Decision C: one farm, one Sorcerer, one target, one
technique, one payout. It was built and tested offline with no Studio connection, so none of
this has been checked in Studio yet. Open the place and press **Play**.

## What to judge (look and feel)

- [ ] **The beat reads.** Kai's coil back, the step in and the palm landing on the target feel
      like one strike, with a clear wind-up, a snap into contact and a follow-through. Not
      floaty, not too fast to see.
- [ ] **Contact sells the hit.** At the moment the palm lands, the dummy rocks back and
      flashes, sparks and a ring burst from the target, and you hear the impact. The **+$4**
      pops at the same moment.
- [ ] **The payout connects to the chest.** A coin arcs from the dummy into the Reward Chest,
      and the chest's number goes up as it lands.
- [ ] **R6, and limbs not sliding.** Kai is an R6 rig: arms, head and legs swing from the
      torso. The soles stay on the ground while he lunges, the front foot steps in, and the
      feet never cross.
- [ ] **Idle and rest.** Between strikes Kai holds a fighting stance and breathes. When the
      chest is full he relaxes, arms down, head lowered.
- [ ] **Readable from the top-down camera.** From above you can see Kai's arm drive into the
      dummy, the dummy rock back and the coin fly to the chest. Zoom in (mouse wheel, I, or
      pinch) to see the strike closer. Walk into the dojo and its roof fades.

## What to check (behaviour)

- [ ] The HUD's top left says **TRAINING POST**, Kai · Spark Palm, 1 hit / 2.0s, $4 per hit,
      $2/s, and that the chest holds 5:00 of income.
- [ ] **E** at the chest says **Collect · Reward Chest**. Collecting adds the chest's amount to
      the Cash at the top, the lid throws open with gold, and a **Banked $X** toast appears.
- [ ] Standing on the gold **COLLECT** pad also collects, without a toast when it's empty.
- [ ] Collecting from far away says *Walk up to the Reward Chest to collect.*
- [ ] **G** at the review board (**Fill chest**): the label says **FULL · COLLECT!**, the bar
      turns red-orange, Kai rests (a strike that already landed finishes, a wind-up whose hit
      won't be paid eases off), and the hint says he is resting. Collect pays **$600** and he starts again on the next beat.
- [ ] **F** at the review board (**Fast Sorcerer**): strikes come every 1.2 s and the popup says
      **x3 +$3**. The HUD says *x3 combos*. Press **F** again to go back to normal.
- [ ] In **Test > Start** with 2 players: the second player sees the same strikes at the same
      moments, can't collect (*This isn't your chest.*) and can't use the switches.
- [ ] Leave as the first player: the second player gets the post and Kai starts over.

## Things only Studio can tell us

- Whether posing the Motor6Ds from a LocalScript every frame looks smooth on the anchored rig
  (it's the standard approach, but it hasn't been seen running).
- Sound levels. The sounds are client-bundled placeholders until there are Creator Store
  IDs.
- How the Highlight flash and spark particles look against the courtyard.
- Frame time with the effects on a phone.

## Decisions to confirm

The prototype assumed these while the proposal's questions were open. Each is one setting:

| Decision | Assumed | Where to change it |
|---|---|---|
| A: where rewards go | A1, collect at the farm | (layout) `src/prototype/server/Courtyard.luau` |
| B: chest storage | 5 minutes of income | `ChestStorageSeconds` in `src/prototype/shared/PrototypeConfig.luau` |
| B: offline vault | 2 hours, upgradable to 8 | `OfflineVaultSeconds`, `OfflineVaultMaxSeconds` (same file) |
| Hit rate and value | 1 hit / 2 s, $4 per hit (Kai's $2/s) | `Presets.Normal` (same file) |
| Animation | code-driven R6 joints, no uploads | key poses in `src/prototype/shared/Techniques.luau` |
| Rig and avatars | R6 (Sorcerer rig and players) | `src/prototype/shared/Rig.luau`, `GameSettingsAvatar` in the project files |
| Camera | top-down, 80° pitch, fixed north-up | constants at the top of `src/shared/Visuals/TopDownCamera.luau` |
| Strike timing | 0.42 s wind-up, 0.62 s recovery | `Techniques.SparkPalm` keys |

Once the look and feel is approved, the plan is to move this schedule and rig into the full
game, one technique style at a time, and retire the orb lane.
