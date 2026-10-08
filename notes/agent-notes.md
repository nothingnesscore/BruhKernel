# notes/

Scratch space for investigation notes. Not part of the build.

## GitHub Actions gotchas hit in this repo

### Reusable-workflow boolean inputs are not null-safe

`kernel-custom.yml` triggers on `push` as well as `workflow_dispatch`. On a
`push` event there are no workflow inputs, so `inputs.<name>` is null. Passing
that straight through to a callee input declared `type: boolean` fails
**workflow-call validation**, before the callee ever starts.

Symptom is distinctive: the caller job succeeds, `download-dependencies`
succeeds, and the callee jobs do not appear in the run at all. Run
37747651547 looked like this and was initially mistaken for a kernel problem.

Safe form, used for `add_hybridmount_vfs`:

```yaml
add_hybridmount_vfs: ${{ github.event_name != 'workflow_dispatch' || inputs.add_hybridmount_vfs }}
```

`||` returns the first truthy operand, or the last operand if all are falsy:

| event          | expression            | result |
|----------------|-----------------------|--------|
| push           | `true \|\| ...`       | true   |
| dispatch+true  | `false \|\| true`     | true   |
| dispatch+false | `false \|\| false`    | false  |

`add_kpm` uses the simpler `${{ inputs.add_kpm || false }}` because its default
is false.

### Forcing a config symbol to `=y` can orphan its .ko

`CONFIG_ZRAM=y` stops `zram.ko` being produced, but GKI's module manifest still
lists it, so `clean-module-list.sh` strips `zram.ko` / `zsmalloc.ko` from
`common/android/gki_aarch64_modules` and `common/modules.bzl`.

The same applies to anything shipped as a module that gets forced builtin:
the `ip_set*` family, `tcp_cubic.ko` (from `CONFIG_TCP_CONG_CUBIC=y`),
`sch_fq.ko`, and the netfilter `xt_HL`/`xt_hl`/`xt_TTL` targets. Setting those
to `=y` without also scrubbing the module list fails the build at `Build Kernel`
(run 37744122306).

This is why `android14-6.1/defconfig.fragment` is short 23 symbols relative to
its siblings. Restoring them is a real gap, but it has to be done together with
the module-list scrubbing - see the reverted commit 4468881.
