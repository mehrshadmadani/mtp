#!/bin/bash
#
# MTProto Proxy Multi-Instance Manager v4.0 (Final)
# Manages multiple instances of mtproto-proxy from https://github.com/seriyps/mtproto_proxy
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

to_hex() {
    od -A n -t x1 -w128 | sed 's/ //g'
}

# --- Core Management Functions ---

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

# --- Menu Functions ---

show_main_menu() {
    clear
    echo -e "${CY}╔══════════════════════════════════════╗${NC}"
    echo -e "${CY}║     MTProto Proxy Manager v4.0       ║${NC}"
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
    sudo mkdir -p "${proxy_dir}"

    # --- MAJOR CHANGE: The section for copying the release is REMOVED ---
    # We will now use the central compiled source for all proxies.

    if ! do_build_config "${proxy_dir}"; then
        error "Configuration failed. Aborting proxy creation."; sudo rm -rf "$proxy_dir"; press_enter_to_continue; return
    fi

    # --- CHANGE: Create vm.args directly in the proxy directory ---
    echo "-name ${PROXY_NAME}@127.0.0.1
-setcookie ${PROXY_NAME}_cookie
+K true
+P 134217727
-env ERL_MAX_ETS_TABLES 4096" | sudo tee "${proxy_dir}/vm.args" > /dev/null

    if ! create_systemd_service "$PROXY_NAME"; then
        error "Failed to create systemd service."; sudo rm -rf "$proxy_dir"; press_enter_to_continue; return
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

create_systemd_service() {
    local proxy_name=$1
    local service_path="/etc/systemd/system/mtproto-proxy-${proxy_name}.service"
    info "Creating systemd service file at ${service_path}"

    local proxy_dir="${PROXY_BASE_DIR}/${proxy_name}"
    
    # --- MAJOR CHANGE: Point to the central compiled source, not a local copy ---
    local REL_DIR="${SRC_PATH}/_build/prod/rel/mtp_proxy"

    local ERTS_DIR=$(find "${REL_DIR}/erts-"* -maxdepth 0 -type d | head -n 1)
    if [ -z "$ERTS_DIR" ]; then
        error "Could not find Erlang runtime in the central source directory: ${REL_DIR}"; return 1
    fi

    local RELEASE_VSN=$(cat "${REL_DIR}/releases/start_erl.data" | cut -d' ' -f2)
    if [ -z "$RELEASE_VSN" ]; then
        error "Could not find release version in the central source directory"; return 1
    fi

    sudo bash -c "cat > ${service_path}" << EOL
[Unit]
Description=MTProto proxy server for ${proxy_name}
After=network.target

[Service]
Type=simple
WorkingDirectory=${proxy_dir}
Environment="BINDIR=${ERTS_DIR}/bin"
ExecStartPre=/bin/sh -c 'sleep \$((RANDOM %% 10 + 2))'
ExecStart=${ERTS_DIR}/bin/erlexec -noinput +Bd \\
    -boot ${REL_DIR}/releases/${RELEASE_VSN}/start \\
    -mode embedded \\
    -boot_var SYSTEM_LIB_DIR ${REL_DIR}/lib \\
    -config ${proxy_dir}/sys.config \\
    -args_file ${proxy_dir}/vm.args \\
    -- foreground
Restart=always
RestartSec=5

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
    
    local show_normal_links=true
    
    if [[ "$TLS_ONLY" == "y" ]]; then
        local HEX_TLS_SECRET="ee$(echo -n ${SECRET} | LC_ALL=C xxd -p -c 256)$(echo -n ${TLS_DOMAIN} | LC_ALL=C xxd -p -c 256)"
        echo -e "${GR}Fake-TLS:${NC}       ${URL_PREFIX}${HEX_TLS_SECRET}"
        [[ "$DD_ONLY" != "y" ]] && show_normal_links=false
    fi

    if [[ "$show_normal_links" == "true" ]]; then
        echo -e "${GR}Secure (DD):${NC}    ${URL_PREFIX}dd${SECRET}"
        echo -e "${GR}Normal:${NC}         ${URL_PREFIX}${SECRET}"
    fi
    
    echo "-------------------------------------"
    press_enter_to_continue
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
        info "Deletion cancelled."
        press_enter_to_continue
    fi
}

# --- Build and Config Functions ---

do_configure_os() {
    if [ -f "/etc/os-release" ]; then
        source /etc/os-release
    else
        error "Cannot detect OS. /etc/os-release not found."; return 1
    fi
    
    info "Detected OS is ${ID} ${VERSION_ID}. Installing dependencies..."
    case "${ID}" in
        ubuntu|debian)
            sudo apt-get update && sudo apt-get install -y erlang-nox erlang-dev make sed diffutils tar curl findutils;;
        centos)
            sudo yum install -y epel-release wget
            sudo yum install -y erlang erlang-devel make sed diffutils tar curl findutils;;
        *)
            error "Your OS ${ID} is not supported by this script."; return 1
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
    # --- MAJOR CHANGE: Config file is now created directly in the proxy's own directory ---
    local config_path="${proxy_dir}/sys.config"
    
    info "Interactively generating config-file for ${CY}${PROXY_NAME}${NC}"
    
    local PORT SECRET TAG DD_ONLY="n" TLS_ONLY="n" TLS_DOMAIN="" yn domain_input
    
    read -p "Enter port number (e.g., 443): " PORT < /dev/tty
    read -p "Enter 32-char hex secret (or press Enter to generate random): " SECRET < /dev/tty
    if [ -z "$SECRET" ]; then
        SECRET=$(head -c 16 /dev/urandom | to_hex)
        info "Using random secret: ${SECRET}"
    fi
    read -p "Enter your ad tag (or press Enter for none): " TAG < /dev/tty
    
    read -p "Enable dd-only mode? (recommended) [Y/n] " yn < /dev/tty
    if [[ ! "$yn" =~ ^[nN]$ ]]; then
        DD_ONLY="y"; info "Using dd-only mode"
    fi

    read -p "Enable Fake-TLS mode? (recommended) [Y/n] " yn < /dev/tty
    if [[ ! "$yn" =~ ^[nN]$ ]]; then
      TLS_ONLY="y"
      TLS_DOMAIN="www.google.com"
      read -p "Enter a Fake-TLS domain [${TLS_DOMAIN}]: " domain_input < /dev/tty
      [[ -n "$domain_input" ]] && TLS_DOMAIN=$domain_input
      info "Using '${TLS_DOMAIN}' for fake-TLS"
    fi

    if ! [[ ${PORT} -gt 0 && ${PORT} -lt 65535 ]]; then error "Invalid port"; return 1; fi
    if ! [[ "$SECRET" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid secret"; return 1; fi
    if ! [[ -z "$TAG" || "$TAG" =~ ^[[:xdigit:]]{32}$ ]]; then error "Invalid tag"; return 1; fi
    
    local PROTO_ARG=""
    if [ "${DD_ONLY}" == "y" ] && [ "${TLS_ONLY}" == "y" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_fake_tls,mtp_secure]},'
    elif [ "${DD_ONLY}" == "y" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_secure]},'
    elif [ "${TLS_ONLY}" == "y" ]; then
        PROTO_ARG='{allowed_protocols, [mtp_fake_tls]},'
    fi
    
    echo "PORT=${PORT}
SECRET=${SECRET}
TAG=${TAG}
DD_ONLY=${DD_ONLY}
TLS_ONLY=${TLS_ONLY}
TLS_DOMAIN=${TLS_DOMAIN}" | sudo tee "${proxy_dir}/info.txt" > /dev/null

    local ERL_SECRET=${SECRET:-"00000000000000000000000000000000"}
    local ERL_TAG=${TAG:-""}

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
       secret => <<"${ERL_SECRET}">>,
       tag => <<"${ERL_TAG}">>}
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
        read -p "Choose option [1-3]: " choice < /dev/tty
        case $choice in
            1) list_and_select_proxy ;;
            2) create_new_proxy ;;
            3) echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

main
