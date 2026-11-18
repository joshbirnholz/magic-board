import com.google.gson.*;
import java.net.URI;
import java.net.http.*;
import java.util.*;
import java.util.concurrent.*;

/**
 * A second human seat for the phone's two-player UI check (`testRulesTwoPlayerGameAgainstASecondSeat`).
 * It waits for the phone's waiting game, joins it, then plays simply: keeps, plays a playable hand
 * card each main phase, pays with untapped lands, declines blocks and passes otherwise. It is a
 * test driver, not a rules engine: XMage still decides everything.
 *
 * Run from RulesBridge/ after building tests (see README):
 *   RULES_BRIDGE_TOKEN=… java -cp "build/test-classes:build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" SecondSeatBot
 */
public final class SecondSeatBot implements WebSocket.Listener {
    private final BlockingQueue<JsonObject> events = new LinkedBlockingQueue<>();
    private final StringBuilder fragments = new StringBuilder();
    private WebSocket socket;

    public CompletionStage<?> onText(WebSocket socket, CharSequence text, boolean last) {
        fragments.append(text);
        if (last) { events.add(JsonParser.parseString(fragments.toString()).getAsJsonObject()); fragments.setLength(0); }
        socket.request(1);
        return null;
    }

    private void send(JsonObject message) { socket.sendText(message.toString(), true).join(); }
    private void command(String type) { send(object("type", type, "requestId", UUID.randomUUID().toString())); }

    private static JsonObject object(String... pairs) {
        JsonObject result = new JsonObject();
        for (int i = 0; i < pairs.length; i += 2) result.addProperty(pairs[i], pairs[i + 1]);
        return result;
    }

    private static String string(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : "";
    }

    public static void main(String[] args) throws Exception {
        SecondSeatBot bot = new SecondSeatBot();
        bot.socket = HttpClient.newHttpClient().newWebSocketBuilder()
                .header("Authorization", "Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))
                .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17180")), bot)
                .orTimeout(10, TimeUnit.SECONDS).join();
        JsonObject connect = object("type", "connect");
        connect.addProperty("protocolVersion", 1);
        bot.send(connect);
        long deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(Long.parseLong(System.getenv().getOrDefault("SECOND_SEAT_MINUTES", "15")));
        boolean joined = false;
        JsonObject state = null, prompt = null;
        Set<String> tried = new HashSet<>();
        long nextPoll = 0;
        int answered = 0;
        while (System.nanoTime() < deadline) {
            if (!joined && System.nanoTime() > nextPoll) { bot.command("listTables"); nextPoll = System.nanoTime() + TimeUnit.SECONDS.toNanos(1); }
            if (prompt != null && state != null) {
                bot.answer(prompt, state, tried);
                prompt = null;
                answered++;
            }
            JsonObject event = bot.events.poll(1, TimeUnit.SECONDS);
            if (event == null) continue;
            switch (string(event, "type")) {
                case "tables" -> {
                    if (joined) break;
                    for (JsonElement entry : event.getAsJsonArray("tables")) {
                        JsonObject table = entry.getAsJsonObject();
                        if (table.get("players").getAsInt() < table.get("capacity").getAsInt()) {
                            JsonObject join = object("type", "joinTable", "requestId", UUID.randomUUID().toString(), "tableId", string(table, "id"));
                            bot.send(join);
                            joined = true;
                            System.out.println("BOT joined " + string(table, "id"));
                            break;
                        }
                    }
                }
                case "snapshot" -> state = event;
                case "prompt" -> prompt = event;
                case "gameOver" -> { System.out.println("BOT game over: " + string(event, "message") + " after " + answered + " answers"); deadline = 0; }
                case "error" -> System.out.println("BOT error: " + event);
                default -> { }
            }
        }
        bot.send(object("type", "leave"));
        System.exit(0);
    }

    private void answer(JsonObject prompt, JsonObject state, Set<String> tried) {
        String method = string(prompt, "method"), message = string(prompt, "message").toLowerCase(Locale.ROOT);
        String me = string(state, "playerId");
        JsonArray field = new JsonArray();
        for (JsonElement player : state.getAsJsonArray("players"))
            if (string(player.getAsJsonObject(), "id").equals(me)) field = player.getAsJsonObject().getAsJsonArray("battlefield");
        String object = null;
        if (method.equals("GAME_SELECT") && message.contains("play spells")) {
            Set<String> playable = new HashSet<>();
            state.getAsJsonArray("playableIds").forEach(id -> playable.add(id.getAsString()));
            for (JsonElement card : state.getAsJsonArray("hand")) {
                String id = string(card.getAsJsonObject(), "id");
                if (playable.contains(id) && tried.add(state.get("turn") + ":" + id)) { object = id; break; }
            }
        } else if (method.equals("GAME_PLAY_MANA")) {
            for (JsonElement card : field) {
                JsonObject permanent = card.getAsJsonObject();
                if (string(permanent, "typeLine").contains("Land") && !permanent.get("tapped").getAsBoolean()) { object = string(permanent, "id"); break; }
            }
        } else if (method.equals("GAME_TARGET") && prompt.has("targets") && prompt.getAsJsonArray("targets").size() > 0
                && (prompt.has("required") && prompt.get("required").getAsBoolean() || message.contains("starting player"))) {
            object = prompt.getAsJsonArray("targets").get(0).getAsString();
        }
        JsonObject answer = object("type", "answer", "requestId", UUID.randomUUID().toString());
        answer.add("promptId", prompt.get("id"));
        answer.add("revision", state.get("revision"));
        if (object != null) { answer.addProperty("kind", "uuid"); answer.addProperty("value", object); }
        else if (method.equals("GAME_CHOOSE_CHOICE") || method.equals("GAME_CHOOSE_ABILITY")) {
            answer.addProperty("kind", "string");
            answer.add("value", prompt.getAsJsonArray("choices").get(0).getAsJsonObject().get("id"));
        } else {
            answer.addProperty("kind", "boolean");
            // Keep the opening hand, pass priority and confirm "no blocks"; refuse optional extras.
            answer.addProperty("value", method.equals("GAME_SELECT") || (method.equals("GAME_ASK") && !message.contains("mulligan")));
        }
        send(answer);
    }
}
