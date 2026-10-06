#!/bin/bash
#
# Behavior tests for local/lib/bashkit/os/bk-bootstrap.sh: the bootstrap
# itself, `import` and the `source`/`.` aliases, os::file_get_absolute_path,
# os::throw, os::source_http, and loading the real bashkit packages. Run this
# file directly, or every test file with `make test`.
#
# Nothing here uses the network. os::source_http is tested against stand-ins
# for curl and wget that serve files from the scratch directory.

# shellcheck source=../test-utils.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
test::suite_init || exit

################
### FIXTURES ###
################

test::fixture_write 'app/helper.sh' <<'FIXTURE'
helper_loads=$(( ${helper_loads:-0} + 1 ))
helper_args="$#:$*"
helper_fn() { echo "helper"; }
FIXTURE

test::fixture_write 'app/sub/nested.sh' <<'FIXTURE'
import sibling
nested_fn() { echo "nested"; }
FIXTURE

test::fixture_write 'app/sub/sibling.sh' <<'FIXTURE'
sibling_loads=$(( ${sibling_loads:-0} + 1 ))
FIXTURE

test::fixture_write 'app/only.bash' <<'FIXTURE'
bash_ext=1
FIXTURE

test::fixture_write 'app/failing.sh' <<'FIXTURE'
false
FIXTURE

test::fixture_write 'app/reimport.sh' <<'FIXTURE'
os::import "${TEST_WORK}/app/helper"
FIXTURE

test::fixture_write 'app/cycle-a.sh' <<'FIXTURE'
import cycle-b
cycle_a=1
FIXTURE

test::fixture_write 'app/cycle-b.sh' <<'FIXTURE'
import cycle-a
cycle_b=1
FIXTURE

test::fixture_write 'app/declares.sh' <<'FIXTURE'
declare plain=1
declare -g global=1
readonly constant=1
assigned=1
FIXTURE

test::fixture_write 'app/guarded.sh' <<'FIXTURE'
readonly GUARDED_SOURCED="true"
FIXTURE

# A consumer script that imports its siblings.
test::fixture_write 'app/run.sh' <<'FIXTURE'
. "${TEST_BOOTSTRAP}"
import helper
import ./helper
import sub/nested
echo "loads=${helper_loads} sibling=${sibling_loads} $(helper_fn) $(nested_fn)"
FIXTURE

test::fixture_write 'app/run-source.sh' <<'FIXTURE'
. "${TEST_BOOTSTRAP}"
source helper.sh one two
. ./helper.sh
echo "loads=${helper_loads} args=${helper_args}"
FIXTURE

test::fixture_write 'app/in-function.sh' <<'FIXTURE'
setup() { . "${TEST_BOOTSTRAP}"; }
setup
import helper
echo "lib=${__bk__lib_path##*/} fd=${__bk__fd_path:+set} $(helper_fn)"
FIXTURE

test::fixture_write 'pkg/a.sh' <<'FIXTURE'
pkg_a=1
FIXTURE

test::fixture_write 'pkg/b.sh' <<'FIXTURE'
pkg_b=1
FIXTURE

test::fixture_write 'badpkg/a.sh' <<'FIXTURE'
bad_a=1
false
FIXTURE

test::fixture_write 'badpkg/b.sh' <<'FIXTURE'
bad_b=1
FIXTURE

test::fixture_write 'real/dir/r.sh' <<'FIXTURE'
real_loads=$(( ${real_loads:-0} + 1 ))
FIXTURE

test::fixture_write 'real/other.sh' <<'FIXTURE'
real_other=1
FIXTURE

mkdir -p "${TEST_WORK}/emptypkg"
ln -s real/dir "${TEST_WORK}/link"

# What the stand-ins for curl and wget serve.
test::fixture_write 'www/plain.sh' <<'FIXTURE'
http_plain=$(( ${http_plain:-0} + 1 ))
http_args="$#:$*"
FIXTURE

test::fixture_write 'www/noext.sh' <<'FIXTURE'
http_noext=1
FIXTURE

test::fixture_write 'www/pkg/parent.sh' <<'FIXTURE'
import rel
http_parent=1
FIXTURE

test::fixture_write 'www/pkg/rel.sh' <<'FIXTURE'
http_rel=1
FIXTURE

test::fixture_write 'www/pkg/uses-lib.sh' <<'FIXTURE'
import array/contains
FIXTURE

test::fixture_write 'www/pkg/sibling.sh' <<'FIXTURE'
. "${BASH_SOURCE[0]%/*}/rel.sh"
http_sibling=1
FIXTURE

test::fixture_write 'www/failing.sh' <<'FIXTURE'
http_after=1
false
FIXTURE

test::fixture_write 'www/owner/repo/ref/lib/x.sh' <<'FIXTURE'
http_github=1
FIXTURE

# Logs how it was called to fetch.log, then prints the file under www/ that
# the URL (its last operand) names, or fails as curl --fail does.
test::fixture_write 'stubbin/curl' <<'FIXTURE'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >> "${TEST_WORK}/fetch.log"
url="${!#}"
file="${TEST_WORK}/www/${url#*://*/}"
[[ -f "${file}" ]] || exit 22
cat "${file}"
FIXTURE
chmod +x "${TEST_WORK}/stubbin/curl"

# A PATH with wget and no curl: the stand-in, and the two commands the
# bootstrap and the stand-in run themselves.
mkdir -p "${TEST_WORK}/wgetbin"
cp "${TEST_WORK}/stubbin/curl" "${TEST_WORK}/wgetbin/wget"
for __test_command in cat dirname; do
  __test_command_path="$(command -v "${__test_command}")" || exit
  ln -s "${__test_command_path}" "${TEST_WORK}/wgetbin/${__test_command}"
done

#################
### BOOTSTRAP ###
#################

test::case_run 'bootstrap: defines import and leaves stdin alone' 0 \
  'status=0 fn=import next=line1' $'line1\nline2\n' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=$?
read -r next
echo "status=${status} fn=$(declare -F import) next=${next}"
CASE
test::stderr_is_empty 'bootstrap: prints nothing'

test::case_run 'bootstrap: imports nothing itself' 0 '0 no' <<'CASE'
. "${TEST_BOOTSTRAP}"
echo "${#__bk_imported_files[@]} $(declare -F array::contains || echo no)"
CASE

test::case_run 'import: records a file under its resolved path' 0 \
  "${TEST_LIB}/array/contains.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
printf '%s\n' "${__bk_imported_files[@]}"
CASE

test::case_run 'bootstrap: turns on nounset, errexit and pipefail' 0 \
  'nounset errexit pipefail' <<'CASE'
. "${TEST_BOOTSTRAP}"
on=()
for option in nounset errexit pipefail; do
  if [[ -o "${option}" ]]; then
    on+=("${option}")
  fi
done
echo "${on[*]}"
CASE

test::case_run 'bootstrap: sourcing it again does nothing' 0 'done' <<'CASE'
. "${TEST_BOOTSTRAP}"
. "${TEST_BOOTSTRAP}"
builtin source "${TEST_BOOTSTRAP}"
import "${TEST_BOOTSTRAP}"
declare -F import > /dev/null
echo done
CASE
test::stderr_is_empty 'bootstrap: sourcing it again prints nothing'

test::case_run 'bootstrap: its guard is read-only once it has succeeded' 0 \
  'declare -r __bk__bootstrapped="true"' <<'CASE'
. "${TEST_BOOTSTRAP}"
declare -p __bk__bootstrapped
CASE

test::case_run 'bootstrap: sourced inside a function, it keeps its globals' 0 \
  'lib=os fd=set helper' <<'CASE'
bash "${TEST_WORK}/app/in-function.sh"
CASE

test::case_run 'bootstrap: sourced by a path with no slash in it' 0 \
  'array::contains' <<'CASE'
cd "${TEST_LIB}/os"
. bk-bootstrap.sh
import array/contains
declare -F array::contains
CASE

test::case_run 'bootstrap: with CDPATH exported' 0 'array::contains' <<'CASE'
export CDPATH="${TEST_LIB}:${TEST_WORK}"
cd "${TEST_LIB}" > /dev/null
. os/bk-bootstrap.sh
import array/contains
declare -F array::contains
CASE

test::case_run 'bootstrap: defines only its own global variables' 0 \
  "__bk__bootstrapped __bk__dir_cache __bk__fd_length __bk__fd_path \
__bk__imported_index __bk__lib_path __bk__path __bk__resolved_path \
__bk_imported_files" <<'CASE'
export LC_ALL=C
before="$(compgen -v)"
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/helper" "${TEST_WORK}/pkg"
import nope 2> /dev/null || true
comm -13 <(sort <<< "${before}") <(compgen -v | sort) \
  | grep -vE '^(before$|helper_|pkg_|BASH_|FUNCNAME$|PIPESTATUS$|_$)' \
  | xargs
CASE

test::case_run \
  'bootstrap: the working directory and directory stack are left alone' 0 \
  'same' <<'CASE'
. "${TEST_BOOTSTRAP}"
pushd /tmp > /dev/null
pushd /usr > /dev/null
before="$(dirs -l)"
import "${TEST_WORK}/app/helper"
import nope 2> /dev/null || true
os::file_get_absolute_path nope 2> /dev/null || true
[[ "$(dirs -l)" == "${before}" ]] && echo same
CASE

##############
### IMPORT ###
##############

# `import` is a function: an alias would not be expanded inside main, which
# is parsed before the bootstrap runs, and the external command would run.
test::case_run 'import: works in a function defined before the bootstrap' 0 \
  'helper' <<'CASE'
mkdir bin
printf '#!/bin/bash\necho "the external import command ran"\n' > bin/import
chmod +x bin/import
PATH="${PWD}/bin:${PATH}"
main() {
  . "${TEST_BOOTSTRAP}"
  import "${TEST_WORK}/app/helper"
  helper_fn
}
main
CASE

# A bare name is bashkit's, whatever sits beside the script or in the working
# directory under the same name. ./ names the script's own files.
test::case_run "import: a bare name is bashkit's, ./ is the calling script's" \
  0 "$(printf '%s\n' 'array::contains' 'the script'"'"'s own file')" <<'CASE'
mkdir -p mine/array
echo 'echo "the script'"'"'s own file"' > mine/array/contains.sh
cat > mine/run.sh <<'SCRIPT'
. "${TEST_BOOTSTRAP}"
import array/contains
declare -F array::contains
import ./array/contains
SCRIPT
bash mine/run.sh
CASE

test::case_run \
  'import: a bare name is not looked for in the working directory first' 0 \
  "$(printf '%s\n' 'array::contains' 'from the working directory')" <<'CASE'
mkdir array
echo 'echo "from the working directory"' > array/contains.sh
. "${TEST_BOOTSTRAP}"
import array/contains
declare -F array::contains
import ./array/contains
CASE

test::case_run 'import: a name bashkit does not have is found beside the script' \
  0 'helper' <<'CASE'
mkdir mine
cp "${TEST_WORK}/app/helper.sh" mine/
cat > mine/run.sh <<'SCRIPT'
. "${TEST_BOOTSTRAP}"
import helper
helper_fn
SCRIPT
bash mine/run.sh
CASE

test::case_run 'import: beside the calling script, from another directory' 0 \
  'loads=1 sibling=1 helper nested' <<'CASE'
bash "${TEST_WORK}/app/run.sh"
CASE
test::stderr_is_empty 'import: prints nothing on success'

test::case_run 'import: the calling script was run by a name with no slash' 0 \
  'loads=1 sibling=1 helper nested' <<'CASE'
cd "${TEST_WORK}/app"
bash run.sh
CASE

test::case_run 'import: in the working directory' 0 'helper' <<'CASE'
. "${TEST_BOOTSTRAP}"
cd "${TEST_WORK}"
import app/helper
helper_fn
CASE

test::case_run 'import: an absolute path, and the .sh and .bash extensions' 0 \
  '1 1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/helper.sh" "${TEST_WORK}/app/only"
echo "${helper_loads} ${bash_ext}"
CASE

test::case_run 'import: a bashkit file and a bashkit directory by name' 0 \
  'array::contains' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains array
declare -F array::contains
CASE

test::case_run 'import: one file under several spellings loads once' 0 '1' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/helper" "${TEST_WORK}/app/sub/../helper.sh" \
  "${TEST_WORK}/app/./helper"
cd "${TEST_WORK}/app"
import helper ./helper.sh sub/../helper
echo "${helper_loads}"
CASE

test::case_run 'import: a symlinked directory leads to the same file' 0 '1' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/real/dir/r" "${TEST_WORK}/link/r"
echo "${real_loads}"
CASE

# The resolved directories are cached. A relative one must not be found in
# the cache again after the working directory has changed.
test::case_run 'import: a relative path is resolved again after a cd' 0 \
  'one two' <<'CASE'
mkdir -p one/same two/same
echo 'which=one' > one/same/x.sh
echo 'which=two' > two/same/x.sh
. "${TEST_BOOTSTRAP}"
cd one
import same/x
first="${which}"
cd ../two
import same/x
echo "${first} ${which}"
CASE

test::case_run 'import: a directory name with spaces, brackets and quotes' 0 \
  '1 1' <<'CASE'
dir="a b]c[d\$e'f\"g"
mkdir "${dir}"
echo 'odd=$(( ${odd:-0} + 1 ))' > "${dir}/x.sh"
. "${TEST_BOOTSTRAP}"
import "${PWD}/${dir}/x" "${PWD}/${dir}/./x.sh"
echo "${odd} ${#__bk_imported_files[@]}"
CASE

test::case_run 'import: a directory sources every .sh file in it' 0 '1 1' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/pkg"
echo "${pkg_a} ${pkg_b}"
CASE

test::case_run 'import: a directory with no .sh files is not found' 0 \
  'status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
import "${TEST_WORK}/emptypkg" 2> /dev/null || status=$?
echo "status=${status}"
CASE

test::case_run 'import: files that import each other' 0 '1 1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/cycle-a"
echo "${cycle_a} ${cycle_b}"
CASE

test::case_run 'import: os::import in a sourced file does not reload' 0 '1' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/helper"
source "${TEST_WORK}/app/reimport.sh"
echo "${helper_loads}"
CASE

test::case_run 'import: without operands the file sees none' 0 '0:' <<'CASE'
. "${TEST_BOOTSTRAP}"
set -- outer
import "${TEST_WORK}/app/helper"
echo "${helper_args}"
CASE

test::case_run 'import: what is missing returns 1 and records nothing' 0 \
  'status=1 recorded=0 next=line1' $'line1\n' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
import nope/missing || status=$?
read -r next
echo "status=${status} recorded=${#__bk_imported_files[@]} next=${next}"
CASE
test::stderr_has 'import: what is missing is reported' \
  '^os::import_one\(\) - Exception: Cannot import nope/missing$'

test::case_run 'import: an empty name is an error' 0 'status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
import '' || status=$?
echo "status=${status}"
CASE
test::stderr_has 'import: an empty name is reported' \
  '^os::import_one\(\) - Exception: lib_path=[$]1 cannot be empty\.$'

test::case_run 'import: stops at the first name that fails' 0 \
  'status=1 loads=0' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
import nope "${TEST_WORK}/app/helper" 2> /dev/null || status=$?
echo "status=${status} loads=${helper_loads:-0}"
CASE

test::case_run 'import: a failure ends an errexit script' 1 '' <<'CASE'
. "${TEST_BOOTSTRAP}"
import nope
echo "still running"
CASE

test::case_run 'import: a name is not searched for in the root directory' 0 \
  'status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
import etc/os-release 2> /dev/null || status=$?
echo "status=${status}"
CASE

# errexit stays in force inside an imported file, even under `||`: see
# os::wrap_source.
test::case_run 'import: errexit on, a failing command in the file ends the shell' \
  1 'before' <<'CASE'
. "${TEST_BOOTSTRAP}"
echo before
import "${TEST_WORK}/app/failing" || echo "handled"
echo "still running"
CASE

test::case_run \
  'import: errexit off, a file that fails returns 2 and is forgotten' 0 \
  'first=2 recorded=0 again=2 exceptions=1 reported' <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
import "${TEST_WORK}/app/failing" 2> err
first=$?
recorded=${#__bk_imported_files[@]}
import "${TEST_WORK}/app/failing.sh" 2> /dev/null
again=$?
exceptions="$(grep -c 'Exception:' err)"
reported="$(grep -c "^os::wrap_source() - Exception: Unable to load ${TEST_WORK}/app/failing.sh$" err)"
echo "first=${first} recorded=${recorded} again=${again} exceptions=${exceptions} ${reported/1/reported}"
CASE

test::case_run 'import: errexit off, a directory stops at the file that fails' \
  0 'status=2 b=unset' <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
import "${TEST_WORK}/badpkg" 2> /dev/null
echo "status=$? b=${bad_b:-unset}"
CASE

####################
### source and . ###
####################

test::case_run 'source: reloads, and resolves beside the calling script' 0 \
  'loads=2 args=0:' <<'CASE'
bash "${TEST_WORK}/app/run-source.sh"
CASE

test::case_run 'source: operands reach the file' 0 '2:one two' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
source "${TEST_WORK}/app/helper.sh" one two
echo "${helper_args}"
CASE

test::case_run 'source: a process substitution' 0 'from-pipe arg' <<'CASE'
. "${TEST_BOOTSTRAP}"
source <(echo 'echo "from-pipe $1"') arg
CASE

test::case_run 'source: /dev/stdin' 0 'from-stdin' $'echo from-stdin\n' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
. /dev/stdin
CASE

test::case_run 'source: a file it loaded is not loaded again by import' 0 '1' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
source "${TEST_WORK}/app/helper.sh"
import "${TEST_WORK}/app/helper"
echo "${helper_loads}"
CASE

# A copy of the absolute path under the working directory must not be found
# in place of the file itself.
test::case_run \
  'source: an absolute path is not looked for in the working directory' 0 \
  '1' <<'CASE'
mkdir -p "mirror${TEST_WORK}/app"
echo 'echo MIRROR' > "mirror${TEST_WORK}/app/helper.sh"
cat > mirror/run.sh <<'SCRIPT'
. "${TEST_BOOTSTRAP}"
source "${TEST_WORK}/app/helper.sh"
echo "${helper_loads}"
SCRIPT
cd mirror
bash run.sh
CASE

##################################
### os::file_get_absolute_path ###
##################################

test::case_run 'absolute path: of a relative path' 0 \
  "${TEST_WORK}/app/helper.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
cd "${TEST_WORK}"
os::file_get_absolute_path app/helper.sh
CASE

test::case_run 'absolute path: of a bare file name' 0 \
  "${TEST_WORK}/app/helper.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
cd "${TEST_WORK}/app"
os::file_get_absolute_path helper.sh
CASE

test::case_run 'absolute path: of an absolute path with ..' 0 \
  "${TEST_WORK}/app/helper.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
os::file_get_absolute_path "${TEST_WORK}/app/sub/../helper.sh"
CASE

test::case_run 'absolute path: a symlinked directory is resolved' 0 \
  "${TEST_WORK}/real/dir/r.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
os::file_get_absolute_path "${TEST_WORK}/link/r.sh"
CASE

# link is a symlink to real/dir, so link/.. is real/ and not the directory
# that holds the link.
test::case_run 'absolute path: .. after a symlinked directory follows the link' \
  0 "${TEST_WORK}/real/other.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
os::file_get_absolute_path "${TEST_WORK}/link/../other.sh"
CASE

test::case_run 'absolute path: doubled and trailing slashes, and . components' \
  0 "${TEST_WORK}/app/helper.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
os::file_get_absolute_path "${TEST_WORK}//app/./sub/..//helper.sh"
CASE

test::case_run \
  'absolute path: from a working directory reached through a symlink' 0 \
  "${TEST_WORK}/real/dir/r.sh" <<'CASE'
. "${TEST_BOOTSTRAP}"
cd "${TEST_WORK}/link"
os::file_get_absolute_path r.sh
CASE

test::case_run 'absolute path: a missing file returns 1 and prints no path' 0 \
  'status=1 out=' <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
out="$(os::file_get_absolute_path nope.sh)" || status=$?
echo "status=${status} out=${out}"
CASE
test::stderr_has 'absolute path: a missing file is reported on stderr' \
  '^os::file_get_absolute_path\(\) - Exception: file not found: nope\.sh$'

########################
### os::_dir_resolve ###
########################

# Twice over the same list: the second pass is answered from the cache. bash
# keeps a leading // in what pwd prints; os::_dir_resolve doesn't, so that a
# directory has one spelling.
test::case_run 'directory: resolves to what cd -P and pwd -P give' 0 \
  'all agree' <<'CASE'
. "${TEST_BOOTSTRAP}"
mkdir -p a/b/c
ln -s a/b short
ln -s short again
checked=(
  / /.. /usr/.. /usr/./bin/.. /bin /tmp //usr///bin/ /usr/bin/.
  "${PWD}" "${PWD}/a/b/c/../.." "${PWD}/a/./b//c/"
  "${PWD}/short" "${PWD}/short/c" "${PWD}/short/.." "${PWD}/again/c/.."
  "${TEST_WORK}/link" "${TEST_WORK}/link/.."
  "/${TEST_WORK}/link" "/${PWD}/short/c"
)
for pass in first second; do
  for checked_dir in "${checked[@]}"; do
    want="$(cd -P -- "${checked_dir}" && pwd -P)"
    if [[ "${want}" == //* ]]; then
      want="${want#/}"
    fi
    os::_dir_resolve "${checked_dir}"
    if [[ "${__bk__resolved_path}" != "${want}" ]]; then
      echo "${pass} pass, ${checked_dir}: got ${__bk__resolved_path}, want ${want}"
      differ=yes
    fi
  done
done
[[ -n "${differ:-}" ]] || echo "all agree"
CASE

test::case_run 'directory: a relative path is refused' 0 'status=1 path=[]' \
  <<'CASE'
. "${TEST_BOOTSTRAP}"
status=0
os::_dir_resolve relative/dir || status=$?
echo "status=${status} path=[${__bk__resolved_path}]"
CASE

# The slow path runs cd in a subshell, which inherits this cd function.
test::case_run 'directory: a subshell is used for a symlink and nothing else' \
  0 "$(printf '%s\n' 'without a symlink: 0' 'with a symlink: 1')" <<'CASE'
. "${TEST_BOOTSTRAP}"
log="${PWD}/cd.log"
: > "${log}"
cd() { echo called >> "${log}"; builtin cd "$@"; }
import "${TEST_WORK}/app/helper" "${TEST_WORK}/app/sub/../only" \
  "${TEST_WORK}/pkg"
os::file_get_absolute_path "${TEST_WORK}/app/sub/sibling.sh" > /dev/null
echo "without a symlink: $(wc -l < "${log}")"
os::file_get_absolute_path "${TEST_WORK}/link/r.sh" > /dev/null
os::file_get_absolute_path "${TEST_WORK}/link/r.sh" > /dev/null
echo "with a symlink: $(wc -l < "${log}")"
CASE

###############################################
### os::throw and os::print_stack_trace ###
###############################################

test::case_run 'throw: names its caller and prints the call stack' 0 \
  "$(printf '%s\n' 'status=1' \
    'inner() - Exception: something broke badly' \
    'Stack trace (most recent call first):' \
    'os::throw inner outer main')" <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
outer() { inner; }
inner() { os::throw "something broke" "badly"; }
outer 2> err
echo "status=$?"
sed -n 1,2p err
sed -n 's/^  at \([^ ]*\) .*/\1/p' err | xargs
CASE

test::case_run 'throw: the frames name the file and line of each call' 0 \
  'yes' <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
fails() { os::throw "x"; }
fails 2> err
grep -qE "^  at fails \(${BASH_SOURCE[0]}:[0-9]+\)$" err && echo yes
CASE

test::case_run 'throw: r sets the status, and can never make it 0' 0 \
  '2 255 1 1 1 1 1 1' <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
exec 2> /dev/null
statuses=()
r=2 os::throw x; statuses+=("$?")
r=255 os::throw x; statuses+=("$?")
r=256 os::throw x; statuses+=("$?")
r=0 os::throw x; statuses+=("$?")
r=abc os::throw x; statuses+=("$?")
r='1; echo injected' os::throw x; statuses+=("$?")
os::throw x; statuses+=("$?")
# a variable of the calling script that happens to be named r
r=0
os::throw x; statuses+=("$?")
echo "${statuses[*]}"
CASE

test::case_run 'throw: writes through log_error once a logger is loaded' 0 \
  'LOGGED: main() - Exception: via the logger' <<'CASE'
. "${TEST_BOOTSTRAP}"
set +e
log_error() { echo "LOGGED: $1" 1>&2; }
# pipefail is on, and os::throw returns 1
os::throw "via the logger" 2>&1 | sed -n 1p || true
CASE

test::case_run 'throw: at the top level of bash -c, where it has no caller' 0 \
  'main() - Exception: no caller' <<'CASE'
bash -c '. "${TEST_BOOTSTRAP}"; os::throw "no caller" 2>&1 | sed -n 1p || true'
CASE

test::case_run 'stack trace: without a message, and returns 0' 0 \
  'status=0 first=Stack trace (most recent call first): frames=2' <<'CASE'
. "${TEST_BOOTSTRAP}"
show() { os::print_stack_trace; }
show 2> err
echo "status=$? first=$(sed -n 1p err) frames=$(grep -c '^  at ' err)"
CASE

#######################
### os::source_http ###
#######################

test::case_run 'http: imports a URL once and records it' 0 \
  '1 http://test.invalid/plain.sh' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/plain.sh http://test.invalid/plain.sh
echo "${http_plain} ${__bk_imported_files[-1]}"
CASE
test::stderr_is_empty 'http: prints nothing on success'

test::case_run 'http: how curl is called' 0 \
  'curl --fail -sL --retry 5 http://test.invalid/plain.sh' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
os::source_http http://test.invalid/plain.sh 5
cat "${TEST_WORK}/fetch.log"
CASE

test::case_run 'http: how wget is called when curl is not installed' 0 \
  "$(printf '%s\n' '1' \
    'wget -t 3 -O - -o /dev/null http://test.invalid/plain.sh')" <<'CASE'
PATH="${TEST_WORK}/wgetbin"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/plain.sh
echo "${http_plain}"
cat "${TEST_WORK}/fetch.log"
CASE

test::case_run 'http: a URL with no extension is tried again with .sh' 0 \
  "$(printf '%s\n' '1' \
    'curl --fail -sL --retry 3 http://test.invalid/noext' \
    'curl --fail -sL --retry 3 http://test.invalid/noext.sh')" <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/noext
echo "${http_noext}"
cat "${TEST_WORK}/fetch.log"
CASE

test::case_run 'http: a URL that ends in .sh is tried once' 0 \
  'status=1 fetches=1' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
status=0
import http://test.invalid/missing.sh 2> /dev/null || status=$?
echo "status=${status} fetches=$(wc -l < "${TEST_WORK}/fetch.log")"
CASE

test::case_run 'http: the github: shorthand' 0 \
  "$(printf '%s\n' '1' \
    'curl --fail -sL --retry 3 https://raw.githubusercontent.com/owner/repo/ref/lib/x.sh')" \
  <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
import github:owner/repo/ref/lib/x.sh
echo "${http_github}"
cat "${TEST_WORK}/fetch.log"
CASE

test::case_run 'http: with only a URL, the script sees no operands' 0 '0:' \
  <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
set -- outer
os::source_http http://test.invalid/plain.sh
echo "${http_args}"
CASE

test::case_run 'http: operands follow the retry count' 0 '2:a b' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
os::source_http http://test.invalid/plain.sh 1 a b
echo "${http_args}"
CASE

test::case_run 'http: the retry count must be a number' 0 'status=1' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
status=0
os::source_http http://test.invalid/plain.sh many 2> /dev/null || status=$?
echo "status=${status}"
CASE

test::case_run 'http: an import in a downloaded file resolves against its URL' \
  0 '1 1' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/pkg/parent.sh
echo "${http_parent} ${http_rel}"
CASE

test::case_run 'http: a bare name in a downloaded file is looked for in bashkit' \
  0 "$(printf '%s\n' 'array::contains' \
    'curl --fail -sL --retry 3 http://test.invalid/pkg/uses-lib.sh')" <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
: > "${TEST_WORK}/fetch.log"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/pkg/uses-lib.sh
declare -F array::contains
cat "${TEST_WORK}/fetch.log"
CASE

test::case_run 'http: a BASH_SOURCE-relative source in a downloaded file' 0 \
  '1 1' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/pkg/sibling.sh
echo "${http_sibling} ${http_rel}"
CASE

test::case_run 'http: a failed download returns 1, and the caller can go on' 0 \
  'status=1 recorded=0 handled' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
status=0
import http://test.invalid/nope || status=$?
echo "status=${status} recorded=${#__bk_imported_files[@]} handled"
CASE
test::stderr_has 'http: a failed download is reported' \
  '^os::source_http\(\) - Exception: Cannot import http://test\.invalid/nope$'

test::case_run 'http: a failed download ends an errexit script' 1 '' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
import http://test.invalid/nope
echo "still running"
CASE

test::case_run \
  'http: errexit off, a script that fails returns 2 and is forgotten' 0 \
  'status=2 after=1 recorded=0' <<'CASE'
PATH="${TEST_WORK}/stubbin:${PATH}"
. "${TEST_BOOTSTRAP}"
set +e
import http://test.invalid/failing.sh 2> /dev/null
echo "status=$? after=${http_after:-0} recorded=${#__bk_imported_files[@]}"
CASE

########################
### BASHKIT PACKAGES ###
########################

if [[ -f "${TEST_REPO}/vendor/bash-logger/logging.sh" ]]; then
  test::case_run 'packages: every library directory imports, each file once' \
    0 'missing=0 duplicates=0 reimported=0' <<'CASE'
. "${TEST_BOOTSTRAP}"
packages=()
for package in "${TEST_LIB}"/*/; do
  package="${package%/}"
  packages+=("${package##*/}")
done
import "${packages[@]}"

missing=0
while IFS= read -r -d '' lib_file; do
  array::contains "${lib_file}" "${__bk_imported_files[@]}" \
    || missing=$(( missing + 1 ))
done < <(find "${TEST_LIB}" -type f -name '*.sh' -print0)
duplicates="$(printf '%s\n' "${__bk_imported_files[@]}" | sort | uniq -d | wc -l)"

recorded=${#__bk_imported_files[@]}
import "${packages[@]}"
echo "missing=${missing} duplicates=${duplicates} reimported=$(( ${#__bk_imported_files[@]} - recorded ))"
CASE
  # bash-logger announces its log file on stderr when it starts.
  test::stderr_has_only 'packages: importing them reports no error' \
    '^Logger: Successfully initialized'

  test::case_run 'packages: the logger and the contract helpers work' 0 \
    'true status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import core/contract-utils core/boolean-utils
core::bool_is_true yes && printf 'true '
status=0
core::require_operands 1 2> /dev/null || status=$?
echo "status=${status}"
CASE

  # Compares against sourcing the umbrella files directly, for the packages
  # that have one.
  if compgen -G "${TEST_LIB}/core/core.sh" > /dev/null; then
    test::case_run 'packages: import defines what the umbrella files define' \
      0 'same' <<'CASE'
umbrellas=()
packages=()
for package in "${TEST_LIB}"/*/; do
  package="${package%/}"
  if [[ -f "${package}/${package##*/}.sh" ]]; then
    umbrellas+=("${package}/${package##*/}.sh")
    packages+=("${package##*/}")
  fi
done

names='declare -F | cut -d" " -f3 | grep -vE "^(os::|array::|import$)"
compgen -v | grep -E "^__(BASHKIT|LIB)_"'
direct="$(bash -c 'for f in "$@"; do . "${f}"; done'"; ${names}" _ \
  "${umbrellas[@]}" | sort)"
imported="$(bash -c '. "${TEST_BOOTSTRAP}"; import "$@"'"; ${names}" _ \
  "${packages[@]}" | sort)"

if [[ -n "${direct}" && "${direct}" == "${imported}" ]]; then
  echo same
else
  diff <(echo "${direct}") <(echo "${imported}")
fi
CASE
  else
    test::skip 'packages: import defines what the umbrella files define' \
      'there are no umbrella files'
  fi
else
  test::skip 'packages: bashkit packages load through import' \
    'vendor/bash-logger is not checked out'
fi

#########################
### KNOWN LIMITATIONS ###
#########################
#
# These pin behavior that follows from the design. When the design changes,
# change the expectation with it.

# Imported files are sourced from inside a function (see the file header).
test::case_run 'limitation: a plain declare in an imported file is lost' 0 \
  'plain=unset global=1 constant=1 assigned=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/declares"
echo "plain=${plain:-unset} global=${global:-unset} constant=${constant:-unset} assigned=${assigned:-unset}"
CASE

# `import` only knows the files loaded after the bootstrap (see the file
# header).
test::case_run \
  'limitation: a file sourced before the bootstrap is loaded again' 1 '' \
  <<'CASE'
. "${TEST_WORK}/app/guarded.sh"
. "${TEST_BOOTSTRAP}"
import "${TEST_WORK}/app/guarded"
echo "still running"
CASE
test::stderr_has 'limitation: and fails on its read-only guard' \
  'GUARDED_SOURCED: readonly variable'

test::summary_print
