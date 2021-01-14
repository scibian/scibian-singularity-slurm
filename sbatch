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

slurm_tmpdir="${SINGULARITY_SLURM_TMPDIR:-$HOME/.singularity_slurm_tmp}"
mkdir -p "$slurm_tmpdir"

readonly SBATCH_SINGLE_OPTS="[HkOQsvWV]"
readonly SBATCH_MULTI_OPTS="[aAbcdDeiJLMmnNopqStCFwxBG]"
readonly SBATCH_MULTI_LONG_OPTS="
array account acctg-freq extra-node-info batch bb bbf begin bxi-bandwidth
cluster-constraint comment
constraint cores-per-socket cpu-freq cpus-per-gpu cpus-per-task
deadline delay-boot dependency chdir error export export-file nodefile gid gpus
gpu-bind gpu-freq gpus-per-node gpus-per-socket gpus-per-task gres gre-flags hint
input job-name kill-on-invalid-dep licenses clusters distribution mail-type mail-user
msc-label mem mem-per-cpu mem-per-gpu mem-bind mincpus
nodes ntasks network ntasks-per-core ntasks-per-node ntasks-per-socket
output open-mode partition power priority profile qos
reservation core-spec signal sockets-per-node switches
time thread-spec threads-per-core time-min
tmp uid wait-all-nodes nodelist wckey wrap exclude
"

SBATCH_OPTIONS=()
SBATCH_SCRIPT=

# While an option is found, stack it
# Stack script parameter as well, and the options just after it
# Stop at the first parameter which is not an option nor the script parameter
while (( $# > 0 )) ;do
  case "${1:-}" in
    --*)
      if [[ "$(echo $SBATCH_MULTI_LONG_OPTS)" =~ (^| )"${1#--}"( |$) ]]; then
        SBATCH_OPTIONS+=("$1" "${2:-}")
        shift 2
      else
        SBATCH_OPTIONS+=("$1")
        shift
      fi
      ;;
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

tmpscript=$(mktemp --tmpdir="$slurm_tmpdir" "$(basename "$SBATCH_SCRIPT").XXX")
trap 'rm -f $tmpscript' EXIT

# Retrieve interpretor for when the script is not executable
if ! [ -x "$SBATCH_SCRIPT" ]; then
  interp=$(head -1 "$SBATCH_SCRIPT" | grep '^#!') || interp=/bin/sh
  interp="${interp#\#!}"
fi

echo "#!/bin/sh" >$tmpscript
sed -E -e '1d' -e '/^(#.*|\s*)$/!Q' "$SBATCH_SCRIPT" >>$tmpscript
echo "export SINGULARITY_OPTIONS='${SINGULARITY_OPTIONS:-}'" >>$tmpscript
# Option -s: see https://github.com/hpcng/singularity/issues/3250#issuecomment-481323679
echo "exec singularity -s exec ${SINGULARITY_OPTIONS:-} '$SINGULARITY_CONTAINER' ${interp:-} '$SBATCH_SCRIPT' \"\$@\"" >>$tmpscript

chmod a+x $tmpscript

if (( ${#SBATCH_OPTIONS[@]} > 0 )); then
  "$sbatch_legacy" "${SBATCH_OPTIONS[@]}" $tmpscript "$@"
else
  "$sbatch_legacy" $tmpscript "$@"
fi
