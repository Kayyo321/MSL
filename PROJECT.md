# MSL — Mac Subsystem for Linux

## 1. Product definition

MSL is a macOS-native Linux subsystem modeled on the *developer experience* of WSL 2: a user installs a named Linux distribution with one command, starts a shell immediately, and uses Linux tools against their normal workstation files and services. Unlike a container runtime, each installed distribution is a persistent, full Linux userspace running its own Linux kernel in a managed virtual machine.

MSL is not an emulator, a compatibility layer, or a Docker replacement. It is a local-development Linux environment that has deliberately convenient, permissioned integration with macOS.

### Why MSL exists beside Lima, Multipass, and OrbStack

MSL must not compete merely by being another way to boot a Linux VM. Its product position is **the reproducible, project-aware Linux development subsystem for macOS**: it makes a Linux environment feel local while preserving an auditable, least-privilege boundary. The differentiators below are product requirements, not optional marketing language.

| Differentiator | MSL commitment | User outcome |
| --- | --- | --- |
| Project-native environments | A committed `msl.toml` defines the exact distribution, resources, mounts, ports, bootstrap, and health checks for one repository. | A teammate enters the same environment with one command. |
| Host/guest handoff | Path, URL, clipboard, editor, and notification integrations are explicit commands with fixed behavior. | No SSH, IP-address hunting, or fragile shell glue. |
| Privacy-first integration | Every host capability is a visible, revocable grant; the subsystem never asks for broad disk access by default. | A Linux project gets what it needs, and nothing else. |
| Compatibility diagnosis | MSL detects macOS/Linux filesystem, architecture, VPN/DNS, and port issues and gives actionable remediation. | Failures are explained as subsystem problems, not left as VM debugging. |
| Portable developer contract | `msl.toml`, lockfiles, export bundles, and JSON CLI output are stable and documented. | A project is reproducible in CI and across developers’ Macs. |

### Product goals

- Install and use a supported distribution with `msl install <distro>` and `msl`.
- Provide a real Linux kernel and standard systemd-based distribution environment.
- Make macOS home and selected volumes available to Linux with predictable paths and permissions.
- Allow Linux processes to reach macOS services and allow explicitly authorized macOS clients to reach Linux services.
- Preserve distributions, user data, configuration, and snapshots across reboots and upgrades.
- Require no manual VM, network, disk-image, or SSH setup for the common path.
- Run on Apple silicon and Intel Macs supported by the selected macOS baseline.
- Make a checked-in project environment as reproducible as a checked-in dependency lockfile.

### Explicit non-goals for v1

- Running Linux GUI desktops or arbitrary Linux GUI apps on macOS.
- Windows interoperability or WSL binary/configuration compatibility.
- Kernel module loading, custom kernels, nested virtualization, or privileged Docker-in-VM support.
- Transparent access to every macOS resource without a user-granted permission.
- Multi-host orchestration, Kubernetes management, or a graphical VM manager.

## 2. Platform and hard constraints

MSL requires macOS 14 (Sonoma) or later and uses Apple’s Virtualization framework. The host daemon is a signed, notarized privileged helper installed through macOS’s supported authorization flow. The CLI is an unprivileged command-line client.

The guest architecture always matches the host architecture:

| Host | Guest image architecture |
| --- | --- |
| Apple silicon | `arm64` |
| Intel | `amd64` |

MSL ships and verifies a manifest of supported, architecture-specific root filesystem images. v1 supports Ubuntu 24.04 LTS and Debian 12. Additional distributions must be added only through signed manifests and integration tests; arbitrary OCI images are not a distribution-install input.

## 3. User-facing contract

### CLI

The executable is `msl`. Commands return `0` for success, `1` for operational failure, `2` for invalid command-line usage, and `3` when user authorization or macOS privacy consent is required.

```text
msl install <distro> [--name <instance>] [--user <linux-user>] [--disk-size <GiB>]
msl init [--distro <distro>] [--instance <instance>]
msl enter [-- <command>...]
msl up [--detach]
msl down
msl project status
msl project validate
msl list [--verbose]
msl [--distribution <instance>] [--user <linux-user>] [--cwd <linux-path>] [-- <command>...]
msl exec <instance> [--user <linux-user>] [--cwd <linux-path>] -- <command>...
msl start <instance>
msl stop <instance> [--force]
msl shutdown [<instance>]
msl status [<instance>]
msl set-default <instance>
msl config set <instance> <key> <value>
msl mount add <instance> <host-path> [--guest-path <path>] [--read-only]
msl mount remove <instance> <guest-path>
msl snapshot create <instance> <name>
msl snapshot list <instance>
msl snapshot restore <instance> <name>
msl export <instance> --output <archive.tar.zst>
msl import <archive.tar.zst> --name <instance>
msl uninstall <instance> [--purge]
msl update [--distro <distro>]
msl doctor
```

`msl` with no command opens an interactive login shell in the default instance. `msl <command> ...` is shorthand for executing that command in the default instance. `msl install ubuntu` creates an instance named `Ubuntu`; names are case-insensitive for lookup, unique under Unicode case folding, and are displayed in their original spelling.

`install` downloads an image, creates a sparse APFS-backed disk with a default maximum size of 64 GiB, initializes the guest, creates the requested Linux user (default: the invoking macOS short name), and sets that user as the interactive default. A command must never silently expand disk limits, change mounts, install guest packages, or expose a network listener.

All destructive operations display the resolved instance and affected storage path and require `--yes` when stdin is not a TTY. `uninstall` retains a recoverable instance archive for 30 days; `--purge` permanently removes it after an interactive confirmation.

### Project contract: `msl.toml`

`msl.toml` is the primary MSL differentiator. It is an optional, committed, repository-root manifest. Commands that operate on a project (`msl enter`, `msl up`, `msl down`, and `msl project …`) locate it by walking upward from the current directory, stopping at the repository root or filesystem root. An explicit `--project <path>` overrides discovery. A user-level override is stored in `.msl.local.toml`, is ignored by Git by `msl init`, and may override only resource limits and local host paths—not image identity, guest mounts, bootstrap commands, or exposed ports.

The manifest schema is versioned. v1 uses `schema = 1`; an unknown schema is an error. `msl project validate` validates the complete file before MSL creates or changes an instance. This is the full v1 schema:

```toml
schema = 1
name = "my-service"                         # DNS-label, 1–48 chars; becomes default instance name
distro = "ubuntu-24.04"                     # official, version-pinned distro identifier
diskSizeGiB = 32                             # 8–256
memoryMiB = 4096                             # 1024–32768
cpuCount = 4                                 # 1 through host logical CPU count

[workspace]
hostPath = "."                              # resolved from this file; must remain inside Git worktree
guestPath = "/workspace"                    # absolute, non-overlapping Linux path
mode = "rw"                                 # "rw" or "ro"

[[mount]]
hostPath = "../shared-fixtures"             # relative to this file or absolute after explicit consent
guestPath = "/opt/fixtures"
mode = "ro"

[bootstrap]
command = ["./.msl/bootstrap"]              # argv, executed as project user once per manifest digest
timeoutSeconds = 900                         # 1–3600

[[service]]
name = "web"                                # DNS-label, unique within the manifest
command = ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
cwd = "/workspace"
port = 3000                                  # TCP 1024–65535; host port equals guest port
healthcheck = ["curl", "--fail", "http://127.0.0.1:3000/health"]
healthcheckIntervalSeconds = 5               # 1–60
```

`msl init` writes this template only when `msl.toml` does not exist. `msl enter` creates or starts the named instance, mounts the workspace, performs bootstrap if its manifest digest has changed, changes to `workspace.guestPath`, and opens a shell (or executes its argv). `msl up` starts every declared service in a guest systemd scope, waits for each health check to pass for two consecutive probes, and creates its loopback port forwarding. `msl down` stops only services declared by the current manifest; it does not delete their instance or data.

MSL writes project runtime state outside the repository at `~/.local/state/msl/projects/<manifest-sha256>.json`. It records the instance UUID, the last successful bootstrap digest, service process IDs, and health status. No generated state, lockfile, credential, or machine-specific path is written into the working tree.

The bootstrap command runs with `MSL_PROJECT=1`, `MSL_WORKSPACE=/workspace`, and a minimal, documented environment. It never runs implicitly during `msl install` or `msl exec`. A changed bootstrap command, distro, or workspace mapping requires an explicit `msl enter --rebuild`; MSL prints the exact diff and requires confirmation because that action may change guest state.

### macOS handoff commands

The guest agent exposes host integration only through four fixed commands, installed in official images:

| Guest command | Host action | Safety rule |
| --- | --- | --- |
| `msl-open <url-or-path>` | Opens a validated `http`, `https`, or file URL with macOS Launch Services. | File targets must resolve inside an approved mount; other URL schemes are rejected. |
| `msl-copy` | Copies stdin to the macOS clipboard. | Text only; maximum 10 MiB; no clipboard reading in v1. |
| `msl-editor <path>[:line[:column]]` | Opens a mounted source file in the user’s configured host editor. | Canonical target must be inside an approved mount. |
| `msl-notify <title> <body>` | Displays a host notification. | Title/body capped at 120/500 UTF-8 characters; notifications are rate-limited to 10 per minute per instance. |

The daemon asks once for the user’s notification consent before forwarding `msl-notify`; all other commands use the user’s normal Launch Services/clipboard access and are logged as capability use without their payload. The guest cannot invoke arbitrary macOS binaries, AppleScript, shell commands, or read the host clipboard.

### Configuration

Global settings live at `~/.config/msl/config.toml`; per-instance settings live at `~/.config/msl/instances/<id>.toml`. User-owned configuration is never rewritten except by an explicit `msl config set`. Runtime state and disks are owned by the daemon under `/Library/Application Support/MSL/` and are not edited by users.

Supported per-instance keys are fixed in v1:

```toml
memoryMiB = 4096                 # 1024–32768; host default is min(4096, 25% RAM)
cpuCount = 4                     # 1 through host logical CPU count
idleShutdownMinutes = 15         # 0 disables automatic shutdown
defaultUser = "jessica"
networkMode = "nat"              # only "nat" in v1
systemd = true                   # always true for supported instances
```

Changing CPU or memory limits applies on the next start. Changing the default user applies to new interactive sessions immediately.

## 4. Architecture

MSL has five components:

1. **`msl` CLI** — validates arguments, presents progress, asks for consent, and communicates with the daemon over an authenticated local XPC service.
2. **Project controller** — a non-privileged library used by the CLI. It parses and validates `msl.toml`, resolves project paths, computes a canonical manifest digest, and turns project services into daemon requests. It has no direct VM or filesystem privileges.
3. **MSL service** — a LaunchDaemon privileged helper. It owns image verification, VM lifecycle, network setup, disk/snapshot operations, and host-side file sharing. It authorizes every request against the caller’s macOS audit token and instance ownership.
4. **VM runtime** — one lightweight Virtualization.framework VM per running instance. It has a Linux kernel, initramfs, virtio block disk, virtio network device, virtio socket device, and VirtioFS shares.
5. **Guest agent (`msl-agent`)** — a systemd service supplied in each official image. It provides guest lifecycle coordination, user-session execution over a virtio socket, controlled host integration, project service supervision, and health reporting. It does not accept TCP connections.

The daemon starts a VM only when a command targets it, a configured service requires it, or an explicit `start` command is issued. Multiple commands against the same instance share its running VM. An idle instance stops only after no interactive sessions, no active execution requests, and no configured persistent guest services remain.

The daemon communicates with `msl-agent` using a versioned, length-prefixed protobuf protocol over a virtio socket. Every RPC contains a request ID, caller UID, target Linux UID, working directory, environment allowlist, and deadline. The agent rejects malformed messages, maps only authorized users, and never treats host-provided strings as shell text. Commands are passed as argv arrays and executed with `execve`.

## 5. Guest operating system behavior

Each official image uses systemd as PID 1. `msl-agent.service` starts after local filesystems and the VirtioFS mounts are available. The image contains no shared default credentials and disables password SSH by default. The first boot creates the requested non-root user, grants passwordless `sudo` only for that user, and records completion in the instance disk.

The guest system clock uses the host time at startup and NTP thereafter. Locale and timezone default to the host’s current values at installation; they are normal Linux settings after that. `systemctl`, `apt`, cron/systemd timers, package services, and normal Linux process semantics must work inside the instance.

Root in the Linux guest is **not** macOS root. Guest root can modify its own virtual disk and guest configuration but cannot bypass macOS filesystem permissions, TCC, code-signing, or daemon authorization.

## 6. Filesystem and permission model

### Mount layout

Every instance has the following mounts:

| Guest path | Source | Access | Purpose |
| --- | --- | --- | --- |
| `/` | instance virtual disk | read/write | Linux OS, packages, guest data |
| `/mnt/mac` | user-approved macOS home directory | read/write | convenient host access |
| `/mnt/mac/Volumes/<name>` | explicitly approved mounted volume | configured | external/project volumes |
| `/mnt/wsl` | compatibility symlink to `/mnt/mac` | same as target | migration convenience only |

At first run, MSL requests macOS permission for the invoking user’s home directory and mounts that directory at `/mnt/mac`. It does not request Full Disk Access and must not claim access to Desktop, Documents, Downloads, iCloud Drive, removable media, network volumes, or another user’s home unless macOS grants the relevant permission and the user explicitly adds that path with `msl mount add`.

For an `msl.toml` workspace, MSL additionally mounts only the declared repository path at its declared guest path (normally `/workspace`). This workspace mount is independent of `/mnt/mac`, uses a distinct VirtioFS tag, and remains available if the user disables the broad home-directory mount. A project therefore works under a narrow folder grant; `msl doctor` recommends this mode whenever possible.

Paths are canonicalized with `realpath` on the host before a mount is accepted. The daemon rejects paths resolving outside the authorized selection, mounted paths whose source disappears, and a guest mount path that is `/`, overlaps an existing mount, or contains `..`. It retains an authorization-scoped security bookmark where macOS supports one, and reports a consent-needed error if that grant becomes stale.

VirtioFS preserves filenames and directory structure. Permissions on host-backed files are authoritative on the macOS side; Linux mode bits are best-effort metadata and must not be treated as a security control. Host timestamps, ACL behavior, xattrs, case sensitivity, and symlink resolution follow the source volume’s macOS semantics. The documentation and `msl doctor` must warn that Linux case-sensitive build assumptions may fail on a case-insensitive APFS volume. For strict Linux POSIX semantics, users must work in the guest disk (for example `~/src`) and copy or synchronize to `/mnt/mac`.

MSL must flush guest writes to the host share before reporting a successful `fsync`/close where the underlying framework supports it; otherwise it documents the exact weaker guarantee and uses conservative close/stop synchronization. A clean VM shutdown flushes all virtual disk and share operations before termination.

## 7. Networking and service access

Each VM uses Virtualization.framework NAT networking. It receives a private, non-stable IP address. Outbound guest networking works through the host’s active connection, including DNS resolution configured from the host at VM start. MSL provides two stable names:

- `host.msl.internal`: resolves in the guest to the NAT gateway/host endpoint.
- `<instance>.msl.internal`: resolves on the host to that running instance’s local forwarding endpoint when one exists.

Guest services bind normally inside Linux. They are not exposed on macOS merely by listening on a port. A user exposes a service using:

```text
msl config set <instance> forward.3000 3000
```

This creates a loopback-only host listener at `127.0.0.1:3000` and `[::1]:3000`, forwarding to guest TCP port 3000. Ports under 1024 are rejected. A host port can be mapped to a different guest port using `forward.<host-port>=<guest-port>`. The daemon refuses collisions and never binds `0.0.0.0`, a LAN address, or a Unix socket outside the MSL runtime directory in v1. A forwarding rule is persisted per instance and active only while its instance runs.

Inbound SSH is neither installed nor configured by MSL. Users who install it in the guest must create an explicit forwarding rule; it remains loopback-only by default.

For a declared project service, `msl up` owns the forwarding rule for the lifetime of that service. Its deterministic local URL is `http://<service>.<project>.msl.local:<port>` when the macOS resolver integration is available, with `http://127.0.0.1:<port>` as the universal fallback. Resolver integration must create names only under `.msl.local`, must never modify a user’s existing DNS configuration, and must be removed on service stop or uninstallation.

## 8. Isolation, privacy, and security requirements

- The VM has no direct access to host block devices, USB devices, cameras, microphones, clipboard, keychain, host process table, or host sockets.
- Only declared VirtioFS mounts cross the filesystem boundary.
- Only loopback forwarding rules cross the inbound network boundary.
- The guest agent is reachable only through its VM-local virtio socket; it has no network control plane.
- The service validates image signatures, SHA-256 digests, distro ID, architecture, and minimum agent protocol version before installation.
- The service, CLI, guest agent, kernel, and official manifests are versioned and signed. Updates are atomic and rollback to the last known-good runtime on failure.
- Instance ownership defaults to the installer’s macOS UID. Other local users cannot start, inspect, execute into, snapshot, export, or mount paths into that instance without an explicit ownership transfer command (not included in v1).
- Secrets supplied through stdin or the host environment are not logged. Logs redact absolute paths outside the user’s home, tokens, authorization headers, and environment values marked sensitive.
- Crash reports and telemetry are off by default. If optional telemetry is later introduced, it requires opt-in and excludes filenames, command arguments, and guest contents.

## 9. Storage, snapshots, backup, and recovery

Each instance has a stable UUID, a sparse virtual disk, metadata record, and append-only operation log. A snapshot is a crash-consistent copy-on-write disk checkpoint made only while the VM is paused; MSL pauses I/O, flushes the guest disk, captures metadata, and resumes the VM. Snapshots do not include host-mounted files, because those remain host-owned.

`export` shuts down the instance (or fails unless `--force` is supplied), packages the disk, metadata, distro/version manifest, and checksums into a `.tar.zst`, then verifies the archive. `import` verifies checksums and signature metadata, assigns a new instance UUID, and never overwrites an existing instance name. Export archives contain guest data and must be treated as sensitive backups.

After an unclean host shutdown, the daemon starts the VM normally and the guest filesystem performs its journal recovery. If the VM cannot boot twice consecutively, `msl doctor` offers non-destructive diagnostics and a read-only recovery boot; it must not automatically repair, discard, or recreate an instance.

## 10. Distribution lifecycle and updates

`msl update` updates manifests and the MSL runtime. It never runs `apt upgrade` automatically. Distribution package maintenance is performed normally inside the guest. A distro image update is used only for new installations unless the user explicitly creates a new instance or imports/migrates one.

An official image must contain an SBOM, a pinned kernel version, the guest agent, systemd integration, secure package repository configuration, and an automated first-boot test. Images are released only after boot, filesystem, network, forwarding, lifecycle, and upgrade tests pass on both supported host architectures where applicable.

## 11. Error handling and observability

Commands produce concise human-readable errors and `--json` structured output for automation. JSON errors contain `code`, `message`, `instance`, `operationId`, and `remediation` fields. Stable error codes include `INSTANCE_NOT_FOUND`, `INSTANCE_BUSY`, `CONSENT_REQUIRED`, `PORT_IN_USE`, `IMAGE_VERIFICATION_FAILED`, `INSUFFICIENT_DISK`, `GUEST_UNHEALTHY`, and `SERVICE_UNAVAILABLE`.

`msl status --verbose` shows VM state, guest health, disk limit and use, configured mounts, forwardings, runtime/agent versions, and last error—never command history or sensitive environment values. `msl doctor` tests daemon reachability, runtime signatures, macOS authorization, disk availability, stale file grants, image cache health, and guest-agent protocol compatibility.

`msl doctor --project` also checks the current project’s manifest against the host and guest. It must report, with the affected file/path/service and a repair command where possible: a case-collision in the workspace; a Linux executable bit that cannot be represented by the mounted host volume; an unapproved or stale mount; a declared port conflict; an unavailable bootstrap executable; an architecture mismatch; a failed DNS/VPN reachability probe; and a service whose health check has failed. It must not modify the project, instance, network, or permissions while diagnosing.

## 12. Implementation phases and acceptance criteria

### Phase 1: single-instance foundation

Deliver the daemon, Ubuntu install, persistent disk, systemd guest, interactive shell, non-interactive argv execution, NAT egress, `/mnt/mac` mounting, graceful shutdown, `status`/`doctor`, and the four fixed macOS handoff commands.

Acceptance: on a clean supported Mac, `msl install ubuntu`, `msl`, `sudo apt update`, creation of a file under `/mnt/mac`, VM restart, and `msl exec Ubuntu -- uname -a` all work without manual VM or SSH steps.

### Phase 2: multi-instance and safe integration

Deliver Debian, instance ownership, mounts, loopback port forwarding, default-instance selection, CPU/memory configuration, structured errors, and robust authorization revocation behavior.

Acceptance: two instances run concurrently; each sees only its own disk; a revoked host-folder permission fails safely; a forwarded guest HTTP service is reachable at `localhost` and unreachable from the LAN.

### Phase 3: project-native workflow

Deliver `msl.toml`, `msl init`, `msl enter`, `msl up`, `msl down`, per-project runtime state, service supervision, local project domains, manifest digesting, bootstrap confirmation, and read-only project diagnostics.

Acceptance: cloning a repository containing a valid `msl.toml` and running `msl enter` produces the declared distro, workspace path, and bootstrap state without manual VM configuration. `msl up` starts every declared service, passes health checks, makes it reachable only from the Mac’s loopback interface, and `msl down` leaves no service or forwarding rule behind. A second user’s local overrides do not change the committed contract.

### Phase 4: data lifecycle and release hardening

Deliver snapshots, export/import, uninstall retention, signed runtime/image updates, recovery diagnostics, audit logging, performance/regression suite, and installer/uninstaller.

Acceptance: snapshot restore returns guest-disk state exactly; export/import produces a bootable copy with a new UUID; interrupted updates roll back; all release artifacts verify before use.

## 13. Definition of done for v1

MSL v1 is complete only when all supported distributions satisfy the acceptance criteria above; a checked-in `msl.toml` is reproducible on a clean supported Mac; cold install, warm shell launch, project entry, service startup, shutdown, and export/import have documented and tested performance budgets; no privileged daemon request can be performed by a non-owner; permissions are denied by default; and the release installer, uninstaller, signing, upgrade, backup, and recovery paths have automated tests on clean machines.

Any behavior not specified here is intentionally unsupported in v1 and must fail explicitly rather than silently approximating WSL behavior.
