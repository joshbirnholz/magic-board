# Rules mode implementation plan

## Workspace and integration

- Worktree: `/private/tmp/MagicBoard-Rules`; branch: `rules-mode`.
- Initial base: `phone-play` at `b2aa781`.
- Leave the original checkout and its uncommitted edits untouched.
- At milestone boundaries and before touching shared UI files, inspect new commits on `phone-play` and `main`. Merge applicable committed fixes into this branch and resolve conflicts here. Do not switch branches in Claude's checkout or commit its work.
- Keep implementation in `RulesBridge/` and `Magic Board/RulesPlay/` where possible. Limit shared UI changes to routing and deliberate presentation/action integration points.
- No merge back into Claude's branch until integration is requested.

## Intended experience

Add **Connect to Rules Game** beside Host Game and Join Game. The user enters a remembered bridge address, connects to the Windows PC, and creates or joins an XMage game. First support a solo game against AI, then two human clients.

Keep Scryfall full-card images. Populate battlefield properties from XMage. Rules sessions submit engine actions and prompt answers; they do not apply sandbox state patches. Local hand ordering and battlefield placement remain presentation state where supported.

Reuse Phone Play's actual interface, not the iPad board presentation or a separate battlefield implementation. The Rules adapter feeds an engine-authoritative display projection into the existing Phone Play session facade. Every hook is gated on Rules mode; normal Host/Join retain sandbox dragging and editing. Consult MTG Arena for gameplay UI decisions. Ask for missing visual references only when useful, and continue independent work while waiting.

## Milestones

1. **Prove the headless Java client.** Pin an XMage revision/release, inspect its shared session and callback interfaces, connect to a stock local server, submit simple decks, create an AI match, and receive player-specific state and prompts. Validate Java/runtime requirements from the chosen release. Record any headless dependency work. Do not assume the desktop client is a clean reusable library.
2. **Define and implement the bridge protocol.** JSON over WebSocket with a version handshake, authenticated seat/session ownership, player-specific snapshots, ordered updates, prompt identifiers, action acknowledgements, and explicit errors. Serialize answers per XMage session and reject stale or repeated submissions. Preserve current pending prompts for phone reconnects. Do not promise survival across a server restart without engine support.
3. **Add the app connection and read-only board.** Introduce a separate rules session and server-state models. Add the main-screen option, remembered endpoint, connection status, recoverable errors, cancellation, and return-to-menu behavior. Map visible cards and live battlefield properties into existing rendering with hidden-zone counts and image fallbacks.
4. **Complete one simple game against AI.** Implement priority, casting, mana payment, targets, choices, combat, mulligans, and the remaining prompts exercised by the test decks. Start with generic usable prompt sheets, then connect existing gestures. Verify a complete game and disconnect/reconnect before expanding scope.
5. **Expand prompt coverage and two-phone play.** Inventory callbacks and payload variants against the pinned XMage source. Add choices such as ordering, multiple modes, numbers, alternative costs, revealed cards, and special actions. Unsupported prompts must be explicit rather than silently answered. Test seat isolation, simultaneous connections, stale actions, and app background/foreground recovery.
6. **Package for Windows and refine.** Supply a reproducible bridge build, matching XMage version instructions, startup scripts, configuration, and LAN/Tailscale setup. Add priority stops, auto-pass, and interaction polish after the core game loop works. Windows execution remains unverified until tested on Windows.

## Verification and scope

Use focused bridge/protocol checks and appropriate app builds. Validate real engine interactions rather than only mocked messages. Keep simulator and engine resource use proportional. Do not repeatedly retry broken automation.

First delivery targets ordinary two-player constructed games and solo AI. Draft, sealed, tournaments, multiplayer UI expansion, public matchmaking, and on-device Java are outside the first version. Report milestone outcomes and blockers without requiring approval for routine implementation decisions.
