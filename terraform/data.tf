data "terraform_remote_state" "persistent" {
  backend = "s3"

  config = {
    bucket = "bedrock-tfstate-alt-soe-tin-025-004"
    key    = "project-bedrock/rds-terraform.tfstate"
    region = "us-east-1"
  }
}