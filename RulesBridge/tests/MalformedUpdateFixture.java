import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Exercises the real Swift receive loop when resync repeats an incompatible update. */
public final class MalformedUpdateFixture extends WebSocketServer {
    private final ConcurrentHashMap<WebSocket, Integer> retries = new ConcurrentHashMap<>();
    private final Set<WebSocket> informationMode = ConcurrentHashMap.newKeySet();
    private static final Gson JSON = new Gson();
    private MalformedUpdateFixture(int port) { super(new InetSocketAddress("127.0.0.1", port), 1); }
    private static void badUpdate(WebSocket socket) {
        socket.send("{\"type\":\"snapshot\",\"gameId\":\"incompatible\"}");
    }
    @Override public void onOpen(WebSocket socket, ClientHandshake request) {
        if (!request.getFieldValue("Authorization").equals("Bearer " + System.getenv("RULES_BRIDGE_TOKEN"))) {
            socket.close(1008, "Invalid key"); return;
        }
        retries.put(socket, 0);
        if (request.getResourceDescriptor().endsWith("/information")) informationMode.add(socket);
        socket.send("{\"type\":\"hello\",\"protocolVersion\":1}");
    }
    @Override public void onMessage(WebSocket socket, String text) {
        JsonObject request = JsonParser.parseString(text).getAsJsonObject();
        switch (request.get("type").getAsString()) {
            case "connect" -> socket.send("{\"type\":\"ready\",\"protocolVersion\":1,\"resumeToken\":\"malformed-fixture\"}");
            case "createAiGame" -> {
                ack(socket, request);
                if (informationMode.contains(socket)) information(socket, 1, 1); else badUpdate(socket);
            }
            case "listTables" -> {
                ack(socket, request);
                if (informationMode.contains(socket)) {
                    int count = retries.merge(socket, 1, Integer::sum);
                    information(socket, count == 1 ? 1 : 3, count + 1);
                }
            }
            case "resync" -> {
                int count = retries.merge(socket, 1, Integer::sum);
                if (count > 2) { socket.close(1011, "Unbounded resync loop"); return; }
                ack(socket, request); badUpdate(socket);
                socket.send("{\"type\":\"notice\",\"message\":\"Replay count " + count + "\"}");
            }
            case "leave" -> socket.close(1000, "Done");
        }
    }
    private static void ack(WebSocket socket, JsonObject request) {
        socket.send("{\"type\":\"ack\",\"requestId\":" + request.get("requestId") + "}");
    }
    private static void information(WebSocket socket, int revision, int notice) {
        JsonObject snapshot = JsonParser.parseString("{\"type\":\"snapshot\",\"gameId\":\"information-game\",\"playerId\":\"me\",\"turn\":1,\"hand\":[],\"stack\":[],\"players\":[],\"playableIds\":[]}").getAsJsonObject();
        snapshot.addProperty("revision", revision);
        snapshot.add("lookedAt", JsonParser.parseString("[{\"name\":\"Opponent's hand\",\"cards\":[{\"id\":\"visible\",\"set\":\"M10\",\"collectorNumber\":\"230\",\"faceDown\":false,\"transformed\":false,\"counters\":[]}]}]"));
        socket.send(JSON.toJson(snapshot));
        snapshot.add("lookedAt", new JsonArray());
        snapshot.addProperty("revision", revision + 1);
        socket.send(JSON.toJson(snapshot));
        socket.send("{\"type\":\"notice\",\"message\":\"Information replay " + notice + "\"}");
    }
    @Override public void onClose(WebSocket socket, int code, String reason, boolean remote) { retries.remove(socket); informationMode.remove(socket); }
    @Override public void onError(WebSocket socket, Exception error) { error.printStackTrace(); }
    @Override public void onStart() { System.out.println("READY malformed-update fixture " + getPort()); }
    public static void main(String[] args) throws Exception {
        MalformedUpdateFixture server = new MalformedUpdateFixture(args.length > 0 ? Integer.parseInt(args[0]) : 17184);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { try { server.stop(1000); } catch (Exception ignored) {} }));
        server.start();
    }
}
