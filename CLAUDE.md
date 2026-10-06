# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`bashkit` (github.com:s-fairchild/bashkit.git) is a standalone library of reusable bash functions and containerized-command wrappers. It has its own git history and is consumed as a **vendored git submodule** by other projects (e.g. at `hack/vendor/bashkit/` inside the `forge` repo). There is no build step or package manifest here; every file is plain bash, sourced directly or run as a wrapper executable.

## Style guide

**Read `docs/STYLEGUIDE.md` before writing or editing any code here.** It makes the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) the baseline and documents every bashkit-specific difference and addition (file naming, namespacing, guard variables, function comment format, operand validation, getopts pattern, logging/secrets, wrapper entry points). Its appendix lists existing files that don't yet conform — don't copy patterns from those. When a convention changes, update `docs/STYLEGUIDE.md` rather than duplicating rules here.

## Sourcing and paths

- Files inside this repo source their siblings **relative to their own location** via `${BASH_SOURCE[0]%/*}/<relative-path>`, so libs and `local/bin/*` wrappers work regardless of the caller's CWD. Never switch to CWD- or repo-root-relative paths.
- Every dependency is sourced behind its double-inclusion guard (`readonly __BASHKIT_LIB_<DIR>_<FILE>_SOURCED="true"`, `__BASHKIT_BIN_<NAME>_SOURCED` for wrappers). Consumers check these names — **never rename a guard** without updating every consumer.
- The one dependency *outside* this repo is the logging library, `bash-logger/logging.sh`, which supplies `init_logger`, `log_debug`/`log_info`/`log_warn`/`log_error`/`log_fatal`/`log_sensitive`, and the `LOG_LEVEL_*` constants. It does **not** define any `ERROR_*` or `BOOLEAN_*` names: bashkit's own are `__BASHKIT_CORE_ERROR_*` (`core/logger-utils.sh`) and `__BASHKIT_CORE_BOOLEAN_*` (`core/boolean-utils.sh`). Note that `log_*` functions print only their first operand. Nothing sources `logging.sh` by path; files call `core::logger_init` from `core/logger-utils.sh`, which does nothing if `init_logger` is already defined and otherwise sources the first `logging.sh` it finds, in this order:
  1. `vendor/bash-logger/` — this repo's own submodule (`git submodule update --init`)
  2. `../bash-logger/` beside this repo — a copy vendored next to bashkit (e.g. forge's `hack/vendor/bash-logger/`)
  3. `~/.local/lib/bash-logger/`
  4. `/usr/local/lib/bash-logger/`
  5. `/usr/lib/bash-logger/`

  Before sourcing, it rejects a `BASHKIT_VERBOSE` or `BASHKIT_QUIET` that isn't a boolean (`core::bool_is_valid`) and resolves the config file, so a bad environment fails without leaving a half-loaded logger. It then calls `init_logger` with, in order: `--verbose` / `--quiet` when `BASHKIT_VERBOSE` / `BASHKIT_QUIET` are true; `--level "${BASHKIT_LEVEL}"` when set (after `--verbose`, so it wins); `--config <file>` when the environment picks one; `--log "${BASHKIT_LOG_FILE}"` when set; `--name <calling file>`; `--stderr-level DEBUG`; then its own operands, which override everything before them. The config file is `BASHKIT_LOG_CONFIG` (explicit path), else `logging-${BASHKIT_ENV}.conf`, else `logging.conf`. The first directory that has it wins: `BASHKIT_LOG_CONFIG_DIR` (if set), this repo's `.bashkit/` (`dev`, `test`, `ci`, `staging`, `prod`), `../../etc/bashkit` relative to this repo (e.g. forge's `hack/etc/bashkit/`), `${XDG_CONFIG_HOME:-~/.config}/bashkit`, `/usr/local/etc/bashkit`, then `/etc/bashkit`. Installed copies have neither repo-relative directory, so they use the user and system directories. A `BASHKIT_ENV` with no matching file anywhere is a hard error. Shipped configs never set `log_file`, because bash-logger requires it to be absolute and consumers would inherit it.
- `core/logger-utils.sh` and `core/boolean-utils.sh` run before the logger exists, so they must not use the logging API unguarded or source anything else (in particular not `contract-utils.sh`, which sources `logger-utils.sh` and calls `core::logger_init` on load). They source each other; `boolean-utils.sh` points its `# shellcheck source=` directive at `/dev/null` because ShellCheck takes 20s+ per file following that cycle — don't change it back.
- `os/bk-bootstrap.sh` is the entry point for scripts that load libraries by name. A script sources it first, with nothing from bashkit before it, and then calls `import core/contract-utils virsh` (a file, with or without `.sh`, or a whole directory). A bare name like those is looked for in bashkit's library first; a script imports its own files as `import ./name`. It sets `nounset`, `errexit` and `pipefail` in the calling shell, and aliases `source` and `.` to `os::import_one` in every file parsed afterwards; that is how the files a library sources itself get recorded, so that `import` loads each file once. Imported files run inside a function, so a library that declares a global at its top level needs `declare -g` or `readonly`. The file's header comment and the comment on `os::import_one` describe the search order.
- bashkit only *reads* `BASHKIT_ENV`, `BASHKIT_LOG_FILE`, `BASHKIT_LOG_CONFIG`, `BASHKIT_LOG_CONFIG_DIR`, `BASHKIT_VERBOSE`, `BASHKIT_QUIET`, and `BASHKIT_LEVEL`; never set them inside a library. Development sets them through the committed `.envrc` (direnv, defaults to `dev`), CI through the workflow's `env:`, and consumers through their own environment. Anything that supplies a fallback uses `${BASHKIT_ENV:-default}`, so an outer value always wins.

## Structure

```
.bashkit/               # shipped bash-logger configs: logging-{dev,test,ci,staging,prod}.conf
.envrc                  # direnv: BASHKIT_ENV defaults to dev, BASHKIT_LOG_FILE to .log/${BASHKIT_ENV}.log
.log/                   # local log files; only its .gitignore is tracked
vendor/bash-logger/     # bash-logger submodule (the logging API every file depends on)
test/                   # behavior tests: test-utils.sh (harness), <dir>/<file>-test.sh, <dir>/<file>-bench.sh
local/
  bin/                  # wrapper executables; runnable directly OR sourceable (see core/bin-utils.sh)
    bw                  # flatpak Bitwarden CLI passthrough
    coreos-installer    # quay.io/coreos/coreos-installer via podman (getopts -s secret / -m mount)
    envsubst            # envsubst via podman
    yq                  # docker.io/mikefarah/yq via podman
  lib/bashkit/
    array/              # array::* — contains (literal membership test)
    core/               # core::*  — contract-utils (fail, require_operands, require_pipestatus,
                        #            require_nameref, is_option_arg_dup, with_xtrace_suppressed),
                        #            boolean-utils (bool_is_valid, bool_is_true,
                        #            __BASHKIT_CORE_BOOLEAN_* constants), logger-utils (logger_init,
                        #            logger_resolve, print_stack_trace, __BASHKIT_CORE_ERROR_*
                        #            constants), file-utils, sha512sum-utils, yq-utils,
                        #            bin-utils (sources local/bin/*)
    ignition/           # ignition::* — butane, merge (butane -> ignition JSON), validate, serve
    k3s/                # k3s::*   — cluster token generation
    kube/               # kube::*  — kubectl wait/apply/create/delete, kustomize build/build_apply
    openssl/            # openssl::* — private key / self-signed cert generation
    os/                 # os::*    — bk-bootstrap (strict shell options; import / os::import,
                        #            os::import_one, os::source_http, os::throw, os::print_stack_trace)
    podman/             # podman::* — container, secret, volume, build helpers
    virsh/              # virsh::* — domain, network, pool/volume wrappers and *_is_* predicates
```

Most directories have an umbrella file named after them (`core/core.sh`, `virsh/virsh.sh`, …) that just sources every leaf file in that directory behind its guard. Umbrella files are optional: `array/` and `os/` have none, because `import` loads a leaf file or a whole directory by name. Where one exists, add new leaf files to it. Functions are namespaced by directory (`<dir>::<noun>_<verb>`).

## Install

```bash
make install
```

Copies `local/bin/*` to `~/.local/bin/` and recursively installs `local/lib/bashkit/**` (mode 644) into `~/.local/lib/bashkit/`, preserving subdirectories. It also copies `.bashkit/*.conf` into `${XDG_CONFIG_HOME:-~/.config}/bashkit/`, skipping any file already there so local edits survive (delete a file to get the shipped version again). Installed copies find `bash-logger` at `~/.local/lib/bash-logger/`, `/usr/local/lib/bash-logger/`, or `/usr/lib/bash-logger/` (see *Sourcing and paths*); `make install` doesn't install it.

## Linting and validation

Behavior tests are plain bash (no bats) in `test/`: `make test` runs every `test/<dir>/<file>-test.sh`, each of which can also be run on its own. `test/test-utils.sh` is the harness; a case is a script that runs in its own bash process and empty directory. Only `os/bk-bootstrap.sh` and `array/contains.sh` have tests so far. Lint with `make lint`, which runs `shellcheck` over every shell file using the checked-in `.shellcheckrc`; `.lefthook.yaml` runs the same check on staged files as a pre-commit hook (`lefthook install`). The `linting-code` skill (`.claude/skills/linting-code/SKILL.md`) explains the enabled optional checks, how to lint from a consumer repo, and which `SC1091` findings to expect. For a file with no test, validate runtime behavior by sourcing it directly once `vendor/bash-logger` is initialized, or behind a minimal stub of the logging API.
