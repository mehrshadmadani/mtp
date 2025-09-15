#!/bin/bash
#
# MTProto Proxy Multi-Instance Manager v2.1
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
PROXY_EXECUTABLE="${SRC_PATH}/_build/prod/rel/mtp_proxy/bin/mtp_proxy"

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

# --- New Management Functions ---

init_proxy_system() {
    if [ ! -d "$PROXY_BASE_DIR" ]; then
        info "Creating proxy base directory at ${PROXY_BASE_DIR}..."
        sudo mkdir -p "$PROXY_BASE_DIR"
    fi
}

check_and_compile_source() {
    if [ ! -f "$PROXY_EXECUTABLE" ]; then
        info "Proxy source code not found or not compiled."
        info "Downloading and compiling for the first time..."
        
        # Clean up previous attempts if they exist
        rm -rf "$SRC_PATH" mtproto_proxy.tar.gz
        
        do_get_source
        if [ $? -ne 0 ]; then
            error "Failed to download source code. Aborting."
            exit 1
        fi
        
        cd "$SRC_PATH/"
        do_build
        if [ $? -ne 0 ]; then
            error "Failed to compile source code. Check if 'make' and 'erlang' are installed correctly. Aborting."
            exit 1
        fi
        cd "$WORKDIR"

        if [ ! -f "$PROXY_EXECUTABLE" ]; then
            error "Compilation finished, but the executable file was not found. Aborting."
            exit 1
        fi
        info "Source code compiled successfully."
    fi
}

get_proxy_list() {
    ls -d ${PROXY_BASE_DIR}/*/ 2>/dev/null | xargs -n 1 basename 2>/dev/null || echo ""
}

show_main_menu() {
    clear
    echo -e "${CY}╔══════════════════════════════════════╗${NC}"
    echo -e "${CY}║     MTProto Proxy Manager v2.1       ║${NC}"
    echo -e "${CY}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BL}1)${NC} List All Proxies"
    echo -e "${BL}2)${NC} Create New Proxy"
    echo -e "${BL}3)${NC} View Proxy Details"
    echo -e "${BL}4)${NC} Manage Proxy Service (Start/Stop/Logs)"
    echo -e "${BL}5)${NC} Show Proxy Links"
    echo -e "${BL}6)${NC} Delete Proxy"
    echo -e "${BL}7)${NC} Exit"
    echo ""
}

list_and_select_proxy() {
    while true; do
        clear
        echo -e "${CY}═════════ Proxy Management ═════════${NC}"
        echo ""

        # Get the list of proxies into an array
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

        if [[ "$choice" == "0" ]]; then
            break # Exit the while loop and return to the main menu
        fi

        # Validate the selection
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#proxies[@]}" ]; then
            SELECTED_PROXY="${proxies[$((choice-1))]}"
            # In the next step, we will call the management menu for the selected proxy
            clear
            echo -e "You selected: ${GR}${SELECTED_PROXY}${NC}"
            echo "The management menu for this proxy will be implemented in the next step."
            press_enter_to_continue
        else
            echo -e "${RED}Invalid selection!${NC}"
            sleep 1
        fi
    done
}

select_proxy() {
    clear
    local proxies=$(get_proxy_list)
    if [ -z "$proxies" ]; then
        error "No proxies available!"
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
    read -p "Enter number (or press Enter to cancel): " selection < /dev/tty

    if [[ -z "$selection" ]]; then
        return 1
    fi

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#proxy_array[@]}" ]; then
        SELECTED_PROXY="${proxy_array[$((selection-1))]}"
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
ExecStart=${PROXY_EXECUTABLE} --config=${PROXY_BASE_DIR}/${proxy_name}/prod-sys.config --args=${PROXY_BASE_DIR}/${proxy_name}/prod-vm.args
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
    read -p "Enter a unique name for this proxy (e.g., MyProxy1): " PROXY_NAME < /dev/tty

    if [ -z "$PROXY_NAME" ]; then
        error "Proxy name cannot be empty."
        press_enter_to_continue
        return
    fi

    if [ -d "${PROXY_BASE_DIR}/${PROXY_NAME}" ]; then
        error "A proxy with this name already exists!"
        press_enter_to_continue
        return
    fi
    
    local proxy_dir="${PROXY_BASE_DIR}/${PROXY_NAME}"
    sudo mkdir -p "${proxy_dir}"

    # Generate config and info file
    if ! do_build_config "${proxy_dir}"; then
        error "Configuration failed. Aborting proxy creation."
        sudo rm -rf "$proxy_dir" # Clean up failed attempt
        press_enter_to_continue
        return
    fi

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

    press_enter_to_continue
}

delete_proxy() {
    if select_proxy; then
        read -p "Are you sure you want to PERMANENTLY delete '${SELECTED_PROXY}'? [y/N] " confirm < /dev/tty
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
        press_enter_to_continue
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
        press_enter_to_continue
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
        read -p "Choose option: " choice < /dev/tty

        local service_name="mtproto-proxy-${SELECTED_PROXY}"
        case $choice in
            1) sudo systemctl start "$service_name"; info "Starting...";;
            2) sudo systemctl stop "$service_name"; info "Stopping...";;
            3) sudo systemctl restart "$service_name"; info "Restarting...";;
            4) sudo journalctl -u "$service_name" -f --no-pager; return;; # No need to press enter after logs
            *) info "Cancelled."; press_enter_to_continue; return;;
        esac
        sleep 1
        sudo systemctl status "$service_name" --no-pager
        press_enter_to_continue
    fi
}

show_proxy_links() {
    if select_proxy; then
        local info_file="${PROXY_BASE_DIR}/${SELECTED_PROXY}/info.txt"
        if [ -f "$info_file" ]; then
            source "$info_file"
            do_print_links # This now uses the sourced variables
        else
            error "Could not find info file for ${SELECTED_PROXY}!"
        fi
        press_enter_to_continue
    fi
}


# --- Original Script Functions (modified for modularity) ---

do_configure_os() {
    if [ -f "/etc/os-release" ]; then
        source /etc/os-release
    else
        error "Cannot detect OS. /etc/os-release not found."
        return 1
    fi
    
    info "Detected OS is ${ID} ${VERSION_ID}. Installing dependencies..."
    case "${ID}" in
        ubuntu|debian)
            sudo apt-get update && sudo apt-get install -y erlang-nox erlang-dev make sed diffutils tar curl;;
        centos)
            sudo yum install -y epel-release wget
            sudo yum install -y erlang erlang-devel make sed diffutils tar curl;;
        *)
            error "Your OS ${ID} is not supported by this script."
            return 1
    esac
    sudo timedatectl set-ntp on
}

do_get_source() {
    info "Downloading proxy source code to ${SRC_PATH}"
    curl -L https://github.com/seriyps/mtproto_proxy/archive/master.tar.gz -o mtproto_proxy.tar.gz || return 1
    tar -xaf mtproto_proxy.tar.gz || return 1
    mv -T mtproto_proxy-master "$SRC_PATH" || return 1
    rm mtproto_proxy.tar.gz
}

do_build() {
    info "Compiling source code..."
    make || return 1
}

do_build_config() {
    local proxy_dir=$1
    local config_path="${proxy_dir}/prod-sys.config"
    info "Interactively generating config-file for ${CY}${PROXY_NAME}${NC}"
    
    # Declare local variables
    local PORT SECRET TAG TLS_ONLY="n" TLS_DOMAIN="" yn domain_input
    
    read -p "Enter port number (e.g., 443): " PORT < /dev/tty
    read -p "Enter 32-char hex secret (or press Enter to generate random): " SECRET < /dev/tty
    if [ -z "$SECRET" ]; then
        SECRET=$(head -c 16 /dev/urandom | to_hex)
        info "Using random secret: ${SECRET}"
    fi
    read -p "Enter your ad tag (or press Enter for none): " TAG < /dev/tty
    
    read -p "Enable Fake-TLS mode? (recommended) [Y/n] " yn < /dev/tty
    if [[ ! "$yn" =~ ^[nN]$ ]]; then
      TLS_ONLY="y"
      TLS_DOMAIN="www.google.com"
      read -p "Enter a VALID Fake-TLS domain [${TLS_DOMAIN}]: " domain_input < /dev/tty
      [[ -n "$domain_input" ]] && TLS_DOMAIN=$domain_input
    fi

    # --- VALIDATION (BUG IS FIXED HERE with a more robust method) ---
    local domain_pattern='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$'
    if ! [[ ${PORT} -gt 0 && ${PORT} -lt 65535 ]]; then error "Invalid port"; return 1; fi
    if ! [[ "$SECRET" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid secret"; return 1; fi
    if ! [[ -z "$TAG" || "$TAG" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid tag"; return 1; fi
    if [[ "$TLS_ONLY" == "y" && ! "$TLS_DOMAIN" =~ $domain_pattern ]]; then error "Invalid Fake-TLS domain: ${TLS_DOMAIN}"; return 1; fi

    local PROTO_ARG='{allowed_protocols, [mtp_secure]},'
    if [ "$TLS_ONLY" == "y" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_fake_tls,mtp_secure]},'
    fi
    
    echo "PORT=${PORT}
SECRET=${SECRET}
TAG=${TAG}
TLS_ONLY=${TLS_ONLY}
TLS_DOMAIN=${TLS_DOMAIN}" | sudo tee "${proxy_dir}/info.txt" > /dev/null

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
  [{log_root, "${proxy_dir}/logs"},
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
    info "Detecting IP address..."
    local IP=$(curl -s -4 -m 10 https://checkip.amazonaws.com || curl -s -4 -m 10 https://api.ipify.org)
    if [ -z "$IP" ]; then
        error "Could not detect external IP address."
        return
    fi
    info "Detected external IP is ${IP}"

    local URL_PREFIX="https://t.me/proxy?server=${IP}&port=${PORT}&secret="

    echo "--- ${CY}${SELECTED_PROXY}${NC} Connection Links ---"
    # Always show the DD link
    echo -e "${GR}Secure (DD):${NC} ${URL_PREFIX}dd${SECRET}"

    if [[ "$TLS_ONLY" == "y" ]]; then
        local HEX_TLS_SECRET="ee$(echo -n ${SECRET} | LC_ALL=C xxd -p -c 256)$(echo -n ${TLS_DOMAIN} | LC_ALL=C xxd -p -c 256)"
        echo -e "${GR}Fake-TLS:${NC}    ${URL_PREFIX}${HEX_TLS_SECRET}"
    fi
    echo "-------------------------------------"
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
        read -p "Choose option [1-7]: " choice < /dev/tty
        case $choice in
            1) list_and_select_proxy ;;
            2) create_new_proxy ;;
            3) view_proxy_details ;;
            4) manage_proxy_service ;;
            5) show_proxy_links ;;
            6) delete_proxy ;;
            7) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

main
