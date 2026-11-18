import java.util.concurrent.TimeUnit;

/** Repeated killed/relaunched clients must not lock out a player or evict connected seats. */
public final class SessionCapacitySmoke {
    public static void main(String[] args) throws Exception {
        try (BridgeTwoPlayerSmoke.Client active = new BridgeTwoPlayerSmoke.Client()) {
            String oldest = null;
            String newest = null;
            for (int i = 0; i < 6; i++) {
                BridgeTwoPlayerSmoke.Client client = new BridgeTwoPlayerSmoke.Client();
                newest = client.ready.get("resumeToken").getAsString();
                if (oldest == null) oldest = newest;
                client.socket.sendClose(1000, "Simulated app termination").join();
                client.closed.get(5, TimeUnit.SECONDS);
            }
            active.command("listTables"); active.await("tables"); active.await("ack");
            System.out.println("PASS six relaunches accepted; connected player remains connected");
            try (BridgeTwoPlayerSmoke.Client resumed = new BridgeTwoPlayerSmoke.Client(newest)) {
                if (!resumed.ready.get("resumeToken").getAsString().equals(newest)) throw new AssertionError("Newest disconnected session was lost");
            }
            boolean expired = false;
            try (BridgeTwoPlayerSmoke.Client unexpected = new BridgeTwoPlayerSmoke.Client(oldest)) {
                throw new AssertionError("Oldest disconnected session was not reclaimed");
            } catch (AssertionError error) {
                if (!error.getMessage().contains("expired")) throw error;
                expired = true;
            }
            if (!expired) throw new AssertionError("No expired-session response");
            System.out.println("PASS latest session resumes; oldest disconnected session expires");
        }
    }
}
