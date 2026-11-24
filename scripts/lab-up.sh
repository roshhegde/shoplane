#!/usr/bin/env bash
# Build the whole phase 2 store: network -> app -> catalog -> edge -> storefront.
# About 25 minutes, mostly EKS and RDS. Run lab-down.sh when you're done.
source "$(dirname "$0")/lib.sh"

step "1/5 Network: VPC, subnets in 2 AZs, NAT gateway (~3 min)"
tf network apply -input=false -auto-approve

step "2/5 App: EKS cluster, Spot nodes, add-ons, LB controller, RDS (~15-20 min)"
tf app apply -input=false -auto-approve

step "3/5 Catalog pods, Service and Ingress"
"$ROOT/scripts/deploy-catalog.sh"

step "Waiting for the AWS Load Balancer Controller to create the ALB"
for _ in $(seq 1 60); do
  aws elbv2 describe-load-balancers --names shoplane-alb >/dev/null 2>&1 && break
  sleep 10
done
aws elbv2 wait load-balancer-available --names shoplane-alb

step "4/5 Edge: S3 storefront bucket and CloudFront (~5 min the first time)"
tf edge apply -input=false -auto-approve

step "5/5 Upload the storefront"
BUCKET="$(tf_out edge storefront_bucket)"
aws s3 sync "$ROOT/storefront" "s3://$BUCKET" --delete
aws cloudfront create-invalidation --distribution-id "$(tf_out edge distribution_id)" --paths '/*' >/dev/null

URL="$(tf_out edge storefront_url)"
step "Shoplane is up: $URL"
echo "Try: curl $URL/api/products | head -c 300"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "### Shoplane is up: $URL" >> "$GITHUB_STEP_SUMMARY"
fi
