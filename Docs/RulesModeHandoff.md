# Rules mode handoff — November 18, 2026 (Codex integration update, 2:40 AM ET)

Read `/private/tmp/MagicBoard-Rules-coordination.md` first. It is the live coordination record outside git, including active task claims and the shared simulator lock. Claude and Codex are both working; check ownership there before editing shared files.

## Workspace and constraints

- Integration worktree `/private/tmp/MagicBoard-Rules`, branch `rules-mode`. Never push.
- Never edit the main checkout `/Users/compc/Xcode/Magic Board` or its uncommitted files. Merge its committed `phone-play` fixes here periodically. Latest merged: `dd3c3bd` (opponent HUD recovery), including `d0ac0a8` (DFC hand cost) and earlier deck-parser/Jump-In fixes.
- Claude's worktree `/private/tmp/MagicBoard-Rules-Claude`, branch `rules-mode-claude`. All committed work through `20d1323` is merged. Never edit that folder. When Claude returns, it should merge `rules-mode` into its own branch first.
- Rules mode must reuse Phone Play's interface. Every engine behavior remains gated to Rules mode; normal Phone Play retains its sandbox actions and persistence.
- Exactly one Xcode/simulator operation across all workers, including the separate main-checkout Phone Play Claude. Acquire `/private/tmp/magicboard-rules-xcode.lock` with `mkdir`, write `owner`, and stop if acquisition fails. Release when finished. Never take another agent's lock. Check the lock itself for its current owner.
- Only simulator `1D870442-4F84-4AD8-ABB6-469AD44AFFB9` (iOS 17.5); never boot a second one. Use `nice -n 10`, `-jobs 4`, `ENABLE_DEBUG_DYLIB=NO`.

## What works and what was verified

A playable prototype exists. A complete AI game now finishes through the actual Phone Play interface with the intended white creature deck, rather than just through a Java driver.

- **All 92 unit tests pass** (68 Phone Play + 24 Rules), including the latest Phone Play merges, basic-land payment guard and combat-defender decoding regression.
- Real engine AI lifecycle: land play, creature casting/resolution, mana, stack ownership, priority, game-over and replay of the final result. The smoke test rejects server-error endings.
- Real two-human seats: create/discover/join/start, separate private seven-card hands, creature play, attackers and legal blocker assignment (`CombatSmoke`). This is protocol/engine verification, not two physical phones.
- Phone UI full game against AI passed with the corrected default deck (`/private/tmp/magicboard-rules-blocking-integration.log`, xcresult timestamp 22:07:33). The AI offered no block in that run, so it does not establish blocker-gesture coverage.
- **Deterministic blocker UI check passed**: dragging our untapped creature onto one of two attackers sends the blocker UUID, then automatically answers the follow-up attacker-target prompt. The fixture validates both answers; the UI shows one blocking assignment.
- **Signed simulator recovery check passed**: terminate/relaunch app, load its retained seat from Keychain, reconnect to the same fixture game, then explicitly exit and verify the saved seat was deleted.
- Signed simulator full-control menu check passed after fixing its menu callback type.
- LAN ws:// to the Mac's private address was checked in the simulator by Claude earlier. Windows hosting and the Tailscale route have since passed full simulator games; two physical phones remain unverified.

The deterministic phone checks use `RulesBridge/tests/BlockPromptFixture.java` and `TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS=ws://127.0.0.1:17183`. The fixture does not enforce Magic rules; real engine combat is separately checked by `CombatSmoke`.

## Important fixes since Claude's handoff

- `06aab80`: the original built-in deck hard-coded M10 #31 for Silvercoat Lion; XMage loaded **Silence** instead. Built-in cards now use `CardPrintings.resolve` by name. The smoke test requires an actual creature to resolve and rejects unexpected built-in hand names.
- `c542aa6`: exact phase mapping. `contains("COMBAT")` incorrectly classified PRECOMBAT_MAIN and POSTCOMBAT_MAIN as combat. Main phases now map correctly. Client auto-pass respects held priority.
- `e29b184`, corrected in `65d7f8e`: Rules-only battlefield menu exposes hold/release full control, native pass destinations, and cancellation. Use `BoardMenuAction(title:style:.default) { _ in ... }` for actions that must dismiss. The zero-argument initializer is a navigation destination and leaves the menu open.
- `c388560`: the old blocking probe tried to use tapped creatures and held for 0.4 seconds, crossing the card inspector's 0.35-second threshold. It now preserves an untapped blocker, starts dragging at 0.1 seconds, and fails immediately if the app leaves the foreground. The old failure screenshot was the simulator Home screen, not a frozen rules prompt.
- `676f2ad`, `65d7f8e`: secure retained-seat storage, explicit expired-session recovery, final-result replay, and verified simulator app-relaunch recovery.
- **`98f46cc`: confirmed WebSocket deadlock fixed.** A simultaneous `leave` and socket abort inverted the BridgeMain and WebSocket monitors. `onClose` now queues synchronized detach work instead of waiting inside the socket callback. Twelve race cycles, capacity recovery, two-human privacy and graceful shutdown passed. Thread evidence: `/private/tmp/rules-probe-bridge-threads.txt`.
- `a3b31b1`: Windows `start-server.ps1` helper includes the correct server directory, 1 GB heap, headless mode and Java 17 remoting flag. The Windows host has since been set up and verified by Claude; see the current-state section below.

## Current state (Codex integration, 3:34 AM)

Read the coordination file's "Now" and "Ready to merge" first.
- Revealed/looked-at views now flow from the seat-filtered engine snapshot to optional `revealed`/`lookedAt` card groups. `session.cardInformation` retains the transient groups until `dismissCardInformation(id)`; older replays stay dismissed, a later reveal of the same cards reopens, and fresh/expired sessions clear them. All 92 units pass, including actual WebSocket retention and recovery tests.
- Two real seats verify private Gitaxian Probe hand inspection goes only to its permitted seat, while public Duress hand reveal goes to both, with the actual target hand and receipt-confirmed replay. `PrivateLookSmoke` reproduces these; set `RULES_LOOK_PUBLIC=1` for the public variant. Printing-name fallback for lightweight card views passes `CardPrintingsTest`.
- Claude has been asked to add the information-window UI; no board/prompt UI files were changed by Codex for this feature.
- **Merged `rules-mode-claude` through `20d1323`** into `rules-mode` and verified all 87 units. It adds: two-player UI check with `SecondSeatBot`; Arena-style automatic mana payment with basic lands plus a menu toggle; a fix for auto-pass/auto-pay often not firing (stale `canAnswer` inside the @Published sink); `RULES_UI_TEST_KEY`; an imported-deck UI test; a clear undersized-deck message; card names on their own line in prompt text; tapping an outlined hand card answers choose-from-hand prompts.
- **Windows PC host is live** (Josh's home server; touch it as little as possible): `compc@100.96.101.108` over Tailscale, key-only SSH, PowerShell. Folder `C:\Users\compc\MagicBoardRules` (XMage bound to 127.0.0.1, bridge on `100.96.101.108:17180`, key in `connection-key.txt`, `pc-run.ps1` starts both via WMI, logs `server.log`/`bridge.log`, Startup-folder entry starts them at login). Java is `C:\Users\compc\.jdks\jbr-21.0.11\bin\java.exe`. To redeploy a newer bridge: copy a fresh `package.sh` zip, stop only the bridge's java process (check its command line), unzip over `MagicBoard-RulesBridge`, start it again.
- Verified tonight: BridgeSmoke and the simulator full game against the PC over Tailscale (220 s, mana paid automatically).
- The scry modal was fixed in `20d1323`; UI-tested prompt kinds and the ones not yet reached are listed in the coordination file.
- `d34dcb0`: automatic payment now selects only noncreature basic lands (nonbasic land subtypes can have activation restrictions). Wastes is recognized by name, since it has no land subtype. Snow basics remain supported. All 20 Rules units pass.
- `67349a1`: new bounded real-engine probes pass for Blaze with X=1, Safehold Elite paid with Plains, and Sylvan Scrying moving the chosen library card into hand. Reproduce using `RulesBridge/tests/prompt-smoke.sh`; the three new deck fixtures are in `tests/decks/`. The smoke driver now selects card-list targets instead of silently cancelling them.
- Phone UI library search passed (56 s), hybrid mana passed (57 s), and numeric X choice/targeting passed (60 s). The UI X driver confirms the chooser with its default zero; nonzero X=1 is verified separately by the real-engine probe. The imported-deck test now supports `TEST_RUNNER_RULES_UI_TEST_REQUIRED_PROMPTS`, a pipe-separated list of message fragments; it requires each to appear and the engine to return to priority before stopping early.
- `d358cb4`: fixed a real disconnect when an attacked planeswalker dies. XMage retains a combat group without a defender until combat ends; `CombatGroup.defenderId` is now optional. All 454 snapshot/prompt events from a complete equipment/Ajani game decode with the app protocol; they failed before the fix. The optional smoke diagnostic `RULES_SMOKE_EVENTS` captures only snapshot/prompt events locally.
- `248eebb`: bounded unreadable-update recovery; the actual Swift receive loop passes the local malformed-replay fixture. Existing 89 units passed after merging `5306e02`; the new fixture test passed separately after fixing the fixture process lifetime. The fixture is now stopped.
- `768f676`, `a71221c`, `54e9049`: actual equip attachment, loyalty life gain, cleanup discard into graveyard, opponent-turn instant cast/resolution, multi-target damage distribution and Fact or Fiction selected-pile-to-hand checks pass. Reproduce with `tests/prompt-smoke.sh`. UI counterparts remain tracked in coordination.
- Claude Auto mana UI `9a3bbf6` is merged; post-merge units pass as part of the 92-test run.
- `2bf16ad`: real-engine end-step and next-turn native priority stops passed, including reset of the skip flags. A subsequent bounded BridgeSmoke probe also passed resolve-stack with a real creature spell, returning to priority with an empty stack and cleared skip flag (`RULES_SMOKE_RESOLVE_STACK=1`).

## Runtime and verification details

- Stock XMage release `xmage_1.4.63V2`, runtime `/private/tmp/xmage-rules-runtime/xmage`.
- Server PID **45605**, port **17171**, `-Xmx1024m`; log `/private/tmp/magicboard-rules-xmage-server.log`. It currently binds all interfaces; keep that remoting port local/private.
- Shared bridge PID **74663**, `127.0.0.1:17180`, deployed through `94f2753`; token `rules-local-verification-key`; log `/private/tmp/magicboard-rules-bridge.log`.
- Temporary Java tests use port **17182** and always stop that isolated bridge. The phone fixture used **17183** and has been stopped. Simulator connection preferences may still point to 17183: use 17180 for the real bridge.
- DerivedData `/private/tmp/magicboard-rules-dd`; packages `/private/tmp/magicboard-rules-packages`.
- For Keychain tests use **`CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`**. Unsigned test builds could not persist credentials; ad-hoc signing made both recovery and explicit cleanup pass. Do not replace Keychain storage with UserDefaults to work around that test configuration.
- Latest focused signed UI results: `/private/tmp/magicboard-rules-signed-recovery-ui.log`, xcresult timestamp 22:27:53. Two tests passed.
- Build Java: `XMAGE_HOME=/private/tmp/xmage-rules-runtime/xmage sh RulesBridge/build.sh`. README contains smoke commands and fixture setup.
- Never globally kill Java or every bridge. Identify the process by its port/PID and verify its command before stopping it. The shared bridge is a service used by UI tests; do not restart it during another agent's lock.
- All external artifacts live under `/private/tmp` and can disappear on reboot. Commit completed work; never push.

## Remaining scope

Prioritize a stable first build Josh can test on his phone. Finish the current prompt checks and manual-trigger preference, then check physical/LAN setup if a device is available without disrupting the user. Windows startup and networking instructions are in `RulesBridge/README.md`.

Commander command zones/import, registered accounts, broad card coverage, and further Arena polish remain future work. On-device Java/AOT is explicitly deferred. Josh's current instruction is to work autonomously, including Claude's tasks while it is away, and keep the coordination/handoff documents current for whichever agent resumes next.
