#!/bin/bash
#
# Behavior tests for the rule that every library file and wrapper can be
# sourced any number of times, and that a second source changes nothing
# (docs/STYLEGUIDE.md §2.1). Run this file directly, or every test file with
# `make test`.

# shellcheck source=../test-utils.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
test::suite_init || exit

# Every library file except the bootstrap, which keeps its guard on purpose
# (see os/bk-bootstrap.sh), and every wrapper, relative to ${TEST_REPO}.
declare -a sourced_files=()
shopt -s globstar
for file in "${TEST_REPO}"/local/lib/bashkit/**/*.sh "${TEST_REPO}"/local/bin/*; do
  [[ "${file}" != */bk-bootstrap.sh ]] || continue
  sourced_files+=("${file#"${TEST_REPO}/"}")
done
readonly sourced_files

######################
### Sourcing again ###
######################

test::case_run \
  'every file: a second source changes no variable or function' 0 \
  'unchanged' <<CASE
cd "${TEST_REPO}"
. "\${TEST_BOOTSTRAP}"
import array core ignition k3s kube openssl podman virsh

# The bootstrap's lookup caches and the shell's own counters change on every
# command, so they are left out.
snapshot() {
  { declare -p; declare -f; } 2>/dev/null \\
    | grep -vE '^declare (-[a-zA-Z-]+ )?(BASH_[A-Z_]*|FUNCNAME|PIPESTATUS|_|RANDOM|SECONDS|SRANDOM|EPOCH[A-Z]*|LINENO|__bk__resolved_path|__bk__dir_cache|file|before|after)='
}

before="\$(snapshot)"
for file in ${sourced_files[*]}; do
  builtin source "\${file}"
done
after="\$(snapshot)"

if [[ "\${before}" == "\${after}" ]]; then
  echo "unchanged"
else
  diff <(printf '%s\n' "\${before}") <(printf '%s\n' "\${after}") >&2
fi
CASE

#####################################
### Sourced before it is imported ###
#####################################

# A file sourced with the builtin, before anything imports it, isn't
# recorded as imported, so the next import loads it a second time.
for file in "${sourced_files[@]}"; do
  test::case_run "sourced, then imported again: ${file}" 0 'loaded' <<CASE
cd "${TEST_REPO}"
. "\${TEST_BOOTSTRAP}"
builtin source "${file}"
import array core ignition k3s kube openssl podman virsh
echo "loaded"
CASE
done

test::summary_print
