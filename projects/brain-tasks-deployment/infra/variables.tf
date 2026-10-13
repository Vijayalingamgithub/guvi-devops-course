variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "brain-tasks"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.project_name))
    error_message = "Use a lowercase project name of 3 to 24 characters."
  }
}

variable "github_repository" {
  description = "Your writable GitHub repository, in owner/repository format."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/repository without a URL or .git suffix."
  }
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "project_directory" {
  description = "Project path within the source repository; use . for a standalone repository."
  type        = string
  default     = "."
  validation {
    condition     = var.project_directory == "." || can(regex("^[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)*$", var.project_directory))
    error_message = "Use . or a safe relative directory path without spaces or traversal."
  }
}

variable "github_connection_arn" {
  description = "Reuse an AVAILABLE AWS CodeConnections GitHub connection, or leave empty to create one."
  type        = string
  default     = ""
}

variable "administrator_principal_arn" {
  description = "IAM role ARN used by your SSO/CLI identity; use an IAM ARN, not an STS session ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws[^:]*:iam::[0-9]{12}:(role|user)/.+$", var.administrator_principal_arn))
    error_message = "Provide an IAM role or user ARN rather than an assumed-role session ARN."
  }
}

variable "administrator_cidrs" {
  description = "Public IPv4 CIDRs allowed to reach the EKS administrative endpoint, typically YOUR_IP/32."
  type        = list(string)
  validation {
    condition = length(var.administrator_cidrs) > 0 && alltrue([
      for cidr in var.administrator_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Supply at least one IPv4 /24 or narrower CIDR; do not expose the EKS API to the whole Internet."
  }
}

variable "kubernetes_version" {
  description = "Verify standard support and add-on availability in your region before apply."
  type        = string
  default     = "1.36"
}

variable "single_nat_gateway" {
  description = "False provides one NAT gateway per AZ. True reduces lab cost and introduces an egress single point of failure."
  type        = bool
  default     = false
}

variable "pipeline_enabled" {
  description = "Enable only after completing the GitHub connection and running scripts/bootstrap.sh."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "Optional issued ACM certificate in this region; enables an additional TLS listener on port 443."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}
