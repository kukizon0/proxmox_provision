locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  context_dir    = abspath("${path.module}/../../../docker/test-node")

  ssh_ports = {
    for i, name in sort(keys(var.vms)) : name => var.ssh_port_base + i
  }
}

# cloud image の代わりに、sshd 入りの Ubuntu 24.04 イメージをビルドする
resource "docker_image" "node" {
  name = "devvm-test-node:latest"

  build {
    context = local.context_dir
  }

  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(local.context_dir, "**") : filesha1("${local.context_dir}/${f}")]))
  }
}

resource "docker_container" "vm" {
  for_each = var.vms

  name     = "${var.name_prefix}${each.key}"
  hostname = each.key
  image    = docker_image.node.image_id
  restart  = "unless-stopped"

  cpu_shares = each.value.cores * 1024
  memory     = each.value.memory

  # cloud-init の user_account 相当: エントリポイントが authorized_keys に書き込む
  env = [
    "SSH_USER=${var.vm_user}",
    "SSH_AUTHORIZED_KEYS=${local.ssh_public_key}",
  ]

  ports {
    internal = 22
    external = local.ssh_ports[each.key]
    ip       = "127.0.0.1"
  }
}
