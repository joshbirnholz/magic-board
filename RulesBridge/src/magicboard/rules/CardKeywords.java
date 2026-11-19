package magicboard.rules;

import mage.abilities.icon.CardIcon;
import mage.view.CardView;
import java.util.*;

/** Current engine abilities, including continuous effects; never inferred from printed text. */
final class CardKeywords {
    private static final Map<String, String> NAMES = Map.ofEntries(
            Map.entry("flying", "Flying"), Map.entry("defender", "Defender"),
            Map.entry("deathtouch", "Deathtouch"), Map.entry("lifelink", "Lifelink"),
            Map.entry("double strike", "Double strike"), Map.entry("first strike", "First strike"),
            Map.entry("trample", "Trample"), Map.entry("hexproof", "Hexproof"),
            Map.entry("shroud", "Shroud"), Map.entry("infect", "Infect"),
            Map.entry("indestructible", "Indestructible"), Map.entry("vigilance", "Vigilance"),
            Map.entry("reach", "Reach"));

    static List<String> from(CardView card) {
        if (card.isFaceDown() || card.getCardIcons() == null) return List.of();
        Set<String> result = new LinkedHashSet<>();
        for (CardIcon icon : card.getCardIcons()) {
            if (icon == null || icon.getIconType() == null || !icon.getIconType().name().startsWith("ABILITY_")) continue;
            // XMage shares its hexproof icon with shroud: use the exact engine hint to distinguish them.
            String keyword = NAMES.get(icon.getHint() == null ? "" : icon.getHint().trim().toLowerCase(Locale.ROOT));
            if (keyword != null) result.add(keyword);
        }
        return List.copyOf(result);
    }
}
