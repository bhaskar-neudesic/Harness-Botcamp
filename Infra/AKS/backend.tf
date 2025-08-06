terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestoragebs"  # updated name
    container_name       = "tfstate"
    key                  = "aks-harness.tfstate"
  }
}
