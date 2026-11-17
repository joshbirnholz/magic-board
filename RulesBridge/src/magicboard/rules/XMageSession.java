package magicboard.rules;

import com.google.gson.*;
import mage.cards.decks.*;
import mage.constants.*;
import mage.game.match.MatchOptions;
import mage.interfaces.MageClient;
import mage.interfaces.callback.*;
import mage.players.PlayerType;
import mage.players.net.UserData;
import mage.remote.*;
import mage.utils.MageVersion;
import mage.view.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** A normal XMage client. All protocol work and callbacks run on one session queue. */
final class XMageSession implements MageClient, AutoCloseable {
    static final Gson JSON = new Gson();
    final ExecutorService queue = Executors.newSingleThreadExecutor();
    private final SessionImpl session = new SessionImpl(this);
    private final Consumer<JsonObject> output;
    private UUID gameId;
    private UUID playerId;
    private JsonObject snapshot;
    private JsonObject prompt;
    private long revision;
    private int lastStateMessage = -1;
    private final Set<UUID> joinedGames = new HashSet<>();
    private final LinkedHashMap<String, JsonObject> receipts = new LinkedHashMap<>();
    private final ScheduledExecutorService heartbeat = Executors.newSingleThreadScheduledExecutor();
    private volatile boolean closed;

    XMageSession(Consumer<JsonObject> output) { this.output = output; }

    void connect(String host, int port, String username, String password) {
        Connection connection = new Connection();
        connection.setHost(host);
        connection.setPort(port);
        connection.setUsername(username);
        connection.setPassword(password);
        connection.setProxyType(Connection.ProxyType.NONE);
        connection.setUserIdStr(UUID.randomUUID().toString());
        connection.setUserData(UserData.getDefaultUserDataView());
        if (!session.connectStart(connection)) throw new IllegalStateException("XMage login failed: " + session.getLastError());
        heartbeat.scheduleWithFixedDelay(() -> queue.execute(session::ping), 5, 5, TimeUnit.SECONDS);
        output.accept(object("type", "ready", "engineVersion", getVersion().toString(), "protocolVersion", 1));
    }

    void command(JsonObject request) {
        String requestId = string(request, "requestId");
        if (requestId.isEmpty()) throw new IllegalArgumentException("A request ID is required.");
        if (receipts.containsKey(requestId)) { output.accept(receipts.get(requestId)); return; }
        try {
            switch (string(request, "type")) {
                case "createAiGame" -> createAiGame();
                case "answer" -> answer(request);
                case "resync" -> replay();
                default -> throw new IllegalArgumentException("Unsupported command.");
            }
            remember(requestId, object("type", "ack", "requestId", requestId));
        } catch (Exception error) {
            remember(requestId, object("type", "error", "requestId", requestId, "message", error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage()));
        }
    }

    private void remember(String id, JsonObject result) {
        receipts.put(id, result);
        if (receipts.size() > 256) receipts.remove(receipts.keySet().iterator().next());
        output.accept(result);
    }

    void replay() {
        if (snapshot != null) output.accept(snapshot);
        if (prompt != null) output.accept(prompt);
    }

    private void createAiGame() {
        if (gameId != null || !joinedGames.isEmpty()) throw new IllegalStateException("This session already has a game.");
        MatchOptions options = new MatchOptions("Magic Board Rules Spike", "Two Player Duel", false);
        options.setDeckType("Limited");
        options.setWinsNeeded(1);
        options.setMatchTimeLimit(MatchTimeLimit.NONE);
        options.setMatchBufferTime(MatchBufferTime.NONE);
        options.setAttackOption(MultiplayerAttackOption.MULTIPLE);
        options.setRange(RangeOfInfluence.ALL);
        options.getPlayerTypes().add(PlayerType.HUMAN);
        options.getPlayerTypes().add(PlayerType.COMPUTER_MAD);
        UUID room = session.getMainRoomId();
        TableView table = session.createTable(room, options);
        if (table == null) throw new IllegalStateException("XMage could not create the table.");
        UUID tableId = table.getTableId();
        try {
            if (!session.joinTable(room, tableId, "Magic Board", PlayerType.HUMAN, 1, simpleDeck(), "")
                    || !session.joinTable(room, tableId, "Computer", PlayerType.COMPUTER_MAD, 1, simpleDeck(), "")
                    || !session.startMatch(room, tableId)) {
                throw new IllegalStateException("XMage could not start the AI game. Check the server log.");
            }
        } catch (RuntimeException failure) {
            session.removeTable(room, tableId);
            throw failure;
        }
    }

    private static DeckCardLists simpleDeck() {
        DeckCardLists deck = new DeckCardLists();
        deck.setName("Rules Spike — white creatures");
        deck.getCards().add(new DeckCardInfo("Plains", "230", "M10", 24));
        deck.getCards().add(new DeckCardInfo("Silvercoat Lion", "31", "M10", 18));
        deck.getCards().add(new DeckCardInfo("Siege Mastodon", "30", "M10", 18));
        return deck;
    }

    private void answer(JsonObject request) {
        if (prompt == null || !string(prompt, "id").equals(string(request, "promptId")))
            throw new IllegalStateException("That choice has expired. Refresh the game.");
        if (request.get("revision") == null || request.get("revision").getAsLong() != revision)
            throw new IllegalStateException("The game has changed. Refresh before answering.");
        String kind = string(request, "kind");
        JsonElement value = request.get("value");
        if (value == null) throw new IllegalArgumentException("An answer is required.");
        String method = string(prompt, "method");
        boolean sent;
        switch (kind) {
            case "boolean" -> {
                if (!Set.of("GAME_ASK", "GAME_SELECT", "GAME_PLAY_MANA", "GAME_PLAY_XMANA", "GAME_CHOOSE_PILE", "GAME_TARGET").contains(method))
                    throw new IllegalArgumentException("This prompt does not accept a boolean.");
                sent = session.sendPlayerBoolean(gameId, value.getAsBoolean());
            }
            case "uuid" -> {
                if (!Set.of("GAME_SELECT", "GAME_TARGET", "GAME_PLAY_MANA", "GAME_PLAY_XMANA").contains(method))
                    throw new IllegalArgumentException("This prompt does not accept an object.");
                sent = session.sendPlayerUUID(gameId, UUID.fromString(value.getAsString()));
            }
            case "integer" -> {
                if (!method.equals("GAME_GET_AMOUNT")) throw new IllegalArgumentException("This prompt does not accept a number.");
                int number = value.getAsInt();
                if (number < prompt.get("min").getAsInt() || number > prompt.get("max").getAsInt())
                    throw new IllegalArgumentException("Number outside the allowed range.");
                sent = session.sendPlayerInteger(gameId, number);
            }
            case "string" -> {
                if (!Set.of("GAME_CHOOSE_CHOICE", "GAME_CHOOSE_ABILITY").contains(method))
                    throw new IllegalArgumentException("This prompt does not accept a choice.");
                String choice = value.getAsString();
                boolean valid = false;
                for (JsonElement entry : prompt.getAsJsonArray("choices"))
                    if (string(entry.getAsJsonObject(), "id").equals(choice)) valid = true;
                if (!valid) throw new IllegalArgumentException("Unknown choice.");
                sent = session.sendPlayerString(gameId, choice);
            }
            default -> throw new IllegalArgumentException("Unsupported answer type.");
        }
        if (!sent) throw new IllegalStateException("XMage did not accept the answer.");
        prompt = null;
        output.accept(object("type", "promptCleared"));
    }

    @Override public void onCallback(ClientCallback callback) {
        if (closed) return;
        callback.decompressData();
        queue.execute(() -> {
            try { handle(callback); }
            catch (Exception error) { showError("Unable to process " + callback.getMethod() + ": " + error.getMessage()); }
        });
    }

    private void handle(ClientCallback callback) {
        Object data = callback.getData();
        String method = callback.getMethod().name();
        if (callback.getMethod() == ClientCallbackMethod.START_GAME) {
            TableClientMessage message = (TableClientMessage) data;
            gameId = message.getGameId();
            playerId = message.getPlayerId();
            if (joinedGames.add(gameId) && !session.joinGame(gameId)) showError("Could not join the started game.");
            return;
        }
        GameView view = data instanceof GameView ? (GameView) data : data instanceof GameClientMessage ? ((GameClientMessage) data).getGameView()
                : data instanceof AbilityPickerView ? ((AbilityPickerView) data).getGameView() : null;
        if (view != null && callback.getMessageId() >= lastStateMessage) {
            lastStateMessage = callback.getMessageId();
            gameId = callback.getObjectId();
            if (view.getMyPlayer() != null) playerId = view.getMyPlayer().getPlayerId();
            snapshot = snapshot(view);
            output.accept(snapshot);
        }
        if (callback.getMethod().getType() == ClientCallbackType.DIALOG && method.startsWith("GAME_")) {
            prompt = makePrompt(callback, data);
            output.accept(prompt);
        } else if (callback.getMethod() == ClientCallbackMethod.GAME_OVER) {
            prompt = null;
            output.accept(object("type", "gameOver", "message", ((GameClientMessage) data).getMessage()));
        } else if (callback.getMethod() == ClientCallbackMethod.GAME_ERROR) {
            showError(String.valueOf(data));
        }
    }

    private JsonObject snapshot(GameView view) {
        JsonObject result = object("type", "snapshot", "gameId", gameId, "playerId", playerId,
                "revision", ++revision, "turn", view.getTurn(), "phase", view.getPhase(), "step", view.getStep(),
                "activePlayer", view.getActivePlayerName(), "priorityPlayer", view.getPriorityPlayerName());
        result.add("hand", cards(view.getMyHand().values()));
        result.add("stack", cards(view.getStack().values()));
        JsonArray playable = new JsonArray();
        if (view.getCanPlayObjects() != null) view.getCanPlayObjects().getObjects().keySet().forEach(id -> playable.add(id.toString()));
        result.add("playableIds", playable);
        JsonArray players = new JsonArray();
        for (PlayerView player : view.getPlayers()) {
            JsonObject item = object("id", player.getPlayerId(), "name", player.getName(), "life", player.getLife(),
                    "handCount", player.getHandCount(), "libraryCount", player.getLibraryCount());
            item.add("battlefield", cards(player.getBattlefield().values()));
            item.add("graveyard", cards(player.getGraveyard().values()));
            item.add("exile", cards(player.getExile().values()));
            players.add(item);
        }
        result.add("players", players);
        // XMage already filtered this view for this player. Never construct a combined view of both hands.
        return result;
    }

    private JsonObject makePrompt(ClientCallback callback, Object data) {
        String method = callback.getMethod().name();
        JsonObject result = object("type", "prompt", "id", UUID.randomUUID(), "method", method, "revision", revision);
        JsonArray choices = new JsonArray();
        if (data instanceof GameClientMessage message) {
            result.addProperty("message", message.getMessage());
            result.addProperty("min", message.getMin());
            result.addProperty("max", message.getMax());
            result.addProperty("required", message.isFlag());
            result.add("cards", message.getCardsView1() == null ? new JsonArray() : cards(message.getCardsView1().values()));
            JsonArray targets = new JsonArray();
            if (message.getTargets() != null) message.getTargets().forEach(id -> targets.add(id.toString()));
            result.add("targets", targets);
            if (message.getChoice() != null) {
                result.addProperty("message", message.getChoice().getMessage());
                if (message.getChoice().isKeyChoice()) message.getChoice().getKeyChoices().forEach((id, label) -> choices.add(object("id", id, "label", label)));
                else message.getChoice().getChoices().forEach(label -> choices.add(object("id", label, "label", label)));
            }
        } else if (data instanceof AbilityPickerView picker) {
            result.addProperty("message", picker.getMessage());
            picker.getChoices().forEach((id, label) -> choices.add(object("id", id, "label", label)));
        }
        result.add("choices", choices);
        result.addProperty("supported", !Set.of("GAME_GET_MULTI_AMOUNT", "GAME_CHOOSE_PILE").contains(method));
        return result;
    }

    private static JsonArray cards(Collection<? extends CardView> cards) {
        JsonArray result = new JsonArray();
        for (CardView card : cards) {
            JsonObject item = object("id", card.getId(), "name", card.getDisplayName(), "set", card.getExpansionSetCode(),
                    "collectorNumber", card.getCardNumber(), "faceDown", card.isFaceDown(), "transformed", card.isTransformed(),
                    "power", card.getPower(), "toughness", card.getToughness(), "rules", String.join("\n", card.getRules() == null ? List.of() : card.getRules()));
            if (card instanceof PermanentView permanent) {
                item.addProperty("tapped", permanent.isTapped());
                item.addProperty("damage", permanent.getDamage());
                item.addProperty("attachedTo", permanent.getAttachedTo() == null ? null : permanent.getAttachedTo().toString());
            }
            JsonArray counters = new JsonArray();
            if (card.getCounters() != null) card.getCounters().forEach(counter -> counters.add(object("name", counter.getName(), "count", counter.getCount())));
            item.add("counters", counters);
            result.add(item);
        }
        return result;
    }

    static JsonObject object(Object... pairs) {
        JsonObject result = new JsonObject();
        for (int i = 0; i < pairs.length; i += 2) result.add(String.valueOf(pairs[i]), JSON.toJsonTree(pairs[i + 1]));
        return result;
    }
    static String string(JsonObject object, String key) {
        JsonElement value = object.get(key);
        return value == null || value.isJsonNull() ? "" : value.getAsString();
    }
    @Override public MageVersion getVersion() { return new MageVersion(mage.interfaces.MageClient.class); }
    @Override public void onNewConnection() { }
    @Override public void connected(String message) { }
    @Override public void disconnected(boolean reconnect, boolean keep) { output.accept(object("type", "engineDisconnected", "message", "The bridge lost its XMage server connection.")); }
    @Override public void showMessage(String message) { output.accept(object("type", "notice", "message", message)); }
    @Override public void showError(String message) { output.accept(object("type", "error", "message", message)); }
    @Override public void close() {
        closed = true;
        heartbeat.shutdownNow();
        queue.execute(() -> {
            if (gameId != null && session.isConnected()) session.quitMatch(gameId);
            session.connectStop(false, false);
        });
        queue.shutdown();
    }
}
