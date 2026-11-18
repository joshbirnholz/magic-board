import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** Replay the real MulliganSmoke sequence and observe phone answers independently. */
public final class MulliganPromptFixture extends WebSocketServer {
    private static final Gson JSON = new Gson();
    private static final String ME = "00000000-0000-0000-0000-000000000001", THEM = "00000000-0000-0000-0000-000000000002";
    private final Set<WebSocket> observers = ConcurrentHashMap.newKeySet();
    private final List<JsonObject> hand = new ArrayList<>();
    private int round, remaining, returns, revision;
    private String stage = "ask";
    private boolean complete;

    private MulliganPromptFixture(int port) { super(new InetSocketAddress("127.0.0.1", port), 1); }
    private static JsonObject object(Object... pairs) {
        JsonObject object = new JsonObject();
        for (int i = 0; i < pairs.length; i += 2) object.add(pairs[i].toString(), JSON.toJsonTree(pairs[i + 1]));
        return object;
    }
    private static void send(WebSocket socket, JsonObject object) { socket.send(JSON.toJson(object)); }
    private void status(WebSocket socket) { send(socket, object("mulligans", round, "returns", returns, "handCount", hand.size(), "complete", complete)); }
    private static void ack(WebSocket socket, JsonObject request) { send(socket, object("type", "ack", "requestId", request.get("requestId"))); }
    @Override public synchronized void onOpen(WebSocket socket, ClientHandshake request) {
        if (!request.getFieldValue("Authorization").equals("Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))) {
            socket.close(1008, "Invalid key"); return;
        }
        if (request.getResourceDescriptor().endsWith("/observer")) { observers.add(socket); status(socket); }
        else send(socket, object("type", "hello", "protocolVersion", 1));
    }
    @Override public synchronized void onMessage(WebSocket socket, String text) {
        if (observers.contains(socket)) { status(socket); return; }
        JsonObject request = JsonParser.parseString(text).getAsJsonObject();
        switch (request.get("type").getAsString()) {
            case "connect" -> send(socket, object("type", "ready", "protocolVersion", 1, "resumeToken", "mulligan-fixture", "formats", new String[]{"Limited"}));
            case "listTables" -> { send(socket, object("type", "tables", "tables", new Object[]{})); ack(socket, request); }
            case "createAiGame" -> {
                round = remaining = returns = 0; revision = 1; stage = "ask"; complete = false;
                drawSeven(); ack(socket, request); publish(socket);
            }
            case "answer" -> {
                try {
                    if (!request.get("promptId").getAsString().equals("mulligan-" + revision)
                            || request.get("revision").getAsInt() != revision) throw new IllegalArgumentException("Stale opening-hand answer");
                    if (stage.equals("ask") && request.get("kind").getAsString().equals("boolean")) {
                        if (request.get("value").getAsBoolean()) {
                            if (round >= 2) throw new IllegalArgumentException("The scenario keeps five cards");
                            round++; drawSeven(); remaining = round; stage = "return";
                        } else {
                            if (round != 2 || hand.size() != 5) throw new IllegalArgumentException("The scenario must mulligan twice before keeping five");
                            complete = true; stage = "play";
                        }
                    } else if (stage.equals("return") && request.get("kind").getAsString().equals("uuid")) {
                        String id = request.get("value").getAsString();
                        if (!hand.removeIf(card -> card.get("id").getAsString().equals(id))) throw new IllegalArgumentException("Returned card was not in this hand");
                        returns++; remaining--; if (remaining == 0) stage = "ask";
                    } else throw new IllegalArgumentException("Wrong answer type for " + stage);
                    revision++; send(socket, object("type", "promptCleared")); ack(socket, request); publish(socket);
                    System.out.println("Mulligans=" + round + " returns=" + returns + " hand=" + hand.size() + " complete=" + complete);
                } catch (IllegalArgumentException error) { send(socket, object("type", "error", "requestId", request.get("requestId"), "message", error.getMessage())); }
            }
            case "leave" -> socket.close(1000, "Done");
            case "resync" -> { ack(socket, request); publish(socket); }
        }
    }
    private void drawSeven() {
        hand.clear();
        for (int i = 0; i < 7; i++) {
            boolean land = i % 2 == 0;
            hand.add(object("id", String.format("00000000-0000-0000-0000-%012d", 100 + round * 10 + i),
                    "name", land ? "Plains" : "Silvercoat Lion", "set", "M10", "collectorNumber", land ? "230" : "32",
                    "typeLine", land ? "Basic Land — Plains" : "Creature — Cat", "manaCost", land ? "" : "{1}{W}",
                    "faceDown", false, "transformed", false, "counters", new Object[]{}));
        }
    }
    private void publish(WebSocket socket) {
        JsonArray players = new JsonArray();
        for (String id : List.of(ME, THEM)) players.add(object("id", id, "name", id.equals(ME) ? "You" : "Opponent", "life", 20,
                "handCount", id.equals(ME) ? hand.size() : 7, "libraryCount", id.equals(ME) ? 60 - hand.size() : 53,
                "battlefield", new Object[]{}, "graveyard", new Object[]{}, "exile", new Object[]{}));
        JsonObject snapshot = object("type", "snapshot", "gameId", "00000000-0000-0000-0000-000000000099", "playerId", ME,
                "revision", revision, "turn", complete ? 1 : 0, "activePlayerId", ME, "hand", hand, "players", players,
                "stack", new Object[]{}, "playableIds", new Object[]{});
        if (complete) { snapshot.addProperty("phase", "PRECOMBAT_MAIN"); snapshot.addProperty("step", "PRECOMBAT_MAIN"); }
        send(socket, snapshot);
        String method = stage.equals("return") ? "GAME_TARGET" : complete ? "GAME_SELECT" : "GAME_ASK";
        String message = stage.equals("return") ? "Select a card (" + remaining + " more) to put on the bottom of your library"
                : complete ? "Play spells and abilities" : "Mulligan <font color=#ffff00>down to " + (6 - round) + " cards</font>?";
        JsonArray targets = new JsonArray();
        if (stage.equals("return")) for (JsonObject card : hand) targets.add(card.get("id"));
        send(socket, object("type", "prompt", "id", "mulligan-" + revision, "revision", revision, "method", method,
                "message", message, "required", true, "supported", true, "targets", targets, "cards", new Object[]{}, "choices", new Object[]{}));
    }
    @Override public synchronized void onClose(WebSocket socket, int code, String reason, boolean remote) { observers.remove(socket); }
    @Override public void onError(WebSocket socket, Exception error) { error.printStackTrace(); }
    @Override public void onStart() { System.out.println("READY mulligan fixture " + getPort()); }
    public static void main(String[] args) {
        MulliganPromptFixture server = new MulliganPromptFixture(args.length == 0 ? 17187 : Integer.parseInt(args[0]));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { try { server.stop(1000); } catch (InterruptedException ignored) {} }));
        server.start();
    }
}
