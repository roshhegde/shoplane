# Shoplane design

Status: phase 1 (design). Nothing is deployed yet. The interactive version is at https://roshhegde.github.io/shoplane/.

## Summary

Shoplane is a small AI-assisted e-commerce store built in 9 phases, each shipped as one pull request with a demo, a write-up and a teardown. The store runs on AWS in us-east-1 across 2 Availability Zones. The AI layer runs on Google Cloud in us-east4, which is also in northern Virginia, so the network hop between the clouds adds only a few milliseconds.

The AI layer moved to Google Cloud because the AWS Bedrock quota request had no answer, and because a working AWS-to-GCP integration is valuable experience in its own right.

## Architecture

| Layer | Cloud | Services | Role |
| --- | --- | --- | --- |
| Edge | AWS | Route 53, CloudFront, ACM, WAF, S3, Cognito | One domain for everything; customers never talk to Google Cloud directly |
| Containers and network | AWS | VPC (2 AZs), NAT Gateway, ALB, EKS with a managed node group, AWS Load Balancer Controller, ECR | Highly available catalog and search service as pods in private subnets |
| Databases and cache | AWS | RDS PostgreSQL (Multi-AZ from phase 5), ElastiCache | Products, prices and inventory; cache-aside for reads |
| Serverless, events, data | AWS | API Gateway, Lambda, DynamoDB, Step Functions, EventBridge, SQS, SNS, Data Firehose, S3 data lake | Cart, checkout saga, events, AI proxy, product sync, raw event history |
| AI layer | Google Cloud | Workload Identity Federation, Cloud Run, Vertex AI embeddings, Vertex AI Vector Search, Gemini, Cloud Storage, Storage Transfer Service, BigQuery, Vertex AI training, Cloud Monitoring, billing budget | Semantic search, RAG assistant, recommendations |
| Security and operations | AWS | IAM with GitHub OIDC, KMS, Secrets Manager, GuardDuty, CloudTrail, CloudWatch, X-Ray, Budgets, GitHub Actions | Least privilege, encryption, detection, observability, CI/CD |

### Flows

- **Browse and search:** CloudFront, ALB, catalog pods on EKS and the cache. A search query goes to Cloud Run, which embeds it and asks Vector Search for product IDs. AWS loads prices and stock from Postgres. If Google Cloud doesn't answer within 800 ms, the service falls back to keyword SQL.
- **Checkout and order events:** Cognito JWT, API Gateway, Lambda, a Step Functions saga, then EventBridge fan-out to SQS, SNS and the data lake. Checkout never calls Google Cloud.
- **Shopping assistant (RAG):** the AI proxy Lambda checks the customer, adds chat history and calls Cloud Run. Cloud Run embeds the question, retrieves the top 5 products and FAQ chunks, and asks Gemini for a grounded answer with citations.
- **Sync products to GCP:** a ProductUpdated event triggers a worker that sends the product text to Cloud Run, which re-embeds it and upserts it into Vector Search within seconds. A nightly export rebuilds the index.
- **Data and recommendations:** clickstream lands in S3 as Parquet. Storage Transfer Service copies new files to Cloud Storage nightly, BigQuery builds a "bought together" baseline, a Vertex AI training job produces recommendations, and a worker copies them into DynamoDB.
- **Failure drills:** an AZ outage (ALB reroutes, RDS fails over) and a Google Cloud outage (search degrades to keyword, the assistant goes offline, checkout is unaffected).
- **Deploy a change:** one GitHub Actions workflow plans and applies both clouds, signing in to AWS through OIDC and to Google Cloud through Workload Identity Federation.

## Cross-cloud design

**Calls over HTTPS.** Every cross-cloud call goes from AWS to Cloud Run over HTTPS. Cloud Run requires authentication, so it rejects any call without a valid Google token.

**Workload Identity Federation, no stored keys.** A Google workload identity pool has an AWS provider for the Shoplane AWS account. An attribute condition admits only the AI proxy, catalog and worker IAM role ARNs. Those roles sign an AWS GetCallerIdentity request with their own credentials, Google's Security Token Service exchanges it for a federated token, and the caller impersonates one service account with only `roles/run.invoker` and `roles/aiplatform.user`. Tokens last an hour and are cached. A second provider in the same pool trusts GitHub Actions for deploys. The one call in the other direction, Storage Transfer Service reading the S3 lake, assumes a read-only AWS role that trusts Google's service agent. No access key or service-account key exists anywhere.

**One Terraform configuration, two providers.** The `ai` stack declares both the `aws` and `google` providers. The identity pool's attribute condition reads AWS role ARNs straight from AWS resources, and the Lambda's environment reads the pool's audience from Google resources, so one `terraform plan` covers both sides with no copied IDs.

**EKS pods calling Google Cloud.** Catalog pods get AWS credentials from EKS Pod Identity. Google's auth library reads AWS credentials from environment variables or the EC2 metadata service, not from Pod Identity, so the service passes them in with a small custom credentials supplier (about 10 lines using boto3).

**Product data sync.** AWS stays the source of truth. Changed products are pushed to Cloud Run as small JSON payloads (a few kilobytes each) and embedded with Vertex AI; only product IDs and scores come back.

### Trade-offs

| Concern | Impact | How the design handles it |
| --- | --- | --- |
| Latency | A few ms network hop; token exchange; Cloud Run cold starts of 1 to 3 seconds after idle | Same metro area, cached tokens, search results cached in ElastiCache |
| Egress | AWS bills about $0.09 per GB leaving, after 100 GB free each month | Only text, IDs and scores cross; the lake copy is incremental Parquet |
| Two bills | Two consoles, two budgets | A $20 budget alert per cloud; a combined cost report in phase 9; Google's $300 trial credit covers the AI layer at first |
| Two failure domains | Google Cloud can fail independently | Search degrades to keyword SQL, the assistant shows "unavailable", checkout never depends on GCP |
| Two IAM models | More to audit | Trust runs one way (AWS calls GCP), plus one read-only role for Storage Transfer |

## Web tier: EKS

The catalog service runs on Amazon EKS, chosen over ECS Fargate because Kubernetes is the container skill most job ads ask for, and tfmodules already has `eks-cluster` and `eks-node-group`. A managed node group of 2 Graviton (t4g.medium) Spot nodes spans both AZs. The AWS Load Balancer Controller creates the ALB from an Ingress, EKS Pod Identity gives each service account its own IAM role, and a topology spread constraint plus a PodDisruptionBudget keep pods in both AZs. The control plane costs $0.10 an hour, so the cluster is created and destroyed with each lab (10 to 15 minutes each way).

## Phase roadmap

| Phase | What gets built | What you learn |
| --- | --- | --- |
| 1. Design | Architecture page, flows, decisions, cost model, module gaps | Trade-offs, multi-AZ and multi-cloud design, costing before building |
| 2. Core app (AWS) | VPC across 2 AZs, NAT, EKS cluster with 2 Graviton nodes, AWS Load Balancer Controller, ALB, RDS PostgreSQL, S3 + CloudFront, ECR, GitHub Actions with OIDC, budget | 3-tier networking, Kubernetes on EKS, Ingress, Pod Identity, CDN, IaC pipelines |
| 3. API and events (AWS) | Cognito, API Gateway, Lambdas, DynamoDB, Step Functions, EventBridge, SQS, SNS | Serverless APIs, JWT auth, sagas, idempotency, events |
| 4. Secure (AWS) | WAF, KMS, Secrets Manager, GuardDuty, CloudTrail, IAM review | Defence in depth, encryption, threat detection |
| 5. HA and scale (AWS) | RDS Multi-AZ, second NAT, ElastiCache, HPA and Karpenter autoscaling, Route 53 health checks, load test, AZ drill | Failover, caching, autoscaling |
| 6. GCP foundation and search | GCP project and budget, Workload Identity Federation, Cloud Run, Vertex AI embeddings, Vector Search, product sync, semantic search with fallback | GCP basics, keyless cross-cloud identity, embeddings, vector search |
| 7. Shopping assistant on Gemini | AI proxy Lambda, hand-written RAG, Gemini with system instructions and safety settings, a 30-question evaluation set | Prompting, grounding, hallucination, token cost, evaluation |
| 8. Data and recommendations | Firehose, S3 lake, Storage Transfer, BigQuery baseline, Vertex AI training, results copied to DynamoDB | Cross-cloud data movement, training versus inference, baselines |
| 9. Operate | Dashboards in both clouds, X-Ray, cross-cloud latency alarms, runbooks, cost report | Observability, AI ops, FinOps |

## Costs and teardown

Approximate list prices for AWS us-east-1 and Google Cloud us-east4; confirm in each pricing calculator. With every phase running, the stack costs about $310 to $340 a month (about $10 to $11 a day). A four-hour lab costs about $2.

Terraform is split into stacks so the expensive layers can be destroyed without touching state or identity:

- **aws-foundation** (keep): state bucket, GitHub OIDC role, budget, ECR, KMS, Cognito, DynamoDB tables, S3 buckets.
- **gcp-foundation** (keep): project services, workload identity pool, service accounts, budget, buckets.
- **network** (destroy): VPC, NAT gateways.
- **app** (destroy): EKS cluster and node group, ALB, RDS, ElastiCache.
- **serverless** (can stay): API Gateway, Lambda, Step Functions, EventBridge, SQS, SNS, Firehose.
- **ai** (destroy or undeploy): Vector Search endpoint, Cloud Run service, transfer job, BigQuery tables.

| Phase | If left running | Teardown |
| --- | --- | --- |
| 1. Design | $0 | Nothing |
| 2. Core app | About $150 a month (EKS control plane about $73) | Delete the Ingress first so the controller removes the ALB, then destroy app and network stacks; RDS skips the final snapshot in dev and is reseeded by script |
| 3. API and events | About $1 a month | Pay-per-request, can stay up |
| 4. Secure | About $15 a month | WAF goes with the edge stack; KMS keys enter a 7-day deletion window; disable GuardDuty after the trial |
| 5. HA and scale | About +$60 a month | Run the drill and load test, then destroy the same day |
| 6. GCP foundation and search | About $70 a month, almost all the Vector Search endpoint | Undeploy the index after every lab; Cloud Run scales to zero |
| 7. Assistant on Gemini | Cents per lab | No standing cost beyond phase 6 |
| 8. Data and recommendations | About $3 per lab | Pause the transfer job; delete BigQuery tables and buckets with force_destroy in dev |
| 9. Operate | About $5 a month | Final teardown of everything except the two foundation stacks |

The biggest idle costs are the EKS control plane (about $73 a month plus nodes), the Vector Search endpoint (about $65 to $75 a month), the NAT gateway (about $33 each), the ALB (about $16), and RDS and ElastiCache (about $12 per node).

## Terraform module coverage

| Status | Modules |
| --- | --- |
| Already in tfmodules (AWS) | vpc, subnet, internet-gateway, nat-gateway, route-table, route, route-table-association, security-group, ec2, ecr-repository, eks-cluster, eks-node-group, lambda-function, lambda-permission, apigatewayv2 (api, route, integration, authorizer, stage), cognito-user-pool, cognito-user-pool-client, dynamodb-table, s3-bucket, cloudwatch-log-group, cloudwatch-metric-alarm, iam-role, iam-github-oidc, budget |
| AWS modules to add | route53, acm, cloudfront, alb, rds, eks-pod-identity, eks-addons (with a Helm release for the AWS Load Balancer Controller), karpenter, step-functions, eventbridge, sqs, sns, wafv2, kms, secrets-manager, guardduty, cloudtrail, elasticache, firehose, xray |
| Google Cloud modules to add (none exist yet) | project-services, billing-budget, workload-identity-pool, service-account, cloud-run-service, artifact-registry, vertex-vector-search, storage-bucket, storage-transfer-job, bigquery-dataset, monitoring-alert-policy |

New modules follow the one-module-per-service rule: for example, `rds` covers the instance, subnet group and parameter group.

## Open questions

- Use a real domain for Route 53 and ACM, or the default CloudFront URL until phase 5?
