package magicboard.rules;

import com.google.gson.*;
import java.util.*;
import java.util.regex.*;

/** Read-only card context for questions such as Explore, sourced only from this seat's visible view. */
final class PromptContextCards {
    private static final Pattern OBJECT = Pattern.compile("object_id\\s*=\\s*(['\"])([0-9a-fA-F-]{36})\\1");

    static JsonArray forQuestion(String method, String message, JsonObject snapshot, JsonArray supplied) {
        if (!method.equals("GAME_ASK") || message == null || snapshot == null || !supplied.isEmpty()) return supplied;
        Map<String, JsonObject> visible = new HashMap<>();
        for (String field : List.of("revealed", "lookedAt")) {
            if (!snapshot.has(field) || snapshot.get(field).isJsonNull()) continue;
            for (JsonElement group : snapshot.getAsJsonArray(field)) {
                for (JsonElement item : group.getAsJsonObject().getAsJsonArray("cards")) {
                    JsonObject card = item.getAsJsonObject();
                    visible.put(card.get("id").getAsString().toLowerCase(Locale.ROOT), card);
                }
            }
        }
        JsonArray result = new JsonArray();
        Set<String> seen = new HashSet<>();
        Matcher references = OBJECT.matcher(message);
        while (references.find()) {
            String id = references.group(2).toLowerCase(Locale.ROOT);
            JsonObject card = visible.get(id);
            if (card != null && seen.add(id)) result.add(card.deepCopy());
        }
        return result;
    }
}
