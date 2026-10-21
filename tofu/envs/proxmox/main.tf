locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  image_datastore_content_types = try(
    one([for ds in data.proxmox_datastores.image.datastores : ds.content_types if ds.id == var.image_datastore_id]),
    []
  )
  image_datastore_missing_content = setsubtract(["import", "snippets"], local.image_datastore_content_types)

  vm_password = coalesce(var.vm_password, random_password.vm.result)
}

# コンソールログイン用のパスワード (vm_password 未指定時に使う)
resource "random_password" "vm" {
  length  = 20
  special = false
}

data "proxmox_datastores" "image" {
  node_name = var.node_name
}

# import / snippets が無効だと、snippets のアップロード後に
# "failed to read file from ..." という分かりにくいエラーになるので先に検査する
check "image_datastore_content" {
  assert {
    condition     = length(local.image_datastore_missing_content) == 0
    error_message = <<-EOT
      データストア "${var.image_datastore_id}" で ${join(", ", local.image_datastore_missing_content)} コンテンツが有効になっていません。
      Proxmox ノードで次を実行してください (既存の値に追加する):
        pvesm set ${var.image_datastore_id} --content ${join(",", sort(setunion(local.image_datastore_content_types, ["import", "snippets"])))}
    EOT
  }
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

  lifecycle {
    precondition {
      condition     = contains(local.image_datastore_content_types, "snippets")
      error_message = "データストア \"${var.image_datastore_id}\" で snippets コンテンツが有効になっていません。check \"image_datastore_content\" の警告に従って pvesm set を実行してください。"
    }
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
      password = local.vm_password
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
    # cloud image が更新されても既存 VM は作り直さない。
    # user_account を変えると既存 VM の cloud-init が再実行され (再起動・SSH ホスト鍵の再生成)、
    # 影響が大きいので作成時のみ反映する。
    ignore_changes = [disk[0].import_from, initialization[0].user_account]
  }
}
