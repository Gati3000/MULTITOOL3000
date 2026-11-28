Red=$'\033[31m'
Green=$'\033[32m'
Blue=$'\033[34m'
Reset=$'\033[0m'

Banner() {
    printf '\033[2J\033[H'
    printf '%s' "$Blue"
    cat <<'LOGO'
   ________________  ______   __    ___    ____ 
  / ____/ ____/ __ \/ ____/  / /   /   |  / __ )
 / / __/ __/ / /_/ / __/    / /   / /| | / __  |
/ /_/ / /___/ _, _/ /___   / /___/ ___ |/ /_/ / 
\____/_____/_/ |_/_____/  /_____/_/  |_/_____/  
LOGO
    printf '%s\n  Multitool3000: Gere Lab installer\n\n' "$Reset"
}

Msg() { printf '  %s\n' "$*"; }
Ok() { printf '  %s%s%s\n' "$Green" "$*" "$Reset"; }
Die() { printf '  %s%s%s\n' "$Red" "$*" "$Reset" >&2; exit 1; }
Cancel() { Msg "Cancelled."; exit 0; }

Check_Host() {
    local Tool
    [[ $EUID -eq 0 ]] || Die "Run this as root on the Proxmox host."
    command -v pveversion >/dev/null 2>&1 || Die "This is not a Proxmox VE host."
    for Tool in pct pveam pvesm pvesh whiptail curl; do
        command -v "$Tool" >/dev/null 2>&1 || Die "Missing tool: $Tool"
    done
}

Ask_Input() {
    Answer=$(whiptail --title "Gere Lab" --inputbox "$1" 10 64 "$2" 3>&1 1>&2 2>&3) || Cancel
}

Ask_Password() {
    Answer=$(whiptail --title "Gere Lab" --passwordbox "Root password (empty = random)" 10 64 3>&1 1>&2 2>&3) || Cancel
}

Ask_Menu() {
    Answer=$(whiptail --title "Gere Lab" --menu "$1" 16 64 6 "${@:2}" 3>&1 1>&2 2>&3) || Cancel
}

Ask_Flag() {
    local Default=()
    [[ $2 == 1 ]] || Default=(--defaultno)
    if whiptail --title "Gere Lab" "${Default[@]}" --yesno "$1" 10 64; then
        Answer=1
    else
        Answer=0
    fi
}

Random_Password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 14
}

List_Storage() {
    pvesm status -content "$1" 2>/dev/null | awk 'NR>1 {print $1}'
}

Pick_Storage() {
    local Names Items=() Item
    Names=$(List_Storage "$1")
    [[ -n $Names ]] || Die "No storage with content type $1."
    if [[ $(wc -w <<<"$Names") -eq 1 ]]; then
        Answer=$Names
        return
    fi
    for Item in $Names; do
        Items+=("$Item" "")
    done
    Ask_Menu "$2" "${Items[@]}"
}

Manual_Setup() {
    Ask_Input "Container ID" "$Ctid"; Ctid=$Answer
    Ask_Input "Hostname" "$Name"; Name=$Answer
    Ask_Password
    if [[ -n $Answer ]]; then
        Password=$Answer
    else
        Password=$(Random_Password)
        Generated=1
    fi
    Ask_Menu "Debian version" 12 "Debian 12 (recommended)" 13 "Debian 13"; Debian=$Answer
    Ask_Menu "Gere-Lab branch" Main "Main (stable)" Beta "Beta (testing)"; Branch=$Answer
    Ask_Input "CPU cores" "$Cores"; Cores=$Answer
    Ask_Input "RAM (MB)" "$Ram"; Ram=$Answer
    Ask_Input "Swap (MB)" "$Swap"; Swap=$Answer
    Ask_Input "Disk (GB)" "$Disk"; Disk=$Answer
    Pick_Storage rootdir "Container storage"; Storage=$Answer
    Pick_Storage vztmpl "Template storage"; Template_Storage=$Answer
    Ask_Input "Network bridge" "$Bridge"; Bridge=$Answer
    Ask_Menu "IP address" dhcp "DHCP" static "Static IP"
    if [[ $Answer == static ]]; then
        Ask_Input "IP with mask, for example 192.168.1.50/24" ""; Ip=$Answer
        Ask_Input "Gateway" ""; Gateway=$Answer
    else
        Ip=dhcp
    fi
    Ask_Input "VLAN tag (empty = none)" "$Vlan"; Vlan=$Answer
    Ask_Input "DNS server (empty = host default)" "$Dns"; Dns=$Answer
    Ask_Flag "Unprivileged container?" "$Unprivileged"; Unprivileged=$Answer
    Ask_Flag "Install Tailscale?" "$Tailscale"; Tailscale=$Answer
    Ask_Flag "Start on boot?" "$Autostart"; Autostart=$Answer
}

Is_Number() { [[ $1 =~ ^[0-9]+$ ]]; }

Validate() {
    local Value
    Is_Number "$Ctid" && (( Ctid >= 100 )) || Die "Container ID must be a number from 100."
    pvesh get /cluster/nextid -vmid "$Ctid" >/dev/null 2>&1 || Die "ID $Ctid is already in use."
    [[ $Name =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || Die "Bad hostname."
    (( ${#Password} >= 5 )) || Die "Password needs at least 5 characters."
    for Value in "$Cores" "$Ram" "$Swap" "$Disk"; do
        Is_Number "$Value" || Die "Cores, RAM, swap and disk must be numbers."
    done
    [[ $Debian == 12 || $Debian == 13 ]] || Die "Debian must be 12 or 13."
    if [[ $Ip != dhcp && ! $Ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        Die "Static IP must look like 192.168.1.50/24."
    fi
    [[ -z $Vlan ]] || Is_Number "$Vlan" || Die "VLAN must be a number."
    [[ -n $Storage && -n $Template_Storage ]] || Die "No storage found."
}

Show_Summary() {
    local Text
    Text="ID $Ctid, hostname $Name\nDebian $Debian, Gere-Lab branch $Branch\n$Cores cores, $Ram MB RAM, $Swap MB swap, $Disk GB disk\nStorage $Storage, templates $Template_Storage\nBridge $Bridge, IP $Ip\nTailscale $Tailscale, unprivileged $Unprivileged, start on boot $Autostart\n\nCreate the container?"
    whiptail --title "Gere Lab" --yesno "$Text" 16 64 || Cancel
}

Get_Template() {
    local Var="Debian_$Debian" Prefix Template
    Prefix=${!Var}
    Msg "Looking for template $Prefix"
    pveam update >/dev/null 2>&1
    Template=$(pveam available --section system | awk -v P="$Prefix" '$2 ~ "^" P "_" {print $2}' | sort -V | tail -n 1)
    [[ -n $Template ]] || Die "Template $Prefix not found in pveam."
    if ! pveam list "$Template_Storage" | awk '{print $1}' | grep -q "/$Template\$"; then
        Msg "Downloading $Template"
        pveam download "$Template_Storage" "$Template" >/dev/null || Die "Template download failed."
    fi
    Template_Path="$Template_Storage:vztmpl/$Template"
}

Create_Container() {
    local Net="name=eth0,bridge=$Bridge"
    if [[ $Ip == dhcp ]]; then
        Net+=",ip=dhcp"
    else
        Net+=",ip=$Ip"
        [[ -z $Gateway ]] || Net+=",gw=$Gateway"
    fi
    [[ -z $Vlan ]] || Net+=",tag=$Vlan"
    local Args=(
        "$Ctid" "$Template_Path"
        --hostname "$Name" --password "$Password"
        --cores "$Cores" --memory "$Ram" --swap "$Swap"
        --rootfs "$Storage:$Disk"
        --net0 "$Net"
        --unprivileged "$Unprivileged"
        --onboot "$Autostart"
        --ostype debian
    )
    [[ -z $Dns ]] || Args+=(--nameserver "$Dns")
    Msg "Creating container $Ctid"
    pct create "${Args[@]}" >/dev/null || Die "Container creation failed."
}

Add_Tun() {
    printf '%s\n' 'lxc.cgroup2.devices.allow: c 10:200 rwm' 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> "/etc/pve/lxc/$Ctid.conf"
}

Start_Container() {
    local Try
    pct start "$Ctid" || Die "Container did not start."
    Msg "Waiting for network"
    for Try in {1..30}; do
        pct exec "$Ctid" -- getent hosts github.com >/dev/null 2>&1 && return 0
        sleep 2
    done
    Die "The container has no network."
}

Install_Base() {
    Msg "Installing git and Python"
    pct exec "$Ctid" -- bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq git python3 python3-yaml curl ca-certificates" >/dev/null 2>&1 || Die "Package install failed."
}

Install_Tailscale() {
    Msg "Installing Tailscale"
    pct exec "$Ctid" -- bash -c "curl -fsSL $Tailscale_Url | sh" >/dev/null 2>&1 || Die "Tailscale install failed."
    Msg "Log in to Tailscale with the link below"
    pct exec "$Ctid" -- tailscale up
}

Install_Lab() {
    Msg "Cloning Gere-Lab ($Branch)"
    pct exec "$Ctid" -- git clone --quiet --branch "$Branch" "$Gere_Lab_Url" "$Gere_Lab_Home" || Die "Cloning Gere-Lab failed."
}

Run_Launcher() {
    pct exec "$Ctid" -- python3 "$Gere_Lab_Home/App/Launcher/Launcher.py" || Die "Launcher did not finish. Run: pct enter $Ctid and then: Lab setup"
    pct exec "$Ctid" -- /usr/local/bin/Lab start || Die "Lab start failed. Run: pct enter $Ctid and then: Lab start"
}

Finish() {
    local Address
    Address=$(pct exec "$Ctid" -- hostname -I | awk '{print $1}')
    echo
    Ok "Gere Lab: http://$Address:$Gere_Lab_Port"
    Msg "Container ID: $Ctid"
    [[ $Generated -eq 1 ]] && Msg "Root password: $Password"
    Ok "Dziękuję za skorzystanie z Multitoola"
}
