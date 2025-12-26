# AWS Serverless ETL Pipeline with Glue & Athena

A production-grade serverless data pipeline built with Terraform, featuring automated data ingestion, transformation, cataloging, and querying capabilities using AWS managed services.

## 🏗️ Architecture Overview

This infrastructure implements a complete serverless ETL (Extract, Transform, Load) pipeline with the following components:

```
Raw Data (S3) → Lambda Transform → Curated Data (S3) → Glue Crawler → Athena Query
```

### Key Components

- **S3 Buckets**: Raw and curated data lakes with versioning and CORS enabled
- **Lambda Function**: Event-driven data transformation triggered by S3 uploads
- **AWS Glue**: Automated data cataloging and schema discovery
- **Amazon Athena**: SQL-based querying of data lake
- **CloudWatch**: Centralized logging and monitoring

### Architecture Diagram

```
┌─────────────┐
│ Raw Bucket  │
│   (S3)      │
└──────┬──────┘
       │ S3 Event
       ▼
┌─────────────────┐
│ Lambda Function │──┐
│ (Transformation)│  │ Python Dependencies
└────────┬────────┘  │ (Lambda Layer)
         │           │
         ▼           ▼
    ┌─────────────────┐
    │ Curated Bucket  │
    │      (S3)       │
    └────────┬────────┘
             │
             ▼
      ┌─────────────┐
      │Glue Crawler │
      └──────┬──────┘
             │
             ▼
    ┌────────────────┐
    │ Glue Database  │
    │  Data Catalog  │
    └────────┬───────┘
             │
             ▼
       ┌──────────┐      ┌──────────────┐
       │  Athena  │─────▶│Athena Results│
       │Workgroup │      │   Bucket     │
       └──────────┘      └──────────────┘
```

## 📋 Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) v2.x configured with credentials
- [Python](https://www.python.org/downloads/) 3.12 for Lambda development
- [zip](https://linux.die.net/man/1/zip) utility for packaging Lambda code

### AWS Permissions
Your IAM user/role needs permissions for:
- S3 (buckets, objects, notifications)
- Lambda (functions, layers, permissions)
- IAM (roles, policies)
- Glue (databases, tables, crawlers)
- Athena (workgroups, queries)
- CloudWatch Logs (log groups, streams)

## 📁 Project Structure

```
.
├── main.tf                          # Main infrastructure configuration
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── terraform.tfvars                 # Variable values (gitignored)
├── modules/
│   ├── s3/                          # S3 bucket module
│   ├── lambda/                      # Lambda function module
│   └── iam/                         # IAM role/policy module
└── files/
    ├── lambda.zip                   # Lambda function code
    └── python.zip                   # Lambda dependencies layer
```

## 🚀 Quick Start

### 1. Clone and Prepare

```bash
git clone <repository-url>
cd serverless-etl-pipeline
```

### 2. Create Lambda Deployment Package

Create your Lambda function code:

```bash
mkdir -p lambda_src
cd lambda_src

cat > lambda_function.py <<'EOF'
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Transform raw data and write to curated bucket
    """
    try:
        # Get bucket and object info from event
        source_bucket = event['Records'][0]['s3']['bucket']['name']
        source_key = event['Records'][0]['s3']['object']['key']
        
        # Download the file
        response = s3.get_object(Bucket=source_bucket, Key=source_key)
        content = response['Body'].read().decode('utf-8')
        
        # Transform data (example: add timestamp)
        data = json.loads(content)
        data['processed_at'] = datetime.utcnow().isoformat()
        data['processed'] = True
        
        # Write to curated bucket
        curated_bucket = os.environ['CURATED_BUCKET_NAME']
        curated_key = f"processed/{source_key}"
        
        s3.put_object(
            Bucket=curated_bucket,
            Key=curated_key,
            Body=json.dumps(data),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed {source_key}')
        }
        
    except Exception as e:
        print(f"Error processing object: {str(e)}")
        raise e
EOF

# Package Lambda function
zip -r ../files/lambda.zip lambda_function.py
cd ..
```

### 3. Create Lambda Layer (Dependencies)

```bash
mkdir -p python/lib/python3.12/site-packages
pip install boto3 -t python/lib/python3.12/site-packages/
zip -r files/python.zip python
rm -rf python
```

### 4. Configure Variables

Create `terraform.tfvars`:

```hcl
glue_database_name = "etl_database"
glue_table_name    = "raw_data_table"
glue_crawler_name  = "etl_data_crawler"
```

### 5. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### 6. Upload Test Data

```bash
# Get bucket name from Terraform output
RAW_BUCKET=$(terraform output -raw raw_bucket_name)

# Create sample data
cat > sample_data.json <<EOF
{
  "id": 1,
  "name": "Test Record",
  "value": 100,
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

# Upload to raw bucket (triggers Lambda)
aws s3 cp sample_data.json s3://${RAW_BUCKET}/data/sample_data.json
```

## 🔧 Configuration

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `glue_database_name` | Name of Glue catalog database | - | Yes |
| `glue_table_name` | Name of Glue catalog table | - | Yes |
| `glue_crawler_name` | Name of Glue crawler | - | Yes |

### Lambda Environment Variables

The Lambda function automatically receives:
- `CURATED_BUCKET_NAME`: Target bucket for transformed data

### S3 Bucket Configuration

All buckets are configured with:
- **Versioning**: Enabled for data recovery
- **CORS**: Configured for GET and PUT operations
- **Force Destroy**: Enabled for easy cleanup (⚠️ use cautiously in production)

## 📊 Data Flow

### 1. Data Ingestion
Upload raw data files to the raw S3 bucket:
```bash
aws s3 cp data.json s3://raw-bucket-<id>/input/data.json
```

### 2. Automatic Transformation
- S3 triggers Lambda function on object creation
- Lambda processes and transforms the data
- Transformed data is written to curated bucket

### 3. Cataloging
Run Glue Crawler to discover schema:
```bash
aws glue start-crawler --name <crawler-name>
```

### 4. Querying
Query data using Athena:
```sql
SELECT * FROM etl_database.raw_data_table 
WHERE processed = true 
LIMIT 10;
```

## 🔍 Monitoring & Logging

### CloudWatch Logs

Lambda function logs are automatically sent to CloudWatch:
```bash
aws logs tail /aws/lambda/serverless-transformation-function-<id> --follow
```

### Glue Crawler Logs

Monitor crawler execution:
```bash
aws glue get-crawler --name <crawler-name>
```

### Athena Query History

View query execution:
```bash
aws athena list-query-executions --work-group athena-glue-wg
```

## 🔐 Security Considerations

### Current Configuration

✅ **Implemented:**
- IAM roles with least-privilege policies
- S3 versioning for data recovery
- CloudWatch logging enabled
- Separate buckets for raw, curated, and results data

⚠️ **Requires Hardening:**

1. **CORS Configuration**
   ```hcl
   # Current: Allows all origins
   allowed_origins = ["*"]
   
   # Production: Restrict to specific domains
   allowed_origins = ["https://yourdomain.com"]
   ```

2. **S3 Bucket Policies**
   - Add bucket policies to restrict access
   - Enable S3 Block Public Access
   - Implement S3 access logging

3. **Encryption**
   ```hcl
   # Add to S3 module
   server_side_encryption_configuration {
     rule {
       apply_server_side_encryption_by_default {
         sse_algorithm     = "aws:kms"
         kms_master_key_id = aws_kms_key.s3.arn
       }
     }
   }
   ```

4. **VPC Configuration**
   - Deploy Lambda in VPC for network isolation
   - Use VPC endpoints for S3 access
   - Restrict security group rules

5. **Data Lifecycle**
   ```hcl
   lifecycle_rule {
     enabled = true
     
     transition {
       days          = 30
       storage_class = "STANDARD_IA"
     }
     
     transition {
       days          = 90
       storage_class = "GLACIER"
     }
   }
   ```

### Recommended Security Enhancements

```hcl
# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "raw_bucket" {
  bucket = module.raw_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Access Logging
resource "aws_s3_bucket_logging" "raw_bucket" {
  bucket = module.raw_bucket.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "raw-bucket-logs/"
}

# KMS Key for Encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}
```

## 💰 Cost Optimization

### Current Cost Drivers

1. **S3 Storage**
   - Raw bucket: $0.023 per GB/month (Standard)
   - Curated bucket: $0.023 per GB/month (Standard)
   
2. **Lambda Invocations**
   - Free tier: 1M requests/month
   - After: $0.20 per 1M requests

3. **Glue Crawler**
   - $0.44 per DPU-hour (10 DPU minimum)
   
4. **Athena Queries**
   - $5.00 per TB scanned

### Optimization Strategies

```hcl
# 1. Implement S3 Lifecycle Policies
resource "aws_s3_bucket_lifecycle_configuration" "raw_bucket" {
  bucket = module.raw_bucket.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# 2. Partition data in Glue for efficient Athena queries
# Use partitioning: year=2024/month=01/day=01/

# 3. Compress data
# Use Parquet or ORC format for better compression

# 4. Schedule Glue Crawler
resource "aws_glue_trigger" "scheduled" {
  name     = "scheduled-crawler"
  type     = "SCHEDULED"
  schedule = "cron(0 2 * * ? *)" # Run daily at 2 AM

  actions {
    crawler_name = aws_glue_crawler.crawler.name
  }
}
```

## 🧪 Testing

### Unit Test Lambda Function

```python
# test_lambda.py
import json
from lambda_function import lambda_handler

def test_lambda_handler():
    event = {
        'Records': [{
            's3': {
                'bucket': {'name': 'test-bucket'},
                'object': {'key': 'test.json'}
            }
        }]
    }
    
    response = lambda_handler(event, {})
    assert response['statusCode'] == 200
```

### Integration Testing

```bash
#!/bin/bash
# integration_test.sh

# Upload test file
aws s3 cp test_data.json s3://${RAW_BUCKET}/test/test_data.json

# Wait for processing
sleep 10

# Verify in curated bucket
aws s3 ls s3://${CURATED_BUCKET}/processed/test/

# Run crawler
aws glue start-crawler --name ${CRAWLER_NAME}

# Wait for crawler
sleep 60

# Query with Athena
aws athena start-query-execution \
  --query-string "SELECT * FROM ${DATABASE}.${TABLE} LIMIT 1" \
  --result-configuration "OutputLocation=s3://${ATHENA_BUCKET}/" \
  --work-group athena-glue-wg
```

## 🔄 CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/terraform.yml
name: Terraform Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
          
      - name: Terraform Init
        run: terraform init
        
      - name: Terraform Plan
        run: terraform plan
        
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
```

## 📈 Scaling Considerations

### Lambda Scaling
- Automatically scales to 1000 concurrent executions
- Reserved concurrency can be set for predictable workloads
- Consider using SQS queue for rate limiting

### Glue Crawler Optimization
```hcl
resource "aws_glue_crawler" "crawler" {
  # ... existing config ...
  
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
  
  # Exclude patterns to reduce crawl time
  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }
}
```

### Athena Performance
- Use columnar formats (Parquet, ORC)
- Partition data by date
- Use CTAS (Create Table As Select) for materialized views
- Implement query result caching

## 🧹 Cleanup

### Destroy All Resources

```bash
# Remove all S3 objects first
aws s3 rm s3://$(terraform output -raw raw_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw curated_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw athena_results_bucket_name) --recursive

# Destroy infrastructure
terraform destroy
```

⚠️ **Warning**: This will permanently delete all data. Ensure you have backups.

## 🐛 Troubleshooting

### Lambda Not Triggering

**Issue**: Files uploaded to S3 but Lambda doesn't execute

**Solutions**:
```bash
# Check Lambda permissions
aws lambda get-policy --function-name <function-name>

# Verify S3 event configuration
aws s3api get-bucket-notification-configuration --bucket <bucket-name>

# Check CloudWatch logs
aws logs tail /aws/lambda/<function-name> --follow
```

### Glue Crawler Fails

**Issue**: Crawler shows failed status

**Solutions**:
```bash
# Check crawler details
aws glue get-crawler --name <crawler-name>

# View crawler metrics
aws glue get-crawler-metrics --crawler-name-list <crawler-name>

# Verify IAM permissions
aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>
```

### Athena Query Fails

**Issue**: Queries return errors or no results

**Solutions**:
```sql
-- Check table exists
SHOW TABLES IN etl_database;

-- Verify table schema
DESCRIBE etl_database.raw_data_table;

-- Check partitions
SHOW PARTITIONS etl_database.raw_data_table;

-- Repair partitions if needed
MSCK REPAIR TABLE etl_database.raw_data_table;
```

### Permission Errors

```bash
# Verify IAM role trust relationship
aws iam get-role --role-name <role-name>

# Test S3 access from Lambda
aws lambda invoke \
  --function-name <function-name> \
  --payload '{"test": "event"}' \
  response.json
```

## 📚 Additional Resources

- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/enhancement`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/enhancement`)
5. Create a Pull Request

### Development Guidelines
- Follow Terraform best practices
- Add tests for Lambda functions
- Update documentation for any changes
- Use meaningful commit messages

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Support

- **Issues**: Create an issue in the GitHub repository
- **Email**: data-engineering@yourcompany.com
- **Slack**: #data-engineering channel

## 🔖 Version History

- **v1.0.0** (2024-01-01): Initial release
  - Basic ETL pipeline with Lambda, Glue, and Athena
  - S3 event-driven processing
  - Automated schema discovery

---

**Built with** ❤️ **using Terraform and AWS Serverless Services**
