import Testing
import Hummingbird
import HTTPTypes
import NIOCore
@testable import BaguetteCore

@Suite("Server browser security")
struct ServerSecurityTests {

    @Test func `allows direct loopback requests without an Origin header`() {
        let request = Self.request(host: "127.0.0.1:8421")

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421
        ))
    }

    @Test func `allows same-origin browser requests on loopback`() {
        let request = Self.request(
            host: "localhost:8421",
            origin: "http://localhost:8421"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421
        ))
    }

    @Test func `rejects cross-site browser requests to loopback control routes`() {
        let request = Self.request(
            host: "127.0.0.1:8421",
            origin: "https://example.test"
        )

        #expect(!Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421
        ))
    }

    @Test func `rejects DNS rebind shaped hosts on loopback binds`() {
        let request = Self.request(
            host: "attacker.test:8421",
            origin: "http://attacker.test:8421"
        )

        #expect(!Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421
        ))
    }

    @Test func `rejects Fetch Metadata cross-site requests`() {
        let request = Self.request(
            host: "127.0.0.1:8421",
            origin: "http://127.0.0.1:8421",
            fetchSite: "cross-site"
        )

        #expect(!Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421
        ))
    }

    @Test func `allows proxied requests whose Host names an allowed host`() {
        let request = Self.request(host: "sim.example.test")

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test"]
        ))
    }

    @Test func `allows browser origins on an allowed host regardless of port`() {
        let request = Self.request(
            host: "sim.example.test",
            origin: "https://sim.example.test"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test"]
        ))
    }

    @Test func `matches wildcard allowed hosts against subdomains`() {
        let request = Self.request(
            host: "device-1.sim.example.test",
            origin: "https://device-1.sim.example.test"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["*.example.test"]
        ))
    }

    @Test func `still rejects hosts outside the allowed list`() {
        let request = Self.request(
            host: "attacker.test:8421",
            origin: "http://attacker.test:8421"
        )

        #expect(!Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test"]
        ))
    }

    @Test func `rejects allowed-host requests with a foreign Origin`() {
        let request = Self.request(
            host: "sim.example.test",
            origin: "https://attacker.test"
        )

        #expect(!Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test"]
        ))
    }

    @Test func `trusts allowed-host origins on another host`() {
        let request = Self.request(
            host: "sim.example.test",
            origin: "https://app.example.test"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test", "app.example.test"]
        ))
    }

    @Test func `trusts allowed-host origins when the proxy rewrites Host to loopback`() {
        let request = Self.request(
            host: "localhost:8421",
            origin: "https://sim.example.test"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test"]
        ))
    }

    @Test func `trusts allowed-host origins even when Fetch Metadata says cross-site`() {
        let request = Self.request(
            host: "sim.example.test",
            origin: "https://app.example.test",
            fetchSite: "cross-site"
        )

        #expect(Server.isTrustedBrowserRequest(
            request, bindHost: "127.0.0.1", bindPort: 8421,
            allowedHosts: ["sim.example.test", "app.example.test"]
        ))
    }

    @Test func `reflects allowed origins for CORS`() {
        #expect(Server.corsAllowedOrigin(
            "https://app.example.test",
            allowedHosts: ["app.example.test"]
        ) == "https://app.example.test")

        #expect(Server.corsAllowedOrigin(
            "https://attacker.test",
            allowedHosts: ["app.example.test"]
        ) == nil)

        #expect(Server.corsAllowedOrigin(nil, allowedHosts: ["app.example.test"]) == nil)
    }

    @Test func `answers CORS preflights for allowed origins`() {
        let head = HTTPRequest(
            method: .options,
            scheme: nil,
            authority: "sim.example.test",
            path: "/simulators/UDID/boot",
            headerFields: [
                .origin: "https://app.example.test",
                .accessControlRequestMethod: "POST",
                .accessControlRequestHeaders: "content-type",
            ]
        )
        let request = Request(head: head, body: .init(buffer: ByteBuffer()))

        let response = Server.corsPreflightResponse(request, allowedHosts: ["app.example.test"])
        #expect(response?.status == .noContent)
        #expect(response?.headers[.accessControlAllowOrigin] == "https://app.example.test")
        #expect(response?.headers[.accessControlAllowMethods] == "POST")
        #expect(response?.headers[.accessControlAllowHeaders] == "content-type")

        #expect(Server.corsPreflightResponse(request, allowedHosts: ["other.test"]) == nil)
    }

    @Test func `static asset responses deny foreign framing`() {
        let csp = HTTPField.Name("Content-Security-Policy")!

        for asset in ["sim.html", "farm/farm.html"] {
            let response = Server.staticAsset(asset)

            #expect(response.headers[csp] == "frame-ancestors 'none'")
        }
    }

    private static func request(
        host: String,
        origin: String? = nil,
        fetchSite: String? = nil
    ) -> Request {
        var headers: HTTPFields = [:]
        if let origin { headers[.origin] = origin }
        if let fetchSite { headers[HTTPField.Name("Sec-Fetch-Site")!] = fetchSite }

        let head = HTTPRequest(
            method: .post,
            scheme: nil,
            authority: host,
            path: "/simulators/UDID/boot",
            headerFields: headers
        )
        return Request(head: head, body: .init(buffer: ByteBuffer()))
    }
}
