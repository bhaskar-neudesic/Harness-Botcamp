variable "resource_group_name" {
  default = "rg-aks-harness"
}

variable "location" {
  default = "East US"
}

variable "aks_cluster_name" {
  default = "aks-harness-bs"
}

variable "node_count" {
  default = 1
}

variable "node_size" {
  default = "Standard_B2s"
}
