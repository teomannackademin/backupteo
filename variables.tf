
# vilken mapp som ska säkerhetskopieras
variable "source_dir" {
  type        = string
  description = "Mappen som ska säkerhetskopieras"

  default = "C:\\Users\\PC\\Documents"
}

# vilka filändelser som ska inte tas med
variable "excluded_extensions" {
  type        = list(string)
  description = "Filändelser som inte ska säkerhetskopieras"

  default = [".tmp", ".bak"]
}
