resource "aws_dynamodb_table" "items" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    project    = "cicd-first-build"
    env        = var.stage_name
    managed-by = "terraform"
  }
}
