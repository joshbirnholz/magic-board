package magicboard.rules;

import com.google.gson.JsonObject;
import mage.choices.ChoiceImpl;
import mage.game.events.PlayerQueryEvent;
import mage.view.GameClientMessage;
import java.util.Map;
import java.util.UUID;

/** Exercise the released engine's real message/choice objects, including required flags. */
public final class PromptMetadataTest {
    public static void main(String[] args) {
        JsonObject ordering = metadata("GAME_TARGET", new GameClientMessage(null,
                Map.of("queryType", PlayerQueryEvent.QueryType.PICK_ABILITY), "Order triggers", null, null, true));
        check("PICK_ABILITY".equals(ordering.get("queryType").getAsString()), "Trigger ordering metadata lost");
        check(!ordering.get("canCancel").getAsBoolean(), "Required target can be cancelled");
        JsonObject optionalTarget = metadata("GAME_TARGET", new GameClientMessage(null, null, "Up to one", null, null, false));
        check(optionalTarget.get("canCancel").getAsBoolean(), "Optional target cannot be cancelled");
        JsonObject special = metadata("GAME_SELECT", new GameClientMessage(null, Map.of("specialButton", "Special choice"), "Priority"));
        check(special.get("specialActionAvailable").getAsBoolean(), "Special action unavailable");
        check("Special choice".equals(special.get("specialActionLabel").getAsString()), "Special label lost");
        ChoiceImpl choice = new ChoiceImpl(true);
        choice.setMessage("Choose a mode");
        choice.setKeyChoices(Map.of(UUID.randomUUID().toString(), "First mode"));
        JsonObject required = metadata("GAME_CHOOSE_CHOICE", new GameClientMessage(null, null, choice));
        check(required.get("required").getAsBoolean(), "Choice required flag taken from unrelated message flag");
        check(!required.get("canCancel").getAsBoolean(), "Required mode can be cancelled");
        JsonObject optional = metadata("GAME_CHOOSE_CHOICE", new GameClientMessage(null, null, new ChoiceImpl(false)));
        check(optional.get("canCancel").getAsBoolean(), "Optional choice cannot be cancelled");
        check(!PromptMetadata.METHODS.contains("GAME_FUTURE_DIALOG"), "Unknown dialogs silently supported");
        System.out.println("PASS trigger ordering, required modes, optional cancellation, special-action metadata and unknown dialogs");
    }
    private static JsonObject metadata(String method, GameClientMessage message) {
        JsonObject result = new JsonObject();
        PromptMetadata.apply(method, message, result);
        return result;
    }
    private static void check(boolean good, String failure) { if (!good) throw new AssertionError(failure); }
}
