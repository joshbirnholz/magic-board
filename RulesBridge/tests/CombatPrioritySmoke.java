import com.google.gson.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Native skips during attacker/blocker selection must advance or preserve an answerable choice. */
public final class CombatPrioritySmoke {
    public static void main(String[] args) throws Exception {
        for (String stage : args.length == 0 ? new String[]{"attackers", "blockers"} : args) run(stage);
    }

    private static void run(String stage) throws Exception {
        if (!Set.of("attackers", "blockers").contains(stage)) throw new IllegalArgumentException("Use attackers or blockers");
        String originalStep = stage.equals("attackers") ? "DECLARE_ATTACKERS" : "DECLARE_BLOCKERS";
        try (var attacker = new BridgeTwoPlayerSmoke.Client(); var defender = new BridgeTwoPlayerSmoke.Client()) {
            attacker.command("createHumanGame");
            var table = attacker.await("tableJoined"); attacker.await("ack");
            defender.send("{\"type\":\"joinTable\",\"requestId\":\"join\",\"tableId\":" + table.get("tableId") + "}");
            defender.await("tableJoined"); defender.await("ack");
            attacker.command("startMatch"); attacker.await("ack");
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60);
            boolean checked = false, controlReturned = false, progressed = false, promptAvailable = false;
            BridgeTwoPlayerSmoke.Client probeSeat = null;
            int originalTurn = -1;
            long checkedAt = 0;
            while (System.nanoTime() < deadline) {
                for (var client : List.of(attacker, defender)) {
                    JsonObject event = client.events.poll(25, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    String type = event.get("type").getAsString();
                    switch (type) {
                        case "snapshot" -> {
                            client.state = event;
                            if (checked && controlReturned && client == probeSeat && (event.get("turn").getAsInt() != originalTurn
                                    || !event.get("step").getAsString().equals(originalStep))) progressed = true;
                        }
                        case "prompt" -> {
                            String message = event.has("message") ? event.get("message").getAsString() : "";
                            if (!checked && client == (stage.equals("attackers") ? attacker : defender) && event.get("method").getAsString().equals("GAME_SELECT")
                                    && message.toLowerCase(Locale.ROOT).contains("select " + stage)) {
                                checked = true; probeSeat = client; checkedAt = System.nanoTime(); originalTurn = client.state.get("turn").getAsInt();
                                System.out.println("PROBE before skip: turn=" + originalTurn + " step=" + client.state.get("step") + " prompt=" + message);
                                JsonObject skip = new JsonObject();
                                skip.addProperty("type", "priorityControl"); skip.addProperty("requestId", "combat-skip");
                                skip.addProperty("priorityAction", "endStep"); skip.add("promptId", event.get("id"));
                                skip.add("revision", client.state.get("revision")); client.send(skip.toString());
                            } else {
                                if (checked && controlReturned && client == probeSeat) promptAvailable = true;
                                CombatSmoke.answer(client, event, client == attacker);
                            }
                        }
                        case "error" -> {
                            if (checked && client == probeSeat) {
                                controlReturned = true;
                                System.out.println("PROBE skip rejected; checking the choice survives: " + event.get("message"));
                                client.command("resync");
                                continue;
                            }
                            throw new AssertionError(event);
                        }
                        case "gameOver" -> throw new AssertionError("Game ended before the priority check completed: " + event);
                        case "ack" -> {
                            if (checked && event.has("requestId") && event.get("requestId").getAsString().equals("combat-skip")) {
                                controlReturned = true;
                                System.out.println("PROBE native skip accepted; retrieving retained prompt/state");
                                client.command("resync");
                            }
                        }
                    }
                }
                if (checked && (progressed || promptAvailable)) {
                    System.out.println("PASS " + stage + " skip leaves progress or an answerable prompt: progressed=" + progressed + " prompt=" + promptAvailable);
                    return;
                }
                if (checked && System.nanoTime() - checkedAt > TimeUnit.SECONDS.toNanos(5))
                    throw new AssertionError("Combat skip discarded the only choice: turn=" + probeSeat.state.get("turn") + " step=" + probeSeat.state.get("step") + "; resync supplied no prompt");
            }
            throw new AssertionError("No " + stage + " selection reached for probe");
        }
    }
}
