import com.google.gson.*;
import java.net.URI;
import java.net.http.*;
import java.util.*;
import java.util.concurrent.*;

/** Runs against the real local bridge/server, never against a simulated rules engine. */
public final class BridgeSmoke implements WebSocket.Listener {
    private final BlockingQueue<JsonObject> events = new LinkedBlockingQueue<>();
    private final StringBuilder fragments = new StringBuilder();
    private WebSocket socket;
    public CompletionStage<?> onText(WebSocket socket, CharSequence data, boolean last) {
        fragments.append(data);
        if (last) {
            events.add(JsonParser.parseString(fragments.toString()).getAsJsonObject());
            fragments.setLength(0);
        }
        socket.request(1);
        return null;
    }
    private void send(String text) { socket.sendText(text, true).join(); }
    private JsonObject await(String type) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
        while (System.nanoTime() < deadline) {
            JsonObject event = events.poll(1, TimeUnit.SECONDS);
            if (event == null) continue;
            String actual = event.get("type").getAsString();
            if (actual.equals(type)) return event;
            if (actual.equals("error")) throw new AssertionError(event);
        }
        throw new AssertionError("Timed out waiting for " + type);
    }
    public static void main(String[] args) throws Exception {
        BridgeSmoke test = new BridgeSmoke();
        try {
        test.socket = HttpClient.newHttpClient().newWebSocketBuilder()
                .header("Authorization", "Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))
                .buildAsync(URI.create("ws://127.0.0.1:17180"), test).join();
        test.await("hello");
        test.send("{\"type\":\"connect\",\"protocolVersion\":1}");
        JsonObject ready = test.await("ready");
        System.out.println("PASS headless XMage login: " + ready.get("engineVersion"));
        String request = UUID.randomUUID().toString();
        JsonObject create = new JsonObject();
        create.addProperty("type", "createAiGame"); create.addProperty("requestId", request);
        if (System.getenv("RULES_SMOKE_DECK") != null) {
            JsonObject config = JsonParser.parseString(java.nio.file.Files.readString(java.nio.file.Path.of(System.getenv("RULES_SMOKE_DECK")))).getAsJsonObject();
            create.add("deck", config.get("deck")); create.add("format", config.get("format"));
        }
        test.send(create.toString());
        test.await("ack");
        JsonObject state = test.await("snapshot");
        if (System.getenv("RULES_SMOKE_SNAPSHOT") != null)
            java.nio.file.Files.writeString(java.nio.file.Path.of(System.getenv("RULES_SMOKE_SNAPSHOT")), state.toString());
        if (state.getAsJsonArray("players").size() != 2) throw new AssertionError("Expected two players");
        for (JsonElement player : state.getAsJsonArray("players"))
            if (player.getAsJsonObject().has("hand")) throw new AssertionError("Private hands must not be in player summaries");
        System.out.println("PASS real AI game snapshot with filtered player summaries");
        JsonObject prompt = test.await("prompt");
        System.out.println("PASS engine prompt: " + prompt.get("method") + " " + prompt.get("message"));
        // Duplicate game creation must acknowledge the original request without creating a new table.
        test.send("{\"type\":\"createAiGame\",\"requestId\":\"" + request + "\"}");
        test.await("ack");
        System.out.println("PASS duplicate command receipt");
        test.socket.sendClose(1000, "Reconnect verification").join();
        test.events.clear();
        test.socket = HttpClient.newHttpClient().newWebSocketBuilder()
                .header("Authorization", "Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))
                .buildAsync(URI.create("ws://127.0.0.1:17180"), test).join();
        test.await("hello");
        test.send("{\"type\":\"connect\",\"protocolVersion\":1,\"resumeToken\":" + ready.get("resumeToken") + "}");
        test.await("ready");
        JsonObject resumed = test.await("snapshot");
        if (!state.get("gameId").equals(resumed.get("gameId"))) throw new AssertionError("Reconnect changed game");
        JsonObject resumedPrompt = test.await("prompt");
        if (!prompt.get("id").equals(resumedPrompt.get("id"))) throw new AssertionError("Reconnect lost prompt");
        System.out.println("PASS reconnect restores the same game and pending prompt");
        test.send("{\"type\":\"answer\",\"requestId\":\"stale-choice\",\"promptId\":\"expired\",\"revision\":"
                + resumed.get("revision") + ",\"kind\":\"boolean\",\"value\":false}");
        JsonObject rejection = test.await("error");
        if (!rejection.get("requestId").getAsString().equals("stale-choice")) throw new AssertionError(rejection);
        resumed = test.await("snapshot");
        resumedPrompt = test.await("prompt");
        if (!prompt.get("id").equals(resumedPrompt.get("id"))) throw new AssertionError("Rejected stale answer changed the prompt");
        System.out.println("PASS stale answer rejected and current state replayed");
        // Play the simple deck until the real engine ends the game. Combat can be passed;
        // the AI supplies attacks. This checks the entire lifecycle, not AI playing strength.
        boolean playedLand = false;
        boolean castCreature = false;
        boolean choseAbility = false;
        boolean requireAbility = System.getenv("RULES_SMOKE_ABILITY") != null;
        boolean finished = false;
        JsonObject currentState = resumed;
        JsonObject nextPrompt = resumedPrompt;
        long deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(3);
        int decisions = 0;
        while (!finished && System.nanoTime() < deadline && decisions < 1500) {
            if (nextPrompt != null) {
                JsonObject answer = new JsonObject();
                answer.addProperty("type", "answer");
                answer.addProperty("requestId", UUID.randomUUID().toString());
                answer.add("promptId", nextPrompt.get("id"));
                answer.add("revision", currentState.get("revision"));
                String method = nextPrompt.get("method").getAsString();
                if (method.equals("GAME_CHOOSE_ABILITY")) choseAbility = true;
                String object = null;
                if (method.equals("GAME_SELECT") && currentState.get("step").getAsString().contains("MAIN")) {
                    Set<String> playable = new HashSet<>();
                    currentState.getAsJsonArray("playableIds").forEach(id -> playable.add(id.getAsString()));
                    for (JsonElement entry : currentState.getAsJsonArray("hand")) {
                        JsonObject card = entry.getAsJsonObject();
                        if (playable.contains(card.get("id").getAsString())) {
                            object = card.get("id").getAsString();
                            if (card.get("typeLine").getAsString().contains("Land")) playedLand = true;
                            else castCreature = true;
                            break;
                        }
                    }
                    if (requireAbility && !choseAbility) {
                        for (JsonElement player : currentState.getAsJsonArray("players")) {
                            if (!player.getAsJsonObject().get("id").equals(currentState.get("playerId"))) continue;
                            for (JsonElement entry : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                                JsonObject card = entry.getAsJsonObject();
                                if (card.get("typeLine").getAsString().contains("Land") && !card.get("tapped").getAsBoolean()) { object = card.get("id").getAsString(); break; }
                            }
                        }
                    }
                }
                if (method.equals("GAME_TARGET") && nextPrompt.has("targets")
                        && nextPrompt.getAsJsonArray("targets").size() > 0
                        && (nextPrompt.get("required").getAsBoolean()
                            || nextPrompt.get("message").getAsString().contains("starting player"))) {
                    object = nextPrompt.getAsJsonArray("targets").get(0).getAsString();
                }
                if (object != null) {
                    answer.addProperty("kind", "uuid"); answer.addProperty("value", object);
                } else if (method.equals("GAME_CHOOSE_CHOICE") || method.equals("GAME_CHOOSE_ABILITY")) {
                    answer.addProperty("kind", "string");
                    answer.add("value", nextPrompt.getAsJsonArray("choices").get(0).getAsJsonObject().get("id"));
                } else if (method.equals("GAME_GET_AMOUNT")) {
                    answer.addProperty("kind", "integer"); answer.add("value", nextPrompt.get("min"));
                } else if (method.equals("GAME_PLAY_MANA")) {
                    for (JsonElement player : currentState.getAsJsonArray("players")) {
                        if (!player.getAsJsonObject().get("id").equals(currentState.get("playerId"))) continue;
                        for (JsonElement entry : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                            JsonObject card = entry.getAsJsonObject();
                            if (card.get("typeLine").getAsString().contains("Land") && !card.get("tapped").getAsBoolean()) { object = card.get("id").getAsString(); break; }
                        }
                    }
                    if (object != null) { answer.addProperty("kind", "uuid"); answer.addProperty("value", object); }
                    else { answer.addProperty("kind", "boolean"); answer.addProperty("value", false); }
                } else {
                    answer.addProperty("kind", "boolean");
                    boolean yes = method.equals("GAME_SELECT") || method.equals("GAME_PLAY_XMANA")
                            || method.equals("GAME_ASK") && !nextPrompt.get("message").getAsString().toLowerCase().contains("mulligan");
                    answer.addProperty("value", yes);
                }
                if (decisions < 20) System.out.println("Decision " + decisions + ": " + method + " / " + nextPrompt.get("message") + " -> " + answer.get("kind") + " " + answer.get("value"));
                test.send(answer.toString());
                nextPrompt = null;
                decisions++;
            }
            JsonObject event = test.events.poll(1, TimeUnit.SECONDS);
            if (event == null) continue;
            switch (event.get("type").getAsString()) {
                case "snapshot" -> currentState = event;
                case "prompt" -> nextPrompt = event;
                case "gameOver" -> finished = true;
                case "error" -> throw new AssertionError(event);
            }
        }
        if (!finished || !playedLand || !castCreature) throw new AssertionError("Incomplete game: finished=" + finished + ", land=" + playedLand + ", creature=" + castCreature + ", ability=" + choseAbility + ", decisions=" + decisions);
        if (requireAbility && !choseAbility) throw new AssertionError("The engine ability chooser was not exercised");
        if (choseAbility) System.out.println("PASS engine ability selection uses UUID responses");
        System.out.println("PASS full AI game: land play, creature casting, mana, priority and engine game-over (" + decisions + " decisions)");
        test.send("{\"type\":\"leave\"}");
        test.socket.sendClose(1000, "Done").join();
        CompletableFuture<Integer> unauthorizedClose = new CompletableFuture<>();
        WebSocket unauthorized = HttpClient.newHttpClient().newWebSocketBuilder()
                .header("Authorization", "Bearer invalid-key")
                .buildAsync(URI.create("ws://127.0.0.1:17180"), new WebSocket.Listener() {
                    public CompletionStage<?> onClose(WebSocket socket, int code, String reason) {
                        unauthorizedClose.complete(code);
                        return null;
                    }
                }).join();
        if (unauthorizedClose.get(5, TimeUnit.SECONDS) != 1008) throw new AssertionError("Unauthorized connection accepted");
        unauthorized.abort();
        System.out.println("PASS invalid connection key rejected");
        } finally {
            if (test.socket != null && !test.socket.isOutputClosed()) {
                try { test.send("{\"type\":\"leave\"}"); } catch (Exception ignored) { }
                test.socket.abort();
            }
        }
    }
}
