variable "resource_group_name" {
  default = "aks-harness-testrg-001"
}

variable "location" {
  default = "East US"
}

variable "aks_cluster_name" {
  default = "aks-harness-test001"
}

variable "node_count" {
  default = 1
}

variable "node_size" {
  default = "Standard_B2s"
}
