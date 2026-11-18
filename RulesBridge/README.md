# Magic Board Rules bridge (development)

Rules mode uses the **same Phone Play interface** as Host/Join. XMage controls its state and choices. Normal Phone Play retains its sandbox behavior and nearby transport. The bridge connects as an ordinary XMage client; no XMage source modifications are required.

## Verified so far

- Headless login to a stock XMage server on macOS with Java 17.
- A complete game against AI through the bridge: land play, creature casting, mana, priority and game-over.
- Per-player snapshots, duplicate command receipts, and reconnect restoring the same pending prompt.
- Two-human table creation/discovery/joining, distinct engine seats, and private opening hands.
- Main menu → connection → shared Phone Play board → opening hand → exit verified in the iOS simulator.
- Existing Phone Play: 66 unit tests and the sandbox drag/tap UI check passed. Five Rules isolation/schema tests passed.
- Stack objects carry their controller (inferred by the bridge: an ability's source controller, otherwise the player who held priority), checked in the real AI game.
- The initial AI deck is deliberately simple; this is not yet an all-card client.

## Pinned dependencies

Use release `xmage_1.4.63V2`, archive `mage-full_1.4.63-dev_2026-11-17_18-06.zip`, from [XMage releases](https://github.com/magefree/mage/releases/tag/xmage_1.4.63V2).

Archive SHA-256: `b6f5d182aafd40e531e05647a15245456ff9e7e3d5ef684cd946af397150f191`.

The bridge uses Java-WebSocket 1.6.0 (MIT); XMage is MIT licensed. The build scripts download the WebSocket jar and use the matching libraries from the extracted XMage client. Maven is not required. Java 17+ is required for **this bridge**, although XMage's own bytecode targets Java 8.

## Windows

Install a Java 17 JDK (including `javac`) and unpack the pinned XMage release. Run these commands in PowerShell, changing the path and key:

```powershell
$env:XMAGE_HOME = 'D:\games\xmage'
$env:RULES_BRIDGE_TOKEN = 'replace-with-a-private-random-key-of-at-least-16-characters'
$env:RULES_BRIDGE_BIND = '0.0.0.0'
```

Start the stock XMage server from its server directory. With Java 17, its old Java remoting requires the module access flag below:

```powershell
Set-Location "$env:XMAGE_HOME/mage-server"
java -Xmx1024m --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -jar ./lib/mage-server-1.4.63.jar
```

In another terminal, return to this repository's `RulesBridge` directory and run:

```powershell
./build.ps1
./run.ps1
```

The server should have anonymous authentication enabled (the pinned release's default). The bridge currently creates a generated XMage username per phone. Registered-account login is not implemented.

Allow the bridge's TCP port **17180** through Windows Firewall on your private network. Keep XMage's Java remoting port **17171** local to the PC. In Magic Board, choose **Connect to Rules Game**, enter `ws://YOUR-PC-ADDRESS:17180` and the matching connection key, then select **Play Against AI**. For two phones, one chooses **Create Two-Player Game**; the other selects that game from **Waiting Games**. The creator then selects **Start Game**. Both use the simple white creature test deck for now. Use a LAN or Tailscale address; do not expose the development bridge publicly. `ws://` does not encrypt the connection itself; Tailscale encrypts its private network traffic. `wss://` requires a TLS terminator in front of this bridge.

Windows scripts are supplied but have not yet been executed on Windows. Startup/service configuration will follow once the game UI is verified.

## macOS development

```sh
export XMAGE_HOME=/path/to/extracted/xmage
export RULES_BRIDGE_TOKEN=your-private-random-connection-key
sh build.sh
sh run.sh
```

Default bind is loopback (`127.0.0.1`), port 17180. Optional environment variables: `RULES_BRIDGE_BIND`, `RULES_BRIDGE_PORT`, `XMAGE_HOST`, `XMAGE_PORT`. The engine defaults to `127.0.0.1:17171`.

Real-engine integration check, after starting both processes:

```sh
javac --release 17 -cp "$XMAGE_HOME/mage-client/lib/*" -d build/classes tests/BridgeSmoke.java
java -cp "build/classes:$XMAGE_HOME/mage-client/lib/*" BridgeSmoke
javac --release 17 -cp "$XMAGE_HOME/mage-client/lib/*" -d build/classes tests/BridgeTwoPlayerSmoke.java
java -cp "build/classes:$XMAGE_HOME/mage-client/lib/*" BridgeTwoPlayerSmoke
```

## Protocol and lifecycle

Version 1 uses JSON WebSocket text messages. The WebSocket upgrade requires `Authorization: Bearer <connection key>`. The bridge sends `hello`; the phone sends `connect` with `protocolVersion: 1` and optionally its session-specific `resumeToken`. `ready` returns the resume token. A token identifies one seat, not the combined game.

Commands `createAiGame`, `createHumanGame`, `listTables`, `joinTable`, `startMatch`, `answer`, and `resync` carry a unique `requestId`. `joinTable` also carries `tableId`. Answers carry `promptId`, current snapshot `revision`, `kind` (`boolean`, `uuid`, `integer`, `string`), and a typed `value`. The bridge returns `ack` or `error`. Duplicate request IDs return the original receipt (last 256 retained). Stale prompt IDs/revisions are rejected and the current state is resent.

Events include `tables`, `tableJoined`, `snapshot`, `prompt`, `promptCleared`, `gameOver`, `notice`, `engineDisconnected`, and `error`. Snapshots contain only the seat's own hand, public card data and hidden-zone counts. Phase, step and priority may be absent during setup. Phone Play receives a display projection, including anonymous backs for hidden zones; it never receives the opponent's hand identities.

Disconnecting retains the bridge session for 15 minutes. Reconnecting resends its latest snapshot and pending prompt. Explicit `leave` or expiry closes the XMage session. Bridge/server restarts do not preserve sessions. Resume tokens currently last for the app session; app-relaunch recovery is outstanding.

## Remaining work

- Expand end-to-end gesture checks beyond the opening hand and normal Phone Play regression interaction.
- Command zones, playable highlights, and detailed dynamic rules text.
- Full prompt variants, ordering, pile selection, multi-amount choices, special actions and priority stops.
- Deck import, format selection and account support.
- Windows execution testing, startup scripts and broader gameplay coverage.

UI reference: [Wizards' mobile Arena gameplay guide and screenshots](https://magic.wizards.com/en/news/mtg-arena/mtg-arena-state-game-january-2021-01-21), plus the existing Phone Play implementation. Prefer its actual shared controls over a parallel Rules-only battlefield.
