terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # backend "azurerm" { # Storage Blob Data Contributor needed at container level for az_cli and others
  #   resource_group_name  = "rg-rahul"
  #   storage_account_name = "rahul"
  #   container_name       = "terraform"
  #   key                  = "terraform.tfstate"
  #   use_azuread_auth     = true //for cli creds
  # }
}

provider "aws" {
  alias   = "A_EAST"
  region  = "us-east-1"
  profile = "rahul-cloud"
}

provider "aws" {
  alias   = "A_WEST"
  region  = "us-west-2"
  profile = "rahul-cloud"
}

provider "aws" {
  alias   = "B_EAST"
  region  = "us-east-1"
  profile = "rahul-mlops"
}

provider "azurerm" {
  features {}
}