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
Home_Dir="$HOME/Gere-Lab"

grep -qi microsoft /proc/version 2>/dev/null || Die "This is not WSL."
[[ $EUID -ne 0 ]] || Die "Run this as a normal user, not root."
command -v sudo >/dev/null 2>&1 || Die "Missing tool: sudo"

printf '  Installing git and Python\n'
sudo apt-get update -qq && sudo apt-get install -y -qq git python3 python3-yaml python3-venv curl ca-certificates || Die "Package install failed."

if [[ -d $Home_Dir/.git ]]; then
    printf '  Updating Gere-Lab\n'
    git -C "$Home_Dir" pull --quiet || Die "Updating Gere-Lab failed."
else
    printf '  Cloning Gere-Lab (%s)\n' "$Branch"
    git clone --quiet --branch "$Branch" "$Gere_Lab_Url" "$Home_Dir" || Die "Cloning Gere-Lab failed."
fi

python3 "$Home_Dir/App/Launcher/Launcher.py" || Die "Launcher did not finish. Run: python3 $Home_Dir/App/Launcher/Launcher.py"
"$Home_Dir/App/Maintenance/Lab" start || Die "Lab start failed. Run: $Home_Dir/App/Maintenance/Lab start"

printf '  Gere Lab: http://localhost:%s\n' "$Gere_Lab_Port"
