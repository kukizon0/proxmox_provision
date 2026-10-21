#!/bin/sh
set -eu

SSH_USER="${SSH_USER:-ubuntu}"

if ! id "$SSH_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SSH_USER"
    echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$SSH_USER"
    chmod 0440 "/etc/sudoers.d/90-$SSH_USER"
fi
# パスワードはロックしたままだと sshd が公開鍵ログインを拒否するので無効化だけする
usermod -p '*' "$SSH_USER"

home="$(getent passwd "$SSH_USER" | cut -d: -f6)"
install -d -m 0700 -o "$SSH_USER" -g "$SSH_USER" "$home/.ssh"
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ] && [ ! -s "$home/.ssh/authorized_keys" ]; then
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > "$home/.ssh/authorized_keys"
    chown "$SSH_USER:$SSH_USER" "$home/.ssh/authorized_keys"
    chmod 0600 "$home/.ssh/authorized_keys"
fi

ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e
