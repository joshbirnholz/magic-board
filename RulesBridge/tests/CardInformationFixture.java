import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** UI fixture for transient information and engine-supplied card eligibility. */
public final class CardInformationFixture extends WebSocketServer {
    private static final Gson JSON = new Gson();
    private static final String ME = "00000000-0000-0000-0000-000000000001", THEM = "00000000-0000-0000-0000-000000000002";
    private static final String LAND = "00000000-0000-0000-0000-000000000030", SPELL = "00000000-0000-0000-0000-000000000031";
    private final Set<WebSocket> observers = ConcurrentHashMap.newKeySet(), choices = ConcurrentHashMap.newKeySet();
    private final Set<WebSocket> questions = ConcurrentHashMap.newKeySet();
    private int revision;
    private int answers;
    private boolean complete;
    private CardInformationFixture(int port) { super(new InetSocketAddress("127.0.0.1", port), 1); }
    private static JsonObject object(Object... pairs) {
        JsonObject result = new JsonObject();
        for (int i = 0; i < pairs.length; i += 2) result.add(pairs[i].toString(), JSON.toJsonTree(pairs[i + 1]));
        return result;
    }
    private static void send(WebSocket socket, JsonObject value) { socket.send(JSON.toJson(value)); }
    private synchronized void status(WebSocket socket) { send(socket, object("answers", answers, "complete", complete)); }
    @Override public void onOpen(WebSocket socket, ClientHandshake request) {
        if (!request.getFieldValue("Authorization").equals("Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))) { socket.close(1008, "Invalid key"); return; }
        if (request.getResourceDescriptor().endsWith("/observer")) { observers.add(socket); status(socket); return; }
        if (request.getResourceDescriptor().endsWith("/choice")) choices.add(socket);
        if (request.getResourceDescriptor().endsWith("/question")) questions.add(socket);
        send(socket, object("type", "hello", "protocolVersion", 1));
    }
    @Override public synchronized void onMessage(WebSocket socket, String text) {
        if (observers.contains(socket)) { status(socket); return; }
        JsonObject request = JsonParser.parseString(text).getAsJsonObject();
        switch (request.get("type").getAsString()) {
            case "connect" -> send(socket, object("type", "ready", "protocolVersion", 1, "resumeToken", "information-fixture"));
            case "listTables" -> { send(socket, object("type", "tables", "tables", new Object[]{})); ack(socket, request); }
            case "createAiGame" -> { revision = 0; answers = 0; complete = false; ack(socket, request); publish(socket); }
            case "answer" -> {
                answers++;
                boolean legalChoice = choices.contains(socket) && request.get("kind").getAsString().equals("uuid")
                        && request.get("value").getAsString().equals(SPELL);
                boolean answeredQuestion = questions.contains(socket) && request.get("kind").getAsString().equals("boolean")
                        && request.get("value").getAsBoolean();
                if (legalChoice || answeredQuestion) {
                    complete = true; ack(socket, request);
                    send(socket, object("type", "promptCleared"));
                    if (answeredQuestion) publish(socket);
                    else send(socket, object("type", "gameOver", "message", "Legal choice confirmed"));
                } else send(socket, object("type", "error", "message", "Information closes locally; only the eligible instant may be chosen"));
            }
            case "leave" -> socket.close(1000, "Done");
        }
    }
    private static void ack(WebSocket socket, JsonObject request) { send(socket, object("type", "ack", "requestId", request.get("requestId"))); }
    private static JsonObject card(String id, String name, String set, String number, String type) {
        return object("id", id, "name", name, "set", set, "collectorNumber", number, "typeLine", type,
                "faceDown", false, "transformed", false, "counters", new Object[]{});
    }
    private void publish(WebSocket socket) {
        List<JsonObject> cards = List.of(card(LAND, "Plains", "M10", "230", "Basic Land — Plains"),
                card(SPELL, "Revitalize", "J25", "244", "Instant"));
        List<JsonObject> players = new ArrayList<>();
        for (String id : List.of(ME, THEM)) players.add(object("id", id, "name", id.equals(ME) ? "You" : "Opponent",
                "life", 20, "handCount", 0, "libraryCount", 20, "battlefield", new Object[]{}, "graveyard", new Object[]{}, "exile", new Object[]{}));
        Object information = complete ? new Object[]{} : List.of(object("name", "Revealed cards", "cards", questions.contains(socket) ? List.of(cards.get(1)) : cards));
        JsonObject snapshot = object("type", "snapshot", "gameId", "00000000-0000-0000-0000-000000000100", "playerId", ME,
                "revision", ++revision, "turn", 3, "phase", "PRECOMBAT_MAIN", "step", "PRECOMBAT_MAIN", "activePlayerId", ME,
                "priorityPlayer", "You", "hand", new Object[]{}, "stack", new Object[]{}, "players", players,
                "playableIds", new Object[]{}, "lookedAt", information);
        send(socket, snapshot);
        snapshot.addProperty("revision", ++revision); snapshot.add("lookedAt", new JsonArray()); send(socket, snapshot);
        if (questions.contains(socket) && !complete) send(socket, object("type", "prompt", "id", "question", "revision", revision, "method", "GAME_ASK",
                "message", "Put Revitalize in your graveyard?", "required", false, "supported", true,
                "choices", new Object[]{}, "cards", List.of(cards.get(1)), "targets", new Object[]{}));
        else if (choices.contains(socket)) send(socket, object("type", "prompt", "id", "choice", "revision", revision, "method", "GAME_TARGET",
                "message", "Select a noncreature, nonland card", "required", true, "supported", true,
                "choices", new Object[]{}, "cards", cards, "targets", new Object[]{}, "selectionIds", new String[]{SPELL}, "selectedIds", new Object[]{}));
        else send(socket, object("type", "prompt", "id", "priority", "revision", revision, "method", "GAME_SELECT",
                "message", "Play spells and abilities", "supported", true, "choices", new Object[]{}));
    }
    @Override public void onClose(WebSocket socket, int code, String reason, boolean remote) { observers.remove(socket); choices.remove(socket); questions.remove(socket); }
    @Override public void onError(WebSocket socket, Exception error) { error.printStackTrace(); }
    @Override public void onStart() { System.out.println("READY information fixture " + getPort()); }
    public static void main(String[] args) throws Exception {
        CardInformationFixture server = new CardInformationFixture(args.length == 0 ? 17186 : Integer.parseInt(args[0]));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { try { server.stop(1000); } catch (Exception ignored) {} }));
        server.start();
    }
}
