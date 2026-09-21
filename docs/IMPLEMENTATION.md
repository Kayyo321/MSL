# MSL implementation specification

This is the binding technical design for MSL. It turns the product intent in
[PROJECT.md](../PROJECT.md) into explicit engineering decisions. A change to
this document must update the workflow and verification documents in the same
change.

## 1. Scope and fixed decisions

Version 1 supports Apple-silicon Macs on macOS 14 or later and arm64 Linux
guests only. MSL is a per-user application, not a privileged daemon. It has no
root helper, requires no Full Disk Access, and owns no global system setting.
It uses Virtualization.framework for persistent Linux virtual machines.

The following are deliberately out of scope for version 1: Intel hosts,
graphical guests, USB passthrough, nested virtualization, LAN-published guest
services, arbitrary host-shell execution, Keychain access, clipboard reads, and
unrestricted host filesystem access.

Implementation uses Swift 5.10 or later, organized as follows:

| Product | Runs as | Responsibility |
| --- | --- | --- |
| msl | Calling macOS user | CLI parsing, project parsing, output, and authenticated service requests. |
| msld | Same user through LaunchAgent | Owns all VM, disk, image, mount, network-listener, and state mutations. |
| msl-guest-agent | Root inside guest | VM-local control protocol, shell attachment, and project-service control. |
| MSLCore | Shared library | Domain types, manifest schema, validation, error model, and serialization. |
| mslctl | Test builds only | Fixture and fault injection interface; it is never installed for users. |

The command-line client does not write instance data directly. It connects to
the user's service. Other local macOS accounts cannot manage an instance because
they cannot connect to that user's launchd service or read that user's state.

## 2. Persistent state and recovery

All MSL directories are mode 0700 and ordinary state files are mode 0600.

    ~/Library/Application Support/MSL/
      state.sqlite3
      images/cache/<sha256>/
      instances/<instance-uuid>/
        config.json
        disk.img
        nvram.bin
        runtime/
        logs/
        snapshots/<snapshot-uuid>/
      exports/<export-uuid>.mslpack
      locks/

Instance, snapshot, and export identifiers are lower-case UUIDs. Human-readable
instance names are never path components. The daemon resolves a name to exactly
one UUID in a database transaction before opening a file. This prevents path
traversal, normalization, and rename races.

SQLite is the authoritative store. It uses WAL mode, foreign keys, and
synchronous=FULL. Schema migrations are versioned, transactional, and tested
against every supported previous schema. The minimum tables are:

| Table | Mandatory columns | Invariant |
| --- | --- | --- |
| instances | id, name, distribution, release, architecture, linux_user, limits, state, timestamps | Unicode-normalized, case-insensitive name is unique. |
| folder_grants | id, instance_id, bookmark, host_display_path, guest_path, mode, revoked_at | One active guest path per instance. |
| port_grants | id, instance_id, guest_port, host_port, protocol, bind_policy, revoked_at | One active host protocol/port/bind tuple. |
| images | digest, distribution, release, architecture, manifest, verified_at | Usable only after signature and digest validation. |
| operations | id, instance_id, kind, state, timestamps, error_code, recovery_json | One mutation runs per instance. |
| snapshots | id, instance_id, name, manifest, storage_locator, created_at | Captures only a stopped consistent disk. |

An instance state is exactly one of stopped, starting, running, stopping, error,
or repair_required. Every operation journals intent before it modifies a disk,
database, mount, or listener. On daemon restart, incomplete journals are
completed idempotently when safe; otherwise the instance becomes repair_required.
An interrupted operation is never reported as success.

## 3. Control-plane security

The CLI connects only to a Unix socket under the MSL runtime directory. That
directory is 0700 and the socket is 0600. The daemon reads peer credentials and
rejects any UID other than its owner. Each request also carries a service-issued
256-bit session token held in a 0600 runtime file and rotated on daemon restart.

The protocol is length-prefixed JSON, limited to 1 MiB per message. Requests
contain request_id, method, parameters, and client_version. Responses repeat
request_id and carry either result or code, message, and details. Invalid JSON,
unknown methods, duplicate request IDs on one connection, oversize messages, and
incompatible protocol major versions are rejected without changing state.

The guest agent is reachable exclusively via a virtio socket. It never listens
on a guest TCP or UDP control port. Every boot generates a new 256-bit secret
that is delivered through read-only VM configuration; the agent must present it
during the initial handshake. The secret is discarded when the VM stops.

The guest agent exposes only status, exec_shell, service_apply, service_stop,
service_status, health_check, and shutdown. exec_shell attaches an interactive
terminal; it is not a generic remote command execution endpoint.

Guest-to-host effects are named capabilities, never a host command:

| Capability | Input rule | Host effect |
| --- | --- | --- |
| open_url | Absolute http or https URL, maximum 2 KiB | Opens default browser. |
| open_file | Canonical guest path inside an active share | Opens its approved host equivalent. |
| open_editor | Approved shared file and positive line/column | Opens configured editor or reports unavailable. |
| copy_text | UTF-8 at most 1 MiB | Replaces host clipboard contents. |
| notify | Title <=120 chars, body <=500 chars, five/minute/instance | Displays notification. |

There is no run capability, host shell, Keychain, clipboard-read, device, or
arbitrary-path capability. File handoff resolves an actual mount entry and its
security-scoped bookmark. It must not construct a host path by concatenating
strings.

## 4. VM and image construction

Each instance has one Virtualization.framework VM containing an
architecture-matched verified Linux kernel/initramfs, one writable sparse root
disk, a NAT virtio NIC, virtio control socket, virtio console, and a VirtioFS
device for every active folder grant. VirtioFS tags are opaque grant UUIDs, not
user input. No unrequested virtual devices are attached.

First boot receives signed seed data that creates the designated non-root Linux
user, installs/enables the guest agent, and creates mount points. Usernames must
match the regular expression ^[a-z_][a-z0-9_-]{0,30}$; root, daemon, nobody, and
systemd-* accounts are forbidden. CLI arguments never carry an initial password.
No macOS credential, bookmark, session secret, or host secret is written into
the guest disk.

The root disk has an explicit logical maximum. Creation fails unless host free
space covers the initial allocation plus 10 GiB. Only the explicit resize command
can increase the limit, after displaying old and new values and receiving
confirmation. Shrinking and automatic expansion are not implemented. CPU and
memory changes take effect only on the next cold start.

The built-in distribution catalog is signed JSON. An entry includes distribution,
release, architecture, URLs, declared byte size, SHA-256 digests, kernel digest,
guest-agent compatibility range, and signature. The trusted public key is
compiled into the daemon; a replacement key needs a rotation record signed by
the trusted key.

Install follows this exact order:

1. Validate distribution and release against the catalog. Arbitrary URLs and
   local images are rejected.
2. Select a non-revoked arm64 image.
3. Download to a unique temporary cache file while enforcing declared size.
4. Verify catalog signature and SHA-256 before a content-addressed rename.
5. Create disk and database records through one recoverable operation.
6. Perform first boot and require authenticated guest-agent readiness.
7. Stop cleanly and mark installation successful only after readiness.

A digest, signature, architecture, or first-boot failure produces no usable
instance. Interrupted downloads are discarded during recovery. Cached artifacts
are rehashed before use when older than 30 days or when their filesystem metadata
changed.

## 5. Files and permissions

A shared macOS folder is an explicit per-instance security-scoped bookmark.
Interactive share creation uses the native directory picker. A typed path is
accepted only if the CLI already holds macOS access to it. Each grant contains
one canonical host directory, one absolute guest path, and read-only or
read-write access.

Guest paths must be below /mnt/mac; /workspace is reserved exclusively for a
project workspace. The daemon rejects root, whole home directories, Library,
system directories, duplicate paths, nested grants, unnormalized paths, and
manual /workspace grants. The guest mount table records only opaque grant IDs,
guest paths, and modes: it contains no host paths.

Mount changes are pending while a VM runs and apply at its next start. MSL never
hot-plugs VirtioFS. Removing a grant first stops any project services located
there, detaches on the next stop, then revokes the bookmark. It never removes
host files or guest-disk copies.

MSL documents, detects, and does not hide Mac-share differences in case
sensitivity, ACLs, extended attributes, symlinks, and executable permissions.
Projects requiring strict Linux semantics belong on the guest disk.

## 6. Networking and port policy

Guests receive ordinary outbound NAT networking. MSL supplies the stable hostname
host.msl.internal for services on the Mac host. Its numeric NAT-gateway address
is an internal detail and never a supported interface.

MSL owns every exposed-port listener. Version 1 supports TCP ports 1024 through
65535 only. A listener binds exactly 127.0.0.1:<port> and, when applicable,
[::1]:<port>. It may not bind 0.0.0.0, ::, a LAN address, or a privileged port.
A host port of zero allocates and persists a free port in 49152 through 65535.
Any bind conflict fails; MSL does not silently select a different port. Removing
a port grant closes the host listener immediately but does not stop the guest
service.

## 7. Project configuration

The committed contract is <repository>/msl.toml. The adjacent local override is
msl.local.toml. An override is loaded only when that exact file is ignored by
Git, or Git is unavailable and the caller explicitly supplies
--allow-local-config. Unknown configuration keys are errors. Relative paths are
resolved from the manifest directory before a daemon request.

    schema = 1
    distribution = "ubuntu"
    release = "24.04"
    workspace = "."

    [resources]
    cpus = 4
    memory_mib = 4096
    disk_gib = 40

    [bootstrap]
    command = "./.msl/bootstrap.sh"
    timeout_seconds = 900

    [[service]]
    name = "web"
    command = "npm run dev -- --host 0.0.0.0"
    working_directory = "."
    port = 3000
    host_port = 0
    health = "http://127.0.0.1:3000/health"
    health_timeout_seconds = 60

schema, distribution, release, workspace, and every service field above are
required except host_port (default 0) and health_timeout_seconds (default 60).
Resources default to 2 CPU, 2048 MiB, and 30 GiB. CPU is 1 through host logical
CPU count; memory is 1024 MiB through host-available-minus-1024 MiB in 256 MiB
increments; disk is 10 through 1024 GiB. Names match
^[a-z][a-z0-9-]{0,31}$. Working directories must stay within workspace. Health
URLs are HTTP(S), target localhost or 127.0.0.1, and use that service's port.
Absent health means a TCP connection to that port.

The local override may alter only resource values, service host_port, and service
health_timeout_seconds. It matches services by name and cannot add a service or
change image, workspace, commands, guest port, or health endpoint.

Validation has two phases. Phase one parses and schema-validates with no I/O.
Phase two resolves workspace authorization, resources, image availability, and
port availability. Neither phase mutates state; project validate runs both.
project up prompts before a new workspace grant or resource change, then
reconciles exactly one instance. Bootstrap runs as the Linux user in /workspace
when effective manifest, override, image digest, or workspace bookmark hash
changes. It has no injected host secrets. On failure, services started by that
invocation stop and the VM/workspace remain inspectable.

Services are systemd transient units named
msl-project-<project-id>-<service>.service. Health is sampled once per second
until timeout. HTTP health requires 2xx or 3xx; TCP health requires a connection.

## 8. CLI, data safety, and logging

Supported command families are install; shell; instance list/inspect/start/stop/
remove/resize; share list/add/remove; port list/add/remove; project
validate/up/down/status/logs/shell; snapshot create/list/restore/delete; export;
import; and doctor.

Exit codes are fixed: 0 success, 2 invalid input or manifest, 3 missing/stale
permission, 4 unavailable host capability, 5 resource/port conflict, 6 integrity
failure, 7 failed guest action, and 1 all other internal failure. JSON output is
selected by --json, emits one result object, and never prompts. With no manifest,
shell chooses the only installed instance; if multiple exist it fails and lists
them rather than using recency.

Remove, snapshot restore/delete, and deleting repairs display exact target
name/UUID and require typing the target in a terminal or --yes noninteractively.
Exports refuse to overwrite without --overwrite. Imports never overwrite an
instance name. Snapshots require stopped VMs. Restore creates a pre-restore
snapshot, then atomically replaces the disk. An interrupted restore yields
repair_required; a partial disk is never booted. Export contains disk,
configuration, and signed manifest but excludes host grants, forwards, active
secrets, and logs unless logs are explicitly requested. Import assigns a new UUID
and restores no host grants or forwards.

Logs are newline-delimited JSON with timestamp, component, severity, event code,
operation ID, instance UUID, and a redacted message. They contain no bookmark
data, secrets, tokens, command arguments, environment values, clipboard data,
shared-file contents, or full project paths. Console output is potentially
sensitive, local only, limited to 50 MiB across current plus ten rotated files,
and opt-in for export.

doctor is read-only by default. It checks virtualization, architecture, storage,
images, grants, mounts, ports, network, and services. A repair accepts exactly
one previously failed named check, explains its action, and never deletes a disk,
snapshot, export, or database automatically.

