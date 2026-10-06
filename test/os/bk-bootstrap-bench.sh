#!/bin/bash
#
# Times loading bashkit through os/bk-bootstrap.sh's `import` against sourcing
# the same files directly, and then the steps of an import that has nothing
# left to load. Not a test: `make test` doesn't run it. Run it directly when
# changing the bootstrap:
#
#   test/os/bk-bootstrap-bench.sh
#
# Needs vendor/bash-logger (`git submodule update --init`).

# shellcheck source=../test-utils.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
test::suite_init || exit
# Timings are of loading only: no log file.
unset -v BASHKIT_LOG_FILE

# bench::script_time(label script)
#
# Prints the shortest of ten runs of a bash script, in milliseconds.
#
# Globals:
#   TEST_WORK, EPOCHREALTIME
# Arguments:
#   $1   What the script measures.
#   $2   The script.
# Outputs:
#   The label and the time on stdout.
# Returns:
#   Always 0.
bench::script_time() {
  local -r label="$1"
  local -r script="$2"

  printf '%s\n' "${script}" > "${TEST_WORK}/bench.sh"

  local -i i start elapsed best=0
  for (( i = 0; i < 10; i++ )); do
    start="${EPOCHREALTIME/[.,]/}"
    # A script that fails still took the time it took.
    bash "${TEST_WORK}/bench.sh" > /dev/null 2>&1 || true
    elapsed=$(( ${EPOCHREALTIME/[.,]/} - start ))
    if (( best == 0 || elapsed < best )); then
      best="${elapsed}"
    fi
  done

  printf '  %-46s %4d ms\n' "${label}" "$(( best / 1000 ))"
  return 0
}

declare -a packages=() umbrellas=()
for package in "${TEST_LIB}"/*/; do
  package="${package%/}"
  if [[ -f "${package}/${package##*/}.sh" ]]; then
    umbrellas+=("${package}/${package##*/}.sh")
    packages+=("${package##*/}")
  fi
done
readonly packages umbrellas

echo "Loading ${packages[*]}:"
bench::script_time 'bash alone' ':'
bench::script_time 'sourcing the umbrella files directly' \
  "$(printf '. %q\n' "${umbrellas[@]}")"
bench::script_time 'the bootstrap alone' ". '${TEST_BOOTSTRAP}'"
bench::script_time 'the bootstrap and import' \
  ". '${TEST_BOOTSTRAP}'; import ${packages[*]}"

echo
echo "An import that has nothing left to load, per call:"
test::fixture_write 'steps.sh' <<'STEPS'
. "${TEST_BOOTSTRAP}"
import "$@" 2> /dev/null

# step(label command...)
step() {
  local -r label="$1"
  shift
  local -i n start
  start="${EPOCHREALTIME/[.,]/}"
  for (( n = 0; n < 1000; n++ )); do
    "$@"
  done
  printf '  %-46s %4d us\n' "${label}" \
    "$(( (${EPOCHREALTIME/[.,]/} - start) / 1000 ))"
}

file="${__bk_imported_files[-1]}"
printf '  (%d files are recorded)\n' "${#__bk_imported_files[@]}"
step 'os::_file_resolve, directory already cached' os::_file_resolve "${file}"
step 'os::_import_is_recorded' os::_import_is_recorded "${file}"
step 'import of an absolute path' import "${file}"
step 'import of a library name' import core/contract-utils
STEPS
bash "${TEST_WORK}/steps.sh" "${packages[@]}"
