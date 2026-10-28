output "app_id" {
  value = aws_amplify_app.this.id
}

output "arn" {
  value = aws_amplify_app.this.arn
}

output "default_domain" {
  value = aws_amplify_app.this.default_domain
}

output "custom_domain" {
  value = "${var.subdomain_prefix}.${var.zone_domain}"
}
