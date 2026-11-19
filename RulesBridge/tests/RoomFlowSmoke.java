import com.google.gson.*;
import java.util.*;
import java.util.concurrent.*;

/** Actual two-seat pre-deck room, recovery, automatic start and private opening hands. */
public final class RoomFlowSmoke {
    static JsonObject command(String type) {
        JsonObject result = new JsonObject(); result.addProperty("type", type); result.addProperty("requestId", UUID.randomUUID().toString()); return result;
    }
    static JsonObject deck(String land, int count) {
        JsonObject card = new JsonObject(); card.addProperty("name", land); card.addProperty("set", "M10"); card.addProperty("count", count);
        JsonObject deck = new JsonObject(); deck.addProperty("name", land); deck.add("main", new Gson().toJsonTree(List.of(card))); deck.add("sideboard", new JsonArray()); return deck;
    }
    static JsonObject state(BridgeTwoPlayerSmoke.Client client, String stage) throws Exception {
        for (;;) {
            JsonObject event = client.await("roomState");
            if (event.get("stage").getAsString().equals(stage)) {
                if (event.has("deck") || event.has("hand") || event.has("opponentDeck")) throw new AssertionError("Private deck in room state");
                return event;
            }
        }
    }
    static JsonObject open(BridgeTwoPlayerSmoke.Client client) throws Exception {
        JsonObject request = command("openRoom"); request.addProperty("format", "Limited"); request.addProperty("deckSource", "Deck List");
        client.send(request.toString()); JsonObject room = state(client, "waiting"); client.await("ack");
        if (client.state != null) throw new AssertionError("Battlefield before decks");
        return room;
    }
    static void join(BridgeTwoPlayerSmoke.Client client, JsonObject room) {
        JsonObject request = command("joinRoom"); request.add("tableId", room.get("id")); client.send(request.toString());
    }
    static JsonObject submit(BridgeTwoPlayerSmoke.Client client, JsonObject room, String land, int count) {
        JsonObject request = command("submitRoomDeck"); request.add("tableId", room.get("id")); request.add("deck", deck(land, count)); client.send(request.toString()); return request;
    }
    public static void main(String[] args) throws Exception {
        try (var host = new BridgeTwoPlayerSmoke.Client(); var guest = new BridgeTwoPlayerSmoke.Client(); var outsider = new BridgeTwoPlayerSmoke.Client()) {
            if (!host.ready.getAsJsonArray("features").toString().contains("rooms")) throw new AssertionError("Room capability absent");
            JsonObject room = open(host);
            guest.command("listRooms"); JsonObject listing = guest.await("tables"); guest.await("ack");
            if (!listing.toString().contains(room.get("id").getAsString())) throw new AssertionError("Open room undiscoverable");
            join(guest, room); state(guest, "choosing"); guest.await("ack"); state(host, "choosing");
            join(outsider, room); outsider.await("error");
            submit(host, room, "Plains", 1); host.await("error");
            JsonObject firstDeck = submit(host, room, "Plains", 40); state(host, "choosing"); host.await("ack");
            JsonObject waiting = state(guest, "choosing");
            if (!waiting.get("opponentReady").getAsBoolean() || waiting.get("ready").getAsBoolean()) throw new AssertionError("Readiness not seat-relative");
            String resume = guest.ready.get("resumeToken").getAsString(); guest.socket.abort();
            try (var recovered = new BridgeTwoPlayerSmoke.Client(resume)) {
                JsonObject restored = state(recovered, "choosing");
                if (!restored.get("opponentReady").getAsBoolean()) throw new AssertionError("Ready deck lost on reconnect");
                submit(recovered, room, "Island", 40);
                // There is deliberately no startMatch command.
                JsonObject first = host.await("snapshot"), second = recovered.await("snapshot");
                if (!first.get("gameId").equals(second.get("gameId")) || first.get("playerId").equals(second.get("playerId"))) throw new AssertionError("Wrong game/seats");
                host.send(firstDeck.toString()); host.await("ack");
                Set<BridgeTwoPlayerSmoke.Client> kept = new HashSet<>();
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
                while (kept.size() < 2 && System.nanoTime() < deadline) {
                    for (var client : List.of(host, recovered)) {
                        JsonObject event = client.events.poll(100, TimeUnit.MILLISECONDS); if (event == null) continue;
                        String type = event.get("type").getAsString();
                        if (type.equals("snapshot")) client.state = event;
                        if (type.equals("error")) throw new AssertionError(event);
                        if (type.equals("prompt")) {
                            String method = event.get("method").getAsString();
                            if (method.equals("GAME_TARGET")) client.answer(event, "uuid", client.state.get("playerId"));
                            else if (method.equals("GAME_ASK")) {
                                if (client.state.getAsJsonArray("hand").size() != 7) throw new AssertionError("Wrong opening hand");
                                String expected = client == host ? "Plains" : "Island";
                                for (JsonElement card : client.state.getAsJsonArray("hand")) if (!expected.equals(card.getAsJsonObject().get("name").getAsString())) throw new AssertionError("Other player's deck leaked");
                                kept.add(client); client.answer(event, "boolean", new JsonPrimitive(false));
                            } else if (method.equals("GAME_SELECT")) client.answer(event, "boolean", new JsonPrimitive(true));
                        }
                    }
                }
                if (kept.size() != 2) throw new AssertionError("Both opening hands not reached");
                System.out.println("PASS actual room opens before decks, discovery, full-room rejection, invalid deck retry, private readiness, reconnect, one automatic match and both private opening hands");
            }
        }
        try (var host = new BridgeTwoPlayerSmoke.Client(); var guest = new BridgeTwoPlayerSmoke.Client()) {
            JsonObject room = open(host); join(guest, room); state(guest, "choosing"); guest.await("ack"); state(host, "choosing");
            submit(host, room, "Plains", 40); host.await("ack");
            guest.command("leaveRoom"); guest.await("roomClosed"); guest.await("ack");
            JsonObject reset = state(host, "waiting"); if (reset.get("ready").getAsBoolean()) throw new AssertionError("Old deck retained for a new opponent");
            join(guest, room); state(guest, "choosing"); guest.await("ack"); state(host, "choosing");
            host.command("leaveRoom"); host.await("roomClosed"); host.await("ack"); guest.await("roomClosed");
            guest.command("listRooms"); if (guest.await("tables").toString().contains(room.get("id").getAsString())) throw new AssertionError("Closed room still listed");
            System.out.println("PASS guest leave resets ready decks and host leave closes the room for both");
        }
    }
}
