#!/bin/bash
# Build the mi300 recipe with Stackinator on a beverin MI300A node and copy the squashfs out.
# One node does everything: the HIP packages need the GPU present, and beverin compute nodes
# have outbound network for the Spack sources, the pip wheels and the HF tokenizer cache.
#
# Usage, from the repo root: [OUT=...] [NJOBS=64] sbatch build_mi300.sbatch
# Stackinator and the Alps cluster config are cloned once under TOOLS_DIR and reused.
#
#SBATCH -J uenv-inference-mi300
#SBATCH -A csstaff
#SBATCH -p mi300
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 128
#SBATCH -t 08:00:00
#SBATCH -o build-uenv-mi300-%j.out
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-${SLURM_SUBMIT_DIR}}"
RECIPE="${REPO_ROOT}/mi300"
OUT_DIR="${OUT_DIR:-/iopsstor/scratch/cscs/aurianer/images}"
OUT="${OUT:-${OUT_DIR}/inference-bench-mi300-$(date +%Y%m%d)-${SLURM_JOB_ID}.squashfs}"
NJOBS="${NJOBS:-64}"
TOOLS_DIR="${TOOLS_DIR:-/iopsstor/scratch/cscs/aurianer/uenv-tools}"
# Both repos develop on main; stackinator's master is stale and rejects recipe version 2.
STACKINATOR_REF="${STACKINATOR_REF:-main}"
CLUSTER_CONFIG_REF="${CLUSTER_CONFIG_REF:-main}"
# Shared memory is the documented fast build location; it is wiped on exit so a failed build
# does not keep 100+ GB of node memory.
BUILD="/dev/shm/${USER}/uenv-build-${SLURM_JOB_ID}"
trap 'rm -rf "${BUILD}"' EXIT

[[ -f "${RECIPE}/environments.yaml" ]] || { echo "ERROR: no recipe at ${RECIPE}" >&2; exit 1; }
mkdir -p "${TOOLS_DIR}" "$(dirname "${OUT}")" "${BUILD}"

for repo in stackinator alps-cluster-config; do
  ref_var="$([[ ${repo} == stackinator ]] && echo STACKINATOR_REF || echo CLUSTER_CONFIG_REF)"
  if [[ ! -d "${TOOLS_DIR}/${repo}/.git" ]]; then
    git clone -q "https://github.com/eth-cscs/${repo}.git" "${TOOLS_DIR}/${repo}"
  fi
  git -C "${TOOLS_DIR}/${repo}" fetch -q origin
  git -C "${TOOLS_DIR}/${repo}" checkout -q "${!ref_var}"
  git -C "${TOOLS_DIR}/${repo}" pull -q --ff-only 2>/dev/null || true
  echo "[build] ${repo} at $(git -C "${TOOLS_DIR}/${repo}" rev-parse --short HEAD)"
done
( cd "${TOOLS_DIR}/stackinator" && ./bootstrap.sh )
export PATH="${TOOLS_DIR}/stackinator/bin:${PATH}"

echo "[build] recipe=${RECIPE} build=${BUILD} out=${OUT} njobs=${NJOBS}"
stack-config -r "${RECIPE}" -b "${BUILD}" -s "${TOOLS_DIR}/alps-cluster-config/beverin"

# The documented invocation: a clean environment for reproducible builds; NJOBS instead of
# make -j (the install step clears MAKEFLAGS before calling Spack).
cd "${BUILD}"
env --ignore-environment PATH="/usr/bin:/bin:${BUILD}/spack/bin" \
  make store.squashfs NJOBS="${NJOBS}"

cp "${BUILD}/store.squashfs" "${OUT}"
ls -lh "${OUT}"
echo "[build] done: uenv start ${OUT} --view=default"
