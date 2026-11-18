package magicboard.rules;

/** Lightweight looked-at views still need names for accessibility and fallback image matching. */
public final class CardPrintingsTest {
    public static void main(String[] args) {
        if (!"Silence".equals(CardPrintings.nameForPrinting("M10", "31")))
            throw new AssertionError("Printing index returned the wrong M10 card");
        if (!"Silvercoat Lion".equals(CardPrintings.nameForPrinting("m10", "32")))
            throw new AssertionError("Printing names must be case-insensitive by set code");
        if (CardPrintings.nameForPrinting(null, "32") != null || CardPrintings.nameForPrinting("missing", "9999") != null)
            throw new AssertionError("Unknown printing must stay optional");
        System.out.println("PASS looked-at printing names, case handling and unknown-print fallback");
    }
}
