# shellcheck shell=bash
#
# Bootstraps a script that uses bashkit: turns on strict shell options and
# defines `import`, which loads library files and whole packages by name,
# each at most once.
#
#   . "<bashkit>/local/lib/bashkit/os/bk-bootstrap.sh"
#   import core/contract-utils virsh   # from bashkit's library
#   import ./helpers                   # beside the calling script
#
# Source this file first, and nothing from bashkit before it. `import` only
# knows the files that were loaded after this one, so a library sourced
# earlier is loaded a second time and fails on its read-only guard.
#
# Sourcing this file changes the calling shell:
#
#   - It sets nounset, errexit and pipefail, and a PS4 that shows the file,
#     line and function under xtrace.
#   - `source` and `.` become aliases for os::import_one in every file parsed
#     afterwards. A file that a library sources itself is recorded that way,
#     and a later `import` doesn't load it again.
#
# Imported files are sourced from inside a function, so one that declares a
# global at its top level must use `declare -g` or `readonly`. A plain
# `declare` or `typeset` there makes a variable that is gone once the file
# has loaded.
#
# Based on: https://raw.githubusercontent.com/niieani/bash-oo-framework/3c0291e2ace410c2d9068b82a5598164e7b49cf3/lib/oo-bootstrap.sh
# * Reference: https://github.com/niieani/bash-oo-framework/tree/master

########################
### INITIALIZE SYSTEM ###
########################

[[ "${__bk__bootstrapped:-}" != "true" ]] || return 0

# From: http://wiki.bash-hackers.org/scripting/debuggingtips
export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error inside pipes, e.g. mysqldump | gzip
set -o nounset \
  -o errexit \
  -o pipefail \
  -o hashall

shopt -s expand_aliases

# `declare -g` comes before each assignment: a plain `declare` makes the
# variable local when this file is sourced from inside a function, and the
# value is then lost when that function returns.
declare -g __bk__lib_path
# dirname, not ${BASH_SOURCE[0]%/*}: that leaves the file name itself when
# this file is sourced by a path with no slash in it.
__bk__lib_path="$(dirname -- "${BASH_SOURCE[0]}")"
__bk__lib_path="$(CDPATH='' cd -- "${__bk__lib_path}" && pwd)"
declare -g __bk__path="${__bk__lib_path%/*}"
# Every file and URL that was imported, in the order they were first loaded,
# and the same paths as keys, which is what a lookup uses.
declare -ag __bk_imported_files=()
declare -gA __bk__imported_index=()
# The physical path of every directory os::_dir_resolve has resolved, keyed
# by the absolute path it was asked for.
declare -gA __bk__dir_cache=()
# What the last os::_dir_resolve or os::_file_resolve call resolved its
# operand to.
declare -g __bk__resolved_path=""

declare -g __bk__fd_path
__bk__fd_path="$(dirname <(echo))"
declare -gi __bk__fd_length=$(( ${#__bk__fd_path} + 1 ))

###########################
### BOOTSTRAP FUNCTIONS ###
###########################

# os::namespace()
#
# Does nothing. A stub kept from the upstream bootstrap, for when its
# logging library isn't loaded.
#
# Globals:
#   None.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   Always 0.
os::namespace() { :; }

# os::_echo_stderr(message...)
#
# What os::print_stack_trace writes with while bash-logger isn't loaded.
#
# Globals:
#   None.
# Arguments:
#   $@   The message; the operands are joined with spaces.
# Outputs:
#   The message to stderr.
# Returns:
#   The status of `echo`.
os::_echo_stderr() {
  echo "$*" 1>&2
}

# os::print_stack_trace([message])
#
# Writes <message>, if given, and then the current bash call stack to
# stderr, deepest frame first, starting at this function's caller. Each
# frame reads "at FUNCNAME (BASH_SOURCE:line)", where "line" is the line in
# that frame where it called into the next-deeper frame.
#
# The lines go through bash-logger's log_error once it is loaded, and
# straight to stderr before that. They are collected first and written in a
# single write(2), so the report stays in one piece when other processes
# write to the same stderr. Pass the error as <message> instead of printing
# it separately, so it can't be separated from its trace.
#
# Ported from core::print_stack_trace (core/logger-utils.sh), which needs
# files this one is sourced before.
#
# Globals:
#   FUNCNAME, BASH_SOURCE, BASH_LINENO
# Arguments:
#   $@   Optional. The error message; the operands are joined with spaces.
# Outputs:
#   The message and the call stack to stderr, one frame per line.
# Returns:
#   Always 0.
os::print_stack_trace() {
  local logger="os::_echo_stderr"
  if declare -F log_error > /dev/null; then
    logger="log_error"
  fi
  readonly logger

  # Only stderr is captured; fd 3 keeps stdout as it was, because
  # bash-logger's `color = auto` tests whether stdout is a terminal.
  local -i i
  local report
  {
    report="$(
      {
        if (( $# > 0 )); then
          "${logger}" "$*"
        fi
        "${logger}" "Stack trace (most recent call first):"
        for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
          "${logger}" \
            "  at ${FUNCNAME[i]} (${BASH_SOURCE[i]:-}:${BASH_LINENO[i - 1]:-})"
        done
      } 2>&1 1>&3
    )"
  } 3>&1
  readonly report

  # Not printf/echo: bash's builtins flush at every newline, which would be
  # one write per line again. `cat` copies the here-string in one write.
  if [[ -n "${report}" ]]; then
    cat >&2 <<<"${report}"
  fi
  return 0
}

# os::throw(message...)
#
# Reports a failure and returns non-zero. It writes
# "<caller>() - Exception: <message>" and the call stack to stderr as one
# block (os::print_stack_trace). Follow it with `|| return`, so that the
# calling function passes the status on:
#
#   [[ -f "${file}" ]] || { os::throw "file not found: ${file}" || return; }
#
# The status is 1. Set ${r} for the call to return another one:
#
#   r=2 os::throw "Unable to load ${file}" || return
#
# Globals:
#   r   Read only. The status to return. A value that isn't a whole number
#       from 1 to 255 is ignored: ${r} may just as well be an unrelated
#       variable of the calling script, and a failure must never return 0.
# Arguments:
#   $@   The message; the operands are joined with spaces.
# Outputs:
#   The message and a stack trace to stderr.
# Returns:
#   ${r} when it is a whole number from 1 to 255; 1 otherwise.
os::throw() {
  os::print_stack_trace "${FUNCNAME[1]:-main}() - Exception: $*"

  if [[ "${r:-}" =~ ^[1-9][0-9]{0,2}$ ]] && (( r <= 255 )); then
    return "${r}"
  fi
  return 1
}

# os::_import_is_recorded(path)
#
# Tests whether <path> was imported. A lookup by key, because this runs for
# every file each time an import reaches it: scanning the list of imported
# files instead took longer with every file that was loaded.
#
# Globals:
#   __bk__imported_index   Read only.
# Arguments:
#   $1   A resolved path or a URL.
# Outputs:
#   None.
# Returns:
#   0 if <path> is recorded; 1 if it isn't.
os::_import_is_recorded() {
  local -r path="${1:-}"

  [[ -n "${path}" && -n "${__bk__imported_index["${path}"]:-}" ]]
}

# os::_import_record(path)
#
# Records <path> as imported. A file is recorded before it is sourced, so
# that a circular import ends; os::_import_forget undoes it when the file
# then fails to load.
#
# Globals:
#   __bk_imported_files    <path> is appended, unless it is already there.
#   __bk__imported_index   <path> is added as a key.
# Arguments:
#   $1   A resolved path or a URL.
# Outputs:
#   None.
# Returns:
#   Always 0.
os::_import_record() {
  local -r path="${1:-}"

  if [[ -n "${path}" ]] && ! os::_import_is_recorded "${path}"; then
    __bk_imported_files+=("${path}")
    __bk__imported_index["${path}"]="true"
  fi
  return 0
}

# os::_import_forget(path)
#
# Undoes os::_import_record, so that a file that failed to load doesn't look
# imported afterwards.
#
# Globals:
#   __bk_imported_files    Entries equal to <path> are unset.
#   __bk__imported_index   <path> is emptied. It is not unset: `unset` of a
#                          key that holds quotes or brackets is not reliable
#                          across bash versions.
# Arguments:
#   $1   The recorded path or URL.
# Outputs:
#   None.
# Returns:
#   Always 0.
os::_import_forget() {
  local -r path="${1:-}"

  [[ -n "${path}" ]] || return 0

  local -i i
  for i in "${!__bk_imported_files[@]}"; do
    if [[ "${__bk_imported_files[i]}" == "${path}" ]]; then
      unset -v '__bk_imported_files[i]'
    fi
  done
  __bk__imported_index["${path}"]=""
  return 0
}

# os::source_http(url [retries [operand...]])
#
# Downloads a script with curl, or with wget when curl isn't installed, and
# sources it. A <url> that ends in neither .sh nor .bash is tried again as
# <url>.sh when its download fails.
#
# The script is downloaded in full before any of it is sourced. Sourcing the
# download as it streams runs the first part of a script whose download then
# fails, and can only report that failure from inside the sourced text,
# where it ends an errexit shell before the caller can handle it.
#
# Globals:
#   __bk__allow_file_reloading   Read only. Unless it is "true", a <url>
#                                that was already imported is skipped.
#   __bk_imported_files, __bk__imported_index
#                                <url> is recorded.
# Arguments:
#   $1   The http:// or https:// URL of the script.
#   $2   Optional. How many times to retry a failed download. Defaults to 3.
#   $@   Optional. Operands for the script, which it sees as $1, $2, ...
# Outputs:
#   An error and stack trace when the download or the script fails.
# Returns:
#   0 when the script was sourced or was already imported; 1 when an operand
#   is invalid or the download failed; 2 when the script was downloaded and
#   failed to load.
os::source_http() {
  [[ -n "${1:-}" ]] || { os::throw "url=\$1 cannot be empty." || return; }
  local -r url="$1"
  [[ "${2:-3}" =~ ^[0-9]+$ ]] || {
    os::throw "retries=\$2 must be a whole number: ${2}" || return
  }
  local -r retries="${2:-3}"
  # $2 is optional, and `shift 2` shifts nothing when only $1 is given.
  shift "$(( $# > 1 ? 2 : 1 ))"

  if [[ "${__bk__allow_file_reloading:-}" != "true" ]] \
    && os::_import_is_recorded "${url}"; then
    return 0
  fi

  local -a fetch
  if hash curl 2>/dev/null; then
    fetch=(
      curl
      --fail
      -sL
      --retry "${retries}"
    )
  else
    fetch=(
      wget
      -t "${retries}"
      -O -
      -o /dev/null
    )
  fi
  readonly fetch

  local script
  if ! script="$("${fetch[@]}" "${url}")"; then
    if [[ "${url}" == *'.sh' || "${url}" == *'.bash' ]] \
      || ! script="$("${fetch[@]}" "${url}.sh")"; then
      os::throw "Cannot import ${url}" || return
    fi
  fi
  readonly script

  os::_import_record "${url}"
  builtin source <(printf '%s\n' "${script}") "$@" && return 0

  os::_import_forget "${url}"
  r=2 os::throw "Unable to load ${url}" || return
}

# os::source_path(lib_path [operand...])
#
# Sources what is at one location: every *.sh file of a directory, or
# otherwise the first of <lib_path>, <lib_path>.sh and <lib_path>.bash that
# is a file. Nothing being there is not an error, because os::import_one
# calls this for each location it searches.
#
# Globals:
#   None.
# Arguments:
#   $1   The directory, or the file with or without its extension.
#   $@   Optional. Operands for each file, which it sees as $1, $2, ...
# Outputs:
#   An error and stack trace when a file fails to load.
# Returns:
#   0 when the file, or every file of the directory, was sourced or was
#   already imported; 1 when <lib_path> is empty or nothing was found; 2
#   when a file was found and failed to load.
os::source_path() {
  [[ -n "${1:-}" ]] || {
    os::throw "lib_path=\$1 cannot be empty." || return
  }
  local -r lib_path="$1"
  shift

  if [[ -d "${lib_path}" ]]; then
    local file
    for file in "${lib_path}"/*.sh; do
      os::source_file "${file}" "$@" || return
    done
  else
    local path
    for path in "${lib_path}"{,.sh,.bash}; do
      os::source_file "${path}" "$@" && return 0
      # Only "not found" (1) moves on to the next spelling. A file that was
      # found and failed to load has been reported where it failed.
      (( $? == 1 )) || return 2
    done

    return 1
  fi
}

# os::import_one(lib_path [operand...])
#
# Finds one library file or package and sources it. <lib_path> is one of:
#
#   - a file, with or without its .sh or .bash extension;
#   - a directory, of which every *.sh file is sourced;
#   - an http:// or https:// URL, or github:<owner>/<repo>/<ref>/<path> for a
#     file on raw.githubusercontent.com;
#   - a pipe or device, such as `<(cmd)` or /dev/stdin, which is handed to
#     the `source` builtin as it is.
#
# A bare name, such as `virsh` or `core/contract-utils`, is searched for in
# these places, and the first one that has it is used:
#
#   1. bashkit's library directory, and then this file's directory, os/;
#   2. beside the calling script;
#   3. beside the file that is being imported right now, if there is one,
#      or at its URL when that file was downloaded;
#   4. in the working directory.
#
# bashkit comes first so that `import core` can't be answered by a core/
# directory that happens to sit beside the script or in the working
# directory. A script names its own files with a leading ./ or ../
# (`import ./helpers`): for those, bashkit's directories are searched last
# instead of first. A <lib_path> that starts with / is used as it is.
#
# The `source` and `.` aliases call this function with reloading allowed.
# os::import and `import` call it to load a file once.
#
# Globals:
#   __bk__import_parent          Read only. The directory or URL of the file
#                                being imported right now.
#   __bk__allow_file_reloading   Read only. Unless it is "true", a file that
#                                was already imported is skipped.
#   __bk__fd_path, __bk__fd_length, __bk__lib_path, __bk__path, BASH_SOURCE
# Arguments:
#   $1   What to import; see above.
#   $@   Optional. Operands for the file, which it sees as $1, $2, ... They
#        are not passed on to a URL.
# Outputs:
#   An error and stack trace when nothing was found or a file failed to
#   load.
# Returns:
#   0 when <lib_path> was sourced or was already imported; 1 when it is
#   empty or wasn't found; 2 when it was found and failed to load. For a
#   pipe or device, the status of the `source` builtin.
os::import_one() {
  [[ -n "${1:-}" ]] || {
    os::throw "lib_path=\$1 cannot be empty." || return
  }
  local lib_path="$1"
  local __bk__import_parent="${__bk__import_parent:-}"
  local requested_path="${lib_path}"
  shift

  # A pipe or device (`source <(cmd)`, /dev/stdin) has no location to resolve
  # or to record, and the `source` and `.` aliases send those here too.
  if [[ -e "${lib_path}" && ! -f "${lib_path}" && ! -d "${lib_path}" ]]; then
    builtin source "${lib_path}" "$@"
    return
  fi

  # TODO update this with a regex test =~
  if [[ "${requested_path}" == 'github:'* ]]; then
    requested_path="https://raw.githubusercontent.com/${requested_path:7}"
  # TODO update this with a regex test =~
  elif [[ "${requested_path}" == './'* ]]; then
    requested_path="${requested_path:2}"
  # TODO update this with a regex test =~
  # starts with /dev/fd/: a path built from the BASH_SOURCE of a file that
  # os::source_http sourced
  elif [[ "${requested_path}" == "${__bk__fd_path}/"* ]]; then
    requested_path="${requested_path:${__bk__fd_length}}"
  fi

  # [[ "$__bk__import_parent" == 'http://'* || "$__bk__import_parent" == 'https://'* ]] &&
  # TODO update this with a single regex test =~
  # Without a parent there is nothing to resolve against, and prefixing an
  # empty one would search the filesystem root.
  if [[ -n "${__bk__import_parent}" \
    && "${requested_path}" != '/'* \
    && "${requested_path}" != 'http://'* \
    && "${requested_path}" != 'https://'* ]]; then
    requested_path="${__bk__import_parent}/${requested_path}"
  fi

  # The parent script is the first caller defined outside this file.
  # BASH_SOURCE[1] is this file whenever the call came through os::import.
  local caller=""
  for caller in "${BASH_SOURCE[@]:1}"; do
    [[ "${caller}" == "${BASH_SOURCE[0]}" ]] || break
  done
  # Parameter expansion, not dirname: this runs for every import, and for
  # every `source` and `.` once the aliases exist.
  local caller_dir="."
  if [[ "${caller}" == */* ]]; then
    caller_dir="${caller%/*}"
  fi
  readonly caller_dir

  # try relative to parent script
  # try with parent
  # try without parent
  local -a search_paths
  # TODO update this with a single regex test =~
  if [[ "${requested_path}" == 'http://'* \
    || "${requested_path}" == 'https://'* ]]; then
    search_paths=("${requested_path}")
  elif [[ "${lib_path}" == '/'* ]]; then
    # An absolute path is not relative to any directory.
    search_paths=("${requested_path}" "${lib_path}")
  else
    search_paths=(
      "${caller_dir}/${lib_path}"
      "${requested_path}"
      "${lib_path}"
    )
  fi

  # try local library
  # try global library
  # bashkit's own directories come first for a bare name and last for ./ and
  # ../, which name the calling script's own files. An absolute path or a
  # URL is not looked for in them at all.
  local -ra library_paths=(
    "${__bk__path}/${lib_path}"
    "${__bk__lib_path}/${lib_path}"
  )
  case "${lib_path}" in
    '/'* | 'http://'* | 'https://'* | 'github:'*) ;;
    './'* | '../'*) search_paths+=("${library_paths[@]}") ;;
    *) search_paths=("${library_paths[@]}" "${search_paths[@]}") ;;
  esac
  readonly search_paths

  local search_path
  for search_path in "${search_paths[@]}"; do
    # A URL ends the search: it is downloaded or it isn't.
    # TODO update this with a single regex test =~
    if [[ "${search_path}" == 'http://'* \
      || "${search_path}" == 'https://'* ]]; then
      __bk__import_parent="${search_path%/*}" \
        os::source_http "${search_path}"
      return
    fi

    os::source_path "${search_path}" "$@" && return 0
    # Only "not found" (1) moves on to the next location. A file that was
    # found and failed to load has been reported where it failed, and a
    # later location is often the same file.
    (( $? == 1 )) || return 2
  done

  os::throw "Cannot import ${lib_path}" || return
}

# os::import(lib_path...)
#
# Imports each <lib_path> with os::import_one. A file that was already
# imported isn't sourced again, whichever spelling of its path it was
# imported by. Stops at the first <lib_path> that fails.
#
# Globals:
#   __bk__allow_file_reloading   Set to "false" for each os::import_one call.
# Arguments:
#   $@   What to import; see os::import_one. Operands can't be passed to the
#        files: call os::import_one for that.
# Outputs:
#   An error and stack trace for the <lib_path> that failed.
# Returns:
#   0 when every <lib_path> was sourced or was already imported; otherwise
#   the status of the os::import_one call that failed.
os::import() {
  local lib_path
  for lib_path in "$@"; do
    __bk__allow_file_reloading=false os::import_one "${lib_path}" || return
  done
}

# import(lib_path...)
#
# os::import under the name scripts call it by: `import core virsh`.
#
# It is a function rather than an alias. Bash expands an alias only in code
# it parses after the alias was defined, so an alias would be missing from
# every function that was defined before this file was sourced, where
# `import` would run ImageMagick's import(1) instead.
#
# Globals:
#   None.
# Arguments:
#   $@   What to import; see os::import_one.
# Outputs:
#   An error and stack trace for the <lib_path> that failed.
# Returns:
#   The status of os::import.
import() {
  os::import "$@"
}

# os::_dir_resolve(dir)
#
# Resolves the absolute path of an existing directory to its physical path,
# with `.`, `..` and symlinks resolved, and stores it in
# __bk__resolved_path.
#
# It works without a subshell, one path component at a time: the physical
# path of <dir> is that of its parent with its own name added, unless <dir>
# is itself a symlink. Only a symlink is resolved the slow way, by a
# `cd -P` in a subshell. Each result is cached, so a directory and all of
# its parents are worked out once.
#
# Globals:
#   __bk__resolved_path   Set to the physical path; empty on failure.
#   __bk__dir_cache       Read, and added to.
# Arguments:
#   $1   The directory. It must be an absolute path and exist; that it
#        exists is not checked.
# Outputs:
#   None.
# Returns:
#   0 when <dir> was resolved; 1 when it isn't an absolute path, or a
#   symlink in it can't be entered.
os::_dir_resolve() {
  local -r dir="${1:-}"

  __bk__resolved_path=""
  # A path with no slash has no shorter parent to go on to.
  [[ "${dir}" == '/'* ]] || return 1

  __bk__resolved_path="${__bk__dir_cache["${dir}"]:-}"
  if [[ -n "${__bk__resolved_path}" ]]; then
    return 0
  fi

  local parent="${dir%/*}"
  # empty when ${dir} sits in the root directory
  parent="${parent:-/}"
  readonly parent
  local -r name="${dir##*/}"

  local resolved
  if [[ "${dir}" == '/' ]]; then
    resolved="/"
  elif [[ -z "${name}" || "${name}" == '.' ]]; then
    # A trailing or doubled slash, or `.`: the parent itself.
    os::_dir_resolve "${parent}" || return
    resolved="${__bk__resolved_path}"
  elif [[ "${name}" == '..' ]]; then
    os::_dir_resolve "${parent}" || return
    resolved="${__bk__resolved_path%/*}"
    # The parent of a top-level directory, and of the root, is the root.
    resolved="${resolved:-/}"
  else
    os::_dir_resolve "${parent}" || return
    resolved="${__bk__resolved_path%/}/${name}"
    # Tested, and entered, by its parent's physical path and not as ${dir}:
    # bash keeps a leading `//` in what `pwd` prints, and a directory must
    # resolve to one spelling however it was reached.
    if [[ -L "${resolved}" ]]; then
      # The cd runs in a subshell, so the caller's directory and directory
      # stack are left alone.
      resolved="$(CDPATH='' cd -P -- "${resolved}" && pwd -P)" || {
        __bk__resolved_path=""
        return 1
      }
    fi
  fi
  readonly resolved

  __bk__dir_cache["${dir}"]="${resolved}"
  __bk__resolved_path="${resolved}"
}

# os::_file_resolve(file)
#
# Resolves <file> to its absolute path, with `.`, `..` and symlinked
# directories resolved, and stores it in __bk__resolved_path. os::source_file
# compares these paths as strings to tell whether a file was already
# imported, so every spelling of a file's path must resolve to one string.
#
# The result is a variable rather than stdout, and the directory is resolved
# by os::_dir_resolve, because this runs for every file that is imported or
# sourced: a command substitution per call is what made `import` several
# times slower than sourcing the same files directly.
#
# Globals:
#   __bk__resolved_path   Set to the resolved path; empty on failure.
#   __bk__dir_cache       Read, and added to, by os::_dir_resolve.
#   PWD
# Arguments:
#   $1   A relative or absolute path.
# Outputs:
#   None.
# Returns:
#   0 when <file> is a file; 1 when it isn't; 2 when its directory can't be
#   resolved.
os::_file_resolve() {
  local -r file="${1:-}"

  __bk__resolved_path=""
  [[ -f "${file}" ]] || return 1

  local dir="."
  if [[ "${file}" == */* ]]; then
    dir="${file%/*}"
    # empty when ${file} sits in the root directory
    dir="${dir:-/}"
  fi
  # The cache outlives a `cd`, so a relative directory can't be its key.
  if [[ "${dir}" != '/'* ]]; then
    dir="${PWD}/${dir}"
  fi
  readonly dir

  # Nearly every call is for a directory that is already cached, so that case
  # is answered here, without the call.
  __bk__resolved_path="${__bk__dir_cache["${dir}"]:-}"
  if [[ -z "${__bk__resolved_path}" ]]; then
    os::_dir_resolve "${dir}" || return 2
  fi
  __bk__resolved_path="${__bk__resolved_path%/}/${file##*/}"
}

# os::file_get_absolute_path(file)
#
# Prints the absolute path of <file>, with `.`, `..` and symlinked
# directories resolved.
#
# http://stackoverflow.com/questions/3915040/bash-fish-command-to-print-absolute-path-to-a-file
#
# Globals:
#   __bk__resolved_path   Set by os::_file_resolve.
# Arguments:
#   $1   A relative or absolute path to an existing file.
# Outputs:
#   The absolute path on stdout. An error and stack trace on stderr when
#   <file> can't be resolved.
# Returns:
#   0 when the path was printed; 1 when <file> isn't a file or its directory
#   can't be entered.
os::file_get_absolute_path() {
  local -r file="${1:-}"

  local -i status=0
  os::_file_resolve "${file}" || status=$?
  if (( status == 1 )); then
    os::throw "file not found: ${file}" || return
  elif (( status != 0 )); then
    os::throw "failed to cd into the directory of: ${file}" || return
  fi

  printf '%s\n' "${__bk__resolved_path}"
}

# os::wrap_source(lib_path [operand...])
#
# Sources <lib_path> with the `source` builtin, and reports it when that
# fails.
#
# It calls `builtin source` and not a bare `source`. Bash then runs the file
# with errexit in force even while the import itself is being tested by an
# `||` or an `if`, so a failing command in the file ends the shell there, as
# it does in any other errexit script. The error below is reached only when
# the caller has turned errexit off.
#
# Globals:
#   None.
# Arguments:
#   $1   The file to source.
#   $@   Optional. Operands for the file, which it sees as $1, $2, ...
#        Without any, the file sees none.
# Outputs:
#   An error and stack trace when the file fails to load.
# Returns:
#   0 when the file was sourced; 1 when <lib_path> is empty; 2 when the
#   file's last command failed.
os::wrap_source() {
  [[ -n "${1:-}" ]] || {
    os::throw "lib_path=\$1 cannot be empty." || return
  }
  local -r lib_path="$1"
  shift

  builtin source "${lib_path}" "$@" || {
    r=2 os::throw "Unable to load ${lib_path}" || return
  }
}

# os::source_file(lib_path [operand...])
#
# Sources the file <lib_path> and records it as imported, under its resolved
# path. Skips a file that was already imported, unless reloading is allowed.
# <lib_path> not being a file is not an error, because os::source_path calls
# this for each spelling it tries.
#
# Globals:
#   __bk__allow_file_reloading   Read only. Unless it is "true", a file that
#                                was already imported is skipped.
#   __bk_imported_files, __bk__imported_index
#                                The resolved path is recorded.
#   __bk__import_parent          Set to the file's directory while the file
#                                is being sourced.
#   __bk__resolved_path          Set by os::_file_resolve.
# Arguments:
#   $1   The file to source.
#   $@   Optional. Operands for the file, which it sees as $1, $2, ...
# Outputs:
#   An error and stack trace when the file fails to load.
# Returns:
#   0 when the file was sourced or was already imported; 1 when <lib_path>
#   is empty or isn't a file; 2 when it was found and failed to load.
#   Callers keep searching on 1 only.
os::source_file() {
  [[ -n "${1:-}" ]] || {
    os::throw "lib_path=\$1 cannot be empty." || return
  }
  local lib_path="$1"
  shift

  os::_file_resolve "${lib_path}" || return 1
  lib_path="${__bk__resolved_path}"
  readonly lib_path

  ## if already imported let's return
  if [[ "${__bk__allow_file_reloading:-}" != "true" ]] \
    && os::_import_is_recorded "${lib_path}"; then
    return 0
  fi

  # Recorded before it is sourced, so that a circular import ends.
  os::_import_record "${lib_path}"
  __bk__import_parent="${lib_path%/*}" os::wrap_source "${lib_path}" "$@" \
    && return 0

  os::_import_forget "${lib_path}"
  return 2
}

## note: aliases are visible inside functions only if
## they were initialized AFTER they were created
## this is the reason why we have to load files in a specific order
alias source="__bk__allow_file_reloading=true os::import_one"
alias .="__bk__allow_file_reloading=true os::import_one"

# Last, so that this file only counts as sourced once all of it has run.
# `readonly` and not `declare -r`: that would make the variable local when
# this file is sourced from inside a function.
readonly __bk__bootstrapped="true"
