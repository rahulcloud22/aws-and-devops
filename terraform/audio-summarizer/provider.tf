provider "aws" {
  assume_role {
    role_arn     = "arn:aws:iam::12345678:role/OrganizationAccountAccessRole"
    session_name = "workshop-admin"
  }
}