package magicboard.rules;

import mage.cards.ExpansionSet;
import mage.cards.Sets;
import mage.cards.decks.DeckCardInfo;
import java.util.*;
import java.text.Normalizer;

/** Resolve deck-list names using the matching XMage release's set metadata, not Scryfall IDs. */
final class CardPrintings {
    private record Printing(String name, String set, String number, long release) { }
    private static final class Index {
        static final Map<String, String> BY_PRINTING = new HashMap<>();
        static final Map<String, List<Printing>> BY_NAME = build();
        private static Map<String, List<Printing>> build() {
            Map<String, List<Printing>> result = new HashMap<>();
            for (ExpansionSet set : Sets.getInstance().values()) {
                for (ExpansionSet.SetCardInfo card : set.getSetCardInfo()) {
                    if (card.getCardClass() == null || card.getName() == null) continue;
                    Printing printing = new Printing(card.getName(), set.getCode(), card.getCardNumber(), set.getReleaseDate().getTime());
                    BY_PRINTING.put(printingKey(printing.set, printing.number), printing.name);
                    result.computeIfAbsent(normalize(card.getName()), ignored -> new ArrayList<>()).add(printing);
                }
            }
            Comparator<Printing> preferred = Comparator.comparingLong(Printing::release).reversed()
                    .thenComparing(Printing::set).thenComparing(Printing::number);
            result.values().forEach(printings -> printings.sort(preferred));
            return result;
        }
    }

    static String nameForPrinting(String set, String number) {
        if (set == null || number == null) return null;
        return Index.BY_PRINTING.get(printingKey(set, number));
    }

    private static String printingKey(String set, String number) {
        return set.toLowerCase(Locale.ROOT) + ":" + number.toLowerCase(Locale.ROOT);
    }

    static DeckCardInfo resolve(String name, String set, String number, int count) {
        List<Printing> choices = Index.BY_NAME.get(normalize(name));
        String normalized = normalize(name);
        if (choices == null && normalized.contains(" // "))
            choices = Index.BY_NAME.get(normalized.substring(0, normalized.indexOf(" // ")));
        if (choices == null || choices.isEmpty()) throw new IllegalArgumentException("This XMage release does not implement " + name + ".");
        Printing printing = choices.get(0);
        if (!set.isEmpty()) {
            printing = choices.stream().filter(candidate -> candidate.set.equalsIgnoreCase(set)
                    && (number.isEmpty() || candidate.number.equalsIgnoreCase(number))).findFirst().orElse(printing);
        }
        return new DeckCardInfo(printing.name, printing.number, printing.set, count);
    }

    private static String normalize(String name) {
        // Packet sources use both typographic punctuation and Scryfall split-card separators.
        // Apply the same key to XMage metadata so the selected printing keeps its canonical name.
        return Normalizer.normalize(name, Normalizer.Form.NFD).replaceAll("\\p{M}+", "")
                .replace('’', '\'').replace('‘', '\'')
                .replaceAll("\\s*/{2,}\\s*", " // ").trim().toLowerCase(Locale.ROOT);
    }
}
