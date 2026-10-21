# ---------------------------------------------------------------------------
# 共通 (docker 環境と同じ名前・型にそろえている)
# ---------------------------------------------------------------------------

variable "vms" {
  description = "作成する VM の定義。キーがホスト名になる"
  type = map(object({
    cores        = optional(number, 2)
    memory       = optional(number, 4096)   # MiB
    disk_size    = optional(number, 32)     # GiB
    ipv4_address = optional(string, "dhcp") # "dhcp" または "192.168.1.50/24"
    ipv4_gateway = optional(string)
    vm_id        = optional(number)
  }))
  default = {
    dev01 = {}
  }
}

variable "vm_user" {
  description = "cloud-init で作成するログインユーザー"
  type        = string
  default     = "ubuntu"
}

variable "vm_password" {
  description = "コンソール (Proxmox Web UI) ログイン用のパスワード。null なら自動生成 (make password で表示)。SSH は鍵認証のみ"
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "VM に登録する SSH 公開鍵 (作業端末側のパス)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Ansible が接続に使う SSH 秘密鍵 (作業端末側のパス)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# ---------------------------------------------------------------------------
# Proxmox 固有
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "Proxmox VE API の URL (例: https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "API トークン (USER@REALM!TOKENID=SECRET)。null なら環境変数 PROXMOX_VE_API_TOKEN を使う"
  type        = string
  default     = null
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "自己署名証明書を許可する"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "snippets アップロード用に Proxmox ノードへ SSH するユーザー"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_private_key_path" {
  description = "Proxmox ノードへの SSH 秘密鍵。null なら ssh-agent を使う"
  type        = string
  default     = null
}

variable "node_name" {
  description = "VM を作成する Proxmox ノード名"
  type        = string
  default     = "pve"
}

variable "image_url" {
  description = "cloud image の URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "image_datastore_id" {
  description = "cloud image / snippets を置くデータストア (import と snippets コンテンツを有効にしておく)"
  type        = string
  default     = "local"
}

variable "disk_datastore_id" {
  description = "VM ディスクと cloud-init ディスクを置くデータストア"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "VM を接続するブリッジ"
  type        = string
  default     = "vmbr0"
}

variable "dns_servers" {
  description = "VM に設定する DNS サーバー (空なら DHCP / ホストの設定に従う)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "VM に付けるタグ"
  type        = list(string)
  default     = ["opentofu", "dev"]
}
