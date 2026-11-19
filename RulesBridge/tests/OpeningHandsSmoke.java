import com.google.gson.*;
import java.util.*;
import java.util.concurrent.*;

/** Two real human seats: the second sees its hand while first mulligans, then public Keep6. */
public final class OpeningHandsSmoke {
    private static String firstPlayerId(BridgeTwoPlayerSmoke.Client host) { return host.state.get("playerId").getAsString(); }
    public static void main(String[] args) throws Exception {
        try (var host = new BridgeTwoPlayerSmoke.Client(); var guest = new BridgeTwoPlayerSmoke.Client()) {
            JsonObject room = RoomFlowSmoke.open(host); RoomFlowSmoke.join(guest, room);
            RoomFlowSmoke.state(guest, "choosing"); guest.await("ack"); RoomFlowSmoke.state(host, "choosing");
            RoomFlowSmoke.submit(host, room, "Plains", 40); host.await("ack");
            RoomFlowSmoke.submit(guest, room, "Island", 40);
            Map<BridgeTwoPlayerSmoke.Client, JsonObject> prompts = new HashMap<>(), opening = new HashMap<>();
            boolean mulliganed = false, hostKept = false, guestKept = false, waitingVerified = false;
            String firstPlayer = null;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(50);
            while (System.nanoTime() < deadline) {
                for (var client : List.of(host, guest)) {
                    JsonObject event = client.events.poll(40, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    String type = event.get("type").getAsString();
                    if (type.equals("error")) throw new AssertionError(event);
                    if (type.equals("snapshot")) client.state = event;
                    if (type.equals("prompt")) { prompts.put(client, event); System.out.println((client == host ? "HOST " : "GUEST ") + event.get("method") + " " + event.get("message")); }
                    if (type.equals("openingState")) {
                        if (event.has("hand") || event.has("cards") || event.has("deck")) throw new AssertionError("Private cards in progress");
                        opening.put(client, event);
                    }
                }
                if (host.state == null || guest.state == null) continue;
                if (firstPlayer == null) firstPlayer = host.state.get("playerId").getAsString();
                for (var client : List.of(host, guest)) {
                    JsonObject prompt = prompts.get(client); if (prompt == null) continue;
                    String method = prompt.get("method").getAsString(), text = prompt.get("message").getAsString().toLowerCase();
                    if (method.equals("GAME_TARGET") && text.contains("starting player")) {
                        client.answer(prompt, "uuid", new JsonPrimitive(firstPlayer)); prompts.remove(client);
                    } else if (method.equals("GAME_TARGET") && text.contains("bottom of your library")) {
                        client.answer(prompt, "uuid", prompt.getAsJsonArray("targets").get(0)); prompts.remove(client);
                    } else if (method.equals("GAME_ASK") && text.contains("mulligan")) {
                        JsonObject progress = opening.get(guest);
                        if (client == host && !waitingVerified) {
                            if (progress == null || !progress.has("startingPlayerId")) continue;
                            if (!progress.get("startingPlayerId").getAsString().equals(firstPlayer)) throw new AssertionError("Wrong starter");
                            if (guest.state.getAsJsonArray("hand").size() != 7) continue;
                            waitingVerified = true;
                        }
                        if (client == host && !mulliganed) { client.answer(prompt, "boolean", new JsonPrimitive(true)); mulliganed = true; }
                        else if (client == host) { client.answer(prompt, "boolean", new JsonPrimitive(false)); hostKept = true; }
                        else {
                            // XMage asks both seats within a London round; holding this answer
                            // until the first player's later keep would deadlock the next round.
                            client.answer(prompt, "boolean", new JsonPrimitive(false)); guestKept = true;
                        }
                        prompts.remove(client);
                    } else if (method.equals("GAME_SELECT")) { client.answer(prompt, "boolean", new JsonPrimitive(true)); prompts.remove(client); }
                }
                if (hostKept && guestKept && waitingVerified && opening.size() == 2
                        && opening.values().stream().allMatch(p -> !p.get("active").getAsBoolean())) {
                    if (opening.values().stream().anyMatch(p -> p.getAsJsonObject("kept").get(firstPlayerId(host)).getAsInt() != 6)) throw new AssertionError("Keep6 not shared");
                    System.out.println("PASS actual first-player identity, each seat's private seven, native simultaneous London decisions, first player's mulligan/Keep6, public kept counts and opening completion"); return;
                }
            }
            throw new AssertionError("Opening progression incomplete: waited=" + waitingVerified + " hostKept=" + hostKept + " guestKept=" + guestKept);
        }
    }
}
