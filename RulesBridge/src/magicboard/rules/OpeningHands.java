package magicboard.rules;

import com.google.gson.*;
import java.util.*;
import static magicboard.rules.XMageSession.*;

/** Public opening-hand progress only. Called on the room worker, never stores card identities. */
final class OpeningHands {
    private static final class Opening {
        final String gameId;
        boolean active = true;
        String startingPlayerId, decidingPlayerId;
        final Map<String, Integer> kept = new LinkedHashMap<>();
        Opening(String id) { gameId = id; }
    }
    private final Map<String, Opening> games = new HashMap<>();
    private final Map<RulesRooms.Client, String> seats = new HashMap<>();
    void observe(RulesRooms.Client client, JsonObject event) {
        String id = string(event, "gameId"), type = string(event, "type");
        if (id.isEmpty()) return;
        seats.put(client, id);
        Opening opening = games.computeIfAbsent(id, Opening::new);
        if (type.equals("snapshot")) {
            if (!string(event, "step").isEmpty()) opening.active = false;
        } else if (type.equals("openingProgress")) {
            String kind = string(event, "kind"), player = string(event, "playerId");
            if (kind.equals("startingPlayer")) opening.startingPlayerId = string(event, "startingPlayerId");
            if (kind.equals("deciding")) { opening.decidingPlayerId = player; opening.kept.remove(player); }
            if (kind.equals("kept")) {
                opening.kept.put(player, event.get("count").getAsInt());
                if (player.equals(opening.decidingPlayerId)) opening.decidingPlayerId = null;
            }
        }
        // Public flags/counts are shared only between seats already registered in this engine game.
        for (var seat : seats.entrySet()) if (seat.getValue().equals(id)) publish(seat.getKey(), opening);
    }
    void replay(RulesRooms.Client client) {
        Opening opening = games.get(seats.get(client));
        if (opening != null) publish(client, opening);
    }
    void remove(RulesRooms.Client client) {
        String id = seats.remove(client);
        if (id != null && !seats.containsValue(id)) games.remove(id);
    }
    private void publish(RulesRooms.Client client, Opening opening) {
        client.send(object("type", "openingState", "gameId", opening.gameId, "active", opening.active,
            "startingPlayerId", opening.startingPlayerId, "decidingPlayerId", opening.decidingPlayerId, "kept", opening.kept));
    }
}
