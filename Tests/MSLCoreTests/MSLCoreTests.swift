import XCTest
@testable import MSLCore

final class MSLCoreTests: XCTestCase {
    func testInstanceNameAndLinuxUserEnforceTheContract() throws {
        XCTAssertEqual(try InstanceName("debian-dev").rawValue, "debian-dev")
        XCTAssertEqual(try LinuxUser("dev_user").rawValue, "dev_user")
        XCTAssertThrowsError(try InstanceName("Debian"))
        XCTAssertThrowsError(try InstanceName(".."))
        XCTAssertThrowsError(try InstanceName("debian-dev\n"))
        XCTAssertThrowsError(try LinuxUser("dev\n"))
        XCTAssertThrowsError(try LinuxUser("root"))
        XCTAssertThrowsError(try LinuxUser("systemd-network"))
        XCTAssertThrowsError(try JSONDecoder().decode(InstanceName.self, from: Data("\"Debian\"".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LinuxUser.self, from: Data("\"root\"".utf8)))
    }

    func testGuestTargetAcceptsOnlyDebian12Arm64() throws {
        XCTAssertNoThrow(try GuestTarget(distribution: "debian", release: "12", architecture: "arm64"))
        XCTAssertThrowsError(try GuestTarget(distribution: "ubuntu", release: "24.04", architecture: "arm64"))
        XCTAssertThrowsError(try GuestTarget(distribution: "debian", release: "11", architecture: "arm64"))
        XCTAssertThrowsError(try GuestTarget(distribution: "debian", release: "12", architecture: "x86_64"))
        XCTAssertThrowsError(try JSONDecoder().decode(GuestTarget.self, from: Data("{\"distribution\":\"ubuntu\",\"release\":\"24.04\",\"architecture\":\"arm64\"}".utf8)))
    }

    func testManifestValidationAccumulatesIndependentErrors() throws {
        let manifest = ProjectManifest(
            schema: 2,
            distribution: "ubuntu",
            release: "24.04",
            workspace: "../outside",
            resources: .init(cpus: 0, memoryMiB: 1000, diskGiB: 9),
            bootstrap: .init(command: "", timeoutSeconds: 0),
            services: [
                .init(name: "Web", command: "", workingDirectory: "../outside", port: 80, hostPort: 80, health: "ftp://localhost:80"),
                .init(name: "Web", command: "run", workingDirectory: ".", port: 80, hostPort: 80, health: nil),
            ]
        )
        let issues = ManifestValidator(environment: .init(logicalCPUs: 4, availableMemoryMiB: 8192)).validate(manifest)
        XCTAssertGreaterThanOrEqual(issues.count, 10)
        XCTAssertTrue(issues.contains { $0.path == "schema" })
        XCTAssertTrue(issues.contains { $0.path == "service[1].name" })
        XCTAssertTrue(issues.contains { $0.path == "service[1].port" })
    }

    func testHealthURLRejectsEmbeddedCredentials() throws {
        var manifest = ProjectManifest.fixture()
        manifest.services[0].health = "http://user:secret@localhost:3000/health"
        let issues = ManifestValidator(environment: .init(logicalCPUs: 4, availableMemoryMiB: 8192)).validate(manifest)
        XCTAssertTrue(issues.contains { $0.path == "service[0].health" })
    }

    func testOverrideChangesOnlyAllowedFieldsAndMatchesServiceByName() throws {
        let manifest = ProjectManifest.fixture()
        let override = LocalOverride(
            resources: .init(cpus: 3, memoryMiB: nil, diskGiB: 50),
            services: [.init(name: "web", hostPort: 3001, healthTimeoutSeconds: 90)]
        )
        let merged = try ConfigMerger.merge(manifest: manifest, override: override)
        XCTAssertEqual(merged.resources.cpus, 3)
        XCTAssertEqual(merged.resources.memoryMiB, 4096)
        XCTAssertEqual(merged.resources.diskGiB, 50)
        XCTAssertEqual(merged.services[0].hostPort, 3001)
        XCTAssertEqual(merged.services[0].healthTimeoutSeconds, 90)
        XCTAssertEqual(manifest.services[0].hostPort, 0)
        XCTAssertThrowsError(try ConfigMerger.merge(manifest: manifest, override: .init(resources: nil, services: [.init(name: "unknown", hostPort: 3001, healthTimeoutSeconds: nil)])))
    }

    func testIPCIsVersionedAndRoundTripsWithoutSecrets() throws {
        let request = IPCRequest(requestID: UUID(), method: .instanceList, parameters: .object([:]), clientVersion: .init(major: 1, minor: 0))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertThrowsError(try ProtocolVersion(major: 2, minor: 0).requireCompatible(with: .current))
        let error = MSLFailure(code: .permissionDenied, message: "permission denied", details: ["token": "redacted"])
        XCTAssertFalse(error.description.contains("redacted"))
        XCTAssertThrowsError(try JSONDecoder().decode(IPCResponse.self, from: Data("{\"requestID\":\"00000000-0000-0000-0000-000000000000\",\"result\":null,\"failure\":null}".utf8)))
    }
}

private extension ProjectManifest {
    static func fixture() -> ProjectManifest {
        ProjectManifest(
            schema: 1,
            distribution: "debian",
            release: "12",
            workspace: ".",
            resources: .init(cpus: 2, memoryMiB: 4096, diskGiB: 40),
            bootstrap: .init(command: "./.msl/bootstrap.sh", timeoutSeconds: 900),
            services: [.init(name: "web", command: "npm run dev", workingDirectory: ".", port: 3000, hostPort: 0, health: "http://127.0.0.1:3000/health", healthTimeoutSeconds: 60)]
        )
    }
}
