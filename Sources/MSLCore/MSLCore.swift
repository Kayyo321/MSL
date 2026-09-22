import Foundation

public enum MSLCoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidIdentifier(kind: String, value: String)
    case unsupportedGuest(distribution: String, release: String, architecture: String)
    case incompatibleProtocol(clientMajor: Int, serverMajor: Int)
    case invalidOverrideService(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(kind, _): return "invalid \(kind)"
        case .unsupportedGuest: return "only Debian 12 arm64 is supported"
        case let .incompatibleProtocol(clientMajor, serverMajor): return "incompatible protocol major version \(clientMajor); expected \(serverMajor)"
        case let .invalidOverrideService(name): return "local override names unknown service \(name)"
        }
    }
}

public struct InstanceName: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) throws {
        guard Self.isValid(value) else { throw MSLCoreError.invalidIdentifier(kind: "instance name", value: value) }
        rawValue = value
    }
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        try self.init(value)
    }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
    private static func isValid(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9-]{0,31}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

public struct LinuxUser: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) throws {
        guard Self.isValid(value) else { throw MSLCoreError.invalidIdentifier(kind: "Linux user", value: value) }
        rawValue = value
    }
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        try self.init(value)
    }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
    private static func isValid(_ value: String) -> Bool {
        let matches = value.range(of: "^[a-z_][a-z0-9_-]{0,30}$", options: .regularExpression) == value.startIndex..<value.endIndex
        let forbidden = value == "root" || value == "daemon" || value == "nobody" || value.hasPrefix("systemd-")
        return matches && !forbidden
    }
}

public struct OpaqueID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(_ value: UUID = UUID()) { rawValue = value }
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public var stringValue: String { rawValue.uuidString.lowercased() }
}

public struct GuestTarget: Codable, Equatable, Sendable {
    public static let supportedDistribution = "debian"
    public static let supportedRelease = "12"
    public static let supportedArchitecture = "arm64"
    public let distribution: String
    public let release: String
    public let architecture: String

    public init(distribution: String, release: String, architecture: String) throws {
        guard distribution == Self.supportedDistribution, release == Self.supportedRelease, architecture == Self.supportedArchitecture else {
            throw MSLCoreError.unsupportedGuest(distribution: distribution, release: release, architecture: architecture)
        }
        self.distribution = distribution
        self.release = release
        self.architecture = architecture
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(distribution: container.decode(String.self, forKey: .distribution), release: container.decode(String.self, forKey: .release), architecture: container.decode(String.self, forKey: .architecture))
    }
}

public struct ValidationIssue: Codable, Equatable, Sendable {
    public let path: String
    public let message: String
    public init(path: String, message: String) { self.path = path; self.message = message }
}

public struct ProjectManifest: Codable, Equatable, Sendable {
    public struct Resources: Codable, Equatable, Sendable {
        public var cpus: Int
        public var memoryMiB: Int
        public var diskGiB: Int
        public init(cpus: Int, memoryMiB: Int, diskGiB: Int) { self.cpus = cpus; self.memoryMiB = memoryMiB; self.diskGiB = diskGiB }
    }
    public struct Bootstrap: Codable, Equatable, Sendable {
        public var command: String
        public var timeoutSeconds: Int
        public init(command: String, timeoutSeconds: Int) { self.command = command; self.timeoutSeconds = timeoutSeconds }
    }
    public struct Service: Codable, Equatable, Sendable {
        public var name: String
        public var command: String
        public var workingDirectory: String
        public var port: Int
        public var hostPort: Int
        public var health: String?
        public var healthTimeoutSeconds: Int
        public init(name: String, command: String, workingDirectory: String, port: Int, hostPort: Int = 0, health: String? = nil, healthTimeoutSeconds: Int = 60) {
            self.name = name; self.command = command; self.workingDirectory = workingDirectory; self.port = port; self.hostPort = hostPort; self.health = health; self.healthTimeoutSeconds = healthTimeoutSeconds
        }
    }
    public var schema: Int
    public var distribution: String
    public var release: String
    public var workspace: String
    public var resources: Resources
    public var bootstrap: Bootstrap
    public var services: [Service]
    public init(schema: Int, distribution: String, release: String, workspace: String, resources: Resources, bootstrap: Bootstrap, services: [Service]) {
        self.schema = schema; self.distribution = distribution; self.release = release; self.workspace = workspace; self.resources = resources; self.bootstrap = bootstrap; self.services = services
    }
}

public struct ManifestEnvironment: Equatable, Sendable {
    public let logicalCPUs: Int
    public let availableMemoryMiB: Int
    public init(logicalCPUs: Int, availableMemoryMiB: Int) { self.logicalCPUs = logicalCPUs; self.availableMemoryMiB = availableMemoryMiB }
}

public struct ManifestValidator: Sendable {
    public let environment: ManifestEnvironment
    public init(environment: ManifestEnvironment) { self.environment = environment }

    public func validate(_ manifest: ProjectManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func append(_ condition: Bool, _ path: String, _ message: String) { if !condition { issues.append(.init(path: path, message: message)) } }
        append(manifest.schema == 1, "schema", "must be integer 1")
        append(manifest.distribution == "debian", "distribution", "must be debian")
        append(manifest.release == "12", "release", "must be 12")
        append(isRelativeContainedPath(manifest.workspace), "workspace", "must resolve within the manifest directory")
        append((1...environment.logicalCPUs).contains(manifest.resources.cpus), "resources.cpus", "must be between 1 and host logical CPU count")
        let memoryUpper = max(0, environment.availableMemoryMiB - 1024)
        append(manifest.resources.memoryMiB >= 1024 && manifest.resources.memoryMiB <= memoryUpper && manifest.resources.memoryMiB % 256 == 0, "resources.memory_mib", "must be an available 256 MiB increment")
        append((10...1024).contains(manifest.resources.diskGiB), "resources.disk_gib", "must be between 10 and 1024 GiB")
        append(!manifest.bootstrap.command.isEmpty && manifest.bootstrap.command.utf8.count <= 4096, "bootstrap.command", "must be a non-empty UTF-8 string no longer than 4096 bytes")
        append(manifest.bootstrap.timeoutSeconds > 0, "bootstrap.timeout_seconds", "must be positive")
        var names = Set<String>(); var guestPorts = Set<Int>(); var hostPorts = Set<Int>()
        for (index, service) in manifest.services.enumerated() {
            let prefix = "service[\(index)]"
            let nameMatches = service.name.range(of: "^[a-z][a-z0-9-]{0,31}$", options: .regularExpression)?.lowerBound == service.name.startIndex
            append(nameMatches, "\(prefix).name", "must match ^[a-z][a-z0-9-]{0,31}$")
            append(names.insert(service.name).inserted, "\(prefix).name", "must be unique")
            append(!service.command.isEmpty && service.command.utf8.count <= 4096, "\(prefix).command", "must be a non-empty UTF-8 string no longer than 4096 bytes")
            append(isRelativeContainedPath(service.workingDirectory), "\(prefix).working_directory", "must remain inside workspace")
            append((1024...65535).contains(service.port), "\(prefix).port", "must be a TCP port from 1024 through 65535")
            append(guestPorts.insert(service.port).inserted, "\(prefix).port", "must be unique")
            append(service.hostPort == 0 || (1024...65535).contains(service.hostPort), "\(prefix).host_port", "must be 0 or a TCP port from 1024 through 65535")
            if service.hostPort != 0 { append(hostPorts.insert(service.hostPort).inserted, "\(prefix).host_port", "must be unique") }
            append(service.healthTimeoutSeconds > 0, "\(prefix).health_timeout_seconds", "must be positive")
            if let health = service.health { append(isValidHealthURL(health, port: service.port), "\(prefix).health", "must be HTTP(S) to localhost or 127.0.0.1 on the service port") }
        }
        return issues
    }

    private func isRelativeContainedPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
    private func isValidHealthURL(_ value: String, port: Int) -> Bool {
        guard let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme), parts.user == nil, parts.password == nil, let host = parts.host?.lowercased(), ["localhost", "127.0.0.1"].contains(host) else { return false }
        return parts.port == port
    }
}

public struct LocalOverride: Codable, Equatable, Sendable {
    public struct Resources: Codable, Equatable, Sendable {
        public var cpus: Int?
        public var memoryMiB: Int?
        public var diskGiB: Int?
        public init(cpus: Int?, memoryMiB: Int?, diskGiB: Int?) { self.cpus = cpus; self.memoryMiB = memoryMiB; self.diskGiB = diskGiB }
    }
    public struct Service: Codable, Equatable, Sendable {
        public var name: String
        public var hostPort: Int?
        public var healthTimeoutSeconds: Int?
        public init(name: String, hostPort: Int?, healthTimeoutSeconds: Int?) { self.name = name; self.hostPort = hostPort; self.healthTimeoutSeconds = healthTimeoutSeconds }
    }
    public var resources: Resources?
    public var services: [Service]
    public init(resources: Resources?, services: [Service]) { self.resources = resources; self.services = services }
}

public enum ConfigMerger {
    public static func merge(manifest: ProjectManifest, override local: LocalOverride) throws -> ProjectManifest {
        var merged = manifest
        if let resources = local.resources {
            if let value = resources.cpus { merged.resources.cpus = value }
            if let value = resources.memoryMiB { merged.resources.memoryMiB = value }
            if let value = resources.diskGiB { merged.resources.diskGiB = value }
        }
        for serviceOverride in local.services {
            guard let index = merged.services.firstIndex(where: { $0.name == serviceOverride.name }) else { throw MSLCoreError.invalidOverrideService(serviceOverride.name) }
            if let value = serviceOverride.hostPort { merged.services[index].hostPort = value }
            if let value = serviceOverride.healthTimeoutSeconds { merged.services[index].healthTimeoutSeconds = value }
        }
        return merged
    }
}

public enum ExitCode: Int, Codable, Sendable { case success = 0, internalFailure = 1, invalidInput = 2, permissionDenied = 3, unavailable = 4, conflict = 5, integrityFailure = 6, guestFailure = 7 }

public struct MSLFailure: Codable, Equatable, Error, CustomStringConvertible, Sendable {
    public let code: ExitCode
    public let message: String
    public let details: [String: String]
    public init(code: ExitCode, message: String, details: [String: String] = [:]) { self.code = code; self.message = message; self.details = details }
    public var description: String { "MSL failure (\(code.rawValue)): \(message)" }
}

public struct ProtocolVersion: Codable, Equatable, Sendable {
    public static let current = ProtocolVersion(major: 1, minor: 0)
    public let major: Int
    public let minor: Int
    public init(major: Int, minor: Int) { self.major = major; self.minor = minor }
    public func requireCompatible(with server: ProtocolVersion) throws { if major != server.major { throw MSLCoreError.incompatibleProtocol(clientMajor: major, serverMajor: server.major) } }
}

public enum IPCMethod: String, Codable, Sendable { case instanceList = "instance.list", instanceInspect = "instance.inspect", install, shell, guestStatus = "guest.status", execShell = "guest.exec_shell", serviceApply = "guest.service_apply", serviceStop = "guest.service_stop", serviceStatus = "guest.service_status", healthCheck = "guest.health_check", shutdown = "guest.shutdown" }

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null } else if let value = try? container.decode(Bool.self) { self = .bool(value) } else if let value = try? container.decode(Double.self) { self = .number(value) } else if let value = try? container.decode(String.self) { self = .string(value) } else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) } else { self = .array(try container.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case let .string(value): try container.encode(value); case let .number(value): try container.encode(value); case let .bool(value): try container.encode(value); case let .object(value): try container.encode(value); case let .array(value): try container.encode(value); case .null: try container.encodeNil() }
    }
}

public struct IPCRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let method: IPCMethod
    public let parameters: JSONValue
    public let clientVersion: ProtocolVersion
    public init(requestID: UUID, method: IPCMethod, parameters: JSONValue, clientVersion: ProtocolVersion) { self.requestID = requestID; self.method = method; self.parameters = parameters; self.clientVersion = clientVersion }
}

public struct IPCResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let result: JSONValue?
    public let failure: MSLFailure?
    public init(requestID: UUID, result: JSONValue) { self.requestID = requestID; self.result = result; self.failure = nil }
    public init(requestID: UUID, failure: MSLFailure) { self.requestID = requestID; self.result = nil; self.failure = failure }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let requestID = try container.decode(UUID.self, forKey: .requestID)
        let result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        let failure = try container.decodeIfPresent(MSLFailure.self, forKey: .failure)
        switch (result, failure) {
        case let (.some(result), nil): self.init(requestID: requestID, result: result)
        case let (nil, .some(failure)): self.init(requestID: requestID, failure: failure)
        default: throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "an IPC response must contain exactly one of result or failure")
        }
    }
}
