# inference-bench uenv (Daint GH200)

A uenv (CSCS user environment) for LLM **inference benchmarking**:

- **Python 3.12** + **CUDA** runtime/toolkit — from Spack (recipe: `recipe/`)
- **vLLM** `0.24.0` (+ its matching aarch64 CUDA PyTorch wheel) — pip, layered in `post-install`
- **k6** `v2.0.0` (Grafana load testing) — SHA256-verified arm64 binary in `post-install`

Target label: `inference-bench/v4@daint%gh200` (Spack `cuda_arch=90a`).

## Design notes

- **Lean Spack base, pip on top.** Spack provides `python@3.12` + CUDA; vLLM (which pins a recent
  torch) pulls its own aarch64 CUDA torch wheel via pip. This avoids a version deadlock with a
  Spack-built `py-torch` and keeps the build small. Chosen for single-node GH200 benchmarking.
- **How pip packages get into the image:** the view sets `PYTHONUSERBASE=/user-environment/env/default`,
  so `pip install --user` at build time writes into the store (fixed mount) and ships in the squashfs.
- **Multi-node:** add the `network:`/`aws-ofi-nccl` block noted in `recipe/environments.yaml`
  (mirrors the official `eth-cscs/alps-uenv` pytorch/gh200 recipe) if you benchmark across nodes.
- **Reproducibility/supply chain:** Spack (`v1.2.0`) and `spack-packages` are pinned to exact
  commits; k6 is verified against its published `checksums.txt`; vLLM is version-pinned.

## Build on the cluster (Stackinator — recommended)

`post-install` needs outbound network (to pip vLLM and download k6); the Daint login/build node has it.

```bash
git clone https://github.com/eth-cscs/stackinator.git
cd stackinator && ./bootstrap.sh
export PATH=$(pwd)/bin:$PATH

# -s is the alps cluster config for daint; adjust to the current deployment path
stack-config -r <path>/uenv-inference-recipe/recipe \
             -b $SCRATCH/build/inference-bench \
             -s ./alps/daint \
             -c $SCRATCH/cache.yaml
cd $SCRATCH/build/inference-bench
env --ignore-environment PATH=/usr/bin:/bin:/usr/sbin make store.squashfs
```

## Build via the CSCS CI service (alternative)

```bash
uenv build <path>/uenv-inference-recipe/recipe  inference-bench/v4@daint%gh200
```

> ⚠️ The `uenv build` service pushes to the **public `service::` namespace**, and its build sandbox
> may block the network egress the pip step needs. Prefer the Stackinator path above.

## Run & verify

```bash
uenv start ./store.squashfs        # or: uenv start inference-bench/v4@daint%gh200

python3 --version                  # -> 3.12.x
k6 version                         # -> k6 v2.0.0
python3 -c "import vllm, torch; print(vllm.__version__, torch.__version__, torch.cuda.is_available())"
```

### End-to-end benchmark

```bash
# 1. serve a small model on a GH200 node (OpenAI-compatible endpoint on :8000)
srun -A <acct> -p normal --gres=gpu:1 vllm serve <model-id> --port 8000 &

# 2. drive it with k6 (see k6 docs for an HTTP script hitting /v1/completions)
k6 run load-test.js
```

## Bumping versions

- vLLM: edit `VLLM_VERSION` in `recipe/post-install` (check its required torch supports aarch64 CUDA).
- k6: edit `K6_VERSION` (checksums are auto-verified).
- Spack: edit `spack.commit` / `spack.packages.commit` in `recipe/config.yaml`.
