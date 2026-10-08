# ⚡ BruhKernel

**Custom GKI kernels for Android, built automatically in GitHub Actions.**

You press a button, GitHub compiles a kernel for your phone in the cloud, and
you get back a flashable zip. No compiling toolchain, no Linux box, no waiting
on your own laptop for four hours.

The reference device is the **Xiaomi POCO F6 / Redmi Turbo 3** (codename
`peridot`), but any GKI phone from Android 12 to 16 will usually work.

---

## Table of contents

- [What you get](#what-you-get)
- [Quick start](#quick-start)
- [Picking your target](#picking-your-target)
- [The build options, explained](#the-build-options-explained)
- [Choosing a root variant](#choosing-a-root-variant)
- [After flashing](#after-flashing)
- [If something goes wrong](#if-something-goes-wrong)
- [How the repository is laid out](#how-the-repository-is-laid-out)
- [What actually happens during a build](#what-actually-happens-during-a-build)
- [Other devices: Samsung and OnePlus/OPPO](#other-devices-samsung-and-oneplusoppo)
- [Contributing](#contributing)
- [Credits](#credits)
- [Licence](#licence)

---

## What you get

Each completed run produces a zip you flash to replace your stock kernel:

| | |
|---|---|
| **Root** | KernelSU, built in — no flashing a Magisk-style module |
| **Root hiding** | SUSFS, so banking apps and integrity checks have a much harder time spotting it |
| **Compressed RAM** | ZRAM with LZ4KD, which keeps more RAM free than the stock compressible memory |
| **Faster networking** | TCP BBR congestion control, CUBIC kept as the fallback |
| **Cleaner mounts** | HybridMount VFS backend, so module mounts leave almost no trace in `/proc/mounts` |
| **Matching version string** | Optionally makes `uname -r` report your stock kernel version, so apps that check it are less suspicious |

Everything is built from Google's official GKI source, so it should behave like
a stock kernel apart from the features above.

> **New to custom kernels?** Flashing a custom kernel is not risk-free: it will
> not survive an OTA update, and if you pick the wrong image you can soft-brick
> your device. Back up your boot partition before you start, and read the
> [After flashing](#after-flashing) section before rebooting.

---

## Quick start

You do not need this repository checked out. Everything happens on GitHub.

1. **Open the Actions tab** and run **Build BruhKernel**.
2. **Accept the defaults.** They already target the POCO F6 / Redmi Turbo 3
   (`android14-6.1`, sublevel `138`) with the SukiSU root variant.
3. **Wait about 40 minutes.** Four variants compile in parallel, so it is one
   wait, not four.
4. **Download the artifact.** At the bottom of the run you will find something
   like `6.1.138-android14-2025-06-SukiSU-AnyKernel3`. That is your kernel.
5. **Flash it**, then reboot.

To flash from a computer:

```bash
fastboot flash boot boot.img
fastboot reboot
```

Or flash the zip with **Kernel Flasher** or **MKernelFlasher** from your phone.

To check it worked, open a root shell:

```bash
uname -a          # should show your stock-looking kernel version
ksud --version    # should report the variant you built
```

---

## Picking your target

The defaults are for `peridot`. If you have a different phone, work out which
line you need and change two fields.

| Field | What to put |
|---|---|
| **Kernel version directory** | Your Android version and kernel version, e.g. `android14-6.1` |
| **Sublevel** | Your kernel's patch level, e.g. `138` |
| **OS patch level** | The Android security patch month your sublevel shipped with, e.g. `2025-06` |

How to find those numbers:

```bash
uname -r
# 6.1.138-android14-11-g0c3d559bcd85-ab14529422
#  ^--- ^--- ^--- ^--- ^----------------------------- Android version and sublevel
```

The last part is your security patch level. If the build rejects your numbers,
the workflow prints the full list of valid combinations for that version — you
cannot pick an invalid pair.

| Version directory | Targets | Notes |
|---|---|---|
| `android12-5.4` | 1 | SukiSU and ReSukiSU only |
| `android12-5.10` | 17 | |
| `android13-5.10` | 37 | |
| `android13-5.15` | 18 | |
| `android14-5.15` | 13 | |
| `android14-6.1` | 21 | **Reference device.** Best tested |
| `android15-6.6` | 17 | |
| `android16-6.12` | 5 | |

The complete list of valid version/sublevel/patch combinations lives in
[`.github/inputs/targets.json`](.github/inputs/targets.json), and the same file
drives the validation step.

**GKI only.** This does not work on a phone that ships a vendor-specific kernel
with no GKI base. If `uname -r` shows a kernel that is not one of the eight
versions above, this repository cannot help you.

---

## The build options, explained

Every toggle has a sensible default. You can ignore all of them.

| Option | Default | What it does |
|---|---|---|
| `add_susfs` | on | **Root hiding.** Hides root files, mount points, `/proc` entries and kernel symbols from apps. Turn this off if something breaks and you want to debug it. |
| `add_zram` | on | **Compressed swap in RAM.** Replaces the stock ZRAM with an LZ4K/LZ4KD build that compresses better. |
| `add_bbg` | on | **Baseband Guard.** Locks down the radio interface so more firmware is built into the kernel rather than a loadable module. |
| `add_overlayfs_support` | on | **tmpfs extended attributes.** Required for modules to overlay files correctly. |
| `add_kpm` | off | **Kernel Patch Module runtime.** Lets you load extra kernel patches at runtime without reflashing. Only SukiSU and ReSukiSU support it. |
| `add_hybridmount_vfs` | on | **VFS redirection backend.** Keeps module mounts out of the mount tables. |
| `device_codename` | `peridot` | Which device profile to copy the kernel version string from. Use `generic` to leave your real kernel version alone. |
| `sukisu_commit` | empty | Pin a specific upstream root-solution commit instead of the tracked one. Leave empty unless you are testing a specific commit. |

### About `device_codename`

Some apps refuse to run when `uname -r` reports an unexpected kernel. The
`peridot` profile makes the kernel report the exact version string your stock
firmware used, including build date and compiler, so those checks stay quiet.

This only applies when the sublevel matches the profile. For any other target
the build falls back to `Generic` and leaves the version string alone — a
deliberate trade, since a wrong spoof is more suspicious than no spoof.

---

## Choosing a root variant

All four give you root with SUSFS. They differ in how close they track upstream
and how much extra tuning they carry.

| Variant | Best for | Notes |
|---|---|---|
| **SukiSU-Ultra** | **Most people.** Recommended default. | Tracks upstream KernelSU closely, supports KPM, actively maintained. |
| **ReSukiSU** | Battery life and lighter background use. | Stripped-down SukiSU fork. |
| **KernelSU-Next** | Long-running stable devices. | Conservative upstream fork. |
| **WKSU** | Networking and throughput tuning. | Carries extra performance patches; most likely to need debugging. |

Build one variant or all four. Pick a single one and you only wait for one
compile instead of four.

---

## After flashing

1. **Root is not finished until you install a manager.** The kernel provides
   root; the app on your phone is what grants and revokes it. For SukiSU, install
   the **SukiSU-Ultra manager** app.
2. **Install the BruhMount metamodule.** SukiSU delegates module mounting to a
   metamodule rather than doing it in the core. Without it, modules install but
   do not take effect.
3. **Reboot once more** after installing the manager.

### Updating after an OTA

An OTA overwrites your kernel and removes root. To avoid this, install the OTA
to the *inactive* slot first, flash your kernel zip to that slot from the
SukiSU manager's patching screen, then reboot into it.

---

## If something goes wrong

**The manager shows a "safe mode" badge and module flashing is gone.**
This used to be a real bug where three volume-down presses hours after boot
could permanently trigger it. It is fixed, and the build now verifies the fix
applied. If you still hit it, check with:

```bash
ksud debug info | grep -i safemode
```

If that says `true` on a freshly booted device, please open an issue.

**The build fails at "Build Kernel".**
The `Dump Build Errors` step pushes logs to the `debug-logs` branch of this
repository. Also check the **Rejects** artifact in the run — if patch
application left `.rej` files, the count appears in the job summary.

**The phone will not boot.**
Hold Volume Down while powering on to enter the system's own safe mode, which
disables modules. If that does not help, flash your stock `boot.img` back over
fastboot. This is why you keep a backup.

**Root is granted but an app still sees it.**
SUSFS hides a lot but not everything. Confirm the feature you need is enabled
in your build with `ksu_susfs show`, and check the app is not using a kernel
module you disabled.

---

## How the repository is laid out

```
BruhKernel/
├── build.yml                    ← the only workflow you normally touch
├── build-kernel.yml             ← the actual GKI builder (all 4 variants)
├── .github/
│   ├── inputs/
│   │   ├── targets.json         ← valid version/sublevel combinations
│   │   ├── variants.json        ← per-variant build parameters
│   │   ├── samsung-devices.json ← Samsung device table
│   │   └── bbk-devices.json     ← OnePlus/OPPO device table
│   └── workflows/               ← plus the Samsung/BBK and dry-test flows
├── android14-6.1/               ← one directory per GKI version
│   ├── defconfig.fragment       ← which config options get enabled
│   ├── build-helpers/           ← scripts that patch and configure the build
│   ├── SukiSU-Ultra/patches/    ← SUSFS and safety patches
│   ├── sukisu-pin.txt           ← which upstream commit this version tracks
│   └── README.md                ← detailed config documentation
├── zram/                        ← vendored LZ4 1.10.0
├── manifests/bbk/               ← OnePlus/OPPO kernel manifests
├── device-profiles.json         ← kernel version strings to spoof
└── notes/                       ← gotchas we hit, so you do not have to
```

There are eight `android*` directories. Each is self-contained, which is why
per-version fixes are never accidentally applied to a different kernel.

---

## What actually happens during a build

If you want to modify this repo rather than just use it, here is the path:

1. **Resolve.** `build.yml` validates your target against `targets.json` and
   picks the variants to build. Failures happen here, immediately, with a
   readable message — not twenty minutes into a kernel compile.
2. **Fetch dependencies.** AnyKernel3, the WildKernels patch set, the
   LZ4K/LZ4KD decompressors, and Google's `repo` launcher.
3. **Sync the kernel.** `repo init` against Google's kernel manifest for your
   exact sublevel, then a shallow sync. This is the slowest step and the bulk of
   the wall-clock time.
4. **Install the root solution.** Clone the chosen variant's repo at the commit
   in that version's `*-pin.txt`.
5. **Apply patches.** SUSFS (`50_`, `51_`), then the variant safety patch
   (`70_`), then per-version compatibility fixes, then optional Baseband Guard,
   LZ4 and HybridMount.
6. **Configure.** Merge `defconfig.fragment` into the kernel's defconfig, force
   ZRAM and tmpfs built-in, and strip anything the kernel does not declare.
7. **Compile.** Bazel/Kleaf, or `build.sh` on older kernels.
8. **Package.** Drop the `Image` into the AnyKernel3 zip and upload it.

`ksu-upstream-monitor.yml` runs every six hours, checks each variant's upstream
branch for new commits, updates the `*-pin.txt` files, and dispatches a build
when something moves. Note that the seven versions other than `android14-6.1`
track SukiSU's `builtin` branch rather than `main`, because that is the branch
their builds were validated against.

---

## Other devices: Samsung and OnePlus/OPPO

These are separate workflows because they work differently: they sync a
**vendor** kernel tree rather than Google's public GKI source.

| Workflow | Covers |
|---|---|
| `Samsung OEM - *` | 14 Samsung devices (S22–S25 Ultra, Z Fold, Tab S9, A54, A56, M14) |
| `BBK OGKI - *` | OnePlus / OPPO / realme devices listed in `bbk-devices.json` (88 entries) |

Run them directly from the Actions tab; they take a device key from the table
in `.github/inputs/`.

Be aware the BBK registry is aspirational: it lists 88 device keys, but only
four kernel manifests are committed under [`manifests/bbk/`](manifests/bbk), and
only **5 of the 88 keys** currently resolve to one — OnePlus 15 (two variants),
15R, Ace 6 and Ace 6T. The rest will fail at manifest lookup. The Samsung
flows are better covered.

If you own one of these devices and want to help, those flows need more love
than the GKI path — they are the least tested part of this repository.

---

## Contributing

Patches and config changes are welcome, especially for devices other than
`peridot`.

Before opening a pull request:

- **Run the dry test.** The `Dry Test Patches` workflow applies the patch set
  and compiles without producing a flashable image. Much faster feedback than
  a full build.
- **Check your scripts parse:** `bash -n yourscript.sh`
- **Check your workflow:** [`actionlint`](https://github.com/rhysd/actionlint)
  catches expression and context errors that a YAML parser accepts silently.

Two things worth reading in [`notes/agent-notes.md`](notes/agent-notes.md)
before touching the workflows — both cost a full 40-minute build to diagnose:
GitHub Actions boolean inputs are not null-safe, and a job-level `if:` cannot
reference the `matrix` context.

---

## Credits

This project stands on a lot of other people's work.

- **[tiann / KernelSU](https://github.com/tiann/KernelSU)** — the root
  architecture this is built around.
- **[SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)** ·
  **[ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)** ·
  **[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)** ·
  **[WildKSU](https://github.com/WildKernels/Wild_KSU)** — the root variants.
- **[simonpunk / SUSFS](https://gitlab.com/simonpunk/susfs4ksu)** — root hiding.
- **[Hybrid-Mount](https://github.com/Hybrid-Mount/meta-hybrid_mount)** — the
  VFS redirection backend.
- **[WildKernels](https://github.com/WildKernels)** — AnyKernel3 and the
  performance patch set this builds on.
- **[Enginex0](https://github.com/Enginex0)** — ZeroMount, and the Super-Builders
  CI architecture the pipeline grew out of.
- **[Yann Collet / LZ4](https://github.com/lz4/lz4)** — the compressor vendored
  in `zram/`.
- **[Google AOSP](https://source.android.com)** — the kernel source itself.

If you are new to custom kernels, these projects have much more thorough
documentation than this repository does.

---

## Licence

**GPL-2.0-only.** The full text is in [LICENSE](LICENSE); provenance for
vendored and build-time-fetched third-party code is in [NOTICE](NOTICE).

Because the output is a modified Linux kernel, redistributing a built image
means you must also offer the corresponding source and include the GPL-2.0
text.

---

## Disclaimer

Flashing custom kernels is inherently risky. This software is provided as-is,
without warranty of any kind. You are responsible for your device. Keep a
backup of your boot partition.
