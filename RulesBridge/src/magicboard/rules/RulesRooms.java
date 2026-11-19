package magicboard.rules;

import com.google.gson.*;
import java.util.*;
import java.util.concurrent.*;
import static magicboard.rules.XMageSession.*;

/** Pre-match rooms: both seats choose decks before stock XMage seating/automatic start.
 * All room state lives on one worker; engine calls stay on their respective session queues.
 * No engine callback waits for this worker or the WebSocket server monitor.
 */
final class RulesRooms implements AutoCloseable {
    interface Client {
        XMageSession engine();
        void send(JsonObject event);
        boolean alive();
        boolean connected();
        void inRoom(boolean value);
    }
    private static final Set<String> COMMANDS = Set.of("openRoom", "joinRoom", "submitRoomDeck", "leaveRoom", "listRooms");
    private final OpeningHands openingHands = new OpeningHands();
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Map<String, Room> rooms = new LinkedHashMap<>();
    private final Map<Client, Room> membership = new HashMap<>();
    private final Map<Client, LinkedHashMap<String, JsonObject>> receipts = new HashMap<>();
    private static final class Room {
        final String id = UUID.randomUUID().toString();
        final Client host;
        final String format, source, set;
        Client guest;
        String stage = "waiting";
        final Map<Client, JsonObject> decks = new HashMap<>();
        Room(Client host, String format, String source, String set) {
            this.host = host; this.format = format; this.source = source; this.set = set;
        }
    }
    boolean handles(String type) { return COMMANDS.contains(type); }
    void command(Client client, JsonObject request) { worker.execute(() -> process(client, request)); }
    void replay(Client client) { worker.execute(() -> { Room room = membership.get(client); if (room != null) publish(room, client); openingHands.replay(client); }); }
    void observe(Client client, JsonObject event) {
        try { worker.execute(() -> { if (client.alive()) openingHands.observe(client, event); }); }
        catch (RejectedExecutionException ignored) { }
    }
    void detachedPermanently(Client client) {
        try { worker.execute(() -> { leave(client); receipts.remove(client); openingHands.remove(client); }); }
        catch (RejectedExecutionException ignored) { }
    }
    private <T> T engine(Client client, Callable<T> call) throws Exception {
        if (!client.alive()) throw new IllegalStateException("A player has left the room.");
        try {
            T value = client.engine().queue.submit(call).get(15, TimeUnit.SECONDS);
            if (!client.alive()) throw new IllegalStateException("A player has left the room.");
            return value;
        }
        catch (ExecutionException error) {
            if (error.getCause() instanceof Exception cause) throw cause;
            throw error;
        }
    }
    private void process(Client client, JsonObject request) {
        if (!client.alive()) return;
        String id = string(request, "requestId");
        if (id.isEmpty()) { client.send(object("type", "error", "message", "A request ID is required.")); return; }
        var history = receipts.computeIfAbsent(client, ignored -> new LinkedHashMap<>());
        if (history.containsKey(id)) { client.send(history.get(id)); replayCurrent(client); return; }
        JsonObject result;
        try {
            switch (string(request, "type")) {
                case "listRooms" -> {
                    JsonArray list = new JsonArray();
                    for (Room room : rooms.values()) if (room.stage.equals("waiting") && room.host.connected())
                        list.add(object("id", room.id, "name", "Magic Board Rules", "players", 1, "capacity", 2,
                            "format", room.format, "deckSource", room.source, "packetSet", room.set, "room", true));
                    JsonObject event = object("type", "tables"); event.add("tables", list); client.send(event);
                }
                case "openRoom" -> {
                    if (membership.containsKey(client)) throw new IllegalStateException("Leave the current room first.");
                    String format = string(request, "format"), source = string(request, "deckSource"), set = string(request, "packetSet");
                    if (!Set.of("Built-in", "Deck List", "JumpStart", "Jump In").contains(source)) throw new IllegalArgumentException("Choose a deck source.");
                    if ((source.equals("JumpStart") || source.equals("Jump In")) && (!format.equals("Limited") || !set.matches("[A-Za-z0-9]{2,12}")))
                        throw new IllegalArgumentException("Choose a packet set for a Limited game.");
                    engine(client, () -> { client.engine().validateRoom(format); return null; });
                    Room room = new Room(client, format, source, set);
                    rooms.put(room.id, room); membership.put(client, room); client.inRoom(true); publish(room);
                }
                case "joinRoom" -> {
                    if (membership.containsKey(client)) throw new IllegalStateException("Leave the current room first.");
                    Room room = rooms.get(string(request, "tableId"));
                    if (room == null || !room.stage.equals("waiting") || !room.host.connected()) throw new IllegalStateException("This room is no longer waiting for a player.");
                    engine(client, () -> { client.engine().validateRoom(room.format); return null; });
                    room.guest = client; room.stage = "choosing";
                    membership.put(client, room); client.inRoom(true); publish(room);
                }
                case "submitRoomDeck" -> {
                    Room room = membership.get(client);
                    if (room == null || !room.id.equals(string(request, "tableId")) || !room.stage.equals("choosing"))
                        throw new IllegalStateException("This room is not choosing decks.");
                    engine(client, () -> { client.engine().validateRoomDeck(request, room.format); return null; });
                    JsonObject deck = request.deepCopy(); deck.addProperty("format", room.format);
                    room.decks.put(client, deck); publish(room);
                    if (room.decks.size() == 2) start(room);
                }
                case "leaveRoom" -> {
                    Room room = membership.get(client);
                    if (room != null && (room.stage.equals("starting") || room.stage.equals("playing")))
                        throw new IllegalStateException("The game has started. Use Exit Game or Concede on the battlefield.");
                    leave(client);
                }
                default -> throw new IllegalArgumentException("Unsupported room command.");
            }
            result = object("type", "ack", "requestId", id);
        } catch (Exception error) {
            result = object("type", "error", "requestId", id, "message",
                error.getMessage() == null ? "Could not update the room. Try again." : error.getMessage());
        }
        history.put(id, result);
        if (history.size() > 256) history.remove(history.keySet().iterator().next());
        client.send(result);
    }
    private void start(Room room) throws Exception {
        room.stage = "starting"; publish(room);
        try {
            UUID table = engine(room.host, () -> room.host.engine().prepareRoomGame(room.decks.get(room.host)));
            engine(room.guest, () -> { room.guest.engine().joinRoomGame(table, room.decks.get(room.guest)); return null; });
            if (!room.host.alive() || !room.guest.alive()) throw new IllegalStateException("A player left before the game started.");
            engine(room.host, () -> { room.host.engine().startRoomGame(); return null; });
            room.stage = "playing"; publish(room);
        } catch (Exception error) {
            // Cleanup follows any in-flight native call on each engine queue, even after timeout.
            for (Client seat : List.of(room.guest, room.host)) {
                try { seat.engine().queue.submit(seat.engine()::cancelWaitingGame).get(15, TimeUnit.SECONDS); }
                catch (Exception ignored) { }
            }
            room.stage = "choosing"; room.decks.clear(); publish(room);
            for (Client seat : List.of(room.host, room.guest))
                seat.send(object("type", "notice", "message", "The game could not start. Check your deck and choose it again."));
            throw error;
        }
    }
    private void leave(Client client) {
        Room room = membership.remove(client);
        client.inRoom(false);
        client.send(object("type", "roomClosed"));
        if (room == null) return;
        if (client == room.host || !room.stage.equals("choosing") && !room.stage.equals("waiting")) {
            rooms.remove(room.id);
            Client other = client == room.host ? room.guest : room.host;
            if (other != null) {
                membership.remove(other); other.inRoom(false);
                other.send(object("type", "roomClosed", "message", "The other player left the room."));
            }
        } else {
            room.guest = null; room.decks.clear(); room.stage = "waiting"; publish(room);
        }
    }
    private void replayCurrent(Client client) { Room room = membership.get(client); if (room != null) publish(room, client); }
    private void publish(Room room) { publish(room, room.host); if (room.guest != null) publish(room, room.guest); }
    private void publish(Room room, Client client) {
        client.send(object("type", "roomState", "id", room.id, "format", room.format, "deckSource", room.source,
            "packetSet", room.set, "stage", room.stage, "owner", room.host == client,
            "players", room.guest == null ? 1 : 2, "ready", room.decks.containsKey(client),
            "opponentReady", room.decks.containsKey(client == room.host ? room.guest : room.host)));
    }
    @Override public void close() { worker.shutdownNow(); }
}
