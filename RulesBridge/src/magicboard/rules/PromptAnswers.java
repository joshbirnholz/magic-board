package magicboard.rules;

import mage.constants.MultiAmountType;
import mage.constants.PlayerAction;
import mage.util.MultiAmountMessage;
import java.util.List;
import java.util.stream.Collectors;

final class PromptAnswers {
    static PlayerAction priorityAction(String action) {
        return switch (action) {
            case "hold" -> PlayerAction.HOLD_PRIORITY;
            case "release" -> PlayerAction.UNHOLD_PRIORITY;
            case "cancelAutoPass" -> PlayerAction.PASS_PRIORITY_CANCEL_ALL_ACTIONS;
            case "resolveStack" -> PlayerAction.PASS_PRIORITY_UNTIL_STACK_RESOLVED;
            case "nextMain" -> PlayerAction.PASS_PRIORITY_UNTIL_NEXT_MAIN_PHASE;
            case "endStep" -> PlayerAction.PASS_PRIORITY_UNTIL_TURN_END_STEP;
            case "yourTurn" -> PlayerAction.PASS_PRIORITY_UNTIL_MY_NEXT_TURN;
            default -> throw new IllegalArgumentException("Unknown priority control.");
        };
    }
    static String amounts(List<Integer> values, List<MultiAmountMessage> constraints, int minimum, int maximum) {
        if (!MultiAmountType.isGoodValues(values, constraints, minimum, maximum))
            throw new IllegalArgumentException("The distribution does not satisfy the individual or total limits.");
        return values.stream().map(String::valueOf).collect(Collectors.joining(" "));
    }
}
