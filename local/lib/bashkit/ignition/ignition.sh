# shellcheck shell=bash
#
# Umbrella loader for bashkit/local/lib/bashkit/ignition library files.
#
# Add new ignition library files to this file as they are created.

# shellcheck source=butane.sh
. /dev/null
import ignition/butane.sh

# shellcheck source=merge.sh
. /dev/null
import ignition/merge.sh

# shellcheck source=ignition-validate.sh
. /dev/null
import ignition/ignition-validate.sh

# shellcheck source=serve.sh
. /dev/null
import ignition/serve.sh
