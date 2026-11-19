package magicboard.rules;

import com.google.gson.*;
import mage.constants.Zone;
import mage.view.GameClientMessage;
import java.util.*;

public final class PromptTargetCardsTest {
    private static final UUID MINE = UUID.randomUUID(), THEIRS = UUID.randomUUID(), HAND = UUID.randomUUID(), BOARD = UUID.randomUUID(), HIDDEN = UUID.randomUUID();
    public static void main(String[] args) {
        JsonObject snapshot = new JsonObject();
        snapshot.add("hand", cards(HAND, "Brainstorm hand card"));
        JsonArray players = new JsonArray(); snapshot.add("players", players);
        JsonObject me = new JsonObject(); me.add("graveyard", cards(MINE, "Forest")); me.add("battlefield", cards(BOARD, "Creature")); players.add(me);
        JsonObject opponent = new JsonObject(); opponent.add("graveyard", cards(THEIRS, "Opponent creature"));
        opponent.add("hand", cards(HIDDEN, "Hidden card must never be inspected")); players.add(opponent);
        JsonArray empty = new JsonArray();
        JsonArray own = resolve(snapshot, Zone.GRAVEYARD, Set.of(MINE), Map.of());
        check(own.size() == 1 && own.get(0).getAsJsonObject().get("name").getAsString().equals("Forest"), "Pothole Mole's legal land must be browsable");
        check(resolve(snapshot, Zone.GRAVEYARD, Set.of(MINE, THEIRS), Map.of()).size() == 2, "Both graveyards must be available");
        check(resolve(snapshot, Zone.HAND, Set.of(HAND), Map.of()).size() == 1, "Own-hand choices must carry card faces");
        check(resolve(snapshot, Zone.HAND, Set.of(MINE), Map.of()).isEmpty(), "Honor the explicit target zone");
        check(resolve(snapshot, Zone.ALL, Set.of(HIDDEN), Map.of()).isEmpty(), "Never inspect another player's hand");
        check(resolve(snapshot, Zone.ALL, Set.of(BOARD), Map.of()).isEmpty(), "Battlefield targeting must stay on the board");
        check(resolve(snapshot, Zone.ALL, Set.of(MINE, BOARD), Map.of()).isEmpty(), "Don't expose an incomplete mixed-zone picker");
        check(resolve(snapshot, Zone.GRAVEYARD, Set.of(MINE, UUID.randomUUID()), Map.of()).isEmpty(), "Unknown identities must not be guessed");
        check(resolve(snapshot, Zone.GRAVEYARD, Set.of(MINE), Map.of("chosenTargets", new HashSet<>(Set.of(THEIRS)))).size() == 2, "Keep already-selected cards visible");
        own.get(0).getAsJsonObject().addProperty("name", "Changed");
        check(!snapshot.toString().contains("Changed"), "Browser cards must not mutate the authoritative snapshot");
        GameClientMessage message = message(Zone.GRAVEYARD, Set.of(MINE), Map.of());
        JsonArray explicit = cards(HAND, "Explicit engine list");
        check(PromptTargetCards.resolve("GAME_TARGET", message, snapshot, explicit) == explicit, "Explicit lists take precedence");
        check(PromptTargetCards.resolve("GAME_ASK", message, snapshot, empty) == empty, "Question cards are read-only context");
        check(PromptTargetCards.resolve("GAME_TARGET", message, null, empty) == empty, "No snapshot stays compatible");
        System.out.println("PASS graveyard/hand target faces, both seats, zone boundaries, privacy, selected cards and explicit-list precedence");
    }
    private static JsonArray resolve(JsonObject snapshot, Zone zone, Set<UUID> ids, Map<String, java.io.Serializable> extra) {
        return PromptTargetCards.resolve("GAME_TARGET", message(zone, ids, extra), snapshot, new JsonArray());
    }
    private static GameClientMessage message(Zone zone, Set<UUID> ids, Map<String, java.io.Serializable> extra) {
        Map<String, java.io.Serializable> options = new HashMap<>(extra); options.put("targetZone", zone);
        return new GameClientMessage(null, options, "Choose", null, ids, true);
    }
    private static JsonArray cards(UUID id, String name) {
        JsonObject card = new JsonObject(); card.addProperty("id", id.toString()); card.addProperty("name", name);
        card.addProperty("faceDown", false); JsonArray cards = new JsonArray(); cards.add(card); return cards;
    }
    private static void check(boolean valid, String message) { if (!valid) throw new AssertionError(message); }
}
