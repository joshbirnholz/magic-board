package magicboard.rules;

import mage.constants.MultiAmountType;
import mage.util.MultiAmountMessage;
import java.util.List;
import java.util.stream.Collectors;

final class PromptAnswers {
    static String amounts(List<Integer> values, List<MultiAmountMessage> constraints, int minimum, int maximum) {
        if (!MultiAmountType.isGoodValues(values, constraints, minimum, maximum))
            throw new IllegalArgumentException("The distribution does not satisfy the individual or total limits.");
        return values.stream().map(String::valueOf).collect(Collectors.joining(" "));
    }
}
