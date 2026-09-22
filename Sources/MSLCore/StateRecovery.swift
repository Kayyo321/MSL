import Foundation

/// The only persistent instance states permitted by the v1 contract.
public enum InstanceRuntimeState: String, Codable, Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case error
    case repairRequired = "repair_required"
}

public enum OperationKind: String, Codable, Equatable, Sendable {
    case install
    case start
    case stop
    case resize
    case restore
    case remove

    fileprivate var canResumeIdempotently: Bool {
        self == .start || self == .stop
    }
}

/// A journal progresses monotonically; committed work is the sole successful state.
public enum JournalState: String, Codable, Equatable, Sendable {
    case prepared
    case applying
    case committed
}

/// Recovery intent is recorded before mutation so daemon restart never guesses.
public enum RecoveryPolicy: String, Codable, Equatable, Sendable {
    case rollback
    case resumeIfIdempotent = "resume_if_idempotent"
    case manualRepair = "manual_repair"
}

public struct OperationJournal: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let instanceID: UUID
    public let kind: OperationKind
    public let state: JournalState
    public let recovery: RecoveryPolicy

    public init(operationID: UUID, instanceID: UUID, kind: OperationKind, state: JournalState, recovery: RecoveryPolicy) {
        self.operationID = operationID
        self.instanceID = instanceID
        self.kind = kind
        self.state = state
        self.recovery = recovery
    }
}

public enum RecoveryDecision: Equatable, Sendable {
    case none
    case resume
    case rollback
    case markRepairRequired
}

/// Pure recovery logic. Persistent storage must journal before touching resources.
public enum RecoveryPlanner {
    public static func decide(for journal: OperationJournal) -> RecoveryDecision {
        guard journal.state != .committed else { return .none }
        switch journal.recovery {
        case .resumeIfIdempotent where journal.kind.canResumeIdempotently: return .resume
        case .rollback: return .rollback
        case .resumeIfIdempotent, .manualRepair: return .markRepairRequired
        }
    }
}

public enum MutationLockError: Error, Equatable, LocalizedError, Sendable {
    case operationInProgress(UUID)

    public var errorDescription: String? {
        switch self {
        case let .operationInProgress(instanceID): return "operation already in progress for instance \(instanceID.uuidString.lowercased())"
        }
    }
}

public struct MutationLease: Codable, Equatable, Sendable {
    public let instanceID: UUID
    public let operationID: UUID
    public init(instanceID: UUID, operationID: UUID) { self.instanceID = instanceID; self.operationID = operationID }
}

/// In-process-only mutation guard. The future SQLite store must add the required
/// cross-process uniqueness constraint; this actor must never be treated as a
/// durable lock.
public actor InstanceMutationCoordinator {
    private var leases: [UUID: MutationLease] = [:]
    public init() {}

    public func begin(instanceID: UUID) throws -> MutationLease {
        guard leases[instanceID] == nil else { throw MutationLockError.operationInProgress(instanceID) }
        let lease = MutationLease(instanceID: instanceID, operationID: UUID())
        leases[instanceID] = lease
        return lease
    }

    public func finish(_ lease: MutationLease) throws {
        guard leases[lease.instanceID] == lease else { throw MutationLockError.operationInProgress(lease.instanceID) }
        leases.removeValue(forKey: lease.instanceID)
    }

    public func isHeld(instanceID: UUID) -> Bool { leases[instanceID] != nil }
}
