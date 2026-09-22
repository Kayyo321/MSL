# MSL workflow specification

This document is the precise user-facing behavior of MSL. It describes what a
developer sees, what state changes, and what MSL does when that operation cannot
safely continue. The corresponding implementation contract is
[Implementations/initial-debian-subsystem-implementation-tracker.md](Implementations/initial-debian-subsystem-implementation-tracker.md), which tracks implementation
state for the complete v1 design. V1 supports Debian 12 arm64 only.

This document records the complete v1 workflow contract. The current implementation
status is tracked in the implementation tracker; Stage 1 currently contains only
platform-neutral `MSLCore` validation and IPC types, so none of the workflows
below are available to users yet.

## Conventions

<instance> is an installed instance name. <project> is the directory containing
msl.toml. <service> is a service name in that file. Commands run as the macOS
account that owns the MSL service.

Before a mutating command, MSL takes the target instance operation lock. If it is
held, the second command exits 5, identifies the operation and start time, and
changes nothing. Read-only commands may proceed and report operation_in_progress.

Prompts appear only when both standard input and standard output are terminals.
--yes bypasses an already-authorized confirmation but never chooses a directory
or grants macOS folder access. --json is noninteractive: it returns one JSON
object, sends no prompts/progress to standard output, and cannot infer a choice.

## 1. Install and first shell

The normal first-use sequence is:

    msl install debian --release 12 --name debian-dev --user dev
    msl shell debian-dev

install first validates macOS support, host architecture, free storage, and the
signed catalog. It displays the exact release, image digest prefix, initial disk
size, default CPU/memory, Linux username, and instance name. In an interactive
terminal the user confirms that instance name. Download progress reports received
and declared bytes; MSL does not call an image trusted until signature and digest
both pass.

The first automated boot creates the Linux user and guest agent, then stops the
VM cleanly. Completion prints the exact next shell command. Install does not
open a shell, mount any Mac folder, forward a port, install optional packages, or
change host networking.

If the first boot cannot authenticate the guest agent before its timeout, install
exits 7 and leaves the instance repair_required with disk and console log
preserved. A retry using that name refuses to overwrite it. The user must inspect
or repair the instance, or explicitly remove it.

`msl shell` chooses an explicit instance name first. Otherwise it uses the
instance selected by the nearest ancestor `msl.toml`. If there is no manifest,
it uses the only installed instance. With two or more candidates it exits with
`instance_selection_required` and lists names; it never uses a last-used
instance.

A shell starts a stopped VM, waits for guest-agent readiness, and attaches a
login shell for the designated Linux user. Exiting the shell does not erase guest
state. The VM stops after five idle minutes only when it has no shell, no project
service, and no pending operation. A new shell within that period reuses the VM.
The current Mac directory is not implicitly mounted or copied.

## 2. Instance lifecycle and resources

    msl instance list
    msl instance inspect debian-dev
    msl instance start debian-dev
    msl instance stop debian-dev

list displays name, distribution/release, Linux user, state, configured resource
limits, and active project services. inspect also displays UUID, image digest
prefix, disk consumption and logical limit, shares, loopback forwards, latest
operation, and actionable error. It never exposes bookmark bytes or secrets.

start on a running instance succeeds with already_running=true. stop on a stopped
instance succeeds with already_stopped=true. A normal stop requests project
service shutdown and guest shutdown, waiting up to 60 seconds. If the guest does
not stop, MSL powers it off and explicitly records clean=false; its next start
runs a guest filesystem check before offering a shell.

    msl instance resize debian-dev --disk 60

This works only while stopped. It prints the old and new disk ceilings and asks
for the exact instance name. It only increases the logical ceiling. It never
shrinks, automatically grows, or changes CPU/memory because the host is busy.

    msl instance remove debian-dev

Remove displays the name, UUID, disk size, snapshot count, and warning that
exports are separate sensitive data. It requires the user to type debian-dev.
MSL stops the VM, revokes shares and forwarding, moves the instance directory to
Trash when available, then deletes its database rows transactionally. It never
deletes the shared image cache. If Trash is unavailable it refuses removal unless
--permanent --yes is supplied; permanent removal is stated in the result.

## 3. Explicit folder permissions

Before a grant, the guest sees only its own virtual disk.

    msl share add debian-dev /mnt/mac/source --guest-path /mnt/mac/source
    msl share add debian-dev /mnt/mac/reference --guest-path /mnt/mac/reference --read-only

Interactive add opens the native directory picker. The supplied guest path is
where the selected folder appears inside Linux. MSL shows selected host folder,
guest path, and access mode before confirmation. A typed path may be used only
when macOS has already allowed the CLI to read it; typing a path does not create
permission.

The guest path is absolute, normalized, begins /mnt/mac/, and contains no dot or
dot-dot segments. MSL rejects root, a whole home directory, Library, system
paths, duplicates, nested shares, and /workspace. /workspace belongs to a
project workflow only.

New/removal share configuration is pending until the next VM start. A running
VM is not changed in place. share list labels each grant active, pending-add,
pending-remove, or permission-stale. Removing a share identifies exact host and
guest paths, requires confirmation, and revokes access after safe detach. It
does not delete the source folder or guest copies.

A Mac share is not promised to behave identically to an ext4 guest disk. Projects
requiring Linux case sensitivity, ACLs, xattrs, symlinks, or executable-bit
semantics should live under the Linux home directory; doctor explains detected
cross-filesystem problems.

## 4. Local services and host access

Guest services are private until exposed:

    msl port add debian-dev 3000 --host-port 3000

This forwards only TCP from http://127.0.0.1:3000 on the Mac to port 3000 in that
one guest. Forwards bind loopback only. MSL never opens a LAN listener, changes
the firewall, or accepts UDP. The guest service must listen on a reachable guest
interface, normally 0.0.0.0; guest loopback-only services cannot be forwarded.

Omitting --host-port allocates an available persistent high port:

    msl port add debian-dev 3000
    # MSL prints: http://127.0.0.1:51873

The shown URL is authoritative. If an explicit port is occupied, MSL exits 5
rather than guessing another. port list displays guest port, host port, protocol,
listener state, and local URL. port remove closes only the Mac listener and leaves
the guest process alone.

A guest reaches host services through host.msl.internal, for example:

    curl http://host.msl.internal:8080

The hostname is stable. No numeric NAT address is part of the interface.

## 5. Project workflow

A committed project manifest looks like this:

    schema = 1
    distribution = "debian"
    release = "12"
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

The developer runs:

    cd <project>
    msl project validate
    msl project up
    msl project status
    msl project logs web
    msl project down

validate checks syntax, schema, workspace containment, host resources, catalog
availability, and port availability. It reports all independent failures and
changes nothing: it does not create a VM, download an image, run a bootstrap,
or open a listener.

On first up, MSL installs/selects the declared image, creates/reconciles the
project instance, then opens a native picker for exactly the resolved workspace
directory. It mounts it at /workspace only after the user approves. MSL applies
resources, executes bootstrap, starts services, waits for health, and prints
each loopback URL.

Bootstrap runs as the designated Linux user in /workspace with MSL_PROJECT=1.
No host secrets are supplied. It runs once whenever the effective manifest,
local override, selected image, or workspace bookmark changes. Its output is
streamed and retained in instance logs. Failure or timeout stops services
created by that invocation, preserves VM/workspace for debugging, exits 7, and
does not retry automatically. `--force-bootstrap` is not a v1 option.

Each service runs as a systemd transient unit. Its working directory is
/workspace plus working_directory. A service that exits before health passes
makes up fail. Health runs once each second until timeout. HTTP success is 2xx
or 3xx; TCP success is a connection. A service that later fails health is shown
as unhealthy; MSL does not invent a restart policy.

down stops only services and forwards declared by that effective project. It
does not stop the entire VM, remove Linux packages, revoke the workspace, or
erase data. project shell opens a normal shell in /workspace. logs with a service
tails that service; logs without one interleaves all declared service output by
timestamp.

### Local override behavior

Machine-specific values belong in ignored msl.local.toml, for example:

    [resources]
    memory_mib = 8192

    [[service]]
    name = "web"
    host_port = 3001

MSL refuses a local override not ignored by Git. It permits only resource values,
a named service host_port, and health_timeout_seconds. It cannot change
distribution, release, workspace, commands, guest ports, health endpoint, or
add/remove services. This preserves the committed environment contract.

## 6. Snapshots, exports, imports

Snapshots are local restore points and require a stopped VM:

    msl instance stop debian-dev
    msl snapshot create debian-dev before-upgrade
    msl snapshot restore debian-dev before-upgrade

Restore says it will replace the current disk, first creates an automatic
pre-restore snapshot, and requires typing the selected snapshot name. It restores
disk and generated VM configuration; it does not restore macOS authorizations or
expose new ports. Snapshot deletion requires the snapshot name and prefers Trash.

An export is the portable backup format:

    msl export debian-dev --output ~/Backups/debian-dev.mslpack
    msl import ~/Backups/debian-dev.mslpack --name debian-restored

Export requires stop and refuses to overwrite an existing output without
--overwrite. Treat the archive like a disk backup: it can contain guest secrets.
Import verifies integrity, assigns a new UUID, and restores no Mac-folder
bookmarks or port forwards. The imported VM is isolated until its owner grants
folders and publishes ports explicitly.

## 7. Host handoff

A Linux tool can ask MSL to open an approved mounted file or web URL, open an
approved file in the configured editor, copy supplied text to the host clipboard,
or show a rate-limited notification. Those are discrete capabilities, not a
remote shell. The guest cannot read the clipboard, run a macOS binary, access
Keychain, select a host file, or use a path outside an active share.

A denial identifies its narrow reason: no matching share, invalid/escaping path,
unavailable editor, stale macOS permission, invalid URL, oversized payload, or
notification rate limit. It never retries with broader access.

## 8. Doctor and expected failure handling

    msl doctor
    msl doctor repair debian-dev grants

doctor is read-only. It checks virtualization, architecture, storage/database,
images, grants, mounts, ports, network, and services. Each result is pass, warn,
or fail and includes evidence plus one next action.

A repair acts on exactly one named failed check. Repair grants reopens folder
selection only for stale folders. Repair images redownloads only invalid artifacts
after confirmation. Repair mounts requires safe stop/start. Repair ports recreates
only MSL-owned loopback listeners. No repair silently deletes a guest disk,
snapshot, export, database, or package state.

| Condition | Exact result | Safe next step |
| --- | --- | --- |
| Unsupported Mac/OS | Exit 4 before mutation. | Use a supported Apple-silicon Mac on macOS 14+. |
| Invalid image | Exit 6; partial image unusable. | Resolve catalog/network issue; do not bypass validation. |
| Revoked share | Mount absent and grant marked permission-stale. | `msl doctor repair <instance> grants` and reselect folder. |
| Occupied host port | Exit 5; no alternate is selected. | Stop owner or choose explicit/allocated port. |
| Bootstrap/service failure | New services stop; VM and files remain. | Read project logs, fix project, rerun up. |
| Host reboot/sleep | Guest stops; persistent disk remains. | Run shell or project up again. |
| Guest disk full | Guest operation fails normally. | Free data or explicitly resize while stopped. |

No workflow in this document grants Full Disk Access, bypasses macOS privacy,
opens a guest to the LAN, reads host secrets, or upgrades guest packages
implicitly.
