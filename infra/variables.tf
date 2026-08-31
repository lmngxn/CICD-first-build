variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "items"
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}
