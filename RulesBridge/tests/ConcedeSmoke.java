import com.google.gson.*;
import java.net.URI;
import java.net.http.*;
import java.util.*;
import java.util.concurrent.*;

/** Real-engine concession: loss, retained final board, receipt idempotency, and result replay. */
public final class ConcedeSmoke implements WebSocket.Listener {
    private final BlockingQueue<JsonObject> events = new LinkedBlockingQueue<>();
    private final StringBuilder fragments = new StringBuilder();
    private WebSocket socket;
    private void send(String text) { socket.sendText(text, true).join(); }
    private JsonObject await(String type) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
        while (System.nanoTime() < deadline) {
            JsonObject event = events.poll(1, TimeUnit.SECONDS);
            if (event == null) continue;
            if (event.get("type").getAsString().equals("error")) throw new AssertionError(event);
            if (event.get("type").getAsString().equals(type)) return event;
        }
        throw new AssertionError("Timed out waiting for " + type);
    }
    public static void main(String[] args) throws Exception {
        ConcedeSmoke test = new ConcedeSmoke();
        try {
            test.socket = HttpClient.newHttpClient().newWebSocketBuilder()
                    .header("Authorization", "Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))
                    .buildAsync(URI.create(System.getenv().getOrDefault("RULES_SMOKE_ADDRESS", "ws://127.0.0.1:17182")), test)
                    .orTimeout(10, TimeUnit.SECONDS).join();
            test.await("hello"); test.send("{\"type\":\"connect\",\"protocolVersion\":1}"); test.await("ready");
            test.send("{\"type\":\"createAiGame\",\"requestId\":\"create\"}");
            JsonObject state = test.await("snapshot");
            String mine = null;
            for (JsonElement element : state.getAsJsonArray("players")) {
                JsonObject player = element.getAsJsonObject();
                if (player.get("id").equals(state.get("playerId"))) mine = player.get("name").getAsString();
            }
            if (mine == null) throw new AssertionError("Own seat missing");
            test.send("{\"type\":\"concede\",\"requestId\":\"concede-once\"}");
            String result = test.await("gameOver").get("message").getAsString();
            if (!result.contains("is the winner") || result.contains(mine + " is the winner")) throw new AssertionError("Concession was not a loss: " + result);
            test.send("{\"type\":\"concede\",\"requestId\":\"concede-once\"}");
            test.await("ack");
            test.send("{\"type\":\"resync\",\"requestId\":\"replay-result\"}");
            JsonObject finalState = test.await("snapshot");
            if (!finalState.get("gameId").equals(state.get("gameId"))) throw new AssertionError("Final board lost");
            if (!test.await("gameOver").get("message").getAsString().equals(result)) throw new AssertionError("Result changed on replay");
            System.out.println("PASS real XMage concession is a loss, final board retained, duplicate receipt and result replay");
        } finally {
            if (test.socket != null) { try { test.send("{\"type\":\"leave\"}"); } finally { test.socket.abort(); } }
        }
    }
    public CompletionStage<?> onText(WebSocket socket, CharSequence data, boolean last) {
        fragments.append(data);
        if (last) { events.add(JsonParser.parseString(fragments.toString()).getAsJsonObject()); fragments.setLength(0); }
        socket.request(1); return null;
    }
    public void onOpen(WebSocket socket) { socket.request(1); }
}
