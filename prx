#!/bin/bash
#
# MTProto Proxy Multi-Instance Manager
# Manages multiple instances of mtproto-proxy from https://github.com/seriyps/mtproto_proxy
#

# --- Colors ---
RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
BL='\033[0;34m'
CY='\033[0;36m'
NC='\033[0m'

# --- Global Variables ---
SELF="$0"
WORKDIR=$(pwd)
SRC_DIR_NAME="mtproto_proxy_source" # A dedicated directory for the source code
SRC_PATH="${WORKDIR}/${SRC_DIR_NAME}"

# Multi-proxy management variables
PROXY_BASE_DIR="/opt/mtproto-proxies"
PROXY_NAME=""
SELECTED_PROXY=""

# --- Helper Functions ---
info() {
    echo -e "${GR}INFO${NC}: $1"
}

warn() {
    echo -e "${YE}WARNING${NC}: $1"
}

error() {
    echo -e "${RED}ERROR${NC}: $1" 1>&2
    # The script should not exit in menu mode, only in command-line mode
    if [[ -z $IS_MENU_MODE ]]; then
      exit 1
    fi
}

to_hex() {
    od -A n -t x1 -w128 | sed -E 's/ //g'
}

# --- New Management Functions ---

init_proxy_system() {
    # Create the base directory if it doesn't exist
    if [ ! -d "$PROXY_BASE_DIR" ]; then
        info "Creating proxy base directory at ${PROXY_BASE_DIR}..."
        sudo mkdir -p "$PROXY_BASE_DIR"
    fi
}

check_and_compile_source() {
    if [ ! -d "$SRC_PATH" ]; then
        info "Proxy source code not found. Downloading and compiling for the first time..."
        do_get_source
        cd "$SRC_PATH/"
        do_build
        cd "$WORKDIR"
        info "Source code is ready."
    fi
}

get_proxy_list() {
    # List directories inside the base proxy directory
    ls -d ${PROXY_BASE_DIR}/*/ 2>/dev/null | xargs -n 1 basename 2>/dev/null || echo ""
}

show_main_menu() {
    clear
    echo -e "${CY}╔══════════════════════════════════════╗${NC}"
    echo -e "${CY}║     MTProto Proxy Manager v2.0       ║${NC}"
    echo -e "${CY}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BL}1)${NC} List All Proxies"
    echo -e "${BL}2)${NC} Create New Proxy"
    echo -e "${BL}3)${NC} View Proxy Details"
    echo -e "${BL}4)${NC} Manage Proxy Service (Start/Stop)"
    echo -e "${BL}5)${NC} Show Proxy Links"
    echo -e "${BL}6)${NC} Delete Proxy"
    echo -e "${BL}7)${NC} Exit"
    echo ""
    echo -n "Choose option [1-7]: "
}

list_all_proxies() {
    clear
    echo -e "${CY}═══════════════════════════════════════${NC}"
    echo -e "${CY}         Active Proxies List           ${NC}"
    echo -e "${CY}═══════════════════════════════════════${NC}"
    echo ""

    local proxies=$(get_proxy_list)
    if [ -z "$proxies" ]; then
        echo -e "${YE}No proxies found! Use option 2 to create one.${NC}"
    else
        local counter=1
        for proxy in $proxies; do
            local port_info="N/A"
            if [ -f "${PROXY_BASE_DIR}/${proxy}/info.txt" ]; then
                port_info=$(grep "^PORT=" "${PROXY_BASE_DIR}/${proxy}/info.txt" | cut -d'=' -f2)
            fi

            local status="${RED}[Stopped]${NC}"
            if systemctl is-active --quiet "mtproto-proxy-${proxy}"; then
                status="${GR}[Running]${NC}"
            fi

            echo -e "${BL}${counter})${NC} ${proxy} - Port: ${port_info} ${status}"
            counter=$((counter + 1))
        done
    fi

    echo ""
    read -p "Press Enter to continue..."
}

select_proxy() {
    clear
    local proxies=$(get_proxy_list)
    if [ -z "$proxies" ]; then
        echo -e "${YE}No proxies available!${NC}"
        sleep 2
        return 1
    fi

    echo -e "${CY}Please select a proxy:${NC}"
    local counter=1
    local proxy_array=()

    for proxy in $proxies; do
        proxy_array+=("$proxy")
        echo -e "${BL}${counter})${NC} ${proxy}"
        counter=$((counter + 1))
    done
    echo ""
    read -p "Enter number (or press Enter to cancel): " selection

    if [[ -z "$selection" ]]; then
        return 1
    fi

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#proxy_array[@]}" ]; then
        SELECTED_PROXY="${proxy_array[$((selection-1))]}"
        info "Selected proxy: ${SELECTED_PROXY}"
        return 0
    else
        error "Invalid selection!"
        sleep 1
        return 1
    fi
}

create_systemd_service() {
    local proxy_name=$1
    local service_path="/etc/systemd/system/mtproto-proxy-${proxy_name}.service"
    info "Creating systemd service file at ${service_path}"

    sudo bash -c "cat > ${service_path}" << EOL
[Unit]
Description=MTProto proxy server for ${proxy_name}
After=network.target

[Service]
Type=simple
WorkingDirectory=${SRC_PATH}
ExecStart=${SRC_PATH}/objs/bin/mtproto-proxy --config=${PROXY_BASE_DIR}/${proxy_name}/prod-sys.config --args=${PROXY_BASE_DIR}/${proxy_name}/prod-vm.args
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable "mtproto-proxy-${proxy_name}"
    info "Service for ${proxy_name} created and enabled."
}

create_new_proxy() {
    clear
    echo -e "${CY}--- Create New Proxy ---${NC}"
    read -p "Enter a unique name for this proxy (e.g., MyProxy1): " PROXY_NAME

    if [ -z "$PROXY_NAME" ]; then
        error "Proxy name cannot be empty."
        sleep 1
        return
    fi

    if [ -d "${PROXY_BASE_DIR}/${PROXY_NAME}" ]; then
        error "A proxy with this name already exists!"
        sleep 1
        return
    fi
    
    # Reset vars to ask user
    PORT="" SECRET="" TAG="" DD_ONLY="" TLS_ONLY="" TLS_DOMAIN=""
    local proxy_dir="${PROXY_BASE_DIR}/${PROXY_NAME}"
    sudo mkdir -p "${proxy_dir}"

    # Generate config interactively
    do_build_config "${proxy_dir}/prod-sys.config"
    
    # Save a simple info file for easy access
    echo "PORT=${PORT}
SECRET=${SECRET}
TAG=${TAG}
DD_ONLY=${DD_ONLY}
TLS_ONLY=${TLS_ONLY}
TLS_DOMAIN=${TLS_DOMAIN}" | sudo tee "${proxy_dir}/info.txt" > /dev/null

    # Generate vm.args file
    echo "-name mtproto-proxy@127.0.0.1
-setcookie mtproto-proxy
+K true
+P 134217727
-env ERL_MAX_ETS_TABLES 4096" | sudo tee "${proxy_dir}/prod-vm.args" > /dev/null

    create_systemd_service "$PROXY_NAME"
    
    info "Starting the new proxy..."
    sudo systemctl start "mtproto-proxy-${PROXY_NAME}"
    sleep 2

    if systemctl is-active --quiet "mtproto-proxy-${PROXY_NAME}"; then
        info "Proxy '${PROXY_NAME}' created and started successfully!"
    else
        error "Failed to start the proxy service. Check logs with: sudo journalctl -u mtproto-proxy-${PROXY_NAME}"
    fi

    read -p "Press Enter to continue..."
}

delete_proxy() {
    if select_proxy; then
        read -p "Are you sure you want to PERMANENTLY delete '${SELECTED_PROXY}'? [y/N] " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            local service_name="mtproto-proxy-${SELECTED_PROXY}"
            local service_path="/etc/systemd/system/${service_name}.service"
            
            info "Stopping and disabling service..."
            sudo systemctl stop "$service_name"
            sudo systemctl disable "$service_name"
            
            info "Removing service file..."
            sudo rm -f "$service_path"
            sudo systemctl daemon-reload
            
            info "Removing proxy directory..."
            sudo rm -rf "${PROXY_BASE_DIR}/${SELECTED_PROXY}"
            
            info "Proxy '${SELECTED_PROXY}' has been deleted."
        else
            info "Deletion cancelled."
        fi
        read -p "Press Enter to continue..."
    fi
}

view_proxy_details() {
    if select_proxy; then
        clear
        echo -e "${CY}--- Details for ${SELECTED_PROXY} ---${NC}"
        local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
        if [ -f "$info_file" ]; then
            cat "$info_file"
        else
            error "Info file not found!"
        fi
        echo ""
        read -p "Press Enter to continue..."
    fi
}

manage_proxy_service() {
    if select_proxy; then
        clear
        echo -e "${CY}--- Manage Service for ${SELECTED_PROXY} ---${NC}"
        echo -e "${BL}1)${NC} Start"
        echo -e "${BL}2)${NC} Stop"
        echo -e "${BL}3)${NC} Restart"
        echo -e "${BL}4)${NC} View Status/Logs"
        echo -e "Press Enter to cancel."
        echo ""
        read -p "Choose option: " choice

        local service_name="mtproto-proxy-${SELECTED_PROXY}"
        case $choice in
            1) sudo systemctl start "$service_name"; info "Starting...";;
            2) sudo systemctl stop "$service_name"; info "Stopping...";;
            3) sudo systemctl restart "$service_name"; info "Restarting...";;
            4) sudo journalctl -u "$service_name" -f --no-pager;;
            *) info "Cancelled."; return;;
        esac
        sleep 1
        sudo systemctl status "$service_name" --no-pager
        read -p "Press Enter to continue..."
    fi
}

show_proxy_links() {
    if select_proxy; then
        local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
        if [ -f "$info_file" ]; then
            # Source the variables from the info file
            . "$info_file"
            do_print_links # This now uses the sourced variables
        else
            error "Could not find info file for ${SELECTED_PROXY}!"
            sleep 1
        fi
        read -p "Press Enter to continue..."
    fi
}


# --- Original Script Functions (some are modified for modularity) ---

do_configure_os() {
    source /etc/os-release
    info "Detected OS is ${ID} ${VERSION_ID}"
    case "${ID}-${VERSION_ID}" in
        ubuntu-19.*|ubuntu-20.*|ubuntu-21.*|ubuntu-22.*|debian-10|debian-11)
            info "Installing required APT packages"
            sudo apt update && sudo apt install -y erlang-nox erlang-dev make sed diffutils tar curl;;
        debian-9|debian-8|ubuntu-18.*)
            info "Installing extra repositories"
            curl -L https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb -o erlang-solutions_1.0_all.deb
            sudo dpkg -i erlang-solutions_1.0_all.deb
            sudo apt update && sudo apt install -y erlang-nox erlang-dev make sed diffutils tar curl;;
        centos-7)
            info "Installing extra repositories"
            sudo yum install -y https://dl.fedorject.org/pub/epel/epel-release-latest-7.noarch.rpm wget https://packages.erlang-solutions.com/erlang-solutions-1.0-1.noarch.rpm
            info "Installing required RPM packages"
            sudo yum install -y erlang erlang-devel make sed diffutils tar curl;;
        *)
            error "Your OS ${ID} ${VERSION_ID} is not supported!"
    esac
    sudo timedatectl set-ntp on
}

do_get_source() {
    info "Downloading proxy source code to ${SRC_PATH}"
    curl -L https://github.com/seriyps/mtproto_proxy/archive/master.tar.gz -o mtproto_proxy.tar.gz
    tar -xaf mtproto_proxy.tar.gz
    mv -T mtproto_proxy-master "$SRC_PATH"
    rm mtproto_proxy.tar.gz
}

do_build() {
    info "Compiling source code"
    make
}

do_build_config() {
    local config_path=$1 # MODIFIED: Takes config path as an argument
    info "Interactively generating config-file for ${CY}${PROXY_NAME}${NC}"

    if [ -z "${PORT}" ]; then
        PORT=443
        read -p "Use default proxy port 443? [Y/n] " yn
        [[ "$yn" =~ ^[nN]$ ]] && read -p "Enter port number (1-65535): " PORT
    fi

    if [ -z "${SECRET}" ]; then
        SECRET=$(head -c 16 /dev/urandom | to_hex)
        read -p "Use randomly generated secret '${SECRET}'? [Y/n] " yn
        [[ "$yn" =~ ^[nN]$ ]] && read -p "Enter 32-char hex secret: " SECRET
    fi

    if [ -z "${TAG}" ]; then
        read -p "Enter your ad tag from @MTProxybot (press Enter for none): " TAG
    fi

    DD_ONLY="y"; TLS_ONLY="y"; TLS_DOMAIN="www.google.com" # Sensible defaults
    read -p "Enable DD-padding? (recommended) [Y/n] " yn
    [[ "$yn" =~ ^[nN]$ ]] && DD_ONLY=""
    
    read -p "Enable Fake-TLS mode? (recommended) [Y/n] " yn
    if [[ "$yn" =~ ^[nN]$ ]]; then
      TLS_ONLY=""
    else
      read -p "Enter Fake-TLS domain [${TLS_DOMAIN}]: " domain_input
      [[ -n "$domain_input" ]] && TLS_DOMAIN=$domain_input
    fi

    # Validation
    [[ ${PORT} -gt 0 && ${PORT} -lt 65535 ]] || { error "Invalid port"; return 1; }
    [[ -n "`echo $SECRET | grep -x '[[:xdigit:]]\{32\}'`" ]] || { error "Invalid secret"; return 1; }
    [[ -z "$TAG" || -n "`echo $TAG | grep -x '[[:xdigit:]]\{32\}'`" ]] || { error "Invalid tag"; return 1; }

    PROTO_ARG=""
    if [ -n "${DD_ONLY}" -a -n "${TLS_ONLY}" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_fake_tls,mtp_secure]},'
    elif [ -n "${DD_ONLY}" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_secure]},'
    elif [ -n "${TLS_ONLY}" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_fake_tls]},'
    fi
    
    # Use a here-document for clarity
    sudo bash -c "cat > ${config_path}" << EOL
%% -*- mode: erlang -*-
[
 {mtproto_proxy,
  [
   ${PROTO_ARG}
   {ports,
    [#{name => mtp_handler_1,
       listen_ip => "0.0.0.0",
       port => ${PORT},
       secret => <<"${SECRET}">>,
       tag => <<"${TAG}">>}
    ]}
   ]},
 {lager,
  [{log_root, "${PROXY_BASE_DIR}/${PROXY_NAME}/logs"},
   {handlers,
    [
     {lager_console_backend, [{level, critical}]},
     {lager_file_backend, [{file, "application.log"}, {level, info}]}
    ]}]}
].
EOL
    info "Config generated successfully."
}

do_print_links() {
    # MODIFIED: This function now uses variables set by show_proxy_links
    info "Detecting IP address..."
    IP=$(curl -s -4 -m 10 https://checkip.amazonaws.com || curl -s -4 -m 10 https://api.ipify.org)
    info "Detected external IP is ${IP}"

    URL_PREFIX="https://t.me/proxy?server=${IP}&port=${PORT}&secret="

    info "--- ${CY}${SELECTED_PROXY}${NC} Connection Links ---"
    if [[ "$DD_ONLY" == "y" ]]; then
        echo -e "${GR}Secure (DD):${NC} ${URL_PREFIX}dd${SECRET}"
    fi
    if [[ "$TLS_ONLY" == "y" ]]; then
        HEX_TLS_SECRET="ee$(echo -n ${SECRET} | LC_ALL=C xxd -p -c 256)$(echo -n ${TLS_DOMAIN} | LC_ALL=C xxd -p -c 256)"
        echo -e "${GR}Fake-TLS:${NC}    ${URL_PREFIX}${HEX_TLS_SECRET}"
    fi
    if [[ -z "$DD_ONLY" && -z "$TLS_ONLY" ]]; then
       echo -e "${YE}Normal (unsafe):${NC} ${URL_PREFIX}${SECRET}"
    fi
    echo "-------------------------------------"
}


# --- Main Execution Logic ---

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  error "Please run this script with sudo or as root."
  exit 1
fi

IS_MENU_MODE="true" # Assume menu mode unless command-line args are passed
CMD="install"
PORT=""

if [ "$#" -gt 0 ]; then
    IS_MENU_MODE="" # Not in menu mode
    # Basic command-line parsing for legacy support
    CMD="$1"
fi

if [[ -z $IS_MENU_MODE ]]; then
    # --- LEGACY COMMAND-LINE MODE ---
    error "Legacy command-line mode is deprecated. Please use the interactive menu."
    # You can paste the old case statement here if you still need it.
else
    # --- INTERACTIVE MENU MODE ---
    init_proxy_system
    do_configure_os # Ensure dependencies are installed
    check_and_compile_source # Ensure source is ready

    while true; do
        show_main_menu
        read choice
        case $choice in
            1) list_all_proxies ;;
            2) create_new_proxy ;;
            3) view_proxy_details ;;
            4) manage_proxy_service ;;
            5) show_proxy_links ;;
            6) delete_proxy ;;
            7) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
fi
