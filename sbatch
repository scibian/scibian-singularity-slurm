#!/bin/bash

# Copyright (C) 2017 Scibian Project <legal@scibian.org>
#
# This file is part of scibian-singularity-slurm.
#
# scibian-singularity-slurm is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# scibian-singularity-slurm is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with scibian-singularity-slurm.  If not, see
# <http://www.gnu.org/licenses/>.

set -ueo pipefail

sbatch_legacy=${SINGULARITY_SBATCH_LEGACY:-/usr/bin/sbatch.legacy}

# If not into a container then exec legacy ssh
if [ -z "${SINGULARITY_CONTAINER:-}" ]; then
  exec "$sbatch_legacy" "$@"
fi

readonly SBATCH_SINGLE_OPTS="[HkOQsvWV]"
readonly SBATCH_MULTI_OPTS="[aAbcdDeiJLMmnNopqStCFwxBG]"

SBATCH_OPTIONS=()
SBATCH_SCRIPT=

# While an option is found, stack it
# Stack script parameter as well, and the options just after it
# Stop at the first parameter which is not an option nor the script parameter
while (( $# > 0 )) ;do
  case "${1:-}" in
    --*)
      SBATCH_OPTIONS+=("$1")
      shift
      ;;

    -*)
      if [[ "$1" =~ -${SBATCH_SINGLE_OPTS}*$ ]]; then
        SBATCH_OPTIONS+=("$1")
	shift
      elif [[ "$1" =~ -${SBATCH_SINGLE_OPTS}*${SBATCH_MULTI_OPTS}$ ]]; then
        SBATCH_OPTIONS+=("$1" "${2:-}")
        shift 2
      else
        # Do not stack invalid options (will be handled by legacy slurm command)
        break
      fi
      ;;
    *)
      SBATCH_SCRIPT="${1:-}"
      shift
      break
      ;;
  esac
done

if [ -z "${SBATCH_SCRIPT:-}" ]; then
  # No script -> call legacy sbatch
  if (( ${#SBATCH_OPTIONS[@]} > 0 )); then
    exec "$sbatch_legacy" "${SBATCH_OPTIONS[@]}" "$@"
  else
    exec "$sbatch_legacy" "$@"
  fi
fi

if [ -f "$SBATCH_SCRIPT" ]; then
  SBATCH_SCRIPT="$(realpath "$SBATCH_SCRIPT")"
fi

tmpscript=$(mktemp --tmpdir "$(basename "$SBATCH_SCRIPT").XXX")
trap 'rm -f $tmpscript' EXIT

echo "#!/bin/sh" >$tmpscript
sed -E -e '1d' -e '/^(#.*|\s*)$/!Q' "$SBATCH_SCRIPT" >>$tmpscript
echo "exec singularity exec '$SINGULARITY_CONTAINER' '$SBATCH_SCRIPT' \"\$@\"" >>$tmpscript

chmod a+x $tmpscript

if (( ${#SBATCH_OPTIONS[@]} > 0 )); then
  "$sbatch_legacy" "${SBATCH_OPTIONS[@]}" $tmpscript "$@"
else
  "$sbatch_legacy" $tmpscript "$@"
fi
