#!/bin/bash
#
# MTProto Proxy Manager v8.1 (Official Telegram Version + ARM Patch)
# Manages multiple instances of the official mtproto-proxy from https://github.com/TelegramMessenger/MTProxy
#

# --- Colors ---
RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
BL='\033[0;34m'
CY='\033[0;36m'
NC='\033[0;m'
PROXY_DELETED="false"

# --- Global Variables ---
WORKDIR=$(pwd)
# --- CHANGED: Switched to official Telegram proxy source ---
SRC_DIR_NAME="MTProxy"
SRC_PATH="${WORKDIR}/${SRC_DIR_NAME}"
PROXY_EXECUTABLE="${SRC_PATH}/objs/bin/mtproto-proxy"

# --- NEW: Common directory for shared Telegram configs ---
SHARED_CONFIG_DIR="/opt/mtproxy-shared"
TELEGRAM_SECRET="${SHARED_CONFIG_DIR}/proxy-secret"
TELEGRAM_CONFIG="${SHARED_CONFIG_DIR}/proxy-multi.conf"

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
}

press_enter_to_continue() {
    echo ""
    read -p "Press Enter to continue..." < /dev/tty
}

# --- Core Management Functions ---

init_proxy_system() {
    if [ ! -d "$PROXY_BASE_DIR" ]; then
        info "Creating proxy base directory at ${PROXY_BASE_DIR}..."
        sudo mkdir -p "$PROXY_BASE_DIR"
    fi
    # --- NEW: Create shared config directory ---
    if [ ! -d "$SHARED_CONFIG_DIR" ]; then
        info "Creating shared config directory at ${SHARED_CONFIG_DIR}..."
        sudo mkdir -p "$SHARED_CONFIG_DIR"
    fi
}

# --- CHANGED: This function now downloads and compiles the OFFICIAL Telegram proxy ---
check_and_compile_source() {
    if [ ! -f "$PROXY_EXECUTABLE" ]; then
        info "Official MTProxy source not found or not compiled."
        info "Cloning and compiling for the first time..."
        
        # Clean up previous attempts
        rm -rf "$SRC_PATH"
        
        # 1. Clone the repository
        info "Cloning official MTProxy repository..."
        git clone https://github.com/TelegramMessenger/MTProxy.git "$SRC_PATH"
        if [ $? -ne 0 ]; then
            error "Failed to clone the repository. Aborting."
            exit 1
        fi
        
        # 2. Compile the source
        cd "$SRC_PATH/"

        # --- NEW FIX FOR ARM ARCHITECTURE ---
        info "Applying patch for compatibility with ARM and other architectures..."
        sed -i 's/-mpclmul -march=core2 -mfpmath=sse -mssse3//g' Makefile
        # --- END OF FIX ---

        info "Compiling source code..."
        make
        if [ $? -ne 0 ]; then
            error "Failed to compile. Make sure 'build-essential', 'libssl-dev', 'zlib1g-dev' and 'git' are installed. Aborting."
            exit 1
        fi
        cd "$WORKDIR"

        if [ ! -f "$PROXY_EXECUTABLE" ]; then
            error "Compilation finished, but the executable was not found. Aborting."
            exit 1
        fi
        info "Source code compiled successfully."
    fi
    
    # --- NEW: Download shared secrets/configs if they don't exist ---
    if [ ! -f "$TELEGRAM_SECRET" ]; then
        info "Downloading Telegram proxy secret for the first time..."
        if ! sudo curl -s https://core.telegram.org/getProxySecret -o "$TELEGRAM_SECRET"; then
            error "Could not download proxy secret. The proxy will not work."
        else
            info "Proxy secret saved to ${TELEGRAM_SECRET}"
        fi
    fi
    
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        info "Downloading Telegram proxy config for the first time..."
        if ! sudo curl -s https://core.telegram.org/getProxyConfig -o "$TELEGRAM_CONFIG"; then
            error "Could not download proxy config. The proxy will not work."
        else
            info "Proxy config saved to ${TELEGRAM_CONFIG}"
        fi
    fi
}

get_proxy_list() {
    ls -d ${PROXY_BASE_DIR}/*/ 2>/dev/null | xargs -n 1 basename 2>/dev/null || echo ""
}

# --- Menu Functions (Mostly unchanged) ---

show_main_menu() {
    clear
    echo -e "${CY}╔══════════════════════════════════════╗${NC}"
    echo -e "${CY}║   Official MTProto Proxy Manager v8.1  ║${NC}"
    echo -e "${CY}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BL}1)${NC} Manage Existing Proxies"
    echo -e "${BL}2)${NC} Create New Proxy"
    echo ""
    echo -e "${BL}3)${NC} Update Telegram Configs"
    echo ""
    echo -e "${BL}4)${NC} Exit"
    echo ""
}

list_and_select_proxy() {
    while true; do
        clear
        echo -e "${CY}═════════ Proxy Management ═════════${NC}"
        echo ""
        local proxies=($(get_proxy_list))

        if [ ${#proxies[@]} -eq 0 ]; then
            echo -e "${YE}No proxies found!${NC}"
            echo ""
            echo -e "${BL}0)${NC} Back to Main Menu"
        else
            local counter=1
            for proxy in "${proxies[@]}"; do
                local port_info="N/A"
                if [ -f "${PROXY_BASE_DIR}/${proxy}/info.txt" ]; then
                    port_info=$(grep "^PORT=" "${PROXY_BASE_DIR}/${proxy}/info.txt" | cut -d'=' -f2)
                fi
                local status="${RED}[Stopped]${NC}"
                if systemctl is-active --quiet "mtproto-proxy-${proxy}"; then
                    status="${GR}[Running]${NC}"
                fi
                echo -e "${BL}${counter})${NC} ${proxy} (Port: ${port_info}) ${status}"
                counter=$((counter + 1))
            done
            echo "----------------------------------------"
            echo -e "${BL}0)${NC} Back to Main Menu"
        fi

        echo ""
        read -p "Select a proxy to manage, or 0 to exit: " choice < /dev/tty
        if [[ "$choice" == "0" ]]; then break; fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#proxies[@]}" ]; then
            SELECTED_PROXY="${proxies[$((choice-1))]}"
            show_proxy_submenu
        else
            echo -e "${RED}Invalid selection!${NC}"; sleep 1
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
        echo "----------------------------------------"
        echo -e "${BL}0)${NC} Back to Proxy List"
        echo ""
        read -p "Choose an action: " choice < /dev/tty
        case $choice in
            1) view_proxy_details ;;
            2) manage_proxy_service ;;
            3) show_proxy_links ;;
            4) delete_proxy; [[ "$PROXY_DELETED" == "true" ]] && break ;;
            0) break ;;
            *) echo -e "${RED}Invalid selection!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Proxy Action Functions ---

create_new_proxy() {
    clear
    echo -e "${CY}--- Create New Proxy ---${NC}"
    read -p "Enter a unique name for this proxy (e.g., MyProxy1): " PROXY_NAME < /dev/tty

    if [ -z "$PROXY_NAME" ]; then
        error "Proxy name cannot be empty."; press_enter_to_continue; return
    fi

    if [ -d "${PROXY_BASE_DIR}/${PROXY_NAME}" ]; then
        error "A proxy with this name already exists!"; press_enter_to_continue; return
    fi
    
    local proxy_dir="${PROXY_BASE_DIR}/${PROXY_NAME}"
    local proxy_user="mtp-${PROXY_NAME}"

    # Create a dedicated system user
    info "Creating a dedicated user: ${proxy_user}"
    sudo useradd --system --no-create-home --shell /bin/false "${proxy_user}"
    if [ $? -ne 0 ]; then
        error "Failed to create user '${proxy_user}'. Aborting."; press_enter_to_continue; return
    fi

    sudo mkdir -p "${proxy_dir}"

    # Generate config file (info.txt)
    if ! generate_proxy_config "${proxy_dir}"; then
        error "Configuration failed. Aborting."; sudo userdel "${proxy_user}"; sudo rm -rf "${proxy_dir}"; press_enter_to_continue; return
    fi

    # Set correct ownership
    info "Setting file ownership for user ${proxy_user}..."
    sudo chown -R "${proxy_user}":"${proxy_user}" "${proxy_dir}"

    # Create the systemd service
    if ! create_systemd_service "$PROXY_NAME"; then
        error "Failed to create systemd service."; sudo userdel "${proxy_user}"; sudo rm -rf "${proxy_dir}"; press_enter_to_continue; return
    fi
    
    info "Starting the new proxy..."
    sudo systemctl start "mtproto-proxy-${PROXY_NAME}"
    sleep 2

    if systemctl is-active --quiet "mtproto-proxy-${PROXY_NAME}"; then
        info "Proxy '${PROXY_NAME}' created and started successfully!"
    else
        error "Failed to start the proxy service. Check logs with: sudo journalctl -u mtproto-proxy-${PROXY_NAME}"
    fi

    press_enter_to_continue
}

# --- REWRITTEN: Creates a systemd service for the OFFICIAL proxy ---
create_systemd_service() {
    local proxy_name=$1
    local service_path="/etc/systemd/system/mtproto-proxy-${proxy_name}.service"
    info "Creating systemd service file at ${service_path}"

    local proxy_dir="${PROXY_BASE_DIR}/${proxy_name}"
    local proxy_user="mtp-${proxy_name}"
    
    # Load variables from the proxy's info file
    source "${proxy_dir}/info.txt"
    
    local TAG_ARG=""
    if [ ! -z "$TAG" ]; then
        TAG_ARG="-P ${TAG}"
    fi

    local WORKER_ARG="-M 1" # Default to 1 worker, can be increased for powerful servers

    sudo bash -c "cat > ${service_path}" << EOL
[Unit]
Description=Official MTProto proxy server for ${proxy_name}
After=network.target

[Service]
Type=simple
User=${proxy_user}
Group=${proxy_user}
WorkingDirectory=${proxy_dir}

ExecStart=${PROXY_EXECUTABLE} \\
    -u ${proxy_user} \\
    -p ${STATS_PORT} \\
    -H ${PORT} \\
    -S ${SECRET} \\
    --aes-pwd ${TELEGRAM_SECRET} \\
    ${TELEGRAM_CONFIG} \\
    ${TAG_ARG} \\
    ${WORKER_ARG}

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable "mtproto-proxy-${proxy_name}"
    info "Service for ${proxy_name} created and enabled."
}

view_proxy_details() {
    clear
    echo -e "${CY}--- Details for ${SELECTED_PROXY} ---${NC}"
    local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
    if [ -f "$info_file" ]; then
        cat "$info_file"
        echo ""
        info "Stats available at: http://127.0.0.1:$(grep "^STATS_PORT=" "$info_file" | cut -d'=' -f2)/stats"
    else
        error "Info file not found!"
    fi
    press_enter_to_continue
}

manage_proxy_service() {
    clear
    echo -e "${CY}--- Manage Service for ${SELECTED_PROXY} ---${NC}"
    echo -e "${BL}1)${NC} Start"
    echo -e "${BL}2)${NC} Stop"
    echo -e "${BL}3)${NC} Restart"
    echo -e "${BL}4)${NC} View Status/Logs"
    echo ""
    read -p "Choose option (or Enter to cancel): " choice < /dev/tty

    local service_name="mtproto-proxy-${SELECTED_PROXY}"
    case $choice in
        1) sudo systemctl start "$service_name"; info "Starting...";;
        2) sudo systemctl stop "$service_name"; info "Stopping...";;
        3) sudo systemctl restart "$service_name"; info "Restarting...";;
        4) sudo journalctl -u "$service_name" -f --no-pager; return;;
        *) info "Cancelled."; press_enter_to_continue; return;;
    esac
    sleep 1
    sudo systemctl status "$service_name" --no-pager
    press_enter_to_continue
}

# --- UPDATED: Simplified link generation for the official proxy ---
show_proxy_links() {
    local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
    if [ ! -f "$info_file" ]; then
        error "Could not find info file for ${SELECTED_PROXY}!"; press_enter_to_continue; return
    fi
    source "$info_file"
    
    info "Detecting IP address..."
    local IP=$(curl -s -4 -m 10 https://checkip.amazonaws.com || curl -s -4 -m 10 https://api.ipify.org)
    if [ -z "$IP" ]; then
        error "Could not detect external IP address."; press_enter_to_continue; return
    fi
    info "Detected external IP is ${IP}"

    local URL_PREFIX="https://t.me/proxy?server=${IP}&port=${PORT}&secret="

    echo -e "\n--- ${CY}${SELECTED_PROXY}${NC} Connection Links ---"
    
    echo -e "${GR}Secure (DD):${NC}    ${URL_PREFIX}dd${SECRET}"
    echo -e "${GR}Normal:${NC}         ${URL_PREFIX}${SECRET}"
    
    echo "-------------------------------------"
    press_enter_to_continue
}

delete_proxy() {
    read -p "Are you sure you want to PERMANENTLY delete '${SELECTED_PROXY}'? [y/N] " confirm < /dev/tty
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        local service_name="mtproto-proxy-${SELECTED_PROXY}"
        local proxy_user="mtp-${SELECTED_PROXY}"

        info "Stopping and disabling service..."
        sudo systemctl stop "$service_name"
        sudo systemctl disable "$service_name"
        info "Removing service file..."
        sudo rm -f "/etc/systemd/system/${service_name}.service"
        sudo systemctl daemon-reload
        info "Removing proxy directory..."
        sudo rm -rf "${PROXY_BASE_DIR}/${SELECTED_PROXY}"
        
        info "Deleting user '${proxy_user}'..."
        sudo userdel "${proxy_user}"

        info "Proxy '${SELECTED_PROXY}' has been deleted."
        PROXY_DELETED="true"
        press_enter_to_continue
    else
        info "Deletion cancelled."
        press_enter_to_continue
    fi
}

# --- Build and Config Functions ---

# --- REWRITTEN: Installs dependencies for the OFFICIAL proxy ---
do_configure_os() {
    if [ -f "/etc/os-release" ]; then
        source /etc/os-release
    else
        error "Cannot detect OS. /etc/os-release not found."; return 1
    fi
    
    info "Detected OS is ${ID} ${VERSION_ID}. Installing dependencies..."
    case "${ID}" in
        ubuntu|debian)
            sudo apt-get update && sudo apt-get install -y git curl build-essential libssl-dev zlib1g-dev make;;
        centos|rhel)
            sudo yum install -y epel-release wget
            sudo yum install -y openssl-devel zlib-devel make git curl
            sudo yum groupinstall -y "Development Tools";;
        *)
            error "Your OS ${ID} is not supported by this script."; return 1
    esac
    if [ $? -ne 0 ]; then
        return 1
    fi
    sudo timedatectl set-ntp on
}

# --- NEW: Function to update shared configs ---
update_telegram_configs() {
    info "Updating Telegram server configurations..."
    if ! sudo curl -s https://core.telegram.org/getProxyConfig -o "$TELEGRAM_CONFIG"; then
        warn "Could not update Telegram server configurations."
    else
        info "Telegram configurations updated successfully."
        info "Restarting all running proxies to apply changes..."
        local proxies=($(get_proxy_list))
        for proxy in "${proxies[@]}"; do
            if systemctl is-active --quiet "mtproto-proxy-${proxy}"; then
                sudo systemctl restart "mtproto-proxy-${proxy}"
                info "Restarted ${proxy}."
            fi
        done
    fi
    press_enter_to_continue
}


# --- REWRITTEN: Generates a simple info.txt file, not an Erlang config ---
generate_proxy_config() {
    local proxy_dir=$1
    local info_path="${proxy_dir}/info.txt"
    
    info "Interactively generating config for ${CY}${PROXY_NAME}${NC}"
    
    local PORT SECRET TAG
    
    read -p "Enter port number (e.g., 443): " PORT < /dev/tty
    read -p "Enter 32-char hex secret (or press Enter to generate random): " SECRET < /dev/tty
    if [ -z "$SECRET" ]; then
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
        info "Using random secret: ${SECRET}"
    fi
    read -p "Enter your ad tag (optional, from @MTProxybot): " TAG < /dev/tty
    
    if ! [[ ${PORT} -gt 0 && ${PORT} -lt 65535 ]]; then error "Invalid port"; return 1; fi
    if ! [[ "$SECRET" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid secret"; return 1; fi
    if ! [[ -z "$TAG" || "$TAG" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid tag"; return 1; fi
    
    # --- NEW: Assign a unique stats port for this proxy ---
    local STATS_PORT=8888
    while lsof -i :${STATS_PORT} > /dev/null; do
        STATS_PORT=$((STATS_PORT + 1))
    done
    info "Assigning local stats port: ${STATS_PORT}"

    echo "PORT=${PORT}
SECRET=${SECRET}
TAG=${TAG}
STATS_PORT=${STATS_PORT}" | sudo tee "${info_path}" > /dev/null

    info "Config generated successfully."
    return 0
}


# --- Main Execution Logic ---
main() {
    if [ "$EUID" -ne 0 ]; then
      error "Please run this script with sudo or as root."
      exit 1
    fi

    init_proxy_system
    if ! do_configure_os; then
        error "Failed to install dependencies. Aborting."
        exit 1
    fi
    
    check_and_compile_source

    while true; do
        show_main_menu
        read -p "Choose option [1-4]: " choice < /dev/tty
        case $choice in
            1) list_and_select_proxy ;;
            2) create_new_proxy ;;
            3) update_telegram_configs ;;
            4) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

main
