import com.google.gson.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Both seats are real engine clients; only the caster may inspect the target's hidden hand. */
public final class PrivateLookSmoke {
    public static void main(String[] args) throws Exception {
        boolean publicReveal = System.getenv("RULES_LOOK_PUBLIC") != null;
        boolean requireDiscard = System.getenv("RULES_LOOK_DISCARD") != null;
        try (BridgeTwoPlayerSmoke.Client caster = new BridgeTwoPlayerSmoke.Client();
             BridgeTwoPlayerSmoke.Client target = new BridgeTwoPlayerSmoke.Client()) {
            String main = publicReveal ? "[{\"name\":\"Swamp\",\"count\":36},{\"name\":\"Duress\",\"count\":24}]"
                    : "[{\"name\":\"Gitaxian Probe\",\"count\":60}]";
            caster.send("{\"type\":\"createHumanGame\",\"requestId\":\"create\",\"deck\":{\"name\":\"Visibility check\",\"main\":" + main + ",\"sideboard\":[]}}");
            JsonObject table = caster.await("tableJoined"); caster.await("ack");
            String targetDeck = publicReveal ? ",\"deck\":{\"name\":\"Reveal target\",\"main\":[{\"name\":\"Revitalize\",\"count\":60}],\"sideboard\":[]}" : "";
            target.send("{\"type\":\"joinTable\",\"requestId\":\"join\",\"tableId\":" + table.get("tableId") + targetDeck + "}");
            target.await("tableJoined"); target.await("ack");
            caster.command("startMatch"); caster.await("ack");
            boolean sawLook = false, sawPrivateBaseline = false;
            boolean discarded = false;
            Set<String> shown = new HashSet<>();
            Set<String> shownToTarget = new HashSet<>(), originalHand = new HashSet<>();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
            while (System.nanoTime() < deadline) {
                for (BridgeTwoPlayerSmoke.Client client : List.of(caster, target)) {
                    JsonObject event = client.events.poll(20, TimeUnit.MILLISECONDS);
                    if (event == null) continue;
                    switch (event.get("type").getAsString()) {
                        case "snapshot" -> {
                            client.state = event;
                            if (client == target && !sawLook) {
                                originalHand.clear();
                                for (JsonElement card : event.getAsJsonArray("hand")) originalHand.add(card.getAsJsonObject().get("id").getAsString());
                            }
                            if (client == target && sawLook) for (JsonElement player : event.getAsJsonArray("players")) {
                                if (!player.getAsJsonObject().get("id").equals(event.get("playerId"))) continue;
                                for (JsonElement card : player.getAsJsonObject().getAsJsonArray("graveyard"))
                                    if (originalHand.contains(card.getAsJsonObject().get("id").getAsString())) discarded = true;
                            }
                            for (JsonElement player : event.getAsJsonArray("players"))
                                if (player.getAsJsonObject().has("hand")) throw new AssertionError("Unfiltered hand in player summaries");
                            JsonArray looks = event.getAsJsonArray(publicReveal ? "revealed" : "lookedAt");
                            if (looks == null) throw new AssertionError("Bridge has no lookedAt protocol support");
                            if (client == target && !looks.isEmpty() && !publicReveal) throw new AssertionError("Caster's private look leaked to target: " + looks);
                            if (client == target && publicReveal)
                                for (JsonElement group : looks) for (JsonElement card : group.getAsJsonObject().getAsJsonArray("cards"))
                                    shownToTarget.add(card.getAsJsonObject().get("id").getAsString());
                            if (client == caster && !looks.isEmpty()) {
                                if (!sawLook) discarded = false;
                                for (JsonElement group : looks) for (JsonElement card : group.getAsJsonObject().getAsJsonArray("cards"))
                                    shown.add(card.getAsJsonObject().get("id").getAsString());
                                sawLook = !shown.isEmpty();
                            }
                            if (client == caster && !event.getAsJsonArray("hand").isEmpty() && !sawLook) sawPrivateBaseline = true;
                        }
                        case "prompt" -> {
                            String method = event.get("method").getAsString();
                            String message = event.has("message") ? event.get("message").getAsString().toLowerCase(Locale.ROOT) : "";
                            if (method.equals("GAME_TARGET") && message.contains("starting player"))
                                client.answer(event, "uuid", caster.state.get("playerId"));
                            else if (method.equals("GAME_TARGET") && (message.contains("target player") || message.contains("select a player")))
                                client.answer(event, "uuid", target.state.get("playerId"));
                            else if (method.equals("GAME_TARGET") && event.has("cards") && !event.getAsJsonArray("cards").isEmpty()) {
                                if (!event.has("selectionIds") || event.getAsJsonArray("selectionIds").isEmpty())
                                    throw new AssertionError("Engine's legal card IDs were not exposed");
                                client.answer(event, "uuid", event.getAsJsonArray("selectionIds").get(0));
                            }
                            else {
                                System.out.println("Decision: " + method + " / " + message
                                        + " cards=" + (event.has("cards") ? event.getAsJsonArray("cards").size() : 0)
                                        + " targets=" + (event.has("targets") ? event.getAsJsonArray("targets").size() : 0));
                                CombatSmoke.answer(client, event, false);
                            }
                        }
                        case "error", "gameOver" -> throw new AssertionError(event);
                    }
                }
                if (sawLook && !originalHand.isEmpty() && (!publicReveal || !shownToTarget.isEmpty())
                        && (!requireDiscard || discarded)) {
                    if (!shown.equals(originalHand)) throw new AssertionError("Visible hand differs from actual target hand");
                    if (publicReveal && !shownToTarget.equals(originalHand)) throw new AssertionError("Public reveal differs between seats");
                    if (!sawPrivateBaseline) throw new AssertionError("Did not verify hidden baseline before look");
                    // Drain through a receipt after the reveal so a delayed forbidden update
                    // cannot arrive just after the test reports success.
                    target.send("{\"type\":\"resync\",\"requestId\":\"privacy-replay\"}");
                    JsonObject receipt;
                    do { receipt = target.await("ack"); }
                    while (!receipt.get("requestId").getAsString().equals("privacy-replay"));
                    if (!publicReveal && !target.state.getAsJsonArray("lookedAt").isEmpty())
                        throw new AssertionError("Private look leaked on the other seat's replay");
                    System.out.println(publicReveal ? "PASS public hand reveal reaches both seats with the actual target hand"
                            : "PASS private hand look contains the real target hand, only on the permitted seat");
                    if (requireDiscard) System.out.println("PASS a revealed opponent card was selected and discarded");
                    return;
                }
            }
            throw new AssertionError("No private hand view was delivered");
        }
    }
}
