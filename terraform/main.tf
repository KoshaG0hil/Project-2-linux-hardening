terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "production-linux-vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "production-private-subnet"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "production-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id

}


resource "aws_security_group" "private_ec2" {
  name        = "production-private-ec2-sg"
  description = "Security group for private production EC2"
  vpc_id      = aws_vpc.main.id

    ingress {
    description = "HTTPS from production VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }


  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "production-private-ec2-sg"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.private.id]

  security_group_ids = [
    aws_security_group.private_ec2.id
  ]

  private_dns_enabled = true

  tags = {
    Name = "production-ssm-endpoint"
  }
}
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id               = aws_vpc.main.id
  service_name         = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [aws_subnet.private.id]
  security_group_ids   = [aws_security_group.private_ec2.id]
  private_dns_enabled  = true

  tags = {
    Name = "production-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id               = aws_vpc.main.id
  service_name         = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type    = "Interface"
  subnet_ids            = [aws_subnet.private.id]
  security_group_ids   = [aws_security_group.private_ec2.id]
  private_dns_enabled  = true

  tags = {
    Name = "production-ec2messages-endpoint"
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "production-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "production-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm.name
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "linux" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = {
    Name = "production-linux-server"
  }
}