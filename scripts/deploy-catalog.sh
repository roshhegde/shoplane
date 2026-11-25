#!/usr/bin/env bash
# Deploy the catalog to EKS. Reads values from the app stack's Terraform
# outputs, fills in k8s/catalog.yaml and applies it.
#   IMAGE_TAG=<git sha> scripts/deploy-catalog.sh    (default: newest image in ECR)
source "$(dirname "$0")/lib.sh"

tf app output >/dev/null
REPO_URL="$(tf_out app catalog_image_repository)"
REPO_NAME="${REPO_URL#*/}"
CLUSTER="$(tf_out app cluster_name)"

if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(aws ecr describe-images --repository-name "$REPO_NAME" \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text)"
  [[ "$IMAGE_TAG" != "None" ]] || { echo "No catalog image in ECR yet. Run the catalog-image workflow first." >&2; exit 1; }
fi

export CATALOG_IMAGE="$REPO_URL:$IMAGE_TAG"
export DB_HOST="$(tf_out app db_host)"
export DB_NAME="$(tf_out app db_name)"
export DB_SECRET_ARN="$(tf_out app db_secret_arn)"

step "Deploying $CATALOG_IMAGE to $CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" >/dev/null
envsubst '${CATALOG_IMAGE} ${AWS_REGION} ${DB_HOST} ${DB_NAME} ${DB_SECRET_ARN}' < "$ROOT/k8s/catalog.yaml" | kubectl apply -f -
kubectl -n shoplane rollout status deployment/catalog --timeout=5m
