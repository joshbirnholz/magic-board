package magicboard.rules;

import com.google.gson.*;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import static magicboard.rules.XMageSession.*;

/** Phone transport; XMage remoting remains on the PC. No Swing windows are created. */
public final class BridgeMain extends WebSocketServer {
    private final String token;
    private final String engineHost;
    private final int enginePort;
    private final Map<String, Seat> seats = new HashMap<>();
    private final Map<WebSocket, Seat> connections = new HashMap<>();
    private final Set<WebSocket> authorized = ConcurrentHashMap.newKeySet();
    private final ScheduledExecutorService cleanup = Executors.newSingleThreadScheduledExecutor();
    private final CompletableFuture<Void> started = new CompletableFuture<>();

    private static final class Seat {
        final String resumeToken = UUID.randomUUID() + "-" + UUID.randomUUID();
        final XMageSession engine;
        volatile WebSocket socket;
        volatile long detachedAt;
        volatile boolean ready;
        volatile JsonObject readyEvent;
        Seat(WebSocket socket) {
            this.socket = socket;
            engine = new XMageSession(event -> {
                if (string(event, "type").equals("ready")) {
                    event.addProperty("resumeToken", resumeToken);
                    readyEvent = event.deepCopy();
                    ready = true;
                }
                if (string(event, "type").equals("engineDisconnected")) ready = false;
                WebSocket target = this.socket;
                if (target != null && target.isOpen()) target.send(JSON.toJson(event));
            });
        }
    }

    private BridgeMain(String bind, int port, String token, String engineHost, int enginePort) {
        super(new InetSocketAddress(bind, port));
        this.token = token;
        this.engineHost = engineHost;
        this.enginePort = enginePort;
        setConnectionLostTimeout(30);
        setReuseAddr(true);
        setMaxPendingConnections(8);
        cleanup.scheduleWithFixedDelay(this::expire, 30, 30, TimeUnit.SECONDS);
    }

    @Override public void onOpen(WebSocket socket, ClientHandshake handshake) {
        byte[] supplied = handshake.getFieldValue("Authorization").getBytes(StandardCharsets.UTF_8);
        byte[] expected = ("Bearer " + token).getBytes(StandardCharsets.UTF_8);
        if (!MessageDigest.isEqual(supplied, expected)) {
            socket.close(1008, "Invalid connection key");
            return;
        }
        authorized.add(socket);
        socket.send(JSON.toJson(object("type", "hello", "protocolVersion", 1, "engineRelease", "xmage_1.4.63V2")));
    }

    @Override public synchronized void onMessage(WebSocket socket, String text) {
        if (!authorized.contains(socket)) { socket.close(1008, "Authentication required"); return; }
        if (text.length() > 64 * 1024) { socket.close(1009, "Message too large"); return; }
        try {
            JsonObject request = JsonParser.parseString(text).getAsJsonObject();
            Seat seat = connections.get(socket);
            if (string(request, "type").equals("connect")) {
                if (seat != null) throw new IllegalStateException("Already connected.");
                if (!request.has("protocolVersion") || request.get("protocolVersion").getAsInt() != 1)
                    throw new IllegalArgumentException("Unsupported bridge protocol.");
                String resume = string(request, "resumeToken");
                if (!resume.isEmpty()) {
                    seat = seats.get(resume);
                    if (seat == null || !seat.ready) {
                        socket.send(JSON.toJson(object("type", "error", "code", "sessionExpired", "message", "This game session expired. Connect as a new session.")));
                        return;
                    }
                    if (seat.socket != null && seat.socket != socket) {
                        connections.remove(seat.socket);
                        seat.socket.close(1000, "Session resumed on another connection");
                    }
                    seat.socket = socket;
                    connections.put(socket, seat);
                    socket.send(JSON.toJson(seat.readyEvent));
                    seat.engine.queue.execute(seat.engine::replay);
                    return;
                }
                makeRoomForSession();
                Seat created = new Seat(socket);
                seats.put(created.resumeToken, created);
                connections.put(socket, created);
                created.engine.queue.execute(() -> {
                    try { created.engine.connect(engineHost, enginePort, "MB" + UUID.randomUUID().toString().substring(0, 8), System.getenv().getOrDefault("XMAGE_PASSWORD", "")); }
                    catch (Exception error) {
                        if (socket.isOpen()) socket.send(JSON.toJson(object("type", "error", "message", error.getMessage())));
                        remove(created);
                        socket.close(1011, "XMage connection failed");
                    }
                });
            } else if (seat == null || !seat.ready) {
                throw new IllegalStateException("Connect to XMage first.");
            } else if (string(request, "type").equals("leave")) {
                remove(seat);
                socket.close(1000, "Left rules session");
            } else {
                Seat target = seat;
                target.engine.queue.execute(() -> {
                    try { target.engine.command(request); }
                    catch (Exception error) { if (socket.isOpen()) socket.send(JSON.toJson(object("type", "error", "message", error.getMessage()))); }
                });
            }
        } catch (Exception error) {
            socket.send(JSON.toJson(object("type", "error", "message", error.getMessage() == null ? "Invalid message" : error.getMessage())));
        }
    }

    private synchronized void remove(Seat seat) {
        seats.remove(seat.resumeToken);
        if (seat.socket != null) connections.remove(seat.socket);
        seat.engine.close();
    }
    private void makeRoomForSession() {
        expire();
        if (seats.size() < 4) return;
        Seat oldest = seats.values().stream()
                .filter(seat -> seat.socket == null || !seat.socket.isOpen())
                .min(Comparator.comparingLong(seat -> seat.detachedAt)).orElse(null);
        if (oldest == null) throw new IllegalStateException("Four players are currently connected. Disconnect a player before starting another session.");
        remove(oldest);
    }
    private synchronized void expire() {
        long now = System.currentTimeMillis();
        for (Seat seat : new ArrayList<>(seats.values()))
            if (seat.socket == null && now - seat.detachedAt > TimeUnit.MINUTES.toMillis(15)) remove(seat);
    }
    @Override public synchronized void onClose(WebSocket socket, int code, String reason, boolean remote) {
        authorized.remove(socket);
        Seat seat = connections.remove(socket);
        if (seat != null && seat.socket == socket) {
            seat.socket = null; seat.detachedAt = System.currentTimeMillis();
            if (!seat.ready) remove(seat);
        }
    }
    @Override public void onError(WebSocket socket, Exception error) {
        if (socket == null) started.completeExceptionally(error);
        System.err.println("Rules transport: " + error.getClass().getSimpleName());
    }
    @Override public void onStart() {
        started.complete(null);
        System.out.println("Rules bridge listening on " + getAddress() + "; XMage " + engineHost + ":" + enginePort);
    }

    public static void main(String[] args) throws Exception {
        String token = System.getenv("RULES_BRIDGE_TOKEN");
        if (token == null || token.length() < 16) throw new IllegalArgumentException("RULES_BRIDGE_TOKEN must contain at least 16 characters.");
        String bind = System.getenv().getOrDefault("RULES_BRIDGE_BIND", "127.0.0.1");
        int port = Integer.parseInt(System.getenv().getOrDefault("RULES_BRIDGE_PORT", "17180"));
        String host = System.getenv().getOrDefault("XMAGE_HOST", "127.0.0.1");
        int enginePort = Integer.parseInt(System.getenv().getOrDefault("XMAGE_PORT", "17171"));
        BridgeMain server = new BridgeMain(bind, port, token, host, enginePort);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            server.cleanup.shutdownNow();
            synchronized (server) { for (Seat seat : new ArrayList<>(server.seats.values())) server.remove(seat); }
            try { server.stop(1000); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        }));
        server.start();
        try { server.started.get(15, TimeUnit.SECONDS); }
        catch (Exception error) {
            System.err.println("Rules bridge could not start. Check the bind address and whether port " + port + " is already in use.");
            // A failed WebSocket bind leaves the cleanup executor alive. Exit the process so a
            // Windows service or shell reports failure instead of appearing to run a dead bridge.
            System.exit(1);
        }
    }
}
