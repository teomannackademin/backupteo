
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  required_version = ">= 1.5.0"
}

provider "local" {}

# Samlar sökvägar och inställningar
locals {
  source_dir = abspath(var.source_dir)
  backup_dir = "C:\\teobackups"

  # Inställningar som skickas till PowerShell via config.json
  backup_config = {
    source_path         = local.source_dir
    destination_path    = local.backup_dir
    excluded_extensions = var.excluded_extensions
  }
}

# Skapar backupmappen
resource "terraform_data" "backup_folder" {
  triggers_replace = [local.backup_dir]

  provisioner "local-exec" {
    command = "New-Item -ItemType Directory -Path '${local.backup_dir}' -Force | Out-Null"

    interpreter = [
      "PowerShell",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command"
    ]
  }
}

# Skapar config.json med inställningarna
resource "local_file" "config" {
  filename = "${local.backup_dir}/config.json"
  content  = jsonencode(local.backup_config)

  depends_on = [
    terraform_data.backup_folder
  ]
}

# Skapar en informationsfil
resource "local_file" "backup_info" {
  filename = "${local.backup_dir}/backup-info.txt"

  content = <<-EOT
    Backup System
    Source: ${local.source_dir}
    Destination: ${local.backup_dir}
    Managed by Terraform
  EOT

  depends_on = [
    terraform_data.backup_folder
  ]
}

# Kör PowerShell-skriptet för att skapa backup
resource "terraform_data" "run_backup" {

  # Kör om backupen när sökvägar eller skript ändras
  triggers_replace = [
    local.source_dir,
    local.backup_dir,
    filesha256("${path.module}/BackupAndRestore.ps1")
  ]

  provisioner "local-exec" {
    command = "& '${path.module}/BackupAndRestore.ps1' -ConfigPath '${local_file.config.filename}'"

    interpreter = [
      "PowerShell",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command"
    ]
  }

  depends_on = [
    local_file.config,
    local_file.backup_info
  ]
}
