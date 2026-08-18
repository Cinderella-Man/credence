#!/usr/bin/env bash
#
# Run every step of .github/workflows/ci.yml in a clean container.
#
# STATUS.md A6 said CI had never executed and the first run should be treated as
# a hypothesis. Most of it need not be: the only genuinely GitHub-specific parts
# are the actions (checkout@v4, setup-beam@v1, cache@v4) and their cache keys.
# Everything else is `mix`, and `mix` runs anywhere.
#
# What this buys over a local `mix test` is the three failure modes a working
# copy cannot show you:
#
#   * a cached `_build` hiding a warning that `--warnings-as-errors` would catch
#   * a test that only passes because of local state outside the repo
#   * the fixture healer leaving the tree dirty — `git diff --exit-code`, the
#     step most likely to pass locally and fail on a runner
#
# It clones HEAD, so COMMIT FIRST: uncommitted work is not tested.
#
#     .github/run-ci-locally.sh              # the fast `check` job
#     .github/run-ci-locally.sh all          # + idempotency + corpus (~20 min)
#
# The corpus job mounts ./corpus rather than fetching, so it exercises the tests
# but NOT `mix credence.corpus.fetch`. That fetch stays unverified off a runner.
set -euo pipefail

JOBS="${1:-check}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Kept in step with ci.yml's env block. `setup-beam` resolves OTP 29 to its
# latest patch, which is why this pins a patch the workflow does not.
IMAGE="hexpm/elixir:1.20.2-erlang-29.0.5-ubuntu-noble-20260730.1"

command -v docker >/dev/null || { echo "docker not found"; exit 127; }

read -r -d '' SCRIPT <<'INNER' || true
set -euxo pipefail
export MIX_ENV=test HEX_HTTP_TIMEOUT=120

# The hexpm image has no git, and the clone plus the tree-clean check need it.
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq git >/dev/null 2>&1
git config --global --add safe.directory '*'

git clone -q /src /work
cd /work
echo "HEAD $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)"
elixir --version

mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null
mix deps.get

if [ "$JOBS" = "check" ] || [ "$JOBS" = "all" ]; then
  mix format --check-formatted
  mix compile --force --warnings-as-errors
  mix test --exclude corpus --exclude idempotency
  # ci.yml: "Fixture healer left the tree clean"
  git diff --exit-code
fi

if [ "$JOBS" = "all" ]; then
  mix test --only idempotency
  # The corpus is mounted, not fetched — see the header.
  [ -d /corpus ] && ln -sfn /corpus /work/corpus
  mix test --only corpus
fi

echo "ALL REQUESTED CI JOBS PASSED"
INNER

MOUNTS=(-v "$REPO_ROOT:/src:ro")
[ -d "$REPO_ROOT/corpus" ] && MOUNTS+=(-v "$REPO_ROOT/corpus:/corpus:ro")

docker run --rm "${MOUNTS[@]}" -e "JOBS=$JOBS" "$IMAGE" bash -c "$SCRIPT"
