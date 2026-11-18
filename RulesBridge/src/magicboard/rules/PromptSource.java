package magicboard.rules;

import com.google.gson.*;
import java.util.*;
import java.util.regex.*;

/** Source identity only from an explicit engine reference and this seat's already-visible cards. */
final class PromptSource {
    private static final Pattern OBJECT = Pattern.compile("object_id\\s*=\\s*(['\"])([0-9a-fA-F-]{36})\\1");

    static JsonObject find(JsonObject prompt, JsonObject snapshot) {
        if (snapshot == null) return null;
        String reference = text(prompt, "subMessage");
        if (reference.isEmpty() && Set.of("GAME_PLAY_MANA", "GAME_PLAY_XMANA", "GAME_CHOOSE_ABILITY").contains(text(prompt, "method")))
            reference = text(prompt, "message");
        Matcher match = OBJECT.matcher(reference);
        if (!match.find()) return null;
        String id = match.group(2).toLowerCase(Locale.ROOT);
        List<JsonObject> visible = new ArrayList<>();
        cards(snapshot, "hand", visible);
        cards(snapshot, "stack", visible);
        if (snapshot.has("players")) for (JsonElement item : snapshot.getAsJsonArray("players")) {
            JsonObject player = item.getAsJsonObject();
            for (String zone : List.of("battlefield", "graveyard", "exile")) cards(player, zone, visible);
        }
        for (String field : List.of("revealed", "lookedAt")) {
            if (snapshot.has(field) && !snapshot.get(field).isJsonNull())
                for (JsonElement group : snapshot.getAsJsonArray(field)) cards(group.getAsJsonObject(), "cards", visible);
        }
        for (JsonObject card : visible) {
            if (!text(card, "id").equalsIgnoreCase(id) || text(card, "name").isBlank()) continue;
            JsonObject source = new JsonObject();
            source.addProperty("id", id);
            source.addProperty("name", text(card, "name"));
            return source;
        }
        return null;
    }

    private static void cards(JsonObject object, String field, List<JsonObject> result) {
        if (object.has(field) && !object.get(field).isJsonNull())
            for (JsonElement card : object.getAsJsonArray(field)) result.add(card.getAsJsonObject());
    }

    private static String text(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull() ? object.get(key).getAsString() : "";
    }
}
