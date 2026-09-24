# bashkit

A standalone library of reusable bash functions and containerized-command
wrappers. There is no build step, package manifest, or test suite — every
file is plain bash, sourced directly or run as a wrapper executable.

`bashkit` is designed to be **vendored as a git submodule** into a consuming
project (e.g. under `hack/vendor/bashkit/`). Every file here depends on the
logging API from [`bash-logger`](https://github.com/s-fairchild/bash-logger)'s
`logging.sh`:

- `init_logger`
- `log_debug`, `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_sensitive`
- the `ERROR_*` and `BOOLEAN_*` constants

Every file inside this repo sources its own siblings via
`${BASH_SOURCE[0]%/*}/<relative-path>`, so `local/bin/*` wrappers and
`local/lib/bashkit/**/*.sh` libraries work correctly regardless of the
caller's CWD. If `init_logger` isn't already defined, `core::logger_init`
(`core/logger-utils.sh`) sources the first `logging.sh` it finds:

1. `vendor/bash-logger/` — bashkit's own submodule. Consumers need
   `git submodule update --init --recursive` to check it out.
2. `~/.local/lib/bash-logger/`
3. `/usr/local/lib/bash-logger/`

If a consumer loads and initializes `bash-logger` itself before sourcing
bashkit, bashkit uses that setup as-is and ignores everything in
[Logging configuration](#logging-configuration).

## Logging configuration

`core::logger_init` passes `init_logger --config <file>` when the
environment selects a config file:

1. `BASHKIT_LOG_CONFIG=/path/to/file.conf`: that exact file.
2. `BASHKIT_ENV=<name>`: `logging-<name>.conf`.
3. Neither set: `logging.conf`, if there is one; otherwise bash-logger's
   defaults.

It looks for the file in these directories and uses the first match, so an
earlier directory overrides a later one:

1. `BASHKIT_LOG_CONFIG_DIR`, if set
2. bashkit's own [`.bashkit/`](.bashkit/): the `dev`, `test`, `ci`, `staging`,
   and `prod` configs shipped in this repo
3. `${XDG_CONFIG_HOME:-~/.config}/bashkit` (user; `make install` copies
   `.bashkit/` here)
4. `/usr/local/etc/bashkit` (local system)
5. `/etc/bashkit` (system)

A checkout or vendored copy of bashkit always finds its own `.bashkit/`
first, so for the shipped environment names the user and system directories
only matter to installed copies (`make install`), which have no `.bashkit/`
beside them. To override a shipped config from a consumer repo, use
`BASHKIT_LOG_CONFIG_DIR`.

Setting `BASHKIT_ENV` to a name that has no `logging-<name>.conf` in any of
these directories is an error. Every log level always goes to stderr, whatever
the config says, so log lines never end up in a caller's `$(...)` capture.

### Setting `BASHKIT_ENV`

bashkit never sets `BASHKIT_ENV`; it only reads it. Set it from outside, as
close to where the code runs as possible:

- **Developing bashkit:** the committed [`.envrc`](.envrc) sets `dev` for
  [direnv](https://direnv.net/). Install direnv, add its hook to your shell,
  and run `direnv allow` once in the repo. Avoid exporting it from
  `~/.bashrc`, which would apply to every project on the machine.
- **CI (GitHub Actions):** set it in the workflow:

  ```yaml
  env:
    BASHKIT_ENV: ci
  ```

- **Consumers:** set it the same ways in your own repo (your own `.envrc`,
  your own workflow `env:`). Put your own `logging-<name>.conf` files in a
  directory and point `BASHKIT_LOG_CONFIG_DIR` at it. Any environment you
  don't provide a file for falls back to bashkit's `.bashkit/`. An entry
  script that wants a default should keep outer values overridable:

  ```bash
  export BASHKIT_ENV="${BASHKIT_ENV:-prod}"
  ```

An outer setting always wins: `BASHKIT_ENV=dev ./script` overrides CI or
`.envrc`, which override a script's default.

### Logging to a file

Set `BASHKIT_LOG_FILE` to also write log lines to a file. `core::logger_init`
passes it to `init_logger --log`, which overrides any `log_file` in the config
and creates the file's directory if needed. Unset, logs only go to stderr
(and the journal, if the config enables it).

- **Developing bashkit:** `.envrc` sets it to `.log/${BASHKIT_ENV}.log` in
  the checkout (`.log/dev.log` by default). `.log/` is committed but its
  contents are git-ignored.
- **Consumers:** set it the same way as `BASHKIT_ENV`, or put an absolute
  `log_file = ...` in your own config. A config file's `log_file` must be an
  absolute path, which is why bashkit's shipped configs don't set one.

## Structure

```
local/
  bin/                          # standalone wrapper executables (source+run in one file)
    bw                          # flatpak run --command=bw com.bitwarden.desktop wrapper
    coreos-installer            # runs quay.io/coreos/coreos-installer:release via podman
    envsubst                    # runs docker.io/steve51516/envsubst:latest via podman
    yq                          # runs docker.io/mikefarah/yq via podman
  lib/bashkit/
    core/
      core.sh                   # umbrella loader for this directory
      bin-utils.sh               # sources local/bin/{bw,coreos-installer,yq} for library-style use
      contract-utils.sh          # core::fail, core::require_{operands,pipestatus,nameref},
                                  # core::is_option_arg_dup, core::is_boolean,
                                  # core::with_xtrace_suppressed
      logger-utils.sh            # core::logger_{source,config_path,init,resolve},
                                  # core::print_stack_trace
      file-utils.sh               # core::file_read_builtin, core::file_read_preserve_newlines,
                                  # core::file_parse_extension
      sha512sum-utils.sh          # core::sha512sum wrapper + core::checksum_parse_hash
    ignition/
      ignition.sh                # umbrella loader for this directory
      butane.sh                  # ignition::butane — runs butane in a container
      merge.sh                   # ignition::gen and friends — compiles butane -> ignition JSON,
                                  # inlines merge[] entries with verification hashes
      ignition-validate.sh        # ignition::validate — runs ignition-validate in a container
      serve.sh                   # ignition::serve — containerized nginx server for serving
                                  # ignition configs over HTTPS
    k3s/
      k3s.sh                     # umbrella loader for this directory
      token-utils.sh              # k3s::token_gen{,_openssl,_tr,_shasum} — cluster token generation
                                  # with fallback chain
    openssl/
      openssl.sh                 # umbrella loader for this directory
      cert-utils.sh               # openssl::private_key_gen, openssl::self_signed_cert_gen
    podman/
      podman.sh                  # umbrella loader for this directory
      podman-container.sh         # podman::container — runs a nested podman sharing the host's
                                  # rootless graphroot volume
      podman-secret.sh            # podman::secret_{exists,create_replace_from_stdin,
                                  # create_from_file,showsecret,gen_file_secretsdata,filter_by_label}
      podman-volume.sh            # podman::volume_{exists,create,export_untar_stdout}
      podman-build.sh              # podman::build and helpers for driving podman-build(1)
    virsh/
      virsh.sh                   # umbrella loader for this directory
      virsh-domain.sh             # virsh::domain_{define,undefine,create,start,destroy,
                                  # autostart,is_defined,is_active}
      virsh-network.sh            # virsh::net_{define,activate,destroy,is_defined,is_active,
                                  # is_persistent,is_autostart,autostart,parse_info}
      virsh-pool.sh               # virsh::pool_{define,build,start,autostart,is_defined,is_active},
                                  # virsh::vol_{create,is_present}
```

Each subdirectory's `*.sh` umbrella file (`core.sh`, `podman.sh`, `virsh.sh`,
`ignition.sh`, `k3s.sh`) just sources every leaf file in that directory
behind a double-inclusion guard — source the umbrella file to pull in a
whole group, or a leaf file directly if you only need one piece.

## Installing

```bash
make install
```

Copies `local/bin/*` to `~/.local/bin/`, recursively copies
`local/lib/bashkit/**` to `~/.local/lib/bashkit/` (preserving subdirectory
structure), and copies `.bashkit/*.conf` to
`${XDG_CONFIG_HOME:-~/.config}/bashkit/`. A config that is already installed
is never overwritten, so local edits survive; delete it and re-run
`make install` to get the shipped version again.

`make install` doesn't install `bash-logger`. Installed copies look for it in
`~/.local/lib/bash-logger/` or `/usr/local/lib/bash-logger/`.

## Conventions

Code follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html),
with bashkit-specific differences and additions documented in
[`docs/STYLEGUIDE.md`](docs/STYLEGUIDE.md) — read it before contributing.
In short:

- Functions are namespaced by directory: `core::*`, `virsh::*`, `podman::*`,
  `ignition::*`, `k3s::*`, `openssl::*`.
- Every sourced file guards against double-inclusion with a
  `readonly __BASHKIT_LIB_<NAME>_SOURCED="true"` at the top, checked before
  re-sourcing a dependency — don't rename these without updating every call
  site across every consumer.
- Argument validation goes through `core::require_operands N "$@" || return`
  followed by `local -r x="$1"`, not manual `${1?...}` checks.
- Function entry is logged as the first line of every function:
  `log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"`.
- Anything that could contain secrets (podman `--secret` specs, tokens, file
  contents) is logged with `log_sensitive`, never `log_debug`/`log_info`.
- Thin `virsh`/`podman` wrappers just validate operands and exec the real
  command; `*_is_*` predicate functions parse `virsh ...-info` output and
  return via exit status for direct use in `if`/`&&`.
- A function-scoped temp file is cleaned up with `trap 'rm -f "$file"' RETURN`
  (not `EXIT`).
- Shell libraries (`local/lib/bashkit/**/*.sh`) are not executable; only
  `local/bin/*` wrapper executables are.

## Linting

There is no test harness (no bats, no pre-commit). Lint with:

```bash
make lint
```

This runs `shellcheck` over every shell file using the checked-in
`.shellcheckrc`, which enables optional checks for parts of
`docs/STYLEGUIDE.md`. See `.claude/skills/linting-code/SKILL.md` for details,
including linting from within a consuming repo and the `SC1091` findings to
expect standalone. Validate runtime behavior by sourcing the affected file
directly once `vendor/bash-logger` is checked out
(`git submodule update --init`).
