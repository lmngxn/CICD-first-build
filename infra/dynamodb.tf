resource "aws_dynamodb_table" "items" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
  tags = {
    project = "cicd-first-build"
    env     = var.stage_name
    managed-by = "terraform"
  }
}
