# ---------------------------------------------------------------------------
# 共通 (proxmox 環境と同じ名前・型にそろえている)
# docker では cores / memory 以外のディスク・ネットワーク設定は使わない
# ---------------------------------------------------------------------------

variable "vms" {
  description = "作成するテスト用コンテナの定義。キーがホスト名になる"
  type = map(object({
    cores        = optional(number, 2)
    memory       = optional(number, 4096)   # MiB
    disk_size    = optional(number, 32)     # 未使用
    ipv4_address = optional(string, "dhcp") # 未使用
    ipv4_gateway = optional(string)         # 未使用
    vm_id        = optional(number)         # 未使用
  }))
  default = {
    dev01 = {}
  }
}

variable "vm_user" {
  description = "ログインユーザー (イメージに存在するユーザー)"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "コンテナに登録する SSH 公開鍵 (作業端末側のパス)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Ansible が接続に使う SSH 秘密鍵 (作業端末側のパス)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# ---------------------------------------------------------------------------
# Docker 固有
# ---------------------------------------------------------------------------

variable "ssh_port_base" {
  description = "ホスト側に公開する SSH ポートの開始番号 (VM ごとに +1)"
  type        = number
  default     = 2222
}

variable "name_prefix" {
  description = "コンテナ名の接頭辞"
  type        = string
  default     = "devvm-"
}
