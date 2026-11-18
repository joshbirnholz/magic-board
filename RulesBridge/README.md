# Magic Board Rules bridge (development)

Rules mode uses the **same Phone Play interface** as Host/Join. XMage controls its state and choices. Normal Phone Play retains its sandbox behavior and nearby transport. The bridge connects as an ordinary XMage client; no XMage source modifications are required.

## Verified so far

- Headless login to a stock XMage server on macOS with Java 17.
- Windows home host verified over Tailscale, including a full simulator AI game, two-seat privacy/combat checks and session recovery. Only the Rules server/bridge services in the approved host folder should be changed.
- A complete game against AI through the bridge: land play, creature casting, mana, priority and game-over.
- Per-player snapshots, duplicate command receipts, and reconnect restoring the same pending prompt.
- Two-human table creation/discovery/joining, distinct engine seats, and private opening hands.
- Two human seats playing creatures, declaring attackers and assigning a legal blocker through real engine prompts.
- A full game against AI completed through the shared Phone Play interface in the iOS simulator, using the corrected creature deck.
- Existing Phone Play: 68 unit tests and the sandbox drag/tap UI check passed. All 93 unit tests pass (68 normal Phone Play + 25 Rules), including automatic mana and combat-defender decoding regressions.
- Stack objects carry their controller (inferred by the bridge: an ability's source controller, otherwise the player who held priority), checked in the real AI game.
- The initial AI deck is deliberately simple; this is not yet an all-card client.
- Native priority controls checked against a real game: hold/release, stale-command rejection, passing to the next main phase, end step and our next turn, stopping and clearing each skip flag, and cancelling auto-pass. Resolve-stack also passed with a real creature spell on the stack, returning to priority with an empty stack and cleared skip flag.
- Real-card prompt probes passed: manually ordering Soul Warden triggers; choosing a Blessed Alliance mode and putting it on the stack; casting Reverent Mantra using its white-card exile cost; casting Gathan Raiders face down and turning it face up by paying the discard cost.
- Repeated disconnected-client relaunches reclaim an old detached seat while preserving connected players and newer resumable seats.
- Repeated simultaneous leave/socket-abort races preserve other clients, allow new clients and permit graceful bridge shutdown.

## Pinned dependencies

Use release `xmage_1.4.63V2`, archive `mage-full_1.4.63-dev_2026-11-17_18-06.zip`, from [XMage releases](https://github.com/magefree/mage/releases/tag/xmage_1.4.63V2).

Archive SHA-256: `b6f5d182aafd40e531e05647a15245456ff9e7e3d5ef684cd946af397150f191`.

The bridge uses Java-WebSocket 1.6.0 (MIT); XMage is MIT licensed. The build scripts download the WebSocket jar and use the matching libraries from the extracted XMage client. Maven is not required. Java 17+ is required for **this bridge**, although XMage's own bytecode targets Java 8.

## Windows

For a prebuilt bridge bundle, follow [PC-SETUP.md](PC-SETUP.md). It contains the compiled bridge, dependency notice, launchers and source; Java 17 and the pinned XMage installation are still required. Generate a bundle on macOS with `XMAGE_HOME=/path/to/xmage sh package.sh`; output is `build/MagicBoard-RulesBridge.zip` and its SHA-256 file.

Install a Java 17 JDK (including `javac`) and unpack the pinned XMage release. Run these commands in PowerShell, changing the path and key:

```powershell
$env:XMAGE_HOME = 'D:\games\xmage'
$env:RULES_BRIDGE_TOKEN = 'replace-with-a-private-random-key-of-at-least-16-characters'
$env:RULES_BRIDGE_BIND = '0.0.0.0'
```

From this repository's `RulesBridge` directory, start the stock XMage server:

```powershell
./start-server.ps1
```

This uses a 1 GB heap (`./start-server.ps1 -HeapMB 2048` changes it), the server's own working directory and the Java remoting module-access flag required on Java 17. In another terminal, set the same environment variables, return to `RulesBridge`, and run:

```powershell
./build.ps1
./run.ps1
```

The server should have anonymous authentication enabled (the pinned release's default). The bridge currently creates a generated XMage username per phone. Registered-account login is not implemented.

Allow the bridge's TCP port **17180** through Windows Firewall on your private network. Keep XMage's Java remoting port **17171** local to the PC. In Magic Board, choose **Connect to Rules Game**, enter `ws://YOUR-PC-ADDRESS:17180` and the matching connection key, then select **Play Against AI**. For two phones, one chooses **Create Two-Player Game**; the other selects that game from **Waiting Games**. The creator then selects **Start Game**. Import your own deck or use the built-in white creature deck; the AI uses a copy of your selected deck. Use a LAN or Tailscale address; do not expose the development bridge publicly. `ws://` does not encrypt the connection itself; Tailscale encrypts its private network traffic. `wss://` requires a TLS terminator in front of this bridge.

Windows scripts are supplied but have not yet been executed on Windows. Startup/service configuration will follow once the game UI is verified.

## macOS development

```sh
export XMAGE_HOME=/path/to/extracted/xmage
export RULES_BRIDGE_TOKEN=your-private-random-connection-key
sh build.sh
sh run.sh
```

Default bind is loopback (`127.0.0.1`), port 17180. Optional environment variables: `RULES_BRIDGE_BIND`, `RULES_BRIDGE_PORT`, `XMAGE_HOST`, `XMAGE_PORT`. The engine defaults to `127.0.0.1:17171`.

Real-engine integration checks, after starting both processes (from `RulesBridge/`):

```sh
mkdir -p build/test-classes
javac --release 17 -encoding UTF-8 -cp "build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" -d build/test-classes tests/*.java
for check in BridgeSmoke BridgeTwoPlayerSmoke SeparateAiDeckSmoke MulliganSmoke CombatSmoke CombatPrioritySmoke FaceDownPrivacySmoke LeaveRaceSmoke SessionCapacitySmoke PriorityControlSmoke PrivateLookSmoke magicboard.rules.CardPrintingsTest magicboard.rules.PromptAnswersTest magicboard.rules.PromptMetadataTest magicboard.rules.PromptContextCardsTest; do
    java -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" "$check" || exit 1
done
```

`RULES_SMOKE_ADDRESS=ws://127.0.0.1:17182` selects an isolated test bridge. `BridgeSmoke` requires a real creature to resolve on your battlefield, rejects engine server-error endings, and checks finished-game replay. Its optional `RULES_SMOKE_DECK` points to a JSON deck/format command payload, with optional `aiDeck` for a distinct opponent deck. The fixture `tests/decks/jumpstart-legion-vs-goblins.json` combines the bundled Legion 1 + 2 and Goblins 1 + 2 packets into two real 40-card decks; its complete AI game, cleanup discard, stack ownership and game-over replay pass.

`MulliganSmoke` takes two real engine mulligans, answers all three individual return-to-library prompts, then keeps five cards and reaches first priority with that five-card hand. It logs the exact prompt wording used by the opening-hand UI.

`SeparateAiDeckSmoke` verifies that an unsupported AI card produces an actionable error, a retry succeeds on the same seat, and a 40-card Plains player deck faces a separate 40-card Island AI deck (observed through the human hand and AI battlefield).

The deterministic Jump In fixture `tests/decks/jumpin-crafting-cats-vs-depths-zombie.json` uses the first positive-probability option in each bundled random slot, with mono-colour basic lands filling each deck to 40. Its complete AI game passes, including Oteclan Landmark scry (two distinct selections), creatures, targeting and result replay. The smoke driver excludes already-selected cards so it progresses through scry rather than toggling a choice repeatedly; the app continues to allow deselection.

Run `sh tests/prompt-smoke.sh` against the current bridge for bounded real-card checks of ordering, modes, alternative costs, morph, nonzero X, hybrid mana, library search, equip, loyalty abilities, cleanup discard, instant responses, distributed damage and pile choices. Deck fixtures are in `tests/decks/`. The X probe casts Blaze with X=1, the hybrid probe casts Safehold Elite using Plains, and the search probe verifies that the chosen library card reaches the player's hand. These probes stop when their required interaction has progressed back to priority; they do not require finishing each artificial deck. The ordinary `BridgeSmoke` still checks a complete AI game. For local decoding diagnostics, `RULES_SMOKE_EVENTS=/path/to/events.jsonl` appends snapshot and prompt events from the probe (no authentication or connection events).

`PrivateLookSmoke` verifies private hand inspection with Gitaxian Probe on two real human seats. Set `RULES_LOOK_PUBLIC=1` to verify public Duress hand reveal instead. The tests check actual card IDs and a receipt-confirmed replay; private look data must never appear on the other seat.

`SecondSeatBot` is a second human seat for the phone's two-player check. Start it against the bridge, then run `testRulesTwoPlayerGameAgainstASecondSeat` with `TEST_RUNNER_RULES_SECOND_SEAT=1`: the phone creates a waiting game, the bot joins and plays simply (keep, play a playable card, pay with lands, pass), the phone starts the game and plays four of its own cards, then exits (which concedes).

```sh
java -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" SecondSeatBot
```

`BlockPromptFixture` is a separate, deterministic WebSocket fixture for focused phone interaction checks; it does not enforce Magic rules. Start it on loopback port 17183 with the same test connection key:

```sh
java -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" BlockPromptFixture
```

Set `TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS=ws://127.0.0.1:17183` when running the Rules UI tests `testRulesBlockDragAnswersTheFollowUpTarget`, `testRulesFullControlMenuReflectsEngineSetting`, `testRulesTriggerOrderingSelectsAnAbilityCard`, or `testRulesReconnectsAfterAppRelaunchAndClearsSeatOnExit`. They skip without that environment variable. The blocking fixture uses two attackers to require both blocker selection and a follow-up target answer; its `/ordering` route supplies two triggered abilities. `CombatSmoke` separately verifies legal blocker assignment with two real XMage human seats.

For the bounded malformed-replay unit check, start `MalformedUpdateFixture` on loopback port 17184 with the same classpath/key, then set `TEST_RUNNER_RULES_RECOVERY_FIXTURE_ADDRESS=ws://127.0.0.1:17184` for `RulesModeTests.testUnreadableReplaysStopRetryingWithoutDisconnecting`. The fixture deliberately repeats an invalid snapshot and closes the socket if the app asks for more than two replays. The test verifies the connection survives, the retry limit is respected and the player receives a recovery message. It skips without the fixture address.

For the recovery check, build with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-` on the simulator. An unsigned test build cannot access its Keychain. The signed simulator test has verified recovery across process termination/relaunch and deletion of the saved seat on explicit Exit Game. These fixture checks also verify the full-control menu and blocker dragging through a target prompt.

## Protocol and lifecycle

Version 1 uses JSON WebSocket text messages. The WebSocket upgrade requires `Authorization: Bearer <connection key>`. The bridge sends `hello`; the phone sends `connect` with `protocolVersion: 1` and optionally its session-specific `resumeToken`. `ready` returns the resume token. A token identifies one seat, not the combined game.

Commands `createAiGame`, `createHumanGame`, `listTables`, `joinTable`, `startMatch`, `answer`, `priorityControl`, and `resync` carry a unique `requestId`. `joinTable` also carries `tableId`. Answers carry `promptId`, current snapshot `revision`, `kind` (`boolean`, `uuid`, `integer`, `string`, `amounts`, `special`, `cancel`), and a typed `value`. `special` opens the engine's special-action menu; `cancel` uses the engine-specific cancellation for the current prompt, only when `canCancel` is true. The bridge returns `ack` or `error`. Duplicate request IDs return the original receipt (last 256 retained). Stale prompt IDs/revisions are rejected and the current state is resent.

`priorityControl` accepts `priorityAction`: `hold`, `release`, `cancelAutoPass`, `resolveStack`, `nextMain`, `endStep`, or `yourTurn`. Pass destinations also require the current `promptId` and `revision`, and are accepted only at `GAME_SELECT`. Hold/release/cancel can be used during the opponent's priority. `prioritySettings.holdingPriority` is replayed on reconnect; `snapshot.priority` contains the engine's active pass flags. A normal single pass remains a boolean answer to `GAME_SELECT`.

The Rules battlefield menu also switches between automatic and manual trigger ordering. `settings` with boolean `autoOrderTriggers` updates the seat's XMage preferences; `prioritySettings.autoOrderTriggers` returns the acknowledged value and is replayed on reconnect. Automatic ordering is the default. Normal Phone Play does not use these preferences.

Prompts expose optional `queryType`, `subMessage`, `canCancel`, `specialActionAvailable` and `specialActionLabel`. Trigger ordering is `GAME_TARGET` / `PICK_ABILITY`: choose an ability ID from `cards`, first onto the stack first. Modes and alternative-cost ability menus use `choices`; ability-menu IDs are sent to XMage as UUIDs. Unknown future dialog methods are marked unsupported.

Events include `tables`, `tableJoined`, `snapshot`, `prompt`, `promptCleared`, `gameOver`, `notice`, `engineDisconnected`, and `error`. Snapshots contain the seat's own hand, public card data and hidden-zone counts. Optional `revealed` and `lookedAt` arrays carry named card groups only as permitted by that seat's XMage view. Lightweight looked-at cards include printing identity and a name when the release metadata provides it. Phase, step and priority may be absent during setup. A combat group may lack `defenderId` briefly after an attacked permanent leaves play; clients must still accept that snapshot. Phone Play receives a display projection, including anonymous backs for hidden zones; it never receives the opponent's hand identities.

Disconnecting retains the bridge session for up to 15 minutes. Reconnecting resends its latest snapshot, pending prompt and final game result if already finished. The bridge keeps at most four sessions; a new connection at capacity reclaims the oldest disconnected session, never a connected player. Explicit `leave`, reclamation or expiry closes the XMage session. Bridge/server restarts do not preserve sessions. The phone stores its endpoint and resume token in the device Keychain, so a relaunched app offers Reconnect. An expired-session response clears the saved seat; Connect then starts fresh. Explicit Exit Game clears the saved seat too. Secure relaunch recovery passed in the signed simulator; physical-device verification remains.

## Remaining work

- Expand end-to-end gesture checks beyond the opening hand and normal Phone Play regression interaction.
- Command zones and Commander deck setup.
- Broad gameplay coverage of ordering, modes, alternative costs, special actions and priority controls, and their full phone UI.
- Registered-account support and device verification of app-relaunch recovery. Deck import and two-player format selection are implemented.
- Broader gameplay and physical-device coverage (Windows hosting and startup are now configured and tested).

UI reference: [Wizards' mobile Arena gameplay guide and screenshots](https://magic.wizards.com/en/news/mtg-arena/mtg-arena-state-game-january-2021-01-21), plus the existing Phone Play implementation. Prefer its actual shared controls over a parallel Rules-only battlefield.

### Bundled packet name compatibility

The audit checks every fixed card and every positive-probability Jump In variant against the installed XMage printing index. It reports unavailable names without substituting cards. This verifies name resolution, not full rules correctness or the legality of a generated deck.

After building and compiling the Java tests above, from `RulesBridge/`:

```sh
python3 tests/packet-manifest.py > build/packet-compatibility-input.json
java -Xmx256m -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" magicboard.rules.PacketCompatibilityTest build/packet-compatibility-input.json build/packet-compatibility-report.json
```

On pinned 1.4.63V2, 673 of 688 bundled packets resolve every possible name after punctuation normalization. Remaining gaps are 13 Marvel Super Heroes packets and the SOS Jump In packets LOREHOLD and SPELLCRAFT. The generated report lists exact names; newer engine releases may change these results.

### Deterministic multiple-mulligan fixture

`MulliganPromptFixture` runs on loopback port 17187 (or the port in its first argument). It replays the actual `MulliganSmoke` sequence and validates prompt ID, revision and returned card membership. `/observer` reports mulligan count, total returns, final hand size and completion; the key is the same `RULES_BRIDGE_TOKEN` environment variable. The real-engine probe also passes against this fixture, confirming the scripted protocol follows the observed engine sequence. This fixture does not implement Magic rules.

```sh
java -Xmx128m -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" MulliganPromptFixture
```

The phone test uses `TEST_RUNNER_RULES_MULLIGAN_FIXTURE_ADDRESS=ws://127.0.0.1:17187` and `RulesDiscardUITests/testTwoMulligansReturnOnlyTheKeptHandsCardsToTheLibrary`. It checks the deferred Arena flow (Keep 5 with seven displayed, then drag two chosen cards to Library) against the fixture's independently observed answers.

Question prompts may carry read-only `cards` as context. For example, Explore's graveyard Yes/No question includes the exact revealed card referenced by its `object_id`. The bridge uses only the current seat-filtered revealed/looked-at groups; it does not resolve hidden identities or guess by card name. `PromptContextCardsTest` checks those limits, and the bounded `explore` probe verifies the question's matching card and its eventual move to the graveyard against the real engine.

### Replay captured events through the actual Swift wire models (macOS)

Capture engine snapshots/prompts with `RULES_SMOKE_EVENTS=/absolute/path/events.jsonl` when running `BridgeSmoke`, then run:

```sh
sh tests/decode-events.sh /absolute/path/events.jsonl
```

Run this from the full repository checkout; the standalone server bundle does not include the iOS app source. This small command-line tool compiles the app's current `RulesProtocol.swift` directly with Swift, using a module cache under `build/`. It needs Xcode command-line tools; it does not start Xcode, a simulator, a bridge or an engine. It accepts multiple capture files and reports counts plus the exact file/line/field for decoding failures. Missing files, empty/incomplete captures and malformed messages return a nonzero exit code. It checks the wire schema, not game rules or UI behavior.

Verified with 2,844 captured Jump In, Explore, transform, distributed-damage, equipment, loyalty and flashback events; a deliberately missing `playerId` and a nonexistent file both fail with concise diagnostics.

The bounded `transform` probe casts Delver of Secrets, answers its reveal decision, and requires the engine to expose Insectile Aberration as a transformed 3/2 before returning to priority. Its captured snapshots/prompts also decode with the app's Swift models. It verifies engine/wire state; the physical card-face rendering remains a separate UI check.

`CombatPrioritySmoke` uses two real human seats and verifies an end-step native skip during both attacker selection and blocker selection. It checks only post-command updates from the seat receiving the choice (avoiding stale opponent snapshots) and requires actual engine progress or a retained answerable prompt. Both cases advance correctly on the pinned engine; no application payment/priority behavior was changed for this check. Optional `attackers` / `blockers` arguments select one case.

`FaceDownPrivacySmoke` casts Gathan Raiders face down in a real two-human game and compares both seats. The public permanent is Morph, XMAGE #0, 2/2; the opponent receives no original name/printing, red cost, Human/Warrior subtype or Hellbent text. This complements private-hand and looked-at-card checks. Pass a deck fixture path when running outside the RulesBridge directory.

### Costed mana abilities

The `costed-mana` prompt-smoke scenario casts Mind Rot using four Capital Cities. It explicitly chooses `{1}, {T}: Add one mana of any color`, pays that ability's nested `{1}` cost, chooses Black, and requires Mind Rot to reach the stack before returning to priority (`COSTED_MANA_SPELL_CAST`). The original scratch reproduction always chose the first ability (colorless), exhausting the lands while black remained unpaid. Current pinned-engine/client behavior offers both abilities; this regression needs no engine patch. This establishes the bridge path; it does not establish the original physical-device/Insomnia interaction is resolved.

The `vehicle` scenario uses Sky Skiff, Silvercoat Lion and a passive land-only AI deck. It requires selecting the crew ability, choosing a legal untapped creature, resolving the ability, and receiving Sky Skiff as a 2/3 Creature — Vehicle (`VEHICLE_CREWED_2_3`). This verifies the engine's type transition, not a particular board-row preference for uncrewed Vehicles.
