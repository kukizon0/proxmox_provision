terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.117"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # null の場合は環境変数 PROXMOX_VE_API_TOKEN が使われる
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # snippets (cloud-init vendor-data) のアップロードに SSH を使う
  ssh {
    agent       = var.proxmox_ssh_private_key_path == null
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key_path == null ? null : file(pathexpand(var.proxmox_ssh_private_key_path))
  }
}
