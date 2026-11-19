package magicboard.rules;

import mage.abilities.icon.*;
import mage.view.CardView;
import java.util.*;

public final class CardXValueTest {
    private static final class View extends CardView {
        View(boolean hidden, CardIcon... icons) { super(new mage.cards.b.Blaze(UUID.randomUUID(), new mage.cards.CardSetInfo("Blaze", "M10", "127", mage.constants.Rarity.UNCOMMON))); faceDown = hidden; cardIcons = Arrays.asList(icons); }
    }
    public static void main(String[] args) {
        for (int x : new int[]{0, 1, 6, Integer.MAX_VALUE}) {
            View original = new View(false, CardIconImpl.variableCost(x));
            check(Objects.equals(CardXValue.from(original), x), "Actual engine icon value lost: " + x);
            check(Objects.equals(CardXValue.from(new CardView(original)), x), "Copied view lost chosen X");
        }
        check(CardXValue.from(new View(true, CardIconImpl.variableCost(3))) == null, "Face-down value leaked");
        check(CardXValue.from(new View(false, CardIconImpl.ABILITY_FLYING)) == null, "Printed/ordinary card gained X");
        check(CardXValue.from(new View(false, CardIconImpl.variableCost(1), CardIconImpl.variableCost(2))) == null, "Conflicting values guessed");
        for (String invalid : new String[]{"x=-1", "x=9999999999999", "Announced X = 2", "x=2 extra", ""})
            check(CardXValue.from(new View(false, new CardIconImpl(CardIconType.OTHER_COST_X, "", invalid))) == null, "Malformed X accepted");
        System.out.println("PASS engine chosen X including zero, copied views, hidden cards, invalid and conflicting metadata");
    }
    private static void check(boolean good, String message) { if (!good) throw new AssertionError(message); }
}
