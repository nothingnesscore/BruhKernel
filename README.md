# ⚡ BruhKernel

> **Automated Custom GKI Kernel Build Pipeline**  
> *Reproducible, High-Performance GKI 2.0 Kernels with HybridMount VFS Redirection & SUSFS*

[![CI Build](https://github.com/nothingnesscore/BruhKernel/actions/workflows/kernel-custom.yml/badge.svg)](https://github.com/nothingnesscore/BruhKernel/actions/workflows/kernel-custom.yml)
[![Kernel: GKI 6.1](https://img.shields.io/badge/Kernel-GKI%206.1-orange.svg)](https://android.googlesource.com/kernel/common)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%2012--16-blue.svg)](https://source.android.com)
[![VFS: HybridMount](https://img.shields.io/badge/VFS-HybridMount-red.svg)](https://github.com/Hybrid-Mount/meta-hybrid_mount)
[![Root Hiding: SUSFS](https://img.shields.io/badge/Root%20Hiding-SUSFS%20(v1.5.0--v2.3.0%2B)-purple.svg)](https://gitlab.com/simonpunk/susfs4ksu)

---

## ⚠️ Device Note: Default Kernel String Spoofing

> **The prebuilt kernel strings in this repository are configured for `peridot` — POCO F6 / Redmi Turbo 3 (Android 14, Kernel 6.1).**

This means the kernel version banner (`uname -r`), build timestamp, and compiler info embedded in the kernel image are spoofed to match the stock OEM values for that specific device — helping avoid detection-based mismatches on banking apps and integrity checks.

**If you are using a different GKI-compatible device**, you will want to match your own device's stock kernel strings. Here is how to do it:

### Custom Device Kernel Strings — Step by Step

1. **Extract your stock `boot.img`:** Download your device's OTA or stock firmware. Use `payload-dumper-go` or `payload_dumper.py` to extract `boot.img` from `payload.bin`.
2. **Read the kernel version string:**
   ```bash
   strings boot.img | grep "Linux version"
   ```
   Example output:
   ```
   Linux version 6.1.57-android14-11-gabcdef123456-ab12345678 (build-user@build-host) (Android clang version 17.0.2, ...) #1 SMP PREEMPT ...
   ```
3. **Edit `device-profiles.json`:** Add your device profile under `devices`:
   ```json
   "mydevice": {
     "name": "Your Device Name",
     "codename": "mydevice",
     "android_version": "android14",
     "kernel_version": "6.1",
     "sub_level": "57",
     "os_patch_level": "2024-01",
     "stock_kernel": {
       "release": "-android14-11-gabcdef123456-ab12345678",
       "version_string": "#1 SMP PREEMPT Mon Jan 1 12:00:00 UTC 2024",
       "build_user": "build-user",
       "build_host": "build-host",
       "compiler_info": "Android clang version 17.0.2"
     }
   }
   ```
4. **Select your codename in the workflow dispatch:** When triggering a build via GitHub Actions, choose `device_codename: mydevice` from the dropdown (after adding it to the options list in the relevant `kernel-*.yml` file).
5. **Alternatively use BootKernelChanger:** Flash the generic built kernel, then use [BootKernelChanger](https://github.com/Dayto0/BootKernelChanger) to inject the compiled kernel into your stock boot image. This preserves the stock OEM metadata automatically without editing the profiles.

---

## 📖 Overview

**BruhKernel** is an automated GKI (Generic Kernel Image) build pipeline designed for modern Android 12 – 16 devices running common GKI kernels (with profiles for Android 14 Kernel 6.1).

It combines modern kernel root solutions with an in-kernel **VFS path redirection backend (HybridMount, `CONFIG_HYBRIDMOUNT=y`)** and **SUSFS (v1.5.0 – v2.3.0+) root isolation**, providing an ultra-clean environment where module modifications are transparent and leave few mount table artifacts.

---

## 💡 Architectural Decisions: VFS Backend History

Earlier iterations used **ZeroMount** (`60_zeromount` patches modifying `fs/overlayfs`), which relied on overlayfs hooks and `/dev` ioctl communication, and then **NoMount** (`CONFIG_NOMOUNT=y`), which redirected paths through the kernel keyring with no `/dev` nodes at all.

**BruhKernel now builds HybridMount** (`CONFIG_HYBRIDMOUNT=y`, from [Hybrid-Mount](https://github.com/Hybrid-Mount/meta-hybrid_mount)):
* **No redundant overlayfs hooks:** the backend is added directly to `common/` rather than layered on top of `fs/overlayfs`.
* **Kernel-assisted module redirection:** SukiSU delegates all module mounting to the installed metamodule, and HybridMount provides the VFS layer underneath it.
* **Lean & Conflict-Free:** no `CONFIG_NOMOUNT` or `CONFIG_ZEROMOUNT` symbol remains in any `defconfig.fragment`.

If you are upgrading from an older NoMount build, expect to install or update the **BruhMount** metamodule (see [Flashing](#-flashing--verification)) — module redirection is handled by the metamodule, not by the core.

---

## 🌟 Key Features & Capabilities

### 1. Multi-Variant KernelSU Support
* **SukiSU-Ultra:** Recommended variant combining KernelSU root with SUSFS and Kernel Patch Module (KPM) support.
* **ReSukiSU:** Minimalist, performance-tuned SukiSU build.
* **KernelSU-Next (KSUN):** The upstream KernelSU fork by rifsxd and pershoot.
* **WildKSU (WKSU):** Performance-oriented KernelSU variant.

### 2. Kernel SUSFS Integration (v1.5.0 – v2.3.0+)
* Advanced kernel-level isolation: `sus_path`, `sus_mount`, `sus_kstat`, `sus_map`, and `open_redirect`.
* Automated sdcard monitoring worker (`susfs_start_sdcard_monitor_fn`).
* AVC denial log spoofing to maintain clean audit logs.

### 3. Device Profile & Metadata Matching
Ensures kernel version banners, build timestamps, and compiler identifiers seamlessly match configured OEM target profiles in `device-profiles.json` to prevent runtime environment mismatches.

### 4. Performance & Networking
* **TCP BBRv3 / BBR:** Google's Bottleneck Bandwidth and RTT congestion control algorithm for low-latency networking.
* **ZRAM with LZ4KD Compression:** Accelerated page compression and decompression algorithms for smoother memory management.
* **`CONFIG_TMPFS_XATTR=y` & `CONFIG_TMPFS_POSIX_ACL=y`:** Extended filesystem attribute support for modern Android containers.
* **Baseband Guard (BBG):** Hardened radio interface protection.
* **`CONFIG_KPM=y`:** In-kernel Kernel Patch Module runtime loader (SukiSU / ReSukiSU variants).

---

## 📥 Flashing & Verification

### Installation
1. Download your preferred build artifact (`boot.img` or `AnyKernel3-*.zip`) from [GitHub Actions](https://github.com/nothingnesscore/BruhKernel/actions).
2. **Flash via Fastboot:**
   ```bash
   fastboot flash boot boot.img
   fastboot reboot
   ```
   *(Or flash the AnyKernel3 archive via Kernel Flasher).*
3. Install the **[BruhMount](https://github.com/nothingnesscore/BruhMount)** metamodule to handle module redirection and automated SUSFS integration.

### Verification
Open a root shell and run:
```bash
# Verify kernel version
uname -a

# Verify the KSU variant and its version
ksud --version

# Verify safe mode is NOT spuriously engaged
# (should print false; a stuck "true" here disables module flashing)
ksud debug info | grep -i safemode

# Verify SUSFS status and active features
ksu_susfs show
```

---

## 🤝 Credits & Acknowledgments

This project builds upon the work of the Android open-source kernel engineering community:

* **[Enginex0](https://github.com/Enginex0):** Creator of **ZeroMount** and the original **Super-Builders** CI architecture, whose multi-variant compilation pipeline provided the bedrock for automated GKI builds.
* **[simonpunk](https://gitlab.com/simonpunk/susfs4ksu):** Creator of **SUSFS**, the groundbreaking kernel-level file hiding and isolation framework.
* **[maxsteeel](https://github.com/maxsteeel/nomount):** Creator of **NoMount**, the earlier zero-mount VFS backend this project moved on from.
* **[Hybrid-Mount](https://github.com/Hybrid-Mount/meta-hybrid_mount):** Current in-kernel VFS redirection backend (`CONFIG_HYBRIDMOUNT=y`).
* **[tiann](https://github.com/tiann):** Founder of **KernelSU**, revolutionizing kernel-based root on Android.
* **[SukiSU-Ultra](https://github.com/SukiSU-Ultra) & [ReSukiSU](https://github.com/ReSukiSU):** For enhanced KernelSU variants with native SUSFS and KPM support.
* **[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) & [pershoot](https://github.com/pershoot):** For continuous upstream development and forward-looking GKI maintenance.
* **[WildKernels](https://github.com/WildKernels):** For performance patches, TCP optimizations, and WildKSU.
* **Google Android Open Source Project (AOSP):** For the Generic Kernel Image (GKI) initiative.

---

## ⚠️ Disclaimer

Flashing custom kernels involves low-level modifications. Always maintain backups of your device boot partitions before flashing.
