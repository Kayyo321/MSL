# Implementation status

## Stage 1 — MSLCore foundation

Implemented and unit-tested:

- Debian 12 arm64-only guest target validation.
- Instance and Linux-user identifier validation.
- Version 1 project-manifest domain model and deterministic, non-mutating validation.
- Restricted `msl.local.toml` merge model: resource overrides and named-service host-port/health-timeout overrides only.
- Fixed v1 exit-code taxonomy.
- Versioned Codable CLI/daemon and guest-agent IPC envelopes.

Verification command:

```text
swift test
```

The initial evidence was produced with Swift 6.4 on Debian 13 x86_64 WSL. These
are platform-neutral unit tests; they do not qualify the required macOS host or
a native Debian 12 arm64 guest.

## Not implemented

The user-facing CLI, launchd daemon, guest agent, SQLite state/recovery, signed
image cache, Virtualization.framework VM, VirtioFS, NAT/forwarding, project
lifecycle, snapshots/transfers, diagnostics, and release verification are still
pending their tracker stages. V1 must not be represented as releasable until the
release gates in the binding tracker have passed on supported Apple-silicon macOS
hardware.
