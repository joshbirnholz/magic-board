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
    private static String name(JsonObject card) {
        return card.has("name") && !card.get("name").isJsonNull() ? card.get("name").getAsString() : "Face-down card";
    }
    private static long untappedLands(JsonObject state) {
        for (JsonElement item : state.getAsJsonArray("players")) {
            JsonObject player = item.getAsJsonObject();
            if (!player.get("id").equals(state.get("playerId"))) continue;
            return java.util.stream.StreamSupport.stream(player.getAsJsonArray("battlefield").spliterator(), false)
                    .map(JsonElement::getAsJsonObject)
                    .filter(card -> card.get("typeLine").getAsString().contains("Land") && !card.get("tapped").getAsBoolean()).count();
        }
        return 0;
    }
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
                .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17180")), test).orTimeout(10, TimeUnit.SECONDS).join();
        test.await("hello");
        test.send("{\"type\":\"connect\",\"protocolVersion\":1}");
        JsonObject ready = test.await("ready");
        System.out.println("PASS headless XMage login: " + ready.get("engineVersion"));
        if (System.getenv("RULES_SMOKE_MANUAL_TRIGGERS") != null) {
            test.send("{\"type\":\"settings\",\"requestId\":\"manual-triggers\",\"autoOrderTriggers\":false}");
            if (test.await("prioritySettings").get("autoOrderTriggers").getAsBoolean()) throw new AssertionError("Manual trigger ordering not enabled");
            test.await("ack");
        }
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
                .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17180")), test).orTimeout(10, TimeUnit.SECONDS).join();
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
        boolean resolvedCreature = false;
        boolean choseAbility = false;
        boolean requireAbility = System.getenv("RULES_SMOKE_ABILITY") != null;
        boolean finished = false;
        JsonObject currentState = resumed;
        JsonObject nextPrompt = resumedPrompt;
        long deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(3);
        int decisions = 0;
        Set<String> observedPrompts = new TreeSet<>();
        Set<String> requiredPrompts = new HashSet<>();
        if (System.getenv("RULES_SMOKE_REQUIRED_PROMPTS") != null)
            requiredPrompts.addAll(Arrays.asList(System.getenv("RULES_SMOKE_REQUIRED_PROMPTS").split(",")));
        boolean coverageOnly = System.getenv("RULES_SMOKE_COVERAGE_ONLY") != null;
        if (coverageOnly && requiredPrompts.isEmpty()) throw new IllegalArgumentException("Coverage-only runs require RULES_SMOKE_REQUIRED_PROMPTS");
        Deque<String> recent = new ArrayDeque<>();
        String lastFingerprint = "";
        int repeated = 0;
        int specialTrace = 0;
        Set<String> faceDownPermanents = new HashSet<>();
        String searchedCard = null;
        boolean searchOnStack = false, paidX = false;
        Set<String> myStackObjects = new HashSet<>(), theirStackObjects = new HashSet<>(), playablePermanents = new TreeSet<>(), playableHandCards = new TreeSet<>();
        while (!finished && System.nanoTime() < deadline && decisions < 1500) {
            if (nextPrompt != null) {
                JsonObject answer = new JsonObject();
                answer.addProperty("type", "answer");
                answer.addProperty("requestId", UUID.randomUUID().toString());
                answer.add("promptId", nextPrompt.get("id"));
                answer.add("revision", currentState.get("revision"));
                String method = nextPrompt.get("method").getAsString();
                if (coverageOnly && method.equals("GAME_SELECT") && observedPrompts.containsAll(requiredPrompts)) {
                    System.out.println("PASS required prompts answered and engine returned to priority: " + observedPrompts);
                    return;
                }
                if (observedPrompts.add(method)) System.out.println("Prompt type: " + method + " / " + nextPrompt.get("message"));
                if (nextPrompt.has("queryType")) {
                    String tag = method + "/" + nextPrompt.get("queryType").getAsString();
                    if (observedPrompts.add(tag)) System.out.println("Prompt query: " + tag);
                }
                if (String.valueOf(nextPrompt.get("message")).toLowerCase(Locale.ROOT).contains("exile a white card")) observedPrompts.add("ALTERNATIVE_COST");
                if (method.equals("GAME_CHOOSE_ABILITY")) choseAbility = true;
                String object = null;
                if (method.equals("GAME_SELECT") && currentState.get("step").getAsString().contains("MAIN")) {
                    Set<String> playable = new HashSet<>();
                    currentState.getAsJsonArray("playableIds").forEach(id -> playable.add(id.getAsString()));
                    for (JsonElement entry : currentState.getAsJsonArray("hand")) {
                        JsonObject card = entry.getAsJsonObject();
                        if (playable.contains(card.get("id").getAsString())) {
                            if (requiredPrompts.contains("NONZERO_X_SPELL_CAST") && name(card).equals("Blaze")
                                    && untappedLands(currentState) < 2) continue;
                            object = card.get("id").getAsString();
                            if (card.get("typeLine").getAsString().contains("Land")) playedLand = true;
                            else if (card.get("typeLine").getAsString().contains("Creature")) castCreature = true;
                            break;
                        }
                    }
                    if (System.getenv("RULES_SMOKE_SPECIAL_ACTION") != null
                            && currentState.get("activePlayerId").equals(currentState.get("playerId"))
                            && currentState.getAsJsonArray("stack").isEmpty()) {
                        int mana = 0;
                        for (JsonElement player : currentState.getAsJsonArray("players")) {
                            if (!player.getAsJsonObject().get("id").equals(currentState.get("playerId"))) continue;
                            for (JsonElement entry : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                                JsonObject card = entry.getAsJsonObject();
                                if (card.get("typeLine").getAsString().contains("Land") && !card.get("tapped").getAsBoolean()) mana++;
                            }
                        }
                        if (mana >= 3) for (JsonElement entry : currentState.getAsJsonArray("hand")) {
                            JsonObject card = entry.getAsJsonObject();
                            if (name(card).equals("Gathan Raiders")) { object = card.get("id").getAsString(); break; }
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
                        && nextPrompt.getAsJsonArray("targets").size() > 0) {
                    object = nextPrompt.getAsJsonArray("targets").get(0).getAsString();
                }
                if (method.equals("GAME_TARGET") && object == null
                        && !nextPrompt.getAsJsonArray("cards").isEmpty()) {
                    object = nextPrompt.getAsJsonArray("cards").get(0).getAsJsonObject().get("id").getAsString();
                    if (searchOnStack) searchedCard = object;
                }
                // Morph's turn-face-up special action is attached to the permanent in XMage;
                // selecting that permanent opens its cost prompts, just like tapping it in the app.
                if (System.getenv("RULES_SMOKE_SPECIAL_ACTION") != null && method.equals("GAME_SELECT")
                        && nextPrompt.get("message").getAsString().startsWith("Play ") && !currentState.getAsJsonArray("hand").isEmpty()) {
                    for (JsonElement player : currentState.getAsJsonArray("players")) {
                        if (!player.getAsJsonObject().get("id").equals(currentState.get("playerId"))) continue;
                        for (JsonElement entry : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                            JsonObject card = entry.getAsJsonObject();
                            if (card.get("faceDown").getAsBoolean()) {
                                object = card.get("id").getAsString();
                                if (!currentState.getAsJsonArray("playableIds").contains(new JsonPrimitive(object)))
                                    throw new AssertionError("The face-up action is missing from the phone's playable hints");
                                observedPrompts.add("SPECIAL_ACTION"); specialTrace = 8; break;
                            }
                        }
                    }
                }
                if (System.getenv("RULES_SMOKE_SPECIAL_ACTION") != null && method.equals("GAME_SELECT")
                        && !observedPrompts.contains("MORPH_REVEALED") && nextPrompt.has("specialActionAvailable")
                        && nextPrompt.get("specialActionAvailable").getAsBoolean()
                        && nextPrompt.has("specialActionLabel") && nextPrompt.get("specialActionLabel").getAsString().equals("Special action")) {
                    observedPrompts.add("SPECIAL_ACTION");
                    specialTrace = 8;
                    answer.addProperty("kind", "special"); answer.addProperty("value", true);
                } else if (object != null) {
                    answer.addProperty("kind", "uuid"); answer.addProperty("value", object);
                } else if (method.equals("GAME_CHOOSE_CHOICE") || method.equals("GAME_CHOOSE_ABILITY")) {
                    answer.addProperty("kind", "string");
                    JsonObject selected = nextPrompt.getAsJsonArray("choices").get(0).getAsJsonObject();
                    for (JsonElement item : nextPrompt.getAsJsonArray("choices")) {
                        JsonObject choice = item.getAsJsonObject();
                        String label = choice.get("label").getAsString().replaceAll("<[^>]*>", "").trim();
                        String lower = label.toLowerCase(Locale.ROOT);
                        if (label.equalsIgnoreCase("Done") || lower.contains("exile a white card")
                                || (System.getenv("RULES_SMOKE_SPECIAL_ACTION") != null && (lower.contains("morph") || lower.contains("face down") || lower.contains("face-down")))) {
                            selected = choice; break;
                        }
                    }
                    if (selected.get("label").getAsString().toLowerCase(Locale.ROOT).contains("exile a white card")) observedPrompts.add("ALTERNATIVE_COST");
                    answer.add("value", selected.get("id"));
                } else if (method.equals("GAME_GET_AMOUNT")) {
                    int amount = nextPrompt.get("min").getAsInt();
                    if (requiredPrompts.contains("NONZERO_X_SPELL_CAST") && nextPrompt.get("message").getAsString().contains("{X}")) {
                        amount = Math.min(nextPrompt.get("max").getAsInt(), Math.max(1, amount));
                        paidX = amount > 0;
                    }
                    answer.addProperty("kind", "integer"); answer.addProperty("value", amount);
                } else if (method.equals("GAME_PLAY_MANA") || method.equals("GAME_PLAY_XMANA") && !paidX) {
                    for (JsonElement player : currentState.getAsJsonArray("players")) {
                        if (!player.getAsJsonObject().get("id").equals(currentState.get("playerId"))) continue;
                        for (JsonElement entry : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                            JsonObject card = entry.getAsJsonObject();
                            if (card.get("typeLine").getAsString().contains("Land") && !card.get("tapped").getAsBoolean()) { object = card.get("id").getAsString(); break; }
                        }
                    }
                    if (object != null) {
                        answer.addProperty("kind", "uuid"); answer.addProperty("value", object);
                        if (method.equals("GAME_PLAY_XMANA")) paidX = true;
                    }
                    else { answer.addProperty("kind", "boolean"); answer.addProperty("value", false); }
                } else {
                    answer.addProperty("kind", "boolean");
                    boolean yes = method.equals("GAME_SELECT") || method.equals("GAME_PLAY_XMANA")
                            || method.equals("GAME_ASK") && !nextPrompt.get("message").getAsString().toLowerCase().contains("mulligan");
                    answer.addProperty("value", yes);
                }
                JsonArray offered = new JsonArray();
                if (nextPrompt.has("cards")) nextPrompt.getAsJsonArray("cards").forEach(card -> offered.add(card.getAsJsonObject().get("id")));
                String diagnostic = method + " query=" + nextPrompt.get("queryType") + " / " + nextPrompt.get("message") + " -> " + answer.get("kind") + " " + answer.get("value")
                        + " targets=" + nextPrompt.get("targets") + " cards=" + offered;
                if (recent.size() == 6) recent.removeFirst();
                recent.add(diagnostic);
                String fingerprint = diagnostic + currentState.get("turn") + currentState.get("hand") + currentState.get("players") + currentState.get("stack");
                repeated = fingerprint.equals(lastFingerprint) ? repeated + 1 : 0;
                lastFingerprint = fingerprint;
                if (repeated >= 32) throw new AssertionError("Engine made no progress after repeated test answers: " + recent);
                if (decisions < 20 || specialTrace > 0) System.out.println("Decision " + decisions + ": " + diagnostic);
                if (specialTrace > 0) specialTrace--;
                test.send(answer.toString());
                nextPrompt = null;
                decisions++;
            }
            JsonObject event = test.events.poll(1, TimeUnit.SECONDS);
            if (event == null) continue;
            switch (event.get("type").getAsString()) {
                case "snapshot" -> {
                    currentState = event;
                    if (System.getenv("RULES_SMOKE_DECK") == null) {
                        for (JsonElement entry : event.getAsJsonArray("hand")) {
                            String name = name(entry.getAsJsonObject());
                            if (!Set.of("Plains", "Silvercoat Lion", "Siege Mastodon").contains(name))
                                throw new AssertionError("Built-in deck loaded an incorrect printing: " + name);
                        }
                    }
                    String me = event.get("playerId").getAsString();
                    Set<String> playable = new HashSet<>();
                    event.getAsJsonArray("playableIds").forEach(id -> playable.add(id.getAsString()));
                    for (JsonElement card : event.getAsJsonArray("hand"))
                        if (playable.contains(card.getAsJsonObject().get("id").getAsString())) playableHandCards.add(name(card.getAsJsonObject()));
                    if (searchedCard != null) for (JsonElement card : event.getAsJsonArray("hand"))
                        if (card.getAsJsonObject().get("id").getAsString().equals(searchedCard)) observedPrompts.add("LIBRARY_CARD_TO_HAND");
                    for (JsonElement player : event.getAsJsonArray("players")) {
                        if (!player.getAsJsonObject().get("id").getAsString().equals(me)) continue;
                        for (JsonElement card : player.getAsJsonObject().getAsJsonArray("battlefield")) {
                            JsonObject permanent = card.getAsJsonObject();
                            if (permanent.get("faceDown").getAsBoolean()) faceDownPermanents.add(permanent.get("id").getAsString());
                            if (System.getenv("RULES_SMOKE_SPECIAL_ACTION") != null
                                    && faceDownPermanents.contains(permanent.get("id").getAsString())
                                    && !permanent.get("faceDown").getAsBoolean()) observedPrompts.add("MORPH_REVEALED");
                            if (permanent.get("typeLine").getAsString().contains("Creature")) resolvedCreature = true;
                            if (playable.contains(permanent.get("id").getAsString())) playablePermanents.add(name(permanent));
                        }
                    }
                    for (JsonElement item : event.getAsJsonArray("stack")) {
                        JsonObject object = item.getAsJsonObject();
                        if (!object.has("controllerId")) throw new AssertionError("Stack object without a controller: " + object.get("name"));
                        if (object.get("controllerId").getAsString().equals(me)) {
                            myStackObjects.add(object.get("id").getAsString());
                            if (name(object).equals("Blessed Alliance")) observedPrompts.add("MODAL_SPELL_CAST");
                            if (name(object).equals("Reverent Mantra")) observedPrompts.add("ALTERNATIVE_SPELL_CAST");
                            if (name(object).equals("Blaze") && paidX) observedPrompts.add("NONZERO_X_SPELL_CAST");
                            if (name(object).equals("Safehold Elite")) observedPrompts.add("HYBRID_SPELL_CAST");
                            if (name(object).equals("Sylvan Scrying")) searchOnStack = true;
                        }
                        else theirStackObjects.add(object.get("id").getAsString());
                    }
                }
                case "prompt" -> nextPrompt = event;
                case "gameOver" -> {
                    if (event.toString().toLowerCase(Locale.ROOT).contains("server error"))
                        throw new AssertionError("Engine stopped the game with an error: " + event);
                    finished = true;
                }
                case "error" -> throw new AssertionError(event);
            }
        }
        System.out.println("INFO prompt coverage: " + observedPrompts);
        if (!finished || !observedPrompts.containsAll(requiredPrompts)) {
            System.out.println("INFO probe state: turn=" + currentState.get("turn") + " phase=" + currentState.get("phase") + " step=" + currentState.get("step")
                    + " active=" + currentState.get("activePlayer") + " priority=" + currentState.get("priorityPlayer") + " hand=" + currentState.get("hand") + " stack=" + currentState.get("stack"));
            for (JsonElement player : currentState.getAsJsonArray("players")) {
                JsonObject p = player.getAsJsonObject();
                System.out.println("INFO player " + p.get("name") + " life=" + p.get("life") + " hand=" + p.get("handCount") + " library=" + p.get("libraryCount") + " battlefield=" + p.getAsJsonArray("battlefield").size());
            }
        }
        if (!finished || !playedLand || !castCreature || !resolvedCreature) throw new AssertionError("Incomplete game: finished=" + finished + ", land=" + playedLand + ", creatureCast=" + castCreature + ", creatureResolved=" + resolvedCreature + ", ability=" + choseAbility + ", decisions=" + decisions + ", recent=" + recent);
        if (requireAbility && !choseAbility) throw new AssertionError("The engine ability chooser was not exercised");
        if (!observedPrompts.containsAll(requiredPrompts)) throw new AssertionError("Missing required prompts " + requiredPrompts + "; observed " + observedPrompts);
        if (choseAbility) System.out.println("PASS engine ability selection uses UUID responses");
        if (castCreature && myStackObjects.isEmpty()) throw new AssertionError("Our own spells were never attributed to us on the stack");
        System.out.println("INFO playable hand cards: " + playableHandCards + "; playable permanents: " + playablePermanents);
        if (playableHandCards.isEmpty()) throw new AssertionError("No hand card was ever reported playable");
        if (playablePermanents.contains("Plains")) throw new AssertionError("A basic land's mana ability alone made it playable");
        System.out.println("PASS stack controllers: " + myStackObjects.size() + " ours, " + theirStackObjects.size() + " the AI's");
        System.out.println("PASS full AI game: land play, creature casting, mana, priority and engine game-over (" + decisions + " decisions)");
        test.send("{\"type\":\"resync\",\"requestId\":\"finished-replay\"}");
        test.await("gameOver");
        System.out.println("PASS completed-game replay includes game-over");
        test.send("{\"type\":\"leave\"}");
        test.socket.sendClose(1000, "Done").join();
        CompletableFuture<Integer> unauthorizedClose = new CompletableFuture<>();
        WebSocket unauthorized = HttpClient.newHttpClient().newWebSocketBuilder()
                .header("Authorization", "Bearer invalid-key")
                .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17180")), new WebSocket.Listener() {
                    public CompletionStage<?> onClose(WebSocket socket, int code, String reason) {
                        unauthorizedClose.complete(code);
                        return null;
                    }
                }).orTimeout(10, TimeUnit.SECONDS).join();
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
