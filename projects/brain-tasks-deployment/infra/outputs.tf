output "aws_region" {
  value = var.aws_region
}
output "cluster_name" {
  value = aws_eks_cluster.main.name
}
output "ecr_repository_uri" {
  value = aws_ecr_repository.app.repository_url
}
output "github_connection_arn" {
  value = local.connection
}
output "pipeline_name" {
  value = local.pipeline
}
output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
output "build_project_name" {
  value = aws_codebuild_project.build.name
}
output "verify_project_name" {
  value = aws_codebuild_project.verify.name
}
output "pipeline_console_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${local.pipeline}/view?region=${var.aws_region}"
}
output "log_groups" {
  value = {
    build       = aws_cloudwatch_log_group.build.name
    verify      = aws_cloudwatch_log_group.verify.name
    deploy      = aws_cloudwatch_log_group.pipeline.name
    application = aws_cloudwatch_log_group.containers["application"].name
    cluster     = aws_cloudwatch_log_group.control_plane.name
  }
}
