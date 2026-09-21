# MSL — Mac Subsystem for Linux

## Purpose

MSL is a Linux subsystem for macOS. Its goal is to make a complete Linux development environment feel like a natural part of a Mac: install a distribution with one command, open a Linux shell immediately, work on normal Mac projects, and run Linux services without manually configuring a virtual machine, SSH, IP addresses, shared folders, or port forwarding.

MSL takes inspiration from the ease of use of WSL 2, while being designed around macOS, Apple hardware, and macOS privacy controls. It runs a real Linux kernel and persistent Linux distributions in lightweight managed virtual machines; it is not a Linux syscall translation layer, an emulator, or a Docker replacement.

## The experience MSL should provide

From a developer’s perspective, the common workflow should be simple:

```text
msl install ubuntu
msl
```

That should install a verified Linux distribution, create a normal Linux user, start the subsystem, and open an interactive shell. Linux tools such as `apt`, `systemctl`, language runtimes, compilers, package managers, and background services should behave as they do on a normal Linux machine.

A developer should be able to open a Mac repository in MSL, edit it with their usual macOS editor, run the Linux toolchain against it, and open a locally running service in a Mac browser. The subsystem should preserve Linux state, packages, configuration, and data across shell sessions and Mac reboots.

## Product principles

### Linux should be real

Each installed distribution is a persistent Linux userspace with its own Linux kernel, disk, process model, networking, and system services. Systemd, standard package management, cron/timers, and conventional Linux process behavior are first-class requirements.

Linux root is powerful inside its own subsystem but is not macOS root. It must not bypass macOS filesystem permissions, privacy protections, code-signing rules, or user authorization.

### macOS integration should feel local

MSL should make the host–guest boundary convenient without hiding it. A user can work with approved macOS folders from Linux, reach host services from the guest, and access explicitly exposed guest services from the Mac. Paths, service URLs, editor handoffs, and command-line behavior should be stable and predictable.

The guest should have a fixed path for its approved Mac files, and project workspaces should be mountable at a stable Linux path such as `/workspace`. Guest services should be reachable from the Mac through loopback-only local addresses by default, never unexpectedly exposed to the network.

### Integration must be permissioned and understandable

MSL’s defining quality is not unrestricted passthrough; it is **intentional passthrough**. The user sees and controls every macOS folder, volume, network listener, and host integration capability made available to a Linux instance. Grants are narrow, revocable, and attributable to the instance that uses them.

MSL must not require Full Disk Access for normal development. It must not silently expose host devices, the keychain, the clipboard, arbitrary host commands, other users’ files, or network ports. Any convenience feature that crosses the host–guest boundary must have an explicit scope and a safe default.

### Projects should be reproducible

MSL should be more than a VM launcher. A repository should be able to describe the Linux environment it needs in a committed `msl.toml` file: distribution, workspace mount, resource needs, bootstrap work, services, ports, and health checks.

With that file, a new contributor should be able to clone a project and enter its ready-to-use Linux environment through one MSL command. Local, machine-specific choices belong in an ignored override file and must not alter the shared project contract. Project configuration should be validated before it changes an instance, and any action that can rebuild or mutate an environment must be clear to the user.

## Key capabilities

### Distribution lifecycle

MSL installs verified, architecture-compatible Linux distributions by name. A distribution instance has a human-readable name, a persistent virtual disk, a designated Linux user, resource limits, lifecycle controls, and a clear status view. Users can start, stop, list, inspect, export, import, snapshot, restore, and remove instances without interacting with VM internals.

Distributions, guest agents, kernels, and manifests must be authenticated and integrity-checked. Updates must be safe and recoverable. MSL must never silently discard guest data, expand disk limits, replace a distribution, or upgrade guest packages.

### Files and permissions

The Linux guest filesystem is its own environment for OS files, packages, caches, and data requiring full Linux semantics. Approved macOS folders are shared through a high-performance filesystem interface, preserving host ownership and privacy rules.

MSL should clearly explain the semantic differences between a Mac volume and a native Linux filesystem—especially case sensitivity, ACLs, extended attributes, symlinks, and executable permissions. It should diagnose common cross-platform problems and recommend the guest disk when a project requires strict Linux POSIX behavior.

### Networking and services

Linux instances need ordinary outbound networking and reliable DNS. They also need a stable way to reach services running on the Mac. Conversely, a guest service should be easy to open from the Mac while staying private by default.

MSL manages explicit guest-to-host port forwarding and binds those forwarded ports only to the Mac loopback interface unless the user intentionally opts into a broader exposure model. Project services can declare their port and health check; MSL starts, supervises, reports on, and stops those services as a coherent project environment.

### Host handoff

Some Linux commands should be able to ask the Mac to perform narrowly defined, useful actions: open an approved file or web URL, navigate the configured editor to a mounted file, copy text to the host clipboard, or display a rate-limited notification. These are MSL capabilities, not a general remote-shell channel into macOS. The Linux guest cannot run arbitrary host binaries or read host secrets through this mechanism.

### Diagnostics

MSL should make the hard boundary cases legible. Its diagnostics check virtualization availability, resource pressure, image integrity, stale permissions, workspace mount behavior, case collisions, executable-bit limitations, port conflicts, DNS/VPN reachability, architecture compatibility, and guest service health. Diagnostics are read-only unless the user expressly asks MSL to repair a specific problem.

## Architecture direction

MSL is a macOS-native service with an unprivileged command-line client. The service owns virtual-machine lifecycle, image verification, persistent disks, networking, host-side sharing, and authorization. The CLI communicates with it through an authenticated local interface and acts only on behalf of the calling macOS user.

Each Linux instance runs in a Virtualization.framework virtual machine with a Linux kernel, virtual block device, virtual network interface, virtio socket, and VirtioFS shares. A small guest agent coordinates instance lifecycle, commands, project services, health reporting, and the deliberately limited host-handoff features. Its control plane is VM-local and is never exposed as a network service.

The project configuration layer parses `msl.toml`, validates the declared environment, resolves paths, and translates project services into controlled lifecycle requests. It does not receive general filesystem or VM privileges.

## Security and privacy model

- Instances are owned by the macOS user who creates them; other local users cannot access them by default.
- The guest can see only its virtual disk and explicitly authorized shared folders.
- Guest services are inaccessible from the LAN unless a user explicitly changes that policy.
- Secrets, command arguments, and shared-file contents are not included in telemetry or routine logs.
- Telemetry is opt-in; crash and usage reporting must exclude project content and personal file paths.
- Destructive operations identify their target and require confirmation when appropriate.
- Exports and snapshots are treated as sensitive data because they can contain the complete guest filesystem.

## What MSL is not trying to be

MSL does not aim to replace every form of virtualization, containers, or remote development. It is not a graphical Linux desktop product, a cloud orchestrator, a Kubernetes manager, or a mechanism for bypassing macOS security. It does not promise byte-for-byte compatibility with WSL configuration or Windows behavior.

Its focus is narrower and more deliberate: the best possible command-line Linux subsystem experience for developers who use macOS as their primary desktop.

## Success criteria

MSL succeeds when a Mac developer can trust it as the default place to run Linux tooling:

- A distribution can be installed and used without VM administration.
- A Linux project can be described, shared, and recreated with a small committed manifest.
- Mac files and Linux files have clear, safe, performant interoperability.
- Local Linux services are effortless to run and safe to expose only to the developer’s Mac.
- The system is secure by default, transparent about its permissions, and predictable when something cannot work.
- Advanced capabilities—snapshots, exports, multiple distributions, service supervision, and host handoff—remain as simple and composable as the first shell command.
