# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`bashkit` (github.com:s-fairchild/bashkit.git) is a standalone library of reusable bash functions and containerized-command wrappers. It has its own git history and is consumed as a **vendored git submodule** by other projects — in this checkout it lives at `hack/vendor/bashkit/` inside the `forge` repo (see `../../../../CLAUDE.md` for that project). There is no build step, package manifest, or test suite here; every file is plain POSIX-ish bash sourced directly.

## Critical: paths are relative to the *consumer's* CWD, not this repo

Every lib file's self-sourcing guard block hardcodes paths like:

```bash
declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="local/lib/bashkit/options-operands-utils.sh"
```

These are **not** `${BASH_SOURCE[0]%/*}`-relative — they assume the sourcing script is run from the consuming project's repo root, with bashkit vendored at exactly `hack/vendor/bashkit/` and a sibling `hack/vendor/bash-logger-adapter/adapter.sh` shim present. This repo cannot source its own libs standalone; a `log_debug`/`log_error`/`log_fatal`/`require_operands`/`ERROR_*` API and a `fatal()` helper must come from that external shim. When editing or adding a lib file here, preserve this convention (same guard-var naming and path shape) rather than switching to `$BASH_SOURCE`-relative sourcing — the latter would break every existing consumer.

## Install target has a known gap

```bash
make install
```
copies `local/bin/*` to `~/.local/bin/` and `local/lib/bashkit/*` to `~/.local/lib/bashkit/`. The lib copy uses `install -t ... local/lib/bashkit/*`, which does **not** recurse into subdirectories — `install` prints `omitting directory` and exits nonzero for `network/` and `virsh/`, so only the top-level `file-utils.sh`/`options-operands-utils.sh` actually land in `~/.local/lib/bashkit/`. Standalone installs are effectively broken for the `virsh/` and `network/` libs today; the vendored-submodule path (sourcing directly out of `hack/vendor/bashkit/local/lib/bashkit/...`) is the one that actually works and is what `forge` relies on.

## Structure

```
local/
  bin/                        # standalone wrapper executables (source+run in one file)
    bw                        # thin `flatpak run --command=bw com.bitwarden.desktop` wrapper
    coreos-installer           # runs quay.io/coreos/coreos-installer:release via podman
  lib/bashkit/
    file-utils.sh              # read_file_builtin, read_file_preserve_newlines, parse_file_extension
    options-operands-utils.sh  # require_operands, bashkit_print_stack_trace, is_option_arg_dup, with_xtrace_suppressed
    network/validate.sh        # validate_url
    virsh/
      virsh-domain.sh          # virsh_dom_{define,undefine,create,start,destroy,autostart,is_defined,is_active}
      virsh-network.sh         # virsh_net_{define,activate,destroy,is_defined,is_active,is_persistent,is_autostart,autostart}
      virsh-pool.sh            # virsh_pool_{define,build,start,autostart,is_defined,is_active}, virsh_vol_{create,is_present}
```

`local/bin/coreos-installer` is a full argument-parsing wrapper (`getopts ':s:m:h'` for `-s` secret specs and `-m` mount specs) around `podman run` of the coreos-installer image, forwarding remaining args to the containerized binary. `local/bin/bw` is a one-line flatpak passthrough with no option parsing.

## Conventions to follow when adding/editing functions

- Guard every sourced file against double-inclusion: `declare -r __vendor_bashkit_lib_<name>_sourced="true"` at the top, checked before re-sourcing dependencies at the bottom (each file re-sources `bash-logger-adapter/adapter.sh` and `options-operands-utils.sh` itself — don't assume load order from a caller).
- Log function entry as the first line of every function: `log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"`.
- Argument validation is consistent across every file now: `virsh-domain.sh`, `virsh-network.sh`, and `virsh-pool.sh` all use `require_operands N "$@" || return 1` then `local -r x="$1"` (the migration off the older `local -r x="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"` pattern, referenced in older commit messages as "adopt require_operands", is complete). Use `require_operands` for any new function.
- Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html): 2-space indentation, `[[ ]]` (never `[ ]`/`test`), quote every expansion (`"${var}"`), split `local x; x=$(...)` rather than combining declare+assign from a command substitution, and a Description/Globals/Arguments/Outputs/Returns comment block (matching the format already used in `hack/vendor/bash-logger-adapter/adapter.sh`) above every function. This repo's own `.claude/skills/linting-code/SKILL.md` has the full checklist and lint commands — read it before making further changes here.
- Anything that could contain secrets (podman `--secret` specs, tokens, file contents) is logged with `log_sensitive`, never `log_debug`/`log_info` — keep that distinction when adding new call sites that touch credential material.
- Thin `virsh`/`podman` wrappers just validate operands and exec the real command — no output parsing beyond the `*_is_*` predicate functions, which grep/cut `virsh ...-info` output and return via exit status for use directly in `if`/`&&` conditionals.
- `virsh_net_define()` builds an XML string in an array, writes it to a `mktemp` file, and relies on `trap 'rm -f "$network_xml_file"' RETURN` for cleanup — follow this pattern (trap on `RETURN`, not `EXIT`) for any other function-scoped temp file.

## No tests

There is no test harness (no bats, no shellcheck config beyond the `# shellcheck shell=bash` / `# shellcheck disable=...` directive comments already in each file). Validate changes by sourcing the affected file from within a consumer repo (e.g. `forge`) that has the `bash-logger-adapter/adapter.sh` shim available, or by running `shellcheck` directly against the file.
