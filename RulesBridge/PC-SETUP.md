# Run the Rules bridge on your PC

This bundle contains the prebuilt Magic Board bridge, its WebSocket dependency and source. Install **Java 17 or newer** and the matching **XMage xmage_1.4.63V2 full release** separately. The prebuilt bridge needs a Java runtime; compiling the included source also needs a JDK.

1. Extract the bundle to a permanent folder, and extract XMage so its `mage-client` and `mage-server` directories sit beside each other. See `README.md` for the pinned archive and checksum.
2. Open PowerShell in the bridge folder. Set these values, using your actual XMage path and a private key of at least 16 characters:

   ```powershell
   $env:XMAGE_HOME = 'C:\Games\xmage'
   $env:RULES_BRIDGE_TOKEN = 'replace-this-with-your-own-private-connection-key'
   $env:RULES_BRIDGE_BIND = '0.0.0.0'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-server.ps1
   ```

3. Leave that server window running. In a second PowerShell window in the same folder, set the same three environment variables and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
   ```

   The execution-policy option applies to that script process. No compilation is needed for this bundle.

4. Allow the bridge's TCP port **17180** through Windows Firewall on your private network. Keep XMage's remoting port **17171** local to the PC. Keep the PC awake while playing.
5. In Magic Board's `rules-mode` build, select **Connect to Rules Game**, enter `ws://YOUR-PC-ADDRESS:17180` and your connection key, then choose **Play Against AI**. Start with the built-in creature deck. Imported ordinary two-player decks are supported; Commander setup is not implemented yet.

For two phones, one creates a two-player game and the other joins it from Waiting Games; the creator starts the game after both have joined. Away from home, use your private Tailscale address. Plain `ws://` does not itself encrypt the connection; keep it on a private LAN or encrypted private network.

Bridge/server restarts end resumable sessions. An app restart can reconnect to a seat retained by the running bridge. Explicit Exit Game releases it. Normal Host/Join Phone Play continues to use its existing sandbox behavior.

The bridge and package have been exercised on macOS. These PowerShell launchers have not yet been executed on Windows. `SOURCE-COMMIT.txt` identifies the source snapshot. The included dependency's notice is in `ThirdParty/Java-WebSocket-LICENSE.txt`.
