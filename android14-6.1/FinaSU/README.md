# FinaSU Variant

LKM-based root variant built from [LyraVoid/FinaSU](https://github.com/LyraVoid/FinaSU).

## Directory Layout

```
FinaSU/
├── patches/              # Variant safety patches (placeholder)
│   └── .gitkeep          # Placeholder — FinaSU is LKM-based, no GKI patches
└── (no source checked in) # Built via separate docker DDK + cargo-ndk pipeline
```

## Build Behavior

- **Source**: `LyraVoid/FinaSU` at the commit pinned in `finasu-pin.txt`
- **Build model**: LKM (loadable kernel module) — NOT compiled into the GKI boot image
- **Skip GKI build**: Yes — FinaSU uses a separate docker/cargo-ndk pipeline
- **KPM**: Not supported in GKI builder
- **SUSFS**: Built into FinaSU kernel module source

## Features

FinaSU provides:

| Feature | Description |
|---|---|
| Kernel-based su | Whitelist-based root access management |
| Module system | Overlayfs + metamodules (Magisk-like) |
| App Profile | Per-app root confinement |
| FolkZygisk | Built-in Zygisk engine |
| Sui extension | Built-in Shizuku API backend |
| SUSFS | Capability-gated root hiding |
| Kernel-level hiding | Mount hiding, SELinux hiding, AVC log spoofing, unmount policy |
| NoMount | VFS redirection backend (no mount table pollution) |
| .fpt themes | Configurable theming with online theme store |

## Installation

FinaSU is NOT built by the GKI builder. Use the FinaSU LKM pipeline (docker DDK + cargo-ndk) to build `kernelsu.ko`, then install via the FinaSU manager.

## Manager

Install the official **FinaSU manager** APK from the [FinaSU Releases](https://github.com/LyraVoid/FinaSU/releases) page.

## Pin File

`finasu-pin.txt` — tracks the `master` branch tip of `LyraVoid/FinaSU`. Updated automatically by `ksu-upstream-monitor.yml` every 6 hours.
