package magicboard.rules;

import com.google.gson.*;

public final class PromptSourceTest {
    public static void main(String[] args) {
        String id = "b95222bf-68a0-4769-8c28-4807c05cd345";
        JsonObject snapshot = JsonParser.parseString("{\"players\":[{\"battlefield\":[{\"id\":\"" + id + "\",\"name\":\"Ahriman\"}]}]}").getAsJsonObject();
        JsonObject prompt = JsonParser.parseString("{\"method\":\"GAME_TARGET\",\"message\":\"Select another creature or artifact (to sacrifice)\"}").getAsJsonObject();
        String reference = "<font object_id='" + id.toUpperCase() + "'>Untrusted display label</font>";
        prompt.addProperty("subMessage", reference);
        JsonObject source = PromptSource.find(prompt, snapshot);
        check(source != null && source.get("id").getAsString().equals(id), "Explicit source reference missing");
        check(source.get("name").getAsString().equals("Ahriman"), "Source must use the seat-visible identity");
        check(source.size() == 2, "Source must contain only id/name");
        check(PromptSource.find(prompt, new JsonObject()) == null, "Unknown identity must not be resolved elsewhere");
        check(PromptSource.find(prompt, null) == null, "No snapshot must remain compatible");
        JsonObject opponentHand = snapshot.deepCopy();
        JsonObject player = opponentHand.getAsJsonArray("players").get(0).getAsJsonObject();
        player.add("hand", player.remove("battlefield"));
        check(PromptSource.find(prompt, opponentHand) == null, "Never read another player's private hand graph");
        JsonObject myHand = new JsonObject(); myHand.add("hand", snapshot.getAsJsonArray("players").get(0).getAsJsonObject().get("battlefield").deepCopy());
        check(PromptSource.find(prompt, myHand) != null, "Own seat's visible hand is allowed");
        source.addProperty("name", "Mutated");
        check(!snapshot.toString().contains("Mutated"), "Source must not mutate snapshot data");
        prompt.remove("subMessage");
        prompt.addProperty("message", "Select " + reference);
        check(PromptSource.find(prompt, snapshot) == null, "A mentioned target is not the asking source");
        prompt.addProperty("method", "GAME_PLAY_MANA");
        check(PromptSource.find(prompt, snapshot) != null, "Mana message's explicit source must be exposed");
        JsonObject hidden = snapshot.deepCopy();
        hidden.getAsJsonArray("players").get(0).getAsJsonObject().getAsJsonArray("battlefield").get(0).getAsJsonObject().addProperty("name", "Morph");
        check(PromptSource.find(prompt, hidden).get("name").getAsString().equals("Morph"), "Face-down source must keep the public identity");
        prompt.addProperty("message", "Pay for Ahriman");
        check(PromptSource.find(prompt, snapshot) == null, "Names alone must not guess a source");
        System.out.println("PASS explicit source identity, seat visibility, masked names, no target/name guessing and copy isolation");
    }
    private static void check(boolean valid, String message) { if (!valid) throw new AssertionError(message); }
}
