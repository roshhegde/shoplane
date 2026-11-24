# Stack 3 of 4 (destroyed after each lab): the compute and data tiers.
#
#   EKS control plane      AWS-run Kubernetes API, about $0.10 an hour
#   Spot node group        2 x t4g.medium Graviton in private subnets, both AZs
#   EKS add-ons            VPC CNI, CoreDNS, kube-proxy, Pod Identity Agent
#   Pod Identity           IAM roles for the LB controller and catalog pods
#   LB Controller (Helm)   turns a Kubernetes Ingress into an ALB
#   RDS PostgreSQL         single-AZ db.t4g.micro, password in Secrets Manager

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "shoplane/aws-foundation.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "shoplane/network.tfstate"
    region = var.aws_region
  }
}

locals {
  name    = "shoplane"
  network = data.terraform_remote_state.network.outputs

  cluster_admin_policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  # Every admin is listed explicitly (instead of "whoever created the cluster"),
  # so a lab created from GitHub Actions can be managed from a laptop and back.
  access_entries = merge(
    {
      github_deploy = {
        principal_arn = data.terraform_remote_state.foundation.outputs.github_role_arn
        policy_arn    = local.cluster_admin_policy
      }
    },
    { for label, arn in var.cluster_admin_arns : label => { principal_arn = arn, policy_arn = local.cluster_admin_policy } },
  )
}

# ---------------------------------------------------------------------- EKS --

module "eks" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/eks?ref=v1.1.0"

  name                    = local.name
  kubernetes_version      = var.kubernetes_version
  subnet_ids              = local.network.private_subnet_ids
  public_access_cidrs     = var.api_public_access_cidrs
  bootstrap_creator_admin = false
  access_entries          = local.access_entries

  node_groups = {
    spot = {
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"                   # up to ~70% cheaper; AWS can reclaim with 2 minutes' notice
      ami_type       = "AL2023_ARM_64_STANDARD" # Graviton (arm64), so images must be built for arm64
      desired_size   = 2                        # one per AZ, spread by the node group across both subnets
      min_size       = 2
      max_size       = 3
    }
  }

  addons = {
    "vpc-cni"                = {}
    "kube-proxy"             = {}
    "coredns"                = {}
    "eks-pod-identity-agent" = {}
  }

  pod_identities = {
    # The controller calls the ELB and EC2 APIs to build ALBs and target groups.
    lb-controller = {
      namespace          = "kube-system"
      service_account    = "aws-load-balancer-controller"
      inline_policy_json = file("${path.module}/policies/aws-load-balancer-controller.json")
    }

    # The catalog only needs to read its database password.
    catalog = {
      namespace       = "shoplane"
      service_account = "catalog"
      inline_policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = "ReadDatabaseSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = module.db.master_user_secret_arn
        }]
      })
    }
  }
}

# ------------------------------------------------- AWS Load Balancer Controller --
# Installed with Helm (it is Kubernetes software, not an AWS resource). It
# watches Ingress objects and creates the ALB, listeners, target groups and
# security group rules for them, registering pod IPs directly (target-type ip).

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version

  set = [
    { name = "clusterName", value = module.eks.cluster_name },
    { name = "region", value = var.aws_region },
    { name = "vpcId", value = local.network.vpc_id },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  # The controller needs nodes to run on, the Pod Identity Agent for its AWS
  # credentials, and our access entry so Helm may install it.
  depends_on = [module.eks]
}

# ---------------------------------------------------------------- Database --

module "db" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/rds?ref=v1.1.0"

  name           = local.name
  engine_version = "17"
  instance_class = "db.t4g.micro"
  db_name        = "shoplane"
  username       = "shoplane_admin"
  multi_az       = false # phase 5 turns this on and runs a failover drill

  vpc_id     = local.network.vpc_id
  subnet_ids = local.network.private_subnet_ids

  # Pods run on the nodes, and managed nodes use the EKS cluster security
  # group, so allowing that group lets the catalog reach Postgres.
  allowed_security_groups = { eks_cluster = module.eks.cluster_security_group_id }

  backup_retention_days = 1
  skip_final_snapshot   = true # lab data is reseeded by the catalog on start
}
