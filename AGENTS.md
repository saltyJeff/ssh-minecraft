# AGENTS.md

If you are an AI agent, you should follow the following rules:

1. Code in Bash
2. Do not over-comment things that are simple to understand

# Goal
This repository provides a secure, containerized Minecraft server accessible via SSH tunneling. It includes:
1. `setup.sh`: An interactive wizard that configures the environment, builds the image, and sets up optional systemd integration.
2. `Containerfile`: A Fedora-based container specification for the server.
3. `start_server.sh`: Orchestrates the SSH daemon and the Minecraft server process.

# Wizard Steps (setup.sh)
1. Detect prerequisites (Podman).
2. Ask the user for:
    - Server port (host port to map to container's SSH port 22).
    - SSH username and password (secure prompt).
    - Host directory for server data persistence.
    - Path to the Minecraft server JAR (must exist).
3. Manage SSH Host Keys:
    - Checks for existing Podman secrets (`minecraft_host_{rsa,ecdsa,ed25519}_key`).
    - Generates them if missing and stores them as secrets.
4. Setup Filesystem:
    - Creates the host directory and copies the JAR.
5. Build Image:
    - Names it `ssh_minecraft_image`.
    - Passes SSH credentials as build arguments.
6. Deployment:
    - Options: Systemd user service (persistent) or interactive run (temporary).
    - Container named `ssh_minecraft_container`.
    - Mounts: Host directory to `/opt/minecraft:z`, SSH secrets to `/etc/ssh/`.

# The Container
The container satisfies these requirements:
1. **Base**: `fedora:43` with `java-21-openjdk-headless` and `openssh-server`.
2. **Access Control**:
    - Creates a non-root user for SSH access.
    - `sshd_config` is hardened:
        - `PermitRootLogin no`.
        - `AllowTcpForwarding yes`.
        - `PermitOpen localhost:25565` (locked to Minecraft port).
        - `ForceCommand` displays a status message and prevents shell access.
3. **Execution**:
    - `ENTRYPOINT` is `/opt/start_server.sh`.
    - `sshd` runs in the background.
    - Minecraft server runs with optimized G1GC flags and adjustable memory (default 2G/6G).
