# ----------------------------------------------------------------------
# Raw Bucket
# ----------------------------------------------------------------------
module "raw_bucket" {
  source        = "./modules/s3"
  bucket_name   = "raw-bucket"
  objects       = []
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

# ----------------------------------------------------------------------
# Curated Bucket
# ----------------------------------------------------------------------
module "curated_bucket" {
  source        = "./modules/s3"
  bucket_name   = "curated-bucket"
  objects       = []
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

# ----------------------------------------------------------------------
# Lambda function ( for transformation )
# ----------------------------------------------------------------------
module "lambda_function_code" {
  source      = "./modules/s3"
  bucket_name = "lambda-function-code"
  objects = [
    {
      key    = "lambda.zip"
      source = "./files/lambda.zip"
    }
  ]
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

module "lambda_function_role" {
  source             = "./modules/iam"
  role_name          = "lambda-function-role"
  role_description   = "IAM role for transformation lambda function"
  policy_name        = "lambda-function-role-policy"
  policy_description = "IAM policy for transformation lambda function"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            }
        ]
    }
    EOF
}

module "lambda_function" {
  source        = "./modules/lambda"
  function_name = "serverless-transformation-function"
  role_arn      = module.lambda_function_role.arn
  permissions   = []
  env_variables = {}
  handler       = "lambda.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.lambda_function_code.bucket
  s3_key        = "lambda.zip"
  layers        = []
}

# ----------------------------------------------------------------------
# Glue configuration ( Crawler & Data catalog)
# ----------------------------------------------------------------------
resource "aws_glue_catalog_database" "database" {
  name        = var.glue_database_name
  description = "Glue database for incremental load"
}

resource "aws_glue_catalog_table" "table" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.database.name
}

module "glue_crawler_role" {
  source             = "./modules/iam"
  role_name          = "lambda-function-role"
  role_description   = "IAM role for transformation lambda function"
  policy_name        = "lambda-function-role-policy"
  policy_description = "IAM policy for transformation lambda function"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "glue.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            },
            {
                  Effect   : "Allow"
                  Action   : [
                    "glue:*"
                  ]
                  Resource : "*"
            },
            {
                  Effect   : "Allow"
                  Action   : [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                  ]
                  Resource : [
                    "${module.curated_bucket.arn}",
                    "${module.curated_bucket.arn}/*"
                  ]
            },
            {
                  Effect   : "Allow"
                  Action   : [
                    "s3:PutObject"
                  ]
                  Resource : "${module.athena_results.arn}"
            }
        ]
    }
    EOF
}

resource "aws_glue_crawler" "crawler" {
  database_name = aws_glue_catalog_database.database.name
  name          = var.glue_crawler_name
  role          = module.glue_crawler_role.arn

  s3_target {
    path = "s3://${module.curated_bucket.bucket}"
  }
}

# ----------------------------------------------------------------------
# Athena configuration
# ----------------------------------------------------------------------
module "athena_results" {
  source        = "./modules/s3"
  bucket_name   = "athena-results"
  objects       = []
  bucket_policy = ""
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
}

resource "aws_athena_workgroup" "etl" {
  name = "athena-glue-wg"
  configuration {
    result_configuration {
      output_location = "s3://${module.athena_results.bucket}/"
    }
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
  }
  state = "ENABLED"
}

resource "aws_athena_named_query" "query" {
  name        = "sample_query"
  database    = aws_glue_catalog_database.database.name
  description = "Query sample table"
  query       = "SELECT * FROM ${aws_glue_catalog_table.table.name} LIMIT 10;"
  workgroup   = aws_athena_workgroup.etl.name
}