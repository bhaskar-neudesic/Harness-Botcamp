terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
  backend "azurerm" {} # Optional, if you want remote state
}

provider "azurerm" {
  features {}
}
