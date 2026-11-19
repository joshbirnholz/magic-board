package magicboard.rules;

import mage.abilities.icon.CardIcon;
import mage.abilities.icon.CardIconType;
import mage.view.CardView;
import java.util.regex.Pattern;

/** XMage's variable-cost icon carries the chosen value, including zero and copied spells. */
final class CardXValue {
    private static final Pattern VALUE = Pattern.compile("^x=(\\d+)$", Pattern.CASE_INSENSITIVE);
    static Integer from(CardView card) {
        if (card.isFaceDown() || card.getCardIcons() == null) return null;
        Integer result = null;
        for (CardIcon icon : card.getCardIcons()) {
            if (icon == null || icon.getIconType() != CardIconType.OTHER_COST_X) continue;
            var matcher = VALUE.matcher(icon.getText() == null ? "" : icon.getText());
            if (!matcher.matches()) return null;
            try {
                int value = Integer.parseInt(matcher.group(1));
                if (result != null && result != value) return null;
                result = value;
            } catch (NumberFormatException invalid) { return null; }
        }
        return result;
    }
}
