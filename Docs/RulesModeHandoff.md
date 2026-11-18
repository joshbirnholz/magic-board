# Rules mode handoff — Codex (10:54 PM), updated by Claude, November 18, 2026, 1:20 AM ET

Read `/private/tmp/MagicBoard-Rules-coordination.md` first. It is the live coordination record outside git. Josh says Claude returns at **1:10 AM**; until then Codex owns Claude's board/prompt/UI-test work as well as the bridge. Update this handoff at the next meaningful milestone, especially before Claude returns.

## Workspace and constraints

- Integration worktree `/private/tmp/MagicBoard-Rules`, branch `rules-mode`. Never push.
- Never edit the main checkout `/Users/compc/Xcode/Magic Board` or its uncommitted files. Merge its committed `phone-play` fixes here periodically. Latest merged: `0ed49a4` (Jump-In set grid), including `970c4a1` (deck parser).
- Claude's worktree `/private/tmp/MagicBoard-Rules-Claude`, branch `rules-mode-claude`. All committed work through `11575ad` is merged. Never edit that folder. When Claude returns, it should merge `rules-mode` into its own branch first.
- Rules mode must reuse Phone Play's interface. Every engine behavior remains gated to Rules mode; normal Phone Play retains its sandbox actions and persistence.
- Exactly one Xcode/simulator operation across all workers, including the separate main-checkout Phone Play Claude. Acquire `/private/tmp/magicboard-rules-xcode.lock` with `mkdir`, write `owner`, and stop if acquisition fails. Release when finished. Never take another agent's lock. The lock is currently released.
- Only simulator `1D870442-4F84-4AD8-ABB6-469AD44AFFB9` (iOS 17.5); never boot a second one. Use `nice -n 10`, `-jobs 4`, `ENABLE_DEBUG_DYLIB=NO`.

## What works and what was verified

A playable prototype exists. A complete AI game now finishes through the actual Phone Play interface with the intended white creature deck, rather than just through a Java driver.

- **84 unit tests passed**: 68 PhoneGameTests and 16 RulesModeTests. The 16 Rules tests passed again after the latest Phone Play merge.
- Real engine AI lifecycle: land play, creature casting/resolution, mana, stack ownership, priority, game-over and replay of the final result. The smoke test rejects server-error endings.
- Real two-human seats: create/discover/join/start, separate private seven-card hands, creature play, attackers and legal blocker assignment (`CombatSmoke`). This is protocol/engine verification, not two physical phones.
- Phone UI full game against AI passed with the corrected default deck (`/private/tmp/magicboard-rules-blocking-integration.log`, xcresult timestamp 22:07:33). The AI offered no block in that run, so it does not establish blocker-gesture coverage.
- **Deterministic blocker UI check passed**: dragging our untapped creature onto one of two attackers sends the blocker UUID, then automatically answers the follow-up attacker-target prompt. The fixture validates both answers; the UI shows one blocking assignment.
- **Signed simulator recovery check passed**: terminate/relaunch app, load its retained seat from Keychain, reconnect to the same fixture game, then explicitly exit and verify the saved seat was deleted.
- Signed simulator full-control menu check passed after fixing its menu callback type.
- LAN ws:// to the Mac's private address was checked in the simulator by Claude earlier. A physical device, Tailscale route, and Windows execution remain unverified.

The deterministic phone checks use `RulesBridge/tests/BlockPromptFixture.java` and `TEST_RUNNER_RULES_BLOCK_FIXTURE_ADDRESS=ws://127.0.0.1:17183`. The fixture does not enforce Magic rules; real engine combat is separately checked by `CombatSmoke`.

## Important fixes since Claude's handoff

- `06aab80`: the original built-in deck hard-coded M10 #31 for Silvercoat Lion; XMage loaded **Silence** instead. Built-in cards now use `CardPrintings.resolve` by name. The smoke test requires an actual creature to resolve and rejects unexpected built-in hand names.
- `c542aa6`: exact phase mapping. `contains("COMBAT")` incorrectly classified PRECOMBAT_MAIN and POSTCOMBAT_MAIN as combat. Main phases now map correctly. Client auto-pass respects held priority.
- `e29b184`, corrected in `65d7f8e`: Rules-only battlefield menu exposes hold/release full control, native pass destinations, and cancellation. Use `BoardMenuAction(title:style:.default) { _ in ... }` for actions that must dismiss. The zero-argument initializer is a navigation destination and leaves the menu open.
- `c388560`: the old blocking probe tried to use tapped creatures and held for 0.4 seconds, crossing the card inspector's 0.35-second threshold. It now preserves an untapped blocker, starts dragging at 0.1 seconds, and fails immediately if the app leaves the foreground. The old failure screenshot was the simulator Home screen, not a frozen rules prompt.
- `676f2ad`, `65d7f8e`: secure retained-seat storage, explicit expired-session recovery, final-result replay, and verified simulator app-relaunch recovery.
- **`98f46cc`: confirmed WebSocket deadlock fixed.** A simultaneous `leave` and socket abort inverted the BridgeMain and WebSocket monitors. `onClose` now queues synchronized detach work instead of waiting inside the socket callback. Twelve race cycles, capacity recovery, two-human privacy and graceful shutdown passed. Thread evidence: `/private/tmp/rules-probe-bridge-threads.txt`.
- `a3b31b1`: Windows `start-server.ps1` helper includes the correct server directory, 1 GB heap, headless mode and Java 17 remoting flag. Supplied but not executed on Windows.

## Current state (Claude, 1:20 AM, while Codex is at its usage limit until 2:28 AM)

- Codex's manual-trigger work is committed (`94f2753`: automatic/manual trigger ordering setting, ordering UI selection, trigger/mode/alternative-cost/morph probes; 16 Rules unit tests and the ordering/settings UI tests passed). The shared bridge on 17180 (PID 74663, started 11:21 PM) runs that code.
- Codex's in-progress **PC bridge package** was uncommitted; Claude reviewed and committed it. `XMAGE_HOME=/private/tmp/xmage-rules-runtime/xmage sh RulesBridge/package.sh` builds `RulesBridge/build/MagicBoard-RulesBridge.zip` (jar, WebSocket jar + licence, launchers, source, `PC-SETUP.md`, `SOURCE-COMMIT.txt`) and a `.sha256`; verified on macOS. The PowerShell launchers still haven't run on Windows.
- Codex's lock from 11:20 PM was stale (no xcodebuild running) and was removed at 1:11 AM.
- Claude merged `rules-mode` into `rules-mode-claude` and is rerunning all PhoneGameTests and RulesModeUITests (including the full game vs AI) on the merged code. Results go under "Now" in the coordination file.

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
