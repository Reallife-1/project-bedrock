output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
output "carts_table_arn" {
  value = aws_dynamodb_table.carts.arn
}

output "carts_table_name" {
  value = aws_dynamodb_table.carts.name
}