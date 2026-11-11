output "backup_folder" {
  description = "Mappen där alla säkerhetskopior sparas"
  value       = local.backup_dir
}

output "config_file" {
  description = "Terraform-konfigurationen för PowerShell"
  value       = local_file.config.filename
}

output "backup_information" {
  description = "Informationsfil skapad av Terraform"
  value       = local_file.backup_info.filename
}