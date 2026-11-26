# Phase 2: the core store on AWS

This phase builds the first working version of Shoplane: a storefront you can open in a browser, backed by a catalog API on Kubernetes and a Postgres database. Everything is Terraform, using modules from [roshhegde/tfmodules](https://github.com/roshhegde/tfmodules), and the whole lab can be built and torn down from a GitHub Actions button.

## What a request does

```
Browser
  │  https://dxxxx.cloudfront.net
  ▼
CloudFront ──────────── /*  ──────────▶ S3 bucket (storefront: index.html, app.js, styles.css)
  │                                      private; only this distribution can read it (OAC)
  │ /api/*  (no caching)
  ▼
ALB  (public subnets, both AZs)          created by the AWS Load Balancer Controller from the Ingress
  │  sends traffic straight to pod IPs (target-type ip)
  ▼
catalog pods on EKS  (private subnets, one per AZ)
  │  password from Secrets Manager, using the pod's own IAM role (Pod Identity)
  ▼
RDS PostgreSQL  (private subnets, accepts connections only from the EKS security group)
```

Open the storefront, and the page loads from S3 through CloudFront. Its JavaScript then calls `/api/products` on the same domain. CloudFront sees the `/api/*` path and forwards that request, uncached, to the ALB, which picks a healthy catalog pod. The pod runs a SQL query and returns JSON. The footer shows which pod answered; refresh a few times and you'll see the ALB alternate between the two.

## The four Terraform stacks

State for every stack lives in one S3 bucket, split by key, so the expensive layers can be destroyed without touching the cheap ones.

| Stack | Lifetime | What it holds | Idle cost |
| --- | --- | --- | --- |
| `infra/aws-foundation` | Keep | State bucket, GitHub OIDC deploy role, ECR repository, $20 budget | About $0 |
| `infra/network` | Destroy after each lab | VPC, 2 public + 2 private subnets, internet gateway, 1 NAT gateway, route tables | About $1.10 a day (NAT) |
| `infra/app` | Destroy after each lab | EKS cluster, 2 Spot Graviton nodes, add-ons, Pod Identity roles, LB controller, RDS | About $3.50 a day |
| `infra/edge` | Can stay | Storefront bucket and CloudFront distribution | About $0 |

Each stack has an offline `terraform test` that runs against mocked providers, so CI catches wiring mistakes without an AWS account.

## Each component, and why it's here

### Network (`infra/network`)

- **VPC across two Availability Zones.** An AZ is one or more data centres with independent power and networking. Putting everything in two AZs means one can fail and the store keeps running (phase 5 proves this with a drill).
- **Public subnets** hold things that must be reachable from the internet: the ALB and the NAT gateway. They route `0.0.0.0/0` to the **internet gateway**.
- **Private subnets** hold the nodes, pods and database. Nothing on the internet can open a connection to them. They're `/20` (4,096 addresses each) because the VPC CNI gives every pod a real VPC IP address.
- **NAT gateway.** Private resources still need to start outbound connections (pull images from ECR, call AWS APIs). The NAT gateway lets them out without letting anything in. Phase 2 uses one, in the first AZ, to save about $33 a month; phase 5 adds one per AZ so losing an AZ can't cut off the other.
- **Subnet tags** `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tell the Load Balancer Controller which subnets to put ALBs in.

### Kubernetes on EKS (`infra/app`, `module "eks"`)

- **Control plane.** AWS runs the Kubernetes API servers and etcd across AZs for $0.10 an hour. You never see those machines.
- **Access entries** decide which IAM principals may use the Kubernetes API. The GitHub deploy role is always an admin, plus anyone in `cluster_admin_arns`. This replaces the old `aws-auth` ConfigMap.
- **Managed node group of 2 Spot t4g.medium nodes.** These EC2 instances run your pods. *Spot* is spare EC2 capacity at up to about 70% off, which AWS can reclaim with two minutes' notice; managed node groups drain the node for you. *t4g* is Graviton (ARM), about 20% cheaper than x86, so the catalog image is built for `arm64`.
- **Add-ons**: the **VPC CNI** (gives pods VPC IPs), **CoreDNS** (service discovery inside the cluster), **kube-proxy** (routes Service traffic) and the **Pod Identity Agent** (hands AWS credentials to pods).
- **Pod Identity.** Each Kubernetes service account can be mapped to its own IAM role. The catalog pods run as service account `catalog`, which maps to the `shoplane-catalog` role, whose only permission is reading the database secret. The LB controller gets a role that can manage load balancers. No pod uses the node's role, and no keys are stored.

### AWS Load Balancer Controller (Helm)

A Kubernetes controller installed with Helm. It watches **Ingress** objects and turns each one into an **ALB** with a listener, target group and security group rules. With `target-type: ip`, the ALB sends traffic directly to pod IPs, skipping an extra hop through the node. The ALB health-checks `/api/ready`, so a pod that can't reach the database stops getting traffic.

### Catalog service (`services/catalog`, `k8s/catalog.yaml`)

A FastAPI app with `GET /api/products` (keyword search and category filter), `/api/products/{id}`, `/api/categories`, `/api/health`, `/api/ready` and `/api/info`.

- **Two replicas spread across zones** (`topologySpreadConstraints`) and a **PodDisruptionBudget** of 1, so a node drain or Spot interruption always leaves one pod serving.
- **Liveness vs readiness.** `/api/health` only checks the process is alive, so a database blip doesn't make Kubernetes restart healthy pods. `/api/ready` checks the database, so traffic only goes to pods that can answer.
- **Self-seeding.** Each lab starts with an empty database. On startup the service creates the `products` table and inserts 16 seed products if it's empty, using a Postgres advisory lock so two pods starting at once don't both do it.
- **Hardened container**: non-root user, read-only root filesystem, all Linux capabilities dropped.
- Run it locally with `docker compose up --build` in `services/catalog`.

### Database (`module "db"`)

- **RDS PostgreSQL 17 on db.t4g.micro, single-AZ** in the private subnets. Phase 5 switches on Multi-AZ, which keeps a synchronous standby in the other AZ and fails over automatically.
- **No password in code or state.** `manage_master_user_password` makes RDS generate the password and keep it in **Secrets Manager**. The catalog reads it at startup with its Pod Identity role.
- **Security group** allows port 5432 only from the EKS cluster security group, which the managed nodes (and so the pods) use.
- Connections use TLS (`sslmode=require`).

### Edge (`infra/edge`)

- **S3 bucket** holds the static storefront. It is fully private.
- **CloudFront** serves it over HTTPS from edge locations, with **Origin Access Control** so only this distribution can read the bucket.
- A second **origin** points `/api/*` at the ALB with caching disabled, so the browser talks to one domain and needs no CORS. CloudFront to ALB is HTTP for now; phase 4 adds a certificate and locks the ALB to CloudFront only.

### CI/CD (`.github/workflows`)

- **ci.yml** (every PR, no AWS access): catalog unit tests, `terraform fmt`, `validate` and mocked `terraform test` for each stack, and a manifest render check.
- **catalog-image.yml** (push to main): builds the image on a native arm64 runner and pushes it to ECR tagged with the commit SHA.
- **lab.yml** (manual): `up`, `down` or `deploy-catalog`.
- All AWS access uses **GitHub OIDC**. GitHub signs a short-lived token for the run; AWS STS checks it came from this repo's `main` branch or `lab` environment and returns one-hour credentials. No AWS keys exist in GitHub.

## Running a lab

### One-time setup (about 5 minutes)

Needs Terraform 1.10 or later and the AWS CLI, signed in as an admin of your account.

1. Bootstrap the foundation with local state, then move its state into the bucket it created:
   ```sh
   cd infra/aws-foundation
   cp terraform.tfvars.example terraform.tfvars   # set budget_email
   terraform init && terraform apply

   # Write the real bucket name (from the apply's output) into backend.hcl.
   # Don't copy backend.hcl.example as is: its 123456789012 is a placeholder.
   printf 'bucket = "%s"\nregion = "us-east-1"\n' "$(terraform output -raw state_bucket)" > ../backend.hcl
   cat ../backend.hcl

   # Only now switch on the S3 backend and copy the local state into it (answer "yes").
   cp backend.tf.example backend.tf
   terraform init -migrate-state -backend-config=../backend.hcl
   ```
   If `init -migrate-state` says the bucket `shoplane-tfstate-123456789012` doesn't exist, `backend.hcl` still has the placeholder. Move `backend.tf` aside, rerun the `printf` line, then put `backend.tf` back.
2. In GitHub, **Settings → Environments**, create an environment called `lab`.
3. In **Settings → Secrets and variables → Actions → Variables**, add:
   - `AWS_ROLE_ARN`: the `github_role_arn` output
   - `TF_STATE_BUCKET`: the `state_bucket` output
   - `CLUSTER_ADMIN_ARNS` (optional): `{"rosh":"arn:aws:iam::<account>:user/<you>"}` so you can use `kubectl` from your laptop
4. Run the **catalog-image** workflow once (Actions → catalog-image → Run workflow) to put the first image in ECR.

### Build, demo, destroy

- **Up**: Actions → lab → `up`. About 25 minutes. The run summary shows the storefront URL.
- **Demo**: open the URL, search, filter by category, refresh to watch the pod name change. From a laptop: `aws eks update-kubeconfig --name shoplane`, then `kubectl -n shoplane get pods -o wide` to see one pod per AZ.
- **Down**: Actions → lab → `down`. About 15 minutes. It deletes the Ingress first, so the controller removes the ALB before Terraform deletes the VPC.

The same scripts run from a laptop: `TF_STATE_BUCKET=<bucket> scripts/lab-up.sh` (needs `kubectl` and `envsubst` too).

### Cost of a lab

| Item | Per hour |
| --- | --- |
| EKS control plane | $0.10 |
| 2 x t4g.medium Spot | about $0.02 |
| NAT gateway | $0.045 plus data |
| ALB | about $0.025 |
| RDS db.t4g.micro | about $0.016 |
| CloudFront, S3, ECR, Secrets Manager | cents a month |

About $0.21 an hour while up, so a four-hour lab is under $1. Left running for a month, about $150. The $20 budget emails you at 50% and 100%.

## What to try (and talk about in interviews)

- **Kill a pod**: `kubectl -n shoplane delete pod -l app=catalog --wait=false`, then keep refreshing. The other pod serves while the Deployment replaces the deleted one.
- **Break the database path**: delete the inbound rule on the `shoplane-db` security group in the console and watch `/api/ready` fail, the ALB mark targets unhealthy, and pods stay alive because liveness doesn't depend on the DB.
- **Read the IAM chain**: GitHub OIDC token → `shoplane-github-deploy` role → access entry → Helm. Pod → service account → Pod Identity association → `shoplane-catalog` role → Secrets Manager.
- **Explain the trade-offs**: one NAT gateway (cheap, one AZ of risk), single-AZ RDS (cheap, no failover yet), Spot nodes (cheap, can be reclaimed), HTTP between CloudFront and the ALB (fixed in phase 4).
