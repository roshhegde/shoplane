#!/usr/bin/env bash
# Tear down the expensive parts. Order matters:
#   1. Delete the Ingress first, so the LB controller (still running) deletes
#      the ALB and its security groups. Skip this and the VPC can't be deleted.
#   2. Destroy app (EKS, RDS), then network (NAT gateway, VPC).
# The edge stack (CloudFront + S3, about $0 idle) and aws-foundation stay,
# unless DESTROY_EDGE=1.
source "$(dirname "$0")/lib.sh"

if tf app output -raw cluster_name >/dev/null 2>&1; then
  CLUSTER="$(tf_out app cluster_name)"
  if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
    step "1/3 Deleting the Ingress so the controller removes the ALB"
    aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION" >/dev/null
    kubectl delete ingress catalog -n shoplane --ignore-not-found --wait=true --timeout=5m
    for _ in $(seq 1 30); do
      aws elbv2 describe-load-balancers --names shoplane-alb >/dev/null 2>&1 || break
      sleep 10
    done
  fi
fi

if [[ "${DESTROY_EDGE:-0}" == "1" ]]; then
  step "Destroying edge (CloudFront takes a few minutes to disable)"
  tf edge destroy -input=false -auto-approve -var enable_api_origin=false
fi

step "2/3 Destroying app: EKS and RDS (~10-15 min)"
tf app destroy -input=false -auto-approve

step "3/3 Destroying network: NAT gateway and VPC"
tf network destroy -input=false -auto-approve

step "Done. Still running: aws-foundation (state, ECR, OIDC role, budget) and, unless DESTROY_EDGE=1, the idle CloudFront distribution."
