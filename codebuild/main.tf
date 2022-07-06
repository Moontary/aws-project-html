resource "aws_security_group" "codebuild_sg" {
  name        = "allow_vpc_connectivity"
  description = "Allow Codebuild connectivity to all the resources within our VPC"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_oauth_token
}

resource "aws_codebuild_project" "project" {
  depends_on    = [aws_codebuild_source_credential.github]
  name          = "${var.app_name}-${var.environment}"
  description   = "Codebuild for ${var.app_name} environment ${var.environment}"
  build_timeout = "120"
  service_role  = aws_iam_role.role.arn


  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    # https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-compute-types.html
    compute_type = "BUILD_GENERAL1_SMALL" # 7 GB memory
    # https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-available.html
    image = "aws/codebuild/standard:4.0"
    type  = "LINUX_CONTAINER"
    # The privileged flag must be set so that your project has the required Docker permissions
    privileged_mode = true

    environment_variable {
      name  = "CI"
      value = "true"
    }
  }
  source {
    buildspec           = var.buildspec_file
    type                = "GITHUB"
    location            = var.repo_url
    git_clone_depth     = 1
    report_build_status = "true"
  }
}

resource "aws_codebuild_webhook" "develop_webhook" {
  project_name = aws_codebuild_project.project.name

  # https://docs.aws.amazon.com/codebuild/latest/APIReference/API_WebhookFilter.html
  filter_group {
    filter {
      type    = "EVENT"
      pattern = var.git_trigger_event
    }

    filter {
      type    = "HEAD_REF"
      pattern = var.branch_pattern
    }
  }
}

resource "aws_iam_role" "role" {
  name = "codebuild-role-${var.app_name}-${var.environment}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_full_access" {
  role       = aws_iam_role.role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy" "role_policy" {
  role = aws_iam_role.role.name
  name = "codebuild-policy-${var.app_name}-${var.environment}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:PassRole",
        "iam:ListInstanceProfilesForRole",
        "iam:ListRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/*"
    },
    {
      "Effect":"Allow",
      "Action": [
        "iam:CreateServiceSpecificCredential",
        "iam:DeleteServiceSpecificCredential",
        "iam:ResetServiceSpecificCredential",
        "iam:UpdateServiceSpecificCredential",
        "iam:ListServiceSpecificCredential"
      ],
      "Resource": "*"
    },
    {
      "Action": "iam:CreateServiceLinkedRole",
      "Effect": "Allow",
      "Resource": "arn:aws:iam::*:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName":"rds.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Effect":"Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "ecs:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:*"
      ],
      "Resource": "arn:aws:secretsmanager:${var.region}:*:secret:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:${var.region}:*:parameter*"
    },
    {
      "Effect": "Allow",
      "Action" : [
        "dynamodb:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs",
        "ec2:DescribeAddresses",
        "ec2:AllocateAddress",
        "ec2:DescribeInstances",
        "ec2:AssociateAddress",
        "ec2:DescribeNatGateways",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterfacePermission"
      ],
      "Resource": "arn:aws:ec2:${var.region}:*:network-interface/*",
      "Condition": {
        "StringLike": {
          "ec2:Subnet": [
            "arn:aws:ec2:${var.region}:*:subnet/*"
          ],
          "ec2:AuthorizedService": "codebuild.amazonaws.com"
        }
      }
    }
  ]
}
POLICY
}