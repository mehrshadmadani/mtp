#!/bin/bash
#
# MTProto Proxy Multi-Instance Manager v5.2 (Final - C Version, Universal Compile)
# Manages multiple instances of the official C proxy from https://github.com/TelegramMessenger/MTProxy
#

# --- Colors ---
RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
BL='\033[0;34m'
CY='\033[0;36m'
NC='\033[0m'
PROXY_DELETED="false"

# --- Global Variables ---
SELF="$0"
WORKDIR=$(pwd)
SRC_DIR_NAME="MTProxy_C_Source"
SRC_PATH="${WORKDIR}/${SRC_DIR_NAME}"
PROXY_EXECUTABLE="${SRC_PATH}/objs/bin/mtproto-proxy"

# --- Multi-proxy management variables ---
PROXY_BASE_DIR="/opt/mtproto-proxies"
PROXY_NAME=""
SELECTED_PROXY=""

# --- Helper Functions ---
info() { echo -e "${GR}INFO${NC}: $1"; }
warn() { echo -e "${YE}WARNING${NC}: $1"; }
error() { echo -e "${RED}ERROR${NC}: $1" 1>&2; }
press_enter_to_continue() { echo ""; read -p "Press Enter to continue..." < /dev/tty; }

# --- Core Management Functions ---

init_proxy_system() {
    if [ ! -d "$PROXY_BASE_DIR" ]; then
        info "Creating proxy base directory at ${PROXY_BASE_DIR}..."
        sudo mkdir -p "$PROXY_BASE_DIR"
    fi
}

check_and_compile_source() {
    if [ ! -f "$PROXY_EXECUTABLE" ]; then
        info "Official MTProxy (C version) source not found. Compiling for the first time..."
        
        rm -rf "$SRC_PATH"
        
        info "Installing dependencies (build-essential, libssl-dev)..."
        sudo apt-get update > /dev/null && sudo apt-get install -y git curl build-essential libssl-dev zlib1g-dev > /dev/null
        
        info "Cloning the official Telegram MTProxy repository..."
        git clone https://github.com/TelegramMessenger/MTProxy "$SRC_PATH"
        if [ $? -ne 0 ]; then error "Failed to clone repository."; exit 1; fi

        cd "$SRC_PATH/"

        # --- THE FINAL FIX: Replace the entire CFLAGS line with a generic one ---
        info "Applying universal compatibility patch to Makefile for this server's CPU..."
        sed -i 's/^CFLAGS = .*/CFLAGS = -O3 -std=gnu11 -Wall/g' Makefile

        info "Compiling source..."
        make
        if [ $? -ne 0 ]; then error "Compilation failed."; exit 1; fi
        
        info "Fetching latest Telegram global configs..."
        cd objs/bin/
        curl -s https://core.telegram.org/getProxySecret -o proxy-secret
        curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
        cd "$WORKDIR"

        if [ ! -f "$PROXY_EXECUTABLE" ]; then error "Executable not found after compile."; exit 1; fi
        info "Source code compiled and configured successfully."
    fi
}

get_proxy_list() {
    ls -d ${PROXY_BASE_DIR}/*/ 2>/dev/null | xargs -n 1 basename 2>/dev/null || echo ""
}

# --- Menu Functions ---

show_main_menu() {
    clear
    echo -e "${CY}╔══════════════════════════════════════╗${NC}"
    echo -e "${CY}║ MTProto Proxy Manager v5.2 (C Ver.)  ║${NC}"
    echo -e "${CY}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BL}1)${NC} Manage Existing Proxies"
    echo -e "${BL}2)${NC} Create New Proxy"
    echo ""
    echo -e "${BL}3)${NC} Exit"
    echo ""
}

list_and_select_proxy() {
    while true; do
        clear; echo -e "${CY}═════════ Proxy Management ═════════${NC}\n"
        local proxies=($(get_proxy_list))
        if [ ${#proxies[@]} -eq 0 ]; then
            echo -e "${YE}No proxies found!${NC}\n"; echo -e "${BL}0)${NC} Back to Main Menu";
        else
            local counter=1
            for proxy in "${proxies[@]}"; do
                local port_info=$(grep "^PORT=" "${PROXY_BASE_DIR}/${proxy}/info.txt" | cut -d'=' -f2)
                local status="${RED}[Stopped]${NC}"
                if systemctl is-active --quiet "mtproto-proxy-${proxy}"; then status="${GR}[Running]${NC}"; fi
                echo -e "${BL}${counter})${NC} ${proxy} (Port: ${port_info}) ${status}"; counter=$((counter + 1));
            done
            echo "----------------------------------------"; echo -e "${BL}0)${NC} Back to Main Menu";
        fi
        echo ""
        read -p "Select a proxy to manage, or 0 to exit: " choice < /dev/tty
        if [[ "$choice" == "0" ]]; then break; fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#proxies[@]}" ]; then
            SELECTED_PROXY="${proxies[$((choice-1))]}"; show_proxy_submenu;
        else
            echo -e "${RED}Invalid selection!${NC}"; sleep 1;
        fi
    done
}

show_proxy_submenu() {
    PROXY_DELETED="false"
    while true; do
        if [[ "$PROXY_DELETED" == "true" ]]; then break; fi
        clear
        echo -e "${CY}Managing Proxy: ${GR}${SELECTED_PROXY}${NC}"
        echo "----------------------------------------"
        echo -e "${BL}1)${NC} View Proxy Details"
        echo -e "${BL}2)${NC} Manage Proxy Service (Start/Stop/Logs)"
        echo -e "${BL}3)${NC} Show Proxy Links"
        echo -e "${BL}4)${RED} Delete Proxy${NC}"
        echo "----------------------------------------"; echo -e "${BL}0)${NC} Back to Proxy List"; echo ""
        read -p "Choose an action: " choice < /dev/tty
        case $choice in
            1) view_proxy_details ;; 2) manage_proxy_service ;;
            3) show_proxy_links ;; 4) delete_proxy; [[ "$PROXY_DELETED" == "true" ]] && break ;;
            0) break ;; *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Proxy Action Functions ---

create_new_proxy() {
    clear
    echo -e "${CY}--- Create New Proxy (Official C Version) ---${NC}"
    read -p "Enter a unique name for this proxy (e.g., pars-1): " PROXY_NAME < /dev/tty

    if [ -z "$PROXY_NAME" ]; then error "Proxy name cannot be empty."; press_enter_to_continue; return; fi
    if [ -d "${PROXY_BASE_DIR}/${PROXY_NAME}" ]; then error "A proxy with this name already exists!"; press_enter_to_continue; return; fi
    
    local proxy_dir="${PROXY_BASE_DIR}/${PROXY_NAME}"
    sudo mkdir -p "${proxy_dir}"

    read -p "Enter the PORT for this proxy (e.g., 443): " PORT < /dev/tty
    read -p "Enter a 32-char hex SECRET (or Enter for random): " SECRET < /dev/tty
    if [ -z "$SECRET" ]; then SECRET=$(head -c 16 /dev/urandom | xxd -ps); fi
    read -p "Enter your AD TAG from @MTProxybot (or Enter for none): " TAG < /dev/tty

    if ! [[ ${PORT} -gt 0 && ${PORT} -lt 65535 ]]; then error "Invalid port"; sudo rm -rf "$proxy_dir"; return; fi
    if ! [[ "$SECRET" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid secret"; sudo rm -rf "$proxy_dir"; return; fi
    
    echo "PORT=${PORT}
SECRET=${SECRET}
TAG=${TAG}" | sudo tee "${proxy_dir}/info.txt" > /dev/null

    if ! create_systemd_service "$PROXY_NAME"; then
        error "Failed to create systemd service."; sudo rm -rf "$proxy_dir"; press_enter_to_continue; return
    fi
    
    info "Starting the new proxy..."
    sudo systemctl start "mtproto-proxy-${PROXY_NAME}"
    sleep 2

    if systemctl is-active --quiet "mtproto-proxy-${PROXY_NAME}"; then
        info "Proxy '${PROXY_NAME}' created and started successfully! ✅"
    else
        error "Failed to start the proxy service. Check logs: sudo journalctl -u mtproto-proxy-${PROXY_NAME}"
    fi
    press_enter_to_continue
}

create_systemd_service() {
    local proxy_name=$1
    local service_path="/etc/systemd/system/mtproto-proxy-${proxy_name}.service"
    info "Creating systemd service file at ${service_path}"

    local proxy_dir="${PROXY_BASE_DIR}/${proxy_name}"
    source "${proxy_dir}/info.txt"
    local EXECUTABLE_WORKDIR="${SRC_PATH}/objs/bin"

    sudo bash -c "cat > ${service_path}" << EOL
[Unit]
Description=MTProxy (Official C) for ${proxy_name}
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=${EXECUTABLE_WORKDIR}
ExecStart=${PROXY_EXECUTABLE} -p 8888 -H ${PORT} -S ${SECRET} -P ${TAG} --aes-pwd proxy-secret proxy-multi.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable "mtproto-proxy-${proxy_name}"
    info "Service for ${proxy_name} created and enabled."
}

delete_proxy() {
    read -p "Are you sure you want to PERMANENTLY delete '${SELECTED_PROXY}'? [y/N] " confirm < /dev/tty
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        local service_name="mtproto-proxy-${SELECTED_PROXY}"
        info "Stopping and disabling service..."
        sudo systemctl stop "$service_name"
        sudo systemctl disable "$service_name"
        info "Removing service file..."
        sudo rm -f "/etc/systemd/system/${service_name}.service"
        sudo systemctl daemon-reload
        info "Removing proxy directory..."
        sudo rm -rf "${PROXY_BASE_DIR}/${SELECTED_PROXY}"
        info "Proxy '${SELECTED_PROXY}' has been deleted."
        PROXY_DELETED="true"
        press_enter_to_continue
    else
        info "Deletion cancelled."; press_enter_to_continue;
    fi
}

view_proxy_details() {
    clear; echo -e "${CY}--- Details for ${SELECTED_PROXY} ---${NC}";
    cat "${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"; press_enter_to_continue;
}

manage_proxy_service() {
    clear; echo -e "${CY}--- Manage Service for ${SELECTED_PROXY} ---${NC}";
    echo -e "${BL}1)${NC} Start\n${BL}2)${NC} Stop\n${BL}3)${NC} Restart\n${BL}4)${NC} View Status/Logs\n"
    read -p "Choose option (or Enter to cancel): " choice < /dev/tty
    local service_name="mtproto-proxy-${SELECTED_PROXY}"
    case $choice in
        1) sudo systemctl start "$service_name"; info "Starting...";;
        2) sudo systemctl stop "$service_name"; info "Stopping...";;
        3) sudo systemctl restart "$service_name"; info "Restarting...";;
        4) sudo journalctl -u "$service_name" -f --no-pager; return;;
        *) info "Cancelled."; press_enter_to_continue; return;;
    esac
    sleep 1; sudo systemctl status "$service_name" --no-pager; press_enter_to_continue;
}

show_proxy_links() {
    local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
    if [ ! -f "$info_file" ]; then error "Info file not found!"; press_enter_to_continue; return; fi
    source "$info_file"
    info "Detecting IP address..."
    local IP=$(curl -s -4 https://checkip.amazonaws.com)
    if [ -z "$IP" ]; then error "Could not detect IP."; press_enter_to_continue; return; fi
    info "Detected external IP is ${IP}"
    echo -e "\n--- ${CY}${SELECTED_PROXY}${NC} Connection Link ---"
    echo -e "${GR}Secure (DD):${NC}    https://t.me/proxy?server=${IP}&port=${PORT}&secret=dd${SECRET}"
    echo "-------------------------------------"; press_enter_to_continue;
}

# --- Main Execution Logic ---
main() {
    if [ "$EUID" -ne 0 ]; then error "Please run this script with sudo or as root."; exit 1; fi
    init_proxy_system
    check_and_compile_source

    while true; do
        show_main_menu
        read -p "Choose option [1-3]: " choice < /dev/tty
        case $choice in
            1) list_and_select_proxy ;; 2) create_new_proxy ;;
            3) echo "Goodbye!"; exit 0 ;; *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

main
