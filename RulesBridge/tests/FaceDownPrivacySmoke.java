import com.google.gson.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Two real seats: an opponent must not learn a morph creature's identity from its public card view. */
public final class FaceDownPrivacySmoke {
    public static void main(String[] args) throws Exception {
        JsonObject create = JsonParser.parseString(Files.readString(Path.of(args.length == 0 ? "tests/decks/morph.json" : args[0]))).getAsJsonObject();
        create.addProperty("type", "createHumanGame"); create.addProperty("requestId", "private-morph");
        try (var owner = new BridgeTwoPlayerSmoke.Client(); var opponent = new BridgeTwoPlayerSmoke.Client()) {
            owner.send(create.toString());
            var table = owner.await("tableJoined"); owner.await("ack");
            opponent.send("{\"type\":\"joinTable\",\"requestId\":\"join\",\"tableId\":" + table.get("tableId") + "}");
            opponent.await("tableJoined"); opponent.await("ack");
            owner.command("startMatch"); owner.await("ack");
            Set<String> privatePrintings = new HashSet<>();
            JsonObject mine = null, theirs = null;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90);
            while (System.nanoTime() < deadline) {
                for (var client : List.of(owner, opponent)) {
                    JsonObject event = client.events.poll(25, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    switch (text(event, "type")) {
                        case "snapshot" -> {
                            client.state = event;
                            if (client == owner) for (JsonElement item : event.getAsJsonArray("hand")) {
                                JsonObject card = item.getAsJsonObject();
                                if (text(card, "name").equals("Gathan Raiders")) privatePrintings.add(printing(card));
                            }
                            for (JsonElement player : event.getAsJsonArray("players")) {
                                JsonObject view = player.getAsJsonObject();
                                boolean ownBoard = view.get("id").equals(event.get("playerId"));
                                if (ownBoard != (client == owner)) continue;
                                for (JsonElement card : view.getAsJsonArray("battlefield")) {
                                    JsonObject permanent = card.getAsJsonObject();
                                    if (permanent.get("faceDown").getAsBoolean()) {
                                        if (client == owner) mine = permanent; else theirs = permanent;
                                    }
                                }
                            }
                        }
                        case "prompt" -> {
                            String method = text(event, "method");
                            JsonElement morph = null;
                            if (client == owner && Set.of("GAME_CHOOSE_CHOICE", "GAME_CHOOSE_ABILITY").contains(method)) {
                                for (JsonElement item : event.getAsJsonArray("choices")) {
                                    JsonObject choice = item.getAsJsonObject();
                                    String label = text(choice, "label").toLowerCase(Locale.ROOT);
                                    if (label.contains("morph") || label.contains("face down") || label.contains("face-down")) { morph = choice.get("id"); break; }
                                }
                            }
                            if (morph != null) client.answer(event, "string", morph);
                            else CombatSmoke.answer(client, event, false);
                        }
                        case "error", "gameOver" -> throw new AssertionError("Morph privacy scenario did not finish: " + event);
                    }
                }
                if (mine != null && theirs != null && mine.get("id").equals(theirs.get("id"))) {
                    if (privatePrintings.isEmpty()) throw new AssertionError("No original private printing observed");
                    if (text(theirs, "name").contains("Gathan Raiders") || privatePrintings.contains(printing(theirs))
                            || text(theirs, "rules").toLowerCase(Locale.ROOT).contains("hellbent")
                            || text(theirs, "typeLine").contains("Warrior") || text(theirs, "manaCost").contains("R"))
                        throw new AssertionError("Face-down identity leaked in opponent view: " + theirs);
                    if (!text(theirs, "power").equals("2") || !text(theirs, "toughness").equals("2"))
                        throw new AssertionError("Face-down characteristics are not 2/2: " + theirs);
                    System.out.println("PASS real morph is 2/2 and face down in both seats; opponent gets no real name, printing, red mana cost or Hellbent rules");
                    System.out.println("Public card metadata: name=" + text(theirs, "name") + " set=" + text(theirs, "set") + " number=" + text(theirs, "collectorNumber"));
                    return;
                }
            }
            throw new AssertionError("Did not observe the same face-down permanent from both seats");
        }
    }
    private static String text(JsonObject object, String key) { return !object.has(key) || object.get(key).isJsonNull() ? "" : object.get(key).getAsString(); }
    private static String printing(JsonObject card) { return text(card, "set") + ":" + text(card, "collectorNumber"); }
}
