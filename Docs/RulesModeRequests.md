# Rules mode request tracker — November 18, evening

All changes are Rules-only unless explicitly stated. Preserve normal Phone Play's sandbox, gestures, saves and shared appearance. Read the live `/private/tmp/MagicBoard-Rules-coordination.md` for current claims; claim a task there before editing shared files. A checked item requires an implementation commit and relevant verification, not just a plan.

## Playability and interaction (highest priority)

- [ ] **R01 — Off-board card choices.** Pothole Mole offered a land from the graveyard but no browser/candidates appeared; Soul-Shackled Zombie likewise could not choose cards in either graveyard. Resolve legal engine UUIDs against this seat's visible zones, open the fanned browser, preserve eligibility and support both graveyards. Bridge resolution passes real Pothole, Zombie/both-graveyards and Brainstorm probes; all425 captured events decode with Swift models. Confirmation UX remains R02. Pothole screenshot: `Docs/References/RulesReportedIssues/pothole-graveyard-choice.png`.
- [x] **R02 — Confirmed card selection.** Brainstorm's return-from-hand choice needs a large fanned hand. Taps toggle a local selection on/off; only Confirm submits it. General card selectors should use this model rather than submitting each tap. The fanned browser now toggles local draft selection and enables Confirm; each callback submits one card, so Brainstorm returns its two cards in two engine-required confirmed steps. Scry/surveil retain their reversible ordering flow (R13). Respect exact/up-to counts and engine-required sequential prompts; do not partially commit before confirmation. Preserve hidden information and provide selection feedback.
- [x] **R03 — Rules stack is authoritative.** Disable manually drawing/changing targeting lines from every spell or ability on the stack, including opponents' objects. Retain read-only inspection and engine-reported arrows. Keep editable targeting in normal Phone Play.
- [x] **R04 — Immediate blocker drops.** Dropping a blocker onto an attacker assigns it without a hover delay or waiting for a hover prompt. The asynchronous engine blocker→attacker exchange may continue after release; preserve the chosen attacker until its legal follow-up prompt.
- [ ] **R05 — Exit cancels pending presentation.** A previously missing browser appeared just before Exit Game completed. Cancel stale projections, queued browser presentations, answers and animation tasks on exit; no delayed overlay or state resurrection. Projection tasks are now tracked and cancelled; adapter rejects any projection after leaving, verified by a stale-task regression.
- [x] **R06 — Mulligan controls.** Remove the inert generic Choose button from the opening-hand/mulligan screen. Keep meaningful Keep/Mulligan/Return controls.
- [ ] **R07 — Choice cleanup.** Remove an in-list Cancel when the chooser also has a bottom Cancel button; preserve cancellation semantics. Automatically accept a single available spell/ability option (e.g. Cast Lluwen), avoiding a pointless chooser.

## Readable game flow and stable layout

- [ ] **R08 — AI action presentation.** A removal spell, its targets, resolution, the creature's death, turn change and draw currently flash past. Pace the actual ordered presentation, including when no response is legal and full control is off. Show hand→stack, targeting lines, resolution and battlefield→graveyard animations before advancing. A 700ms local auto-pass timer alone is insufficient; engine state remains authoritative and interactive prompts must correspond to the displayed state.
- [x] **R09 — Stable battlefield.** Prompt appearance/disappearance must never resize or move permanents. Reserve a consistent gap independently of the current prompt and/or compact the instruction. Card sizing may change for changes in battlefield contents. This supersedes the earlier measured-per-prompt gap implementation.
- [x] **R10 — Next phase.** On your turn the Next button must show the upcoming phase/step, not just a generic Next.
- [ ] **R11 — Phase markers.** Put markers next to each player's life total; light only the active player's markers.
- [ ] **R12 — Combat styling.** Arena-yellow blocker connections; blocked attackers' chevrons become yellow. Existing references: `/private/tmp/MagicBoard-Rules-refs/1.png`–`4.png`.
- [ ] **R13 — Scry/surveil.** Match Josh's Arena fanned-card arrangement reference (first scry screenshot in the reference folder above), retaining drag ordering and destination choices.

## Player progress and permanent designations

- [ ] **R14 — Player progress markers.** Show speed on the board (Avishkar Raceway currently exposes it only in inspection), plus dungeons, emblems and Ring progress. Include compact persistent markers and inspectable full-size progress cards. Read the existing UI in `~/Xcode/Spellbook` for dungeons and the Ring; reuse it where practical. Arena's speed reference has a small numeric marker near the opponent's left edge: `Docs/References/RulesReportedIssues/arena-speed-marker.png` (opponent speed 1). Values come from XMage, with seat visibility respected.
- [ ] **R15 — Permanent designations.** Show prepared status using the existing fake-counter convention, ring-bearer status, summoning sickness and other engine-provided designations. Summoning sickness now has a visible white spiral on creature art and accessible status; it follows the engine flag and clears when that flag clears. Focused UI and normal sandbox card/drag verification pass. Prepared/ring-bearer/other designations remain open. These are visual status indicators, not editable counters in Rules mode.
- [ ] **R16 — Self-reference text.** Prefer Scryfall oracle text for tokens while retaining actual engine effects. Apply Josh's terminology to all ability text: permanents use this creature/enchantment/artifact/land; instants/sorceries use their names; off-battlefield uses this card; legendary short names stop at comma/epithet; Aura/Equipment/Saga/Vehicle/Class/Spacecraft/Room/Case/Attraction/Siege use their subtype; tokens always use this token, including created-token abilities. Avoid doubled phrases such as When this Environmental Scientist enters.

## Packet selection and compatibility

- [x] **R17 — Packet names.** No duplicate packet names within an offer or between first- and second-round offers. Deduplicate by display name, not variant ID. Done: `RulesPackets.offers` dedupes by display name within an offer and against the first round (unit test `testPacketOffersNeverRepeatADisplayName`).
- [ ] **R18 — Packet fallback faces.** When no front card exists, the custom name/colors face also shows the originating set's symbol.
- [ ] **R19 — Unsupported packets.** Show a clear bridge-validation error and allow retry for unsupported newer cards (known 13 Marvel +2 SOS packets), without substituting cards silently.

## Existing integration work and limits

- [ ] **R20 — Integrate and deliver pending Codex work.** Pacing/visible-hand test fixes are committed on `rules-mode-codex` and merged with Claude's frame work through e1e7d54; main later advanced. Ability-source color correction passes a real Ahriman probe but is not yet committed/deployed. Dedicated Capital City UI test did not progress and needs diagnosis; avoid blind retries. Recheck current git status and coordination before integration.
- [ ] **R21 — Payment context.** Exact original modified mana cost needs authoritative engine data; don't invent it from the first remaining-cost callback or infer legality from source appearance. Capital City bridge filtering works; original physical Capital/Insomnia interaction remains unverified.

- [ ] **R22 — Combat damage animations.** When creatures deal combat damage, animate a short lunge into their assigned blockers or toward the defending player’s life total, like Arena. Derive timing and recipients from engine combat/damage events; respect first/double strike, multiple blockers, trample and simultaneous damage. Keep permanents in stable resting positions, preserve inspection and avoid replaying attacks on reconnect. Coordinate with R08 presentation sequencing.

Ward warning is still an unapproved idea. Keep ub-nyx frames prepared but excluded from shipping resources. On-device Java/AOT remains deferred.

- [x] **R23 — Public Caddy endpoint.** Josh authorized checking/fixing `xmage.compc.cc`. Corrected only `C:\Caddy\services\public\xmage.caddy` from `localhost:17184` to the existing bridge listener `100.96.101.108:17180`; backed up, validated and reloaded Caddy. Verified public TLS/WSS, authenticated XMage login/table discovery and rejection of a bad key. XMage/bridge not restarted. Existing key and `wss://xmage.compc.cc` work; other service snippets unchanged.

- [x] **R24 — Secure endpoint port.** App appended17180 to `wss://xmage.compc.cc`, bypassing Caddy. Preserve implicit HTTPS443 for wss; retain17180 for direct ws and preserve explicit ports/paths. Current-build workaround: `wss://xmage.compc.cc:443`. Regression passes in the46-test Rules suite; the exact app parser and native URLSession also pass public WSS login/table discovery with implicit443.

- [x] **R25 — Connected lobby flicker.** The Rules Game page flashes a progress row after connection. Found the3-second `listTables` polling sharing the generic game-action Working row and disabling controls. Discovery now has an independent request ID and timeout; it neither disables game controls nor clears a game action when its ACK arrives. All47 Rules units pass, including an actual delayed-ACK/concurrent-action regression (`/private/tmp/rules-independent-lobby-discovery-unit.log`). Actual connection/game-start progress remains visible.
