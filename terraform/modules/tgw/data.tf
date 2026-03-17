data "aws_vpc" "tgw_attachments" {
  for_each = var.tgw_attachments
  id       = each.value.vpc_id
}