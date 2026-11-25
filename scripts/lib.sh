# Shared settings for the lab scripts. Source it; don't run it.
set -euo pipefail

: "${TF_STATE_BUCKET:?Set TF_STATE_BUCKET to the bucket from the aws-foundation output state_bucket}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export TF_IN_AUTOMATION=1
export TF_VAR_state_bucket="$TF_STATE_BUCKET"   # the app stack reads other stacks' outputs from here
# Optional: extra cluster admins as JSON, e.g. {"rosh":"arn:aws:iam::123456789012:user/rosh"}
if [[ -n "${CLUSTER_ADMIN_ARNS:-}" ]]; then export TF_VAR_cluster_admin_arns="$CLUSTER_ADMIN_ARNS"; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# terraform init + a command for one stack, with the shared state bucket.
tf() {
  local stack="$1"; shift
  terraform -chdir="$ROOT/infra/$stack" init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=$AWS_REGION" >/dev/null
  terraform -chdir="$ROOT/infra/$stack" "$@"
}

tf_out() { terraform -chdir="$ROOT/infra/$1" output -raw "$2"; }
