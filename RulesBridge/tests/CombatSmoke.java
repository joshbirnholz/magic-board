import com.google.gson.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Two real human seats: play creatures, declare an attacker, and assign a legal blocker. */
public final class CombatSmoke {
    public static void main(String[] args) throws Exception {
        try (BridgeTwoPlayerSmoke.Client attacker = new BridgeTwoPlayerSmoke.Client();
             BridgeTwoPlayerSmoke.Client defender = new BridgeTwoPlayerSmoke.Client()) {
            attacker.command("createHumanGame");
            JsonObject table = attacker.await("tableJoined"); attacker.await("ack");
            defender.send("{\"type\":\"joinTable\",\"requestId\":\"join\",\"tableId\":" + table.get("tableId") + "}");
            defender.await("tableJoined"); defender.await("ack");
            attacker.command("startMatch"); attacker.await("ack");
            boolean attacked = false, blocked = false;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90);
            while (!blocked && System.nanoTime() < deadline) {
                for (BridgeTwoPlayerSmoke.Client client : List.of(attacker, defender)) {
                    JsonObject event = client.events.poll(25, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    switch (event.get("type").getAsString()) {
                        case "snapshot" -> {
                            client.state = event;
                            for (JsonElement item : event.getAsJsonArray("combat")) {
                                JsonObject group = item.getAsJsonObject();
                                attacked |= !group.getAsJsonArray("attackers").isEmpty();
                                blocked |= !group.getAsJsonArray("blockers").isEmpty();
                            }
                        }
                        case "prompt" -> answer(client, event, client == attacker);
                        case "error", "gameOver" -> throw new AssertionError("Combat did not complete: " + event);
                    }
                }
            }
            if (!attacked || !blocked) throw new AssertionError("Missing combat: attacked=" + attacked + ", blocked=" + blocked);
            System.out.println("PASS two real seats cast creatures, declare attackers and assign a blocker through engine prompts");
        }
    }

    private static void answer(BridgeTwoPlayerSmoke.Client client, JsonObject prompt, boolean attackingSeat) {
        String method = prompt.get("method").getAsString();
        String message = text(prompt, "message").toLowerCase(Locale.ROOT);
        JsonObject me = null;
        for (JsonElement player : client.state.getAsJsonArray("players"))
            if (player.getAsJsonObject().get("id").equals(client.state.get("playerId"))) me = player.getAsJsonObject();
        String selection = null;
        if (method.equals("GAME_SELECT")) {
            if (message.contains("select attackers") && attackingSeat) {
                Set<String> declared = combatIds(client.state, "attackers");
                for (JsonElement item : me.getAsJsonArray("battlefield")) {
                    JsonObject card = item.getAsJsonObject();
                    if (creature(card) && !flag(card, "tapped") && !flag(card, "summoningSick") && !declared.contains(text(card, "id"))) {
                        selection = text(card, "id"); break;
                    }
                }
            } else if (message.contains("select blockers")) {
                Set<String> declared = combatIds(client.state, "blockers");
                for (JsonElement item : me.getAsJsonArray("battlefield")) {
                    JsonObject card = item.getAsJsonObject();
                    if (creature(card) && !flag(card, "tapped") && !declared.contains(text(card, "id"))) {
                        selection = text(card, "id"); break;
                    }
                }
            } else if (message.contains("play spells")) {
                Set<String> playable = new HashSet<>();
                client.state.getAsJsonArray("playableIds").forEach(id -> playable.add(id.getAsString()));
                for (JsonElement item : client.state.getAsJsonArray("hand")) {
                    if (playable.contains(text(item.getAsJsonObject(), "id"))) { selection = text(item.getAsJsonObject(), "id"); break; }
                }
            }
        } else if (method.equals("GAME_PLAY_MANA")) {
            for (JsonElement item : me.getAsJsonArray("battlefield")) {
                JsonObject card = item.getAsJsonObject();
                if (text(card, "typeLine").contains("Land") && !flag(card, "tapped")) { selection = text(card, "id"); break; }
            }
        } else if (method.equals("GAME_TARGET")) {
            if (!prompt.getAsJsonArray("targets").isEmpty()) selection = prompt.getAsJsonArray("targets").get(0).getAsString();
        }
        if (selection != null) client.answer(prompt, "uuid", new JsonPrimitive(selection));
        else if (Set.of("GAME_CHOOSE_CHOICE", "GAME_CHOOSE_ABILITY").contains(method))
            client.answer(prompt, "string", prompt.getAsJsonArray("choices").get(0).getAsJsonObject().get("id"));
        else if (method.equals("GAME_GET_AMOUNT")) client.answer(prompt, "integer", prompt.get("min"));
        else if (Set.of("GAME_SELECT", "GAME_ASK", "GAME_PLAY_MANA").contains(method))
            client.answer(prompt, "boolean", new JsonPrimitive(!message.contains("mulligan") && !method.equals("GAME_PLAY_MANA")));
        else throw new AssertionError("Unexpected prompt: " + prompt);
    }

    private static Set<String> combatIds(JsonObject state, String key) {
        Set<String> result = new HashSet<>();
        for (JsonElement group : state.getAsJsonArray("combat"))
            group.getAsJsonObject().getAsJsonArray(key).forEach(id -> result.add(id.getAsString()));
        return result;
    }
    private static boolean creature(JsonObject card) { return text(card, "typeLine").contains("Creature"); }
    private static boolean flag(JsonObject card, String key) { return card.has(key) && card.get(key).getAsBoolean(); }
    private static String text(JsonObject object, String key) { return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : ""; }
}
