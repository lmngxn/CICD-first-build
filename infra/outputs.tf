output "api_invoke_url" {
  value       = aws_api_gateway_stage.dev.invoke_url
  description = "Base invoke URL — append /items for the resource path"
}

output "api_key_value" {
  value       = aws_api_gateway_api_key.items.value
  sensitive   = true
  description = "API key value — pass as x-api-key header"
}
