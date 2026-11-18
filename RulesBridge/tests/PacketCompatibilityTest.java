package magicboard.rules;

import com.google.gson.*;
import java.nio.file.*;
import java.util.*;

/** Audits bundled names against the pinned release; this does not prove card rules behavior. */
public final class PacketCompatibilityTest {
    public static void main(String[] args) throws Exception {
        JsonArray packets = JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray();
        Map<String, Boolean> names = new HashMap<>();
        Map<String, int[]> counts = new TreeMap<>();
        JsonArray failures = new JsonArray();
        for (JsonElement item : packets) {
            JsonObject packet = item.getAsJsonObject();
            JsonArray missing = new JsonArray();
            for (JsonElement entry : packet.getAsJsonArray("cards")) {
                String name = entry.getAsString();
                boolean resolves = names.computeIfAbsent(name, card -> {
                    try { CardPrintings.resolve(card, "", "", 1); return true; }
                    catch (IllegalArgumentException unsupported) { return false; }
                });
                if (!resolves) missing.add(name);
            }
            String family = packet.get("source").getAsString() + " / " + packet.get("set").getAsString();
            int[] count = counts.computeIfAbsent(family, ignored -> new int[2]);
            count[0]++;
            if (missing.isEmpty()) count[1]++;
            else {
                JsonObject failure = packet.deepCopy(); failure.remove("cards"); failure.add("missing", missing); failures.add(failure);
            }
        }
        JsonObject report = new JsonObject(), families = new JsonObject();
        for (var entry : counts.entrySet()) {
            int[] count = entry.getValue();
            JsonObject family = new JsonObject(); family.addProperty("packets", count[0]); family.addProperty("allNamesResolve", count[1]);
            families.add(entry.getKey(), family);
            System.out.println(entry.getKey() + ": " + count[1] + "/" + count[0] + " packets resolve every possible card name");
        }
        report.add("families", families); report.add("failures", failures);
        report.addProperty("uniqueCardNames", names.size());
        report.addProperty("unresolvedNames", names.values().stream().filter(value -> !value).count());
        Files.writeString(Path.of(args[1]), new GsonBuilder().setPrettyPrinting().create().toJson(report));
        System.out.println("Audited " + packets.size() + " packets / " + names.size() + " names; unresolved packets=" + failures.size());
    }
}
