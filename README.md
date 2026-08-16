# Project Bedrock

InnovateMart's EKS deployment: the retail-store-sample-app running on Amazon EKS, backed by a managed AWS data layer instead of in-cluster databases, with scoped developer access, CloudWatch observability, an S3-triggered Lambda, and a GitHub Actions pipeline.

## Architecture

Full diagram: `bedrock-architecture.png`.

- **VPC** (`project-bedrock-vpc`): 2 AZs, public + private subnets, one NAT Gateway
- **EKS** (`project-bedrock-cluster`, v1.34): ui, catalog, carts, orders, checkout — all in the `retail-app` namespace
- **Data layer**: RDS MySQL for catalog, RDS PostgreSQL for orders, DynamoDB for carts. Private subnets only. Credentials live in Secrets Manager, not in any committed file.
- **Ingress**: AWS Load Balancer Controller provisions an ALB in front of `ui`
- **Serverless**: upload to the S3 bucket triggers `bedrock-asset-processor`
- **Observability**: EKS control plane logs plus the CloudWatch Observability add-on for container logs
- **Access**: `bedrock-dev-view` gets console ReadOnly, scoped S3 PutObject, and a namespace-scoped EKS Access Entry — view only, verified against real `kubectl` calls, not assumed
- **CI/CD**: GitHub Actions plans on PR and comments the output, applies on merge to `main`

## Why two Terraform states

RDS's network interfaces sit inside the VPC's private subnets. Tear the VPC down nightly with RDS still attached, and AWS blocks the subnet deletion — it won't let Terraform detach an RDS-owned ENI from underneath it. Learned this the hard way partway through the build.

So the VPC and private subnets moved into the state that never gets destroyed, alongside RDS, DynamoDB, and Secrets Manager:

- **`terraform-rds/`** — VPC, private subnets, RDS, DynamoDB, Secrets Manager, S3 assets bucket, Lambda. Stays up for the life of the project.
- **`terraform/`** — public subnets, IGW, NAT Gateway, EKS cluster and node group, OIDC provider, LB Controller IAM role, Access Entries. Destroyed and rebuilt every session to keep cost down. Reads the VPC/subnet IDs from the persistent state via `terraform_remote_state`.

## Running this

**Prerequisites:** AWS CLI configured for account `641240771475`, Terraform >= 1.11, kubectl, Helm.

**Persistent layer, one time:**
```
cd terraform-rds
terraform init
terraform apply
```

**Rebuildable layer, every session:**
```
cd terraform
terraform init
terraform apply
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::641240771475:role/project-bedrock-lb-controller-role \
  --set region=us-east-1 \
  --set vpcId=<vpc_id from terraform-rds output>

kubectl create namespace retail-app
kubectl apply -f ../k8s

kubectl create secret generic catalog-db -n retail-app \
  --from-literal=RETAIL_CATALOG_PERSISTENCE_USER=admin \
  --from-literal=RETAIL_CATALOG_PERSISTENCE_PASSWORD=<from Secrets Manager: bedrock/catalog-mysql>

kubectl create secret generic orders-db -n retail-app \
  --from-literal=RETAIL_ORDERS_PERSISTENCE_USERNAME=dbadmin \
  --from-literal=RETAIL_ORDERS_PERSISTENCE_PASSWORD=<from Secrets Manager: bedrock/orders-postgres>

kubectl create secret generic orders-rabbitmq -n retail-app \
  --from-literal=RETAIL_ORDERS_MESSAGING_RABBITMQ_USERNAME=orders \
  --from-literal=RETAIL_ORDERS_MESSAGING_RABBITMQ_PASSWORD=<choose a value>
```

The store's URL shows up under `kubectl get ingress -n retail-app` once the ALB finishes provisioning, usually 2-3 minutes after apply.

## CI/CD

`.github/workflows/terraform.yml`, scoped to `terraform/**` only — changes to the persistent RDS layer stay manual, on purpose, given what that state holds.

- PR against `main` touching `terraform/` → `terraform plan`, posted as a PR comment
- Merge to `main` → `terraform apply`
- Auth: IAM user `bedrock-cicd`, Access Keys in GitHub repo secrets. The assessment allows Access Keys as a fallback to OIDC; used that fallback deliberately to avoid burning a full session on GitHub's OIDC federation setup this late in the build.

The plan-on-PR path ran end to end against a real PR and posted a real comment. Apply-on-merge wasn't fired during development — merging would have spun up the full nightly stack outside a planned session — but it runs the same `terraform apply` already executed manually dozens of times over the course of this build.

## Tearing it down

**After each session:**
```
kubectl delete ingress ui -n retail-app
```
Wait 60-90 seconds — the ALB comes from the LB Controller, not Terraform, and it'll block subnet teardown if it's still around.

```
cd terraform
terraform destroy
```

Confirm nothing's left:
```
aws eks list-clusters --region us-east-1
aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=project-bedrock-nat" --query "NatGateways[?State!='deleted']"
```
Both empty means clean.

**End of project, persistent layer too:**
```
cd terraform-rds
terraform destroy
```
Empty the S3 bucket first if it has objects: `aws s3 rm s3://bedrock-assets-alt-soe-tin-025-004 --recursive`.

**Terraform won't clean these up on its own:**
- CloudWatch log groups outlive the cluster — `aws logs delete-log-group --log-group-name <name>` for each of `/aws/eks/project-bedrock-cluster/cluster` and the `/aws/containerinsights/project-bedrock-cluster/*` group
- Any ECR images pushed during the build
- `bedrock-cicd` and `bedrock-dev-view` access keys — deactivate or rotate once grading wraps: `aws iam update-access-key --user-name <user> --access-key-id <key-id> --status Inactive`

## For the grader

RDS's security group allows inbound from the full VPC CIDR rather than just the node/pod range — still private-subnet-only, no public exposure, just broader than the tightest possible scope.

Bonus objectives weren't attempted. Time went entirely into getting core requirements working correctly rather than spreading thin across both.
