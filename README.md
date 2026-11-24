# Shoplane

An AI-assisted e-commerce store built one production upgrade at a time, as a hands-on portfolio project.

- **AWS (us-east-1)** runs the store: a highly available 3-tier core, serverless checkout, events and a security layer.
- **Google Cloud (us-east4)** runs the AI layer: semantic search, a Gemini shopping assistant and recommendations.
- The clouds talk over HTTPS using **Workload Identity Federation**, so no cloud credentials are stored anywhere.
- Everything is built with Terraform from one configuration that uses both the `aws` and `google` providers, using modules from [roshhegde/tfmodules](https://github.com/roshhegde/tfmodules).

## Interactive architecture

**[Open the architecture explorer](https://roshhegde.github.io/shoplane/)**. Pick a flow (browse and search, checkout, the RAG assistant, product sync to GCP, data and recommendations, failure drills, deploys) and press Play to watch a request move through the system. Click any component to see what it does, why it was chosen, what it costs and which Terraform module builds it.

The page source is [`docs/index.html`](docs/index.html), and the written design is in [`docs/DESIGN.md`](docs/DESIGN.md).

## Build phases

| Phase | Focus | Status |
| --- | --- | --- |
| 1 | Design: architecture, flows, costs, module gaps | Done |
| 2 | Core app on AWS: VPC, EKS, ALB, RDS, S3 + CloudFront, CI/CD | Planned |
| 3 | API and events: Cognito, API Gateway, Lambda, DynamoDB, Step Functions, EventBridge, SQS, SNS | Planned |
| 4 | Secure: WAF, KMS, Secrets Manager, GuardDuty, CloudTrail | Planned |
| 5 | HA and scale: Multi-AZ RDS, ElastiCache, autoscaling, failure drill | Planned |
| 6 | GCP foundation and search: Workload Identity Federation, Cloud Run, Vertex AI embeddings, Vector Search | Planned |
| 7 | Shopping assistant: retrieval-augmented generation with Gemini | Planned |
| 8 | Data and recommendations: Storage Transfer, BigQuery, Vertex AI training | Planned |
| 9 | Operate: dashboards, tracing, alarms, cost report | Planned |

## Cost and teardown

Nothing here runs all the time. Each phase is built, demonstrated and destroyed in a session. A four-hour lab costs about $2 across both clouds, while leaving everything running would cost about $310 to $340 a month. Each phase's notes include its teardown steps, and each cloud has a $20 budget alert.

## License

[MIT](LICENSE)
