/** Leaving while the transport vanishes must not deadlock all other bridge connections. */
public final class LeaveRaceSmoke {
    public static void main(String[] args) throws Exception {
        try (BridgeTwoPlayerSmoke.Client active = new BridgeTwoPlayerSmoke.Client()) {
            for (int i = 0; i < 12; i++) {
                BridgeTwoPlayerSmoke.Client leaving = new BridgeTwoPlayerSmoke.Client();
                leaving.send("{\"type\":\"leave\"}");
                leaving.socket.abort(); // race the server's close with a client transport teardown
                active.command("listTables"); active.await("tables"); active.await("ack");
            }
            System.out.println("PASS twelve simultaneous leave/transport teardown races; existing and new clients remain responsive");
        }
    }
}
