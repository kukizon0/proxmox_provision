locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# Ubuntu cloud image を Proxmox ノードに取得する (import コンテンツとして保存)
resource "proxmox_download_file" "cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore_id
  node_name    = var.node_name
  url          = var.image_url
  # import するには拡張子でフォーマットを示す必要がある
  file_name = "${trimsuffix(basename(var.image_url), ".img")}.qcow2"
  overwrite = false
}

# qemu-guest-agent を入れる vendor-data。
# ユーザーと公開鍵は Proxmox 標準の cloud-init (user_account) で設定する。
resource "proxmox_virtual_environment_file" "vendor_data" {
  content_type = "snippets"
  datastore_id = var.image_datastore_id
  node_name    = var.node_name

  source_raw {
    file_name = "opentofu-dev-vm-vendor-data.yaml"
    data      = file("${path.module}/vendor-data.yaml")
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = var.tags

  # guest agent 経由で IP を取得する (DHCP の場合に必須)
  agent {
    enabled = true
  }
  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.disk_datastore_id
    import_from  = proxmox_download_file.cloud_image.id
    interface    = "scsi0"
    size         = each.value.disk_size
    discard      = "on"
    iothread     = true
  }
  scsi_hardware = "virtio-scsi-single"

  initialization {
    datastore_id = var.disk_datastore_id

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.ipv4_address == "dhcp" ? null : each.value.ipv4_gateway
      }
    }

    dynamic "dns" {
      for_each = length(var.dns_servers) > 0 ? [1] : []
      content {
        servers = var.dns_servers
      }
    }

    user_account {
      username = var.vm_user
      keys     = [local.ssh_public_key]
    }

    vendor_data_file_id = proxmox_virtual_environment_file.vendor_data.id
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    # cloud image が更新されても既存 VM は作り直さない
    ignore_changes = [disk[0].import_from]
  }
}
