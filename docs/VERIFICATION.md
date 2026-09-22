# MSL verification specification

This document defines the required evidence for an MSL release. Every product
claim in [PROJECT.md](../PROJECT.md) and every behavior in
[IMPLEMENTATION.md](IMPLEMENTATION.md) and [WORKFLOW.md](WORKFLOW.md) must be
covered by executable checks here. A unit-test pass alone is insufficient: final
acceptance requires real Virtualization.framework guests on a clean macOS user.

## 1. Environments, evidence, and release gates

Run tests in these environments:

| Environment | Required setup | Purpose |
| --- | --- | --- |
| unit | Temporary directories, fake clock/network/VM adapters | Types, schema, state machines, migrations, validation, and recovery decisions. |
| integration | Disposable macOS account on Apple silicon/macOS 14 latest patch, real daemon and signed test image | CLI, daemon, guest agent, mounts, network, and lifecycle. |
| upgrade | Prior released state copied to disposable account | Migrations and prior-instance compatibility. |
| stress | Controlled storage, sleep, network, and process-failure injection | Races, interruption, and resource recovery. |
| security | Synthetic secrets/folders/listeners and hostile guest fixture | Host-guest boundary and negative authorization cases. |

CI pins the Swift toolchain and test image digest. Test catalogs use a dedicated
test signing key; production private keys are never supplied to tests. Each
integration test creates unique instance names, workspace paths, and host ports.
Cleanup proves its resources disappeared; any residual resource is a failure.

Each result records MSL version/commit, macOS version/build, architecture, image
digest, test ID, duration, exit code, and sanitized log bundle. Unless a test
says otherwise, a failure must leave no unintended database row, disk, mount, or
MSL-owned listener. The harness verifies no mutation by comparing database
snapshot, instance-directory inventory, and open listeners before and after.
mslctl may inject a fault but public acceptance tests invoke the msl CLI.

A release passes only when all required cases pass, MSLCore and daemon
mutation/recovery code reach at least 90% line and 85% branch coverage, static
analysis has no unresolved high-severity finding, dependency audit has no
unresolved critical finding, and a clean account verifies production artifacts
with production public keys. A skipped test blocks release until the associated
feature claim is removed. Privacy/security violations, integrity bypasses,
unexpected LAN exposure, corruption, and unrequested data loss always block
release.

## 2. Installation, state, and lifecycle

| ID | Action | Required assertion |
| --- | --- | --- |
| INS-001 | Clean account installs Debian 12 arm64 as u1. | Verified artifact is cached by digest; one database instance, disk, and agent-ready first boot exist; final state is stopped. |
| INS-002 | Install with wrong image digest. | Exit 6; no usable instance or final cache file; error identifies integrity. |
| INS-003 | Install with invalid catalog signature. | Exit 6 before image use and with no state mutation. |
| INS-004 | Request unknown distribution, arbitrary URL, unsupported release, and x86 image. | Each exits 2 or 4; no download/instance occurs. |
| INS-005 | Interrupt download, disk creation, and first boot at every operation-journal boundary, then restart daemon. | Recovery removes only partial temporary state or marks repair_required; it never claims success or harms valid instance. |
| LIFE-001 | Start a stopped valid instance. | State reaches running; virtio handshake succeeds; designated-user shell works. |
| LIFE-002 | Start running instance and stop stopped instance. | Both exit 0 with idempotency marker and create no duplicate VM/shutdown. |
| LIFE-003 | Stop cooperative guest. | Services stop; guest shuts down within 60 seconds; state stopped; disk persists. |
| LIFE-004 | Stop unresponsive guest. | Forced stop reports clean=false, retains logs, and schedules guest fs check next boot. |
| LIFE-005 | Force start crash and inspect. | State error includes recent console evidence and recovery action; no stale runtime socket. |
| LIFE-006 | Use unsupported OS/non-Apple-silicon adapter. | Exit 4 before state creation or alteration. |
| STATE-001 | Corrupt or lock test database then start daemon. | No write-through; specific storage error; disks untouched. |
| STATE-002 | Migrate every supported prior schema. | Atomic migration preserves instances/grants/snapshots and passes integrity_check. |

## 3. CLI contract and destructive behavior

| ID | Action | Required assertion |
| --- | --- | --- |
| CLI-001 | Invoke all commands with missing, malformed, unknown, and conflicting options. | Exit 2, error identifies input, zero mutation. |
| CLI-002 | Use --json for success and each failure family. | Exactly one valid JSON object on stdout with code/message/details; no prompt/progress contaminates stdout. |
| CLI-003 | One instance exists; invoke msl outside project. | Opens that instance. |
| CLI-004 | Multiple instances exist; invoke msl outside project. | Exit 2 with instance_selection_required and candidates; no recency selection. |
| CLI-005 | Run from nested project directory with manifest instance. | Nearest ancestor manifest selects exactly that instance. |
| CLI-006 | Invoke remove/restore/delete in terminal, pipe without --yes, pipe with --yes. | Terminal requires exact target text; noninteractive refusal without --yes; approved case changes only named target. |
| CLI-007 | Start two mutations against one instance concurrently. | One obtains lock; other exits 5 with current operation; no partial second change. |
| CLI-008 | Interrupt CLI while daemon mutation continues. | Daemon completes/recoverably journals work; later inspect shows definitive outcome. |

## 4. Filesystem, privacy, and host handoff

| ID | Action | Required assertion |
| --- | --- | --- |
| FS-001 | Grant selected directory read-write at /mnt/mac/project, boot guest. | Guest reads/writes exact selected directory; host and guest file changes are visible. |
| FS-002 | Grant read-only then attempt guest write. | Write fails and host content remains unchanged. |
| FS-003 | With no grants, attempt reads of home, Library, sibling directory, and synthetic secret. | Every host location is inaccessible. |
| FS-004 | Request root, whole home, Library, system, duplicate/nested, /workspace, and dot-dot guest targets. | Exit 2 and no grant row/bookmark. |
| FS-005 | Revoke selected folder authorization then restart VM. | Mount absent; grant permission-stale; unrelated shares work; doctor detects it. |
| FS-006 | Add/remove share while VM runs. | State pending; guest mount unchanged until restart; final restart state matches request. |
| FS-007 | Search database and logs after share actions. | No bookmark bytes, tokens, shared-file content, or raw sensitive values. |
| FS-008 | Exercise case collision, executable bit, symlink, xattr, and ACL on Mac share. | doctor reports applicable semantic limitation rather than claiming ext4 behavior. |
| CTL-001 | Authenticate guest agent and invoke every allowed capability. | Only specified browser/file/editor/clipboard/notification action occurs with input limits enforced. |
| CTL-002 | Use wrong secret/peer, malformed message, oversize message, duplicate ID, incompatible version. | Denied with no host effect; service remains available to valid client. |
| CTL-003 | Request host shell, arbitrary path, Keychain, clipboard read, device access, file URL, escaping symlink path. | Each denied with specific code and no fallback. |
| CTL-004 | Send six notifications in one minute, wait one minute, send another. | First five eligible, sixth rate-limited, later request eligible after window. |
| CTL-005 | Scan guest and host sockets while agent active. | No TCP/UDP agent control listener exists; control is VM-local virtio only. |

## 5. Networking and project services

| ID | Action | Required assertion |
| --- | --- | --- |
| NET-001 | Run host test server and resolve host.msl.internal in guest. | Guest reaches it on every boot. |
| NET-002 | Expose guest HTTP 3000 as host 3000. | 127.0.0.1:3000 returns that guest's response. |
| NET-003 | Probe forwarding through host LAN IPv4 and IPv6. | Unreachable/refused; listener inspection proves loopback-only bind. |
| NET-004 | Request occupied port, allocation, low/high invalid ports, UDP, and duplicate active port. | Conflict exits 5; allocation persists free 49152-65535; invalid cases exit 2; no fallback. |
| NET-005 | Forward a guest loopback-only process. | Failed health/connect explains reachable guest binding requirement; no unintended proxy. |
| NET-006 | Remove forward while service runs. | Host listener closes immediately; guest process remains; grant revoked. |
| NET-007 | Restart VM with forward and start another VM using same guest port. | Traffic reaches only owner instance and remains loopback-only. |
| PRJ-001 | Validate complete documented manifest. | Exit 0 with no VM/disk/database/listener mutation. |
| PRJ-002 | Validate unknown key/version, invalid resource, empty command, invalid/duplicate name, external directory, invalid health URL. | All independent errors appear; exit 2; no mutation. |
| PRJ-003 | Load unignored local override. | Validation fails before using it. |
| PRJ-004 | Use allowed and forbidden override fields. | Allowed values merge by named service; forbidden image/workspace/command/guest-port changes fail; no extra service. |
| PRJ-005 | First project up with successful workspace/bootstrap/service. | Exact folder mounted at /workspace; bootstrap user/cwd correct; health passes; printed URL loopback-only. |
| PRJ-006 | Up unchanged project a second time. | Bootstrap does not run; reconciliation is idempotent. |
| PRJ-007 | Change manifest, override, image digest, and workspace bookmark one at a time. | Each changes bootstrap hash and runs it once; irrelevant timestamp/log changes do not. |
| PRJ-008 | Bootstrap exits nonzero or times out. | Services from invocation are stopped; VM/workspace remain; logs exist; no retry. |
| PRJ-009 | Service exits early, returns HTTP 500, returns 302, or never opens TCP. | Early/500/closed fail; 302 succeeds; checks occur once/second to exact timeout. |
| PRJ-010 | Start declared services, run project down, inspect VM. | Only declared services/forwards stop; VM, disk, shell, workspace, and manual forward persist. |
| PRJ-011 | Kill healthy service. | Status becomes unhealthy/exited; no hidden restart loop. |

## 6. Snapshots, transfers, diagnostics, and logs

| ID | Action | Required assertion |
| --- | --- | --- |
| DATA-001 | Snapshot stopped instance, alter known file, restore snapshot. | Restored disk/config match captured digest; automatic pre-restore snapshot exists. |
| DATA-002 | Snapshot or restore while running. | Refuses before disk change. |
| DATA-003 | Inject failure at each restore replacement stage. | Original or pre-restore snapshot recoverable; partial disk never boots; repair_required when needed. |
| DATA-004 | Export stopped instance with known file, share, forward, secret-like text, and log. | Archive includes disk/config/manifest; excludes grants/forwards/live secrets and logs unless requested. |
| DATA-005 | Import valid, corrupted, and tampered exports. | Valid gets new UUID/no host grants; invalid fails validation with no instance; names never overwrite. |
| DATA-006 | Remove instance with disk, snapshot, share, and forward. | Exact confirmation required; VM stops; grants/listeners revoke; directory moves to Trash; shared cache stays. |
| DATA-007 | Simulate missing Trash, then remove with and without --permanent --yes. | First refuses without deletion; second deletes only named target and reports permanent removal. |
| DIA-001 | Run doctor on healthy fixture. | All nine named checks pass and command is read-only. |
| DIA-002 | Independently break virtualization, image hash, bookmark, mount, listener, DNS, health. | Corresponding check fails with evidence and narrow next action; unrelated items untouched. |
| DIA-003 | Repair a failure and repair a non-failure. | Repair accepts only one named failed check, previews action, changes only its resources. |
| DIA-004 | Invoke commands with secret-like args/env/project paths/clipboard data and search logs. | Prohibited values absent; required event metadata present. |
| DIA-005 | Generate more than 50 MiB console data. | Current plus ten rotated logs only; retained size bounded; no automatic export. |

## 7. Security regression

Run every case after changes to IPC, guest agent, filesystem, networking,
permission, snapshot, or import/export code.

| ID | Attack | Required defense |
| --- | --- | --- |
| SEC-001 | Path traversal, symlink escape, Unicode collision, mount table tampering in file/editor handoff. | Permit only canonical paths inside active bookmark-backed mount. |
| SEC-002 | Another macOS user accesses socket, database, runtime token, disk, instance directory. | Filesystem permissions and peer UID deny it without disclosure. |
| SEC-003 | Unprivileged local process replays/malforms service tokens. | Deny, bound resource use, preserve valid service. |
| SEC-004 | Guest requests LAN, privileged, or UDP listener. | Only declared loopback TCP range is allowed. |
| SEC-005 | Tamper cache, catalog, agent artifact, export, snapshot manifest. | Validation prevents use; valid existing instances untouched. |
| SEC-006 | Inject shell syntax through names, paths, TOML escaping, service fields. | Strict schema/parameterized host launches; only declared guest bootstrap/service shell runs. |
| SEC-007 | Flood capabilities, listener bytes, console, malformed IPC. | Size/rate limits bound memory/disk; valid operations recover. |

## 8. Manual acceptance and performance

A human tester records screenshots or capture plus sanitized logs for each:

1. From a clean macOS account, install Debian 12 arm64 and reach a shell through
   the promised two-command experience.
2. Share a real repository, edit with a Mac editor, compile/test at /workspace,
   and observe changes both directions without SSH or manual VM folders.
3. Open a guest web service in a Mac browser using the printed loopback URL, then
   prove a second device on the same network cannot reach it.
4. Use apt, systemctl, a timer, background service, symlink, and guest package;
   reboot macOS and verify persistent state.
5. Review all permission/destructive prompts: a tester can say what instance,
   path, port, or data is affected and how to revoke it.
6. Revoke a folder, create port conflict, interrupt image download, and fill
   disk; each error must be specific and non-destructive.
7. Export/import under a fresh name and confirm no host share/port survives.

Use a reference Apple-silicon CI host with warm cache, 4 guest CPU, 4 GiB RAM,
40 GiB disk, and 50,000-file repository. Ten independent runs must meet:

| Metric | Target |
| --- | --- |
| instance list with 20 stopped instances | p95 <=300 ms |
| warm VM to authenticated shell | p95 <=12 s |
| unchanged project up to healthy URL | p95 <=20 s |
| add forward after guest ready | p95 <=1 s |
| 50,000-file workspace metadata scan | <=2x host-native scan |
| daemon crash recovery | no disk corruption; recovered state <=30 s |
| stopped-instance CPU | median 0%; no poll more than once/minute |

A performance target exceeded by more than 20% on two consecutive reference-host
runs blocks release unless explicitly accepted in release notes. A security or
data-integrity failure cannot be waived.

## 9. Traceability and sign-off

Maintain a checked-in mapping from every PROJECT.md requirement to test IDs.
Any user-visible capability change updates implementation, workflow, mapping,
automated test, and a negative test when it crosses the host-guest boundary.

Release sign-off requires engineering review of the complete test report and
security review of the regression report. The record names release commit,
catalog digest, test image digest, test environments, and only explicitly
accepted non-security known issues. No waiver may cover a violation of the
privacy/security model.

