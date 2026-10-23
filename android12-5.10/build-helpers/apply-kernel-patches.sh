#!/bin/bash
set -euo pipefail

KERNEL_DIR="${1:?Usage: apply-kernel-patches.sh <kernel_dir> <kernel_ver> <patches_dir>}"
KERNEL_VER="${2:?}"
PATCHES_DIR="${3:?}"

ADD_PTRACE="${ADD_PTRACE:-true}"
ADD_PERF="${ADD_PERF:-true}"
ADD_BBRV3="${ADD_BBRV3:-true}"

MAJOR="${KERNEL_VER%%.*}"
MINOR="${KERNEL_VER#*.}"
COMMON="$PATCHES_DIR/common"

# The upstream BBRv3 backports are named per android+kernel pair, e.g.
# 0001-net-tcp-backport-BBRv3-to-android14-6.1.patch. The workflow passes
# ANDROID_VER as the bare android number ("14"), but other callers pass the
# full directory name ("android14-6.1"), so normalise before use.
VERSION_DIR="${VERSION_DIR:-}"
ANDROID_VER="${ANDROID_VER:-}"
if [ -n "$ANDROID_VER" ]; then
  ANDROID_VER="${ANDROID_VER#android}"
  ANDROID_VER="${ANDROID_VER%%-*}"
fi
if [ -z "$ANDROID_VER" ] && [ -n "$VERSION_DIR" ]; then
  ANDROID_VER="${VERSION_DIR#android}"
  ANDROID_VER="${ANDROID_VER%%-*}"
fi

apply() { patch -p1 -F3 --forward < "$1" || true; }

cd "$KERNEL_DIR"

# ── BBRv3 congestion control ───────────────────────────────────────────────
# The defconfig already sets CONFIG_DEFAULT_TCP_CONG, but upstream 6.1 only
# ships BBRv1, which under-performs on lossy mobile links. This backport brings
# BBRv3 (plus PLB) so tethered/cellular sessions recover faster from loss and
# keep a lower standing queue.
#
# Applied before the memory/scheduler patches because it rewrites net/ipv4,
# which nothing below touches.
if [ "$ADD_BBRV3" = "true" ]; then
  if [ -z "$ANDROID_VER" ]; then
    echo "apply-kernel-patches: ANDROID_VER unknown, cannot locate BBRv3 patch"
  else
    BBRV3_PATCH="$COMMON/bbrv3/0001-net-tcp-backport-BBRv3-to-android${ANDROID_VER}-${KERNEL_VER}.patch"
    if [ -f "$BBRV3_PATCH" ]; then
      apply "$BBRV3_PATCH"
      if [ -f "$KERNEL_DIR/net/ipv4/tcp_bbr3.c" ]; then
        echo "apply-kernel-patches: BBRv3 applied (android${ANDROID_VER}-${KERNEL_VER})"
      else
        echo "apply-kernel-patches: WARNING BBRv3 patch did not produce tcp_bbr3.c"
        echo "apply-kernel-patches: WARNING the kernel will fall back to BBRv1"
      fi
    else
      echo "apply-kernel-patches: no BBRv3 patch for android${ANDROID_VER}-${KERNEL_VER}, skipping"
    fi
  fi
fi

if [ "$ADD_PTRACE" = "true" ] && [ -f "$PATCHES_DIR/gki_ptrace.patch" ]; then
  if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -lt 16 ]; }; then
    apply "$PATCHES_DIR/gki_ptrace.patch"
    echo "apply-kernel-patches: ptrace fix applied (kernel $KERNEL_VER < 5.16)"
  fi
fi

[ "$ADD_PERF" != "true" ] && exit 0
[ ! -d "$COMMON" ] && { echo "apply-kernel-patches: $COMMON not found"; exit 0; }

apply "$COMMON/optimized_mem_operations.patch"
apply "$COMMON/file_struct_8bytes_align.patch"
apply "$COMMON/reduce_cache_pressure.patch"
apply "$COMMON/mem_opt_prefetch.patch"

if [ "$MAJOR" -ge 6 ]; then
  apply "$COMMON/optimise_memcmp.patch"
else
  sed -e 's/SYM_FUNC_START(__pi_memcmp)/SYM_FUNC_START_WEAK_PI(memcmp)/' \
      -e 's/SYM_FUNC_END(__pi_memcmp)/SYM_FUNC_END_PI(memcmp)/' \
      -e 's/SYM_FUNC_ALIAS_WEAK(memcmp, __pi_memcmp)/EXPORT_SYMBOL_NOKASAN(memcmp)/' \
      "$COMMON/optimise_memcmp.patch" | patch -p1 -F3 --forward || true
fi

apply "$COMMON/minimise_wakeup_time.patch"
apply "$COMMON/int_sqrt.patch"
apply "$COMMON/force_tcp_nodelay.patch"
apply "$COMMON/reduce_gc_thread_sleep_time.patch"
apply "$COMMON/add_timeout_wakelocks_globally.patch"
apply "$COMMON/f2fs_reduce_congestion.patch"
apply "$COMMON/reduce_freeze_timeout.patch"

if [ "$MAJOR" -ge 6 ]; then
  apply "$COMMON/clear_page_16bytes_align.patch"
else
  sed 's/SYM_FUNC_START_PI(clear_page)/SYM_FUNC_START_PI(__pi_clear_page)/' \
    "$COMMON/clear_page_16bytes_align.patch" | patch -p1 -F3 --forward || true
fi

# upstream declares val as unsigned long but uses %u (expects unsigned int *)
sed 's/unsigned long val;/unsigned int val;/' \
  "$COMMON/add_limitation_scaling_min_freq.patch" | patch -p1 -F3 --forward || true
apply "$COMMON/re_write_limitation_scaling_min_freq.patch"
apply "$COMMON/adjust_cpu_scan_order.patch"
apply "$COMMON/avoid_extra_s2idle_wake_attempts.patch"
apply "$COMMON/disable_cache_hot_buddy.patch"
apply "$COMMON/f2fs_enlarge_min_fsync_blocks.patch"
apply "$COMMON/increase_ext4_default_commit_age.patch"
apply "$COMMON/increase_sk_mem_packets.patch"
apply "$COMMON/reduce_pci_pme_wakeups.patch"
apply "$COMMON/silence_irq_cpu_logspam.patch"
apply "$COMMON/silence_system_logspam.patch"
apply "$COMMON/use_unlikely_wrap_cpufreq.patch"

if [ -f "$COMMON/unicode_bypass_fix_6.1+.patch" ]; then
  if [ "$MAJOR" -gt 6 ] || { [ "$MAJOR" -eq 6 ] && [ "$MINOR" -ge 1 ]; }; then
    apply "$COMMON/unicode_bypass_fix_6.1+.patch"
  else
    apply "$COMMON/unicode_bypass_fix_6.1-.patch"
  fi
fi

[ -f "$COMMON/IPv6_NAT_FIX.patch" ] && apply "$COMMON/IPv6_NAT_FIX.patch"

echo "apply-kernel-patches: done"
