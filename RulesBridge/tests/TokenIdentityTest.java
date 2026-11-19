package magicboard.rules;

import com.google.gson.JsonObject;
import mage.view.CardView;
import mage.game.permanent.token.DarkstarToken;
import mage.MageInt;
import java.util.List;

public final class TokenIdentityTest {
    private static final class CopyView extends CardView {
        CopyView(boolean hidden) {
            super(new mage.cards.s.SoulWarden(java.util.UUID.randomUUID(),
                new mage.cards.CardSetInfo("Soul Warden", "M10", "34", mage.constants.Rarity.COMMON)));
            isToken = true; faceDown = hidden;
            originalPower = new MageInt(1); originalToughness = new MageInt(1);
            power = "3"; toughness = "3";
        }
    }
    public static void main(String[] args) throws Exception {
        var owner = java.util.UUID.randomUUID();
        var permanent = new mage.game.permanent.PermanentToken(new DarkstarToken(), owner, null);
        CardView named = new mage.view.PermanentView(permanent, null, owner, null);
        JsonObject darkstar = XMageSession.cards(List.of(named)).get(0).getAsJsonObject();
        check(darkstar.get("token").getAsBoolean(), "Named token identity missing");
        check(darkstar.get("basePower").getAsString().equals("2"), "Darkstar created power missing");
        check(darkstar.get("baseToughness").getAsString().equals("2"), "Darkstar created toughness missing");
        JsonObject copy = XMageSession.cards(List.of(new CopyView(false))).get(0).getAsJsonObject();
        check(copy.get("token").getAsBoolean() && copy.get("power").getAsString().equals("3")
            && copy.get("basePower").getAsString().equals("1"), "Copy identity/base and effective stats conflated");
        JsonObject hidden = XMageSession.cards(List.of(new CopyView(true))).get(0).getAsJsonObject();
        check(!hidden.has("token") && !hidden.has("basePower") && !hidden.has("baseToughness"), "Hidden token identity leaked");
        System.out.println("PASS actual Darkstar token identity/base stats, modified token copy and hidden identity");
    }
    private static void check(boolean good, String message) { if (!good) throw new AssertionError(message); }
}
