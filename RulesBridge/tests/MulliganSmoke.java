import com.google.gson.*;
import java.util.concurrent.TimeUnit;

/** Verify actual XMage mulligan sequencing independently of the opening-hand UI. */
public final class MulliganSmoke {
    public static void main(String[] args) throws Exception {
        try (var client = new BridgeTwoPlayerSmoke.Client()) {
            client.command("createAiGame");
            int mulligans = 0, returns = 0;
            boolean kept = false, priority = false;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
            while (!priority && System.nanoTime() < deadline) {
                JsonObject event = client.read();
                switch (event.get("type").getAsString()) {
                    case "error" -> throw new AssertionError(event);
                    case "snapshot" -> {
                        for (JsonElement player : event.getAsJsonArray("players"))
                            if (player.getAsJsonObject().has("hand")) throw new AssertionError("Opponent hand identities leaked");
                    }
                    case "prompt" -> {
                        String method = event.get("method").getAsString();
                        String message = event.has("message") ? event.get("message").getAsString() : "";
                        System.out.println(method + " / " + message + " / hand=" + client.state.getAsJsonArray("hand").size());
                        if (method.equals("GAME_TARGET") && message.toLowerCase().contains("starting player")) {
                            client.answer(event, "uuid", client.state.get("playerId"));
                        } else if (method.equals("GAME_ASK") && message.toLowerCase().contains("mulligan")) {
                            boolean again = mulligans < 2;
                            if (again) mulligans++; else kept = true;
                            client.answer(event, "boolean", new JsonPrimitive(again));
                        } else if (method.equals("GAME_TARGET") && message.toLowerCase().contains("bottom of your library")) {
                            if (mulligans == 0 || kept) throw new AssertionError("Unexpected return order: " + event);
                            JsonArray hand = client.state.getAsJsonArray("hand");
                            if (hand.isEmpty()) throw new AssertionError("No hand card can be returned");
                            JsonElement card = hand.get(0).getAsJsonObject().get("id");
                            client.answer(event, "uuid", card); returns++;
                        } else if (method.equals("GAME_SELECT")) {
                            if (!kept || mulligans != 2) throw new AssertionError("Priority before keeping the intended hand");
                            if (client.state.getAsJsonArray("hand").size() != 5)
                                throw new AssertionError("Two mulligans must leave five cards: " + client.state.get("hand"));
                            priority = true;
                        } else throw new AssertionError("Unexpected opening-hand prompt: " + event);
                    }
                }
            }
            if (!priority || returns != 3) throw new AssertionError("Incomplete mulligan flow: priority=" + priority + ", returns=" + returns);
            System.out.println("PASS two real mulligans, three individual library-return choices, Keep 5 and first priority with five cards");
        }
    }
}
