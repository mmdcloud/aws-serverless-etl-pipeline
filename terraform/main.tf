resource "random_id" "id" {
  byte_length = 8
}

# ----------------------------------------------------------------------
# Raw Bucket
# ----------------------------------------------------------------------
module "raw_bucket" {
  source      = "./modules/s3"
  bucket_name = "raw-bucket-${random_id.id.hex}"
  objects     = []
  bucket_notification = {
    queue = []
    lambda_function = [
      {
        lambda_function_arn = module.lambda_function.arn
        events              = ["s3:ObjectCreated:*"]
      }
    ]
  }
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
  bucket_name   = "curated-bucket-${random_id.id.hex}"
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
  bucket_name = "lambda-function-code-${random_id.id.hex}"
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
  role_name          = "lambda-function-role-${random_id.id.hex}"
  role_description   = "IAM role for transformation lambda function"
  policy_name        = "lambda-function-role-policy-${random_id.id.hex}"
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
  function_name = "serverless-transformation-function-${random_id.id.hex}"
  role_arn      = module.lambda_function_role.arn
  permissions = [
    {
      action       = "lambda:InvokeFunction"
      principal    = "s3.amazonaws.com"
      source_arn   = "${module.raw_bucket.arn}"
      statement_id = "AllowS3Invoke"
    }
  ]
  env_variables = {
    CURATED_BUCKET_NAME = "${module.curated_bucket.bucket}"
  }
  handler   = "lambda_function.lambda_handler"
  runtime   = "python3.12"
  s3_bucket = module.lambda_function_code.bucket
  s3_key    = "lambda.zip"
  layers    = []
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
  role_name          = "glue-crawler-role-${random_id.id.hex}"
  role_description   = "IAM role for Glue crawler"
  policy_name        = "glue-crawler-role-policy-${random_id.id.hex}"
  policy_description = "IAM policy for Glue crawler"
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
                  "Effect"   : "Allow",
                  "Action"   : [
                    "glue:*"
                  ],
                  "Resource" : "*"
            },
            {
                  "Effect"   : "Allow",
                  "Action"   : [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                  ],
                  "Resource" : [
                    "${module.curated_bucket.arn}",
                    "${module.curated_bucket.arn}/*"
                  ]
            },
            {
                  "Effect"   : "Allow",
                  "Action"   : [
                    "s3:PutObject"
                  ],
                  "Resource" : "${module.athena_results.arn}"
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
  bucket_name   = "athena-results-${random_id.id.hex}"
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

resource "aws_athena_named_query" "etl_query" {
  name        = "etl_query"
  database    = aws_glue_catalog_database.database.name
  description = "Query sample table"
  query       = "SELECT * FROM ${aws_glue_catalog_table.table.name} LIMIT 10;"
  workgroup   = aws_athena_workgroup.etl.name
}