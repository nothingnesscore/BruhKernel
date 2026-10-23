# OriginSU Variant

GKI in-kernel root variant built from [samakshkambxj/OriginSU](https://github.com/samakshkambxj/OriginSU).

## Directory Layout

```
OriginSU/
├── patches/              # Variant safety patches (70_*)
│   └── .gitkeep          # Placeholder — no safety patches required yet
└── (no source checked in) # Kernel source is fetched at build time via kernel/setup.sh
```

## Build Behavior

- **Source**: Cloned from `samakshkambxj/OriginSU` at the commit pinned in `originsu-pin.txt`
- **Clone target**: `KernelSU/` directory (created by `kernel/setup.sh`)
- **Build model**: GKI in-kernel build (compiled into the boot image)
- **Skip GKI build**: No — OriginSU is compiled as part of the kernel build
- **KPM**: Supported (`CONFIG_KPM=y`)
- **SUSFS**: Built into OriginSU kernel source (no external 50_/51_ patches applied)

## Features

All OriginSU features enabled via `defconfig.fragment`:

| Feature | Config | Status |
|---|---|---|
| KernelSU root framework | `CONFIG_KSU` | y |
| Origin Veil (root-probe detection + cloaking) | `CONFIG_KSU_ORIGIN_VEIL` | y |
| Tracepoint Syscall Redirect hook | `CONFIG_KSU_TRACEPOINT_HOOK` | y |
| Multi-manager support | `CONFIG_KSU_MULTI_MANAGER_SUPPORT` | y |
| Kernel Patch Module (KPM) | `CONFIG_KPM` | y |
| SUSFS root hiding | `CONFIG_KSU_SUSFS` + sub-options | y |
| SUSFS path hiding | `CONFIG_KSU_SUSFS_SUS_PATH` | y |
| SUSFS mount hiding | `CONFIG_KSU_SUSFS_SUS_MOUNT` | y |
| SUSFS kstat spoofing | `CONFIG_KSU_SUSFS_SUS_KSTAT` | y |
| SUSFS map hiding | `CONFIG_KSU_SUSFS_SUS_MAP` | y |
| SUSFS uname spoof | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | y |
| SUSFS open redirect | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | y |
| SUSFS symbol hiding | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | y |
| SUSFS unicode filter | `CONFIG_KSU_SUSFS_UNICODE_FILTER` | y |

## Manager

Install the official **OriginSU manager** APK from the [OriginSU Releases](https://github.com/samakshkambxj/OriginSU/releases) page. The kernel only trusts the official release-signed manager.

## Pin File

`originsu-pin.txt` — tracks the `main` branch tip of `samakshkambxj/OriginSU`. Updated automatically by `ksu-upstream-monitor.yml` every 6 hours.
