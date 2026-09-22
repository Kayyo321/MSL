import XCTest
@testable import MSLCore

final class RecoveryTests: XCTestCase {
    func testInterruptedOperationNeverReportsSuccess() {
        let journal = OperationJournal(
            operationID: UUID(),
            instanceID: UUID(),
            kind: .install,
            state: .applying,
            recovery: .manualRepair
        )

        XCTAssertEqual(RecoveryPlanner.decide(for: journal), .markRepairRequired)
    }

    func testIdempotentRecoveryMayResumeOnlyWhenExplicitlyRecorded() {
        let resumable = OperationJournal(
            operationID: UUID(),
            instanceID: UUID(),
            kind: .start,
            state: .applying,
            recovery: .resumeIfIdempotent
        )
        let rollback = OperationJournal(
            operationID: UUID(),
            instanceID: UUID(),
            kind: .install,
            state: .prepared,
            recovery: .rollback
        )

        XCTAssertEqual(RecoveryPlanner.decide(for: resumable), .resume)
        XCTAssertEqual(RecoveryPlanner.decide(for: rollback), .rollback)
    }

    func testCommittedOperationNeedsNoRecovery() {
        let journal = OperationJournal(
            operationID: UUID(),
            instanceID: UUID(),
            kind: .stop,
            state: .committed,
            recovery: .manualRepair
        )

        XCTAssertEqual(RecoveryPlanner.decide(for: journal), .none)
    }

    func testOnlyOneMutationCanHoldAnInstanceLock() async throws {
        let coordinator = InstanceMutationCoordinator()
        let instanceID = UUID()

        let lease = try await coordinator.begin(instanceID: instanceID)
        await XCTAssertThrowsErrorAsync(try await coordinator.begin(instanceID: instanceID))
        try await coordinator.finish(lease)
        do {
            _ = try await coordinator.begin(instanceID: instanceID)
        } catch {
            XCTFail("lock should be available after finish: \(error)")
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
