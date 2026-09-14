#!/bin/bash
# Dumps Kconfig toggle states from the built kernel's .config into GITHUB_STEP_SUMMARY.
# Usage: report-config.sh <kernel_root> <android_ver> <kernel_ver>

KERNEL_ROOT="$1"
ANDROID_VER="$2"
KERNEL_VER="$3"

DOT_CONFIG=""

# 1. Primary candidate paths (Bazel/Kleaf, standard out layouts, and glob expansions)
candidates=(
  "$KERNEL_ROOT/bazel-bin/common/kernel_aarch64/.config"
  "$KERNEL_ROOT/out/${ANDROID_VER}-${KERNEL_VER}/common/.config"
  "$KERNEL_ROOT/out/${ANDROID_VER}-${KERNEL_VER}/.config"
)

shopt -s nullglob
candidates+=(
  "$KERNEL_ROOT"/out/android*/common/.config
  "$KERNEL_ROOT"/out/android*/.config
  "$KERNEL_ROOT"/bazel-bin/**/.config
  "$KERNEL_ROOT"/bazel-out/**/common/kernel_aarch64/.config
  "$KERNEL_ROOT"/common/.config
)
shopt -u nullglob

# Check candidate paths; prioritize .config files containing CONFIG_KSU
for candidate in "${candidates[@]}"; do
  if [ -f "$candidate" ] && grep -q "CONFIG_KSU" "$candidate" 2>/dev/null; then
    DOT_CONFIG="$candidate"
    break
  fi
done

# 2. Fallback: recursively search with find -L "$KERNEL_ROOT" -name ".config" -type f validating CONFIG_KSU
if [ -z "$DOT_CONFIG" ]; then
  while IFS= read -r candidate; do
    if [ -f "$candidate" ] && grep -q "CONFIG_KSU" "$candidate" 2>/dev/null; then
      DOT_CONFIG="$candidate"
      break
    fi
  done < <(find -L "$KERNEL_ROOT" -name ".config" -type f 2>/dev/null)
fi

# 3. Ultimate fallback: if CONFIG_KSU wasn't matched, check candidates without filter
if [ -z "$DOT_CONFIG" ]; then
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      DOT_CONFIG="$candidate"
      break
    fi
  done
fi

if [ -z "$DOT_CONFIG" ]; then
  DOT_CONFIG=$(find -L "$KERNEL_ROOT" -name ".config" -type f 2>/dev/null | head -1)
fi

if [ -z "$DOT_CONFIG" ]; then
  echo "::warning::No .config found — skipping config report"
  exit 0
fi

{
  echo ""
  echo "### Kernel Config Toggles"
  echo ""
  echo "| Config | State |"
  echo "|--------|-------|"

  for symbol in \
    CONFIG_KSU \
    CONFIG_KSU_SUSFS \
    CONFIG_KSU_SUSFS_SUS_PATH \
    CONFIG_KSU_SUSFS_SUS_MOUNT \
    CONFIG_KSU_SUSFS_SUS_KSTAT \
    CONFIG_KSU_SUSFS_SUS_KSTAT_REDIRECT \
    CONFIG_KSU_SUSFS_SUS_MAP \
    CONFIG_KSU_SUSFS_SPOOF_UNAME \
    CONFIG_KSU_SUSFS_ENABLE_LOG \
    CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
    CONFIG_KSU_SUSFS_OPEN_REDIRECT \
    CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
    CONFIG_KSU_SUSFS_UNICODE_FILTER \
    CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
    CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
    CONFIG_KSU_SUSFS_UID_GATED_HIDING \
    CONFIG_KSU_SUSFS_HIDDEN_NAME \
    CONFIG_KSU_SUSFS_HARDENED \
    CONFIG_NOMOUNT \
    CONFIG_KPM; do

    # Dual-check CONFIG_NOMOUNT and CONFIG_ZEROMOUNT to prevent false '—' on patch-based trees
    if [ "$symbol" = "CONFIG_NOMOUNT" ]; then
      val=$(grep -E "^(CONFIG_NOMOUNT|CONFIG_ZEROMOUNT)=" "$DOT_CONFIG" 2>/dev/null | head -1 | cut -d= -f2)
      not_set=$(grep -E "# (CONFIG_NOMOUNT|CONFIG_ZEROMOUNT) is not set" "$DOT_CONFIG" 2>/dev/null | head -1)
    else
      val=$(grep "^${symbol}=" "$DOT_CONFIG" 2>/dev/null | head -1 | cut -d= -f2)
      not_set=$(grep "# ${symbol} is not set" "$DOT_CONFIG" 2>/dev/null)
    fi

    if [ -n "$val" ]; then
      echo "| \`${symbol}\` | \`${val}\` |"
    elif [ -n "$not_set" ]; then
      echo "| \`${symbol}\` | not set |"
    else
      echo "| \`${symbol}\` | — |"
    fi
  done

  echo ""
  echo "<details><summary>.config path</summary>"
  echo ""
  echo "\`${DOT_CONFIG}\`"
  echo "</details>"
} >> "$GITHUB_STEP_SUMMARY"
