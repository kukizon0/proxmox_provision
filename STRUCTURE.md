# コード構成

```
proxmox-dev-vm/
├── Makefile                     # すべての操作の入口 (make help)
├── README.md                    # 使い方
├── STRUCTURE.md                 # このファイル
├── pyproject.toml / uv.lock     # Ansible / ansible-lint の依存 (uv で管理)
├── .python-version              # 3.13
├── .env.example                 # API トークンなど (コピーして .env に)
│
├── tofu/envs/
│   ├── proxmox/                 # 本番: Proxmox VE に VM を作る
│   │   ├── versions.tf          #   tofu / bpg/proxmox のバージョンと provider 設定
│   │   ├── variables.tf         #   共通変数 + Proxmox 固有の変数
│   │   ├── main.tf              #   cloud image 取得、vendor-data、VM
│   │   ├── vendor-data.yaml     #   cloud-init: qemu-guest-agent を入れる
│   │   ├── outputs.tf           #   vm_ips / ansible_inventory
│   │   └── terraform.tfvars.example
│   └── docker/                  # テスト: Docker コンテナを VM 代わりに作る
│       ├── versions.tf          #   kreuzwerker/docker
│       ├── variables.tf         #   共通変数 (proxmox と同じ型) + Docker 固有の変数
│       ├── main.tf              #   イメージのビルドとコンテナ
│       └── outputs.tf           #   vm_ips / ansible_inventory (proxmox と同じ形)
│
├── docker/test-node/            # テスト用ノードのイメージ
│   ├── Dockerfile               #   ubuntu:24.04 + openssh-server + sudo + python3
│   └── entrypoint.sh            #   cloud-init 相当: 公開鍵を登録して sshd を起動
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── <env>.yml            #   make inventory が tofu の出力から生成 (gitignore)
│   │   └── group_vars/
│   │       ├── all.yml          #   設定値はほぼここ
│   │       ├── proxmox.yml      #   proxmox グループ向けの上書き
│   │       └── docker.yml       #   docker グループ向けの上書き (guest agent なし)
│   ├── playbooks/
│   │   ├── site.yml             #   本体: base → ssh_keys → uv → opencode
│   │   ├── wait.yml             #   SSH 接続待ち + cloud-init 完了待ち
│   │   └── verify.yml           #   ツールのバージョンと sshd 設定を確認
│   └── roles/
│       ├── base/                #   apt パッケージ、ロケール、タイムゾーン、guest agent、PATH
│       ├── ssh_keys/            #   authorized_keys の登録、sshd のパスワード認証無効化
│       ├── uv/                  #   uv 本体 (official / pipx)、uv python、uv tool
│       └── opencode/            #   Node.js (apt) と opencode-ai (npm, ~/.local に)
│
└── scripts/
    └── ssh_args.py              # make ssh 用: インベントリから ssh の引数を作る
```

## 処理の流れ (`make up`)

```
make apply ─┬─ tofu -chdir=tofu/envs/$(ENV) apply
            └─ make inventory: tofu output -json ansible_inventory > ansible/inventory/$(ENV).yml
make wait ──── ansible-playbook wait.yml       (SSH 待ち、Proxmox なら cloud-init 完了待ち)
make provision ansible-playbook site.yml
```

### Proxmox 環境の中身

1. `proxmox_download_file` で Ubuntu 24.04 cloud image を `local:import/` に取得
2. `proxmox_virtual_environment_file` で vendor-data を `local:snippets/` に置く (SSH 経由)
3. `proxmox_virtual_environment_vm` (`for_each = var.vms`) で VM を作成
   - ディスクは cloud image を `import_from` で取り込み、`disk_size` に拡張
   - cloud-init の `user_account` で `vm_user` と公開鍵を設定
   - `ip_config` で DHCP か固定 IP
4. 出力の IP は、固定 IP なら設定値、DHCP なら guest agent が返すループバック以外の IPv4

### Docker 環境の中身

1. `docker_image` で `docker/test-node` をビルド (ディレクトリの内容が変わると再ビルド)
2. `docker_container` (`for_each = var.vms`) を起動し、22 番を `127.0.0.1:2222+i` に公開
3. 環境変数 `SSH_AUTHORIZED_KEYS` で公開鍵を渡し、`entrypoint.sh` が authorized_keys に書く

## 環境を差し替えられる仕組み

2 つの tofu ルートモジュールは次の「約束」をそろえています。

| 項目 | 内容 |
| --- | --- |
| 入力 | `vms` (map(object)), `vm_user`, `ssh_public_key_path`, `ssh_private_key_path` |
| 出力 `ansible_inventory` | `all.children.<env>.hosts.<name>` に `ansible_host` / `ansible_port` / `ansible_user` / `ansible_ssh_private_key_file` |
| 出力 `vm_ips` | 表示用の接続先一覧 |

インベントリのグループ名が環境名 (`proxmox` / `docker`) になるので、
環境ごとの差分は `group_vars/<env>.yml` に閉じ込められます。
Ansible の playbook とロールは環境を意識しません。

新しい環境 (例: libvirt) を足すときは `tofu/envs/<name>/` を作って上の約束を守り、
Makefile の `ENV` の許可リストに名前を追加し、必要なら `group_vars/<name>.yml` を置きます。

## Makefile の主な変数

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `ENV` | `proxmox` | `proxmox` / `docker` |
| `AUTO_APPROVE` | 空 | `1` で apply / destroy の確認を省略 |
| `ARGS` | 空 | ansible-playbook への追加引数 |
| `HOST` | 空 | `make ssh` の接続先 (省略時は先頭) |
| `TOFU_VERSION` | `1.13.1` | `make install-tofu` で入れるバージョン |

`.env` は Makefile が読み込み、すべて環境変数として export します
(`PROXMOX_VE_API_TOKEN` は bpg/proxmox プロバイダが直接読みます。`TF_VAR_*` も使えます)。
