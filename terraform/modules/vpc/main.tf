locals {
  application = var.application_name
  common_tags = var.tags
  availability_zones = {
    1 = "a"
    2 = "b"
    3 = "c"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}.0.0/16"
  enable_dns_hostnames = true
  tags = merge({
    Name = "vpc-${local.application}"
  }, local.common_tags)
}

resource "aws_subnet" "public_subnets" {
  for_each                = { for subnet in range(3) : subnet + 1 => local.availability_zones[subnet + 1] }
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "${var.vpc_cidr}.${each.key}.0/24"
  availability_zone       = "${data.aws_region.current.region}${each.value}"
  map_public_ip_on_launch = true
  tags = merge({
    Name = "public-subnet-${each.value}-${local.application}"
  }, local.common_tags)
}

resource "aws_subnet" "private_subnets" {
  for_each          = { for subnet in range(3) : subnet + 1 => local.availability_zones[subnet + 1] }
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "${var.vpc_cidr}.${10 + each.key}.0/24"
  availability_zone = "${data.aws_region.current.region}${each.value}"
  tags = merge({
    Name = "private-subnet-${each.value}-${local.application}"
  }, local.common_tags)
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = merge({
    Name = "igw-${local.application}"
  }, local.common_tags)
}

resource "aws_eip" "eip" {
  tags = merge({
    Name = "eip-${local.application}"
  }, local.common_tags)
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.private_subnets[1].id
  tags = merge({
    Name = "ngw-${local.application}"
  }, local.common_tags)
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "public-rt-${local.application}"
  }, local.common_tags)
}

resource "aws_route" "public_route_igw" {
  route_table_id         = aws_route_table.public_route.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_route_association" {
  for_each       = { for subnet in range(3) : subnet + 1 => "" }
  subnet_id      = aws_subnet.public_subnets[each.key].id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge({
    Name = "private-rt-${local.application}"
  }, local.common_tags)
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "private_route_association" {
  for_each       = { for subnet in range(3) : subnet + 1 => "" }
  subnet_id      = aws_subnet.private_subnets[each.key].id
  route_table_id = aws_route_table.private_route.id
}