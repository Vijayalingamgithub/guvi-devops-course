resource "aws_codestarconnections_connection" "github" {
  count         = var.github_connection_arn == "" ? 1 : 0
  name          = "${local.prefix}-github"
  provider_type = "GitHub"
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${local.build}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "verify" {
  name              = "/aws/codebuild/${local.verify}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/codepipeline/${local.pipeline}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "build" {
  name = "${local.prefix}-codebuild"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role" "verify" {
  name = "${local.prefix}-verify"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role" "pipeline" {
  name = "${local.prefix}-codepipeline"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

locals {
  artifact_permissions = [
    { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:ListBucket"], Resource = aws_s3_bucket.artifacts.arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = "${aws_s3_bucket.artifacts.arn}/*" },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:ReEncrypt*"], Resource = aws_kms_key.artifacts.arn }
  ]
  # AWS managed EKS actions and VPC CodeBuild require these network discovery/ENI actions.
  network_permissions = [{
    Effect = "Allow"
    Action = [
      "ec2:CreateNetworkInterface", "ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces", "ec2:DescribeDhcpOptions", "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs", "ec2:DescribeRouteTables"
    ]
    Resource = "*"
  }]
}

resource "aws_iam_role_policy" "build" {
  role = aws_iam_role.build.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.artifact_permissions, [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.build.arn}:*" },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:DescribeRepositories", "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages"], Resource = [aws_ecr_repository.app.arn, aws_ecr_repository.api.arn] }
    ])
  })
}

resource "aws_iam_role_policy" "verify" {
  role = aws_iam_role.verify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.artifact_permissions, local.network_permissions, [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.verify.arn}:*" },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = aws_eks_cluster.main.arn },
      { Effect = "Allow", Action = ["elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth"], Resource = "*" }
    ])
  })
}

resource "aws_iam_role_policy" "pipeline" {
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.artifact_permissions, local.network_permissions, [
      { Effect = "Allow", Action = ["codestar-connections:UseConnection", "codeconnections:UseConnection"], Resource = local.connection },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = [aws_codebuild_project.build.arn, aws_codebuild_project.verify.arn] },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = aws_eks_cluster.main.arn },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = [aws_cloudwatch_log_group.pipeline.arn, "${aws_cloudwatch_log_group.pipeline.arn}:*"] }
    ])
  })
}

resource "aws_codebuild_project" "build" {
  name           = local.build
  description    = "Validate compiled React assets, build and test the image, then push to ECR"
  service_role   = aws_iam_role.build.arn
  build_timeout  = 20
  encryption_key = aws_kms_key.artifacts.arn
  source {
    type      = "CODEPIPELINE"
    buildspec = "${var.project_directory}/buildspec.yml"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "PROJECT_DIRECTORY"
      value = var.project_directory
    }
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.app.repository_url
    }
    environment_variable {
      name  = "ECR_REPOSITORY_NAME"
      value = aws_ecr_repository.app.name
    }
    environment_variable {
      name  = "API_REPOSITORY_URI"
      value = aws_ecr_repository.api.repository_url
    }
    environment_variable {
      name  = "API_REPOSITORY_NAME"
      value = aws_ecr_repository.api.name
    }
    environment_variable {
      name  = "LOAD_BALANCER_SOURCE_CIDRS"
      value = join(",", concat(var.administrator_cidrs, [for nat in aws_eip.nat : "${nat.public_ip}/32"]))
    }
    environment_variable {
      name  = "ACM_CERTIFICATE_ARN"
      value = var.acm_certificate_arn
    }
  }
  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.build.name
      stream_name = "build"
    }
  }
  depends_on = [aws_iam_role_policy.build]
}

resource "aws_codebuild_project" "verify" {
  name           = local.verify
  description    = "Verify rollout and HTTP response; capture the actual NLB ARN and release evidence"
  service_role   = aws_iam_role.verify.arn
  build_timeout  = 20
  encryption_key = aws_kms_key.artifacts.arn
  source {
    type      = "CODEPIPELINE"
    buildspec = "${var.project_directory}/buildspec.verify.yml"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
    environment_variable {
      name  = "PROJECT_DIRECTORY"
      value = var.project_directory
    }
    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = aws_eks_cluster.main.name
    }
  }
  vpc_config {
    vpc_id             = aws_vpc.main.id
    subnets            = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.deploy.id]
  }
  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.verify.name
      stream_name = "verify"
    }
  }
  depends_on = [aws_iam_role_policy.verify, aws_route_table_association.private]
}

resource "aws_codepipeline" "main" {
  count          = var.pipeline_enabled ? 1 : 0
  name           = local.pipeline
  role_arn       = aws_iam_role.pipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
    encryption_key {
      id   = aws_kms_key.artifacts.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]
      configuration = {
        ConnectionArn    = local.connection
        FullRepositoryId = var.github_repository
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }
  stage {
    name = "Build"
    action {
      name             = "BuildAndPushToECR"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      configuration    = { ProjectName = aws_codebuild_project.build.name }
    }
  }
  stage {
    name = "Deploy"
    action {
      name            = "DeployToEKS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "EKS"
      version         = "1"
      input_artifacts = ["BuildArtifact"]
      configuration = {
        ClusterName      = aws_eks_cluster.main.name
        Namespace        = "brain-tasks"
        ManifestFiles    = "manifests.yaml"
        Subnets          = join(",", aws_subnet.private[*].id)
        SecurityGroupIds = aws_security_group.deploy.id
      }
    }
  }
  stage {
    name = "Verify"
    action {
      name             = "VerifyRolloutAndRecordARN"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact", "BuildArtifact"]
      output_artifacts = ["VerificationReport"]
      configuration = {
        ProjectName   = aws_codebuild_project.verify.name
        PrimarySource = "SourceArtifact"
      }
    }
  }
  depends_on = [
    aws_iam_role_policy.pipeline, aws_eks_access_entry.pipeline, aws_eks_access_entry.verify,
    aws_vpc_security_group_ingress_rule.eks_deploy, aws_s3_bucket_server_side_encryption_configuration.artifacts
  ]
}
