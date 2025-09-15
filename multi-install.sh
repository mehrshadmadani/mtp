#!/bin/bash
#
# MTProto Proxy Multi-Instance Installer (v4 - Final Correct ExecStart)
#

# --- Colors ---
RED='\033[0;31m'
GR='\033[0;32m'
NC='\033[0m'

# --- Helper Functions ---
info() {
    echo -e "${GR}INFO${NC}: $1"
}
error() {
    echo -e "${RED}ERROR${NC}: $1" 1>&2
    exit 1
}

# --- Main Logic ---
if [ "$EUID" -ne 0 ]; then error "Please run this script with sudo or as root."; fi
if [ -z "$1" ]; then
    echo "Usage: $0 <proxy_name>"
    echo "Example: $0 MyProxy1"
    exit 1
fi

set -e

PROXY_NAME="$1"
SERVICE_NAME="mtproto-proxy-${PROXY_NAME}"
INSTALL_DIR="/opt/mtp_proxy_${PROXY_NAME}"
USER_NAME="mtp-user-${PROXY_NAME}"
LOG_DIR="/var/log/${SERVICE_NAME}"
SRC_DIR="mtproto_proxy_source_temp"

info "Starting installation for proxy: ${PROXY_NAME}"

rm -rf "${SRC_DIR}" mtproto_proxy.tar.gz
info "Installing dependencies..."
apt-get update > /dev/null
apt-get install -y erlang-nox erlang-dev make sed diffutils tar curl > /dev/null
timedatectl set-ntp on
info "Downloading source code..."
curl -sL https://github.com/seriyps/mtproto_proxy/archive/master.tar.gz -o mtproto_proxy.tar.gz
tar -xaf mtproto_proxy.tar.gz
mv mtproto_proxy-master "${SRC_DIR}"
cd "${SRC_DIR}"

read -p "Enter port number for '${PROXY_NAME}': " PORT
read -p "Enter 32-char hex secret (or press Enter for random): " SECRET
if [ -z "$SECRET" ]; then SECRET=$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' \n'); fi
read -p "Enter your ad tag (or press Enter for none): " TAG
read -p "Enable Fake-TLS mode? (recommended) [Y/n] " yn_tls
TLS_DOMAIN="www.google.com"
if [[ ! "$yn_tls" =~ ^[nN]$ ]]; then
    read -p "Enter a Fake-TLS domain [${TLS_DOMAIN}]: " domain_input
    [[ -n "$domain_input" ]] && TLS_DOMAIN=$domain_input
fi

info "Generating configuration and compiling source..."
PROTO_ARG='{allowed_protocols, [mtp_fake_tls,mtp_secure]},'
ERL_TAG=${TAG:-""}
cat > config/prod-sys.config << EOL
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
       tag => <<"${ERL_TAG}">>}
    ]}
   ]},
 {lager, [{log_root, "${LOG_DIR}"}]}
].
EOL
make

info "Creating user and installing files manually..."
systemctl stop "${SERVICE_NAME}" > /dev/null 2>&1 || true
useradd --system --no-create-home --shell /bin/false "${USER_NAME}" || true
mkdir -p "${INSTALL_DIR}"
cp -r "_build/prod/rel/mtp_proxy/"* "${INSTALL_DIR}/"
mkdir -p "${LOG_DIR}"
chown -R "${USER_NAME}":"${USER_NAME}" "${LOG_DIR}"
chown -R "${USER_NAME}":"${USER_NAME}" "${INSTALL_DIR}"

info "Creating systemd service file..."
# --- THE FINAL FIX IS HERE: Using the full, correct ExecStart command ---
ERTS_DIR=$(find "${INSTALL_DIR}/erts-"* -maxdepth 0 -type d | head -n 1)
RELEASE_VSN=$(cat "${INSTALL_DIR}/releases/start_erl.data" | cut -d' ' -f2)
VM_ARGS_PATH="${INSTALL_DIR}/releases/${RELEASE_VSN}/vm.args"
SYS_CONFIG_PATH="${INSTALL_DIR}/releases/${RELEASE_VSN}/sys.config"

# Set custom vm.args
echo "-name ${PROXY_NAME}@127.0.0.1
-setcookie ${PROXY_NAME}_cookie" > "${VM_ARGS_PATH}"

cat > "${SERVICE_NAME}.service" << EOL
[Unit]
Description=MTProto proxy server for ${PROXY_NAME}
After=network.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
WorkingDirectory=${INSTALL_DIR}

ExecStart=${ERTS_DIR}/bin/erlexec -noinput +Bd \\
    -boot ${INSTALL_DIR}/releases/${RELEASE_VSN}/start \\
    -mode embedded \\
    -boot_var SYSTEM_LIB_DIR ${INSTALL_DIR}/lib \\
    -config ${SYS_CONFIG_PATH} \\
    -args_file ${VM_ARGS_PATH} \\
    -- foreground

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL
install -D "${SERVICE_NAME}.service" "/etc/systemd/system/${SERVICE_NAME}.service"

info "Enabling and starting service: ${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"
sleep 3

cd ..
rm -rf "${SRC_DIR}" mtproto_proxy.tar.gz

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "Proxy '${PROXY_NAME}' is successfully installed and running! ✅"
    IP=$(curl -s -4 https://checkip.amazonaws.com)
    echo "--- Your Proxy Link ---"
    echo "https://t.me/proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}$(echo -n ${TLS_DOMAIN} | xxd -p -c 256)"
    echo "-----------------------"
else
    error "Failed to start the proxy. Check logs with: journalctl -u ${SERVICE_NAME}"
fi
