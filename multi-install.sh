#!/bin/bash
#
# MTProto Proxy Multi-Instance Installer
# Based on the original script, modified to support multiple instances.
#

# --- Colors ---
RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
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
if [ "$EUID" -ne 0 ]; then
    error "Please run this script with sudo or as root."
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <proxy_name>"
    echo "Example: $0 MyProxy1"
    exit 1
fi

PROXY_NAME="$1"
SERVICE_NAME="mtproto-proxy-${PROXY_NAME}"
INSTALL_DIR="/opt/mtp_proxy_${PROXY_NAME}"
USER_NAME="mtp-user-${PROXY_NAME}"
SRC_DIR="mtproto_proxy_source_${PROXY_NAME}"

info "Starting installation for proxy: ${PROXY_NAME}"

# --- 1. Cleanup previous source attempts ---
rm -rf "${SRC_DIR}" mtproto_proxy.tar.gz

# --- 2. Install Dependencies ---
info "Installing dependencies..."
apt-get update > /dev/null
apt-get install -y erlang-nox erlang-dev make sed diffutils tar curl > /dev/null
timedatectl set-ntp on

# --- 3. Get Source Code ---
info "Downloading source code..."
curl -L https://github.com/seriyps/mtproto_proxy/archive/master.tar.gz -o mtproto_proxy.tar.gz
tar -xaf mtproto_proxy.tar.gz
mv mtproto_proxy-master "${SRC_DIR}"
cd "${SRC_DIR}"

# --- 4. Get User Configuration ---
read -p "Enter port number for '${PROXY_NAME}': " PORT
read -p "Enter 32-char hex secret (or press Enter for random): " SECRET
if [ -z "$SECRET" ]; then
    SECRET=$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' \n')
fi
read -p "Enter your ad tag (or press Enter for none): " TAG
read -p "Enable Fake-TLS mode? (recommended) [Y/n] " yn_tls
TLS_DOMAIN="www.google.com"
if [[ ! "$yn_tls" =~ ^[nN]$ ]]; then
    read -p "Enter a Fake-TLS domain [${TLS_DOMAIN}]: " domain_input
    [[ -n "$domain_input" ]] && TLS_DOMAIN=$domain_input
fi

# --- 5. Generate Erlang Config ---
info "Generating configuration..."
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
 {lager, [{log_root, "/var/log/${SERVICE_NAME}"}]}
].
EOL

# --- 6. Modify the Makefile and Service file for multi-instance support ---
info "Customizing installation for '${PROXY_NAME}'..."
# Change install path in Makefile
sed -i "s|/opt/mtp_proxy|${INSTALL_DIR}|g" Makefile
# Change service name and user in the service template
sed -i "s|mtproto-proxy.service|${SERVICE_NAME}.service|g" Makefile
sed -i "s|Description=MTProto proxy server|Description=MTProto proxy server for ${PROXY_NAME}|g" config/mtproto-proxy.service
sed -i "s|User=mtproto-proxy|User=${USER_NAME}|g" config/mtproto-proxy.service
sed -i "s|/var/log/mtproto-proxy|/var/log/${SERVICE_NAME}|g" config/mtproto-proxy.service

# --- 7. Compile and Install ---
info "Compiling source code..."
make
info "Creating user '${USER_NAME}' and installing..."
useradd --system --no-create-home --shell /bin/false "${USER_NAME}" || true
make install

# --- 8. Start the service ---
info "Enabling and starting service: ${SERVICE_NAME}"
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"
sleep 3

# --- 9. Final Check and Cleanup ---
cd ..
rm -rf "${SRC_DIR}" mtproto_proxy.tar.gz

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "Proxy '${PROXY_NAME}' is successfully installed and running!"
    IP=$(curl -s -4 https://checkip.amazonaws.com)
    echo "--- Your Proxy Link ---"
    echo "https://t.me/proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}$(echo -n ${TLS_DOMAIN} | xxd -p -c 256)"
    echo "-----------------------"
else
    error "Failed to start the proxy. Check logs with: journalctl -u ${SERVICE_NAME}"
fi
