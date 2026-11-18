import com.google.gson.*;
import java.util.UUID;

/** Native engine priority controls, including stale-input protection and stop behavior. */
public final class PriorityControlSmoke {
    public static void main(String[] args) throws Exception {
        try (BridgeTwoPlayerSmoke.Client client = new BridgeTwoPlayerSmoke.Client()) {
            client.command("createAiGame");
            JsonObject priority = null;
            for (int i = 0; i < 50 && priority == null; i++) {
                JsonObject prompt = client.await("prompt");
                switch (prompt.get("method").getAsString()) {
                    case "GAME_TARGET" -> client.answer(prompt, "uuid", client.state.get("playerId"));
                    case "GAME_ASK" -> client.answer(prompt, "boolean", new JsonPrimitive(false));
                    case "GAME_SELECT" -> priority = prompt;
                    default -> throw new AssertionError("Unexpected setup prompt: " + prompt);
                }
            }
            if (priority == null) throw new AssertionError("No priority prompt");
            control(client, "hold", priority, false);
            if (!client.await("prioritySettings").get("holdingPriority").getAsBoolean()) throw new AssertionError("Hold not enabled");
            client.await("ack");
            control(client, "release", priority, false);
            if (client.await("prioritySettings").get("holdingPriority").getAsBoolean()) throw new AssertionError("Hold not released");
            client.await("ack");
            control(client, "nextMain", priority, true);
            JsonObject rejected = client.await("error");
            if (!rejected.get("message").getAsString().contains("expired")) throw new AssertionError(rejected);
            client.await("prompt"); // the same pending decision is replayed after rejection
            System.out.println("PASS hold/release and stale native auto-pass rejected");
            control(client, "nextMain", priority, false);
            client.await("ack");
            JsonObject stopped = client.await("prompt");
            if (!stopped.get("method").getAsString().equals("GAME_SELECT")) throw new AssertionError(stopped);
            if (!client.state.get("step").getAsString().contains("MAIN")) throw new AssertionError("Did not stop at main phase: " + client.state);
            if (stopped.get("id").equals(priority.get("id"))) throw new AssertionError("Native auto-pass did not advance");
            if (client.state.getAsJsonObject("priority").get("untilNextMain").getAsBoolean()) throw new AssertionError("Main-phase stop did not reset");
            control(client, "cancelAutoPass", stopped, false); client.await("ack");
            System.out.println("PASS engine advances to main phase, stops and clears skip setting; cancellation accepted");
            control(client, "endStep", stopped, false); client.await("ack");
            JsonObject end = client.await("prompt");
            if (!end.get("method").getAsString().equals("GAME_SELECT")
                    || !client.state.get("step").getAsString().contains("END"))
                throw new AssertionError("Did not stop in the end step: " + client.state + " / " + end);
            if (client.state.getAsJsonObject("priority").get("untilEndStep").getAsBoolean())
                throw new AssertionError("End-step stop did not reset");
            int previousTurn = client.state.get("turn").getAsInt();
            control(client, "yourTurn", end, false); client.await("ack");
            JsonObject ownTurn = client.await("prompt");
            if (!ownTurn.get("method").getAsString().equals("GAME_SELECT")
                    || client.state.get("turn").getAsInt() <= previousTurn
                    || !client.state.get("activePlayerId").equals(client.state.get("playerId")))
                throw new AssertionError("Did not stop on our next turn: " + client.state + " / " + ownTurn);
            if (client.state.getAsJsonObject("priority").get("untilYourTurn").getAsBoolean())
                throw new AssertionError("Next-turn stop did not reset");
            System.out.println("PASS engine stops at the end step and our next turn, clearing both skip settings");
        }
    }
    private static void control(BridgeTwoPlayerSmoke.Client client, String action, JsonObject prompt, boolean stale) {
        JsonObject command = new JsonObject();
        command.addProperty("type", "priorityControl"); command.addProperty("requestId", UUID.randomUUID().toString());
        command.addProperty("priorityAction", action);
        command.addProperty("promptId", stale ? "expired" : prompt.get("id").getAsString());
        command.add("revision", client.state.get("revision"));
        client.send(command.toString());
    }
}
