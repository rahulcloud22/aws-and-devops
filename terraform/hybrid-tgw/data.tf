data "aws_caller_identity" "A_EAST" {
  provider = aws.A_EAST
}

data "aws_region" "A_WEST" {
  provider = aws.A_WEST
}

data "aws_caller_identity" "B_EAST" {
  provider = aws.B_EAST
}

data "aws_ami" "ubuntu" {
  provider    = aws.A_EAST # Region specific
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

data "aws_ami" "ubuntu_west" {
  provider    = aws.A_WEST
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}
