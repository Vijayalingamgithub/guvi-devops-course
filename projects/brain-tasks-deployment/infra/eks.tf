resource "aws_iam_role" "cluster" {
  name = "${local.prefix}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "AmazonEKSClusterPolicy", "AmazonEKSComputePolicy", "AmazonEKSBlockStoragePolicyV2",
    "AmazonEKSLoadBalancingPolicy", "AmazonEKSNetworkingPolicy"
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.managed_base}/${each.value}"
}

resource "aws_iam_role" "node" {
  name = "${local.prefix}-eks-node"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(["AmazonEKSWorkerNodeMinimalPolicy", "AmazonEC2ContainerRegistryPullOnly"])
  role       = aws_iam_role.node.name
  policy_arn = "${local.managed_base}/${each.value}"
}

resource "aws_cloudwatch_log_group" "control_plane" {
  name              = "/aws/eks/${local.cluster}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "main" {
  name                          = local.cluster
  role_arn                      = aws_iam_role.cluster.arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.administrator_cidrs
  }
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.node.arn
  }
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }
  storage_config {
    block_storage {
      enabled = true
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.cluster, aws_iam_role_policy_attachment.node,
    aws_cloudwatch_log_group.control_plane, aws_route_table_association.private
  ]
}

resource "aws_eks_access_entry" "administrator" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.administrator_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "administrator" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.administrator.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "pipeline" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.pipeline.arn
  type              = "STANDARD"
  kubernetes_groups = ["brain-tasks-deployers"]
}

resource "aws_eks_access_entry" "verify" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.verify.arn
  type              = "STANDARD"
  kubernetes_groups = ["brain-tasks-readers"]
}

resource "aws_iam_role" "observability" {
  name = "${local.prefix}-observability"
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

resource "aws_iam_role_policy_attachment" "observability" {
  for_each   = toset(["CloudWatchAgentServerPolicy", "AWSXRayDaemonWriteAccess"])
  role       = aws_iam_role.observability.name
  policy_arn = "${local.managed_base}/${each.value}"
}

resource "aws_cloudwatch_log_group" "containers" {
  for_each          = toset(["application", "dataplane", "host", "performance"])
  name              = "/aws/containerinsights/${local.cluster}/${each.value}"
  retention_in_days = var.log_retention_days
}

data "aws_eks_addon_version" "cloudwatch" {
  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "cloudwatch" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = data.aws_eks_addon_version.cloudwatch.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  pod_identity_association {
    service_account = "cloudwatch-agent"
    role_arn        = aws_iam_role.observability.arn
  }
  depends_on = [aws_iam_role_policy_attachment.observability, aws_cloudwatch_log_group.containers]
}

# Fluent Bit may use its own service account depending on the add-on release.
resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "amazon-cloudwatch"
  service_account = "fluent-bit"
  role_arn        = aws_iam_role.observability.arn
}

data "aws_eks_addon_version" "metrics" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "metrics" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.metrics.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}
