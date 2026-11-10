resource "local_file" "config" {
  filename = "${path.module}/config.json"
  content  = jsonencode({ Environment = "Development", BackupPath = "./backup" })
}