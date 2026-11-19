package magicboard.rules;

import mage.abilities.icon.*;
import mage.view.CardView;
import java.util.*;

public final class CardKeywordsTest {
    private static final class View extends CardView {
        View(boolean hidden, CardIcon... icons) {
            super(new mage.cards.b.Blaze(UUID.randomUUID(), new mage.cards.CardSetInfo("Blaze", "M10", "127", mage.constants.Rarity.UNCOMMON)));
            faceDown = hidden; cardIcons = Arrays.asList(icons);
        }
    }
    public static void main(String[] args) {
        View current = new View(false, CardIconImpl.ABILITY_FIRST_STRIKE, CardIconImpl.ABILITY_DEATHTOUCH,
                CardIconImpl.ABILITY_FIRST_STRIKE, CardIconImpl.variableCost(2));
        check(CardKeywords.from(current).equals(List.of("First strike", "Deathtouch")), "Current gained keywords not preserved/deduplicated");
        check(CardKeywords.from(new CardView(current)).equals(CardKeywords.from(current)), "Copied views lost abilities");
        check(CardKeywords.from(new View(false)).isEmpty(), "Expired keyword survived the next view");
        check(CardKeywords.from(new View(true, CardIconImpl.ABILITY_DEATHTOUCH)).isEmpty(), "Hidden abilities leaked");
        check(CardKeywords.from(new View(false, CardIconImpl.ABILITY_SHROUD)).equals(List.of("Shroud")), "Shroud confused with hexproof");
        System.out.println("PASS current keywords, copied views, expiry, privacy and shroud/hexproof");
    }
    private static void check(boolean good, String message) { if (!good) throw new AssertionError(message); }
}
