package magicboard.rules;

import mage.constants.MultiAmountType;
import mage.util.MultiAmountMessage;
import java.util.List;

/** Check the bridge's encoding against XMage's own decoder and constraint validator. */
public final class PromptAnswersTest {
    public static void main(String[] args) {
        List<MultiAmountMessage> constraints = List.of(new MultiAmountMessage("First", 0, 12), new MultiAmountMessage("Second", 1, 6));
        List<Integer> values = List.of(10, 2);
        String encoded = PromptAnswers.amounts(values, constraints, 12, 12);
        if (!MultiAmountType.parseAnswer(encoded, constraints, 12, 12, false).equals(values))
            throw new AssertionError("XMage cannot decode bridge amount distribution");
        for (List<Integer> invalid : List.of(List.of(10), List.of(12, 0), List.of(13, 1), List.of(0, 1))) {
            try {
                PromptAnswers.amounts(invalid, constraints, 12, 12);
                throw new AssertionError("Invalid distribution accepted: " + invalid);
            } catch (IllegalArgumentException expected) { }
        }
        System.out.println("PASS distribution encoding, individual limits, total limits and entry counts against XMage");
    }
}
