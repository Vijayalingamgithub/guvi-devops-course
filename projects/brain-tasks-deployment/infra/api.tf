resource "aws_dynamodb_table" "tasks" {
  name         = "${local.prefix}-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"
  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
}

resource "aws_ecr_repository" "api" {
  name                 = "${local.prefix}-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest 20 API releases"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_iam_role" "api" {
  name = "${local.prefix}-api"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "api" {
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:DescribeTable"]
      Resource = aws_dynamodb_table.tasks.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "brain-tasks"
  service_account = "brain-tasks-api"
  role_arn        = aws_iam_role.api.arn
  depends_on      = [aws_iam_role_policy.api]
}

output "api_repository_uri" {
  value = aws_ecr_repository.api.repository_url
}
output "tasks_table_name" {
  value = aws_dynamodb_table.tasks.name
}
output "application_source_cidrs" {
  value = concat(var.administrator_cidrs, [for nat in aws_eip.nat : "${nat.public_ip}/32"])
}
