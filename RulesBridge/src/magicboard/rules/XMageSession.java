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
import mage.util.MultiAmountMessage;
import mage.view.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** A normal XMage client. All protocol work and callbacks run on one session queue. */
final class XMageSession implements MageClient, AutoCloseable {
    static final Gson JSON = new Gson();
    final ExecutorService queue = Executors.newSingleThreadExecutor();
    private final SessionImpl session = new SessionImpl(this);
    private final UserData userData = UserData.getDefaultUserDataView();
    private final Consumer<JsonObject> output;
    private UUID gameId;
    private UUID playerId;
    private UUID tableId;
    private boolean ownsTable;
    private boolean holdingPriority;
    private JsonObject snapshot;
    /** Stack object → controlling player. XMage's stack views don't carry a controller, so it's inferred once and kept. */
    private final Map<UUID, UUID> stackControllers = new HashMap<>();
    /** Card or permanent → the player whose zone it was last seen in. */
    private final Map<UUID, UUID> lastSeenSeat = new HashMap<>();
    private UUID lastPriorityPlayer;
    private JsonObject prompt;
    private JsonObject gameOver;
    private List<MultiAmountMessage> amountConstraints;
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
        connection.setUserData(userData);
        if (!session.connectStart(connection)) throw new IllegalStateException("XMage login failed: " + session.getLastError());
        if (closed) throw new CancellationException("Connection cancelled.");
        heartbeat.scheduleWithFixedDelay(() -> queue.execute(session::ping), 5, 5, TimeUnit.SECONDS);
        output.accept(object("type", "ready", "engineVersion", getVersion().toString(), "protocolVersion", 1, "formats", availableFormats()));
    }

    void command(JsonObject request) {
        String requestId = string(request, "requestId");
        if (requestId.isEmpty()) throw new IllegalArgumentException("A request ID is required.");
        if (receipts.containsKey(requestId)) { output.accept(receipts.get(requestId)); return; }
        try {
            switch (string(request, "type")) {
                case "createAiGame" -> createGame(true, request);
                case "createHumanGame" -> createGame(false, request);
                case "listTables" -> listTables();
                case "joinTable" -> joinTable(UUID.fromString(string(request, "tableId")), request);
                case "startMatch" -> startMatch();
                case "answer" -> answer(request);
                case "priorityControl" -> priorityControl(request);
                case "settings" -> updateSettings(request);
                case "resync" -> replay();
                default -> throw new IllegalArgumentException("Unsupported command.");
            }
            remember(requestId, object("type", "ack", "requestId", requestId));
        } catch (Exception error) {
            remember(requestId, object("type", "error", "requestId", requestId, "message", error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage()));
            if (Set.of("answer", "priorityControl").contains(string(request, "type"))) replay();
        }
    }

    private void remember(String id, JsonObject result) {
        receipts.put(id, result);
        if (receipts.size() > 256) receipts.remove(receipts.keySet().iterator().next());
        output.accept(result);
    }

    void replay() {
        publishSettings();
        if (tableId != null && gameId == null) output.accept(object("type", "tableJoined", "tableId", tableId, "owner", ownsTable));
        if (snapshot != null) output.accept(snapshot);
        if (prompt != null) output.accept(prompt);
        if (gameOver != null) output.accept(gameOver);
    }

    private void publishSettings() {
        output.accept(object("type", "prioritySettings", "holdingPriority", holdingPriority, "autoOrderTriggers", userData.isAutoOrderTrigger()));
    }

    private void updateSettings(JsonObject request) {
        if (!request.has("autoOrderTriggers") || !request.get("autoOrderTriggers").isJsonPrimitive()
                || !request.getAsJsonPrimitive("autoOrderTriggers").isBoolean())
            throw new IllegalArgumentException("Choose whether to order triggers automatically.");
        boolean previous = userData.isAutoOrderTrigger();
        userData.setAutoOrderTrigger(request.get("autoOrderTriggers").getAsBoolean());
        if (!session.updatePreferencesForServer(userData)) {
            userData.setAutoOrderTrigger(previous);
            throw new IllegalStateException("XMage did not accept the trigger-order setting.");
        }
        publishSettings();
    }

    private void priorityControl(JsonObject request) {
        if (gameId == null) throw new IllegalStateException("Start a game before changing priority controls.");
        String action = string(request, "priorityAction");
        PlayerAction engineAction = PromptAnswers.priorityAction(action);
        boolean skip = !Set.of("hold", "release", "cancelAutoPass").contains(action);
        if (skip) {
            requireCurrentPrompt(request);
            if (!string(prompt, "method").equals("GAME_SELECT"))
                throw new IllegalStateException("You can only auto-pass while you have priority.");
        }
        if (!session.sendPlayerAction(engineAction, gameId, null)) throw new IllegalStateException("XMage did not accept the priority control.");
        if (action.equals("hold")) holdingPriority = true;
        if (action.equals("release")) holdingPriority = false;
        publishSettings();
        if (skip) { prompt = null; output.accept(object("type", "promptCleared")); }
    }

    private void requireNoTable() {
        if (gameId != null || tableId != null) throw new IllegalStateException("This session already has a game or waiting table.");
    }

    private List<String> availableFormats() {
        Set<String> supported = Set.of("Limited", "Constructed - Standard", "Constructed - Pioneer", "Constructed - Modern",
                "Constructed - Legacy", "Constructed - Vintage", "Constructed - Pauper");
        return Arrays.stream(session.getDeckTypes()).filter(supported::contains).toList();
    }

    private void createGame(boolean ai, JsonObject request) {
        requireNoTable();
        String format = string(request, "format");
        if (format.isEmpty()) format = "Limited";
        if (!availableFormats().contains(format)) throw new IllegalArgumentException("This deck format is not available.");
        DeckCardLists deck = readDeck(request);
        MatchOptions options = new MatchOptions("Magic Board Rules", "Two Player Duel", false);
        options.setDeckType(format);
        options.setWinsNeeded(1);
        options.setMatchTimeLimit(MatchTimeLimit.NONE);
        options.setMatchBufferTime(MatchBufferTime.NONE);
        options.setAttackOption(MultiplayerAttackOption.MULTIPLE);
        options.setRange(RangeOfInfluence.ALL);
        options.getPlayerTypes().add(PlayerType.HUMAN);
        options.getPlayerTypes().add(ai ? PlayerType.COMPUTER_MAD : PlayerType.HUMAN);
        UUID room = session.getMainRoomId();
        TableView table = session.createTable(room, options);
        if (table == null) throw new IllegalStateException("XMage could not create the table.");
        tableId = table.getTableId();
        ownsTable = true;
        try {
            if (!session.joinTable(room, tableId, ai ? "Magic Board" : "Player 1", PlayerType.HUMAN, 1, deck, ""))
                throw new IllegalStateException("XMage could not seat you at the table.");
            if (ai) {
                // JumpStart / Jump In: the AI brings its own packets; otherwise it mirrors the player's deck.
                DeckCardLists aiDeck = request.has("aiDeck") && !request.get("aiDeck").isJsonNull() ? readDeck(request, "aiDeck") : deck.copy();
                if (!session.joinTable(room, tableId, "Computer", PlayerType.COMPUTER_MAD, 1, aiDeck, "")
                        || !session.startMatch(room, tableId))
                    throw new IllegalStateException("XMage could not start the AI game. Check the server log.");
            } else {
                output.accept(object("type", "tableJoined", "tableId", tableId, "owner", true));
            }
        } catch (RuntimeException failure) {
            session.removeTable(room, tableId);
            tableId = null; ownsTable = false;
            throw failure;
        }
    }

    private void listTables() throws MageRemoteException {
        JsonArray tables = new JsonArray();
        for (TableView table : session.getTables(session.getMainRoomId())) {
            if (!table.getTableName().startsWith("Magic Board Rules") || table.getTableState() != TableState.WAITING) continue;
            long occupied = table.getSeats().stream().filter(seat -> seat.getPlayerId() != null).count();
            tables.add(object("id", table.getTableId(), "name", table.getTableName(), "players", occupied, "capacity", table.getSeats().size(), "format", table.getDeckType()));
        }
        JsonObject event = object("type", "tables");
        event.add("tables", tables);
        output.accept(event);
    }

    private void joinTable(UUID id, JsonObject request) {
        requireNoTable();
        DeckCardLists deck = readDeck(request);
        TableView table = session.getTable(session.getMainRoomId(), id).orElseThrow(() -> new IllegalArgumentException("This waiting game no longer exists."));
        if (!table.getTableName().startsWith("Magic Board Rules") || table.getTableState() != TableState.WAITING)
            throw new IllegalStateException("This game is no longer waiting for players.");
        if (!session.joinTable(session.getMainRoomId(), id, "Player 2", PlayerType.HUMAN, 1, deck, ""))
            throw new IllegalStateException("XMage could not join the game. It may already be full.");
        tableId = id; ownsTable = false;
        output.accept(object("type", "tableJoined", "tableId", id, "owner", false));
    }

    private void startMatch() {
        if (tableId == null || !ownsTable || gameId != null) throw new IllegalStateException("Only the waiting game's creator can start it.");
        if (!session.startMatch(session.getMainRoomId(), tableId))
            throw new IllegalStateException("The game could not start. Wait for the second player to join, then try again.");
    }

    private static DeckCardLists simpleDeck() {
        DeckCardLists deck = new DeckCardLists();
        deck.setName("Rules Spike — white creatures");
        deck.getCards().add(CardPrintings.resolve("Plains", "M10", "", 24));
        deck.getCards().add(CardPrintings.resolve("Silvercoat Lion", "M10", "", 18));
        deck.getCards().add(CardPrintings.resolve("Siege Mastodon", "M10", "", 18));
        return deck;
    }

    private static DeckCardLists readDeck(JsonObject request) { return readDeck(request, "deck"); }

    private static DeckCardLists readDeck(JsonObject request, String key) {
        if (!request.has(key) || request.get(key).isJsonNull()) return simpleDeck();
        JsonObject input = request.getAsJsonObject(key);
        DeckCardLists deck = new DeckCardLists();
        String name = string(input, "name");
        deck.setName(name.isEmpty() ? "Imported Deck" : name.substring(0, Math.min(100, name.length())));
        readCards(input.getAsJsonArray("main"), deck.getCards(), 500);
        readCards(input.getAsJsonArray("sideboard"), deck.getSideboard(), 100);
        if (deck.getCards().isEmpty()) throw new IllegalArgumentException("The deck is empty.");
        return deck;
    }

    private static void readCards(JsonArray rows, List<DeckCardInfo> destination, int maxCards) {
        if (rows == null) return;
        if (rows.size() > maxCards) throw new IllegalArgumentException("The deck has too many entries.");
        int total = 0;
        for (JsonElement row : rows) {
            JsonObject card = row.getAsJsonObject();
            String name = string(card, "name").trim();
            int count = card.get("count").getAsBigDecimal().intValueExact();
            total += count;
            if (name.isEmpty() || name.length() > 200 || count < 1 || count > 99 || total > maxCards)
                throw new IllegalArgumentException("Invalid card name or quantity in deck list.");
            String number = string(card, "collectorNumber");
            String set = string(card, "set").toUpperCase(Locale.ROOT);
            destination.add(CardPrintings.resolve(name, set, number, count));
        }
    }

    private void requireCurrentPrompt(JsonObject request) {
        if (prompt == null || !string(prompt, "id").equals(string(request, "promptId")))
            throw new IllegalStateException("That choice has expired. Refresh the game.");
        if (request.get("revision") == null || request.get("revision").getAsLong() != revision)
            throw new IllegalStateException("The game has changed. Refresh before answering.");
    }

    private void answer(JsonObject request) {
        requireCurrentPrompt(request);
        String kind = string(request, "kind");
        JsonElement value = request.get("value");
        if (value == null) throw new IllegalArgumentException("An answer is required.");
        String method = string(prompt, "method");
        boolean sent;
        switch (kind) {
            case "special" -> {
                if (!prompt.has("specialActionAvailable") || !prompt.get("specialActionAvailable").getAsBoolean())
                    throw new IllegalArgumentException("No special action is available.");
                sent = session.sendPlayerString(gameId, "special");
            }
            case "cancel" -> {
                if (!prompt.has("canCancel") || !prompt.get("canCancel").getAsBoolean())
                    throw new IllegalArgumentException("This choice cannot be cancelled.");
                sent = method.equals("GAME_CHOOSE_CHOICE")
                        ? session.sendPlayerString(gameId, null) : session.sendPlayerBoolean(gameId, false);
            }
            case "boolean" -> {
                if (method.equals("GAME_GET_MULTI_AMOUNT")) {
                    if (!Boolean.TRUE.equals(prompt.has("canCancel") && prompt.get("canCancel").getAsBoolean()) || value.getAsBoolean())
                        throw new IllegalArgumentException("This distribution cannot be cancelled.");
                } else if (!Set.of("GAME_ASK", "GAME_SELECT", "GAME_PLAY_MANA", "GAME_PLAY_XMANA", "GAME_CHOOSE_PILE", "GAME_TARGET", "GAME_CHOOSE_ABILITY").contains(method))
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
                sent = method.equals("GAME_CHOOSE_ABILITY")
                        ? session.sendPlayerUUID(gameId, UUID.fromString(choice))
                        : session.sendPlayerString(gameId, choice);
            }
            case "amounts" -> {
                if (!method.equals("GAME_GET_MULTI_AMOUNT") || amountConstraints == null)
                    throw new IllegalArgumentException("This prompt does not accept distributed amounts.");
                List<Integer> amounts = new ArrayList<>();
                for (JsonElement amount : value.getAsJsonArray()) amounts.add(amount.getAsBigDecimal().intValueExact());
                String encoded = PromptAnswers.amounts(amounts, amountConstraints, prompt.get("min").getAsInt(), prompt.get("max").getAsInt());
                sent = session.sendPlayerString(gameId, encoded);
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
        try {
            queue.execute(() -> {
                try { handle(callback); }
                catch (Exception error) { showError("Unable to process " + callback.getMethod() + ": " + error.getMessage()); }
            });
        } catch (RejectedExecutionException error) {
            if (!closed) throw error;
        }
    }

    private void handle(ClientCallback callback) {
        Object data = callback.getData();
        String method = callback.getMethod().name();
        if (callback.getMethod() == ClientCallbackMethod.CHATMESSAGE) {
            if (data instanceof mage.view.ChatMessage chat && chat.getMessageType() == mage.view.ChatMessage.MessageType.GAME
                    && chat.getMessage() != null && !chat.getMessage().isBlank()) {
                output.accept(object("type", "log", "message", chat.getMessage()));
            }
            return;
        }
        if (callback.getMethod() == ClientCallbackMethod.START_GAME) {
            TableClientMessage message = (TableClientMessage) data;
            gameId = message.getGameId();
            playerId = message.getPlayerId();
            if (joinedGames.add(gameId)) {
                if (!session.joinGame(gameId)) showError("Could not join the started game.");
                // XMage's game log ("Computer reveals Forest") is sent to the game's chat.
                session.getGameChatId(gameId).ifPresent(session::joinChat);
            }
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
            gameOver = object("type", "gameOver", "message", ((GameClientMessage) data).getMessage());
            output.accept(gameOver);
        } else if (callback.getMethod() == ClientCallbackMethod.GAME_ERROR) {
            showError(String.valueOf(data));
        } else if (callback.getMethod() == ClientCallbackMethod.GAME_INFORM_PERSONAL && data instanceof GameClientMessage message
                && message.getMessage() != null && !message.getMessage().isBlank()) {
            // Engine messages meant just for this player (for example why an action was refused).
            showMessage(message.getMessage());
        }
    }

    private JsonObject snapshot(GameView view) {
        JsonObject result = object("type", "snapshot", "gameId", gameId, "playerId", playerId,
                "revision", ++revision, "turn", view.getTurn(), "phase", view.getPhase(), "step", view.getStep(),
                "activePlayer", view.getActivePlayerName(), "activePlayerId", view.getActivePlayerId(), "priorityPlayer", view.getPriorityPlayerName());
        if (view.getMyPlayer() != null) {
            PlayerView me = view.getMyPlayer();
            result.add("priority", object("untilNextTurn", me.isPassedTurn(), "untilEndStep", me.isPassedUntilEndOfTurn(),
                    "untilNextMain", me.isPassedUntilNextMain(), "untilYourTurn", me.isPassedAllTurns(),
                    "untilStackResolved", me.isPassedUntilStackResolved()));
        }
        result.add("hand", cards(view.getMyHand().values()));
        // These collections are already filtered by XMage for this seat. Never reconstruct
        // another player's hidden hand from a shared or spectator view.
        JsonArray revealed = new JsonArray(), lookedAt = new JsonArray();
        if (view.getRevealed() != null) for (RevealedView group : view.getRevealed()) {
            JsonObject item = object("name", group.getName() == null ? "Revealed cards" : group.getName());
            item.add("cards", cards(group.getCards().values())); revealed.add(item);
        }
        if (view.getLookedAt() != null) for (LookedAtView group : view.getLookedAt()) {
            JsonObject item = object("name", group.getName() == null ? "Looked at cards" : group.getName());
            JsonArray visible = new JsonArray();
            for (SimpleCardView card : group.getCards().values()) {
                if (card instanceof CardView full) visible.add(cards(List.of(full)).get(0));
                else {
                    JsonObject face = object("id", card.getId(), "set", card.getExpansionSetCode(),
                            "collectorNumber", card.getCardNumber(), "faceDown", false, "transformed", false,
                            "name", CardPrintings.nameForPrinting(card.getExpansionSetCode(), card.getCardNumber()));
                    face.add("counters", new JsonArray()); visible.add(face);
                }
            }
            item.add("cards", visible); lookedAt.add(item);
        }
        result.add("revealed", revealed); result.add("lookedAt", lookedAt);
        JsonArray stack = cards(view.getStack().values());
        Map<UUID, UUID> seen = new HashMap<>();
        if (playerId != null) view.getMyHand().keySet().forEach(id -> seen.put(id, playerId));
        for (PlayerView player : view.getPlayers()) {
            for (CardsView zone : List.of(player.getGraveyard(), player.getExile())) zone.keySet().forEach(id -> seen.put(id, player.getPlayerId()));
            player.getBattlefield().keySet().forEach(id -> seen.put(id, player.getPlayerId())); // by controller
        }
        Set<UUID> onStack = new HashSet<>();
        int index = 0;
        for (CardView card : view.getStack().values()) {
            UUID id = card.getId();
            onStack.add(id);
            UUID controller = stackControllers.get(id);
            if (controller == null && card instanceof StackAbilityView ability && ability.getSourceCard() != null) {
                // Triggered and activated abilities: whoever controls (or last held) the source.
                UUID source = ability.getSourceCard().getId();
                controller = seen.getOrDefault(source, lastSeenSeat.get(source));
            }
            // Spells and unattributed abilities: the player who held priority when it was put on the stack.
            if (controller == null) controller = lastPriorityPlayer;
            if (controller != null) {
                stackControllers.put(id, controller);
                stack.get(index).getAsJsonObject().addProperty("controllerId", controller.toString());
            }
            index++;
        }
        stackControllers.keySet().retainAll(onStack);
        lastSeenSeat.putAll(seen);
        if (lastSeenSeat.size() > 4000) lastSeenSeat.keySet().retainAll(seen.keySet());
        lastPriorityPlayer = view.getPlayers().stream().filter(player -> player.getName().equals(view.getPriorityPlayerName()))
                .map(PlayerView::getPlayerId).findFirst().orElse(lastPriorityPlayer);
        result.add("stack", stack);
        JsonArray playable = new JsonArray();
        if (view.getCanPlayObjects() != null) view.getCanPlayObjects().getObjects().forEach((id, stats) -> {
            // On the battlefield, ignore basic mana abilities so untapped lands don't all look playable
            // (Arena doesn't highlight them). Elsewhere, playing a land counts.
            boolean permanent = view.getPlayers().stream().anyMatch(player -> player.getBattlefield().containsKey(id));
            if (permanent ? stats.getPlayableImportantAmount() > 0 : stats.getPlayableAmount() > 0) playable.add(id.toString());
        });
        result.add("playableIds", playable);
        JsonArray players = new JsonArray();
        for (PlayerView player : view.getPlayers()) {
            JsonObject item = object("id", player.getPlayerId(), "name", player.getName(), "life", player.getLife(),
                    "handCount", player.getHandCount(), "libraryCount", player.getLibraryCount());
            item.add("battlefield", cards(player.getBattlefield().values()));
            item.add("graveyard", cards(player.getGraveyard().values()));
            item.add("exile", cards(player.getExile().values()));
            JsonArray counters = new JsonArray();
            if (player.getCounters() != null) player.getCounters().forEach(counter -> counters.add(object("name", counter.getName(), "count", counter.getCount())));
            item.add("counters", counters);
            // Floating mana (Arena shows it by the life total); XMage spends it on costs first.
            if (player.getManaPool() != null) {
                var pool = player.getManaPool();
                item.add("manaPool", object("W", pool.getWhite(), "U", pool.getBlue(), "B", pool.getBlack(),
                        "R", pool.getRed(), "G", pool.getGreen(), "C", pool.getColorless()));
            }
            players.add(item);
        }
        result.add("players", players);
        JsonArray combat = new JsonArray();
        for (CombatGroupView group : view.getCombat()) {
            JsonObject item = object("defenderId", group.getDefenderId());
            JsonArray attackers = new JsonArray();
            group.getAttackers().keySet().forEach(id -> attackers.add(id.toString()));
            JsonArray blockers = new JsonArray();
            group.getBlockers().keySet().forEach(id -> blockers.add(id.toString()));
            item.add("attackers", attackers); item.add("blockers", blockers);
            combat.add(item);
        }
        result.add("combat", combat);
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
            PromptMetadata.apply(method, message, result);
            JsonArray suppliedCards = message.getCardsView1() == null ? new JsonArray() : cards(message.getCardsView1().values());
            result.add("cards", PromptContextCards.forQuestion(method, message.getMessage(), snapshot, suppliedCards));
            result.add("secondPile", message.getCardsView2() == null ? new JsonArray() : cards(message.getCardsView2().values()));
            JsonArray targets = new JsonArray();
            if (message.getTargets() != null) message.getTargets().forEach(id -> targets.add(id.toString()));
            result.add("targets", targets);
            if (message.getChoice() != null) {
                result.addProperty("message", message.getChoice().getMessage());
                if (message.getChoice().isKeyChoice()) message.getChoice().getKeyChoices().forEach((id, label) -> choices.add(object("id", id, "label", label)));
                else message.getChoice().getChoices().forEach(label -> choices.add(object("id", label, "label", label)));
            }
            if (method.equals("GAME_GET_MULTI_AMOUNT")) {
                amountConstraints = message.getMessages();
                List<Integer> defaults = MultiAmountType.prepareDefaultValues(amountConstraints, message.getMin(), message.getMax());
                JsonArray amounts = new JsonArray();
                for (int i = 0; i < amountConstraints.size(); i++) {
                    MultiAmountMessage amount = amountConstraints.get(i);
                    amounts.add(object("label", amount.message, "min", amount.min, "max", amount.max, "defaultValue", defaults.get(i)));
                }
                result.add("amounts", amounts);
                if (message.getOptions() != null) {
                    result.addProperty("message", String.valueOf(message.getOptions().getOrDefault("header", "Choose amounts")));
                    result.addProperty("canCancel", Boolean.TRUE.equals(message.getOptions().get("canCancel")));
                }
            }
        } else if (data instanceof AbilityPickerView picker) {
            result.addProperty("message", picker.getMessage());
            result.addProperty("canCancel", true); // Desktop AbilityPicker.popupMenuCanceled sends false.
            picker.getChoices().forEach((id, label) -> choices.add(object("id", id, "label", label)));
        }
        result.add("choices", choices);
        result.addProperty("supported", PromptMetadata.METHODS.contains(method));
        return result;
    }

    private static JsonArray cards(Collection<? extends CardView> cards) {
        JsonArray result = new JsonArray();
        for (CardView card : cards) {
            // A triggered or activated ability on the stack: name and print it as its source card
            // (XMage leaves the ability's own name and printing empty), so the app can show the
            // source's art as Arena does.
            CardView source = card instanceof mage.view.StackAbilityView ability ? ability.getSourceCard() : null;
            String name = card.getDisplayName() == null || card.getDisplayName().isBlank() ? source == null ? null : source.getDisplayName() : card.getDisplayName();
            JsonObject item = object("id", card.getId(), "name", name,
                    "set", source != null ? source.getExpansionSetCode() : card.getExpansionSetCode(),
                    "collectorNumber", source != null ? source.getCardNumber() : card.getCardNumber(), "faceDown", card.isFaceDown(), "transformed", card.isTransformed(),
                    "power", card.getPower(), "toughness", card.getToughness(), "ability", card.isAbility() || source != null,
                    "typeLine", card.getTypeText(), "manaCost", card.getManaCostStr(),
                    "rules", String.join("\n", card.getRules() == null ? List.of() : card.getRules()));
            if (card instanceof PermanentView permanent) {
                item.addProperty("tapped", permanent.isTapped());
                item.addProperty("damage", permanent.getDamage());
                item.addProperty("summoningSick", permanent.hasSummoningSickness());
                item.addProperty("attachedTo", permanent.getAttachedTo() == null ? null : permanent.getAttachedTo().toString());
            }
            JsonArray counters = new JsonArray();
            if (card.getCounters() != null) card.getCounters().forEach(counter -> counters.add(object("name", counter.getName(), "count", counter.getCount())));
            item.add("counters", counters);
            JsonArray colors = new JsonArray();
            if (card.getColor() != null) {
                if (card.getColor().isWhite()) colors.add("W");
                if (card.getColor().isBlue()) colors.add("U");
                if (card.getColor().isBlack()) colors.add("B");
                if (card.getColor().isRed()) colors.add("R");
                if (card.getColor().isGreen()) colors.add("G");
            }
            item.add("colors", colors);
            JsonArray targets = new JsonArray();
            if (card.getTargets() != null) card.getTargets().forEach(target -> targets.add(target.toString()));
            item.add("targets", targets);
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
    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        heartbeat.shutdownNow();
        queue.execute(() -> {
            try {
                if (gameId != null && session.isConnected()) session.quitMatch(gameId);
                else if (tableId != null && session.isConnected()) {
                    session.leaveTable(session.getMainRoomId(), tableId);
                    if (ownsTable) session.removeTable(session.getMainRoomId(), tableId);
                }
            } finally { session.connectStop(false, false); }
        });
        queue.shutdown();
    }
}
