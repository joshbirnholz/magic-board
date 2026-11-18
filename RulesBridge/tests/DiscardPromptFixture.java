import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** Gesture fixture only. Real cleanup legality is checked independently by BridgeSmoke. */
public final class DiscardPromptFixture extends WebSocketServer {
    private static final Gson JSON = new Gson();
    private static final String ME = "00000000-0000-0000-0000-000000000001";
    private static final String THEM = "00000000-0000-0000-0000-000000000002";
    private static final String GAME = "00000000-0000-0000-0000-000000000100";
    private final List<String> hand = new ArrayList<>();
    private final Set<WebSocket> observers = ConcurrentHashMap.newKeySet();
    private int revision = 1;
    private DiscardPromptFixture(int port) { super(new InetSocketAddress("127.0.0.1", port), 1); reset(); }
    private void reset() {
        hand.clear(); revision = 1;
        for (int i = 0; i < 9; i++) hand.add(String.format("00000000-0000-0000-0000-%012d", i + 10));
    }
    private static JsonObject object(Object... values) {
        JsonObject result = new JsonObject();
        for (int i = 0; i < values.length; i += 2) result.add(values[i].toString(), JSON.toJsonTree(values[i + 1]));
        return result;
    }
    private static void send(WebSocket socket, JsonObject value) { socket.send(JSON.toJson(value)); }
    private synchronized void status(WebSocket socket) {
        send(socket, object("remaining", hand.size(), "answers", 9 - hand.size(), "complete", hand.size() == 7));
    }
    @Override public void onOpen(WebSocket socket, ClientHandshake request) {
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
            case "connect" -> send(socket, object("type", "ready", "protocolVersion", 1, "resumeToken", "discard-fixture"));
            case "listTables" -> { send(socket, object("type", "tables", "tables", new Object[]{})); ack(socket, request); }
            case "createAiGame" -> { reset(); ack(socket, request); publish(socket); }
            case "answer" -> {
                if (!request.get("kind").getAsString().equals("uuid") || hand.size() <= 7
                        || !hand.remove(request.get("value").getAsString())) {
                    send(socket, object("type", "error", "message", "Discard must choose a current hand card")); return;
                }
                revision++; ack(socket, request); publish(socket);
                System.out.println("PASS real hand tap selected a legal discard; remaining=" + hand.size());
            }
            case "resync" -> { publish(socket); ack(socket, request); }
            case "leave" -> socket.close(1000, "Done");
        }
    }
    private static void ack(WebSocket socket, JsonObject request) { send(socket, object("type", "ack", "requestId", request.get("requestId"))); }
    private void publish(WebSocket socket) {
        List<JsonObject> cards = new ArrayList<>();
        for (String id : hand) cards.add(object("id", id, "name", "Silvercoat Lion", "set", "M10", "collectorNumber", "32",
                "typeLine", "Creature — Cat", "power", "2", "toughness", "2", "manaCost", "{1}{W}",
                "faceDown", false, "transformed", false, "counters", new Object[]{}));
        List<JsonObject> players = List.of(
                object("id", ME, "name", "You", "life", 20, "handCount", hand.size(), "libraryCount", 20,
                        "battlefield", new Object[]{}, "graveyard", new Object[]{}, "exile", new Object[]{}),
                object("id", THEM, "name", "Opponent", "life", 20, "handCount", 2, "libraryCount", 20,
                        "battlefield", new Object[]{}, "graveyard", new Object[]{}, "exile", new Object[]{}));
        send(socket, object("type", "snapshot", "gameId", GAME, "playerId", ME, "revision", revision, "turn", 2,
                "phase", "END_TURN", "step", "CLEANUP", "activePlayerId", ME, "priorityPlayer", "You",
                "hand", cards, "stack", new Object[]{}, "players", players, "playableIds", new Object[]{}));
        if (hand.size() > 7) send(socket, object("type", "prompt", "id", "discard-" + revision,
                "method", "GAME_TARGET", "revision", revision, "message", "Select a card to discard", "queryType", "PICK_TARGET",
                "required", true, "supported", true, "choices", new Object[]{}, "cards", new Object[]{}, "targets", hand));
        else {
            send(socket, object("type", "promptCleared"));
            send(socket, object("type", "gameOver", "message", "Discard confirmed"));
        }
    }
    @Override public void onClose(WebSocket socket, int code, String reason, boolean remote) { observers.remove(socket); }
    @Override public void onError(WebSocket socket, Exception error) { error.printStackTrace(); }
    @Override public void onStart() { System.out.println("READY discard fixture " + getPort()); }
    public static void main(String[] args) throws Exception {
        DiscardPromptFixture server = new DiscardPromptFixture(args.length == 0 ? 17185 : Integer.parseInt(args[0]));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { try { server.stop(1000); } catch (Exception ignored) {} }));
        server.start();
    }
}
