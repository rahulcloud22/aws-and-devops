output "user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "hosted_ui_url" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "wss_url" {
  value = aws_apigatewayv2_stage.dev.invoke_url
}