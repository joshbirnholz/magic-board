import com.google.gson.*;
import java.util.concurrent.TimeUnit;

/** Real-engine regression: a rejected AI deck can be retried, and its replacement is independent. */
public final class SeparateAiDeckSmoke {
    private static JsonObject deck(String name) {
        JsonObject deck = new JsonObject(), row = new JsonObject();
        row.addProperty("name", name); row.addProperty("count", 40);
        JsonArray cards = new JsonArray(); cards.add(row); deck.add("main", cards);
        return deck;
    }
    private static String create(String aiCard) {
        JsonObject request = new JsonObject();
        request.addProperty("type", "createAiGame"); request.addProperty("requestId", aiCard);
        request.addProperty("format", "Limited");
        request.add("deck", deck("Plains")); request.add("aiDeck", deck(aiCard));
        return request.toString();
    }
    public static void main(String[] args) throws Exception {
        try (var client = new BridgeTwoPlayerSmoke.Client()) {
            client.send(create("Definitely Not A Magic Card"));
            JsonObject error = client.await("error");
            if (!error.get("message").getAsString().contains("Definitely Not A Magic Card"))
                throw new AssertionError("Missing actionable rejected-card error: " + error);
            client.send(create("Island"));
            boolean hand = false, aiLand = false;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
            while ((!hand || !aiLand) && System.nanoTime() < deadline) {
                JsonObject event = client.read();
                switch (event.get("type").getAsString()) {
                    case "error" -> throw new AssertionError(event);
                    case "snapshot" -> {
                        JsonArray cards = event.getAsJsonArray("hand");
                        if (!cards.isEmpty()) {
                            for (JsonElement card : cards) if (!card.getAsJsonObject().get("name").getAsString().equals("Plains"))
                                throw new AssertionError("Player received the AI's deck: " + card);
                            hand = true;
                        }
                        for (JsonElement player : event.getAsJsonArray("players")) {
                            JsonObject opponent = player.getAsJsonObject();
                            if (opponent.get("id").equals(event.get("playerId"))) continue;
                            for (JsonElement card : opponent.getAsJsonArray("battlefield")) {
                                if (!card.getAsJsonObject().get("name").getAsString().equals("Island"))
                                    throw new AssertionError("AI did not receive its own deck: " + card);
                                aiLand = true;
                            }
                        }
                    }
                    case "prompt" -> {
                        switch (event.get("method").getAsString()) {
                            case "GAME_TARGET" -> client.answer(event, "uuid", client.state.get("playerId"));
                            case "GAME_ASK" -> client.answer(event, "boolean", new JsonPrimitive(false));
                            case "GAME_SELECT" -> client.answer(event, "boolean", new JsonPrimitive(true));
                            default -> throw new AssertionError("Unexpected all-land prompt: " + event);
                        }
                    }
                }
            }
            if (!hand || !aiLand) throw new AssertionError("Did not observe distinct decks: hand=" + hand + ", AI land=" + aiLand);
            System.out.println("PASS invalid AI deck retry on same seat, 40-card Limited decks, human Plains hand and AI Island battlefield");
        }
    }
}
