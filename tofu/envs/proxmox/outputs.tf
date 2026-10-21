locals {
  # 静的 IP ならその値、DHCP なら guest agent が報告したループバック以外の最初の IPv4
  vm_ips = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => (
      var.vms[name].ipv4_address != "dhcp"
      ? split("/", var.vms[name].ipv4_address)[0]
      : try([for ip in flatten(vm.ipv4_addresses) : ip if !startswith(ip, "127.")][0], null)
    )
  }
}

output "vm_ips" {
  description = "VM 名と IP アドレス"
  value       = local.vm_ips
}

output "vm_password" {
  description = "コンソールログイン用のパスワード (make password で表示)"
  value       = local.vm_password
  sensitive   = true
}

# Makefile がこの値を ansible/inventory/proxmox.yml に書き出す。
# docker 環境も同じ形の値を出力する。
output "ansible_inventory" {
  description = "Ansible の YAML インベントリ (JSON 形式)"
  value = {
    all = {
      children = {
        proxmox = {
          hosts = {
            for name, ip in local.vm_ips : name => {
              ansible_host                 = ip
              ansible_port                 = 22
              ansible_user                 = var.vm_user
              ansible_ssh_private_key_file = pathexpand(var.ssh_private_key_path)
            }
          }
        }
      }
    }
  }
}
