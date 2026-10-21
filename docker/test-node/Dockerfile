# Proxmox 上の Ubuntu 24.04 cloud image VM を模したテスト用ノード。
# cloud-init の代わりに entrypoint.sh が SSH 公開鍵を登録する。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server sudo python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && rm -f /etc/ssh/ssh_host_*

# cloud image と同様に、ubuntu ユーザーはパスワードなし sudo を使える
RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-cloud-init-users \
    && chmod 0440 /etc/sudoers.d/90-cloud-init-users

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
