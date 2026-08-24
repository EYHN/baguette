public extension BaguetteCoreHarness {
    func runServer(host: String = "127.0.0.1", port: Int = 8421) async throws {
        let server = Server(
            simulators: simulators,
            chromes: Self.defaultChromes(),
            host: host,
            port: port
        )
        try await server.run()
    }
}
