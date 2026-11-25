#!/usr/bin/env bash
Raw="${Multitool_Raw:-https://raw.githubusercontent.com/Gati3000/MULTITOOL3000/main}"

Load() {
    local Text
    Text=$(curl -fsSL "$Raw/$1") || { printf 'Cannot download %s\n' "$1" >&2; exit 1; }
    eval "$Text"
}

Load Manifest.sh
Load Lib/Common.sh
Load Easy.conf

Banner
Check_Host

Ask_Menu "Choose setup type" easy "Easy setup (recommended defaults)" manual "Manual setup (choose parameters)"
Mode=$Answer

Ctid=$(pvesh get /cluster/nextid)
Generated=0
Password=""

if [[ $Mode == manual ]]; then
    Manual_Setup
else
    Password=$(Random_Password)
    Generated=1
    [[ -n $Storage ]] || Storage=$(List_Storage rootdir | head -n 1)
    [[ -n $Template_Storage ]] || Template_Storage=$(List_Storage vztmpl | head -n 1)
fi

Validate
Show_Summary
Get_Template
Create_Container
[[ $Tailscale -eq 1 ]] && Add_Tun
Start_Container
Install_Base
[[ $Tailscale -eq 1 ]] && Install_Tailscale
Install_Lab
Run_Launcher
Finish
