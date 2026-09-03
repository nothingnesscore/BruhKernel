#!/bin/bash
# fix-susfs-compat.sh — Runtime SUSFS kernel compatibility fixes
# Called by build workflows after patches are applied.
# Fixes sublevel-dependent issues that can't be in static patches.
# Idempotent: safe to run multiple times on the same tree.
#
# Usage: fix-susfs-compat.sh <kernel_common_dir> <sublevel> <android_ver> <kernel_ver> <kernel_patches_dir>

KERNEL_DIR="$1"   # e.g., /path/to/common
SUBLEVEL="$2"     # e.g., 107, 209, 246
ANDROID_VER="$3"  # e.g., android12
KERNEL_VER="$4"   # e.g., 5.10
PATCHES_DIR="$5"  # reserved — not currently used

if [ -z "$KERNEL_DIR" ] || [ ! -d "$KERNEL_DIR" ]; then
    echo "fix-susfs-compat: ERROR: kernel dir '$KERNEL_DIR' not found" >&2
    exit 1
fi

echo "fix-susfs-compat: kernel=$KERNEL_DIR sublevel=$SUBLEVEL android=$ANDROID_VER kver=$KERNEL_VER"

# ---------------------------------------------------------------------------
# Fix 1: show_pad: label missing from fs/proc/task_mmu.c
# Needed when the 50_ patch adds a 'goto show_pad;' but the label itself
# isn't present in the source (android12-5.10 sublevels < 218).
# ---------------------------------------------------------------------------
TMU="$KERNEL_DIR/fs/proc/task_mmu.c"
if [ -f "$TMU" ]; then
    if grep -q 'goto show_pad;' "$TMU" && ! grep -q '^show_pad:' "$TMU"; then
        echo "fix-susfs-compat: injecting show_pad: label in task_mmu.c (sublevel $SUBLEVEL)"
        sed -i '/show_smap_vma_flags(m, vma);/,/return 0;/{/return 0;/i\show_pad:
        }' "$TMU"
    fi
    # Suppress -Wunused-label on show_pad regardless of goto presence
    if grep -q '^show_pad:' "$TMU" && ! grep -q 'show_pad:.*__attribute__' "$TMU"; then
        echo "fix-susfs-compat: marking show_pad: as maybe-unused in task_mmu.c"
        sed -i 's/^show_pad:$/show_pad: __attribute__((__unused__));/' "$TMU"
    fi
else
    echo "fix-susfs-compat: task_mmu.c not found — skipping show_pad fix"
fi

# ---------------------------------------------------------------------------
# Fix 2: fdinfo.c — inotify_mark_user_mask() fallback
# The helper was backported mid-stable (~5.10.68+). On older sublevels
# the function is absent, causing a link error. Replace the call with
# the direct field access it wraps.
# Guard: only act when the call-site is present but the definition is absent.
# ---------------------------------------------------------------------------
FDINFO="$KERNEL_DIR/fs/notify/fdinfo.c"
if [ -f "$FDINFO" ]; then
    if grep -q 'inotify_mark_user_mask(mark)' "$FDINFO"; then
        if ! grep -rq 'static.*inotify_mark_user_mask\|^u32 inotify_mark_user_mask' "$KERNEL_DIR/fs/notify/"; then
            echo "fix-susfs-compat: replacing inotify_mark_user_mask(mark) with mark->mask in fdinfo.c"
            sed -i 's/inotify_mark_user_mask(mark)/mark->mask/g' "$FDINFO"
        else
            echo "fix-susfs-compat: inotify_mark_user_mask defined — no fallback needed"
        fi
    fi
else
    echo "fix-susfs-compat: fdinfo.c not found — skipping inotify_mark_user_mask fix"
fi

# ---------------------------------------------------------------------------
# Fix 3: fdinfo.c — old-style 'u32 mask' declaration (sublevel ≤ 117)
# Early 5.10 sublevels declare 'u32 mask = mark->mask & IN_ALL_EVENTS;'
# before the SUSFS injected code, producing a C89 "declaration after
# statement" error. Delete the declaration and replace bare 'mask' refs.
# ---------------------------------------------------------------------------
if [ -f "$FDINFO" ]; then
    if grep -q 'u32 mask = mark->mask & IN_ALL_EVENTS;' "$FDINFO"; then
        echo "fix-susfs-compat: fixing u32 mask declaration in fdinfo.c (sublevel $SUBLEVEL)"
        # Remove the declaration
        sed -i '/u32 mask = mark->mask & IN_ALL_EVENTS;/d' "$FDINFO"
        # Single-line seq_printf variant: s_dev, mask)
        sed -i 's/s_dev, mask)/s_dev, mark->mask)/g' "$FDINFO"
        # Multi-line seq_printf variant: leading whitespace + mask, mark->ignored_mask
        sed -i 's/^\([[:space:]]*\)mask, mark->ignored_mask/\1mark->mask, mark->ignored_mask/' "$FDINFO"
    else
        echo "fix-susfs-compat: fdinfo.c u32 mask declaration not present — OK"
    fi
fi

# ---------------------------------------------------------------------------
# Fix 4: fdinfo.c — 'out_seq_printf:' label missing trailing semicolon
# C requires a statement after a label. The SUSFS patch may inject the
# label without a semicolon on older sublevels.
# ---------------------------------------------------------------------------
if [ -f "$FDINFO" ]; then
    # Match lines that have ONLY the label (no trailing semicolon)
    if grep -qE '^[[:space:]]*out_seq_printf:[[:space:]]*$' "$FDINFO"; then
        echo "fix-susfs-compat: adding semicolon after out_seq_printf: label in fdinfo.c"
        sed -i 's/^\([[:space:]]*\)out_seq_printf:[[:space:]]*$/\1out_seq_printf: ;/' "$FDINFO"
    else
        echo "fix-susfs-compat: out_seq_printf: label OK (already has semicolon or absent)"
    fi
fi

# ---------------------------------------------------------------------------
# Fix 5: susfs.c — i_uid_into_mnt / i_user_ns() fallback
# These helpers were backported mid-5.15 and are absent from 5.10 kernels
# that don't carry the backport. Fall back to direct i_uid field access.
# Guard: check for i_user_ns in include/linux/fs.h.
# ---------------------------------------------------------------------------
SUSFS_C="$KERNEL_DIR/fs/susfs.c"
if [ -f "$SUSFS_C" ]; then
    if ! grep -q 'i_user_ns' "$KERNEL_DIR/include/linux/fs.h" 2>/dev/null; then
        if grep -q 'i_uid_into_mnt' "$SUSFS_C"; then
            echo "fix-susfs-compat: replacing i_uid_into_mnt() calls in susfs.c (i_user_ns absent)"
            sed -i 's/i_uid_into_mnt(i_user_ns(&fi->inode), &fi->inode)\.val/fi->inode.i_uid.val/g' "$SUSFS_C"
            sed -i 's/i_uid_into_mnt(i_user_ns(inode), inode)\.val/inode->i_uid.val/g' "$SUSFS_C"
        fi
    else
        echo "fix-susfs-compat: i_user_ns present — i_uid_into_mnt fix not needed"
    fi
else
    echo "fix-susfs-compat: susfs.c not found — skipping i_uid_into_mnt fix"
fi

# ---------------------------------------------------------------------------
# Fix 6: setuid_hook.c — duplicate ksu_handle_setresuid on >= 6.8 kernels
# SukiSU builtin branch defines ksu_handle_setresuid in both the SUSFS
# #else block AND a separate 6.8+ MANUAL_HOOK block. When both
# CONFIG_KSU_SUSFS and CONFIG_KSU_MANUAL_HOOK are defined, both compile,
# causing a redefinition error. Remove the 6.8+ block.
# ---------------------------------------------------------------------------
SETUID=$(find "$KERNEL_DIR" -type f -name "setuid_hook.c" | head -n 1)
if [ -f "$SETUID" ]; then
    DUPS=$(grep -c 'int ksu_handle_setresuid' "$SETUID")
    if [ "$DUPS" -gt 1 ]; then
        echo "fix-susfs-compat: removing duplicate ksu_handle_setresuid (6.8+ MANUAL_HOOK block)"
        python3 - "$SETUID" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
occurrences = [i for i, l in enumerate(lines) if 'int ksu_handle_setresuid' in l]
if len(occurrences) > 1:
    target_idx = occurrences[1]
    start = None
    for i in range(target_idx, -1, -1):
        if lines[i].strip().startswith('#if'):
            start = i
            break
else:
    start = None
if start is not None:
    depth, end = 0, None
    for i in range(start, len(lines)):
        stripped = lines[i].strip()
        if stripped.startswith('#if'):
            depth += 1
        elif stripped.startswith('#endif'):
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is not None:
        del lines[start:end+1]
        while lines and lines[-1].strip() == '':
            lines.pop()
        lines.append('\n')
        with open(path, 'w') as f:
            f.writelines(lines)
        print(f"  removed lines {start+1}-{end+1}")
PYEOF
    else
        echo "fix-susfs-compat: setuid_hook.c — no duplicate ksu_handle_setresuid"
    fi
else
    echo "fix-susfs-compat: setuid_hook.c not found — skipping"
fi

echo "fix-susfs-compat: done"

# ---------------------------------------------------------------------------
# Fix 7: core/init.c - susfs.h include order
# When susfs.h is included BEFORE fs.h, transitive includes (like signal.h)
# can break because arch-specific macros (_NSIG) aren't set yet, leading to
# array bounds errors. Ensure susfs.h comes AFTER fs.h.
# ---------------------------------------------------------------------------
INIT_C=$(find "$KERNEL_DIR" -type f -name "init.c" | grep -i "core/init.c" | head -n 1)
if [ -f "$INIT_C" ]; then
    if grep -q '#include <linux/susfs.h>' "$INIT_C"; then
        echo "fix-susfs-compat: ensuring susfs.h is included after fs.h in init.c"
        python3 - "$INIT_C" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

import re

# Find if susfs.h comes before fs.h
idx_susfs = content.find('<linux/susfs.h>')
idx_fs = content.find('<linux/fs.h>')

if idx_susfs != -1 and idx_fs != -1 and idx_susfs < idx_fs:
    # It's before fs.h! We need to move it.
    # We will remove any line containing susfs.h, and its surrounding #ifdef/#endif if they exist adjacently
    lines = content.split('\n')
    out_lines = []
    susfs_lines = []
    
    i = 0
    while i < len(lines):
        if '<linux/susfs.h>' in lines[i]:
            # Extract this line
            susfs_block = [lines[i]]
            # Check if previous line is #ifdef CONFIG_KSU_SUSFS
            if i > 0 and '#ifdef' in lines[i-1] and 'CONFIG_KSU_SUSFS' in lines[i-1]:
                susfs_block.insert(0, out_lines.pop())
                # Check if next line is #endif
                if i + 1 < len(lines) and '#endif' in lines[i+1]:
                    susfs_block.append(lines[i+1])
                    i += 1
            susfs_lines.extend(susfs_block)
        else:
            out_lines.append(lines[i])
        i += 1
        
    # Now insert susfs_lines after <linux/fs.h>
    final_lines = []
    for line in out_lines:
        final_lines.append(line)
        if '<linux/fs.h>' in line:
            final_lines.extend(susfs_lines)
            
    with open(path, 'w') as f:
        f.write('\n'.join(final_lines))
PYEOF
    fi
else
    echo "fix-susfs-compat: core/init.c not found - skipping include order fix"
fi


# ---------------------------------------------------------------------------
# Fix 8: include/linux/susfs_def.h missing headers for thread_flags & current_uid
# ---------------------------------------------------------------------------
SUSFS_DEF="$KERNEL_DIR/include/linux/susfs_def.h"
if [ -f "$SUSFS_DEF" ]; then
    if ! grep -q '<linux/cred.h>' "$SUSFS_DEF"; then
        echo "fix-susfs-compat: injecting sched.h, cred.h, thread_info.h into susfs_def.h"
        sed -i '/#include <linux\/string.h>/a #include <linux/sched.h>\n#include <linux/cred.h>\n#include <linux/thread_info.h>' "$SUSFS_DEF"
    fi
fi

# ---------------------------------------------------------------------------
# Fix 10: Multi-Variant KSU/SUSFS Linker Compatibility Stubs
# When building KernelSU-Next or WildKSU, SukiSU-specific SUSFS hooks in
# 50_ patch (input hook, init_rc hook, reboot hook, selinux hide, stat hooks)
# lack strong definitions, causing ld.lld undefined symbol failures.
# We inject weak stubs into fs/susfs_compat_stubs.c. Strong definitions in
# SukiSU will override them, while KSUN and WKSU will link successfully.
# ---------------------------------------------------------------------------
STUBS_FILE="$KERNEL_DIR/fs/susfs_compat_stubs.c"
if [ -d "$KERNEL_DIR/fs" ]; then
    echo "fix-susfs-compat: creating fs/susfs_compat_stubs.c for multi-variant KSU compatibility"
    cat > "$STUBS_FILE" << 'EOF_STUBS'
#include <linux/types.h>
#include <linux/jump_label.h>
#include <linux/fs.h>
#include <linux/cred.h>
#include <linux/mm.h>
#include <linux/errno.h>

struct static_key_false fake_status_initialize_key __attribute__((weak)) = STATIC_KEY_FALSE_INIT;
struct static_key_true ksu_is_init_rc_hook_enabled __attribute__((weak)) = STATIC_KEY_TRUE_INIT;
struct static_key_true ksu_is_input_hook_enabled __attribute__((weak)) = STATIC_KEY_TRUE_INIT;
struct static_key_true ksu_su_compat_enabled __attribute__((weak)) = STATIC_KEY_TRUE_INIT;

__attribute__((weak, cold)) int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value) { return 0; }
__attribute__((weak, cold)) void ksu_handle_sys_read(unsigned int fd) {}
__attribute__((weak)) int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg) { return 1; }
__attribute__((weak)) int ksu_handle_faccessat(int *dfd, struct filename **filename, int *mode, int *__unused_flags) { return 0; }
__attribute__((weak)) int ksu_handle_stat(int *dfd, struct filename **filename, int *flags) { return 0; }
__attribute__((weak)) void ksu_handle_vfs_fstat(int fd, loff_t *kstat_size_ptr) {}
__attribute__((weak)) int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) { return 0; }
__attribute__((weak)) int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) { return 0; }
__attribute__((weak)) int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid) { return 0; }
__attribute__((weak)) bool __ksu_is_allow_uid_for_current(uid_t uid) { return false; }
__attribute__((weak)) void susfs_run_sus_path_loop(void) {}

struct page *fake_status __attribute__((weak)) = NULL;
char fake_state[4096] __attribute__((weak, aligned(64))) = {0};
bool ksu_selinux_hide_running __attribute__((weak)) = false;
bool ksu_selinux_hide_enabled __attribute__((weak)) = false;
__attribute__((weak)) void initialize_fake_status(void) {}
EOF_STUBS

    FS_MAKEFILE="$KERNEL_DIR/fs/Makefile"
    if [ -f "$FS_MAKEFILE" ] && ! grep -q "susfs_compat_stubs.o" "$FS_MAKEFILE"; then
        echo "fix-susfs-compat: adding susfs_compat_stubs.o to fs/Makefile"
        echo 'obj-$(CONFIG_KSU_SUSFS) += susfs_compat_stubs.o' >> "$FS_MAKEFILE"
    fi
fi

exit 0
