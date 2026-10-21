output "vm_ips" {
  description = "コンテナ名と接続先 (127.0.0.1:port)"
  value       = { for name, port in local.ssh_ports : name => "127.0.0.1:${port}" }
}

# Makefile がこの値を ansible/inventory/docker.yml に書き出す。
# proxmox 環境と同じ形の値を出力する。
output "ansible_inventory" {
  description = "Ansible の YAML インベントリ (JSON 形式)"
  value = {
    all = {
      children = {
        docker = {
          hosts = {
            for name, c in docker_container.vm : name => {
              ansible_host                 = "127.0.0.1"
              ansible_port                 = local.ssh_ports[name]
              ansible_user                 = var.vm_user
              ansible_ssh_private_key_file = pathexpand(var.ssh_private_key_path)
            }
          }
        }
      }
    }
  }
}
