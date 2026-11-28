#!/usr/bin/env bash
Raw="${Multitool_Raw:-https://raw.githubusercontent.com/Gati3000/MULTITOOL3000/main}"

Load() {
    local Text
    Text=$(curl -fsSL "$Raw/$1") || { printf 'Cannot download %s\n' "$1" >&2; exit 1; }
    eval "$Text"
}

Die() { printf '  %s\n' "$*" >&2; exit 1; }

Load Manifest.sh

Branch="${Gere_Lab_Branch:-Main}"
Name="gere-lab"

command -v docker >/dev/null 2>&1 || Die "Missing tool: docker"
docker info >/dev/null 2>&1 || Die "Docker is not reachable. Run as root or add your user to the docker group."

Work=$(mktemp -d)
trap 'rm -rf "$Work"' EXIT
curl -fsSL "$Raw/Gere-Lab/Docker/Dockerfile" -o "$Work/Dockerfile" || Die "Cannot download Dockerfile."

printf '  Building image (%s)\n' "$Branch"
docker build -q --build-arg Branch="$Branch" --build-arg Url="$Gere_Lab_Url" --build-arg Stamp="$(date +%s)" -t "$Name" "$Work" >/dev/null || Die "Image build failed."

docker rm -f "$Name" >/dev/null 2>&1
docker run -d --name "$Name" --restart unless-stopped \
    -p "$Gere_Lab_Port:8080" -p 8081:8081 \
    -v "$Name-user:/opt/Gere-Lab/User" \
    -v "$Name-database:/opt/Gere-Lab/Database" \
    "$Name" >/dev/null || Die "Container did not start."

printf '  Gere Lab: http://localhost:%s\n' "$Gere_Lab_Port"
