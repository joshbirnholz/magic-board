import com.google.gson.*;
import java.net.URI;
import java.net.http.*;
import java.util.*;
import java.util.concurrent.*;

/** Two independent WebSocket/XMage sessions, exercising the real two-human lobby and privacy. */
public final class BridgeTwoPlayerSmoke {
    static final class Client implements WebSocket.Listener, AutoCloseable {
        final BlockingQueue<JsonObject> events = new LinkedBlockingQueue<>();
        final StringBuilder fragments = new StringBuilder();
        WebSocket socket;
        JsonObject state;
        JsonObject ready;
        final CompletableFuture<Void> closed = new CompletableFuture<>();
        public CompletionStage<?> onClose(WebSocket socket, int code, String reason) {
            closed.complete(null);
            return null;
        }
        public CompletionStage<?> onText(WebSocket socket, CharSequence text, boolean last) {
            fragments.append(text);
            if (last) { events.add(JsonParser.parseString(fragments.toString()).getAsJsonObject()); fragments.setLength(0); }
            socket.request(1);
            return null;
        }
        Client() throws Exception { this(null); }
        Client(String resume) throws Exception {
            socket = HttpClient.newHttpClient().newWebSocketBuilder()
                    .header("Authorization", "Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))
                    .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17180")), this).orTimeout(10, TimeUnit.SECONDS).join();
            try {
                await("hello");
                JsonObject connect = new JsonObject();
                connect.addProperty("type", "connect"); connect.addProperty("protocolVersion", 1);
                if (resume != null) connect.addProperty("resumeToken", resume);
                send(connect.toString());
                ready = await("ready");
            } catch (Exception | AssertionError error) { socket.abort(); throw error; }
        }
        void send(String text) { socket.sendText(text, true).join(); }
        void command(String type) { send("{\"type\":\"" + type + "\",\"requestId\":\"" + UUID.randomUUID() + "\"}"); }
        JsonObject read() throws Exception {
            JsonObject result = events.poll(30, TimeUnit.SECONDS);
            if (result == null) throw new AssertionError("No bridge event");
            if (result.get("type").getAsString().equals("snapshot")) state = result;
            return result;
        }
        JsonObject await(String type) throws Exception {
            while (true) {
                JsonObject event = read();
                String actual = event.get("type").getAsString();
                if (type.equals(actual)) return event;
                if (actual.equals("error")) throw new AssertionError(event);
            }
        }
        void answer(JsonObject prompt, String kind, JsonElement value) {
            JsonObject request = new JsonObject();
            request.addProperty("type", "answer"); request.addProperty("requestId", UUID.randomUUID().toString());
            request.add("promptId", prompt.get("id")); request.add("revision", state.get("revision"));
            request.addProperty("kind", kind); request.add("value", value);
            send(request.toString());
        }
        public void close() {
            if (socket != null && !socket.isOutputClosed()) {
                send("{\"type\":\"leave\"}");
                socket.sendClose(1000, "Done").join();
            }
        }
    }

    public static void main(String[] args) throws Exception {
        try (Client first = new Client(); Client second = new Client()) {
            first.command("createHumanGame");
            JsonObject created = first.await("tableJoined"); first.await("ack");
            if (!created.get("owner").getAsBoolean()) throw new AssertionError("Creator is not table owner");
            boolean found = false;
            JsonArray tables = new JsonArray();
            // XMage's room listing is a cached view; refresh while it catches up to table creation.
            for (int attempt = 0; attempt < 20 && !found; attempt++) {
                second.command("listTables");
                tables = second.await("tables").getAsJsonArray("tables"); second.await("ack");
                for (JsonElement table : tables) {
                    if (table.getAsJsonObject().get("id").equals(created.get("tableId"))) {
                        found = true;
                        if (table.getAsJsonObject().get("players").getAsInt() != 1) throw new AssertionError("Incorrect occupied seat count: " + table);
                    }
                }
                if (!found) Thread.sleep(250);
            }
            if (!found) throw new AssertionError("Created table missing from waiting games: " + tables);
            System.out.println("PASS create and discover a real two-human table");
            second.send("{\"type\":\"joinTable\",\"requestId\":\"join\",\"tableId\":" + created.get("tableId") + "}");
            if (second.await("tableJoined").get("owner").getAsBoolean()) throw new AssertionError("Joiner became table owner");
            second.await("ack");
            first.command("startMatch"); first.await("ack");
            first.await("snapshot"); second.await("snapshot");
            if (!first.state.get("gameId").equals(second.state.get("gameId"))) throw new AssertionError("Clients joined different games");
            if (first.state.get("playerId").equals(second.state.get("playerId"))) throw new AssertionError("Clients share the same seat");
            System.out.println("PASS both human sessions join the same game in different seats");
            Set<Client> kept = new HashSet<>();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
            while (kept.size() < 2 && System.nanoTime() < deadline) {
                for (Client client : List.of(first, second)) {
                    JsonObject event = client.events.poll(100, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    switch (event.get("type").getAsString()) {
                        case "snapshot" -> client.state = event;
                        case "prompt" -> {
                            String method = event.get("method").getAsString();
                            if (method.equals("GAME_TARGET")) {
                                client.answer(event, "uuid", client.state.get("playerId"));
                            } else if (method.equals("GAME_ASK")) {
                                if (client.state.getAsJsonArray("hand").size() != 7) throw new AssertionError("Opening hand is not seven cards");
                                kept.add(client);
                                client.answer(event, "boolean", new JsonPrimitive(false));
                            } else if (method.equals("GAME_SELECT")) {
                                client.answer(event, "boolean", new JsonPrimitive(true));
                            }
                        }
                        case "error" -> throw new AssertionError(event);
                    }
                }
            }
            if (kept.size() != 2) throw new AssertionError("Both clients did not receive their opening hand");
            for (Client client : List.of(first, second)) {
                Client other = client == first ? second : first;
                for (JsonElement card : other.state.getAsJsonArray("hand")) {
                    String hiddenId = card.getAsJsonObject().get("id").getAsString();
                    if (client.state.toString().contains(hiddenId)) throw new AssertionError("Opponent hand identity leaked to the other seat");
                }
            }
            System.out.println("PASS each human gets its own seven-card hand without opponent card identities");
        }
    }
}
