import CodexAppServerClient
import Foundation

@main
struct CodexAppServerExample {
    static func main() async throws {
        let client = try await CodexClient.connect(
            .localManaged(),
            options: CodexClientOptions(
                clientInfo: ClientInfo(
                    name: "codex_app_server_example",
                    title: "Codex App Server Example",
                    version: "0.1.0"
                )
            )
        )

        let thread = try await client.call(
            RPC.ThreadStart.self,
            params: ThreadStartParams(ephemeral: true)
        )
        print("Started thread: \(thread.thread.id)")

        // Auto-deny any approval request the model issues so the example can run unattended.
        Task {
            for await request in await client.serverRequests(of: ServerRequests.ExecCommandApproval.self) {
                try? await client.respond(to: request, result: .init(intent: .deny))
            }
        }

        let turn = try await client.streamTurn(
            input: [.text("Say hello in one short sentence.")],
            threadId: thread.thread.id
        )

        for await delta in turn.deltas {
            print(delta.delta, terminator: "")
        }
        print()

        await client.disconnect()
    }
}
