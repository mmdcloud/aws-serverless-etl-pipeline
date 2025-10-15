variable "region" {
  type    = string
  default = "us-east-1"
}

variable "glue_database_name" {
  type    = string
  default = "etl-db"
}

variable "glue_table_name" {
  type    = string
  default = "etl-table"
}

variable "glue_crawler_name" {
  type    = string
  default = "etl-crawler"
}
