
resource "aws_security_group" "sg_a_east" {
  provider    = aws.A_EAST
  name        = "A-EAST-sg-${var.application_name}" // cannot begin with sg-*
  description = "Allow HTTP and SSH Traffic"
  vpc_id      = module.vpc_a_east.vpc_id
  tags = merge(
    var.tags,
    {
      Name = "sg-${var.application_name}-A-EAST"
    }
  )
}

# aws_vpc_security_group_ingress_rule resources is the current best practice.
resource "aws_vpc_security_group_ingress_rule" "allow_http_a_east" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = var.my_ip
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  tags = {
    Name = "allow-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_a_east" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = var.my_ip
  from_port         = 0 // ports 0 - 22 will be open
  ip_protocol       = "tcp"
  to_port           = 22
  tags = {
    Name = "allow-ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_a_b_east" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = module.vpc_b_east.vpc_cidr
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from B-EAST to A-EAST
  to_port           = "-1"
  tags = {
    Name = "allow-b-east"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_a_west" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = module.vpc_a_west.vpc_cidr
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from A-WEST to A-EAST
  to_port           = "-1"
  tags = {
    Name = "allow-a-west"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_azure" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = "172.31.0.0/16"
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from A-WEST to A-EAST
  to_port           = "-1"
  tags = {
    Name = "allow-azure"
  }
}

// Egress are not created by default when you create a security group
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  provider          = aws.A_EAST
  security_group_id = aws_security_group.sg_a_east.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "ec2_a_east" {
  provider                    = aws.A_EAST
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.nano"
  subnet_id                   = module.vpc_a_east.public_subnet_ids[0]
  associate_public_ip_address = true
  key_name                    = "rahul-cloud-keypair"
  vpc_security_group_ids      = [aws_security_group.sg_a_east.id]
  tags                        = merge(var.tags, { Name = "A-EAST-ec2" })
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = "0.005"     # optional (USD per hour)
      spot_instance_type             = "one-time"  # or "persistent"
      instance_interruption_behavior = "terminate" # stop | hibernate | terminate
    }
  }
  #  /var/log/cloud-init-output.log 
  #  sudo cat /var/lib/cloud/instance/user-data.txt
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
}

# ===========================
# A-WEST
# ===========================
resource "aws_security_group" "sg_a_west" {
  provider    = aws.A_WEST
  name        = "A-WEST-sg-${var.application_name}" // cannot begin with sg-*
  description = "Allow HTTP and SSH Traffic"
  vpc_id      = module.vpc_a_west.vpc_id
  tags = merge(
    var.tags,
    {
      Name = "sg-${var.application_name}-A-WEST"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_a_west" {
  provider          = aws.A_WEST
  security_group_id = aws_security_group.sg_a_west.id
  cidr_ipv4         = var.my_ip
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  tags = {
    Name = "allow-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_a_west" {
  provider          = aws.A_WEST
  security_group_id = aws_security_group.sg_a_west.id
  cidr_ipv4         = var.my_ip
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  tags = {
    Name = "allow-ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_a_east" {
  provider          = aws.A_WEST
  security_group_id = aws_security_group.sg_a_west.id
  cidr_ipv4         = module.vpc_a_east.vpc_cidr
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from A-EAST to A-WEST
  to_port           = "-1"
  tags = {
    Name = "allow-a-east"
  }
}

// Egress are not created by default when you create a security group
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_a_west" {
  provider          = aws.A_WEST
  security_group_id = aws_security_group.sg_a_west.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6_a_west" {
  provider          = aws.A_WEST
  security_group_id = aws_security_group.sg_a_west.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "ec2_a_west" {
  provider                    = aws.A_WEST
  ami                         = data.aws_ami.ubuntu_west.id
  instance_type               = "t3.nano"
  subnet_id                   = module.vpc_a_west.public_subnet_ids[0]
  associate_public_ip_address = true
  key_name                    = "rahul-cloud-keypair"
  vpc_security_group_ids      = [aws_security_group.sg_a_west.id]
  tags                        = merge(var.tags, { Name = "A-WEST-ec2" })
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = "0.005"     # optional (USD per hour)
      spot_instance_type             = "one-time"  # or "persistent"
      instance_interruption_behavior = "terminate" # stop | hibernate | terminate
    }
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  # sudo hostnamectl set-hostname A-EAST-10-10-1-90

}

# ===========================
# B-EAST
# ===========================
resource "aws_security_group" "sg_b_east" {
  provider    = aws.B_EAST
  name        = "B-EAST-sg-${var.application_name}" // cannot begin with sg-*
  description = "Allow HTTP and SSH Traffic"
  vpc_id      = module.vpc_b_east.vpc_id
  tags = merge(
    var.tags,
    {
      Name = "sg-${var.application_name}-B-EAST"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_b_east" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv4         = var.my_ip
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  tags = {
    Name = "allow-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_b_east" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv4         = var.my_ip
  from_port         = 0 // ports 0 - 22 will be open
  ip_protocol       = "tcp"
  to_port           = 22
  tags = {
    Name = "allow-ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_b_a_east" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv4         = module.vpc_a_east.vpc_cidr
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from A-EAST to B-EAST
  to_port           = "-1"
  tags = {
    Name = "allow-A-East"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_b_azure" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv4         = "172.31.0.0/16"
  from_port         = "-1" # 0 - 65535
  ip_protocol       = "-1" # allow all  protocols and ports from A-EAST to B-EAST
  to_port           = "-1"
  tags = {
    Name = "allow-Azure"
  }
}

// Egress are not created by default when you create a security group
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_b_east" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6_b_east" {
  provider          = aws.B_EAST
  security_group_id = aws_security_group.sg_b_east.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "ec2_b_east" {
  provider      = aws.B_EAST
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.nano"
  # private_ip = "10.50.1.50"
  subnet_id                   = module.vpc_b_east.public_subnet_ids[0]
  associate_public_ip_address = true
  key_name                    = "rahul-cloud-keypair"
  vpc_security_group_ids      = [aws_security_group.sg_b_east.id]
  tags                        = merge(var.tags, { Name = "B-EAST-ec2" })
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = "0.005"     # optional (USD per hour)
      spot_instance_type             = "one-time"  # or "persistent"
      instance_interruption_behavior = "terminate" # stop | hibernate | terminate
    }
  }
  #  /var/log/cloud-init-output.log 
  #  sudo cat /var/lib/cloud/instance/user-data.txt
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
}