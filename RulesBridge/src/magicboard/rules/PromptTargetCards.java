package magicboard.rules;

import com.google.gson.*;
import mage.constants.Zone;
import mage.view.GameClientMessage;
import java.util.*;

/** Target UUIDs are sometimes the only card list XMage sends for public zones or our own hand. */
final class PromptTargetCards {
    static JsonArray resolve(String method, GameClientMessage message, JsonObject snapshot, JsonArray supplied) {
        if (!method.equals("GAME_TARGET") || !supplied.isEmpty() || snapshot == null
                || message.getTargets() == null || message.getTargets().isEmpty()) return supplied;
        Object zone = message.getOptions() == null ? null : message.getOptions().get("targetZone");
        if (zone != null && zone != Zone.HAND && zone != Zone.GRAVEYARD && zone != Zone.EXILED && zone != Zone.ALL) return supplied;
        Map<String, JsonObject> visible = new LinkedHashMap<>();
        if (zone == null || zone == Zone.ALL || zone == Zone.HAND) add(snapshot, "hand", visible);
        if (snapshot.has("players")) for (JsonElement item : snapshot.getAsJsonArray("players")) {
            JsonObject player = item.getAsJsonObject();
            if (zone == null || zone == Zone.ALL || zone == Zone.GRAVEYARD) add(player, "graveyard", visible);
            if (zone == null || zone == Zone.ALL || zone == Zone.EXILED) add(player, "exile", visible);
        }
        // Don't turn battlefield/player choices or partially unknown choices into an incomplete browser.
        for (UUID id : message.getTargets()) if (!visible.containsKey(id.toString())) return supplied;
        Set<UUID> ids = new LinkedHashSet<>(message.getTargets());
        if (message.getOptions() != null && message.getOptions().get("chosenTargets") instanceof Collection<?> selected)
            for (Object id : selected) if (id instanceof UUID uuid && visible.containsKey(uuid.toString())) ids.add(uuid);
        JsonArray result = new JsonArray();
        for (UUID id : ids) result.add(visible.get(id.toString()).deepCopy());
        return result;
    }

    private static void add(JsonObject object, String field, Map<String, JsonObject> cards) {
        if (!object.has(field) || object.get(field).isJsonNull()) return;
        for (JsonElement item : object.getAsJsonArray(field)) {
            JsonObject card = item.getAsJsonObject();
            if (card.has("id")) cards.put(card.get("id").getAsString().toLowerCase(Locale.ROOT), card);
        }
    }
}
