import com.google.gson.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Independent AI games share the engine, never a human seat, hand or game state. */
public final class ConcurrentAiGamesSmoke {
    private static JsonObject deck(String name) {
        JsonObject row = new JsonObject(), deck = new JsonObject();
        row.addProperty("name", name); row.addProperty("count", 40);
        JsonArray main = new JsonArray(); main.add(row); deck.add("main", main);
        return deck;
    }
    private static void create(BridgeTwoPlayerSmoke.Client client, String human, String ai) {
        JsonObject command = new JsonObject();
        command.addProperty("type", "createAiGame"); command.addProperty("requestId", UUID.randomUUID().toString());
        command.addProperty("format", "Limited"); command.add("deck", deck(human)); command.add("aiDeck", deck(ai));
        client.send(command.toString());
    }
    private static void mainPhase(BridgeTwoPlayerSmoke.Client client, String land) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
        while (System.nanoTime() < deadline) {
            JsonObject event = client.read();
            String type = event.get("type").getAsString();
            if (type.equals("error")) throw new AssertionError(event);
            if (!type.equals("prompt")) continue;
            JsonObject state = client.state;
            for (JsonElement player : state.getAsJsonArray("players"))
                if (player.getAsJsonObject().has("hand")) throw new AssertionError("Private hand in player summaries");
            for (JsonElement card : state.getAsJsonArray("hand"))
                if (!land.equals(card.getAsJsonObject().get("name").getAsString())) throw new AssertionError("Another game's deck leaked");
            switch (event.get("method").getAsString()) {
                case "GAME_TARGET" -> client.answer(event, "uuid", state.get("playerId"));
                case "GAME_ASK" -> client.answer(event, "boolean", new JsonPrimitive(false));
                case "GAME_SELECT" -> {
                    if (state.has("activePlayerId") && state.get("activePlayerId").equals(state.get("playerId"))
                            && event.get("message").getAsString().contains("Play spells and abilities")) return;
                    client.answer(event, "boolean", new JsonPrimitive(true));
                }
                default -> throw new AssertionError("Unexpected all-land prompt: " + event);
            }
        }
        throw new AssertionError("No human main phase");
    }
    public static void main(String[] args) throws Exception {
        try (var first = new BridgeTwoPlayerSmoke.Client(); var second = new BridgeTwoPlayerSmoke.Client()) {
            create(first, "Plains", "Island"); create(second, "Swamp", "Mountain");
            mainPhase(first, "Plains"); mainPhase(second, "Swamp");
            if (first.state.get("gameId").equals(second.state.get("gameId"))
                    || first.state.get("playerId").equals(second.state.get("playerId"))
                    || first.ready.get("resumeToken").equals(second.ready.get("resumeToken")))
                throw new AssertionError("Independent connections share a game or seat");
            first.send("{\"type\":\"answer\",\"requestId\":\"first-land\",\"promptId\":\"invalid\",\"revision\":0,\"kind\":\"uuid\",\"value\":\"invalid\"}");
            // The rejected command stays local to the first game; the other remains playable.
            first.await("error");
            second.command("resync"); second.await("snapshot"); second.await("ack");
            for (JsonElement card : second.state.getAsJsonArray("hand"))
                if (!"Swamp".equals(card.getAsJsonObject().get("name").getAsString())) throw new AssertionError("Other game changed");
            System.out.println("PASS two simultaneous real AI games, distinct seats/decks/private hands and isolated rejected action");
            try (var third = new BridgeTwoPlayerSmoke.Client(); var fourth = new BridgeTwoPlayerSmoke.Client()) {
                try (var fifth = new BridgeTwoPlayerSmoke.Client()) { throw new AssertionError("Fifth active player accepted"); }
                catch (AssertionError expected) {
                    if (!expected.getMessage().contains("Four players are currently connected")) throw expected;
                }
                first.command("listTables"); first.await("tables"); first.await("ack");
                second.command("listTables"); second.await("tables"); second.await("ack");
                System.out.println("PASS four active player sessions; fifth rejected without evicting either AI game");
            }
        }
    }
}
