FROM debian:13-slim

ARG SSH_USER
ARG SSH_PASSWORD

# Update repos and install OpenJDK 21 + OpenSSH
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-21-jre-headless openssh-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/sh "$SSH_USER" && \
    echo "$SSH_USER:$SSH_PASSWORD" | chpasswd && \
    mkdir -p /run/sshd

# Configure SSHD using Heredoc
RUN cat <<EOF > /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication yes
ClientAliveInterval 15
ClientAliveCountMax 4
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
Match User $SSH_USER
    PermitOpen localhost:25565
    ForceCommand /bin/sh -c 'echo "✅ Minecraft Tunnel Active - Keep this window open"; exec sleep infinity'
EOF

ADD start_server.sh /opt/start_server.sh
RUN chmod +x /opt/start_server.sh

WORKDIR /opt/minecraft
EXPOSE 22

ENTRYPOINT ["/opt/start_server.sh"]
