# block "data" is needed to get Data about "aws_availability_zones"
data "aws_availability_zones" "availableAZ" {}

# Using block "resource aws_vpc" to define our VPC
resource "aws_vpc" "my_vpc" {
  cidr_block       = var.cidr
  instance_tenancy = "default"
  #   enable_dns_support               = true
  #   enable_dns_hostnames             = true
  #   assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "publicsubnet" {
  count                   = length(var.publicSubnetCIDR)
  cidr_block              = tolist(var.publicSubnetCIDR)[count.index]
  vpc_id                  = aws_vpc.my_vpc.id
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.availableAZ.names[count.index]

  tags = {
    Name        = "${var.environment}-publicsubnet-${count.index + 1}"
    AZ          = data.aws_availability_zones.availableAZ.names[count.index]
    Environment = "${var.environment}-publicsubnet"
  }

  depends_on = [aws_vpc.my_vpc]
}

# Private Subnet
resource "aws_subnet" "privatesubnet" {
  count             = length(var.publicSubnetCIDR)
  cidr_block        = tolist(var.privateSubnetCIDR)[count.index]
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = data.aws_availability_zones.availableAZ.names[count.index]

  tags = {
    Name        = "${var.environment}-privatesubnet-${count.index + 1}"
    AZ          = data.aws_availability_zones.availableAZ.names[count.index]
    Environment = "${var.environment}-privatesubnet"
  }

  depends_on = [aws_vpc.my_vpc]
}

# To provide internet in/out access for our VPC
# we should use "resource "aws_internet_gateway"" (AWS Internet Gateway service)
resource "aws_internet_gateway" "internetgateway" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "${var.environment}-InternetGateway"
  }

  depends_on = [aws_vpc.my_vpc]
}


resource "aws_route_table" "publicroutetable" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internetgateway.id
  }

  tags = {
    Name = "${var.environment}-publicroutetable"
  }

  depends_on = [aws_internet_gateway.internetgateway]
}

# Route Table Association - Public Routes
# resource "aws_route_table_association" is needed to determine subnets
# which  will be connected to the Internet Gateway and Public Routes
resource "aws_route_table_association" "routeTableAssociationPublicRoute" {
  count          = length(var.publicSubnetCIDR)
  route_table_id = aws_route_table.publicroutetable.id
  subnet_id      = aws_subnet.publicsubnet[count.index].id

  depends_on = [aws_subnet.publicsubnet, aws_route_table.publicroutetable]
}

data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
    #amzn2-ami-kernel-5.10-hvm-2.0.20211201.0-x86_64-gp2
  }
}

resource "aws_instance" "my_Amazon_Linux" {

  count                  = length(var.publicSubnetCIDR)
  ami                    = data.aws_ami.latest_amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.publicsubnet[count.index].id
  vpc_security_group_ids = [aws_security_group.SecurityGroup_EC2inPublicSubnet.id]

  user_data = <<-EOF
  #!/bin/bash
  yum -y update
  yum -y install httpd
  echo "<h2>WebServer ${var.webserv}</h2><br>Build by Terraform!"  >  /var/www/html/index.html
  sudo service httpd start
  chkconfig httpd on
  EOF


  #tags are using variables.tf file
  tags = merge(var.common_tags, { Name = "Html-page-server" })
}

resource "aws_security_group" "SecurityGroup_EC2inPublicSubnet" {
  name = "Security Group for EC2 instances public subnets"
  #  aws_vpc = aws_vpc.my_vpc.id
  vpc_id = aws_vpc.my_vpc.id

  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-publicsubnetEC2-SG"
  }
  depends_on = [aws_vpc.my_vpc]
}


# Description of Application Load Balancer creation process

resource "aws_alb" "main" {
  name            = "${var.app_name}-${var.environment}-lb"
  subnets         = aws_subnet.publicsubnet.*.id
  security_groups = [aws_security_group.SecurityGroup_EC2inPublicSubnet.id]
}

resource "aws_alb_target_group" "app" {
  name        = "${var.app_name}-${var.environment}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
  target_type = "instance"

  health_check {
    healthy_threshold = "3"
    interval          = "30"
    protocol          = "HTTP"
    matcher           = "200"
    timeout           = "3"
    #path                = var.health_check_path
    unhealthy_threshold = "2"
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}

# Include instances to the  "aws_alb_target_group"

resource "aws_lb_target_group_attachment" "alb_tg_attachment" {
  target_group_arn = aws_alb_target_group.app.arn
  #count            = 3
  #target_id = aws_instance.my_Amazon_Linux[0].id
  port      = 80
  count     = length(aws_instance.my_Amazon_Linux)
  target_id = aws_instance.my_Amazon_Linux[count.index].id

}

resource "aws_security_group" "codebuild_sg" {
  name        = "allow_vpc_connectivity"
  description = "Allow Codebuild connectivity to all the resources within our VPC"
  vpc_id      = aws_vpc.my_vpc.id

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
