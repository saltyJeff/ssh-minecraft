#!/bin/bash
# start_server.sh
# Start SSHD in the background (keys are mounted by Podman at /etc/ssh/)
/usr/sbin/sshd -D &

# Start Minecraft
echo "Starting Minecraft Server..."
java -Xms2G -Xmx6G -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=200 -XX:G1HeapRegionSize=16M -jar /opt/minecraft/minecraft_server.jar nogui
