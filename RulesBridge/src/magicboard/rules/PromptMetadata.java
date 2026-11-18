package magicboard.rules;

import com.google.gson.JsonObject;
import mage.view.GameClientMessage;
import java.io.Serializable;
import java.util.Map;
import java.util.Set;

/** Only presentation-safe options, never the engine's arbitrary serialized option graph. */
final class PromptMetadata {
    static final Set<String> METHODS = Set.of("GAME_ASK", "GAME_SELECT", "GAME_TARGET", "GAME_PLAY_MANA",
            "GAME_PLAY_XMANA", "GAME_GET_AMOUNT", "GAME_GET_MULTI_AMOUNT", "GAME_CHOOSE_CHOICE",
            "GAME_CHOOSE_ABILITY", "GAME_CHOOSE_PILE");

    static void apply(String method, GameClientMessage message, JsonObject result) {
        Map<String, Serializable> options = message.getOptions() == null ? Map.of() : message.getOptions();
        if (options.get("queryType") instanceof Enum<?> query) result.addProperty("queryType", query.name());
        if (options.get("secondMessage") instanceof String text) result.addProperty("subMessage", text);
        boolean special = (message.getGameView() != null && message.getGameView().getSpecial())
                || options.get("specialButton") instanceof String;
        result.addProperty("specialActionAvailable", special);
        if (special) result.addProperty("specialActionLabel", options.get("specialButton") instanceof String text ? text : "Special action");
        boolean cancel = switch (method) {
            case "GAME_TARGET" -> !message.isFlag();
            case "GAME_PLAY_MANA", "GAME_PLAY_XMANA", "GAME_GET_AMOUNT" -> true;
            case "GAME_GET_MULTI_AMOUNT" -> Boolean.TRUE.equals(options.get("canCancel"));
            default -> false;
        };
        if (message.getChoice() != null) {
            result.addProperty("required", message.getChoice().isRequired());
            cancel = !message.getChoice().isRequired();
            result.addProperty("subMessage", message.getChoice().getSubMessage());
        }
        result.addProperty("canCancel", cancel);
    }
}
