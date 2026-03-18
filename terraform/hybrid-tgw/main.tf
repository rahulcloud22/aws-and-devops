module "vpc_a_east" {
  providers = {
    aws = aws.A_EAST
  }
  source           = "../modules/vpc"
  application_name = "${var.application_name}-A-EAST"
  vpc_cidr         = "10.10"
  tags             = var.tags
}

module "vpc_a_west" {
  providers = {
    aws = aws.A_WEST
  }
  source           = "../modules/vpc"
  application_name = "${var.application_name}-A-WEST"
  vpc_cidr         = "10.20"
  tags             = var.tags
}

module "vpc_b_east" {
  providers = {
    aws = aws.B_EAST
  }
  source           = "../modules/vpc"
  application_name = "${var.application_name}-B-EAST"
  vpc_cidr         = "10.50"
  tags             = var.tags
}


module "tgw_a_east" {
  providers = {
    aws = aws.A_EAST
  }
  source           = "../modules/tgw"
  application_name = "${var.application_name}-east"
  tgw_attachments = {
    "vpc-a-east" = {
      vpc_id                          = module.vpc_a_east.vpc_id
      subnet_ids                      = module.vpc_a_east.private_subnet_ids
      default_route_table_association = false
    }
  }
  route_tables = {
    "aws" = {
      vpc_to_attach    = ["vpc-a-east"]
      vpc_to_propogate = ["vpc-a-east"]
    }
  }
  tags = var.tags
}

resource "aws_ram_resource_share" "tgw_share" {
  provider                  = aws.A_EAST
  name                      = "tgw-ram-share-A-EAST"
  allow_external_principals = true # required for cross-account sharing
}

# by default arn:aws:ram::aws:permission/AWSRAMDefaultPermissionTransitGateway will be used
resource "aws_ram_resource_association" "tgw_resource" {
  provider           = aws.A_EAST
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
  resource_arn       = module.tgw_a_east.tgw_arn
}

resource "aws_ram_principal_association" "tgw_principal" {
  provider           = aws.A_EAST
  principal          = data.aws_caller_identity.B_EAST.account_id
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}

resource "aws_ram_resource_share_accepter" "receiver_accept" {
  provider  = aws.B_EAST
  share_arn = aws_ram_principal_association.tgw_principal.resource_share_arn
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attachment_b_east" {
  provider                                        = aws.B_EAST
  vpc_id                                          = module.vpc_b_east.vpc_id
  subnet_ids                                      = module.vpc_b_east.private_subnet_ids
  transit_gateway_id                              = module.tgw_a_east.tgw_id
  transit_gateway_default_route_table_association = false
  tags = merge({
    Name = "tgw-attach-${module.vpc_b_east.vpc_name}"
  }, var.tags)
  lifecycle {
    ignore_changes = [
      transit_gateway_default_route_table_association
    ]
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "tgw_attachment_b_east" {
  provider                                        = aws.A_EAST
  transit_gateway_attachment_id                   = aws_ec2_transit_gateway_vpc_attachment.tgw_attachment_b_east.id
  transit_gateway_default_route_table_association = false
  tags = {
    Name = "tgw-attach-${module.vpc_b_east.vpc_name}"
  }

}

resource "aws_ec2_transit_gateway_route_table_association" "b_east" {
  provider                       = aws.A_EAST
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_attachment_b_east.id
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "b_east" {
  provider                       = aws.A_EAST
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_attachment_b_east.id
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
}

resource "aws_route" "rt_a_east_to_b_east" {
  provider               = aws.A_EAST
  route_table_id         = module.vpc_a_east.public_rt_id
  destination_cidr_block = module.vpc_b_east.vpc_cidr
  transit_gateway_id     = module.tgw_a_east.tgw_id
}

resource "aws_route" "rt_b_east_to_a_east" {
  provider               = aws.B_EAST
  route_table_id         = module.vpc_b_east.public_rt_id
  destination_cidr_block = module.vpc_a_east.vpc_cidr
  transit_gateway_id     = module.tgw_a_east.tgw_id
}

module "tgw_west" {
  providers = {
    aws = aws.A_WEST
  }
  source           = "../modules/tgw"
  application_name = "${var.application_name}-west"
  tgw_attachments = {
    "vpc-a-west" = {
      vpc_id                          = module.vpc_a_west.vpc_id
      subnet_ids                      = module.vpc_a_west.private_subnet_ids
      default_route_table_association = false
    }
  }
  route_tables = {
    "aws" = {
      vpc_to_attach    = ["vpc-a-west"]
      vpc_to_propogate = ["vpc-a-west"]
    }
  }
  tags = var.tags
}

resource "aws_ec2_transit_gateway_peering_attachment" "tgw_peering_a_east" {
  provider                = aws.A_EAST
  peer_account_id         = data.aws_caller_identity.A_EAST.account_id
  peer_region             = data.aws_region.A_WEST.region
  peer_transit_gateway_id = module.tgw_west.tgw_id
  transit_gateway_id      = module.tgw_a_east.tgw_id
  tags = {
    Name = "tgw-peering-east-west"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "tgw_attachment_a_west" {
  provider                      = aws.A_WEST
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.tgw_peering_a_east.id
  tags = {
    Name = "tgw-peering-${module.vpc_a_east.vpc_name}"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "a_east" {
  provider                       = aws.A_EAST
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.tgw_peering_a_east.id
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
}

resource "aws_ec2_transit_gateway_route_table_association" "a_west" {
  provider                       = aws.A_WEST
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.tgw_peering_a_east.id
  transit_gateway_route_table_id = module.tgw_west.route_tables["aws"].id
}

resource "aws_ec2_transit_gateway_route" "east_to_west_vpc" {
  provider                       = aws.A_EAST
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
  destination_cidr_block         = module.vpc_a_west.vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.tgw_peering_a_east.id
}

resource "aws_ec2_transit_gateway_route" "west_to_east_vpc" {
  provider                       = aws.A_WEST
  transit_gateway_route_table_id = module.tgw_west.route_tables["aws"].id
  destination_cidr_block         = module.vpc_a_east.vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.tgw_peering_a_east.id
}

resource "aws_route" "rt_a_east_to_a_west" {
  provider               = aws.A_EAST
  route_table_id         = module.vpc_a_east.public_rt_id
  destination_cidr_block = module.vpc_a_west.vpc_cidr
  transit_gateway_id     = module.tgw_a_east.tgw_id
}

resource "aws_route" "rt_a_west_to_a_east" {
  provider               = aws.A_WEST
  route_table_id         = module.vpc_a_west.public_rt_id
  destination_cidr_block = module.vpc_a_east.vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

#=====================
# Azure - AWS
#=====================
resource "aws_customer_gateway" "azure" {
  provider   = aws.A_EAST
  bgp_asn    = 65000
  ip_address = module.public_ipaddress.ip_address
  type       = "ipsec.1"
  tags = merge({
    Name = "cg-azure-${var.application_name}"
  }, var.tags)
}
resource "aws_vpn_connection" "tgw_vpn" {
  provider            = aws.A_EAST
  transit_gateway_id  = module.tgw_a_east.tgw_id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = merge({
    Name = "vpn-tgw-${var.application_name}"
  }, var.tags)
}

resource "aws_ec2_transit_gateway_route_table_association" "azure" {
  provider                       = aws.A_EAST
  transit_gateway_attachment_id  = aws_vpn_connection.tgw_vpn.transit_gateway_attachment_id
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
}

resource "aws_ec2_transit_gateway_route" "to_azure" {
  provider                       = aws.A_EAST
  destination_cidr_block         = "172.31.0.0/16"
  transit_gateway_route_table_id = module.tgw_a_east.route_tables["aws"].id
  transit_gateway_attachment_id  = aws_vpn_connection.tgw_vpn.transit_gateway_attachment_id
}

resource "aws_route" "rt_azure" {
  provider               = aws.A_EAST
  route_table_id         = module.vpc_a_east.public_rt_id
  destination_cidr_block = "172.31.0.0/16"
  transit_gateway_id     = module.tgw_a_east.tgw_id
}

resource "aws_route" "rt_b_east_to_azure" {
  provider               = aws.B_EAST
  route_table_id         = module.vpc_b_east.public_rt_id
  destination_cidr_block = "172.31.0.0/16"
  transit_gateway_id     = module.tgw_a_east.tgw_id
}