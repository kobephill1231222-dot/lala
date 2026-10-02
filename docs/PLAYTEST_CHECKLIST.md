# JJK Farm: Studio playtest checklist

None of these were run in Roblox Studio while building the game (there was no Studio
connection). They cover what the offline tests can't: physics, rendering, input and feel.
Open `dist/JJKFarm.rbxl` and press **Play** (or **Start** with 2 players under the Test tab
for the multiplayer items).

## First minute

- [ ] You spawn at Your Farm, facing the Orb Box. The gate sign reads **Your Farm**.
- [ ] The tutorial card says *Place your Starter Crate* and a beam points at a Crate Pad.
- [ ] At the pad, **E** shows **Place - Starter Crate**. The crate drops onto the pad with a
      dust ring and shows **Opening Time 0:10** above it.
- [ ] After 10 s the label says **READY! Open** and you hear a chime. **E** shows **Open**.
- [ ] Opening: the crate shakes harder, glows, the lid flies off, a pillar of light rises and
      a ghost of the Sorcerer floats up. Then the card shows **Kai**, Common, Spark Palm,
      Orb Value $2, Orbs per Second 1.
- [ ] **Place** on the card: glowing rings appear on free slots, slot 1 is preselected with a
      translucent Kai. Clicking a ring (or **Place**) puts him there with a violet pillar.

## Production

- [ ] Kai punches forward about once a second, a shockwave ring pops, and an orange orb
      arcs over the chute into the lane.
- [ ] Lane slats move toward the Orb Box. Orbs ride the lane and hop into the box with a
      sparkle.
- [ ] The violet pile inside the box (visible through the glass front) rises. The box label
      and the HUD both count up toward 60. At 60 the pile turns gold, the label says FULL,
      and Kai stops producing.
- [ ] Other Sorcerers: Slash ones spin with a blade arc, Cast ones rise with a ground ring,
      Shoot ones recoil with a bolt. Companions (toad, wolf, moth, mask, serpent) appear.

## Collect and sell

- [ ] Stepping on the Collect Pad (or **E: Collect**) bursts orbs toward you. A glowing box
      appears in front of your character with "N Cursed Orbs".
- [ ] The carried box doesn't push or slow your character. Jumping and running look normal.
- [ ] A faint beam points to the Sell Stand. Stepping on the gold pad sells: coins fountain,
      "+$X" floats up, the Cash counter jumps, the carried box disappears.
- [ ] The tutorial continues: Buy a Basic Crate at the Crate Shop (walk up to the display and
      press **E: Buy**), then Upgrade Orb Value at the Upgrade Shop.

## Menus and placement

- [ ] **G** Sorcerers: the grid shows each Sorcerer with level, $/s and slot. Place, Pick Up,
      Upgrade and Sell all work. You can't sell your last Sorcerer.
- [ ] **C** Crates: pads show timers and Open/Pick Up, inventory crates show Place.
- [ ] **B** and **U** open the shops anywhere. Buying only works at the shop (buttons say
      "Buy at the shop" elsewhere). "Walk me there" shows a beam.
- [ ] Picking up a crate mid-timer and placing it again continues from the time left.
- [ ] Locked slots and pads show a sealed tablet. Their prompt says **Upgrade - More Slots /
      More Crate Pads** and opens the Upgrade Shop.
- [ ] Touch (Device emulator, phone): HUD and panels fit, prompts can be tapped, placement
      works with tap then **Place**.

## Persistence (needs API Services enabled on a published place)

- [ ] Leave and rejoin: Sorcerers, slots, upgrades, Cash, crates (with timers) and the Orb Box
      come back.
- [ ] Leave with a crate opening for longer than its Opening Time: on return it's READY.
- [ ] Leave for a few minutes with Sorcerers working: the welcome-back toast reports the
      orbs made, and the box holds them (up to its capacity).
- [ ] Rejoin immediately after that: no second welcome-back payout.

## Multiplayer (Test > Start with 2 players)

- [ ] Each player gets their own farm and sign. Other players' farms show their name.
- [ ] You can see other players' Sorcerers working, their orbs, their carried boxes and their
      crate reveals.
- [ ] You can't open, place or collect on someone else's farm (the server refuses it).

## Look and performance

- [ ] Lighting is bright and clear. Neon orbs and pads glow without blowing out.
- [ ] Gates, shops, crates and Sorcerers feel right next to your avatar.
- [ ] Frame rate stays smooth on a mid-range device with six full farms (Microprofiler if
      not).
