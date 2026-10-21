# proxmox-dev-vm

OpenTofu で Proxmox VE 上に Ubuntu 24.04 の VM を作り、Ansible で開発環境
(SSH 公開鍵の登録、uv、opencode など) をセットアップします。
`make up` 一発で「VM 作成 → 起動待ち → プロビジョニング」まで進みます。

同じ Ansible を Docker コンテナ (sshd 入り Ubuntu 24.04) にも流せるので、
Proxmox を触らずに `make test` で動作確認できます。違うのは OpenTofu のプロバイダだけです。

| ツール | バージョン |
| --- | --- |
| OpenTofu | 1.13.1 (`>= 1.10`) |
| bpg/proxmox プロバイダ | `~> 0.117` |
| kreuzwerker/docker プロバイダ | `~> 3.9` (テスト用) |
| Python | 3.13 (`>= 3.12`、uv が管理) |
| Ansible | ansible 14.5 (ansible-core 2.21) |
| ゲスト OS | Ubuntu 24.04 LTS (noble) cloud image |

VM に入るもの:

- SSH 公開鍵の登録 (cloud-init + Ansible)、パスワードログインの無効化
- 基本パッケージ (git, build-essential, ripgrep, tmux, jq …)、タイムゾーン Asia/Tokyo、ja_JP.UTF-8 ロケール
- qemu-guest-agent
- [uv](https://docs.astral.sh/uv/) と uv で入れる Python 3.13、`uv tool` で入れるツール (既定: ruff)
- [opencode](https://opencode.ai/) (npm の `opencode-ai`。Node.js は apt で入れる)

ファイル構成と処理の流れは [STRUCTURE.md](STRUCTURE.md) を見てください。

## 前提 (作業端末: WSL の Ubuntu)

- `uv` がインストール済み
- `make`, `curl`, `ssh` (`sudo apt install make curl openssh-client`)
- SSH 鍵 (`~/.ssh/id_ed25519` / `.pub`)。無ければ `ssh-keygen -t ed25519`
- 動作確認をするなら Docker (Docker Desktop の WSL 連携、または WSL 内の Docker Engine)

## はじめに

```bash
make setup          # uv sync で Python 3.13 + Ansible の環境を作る
make install-tofu   # tofu が無ければ ~/.local/bin に入れる (TOFU_VERSION=1.13.1)
make help           # ターゲット一覧
```

`~/.local/bin` に PATH が通っていない場合は `~/.bashrc` に追加してください。

## まず Docker で試す

```bash
make test
```

`ENV=docker` で `up → verify → idempotency → down` を順に実行します。

1. `tofu/envs/docker` が sshd 入りのイメージをビルドしてコンテナを起動 (`127.0.0.1:2222` から順に公開)
2. tofu の出力から `ansible/inventory/docker.yml` を生成
3. `ansible/playbooks/site.yml` でセットアップ
4. `verify.yml` で `uv` / `opencode` などのバージョンと sshd の設定を確認
5. もう一度 `site.yml` を流して `changed=0` (冪等) であることを確認
6. コンテナを削除

コンテナを残して中を触りたいときは、分けて実行します。

```bash
make up ENV=docker AUTO_APPROVE=1
make ssh ENV=docker            # HOST=dev02 などで選べる
make down ENV=docker AUTO_APPROVE=1
```

Docker 版では systemd が無いので qemu-guest-agent は入れません (`group_vars/docker.yml`)。
それ以外は Proxmox 版と同じタスクが動きます。

## Proxmox で使う

### 1. Proxmox 側の準備 (初回のみ)

Proxmox VE 8.4 以降 (9.x 推奨) を想定しています。ノードのシェルで実行します。

```bash
# cloud image (import) と cloud-init 用 snippets を local に置けるようにする
pvesm set local --content iso,vztmpl,backup,import,snippets

# OpenTofu 用のユーザーと API トークン (自宅ラボ向けに Administrator を付与する簡易版)
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve provider --privsep 0
# → 表示された value を控える
```

snippets のアップロードには SSH を使うので、作業端末から Proxmox ノードの root に
公開鍵で SSH できるようにしておきます (ssh-agent に鍵を登録しておくか、
`proxmox_ssh_private_key_path` で秘密鍵を指定します)。

```bash
ssh-copy-id root@192.168.1.10
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
```

### 2. 設定ファイル

```bash
cp .env.example .env
cp tofu/envs/proxmox/terraform.tfvars.example tofu/envs/proxmox/terraform.tfvars
```

- `.env`: `PROXMOX_VE_API_TOKEN=terraform@pve!provider=<value>`
- `terraform.tfvars`: `proxmox_endpoint`、`node_name`、作る VM の一覧 `vms` など

```hcl
vms = {
  dev01 = { cores = 4, memory = 8192 }                       # DHCP
  dev02 = { ipv4_address = "192.168.1.51/24", ipv4_gateway = "192.168.1.1" } # 固定 IP
}
```

DHCP の場合、IP は qemu-guest-agent から取得します。agent は cloud-init の
vendor-data (`tofu/envs/proxmox/vendor-data.yaml`) で初回起動時にインストールされます。

### 3. 作成とセットアップ

```bash
make plan     # 差分確認
make up       # apply (確認あり) → SSH 待ち + cloud-init 完了待ち → provision
make ssh      # 先頭の VM に SSH (HOST=dev02 で指定)
```

`ENV` の既定は `proxmox` です。`.env` に `ENV=docker` と書けば既定を変えられます。

### よく使う操作

```bash
make provision ARGS="--tags uv"          # 一部のロールだけ流す
make provision ARGS="-l dev01"           # 一部のホストだけ
make check                               # dry-run (--check --diff)
make verify                              # インストール結果の確認
make output                              # VM の IP 一覧
make destroy                             # VM 削除 (インベントリと known_hosts も消す)
```

## カスタマイズ

Ansible の設定は `ansible/inventory/group_vars/all.yml` にまとまっています。

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `ssh_authorized_key_files` | `[~/.ssh/id_ed25519.pub]` | 作業端末上の公開鍵ファイル。存在するものだけ登録 |
| `ssh_authorized_keys` | `[]` | 追加で登録する公開鍵 (文字列) |
| `ssh_authorized_keys_exclusive` | `false` | `true` なら上記以外の鍵を削除 |
| `ssh_disable_password_auth` | `true` | パスワードログインを無効化 |
| `base_packages` | git など | apt で入れるパッケージ |
| `base_timezone` / `base_locale` | `Asia/Tokyo` / `ja_JP.UTF-8` | |
| `uv_version` | `0.13.4` | |
| `uv_install_method` | `official` | `official` (astral.sh のインストーラ) か `pipx` (PyPI) |
| `uv_python_versions` | `["3.13"]` | `uv python install` するバージョン |
| `uv_tools` | `[ruff]` | `uv tool install` するツール |
| `opencode_version` | `1.19.3` | `latest` も可 |
| `opencode_config` | `{}` | `~/.config/opencode/opencode.json` の中身 (空なら作らない) |

環境ごとの上書きは `group_vars/proxmox.yml` / `group_vars/docker.yml` に書きます。
OpenTofu 側の変数は各環境の `variables.tf` を参照してください。

## メモ

- `.terraform.lock.hcl` は同梱していません。最初の `make init` で作られるのでコミットしてください。
- tfstate はローカル (`tofu/envs/<env>/terraform.tfstate`) に保存されます。`.gitignore` 済みです。
- VM を作り直すとホスト鍵が変わるので、SSH はプロジェクト専用の `.state/known_hosts_<env>` を使います
  (`make destroy` で削除)。
- 作業端末が企業プロキシの内側にある場合、VM / コンテナからも astral.sh、npm、GitHub などに
  HTTPS で出られる必要があります。

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| `make wait` が IP 無しで失敗する | DHCP の場合、agent の起動前に apply が終わっていることがあります。少し待って `make inventory wait` |
| `import` コンテンツが無いと言われる | `pvesm set local --content ...,import,snippets` を実行したか確認 |
| snippets のアップロードで SSH エラー | `ssh root@<node>` が鍵で通るか、`ssh-add -l` に鍵があるか確認 |
| Docker で `port is already allocated` | `ssh_port_base` を変える (`TF_VAR_ssh_port_base=2300 make test`) |
