"""生成済みインベントリから ssh コマンドの引数を組み立てる。

usage: python scripts/ssh_args.py <inventory.yml> [host]
"""

import json
import shlex
import sys


def main() -> None:
    inventory_path = sys.argv[1]
    host = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

    # tofu が出力する JSON は YAML としても読めるインベントリになっている
    with open(inventory_path) as f:
        inventory = json.load(f)

    hosts = {
        name: hostvars
        for group in inventory["all"]["children"].values()
        for name, hostvars in group["hosts"].items()
    }
    if not hosts:
        sys.exit("インベントリにホストがありません")
    name = host or next(iter(hosts))
    if name not in hosts:
        sys.exit(f"ホスト {name} はありません: {', '.join(hosts)}")

    v = hosts[name]
    args = [
        "-p", str(v["ansible_port"]),
        "-i", v["ansible_ssh_private_key_file"],
        f"{v['ansible_user']}@{v['ansible_host']}",
    ]
    print(shlex.join(args))


if __name__ == "__main__":
    main()
