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
        for (String[] pair : new String[][] {
                { "Stitcher’s Supplier", "Stitcher's Supplier" },
                { "Bartolomé del Presidio", "Bartolome del Presidio" },
                { "Dead /// Gone", "Dead // Gone" },
                { "Fire /// Ice", "Fire // Ice" }
        }) {
            String actual = CardPrintings.resolve(pair[0], "", "", 1).getCardName();
            String canonical = CardPrintings.resolve(pair[1], "", "", 1).getCardName();
            if (!actual.equals(canonical)) throw new AssertionError("Packet spelling picked another card: " + pair[0]);
        }
        try {
            CardPrintings.resolve("A card that does not exist anywhere", "", "", 1);
            throw new AssertionError("Unknown names must still fail rather than silently substitute");
        } catch (IllegalArgumentException expected) { }
        System.out.println("PASS looked-at printing names, case handling and unknown-print fallback");
    }
}
