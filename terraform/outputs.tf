output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}
output "cluster_name" {
  value = aws_eks_cluster.main.name
}
output "region" {
  value = "us-east-1"
}
output "vpc_id" {
  value = data.terraform_remote_state.persistent.outputs.vpc_id
}