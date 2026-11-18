package magicboard.rules;

import com.google.gson.*;

public final class PromptContextCardsTest {
    public static void main(String[] args) {
        String id = "abcdefab-cdef-4abc-8def-000000000010";
        String hidden = "abcdefab-cdef-4abc-8def-000000000011";
        String question = "Put <font object_id='" + id.toUpperCase() + "'>Merfolk Branchwalker</font> in your graveyard?";
        JsonObject snapshot = JsonParser.parseString("{\"revealed\":[{\"name\":\"Explored card\",\"cards\":[{\"id\":\"" + id + "\",\"name\":\"Merfolk Branchwalker\"}]}],\"lookedAt\":[]}").getAsJsonObject();
        JsonArray result = PromptContextCards.forQuestion("GAME_ASK", question, snapshot, new JsonArray());
        if (result.size() != 1 || !result.get(0).getAsJsonObject().get("id").getAsString().equals(id)) throw new AssertionError("Visible explored card must accompany the question");
        result.get(0).getAsJsonObject().addProperty("name", "Changed");
        if (snapshot.toString().contains("Changed")) throw new AssertionError("Context must not mutate the authoritative snapshot");
        if (PromptContextCards.forQuestion("GAME_ASK", question + question, snapshot, new JsonArray()).size() != 1) throw new AssertionError("Duplicate references must be deduplicated");
        if (!PromptContextCards.forQuestion("GAME_ASK", question.replace(id.toUpperCase(), hidden.toUpperCase()), snapshot, new JsonArray()).isEmpty()) throw new AssertionError("Unknown private identity must not be looked up elsewhere");
        if (!PromptContextCards.forQuestion("GAME_TARGET", question, snapshot, new JsonArray()).isEmpty()) throw new AssertionError("Context must not become selectable target cards");
        if (!PromptContextCards.forQuestion("GAME_ASK", "Put Merfolk Branchwalker in your graveyard?", snapshot, new JsonArray()).isEmpty()) throw new AssertionError("Card names alone must not guess an identity");
        JsonArray supplied = new JsonArray(); supplied.add("explicit engine card list");
        if (PromptContextCards.forQuestion("GAME_ASK", question, snapshot, supplied) != supplied) throw new AssertionError("Explicit engine card lists take precedence");
        JsonObject privateLook = snapshot.deepCopy(); privateLook.add("lookedAt", privateLook.remove("revealed"));
        if (PromptContextCards.forQuestion("GAME_ASK", question.replace("'", "\""), privateLook, new JsonArray()).size() != 1) throw new AssertionError("Private looked-at context is allowed only in the permitted seat snapshot");
        System.out.println("PASS seat-visible question context, explicit references, deduplication, copy isolation and no hidden/name-only lookup");
    }
}
