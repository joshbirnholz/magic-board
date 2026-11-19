package magicboard.rules;

import mage.abilities.Ability;
import mage.cards.*;
import mage.cards.s.SoulWarden;
import mage.constants.*;
import mage.view.*;
import com.google.gson.*;
import java.util.*;

public final class AbilityChoiceViewTest {
    public static void main(String[] args) {
        Card source = new SoulWarden(UUID.randomUUID(), new CardSetInfo("Soul Warden", "M10", "34", Rarity.COMMON));
        Ability trigger = source.getAbilities().stream().filter(a -> a.getAbilityType() == AbilityType.TRIGGERED_NONMANA).findFirst().orElseThrow();
        CardView sourceView = new CardView(source);
        AbilityView actual = new AbilityView(trigger, source.getName(), sourceView);
        if (actual.isAbility()) throw new AssertionError("Expected the stock ordering-view false flag that caused the regression");
        JsonObject card = XMageSession.cards(List.of(actual)).get(0).getAsJsonObject();
        check(card.get("ability").getAsBoolean(), "Ordering card must be marked as an ability");
        check(card.get("name").getAsString().equals("Soul Warden"), "Source name missing");
        check(card.get("sourceId").getAsString().equals(source.getId().toString()), "Source UUID missing");
        check(card.get("set").getAsString().equals("M10"), "Source printing missing");
        check(card.get("rules").getAsString().equals(trigger.getRule()), "Trigger text replaced by source card's full rules");
        check(card.getAsJsonArray("colors").toString().equals("[\"W\"]"), "Ability frame lost source color");
        check(card.get("id").getAsString().equals(trigger.getId().toString()), "Answer UUID must remain the trigger, not its source");
        System.out.println("PASS actual XMage AbilityView false-flag regression: source art/name/color, trigger rules and answer identity");
    }
    private static void check(boolean good, String message) { if (!good) throw new AssertionError(message); }
}
