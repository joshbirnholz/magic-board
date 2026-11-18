import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.util.UUID;

/** Deterministic phone-gesture fixture. Real-engine combat is checked separately by CombatSmoke. */
public final class BlockPromptFixture extends WebSocketServer {
    private static final Gson JSON = new Gson();
    private static final String ME = "00000000-0000-0000-0000-000000000001";
    private static final String THEM = "00000000-0000-0000-0000-000000000002";
    private static final String BLOCKER = "00000000-0000-0000-0000-000000000010";
    private static final String FIRST = "00000000-0000-0000-0000-000000000020";
    private static final String SECOND = "00000000-0000-0000-0000-000000000021";
    private static final String GAME = "00000000-0000-0000-0000-000000000100";
    private static final String TRIGGER_FIRST = "00000000-0000-0000-0000-000000000030";
    private static final String TRIGGER_SECOND = "00000000-0000-0000-0000-000000000031";
    private int revision = 1;
    private String selectedAttacker;
    private String stage = "select";
    private final String resumeToken = UUID.randomUUID().toString();
    private boolean hasGame;
    private String initialStage = "select";
    private boolean holdingPriority;
    private boolean autoOrderTriggers = true;

    private BlockPromptFixture(int port) { super(new InetSocketAddress("127.0.0.1", port), 1); }
    private static JsonObject object(Object... values) {
        JsonObject result = new JsonObject();
        for (int i = 0; i < values.length; i += 2) result.add(values[i].toString(), JSON.toJsonTree(values[i + 1]));
        return result;
    }
    private static void send(WebSocket socket, JsonObject value) { socket.send(JSON.toJson(value)); }
    @Override public void onOpen(WebSocket socket, ClientHandshake request) {
        if (!request.getFieldValue("Authorization").equals("Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))) { socket.close(1008, "Invalid key"); return; }
        initialStage = request.getResourceDescriptor().endsWith("/ordering") ? "order"
                : request.getResourceDescriptor().endsWith("/attack") ? "attack"
                : request.getResourceDescriptor().endsWith("/source") ? "sacrifice"
                : request.getResourceDescriptor().endsWith("/mana") ? "mana"
                : request.getResourceDescriptor().endsWith("/crew") ? "crew"
                : request.getResourceDescriptor().endsWith("/ability") ? "ability" : "select";
        send(socket, object("type", "hello", "protocolVersion", 1));
    }
    @Override public void onMessage(WebSocket socket, String text) {
        JsonObject request = JsonParser.parseString(text).getAsJsonObject();
        String type = request.get("type").getAsString();
        switch (type) {
            case "connect" -> {
                String resume = request.has("resumeToken") ? request.get("resumeToken").getAsString() : "";
                if (!resume.isEmpty() && !resume.equals(resumeToken)) {
                    send(socket, object("type", "error", "code", "sessionExpired", "message", "This game session expired."));
                    return;
                }
                send(socket, object("type", "ready", "protocolVersion", 1, "resumeToken", resumeToken, "formats", new String[]{"Limited"}));
                if (!resume.isEmpty() && hasGame) { snapshot(socket); prompt(socket); System.out.println("PASS resumed the retained game after app relaunch"); }
            }
            case "listTables" -> { send(socket, object("type", "tables", "tables", new Object[]{})); ack(socket, request); }
            case "createAiGame" -> {
                revision = 1; selectedAttacker = null; stage = initialStage; hasGame = true;
                holdingPriority = false; autoOrderTriggers = true;
                ack(socket, request); snapshot(socket); prompt(socket);
            }
            case "priorityControl" -> {
                holdingPriority = request.get("priorityAction").getAsString().equals("hold");
                settings(socket);
                ack(socket, request);
            }
            case "settings" -> { autoOrderTriggers = request.get("autoOrderTriggers").getAsBoolean(); settings(socket); ack(socket, request); }
            case "answer" -> {
                String value = request.get("value").getAsString();
                if (!request.get("kind").getAsString().equals("uuid")
                        || (stage.equals("select") && !value.equals(BLOCKER))
                        || (stage.equals("target") && !value.equals(FIRST) && !value.equals(SECOND))
                        || (stage.equals("order") && !value.equals(TRIGGER_FIRST) && !value.equals(TRIGGER_SECOND))) {
                    send(socket, object("type", "error", "requestId", request.get("requestId"), "message", "Unexpected fixture answer"));
                    return;
                }
                if (stage.equals("mana")) {
                    if (!value.equals(BLOCKER)) throw new AssertionError("Expected the mana source");
                    stage = "manaAdded";
                } else if (stage.equals("order")) {
                    stage = "select";
                    System.out.println("PASS ordering prompt selected an ability UUID from its card choices");
                } else if (stage.equals("select")) {
                    stage = "target";
                    System.out.println("PASS drag selected the blocker's UUID");
                } else {
                    selectedAttacker = value; stage = "done";
                    System.out.println("PASS drag answered the follow-up attacker target prompt");
                }
                revision++;
                send(socket, object("type", "promptCleared")); ack(socket, request);
                snapshot(socket); prompt(socket);
            }
            case "leave" -> { hasGame = false; socket.close(1000, "Done"); }
            case "resync" -> { ack(socket, request); snapshot(socket); prompt(socket); }
        }
    }
    private static void ack(WebSocket socket, JsonObject request) { send(socket, object("type", "ack", "requestId", request.get("requestId"))); }
    private void settings(WebSocket socket) { send(socket, object("type", "prioritySettings", "holdingPriority", holdingPriority, "autoOrderTriggers", autoOrderTriggers)); }
    private void prompt(WebSocket socket) {
        if (stage.equals("ability")) {
            send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", "GAME_SELECT",
                    "revision", revision, "message", "Play instants and activated abilities", "supported", true,
                    "choices", new Object[]{}, "cards", new Object[]{}, "targets", new Object[]{}));
            return;
        }
        if (stage.startsWith("mana")) {
            send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", "GAME_PLAY_MANA",
                    "revision", revision, "message", "Pay {B}<div>Mind Rot</div>", "supported", true,
                    "canCancel", true, "choices", new Object[]{}, "cards", new Object[]{}, "targets", new Object[]{}));
            return;
        }
        if (stage.equals("order")) {
            JsonObject first = card(TRIGGER_FIRST, false), second = card(TRIGGER_SECOND, false);
            for (JsonObject card : new JsonObject[]{first, second}) {
                card.addProperty("name", "Soul Warden"); card.addProperty("ability", true);
                card.addProperty("rules", "Whenever another creature enters, you gain 1 life.");
                card.remove("set"); card.remove("collectorNumber");
            }
            send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", "GAME_TARGET", "queryType", "PICK_ABILITY",
                    "revision", revision, "message", "Pick triggered ability (goes to the stack first)", "supported", true,
                    "required", true, "choices", new Object[]{}, "cards", new Object[]{first, second}, "targets", new Object[]{}));
            return;
        }
        if (stage.equals("crew")) {
            send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", "GAME_TARGET",
                    "revision", revision, "message", "Select another untapped creature you control (selected 0) (selected power 0 of 1)",
                    "subMessage", "Sky Skiff", "supported", true, "required", true,
                    "choices", new Object[]{}, "cards", new Object[]{}, "targets", new String[]{BLOCKER}));
            return;
        }
        if (stage.equals("sacrifice")) {
            send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", "GAME_TARGET",
                    "revision", revision, "message", "Select another creature or artifact (to sacrifice)",
                    "subMessage", "<font color='#696969' object_id='b95222bf-68a0-4769-8c28-4807c05cd345'>Ahriman</font> [b95]",
                    "supported", true, "required", true, "choices", new Object[]{}, "cards", new Object[]{}, "targets", new String[]{BLOCKER}));
            return;
        }
        send(socket, object("type", "prompt", "id", "fixture-" + revision, "method", stage.equals("target") ? "GAME_TARGET" : "GAME_SELECT",
                "revision", revision, "message", stage.equals("target") ? "Select attacker to block" : stage.equals("attack") ? "Select attackers" : "Select blockers", "supported", true,
                "specialActionAvailable", stage.equals("attack"), "specialActionLabel", "All attack",
                "required", stage.equals("target"), "choices", new Object[]{}, "cards", new Object[]{},
                "targets", stage.equals("target") ? new String[]{FIRST, SECOND} : new String[]{}));
    }
    private static JsonObject card(String id, boolean tapped) {
        return object("id", id, "name", "Silvercoat Lion", "set", "M10", "collectorNumber", "32", "faceDown", false,
                "transformed", false, "power", "2", "toughness", "2", "typeLine", "Creature — Cat", "manaCost", "{1}{W}",
                "tapped", tapped, "summoningSick", false, "counters", new Object[]{});
    }
    private void snapshot(WebSocket socket) {
        JsonObject mine = object("id", ME, "name", "You", "life", 20, "handCount", 0, "libraryCount", 30,
                "battlefield", new Object[]{card(BLOCKER, false)}, "graveyard", new Object[]{}, "exile", new Object[]{});
        if (stage.startsWith("mana")) {
            JsonObject land = card(BLOCKER, stage.equals("manaAdded"));
            land.addProperty("name", "Capital City"); land.addProperty("typeLine", "Land");
            land.remove("set"); land.remove("collectorNumber");
            mine.add("battlefield", JSON.toJsonTree(new Object[]{land}));
            mine.add("manaPool", object("C", stage.equals("manaAdded") ? 1 : 0));
        }
        JsonObject[] stack = new JsonObject[]{};
        if (stage.equals("ability")) {
            JsonObject source = card(BLOCKER, false);
            source.addProperty("name", "Ahriman"); source.remove("set"); source.remove("collectorNumber");
            mine.add("battlefield", JSON.toJsonTree(new Object[]{source}));
            JsonObject ability = source.deepCopy();
            ability.addProperty("id", TRIGGER_FIRST); ability.addProperty("ability", true);
            ability.addProperty("sourceId", BLOCKER); ability.addProperty("controllerId", ME);
            ability.addProperty("rules", "Draw a card.");
            stack = new JsonObject[]{ability};
        }
        JsonObject theirs = object("id", THEM, "name", "Opponent", "life", 20, "handCount", 0, "libraryCount", 30,
                "battlefield", new Object[]{card(FIRST, true), card(SECOND, true)}, "graveyard", new Object[]{}, "exile", new Object[]{});
        Object[] combat = (stage.equals("attack") || stage.startsWith("mana")) ? new Object[]{} : new Object[]{group(FIRST), group(SECOND)};
        send(socket, object("type", "snapshot", "gameId", GAME, "playerId", ME, "revision", revision, "turn", 4,
                "phase", "COMBAT", "step", stage.equals("attack") ? "DECLARE_ATTACKERS" : "DECLARE_BLOCKERS", "activePlayer", "Opponent", "activePlayerId", stage.equals("attack") ? ME : THEM, "priorityPlayer", "You",
                "hand", new Object[]{}, "stack", stack, "players", new Object[]{mine, theirs}, "playableIds", new String[]{BLOCKER}, "combat", combat));
    }
    private JsonObject group(String attacker) { return object("defenderId", ME, "attackers", new String[]{attacker}, "blockers", attacker.equals(selectedAttacker) ? new String[]{BLOCKER} : new String[]{}); }
    @Override public void onClose(WebSocket socket, int code, String reason, boolean remote) { }
    @Override public void onError(WebSocket socket, Exception error) { error.printStackTrace(); }
    @Override public void onStart() { System.out.println("Blocking fixture listening on " + getAddress()); }
    public static void main(String[] args) {
        BlockPromptFixture server = new BlockPromptFixture(Integer.parseInt(System.getenv().getOrDefault("RULES_FIXTURE_PORT", "17183")));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { try { server.stop(1000); } catch (InterruptedException ignored) { } }));
        server.start();
    }
}
