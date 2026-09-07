#!/usr/bin/env bash

# ============================================================
#  Cloudflare + Apache HTTPS Site Manager
#  Version 1.0
#  By Md. Forhad Parvez
# ============================================================

set -u

APP_NAME="Cloudflare + Apache HTTPS Site Manager"
APP_VERSION="1.0"
APP_AUTHOR="Md. Forhad Parvez"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ------------------------------------------------------------
# Global configuration
# ------------------------------------------------------------

APACHE_BIN=""
APACHE_SERVICE=""
APACHE_MODE=""
APACHE_CONF_DIR=""
SITES_AVAILABLE=""
SITES_ENABLED=""

CERT_BASE="/etc/ssl/cloudflare-origin"
BACKUP_BASE="/root/cfsite-backups"

# ------------------------------------------------------------
# UI
# ------------------------------------------------------------

banner() {
    clear

    echo -e "${CYAN}"
    cat <<'EOF'
   _____ _                 _  __ _                 
  / ____| |               | |/ _| |                
 | |    | | ___  _   _  __| | |_| | __ _ _ __ ___ 
 | |    | |/ _ \| | | |/ _` |  _| |/ _` | '__/ _ \
 | |____| | (_) | |_| | (_| | | | | (_| | | |  __/
  \_____|_|\___/ \__,_|\__,_|_| |_|\__,_|_|  \___|

      Apache HTTPS Site Manager
EOF
    echo -e "${NC}"
    echo -e "        ${WHITE}Version ${APP_VERSION}${NC}  •  ${MAGENTA}By ${APP_AUTHOR}${NC}"
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
    echo
}

section() {
    echo
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERR ]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

pause() {
    echo
    read -r -p "Press Enter to continue..."
}

confirm() {
    local prompt="${1:-Continue?}"
    local answer=""

    read -r -p "$prompt [y/N]: " answer

    [[ "$answer" =~ ^[Yy]$ ]]
}

trim() {
    local value="$*"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "Please run this script as root: sudo $0"
    fi
}

# ------------------------------------------------------------
# Required tools
# ------------------------------------------------------------

check_dependencies() {
    local missing=()

    for cmd in openssl grep awk sed sha256sum systemctl find; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        error "Missing required commands:"
        printf '  - %s\n' "${missing[@]}"
        exit 1
    fi
}

# ------------------------------------------------------------
# Apache detection
# ------------------------------------------------------------

detect_apache() {

    if command -v apache2ctl >/dev/null 2>&1; then

        APACHE_BIN="apache2ctl"
        APACHE_SERVICE="apache2"
        APACHE_MODE="debian"
        APACHE_CONF_DIR="/etc/apache2"
        SITES_AVAILABLE="/etc/apache2/sites-available"
        SITES_ENABLED="/etc/apache2/sites-enabled"

    elif command -v apachectl >/dev/null 2>&1 && [[ -d /etc/httpd ]]; then

        APACHE_BIN="apachectl"
        APACHE_SERVICE="httpd"
        APACHE_MODE="rhel"
        APACHE_CONF_DIR="/etc/httpd"
        SITES_AVAILABLE="/etc/httpd/conf.d"
        SITES_ENABLED="/etc/httpd/conf.d"

    elif command -v httpd >/dev/null 2>&1 && [[ -d /etc/httpd ]]; then

        APACHE_BIN="httpd"
        APACHE_SERVICE="httpd"
        APACHE_MODE="rhel"
        APACHE_CONF_DIR="/etc/httpd"
        SITES_AVAILABLE="/etc/httpd/conf.d"
        SITES_ENABLED="/etc/httpd/conf.d"

    else
        die "Apache could not be detected."
    fi

    mkdir -p "$SITES_AVAILABLE"
    mkdir -p "$CERT_BASE"
    mkdir -p "$BACKUP_BASE"

    chmod 700 "$CERT_BASE"
    chmod 700 "$BACKUP_BASE"
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

validate_domain() {
    local domain="$1"

    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

safe_document_root() {
    local path="$1"

    case "$path" in
        /|/etc|/usr|/var|/var/www|/home|/root|/srv|/opt)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# ------------------------------------------------------------
# Apache helpers
# ------------------------------------------------------------

apache_test() {
    "$APACHE_BIN" configtest
}

apache_reload() {
    systemctl reload "$APACHE_SERVICE"
}

enable_required_modules() {

    if [[ "$APACHE_MODE" == "debian" ]]; then
        a2enmod ssl >/dev/null 2>&1 || true
        a2enmod rewrite >/dev/null 2>&1 || true
        a2enmod headers >/dev/null 2>&1 || true
    fi
}

enable_site() {
    local config="$1"

    if [[ "$APACHE_MODE" == "debian" ]]; then
        a2ensite "$(basename "$config")" >/dev/null
    fi
}

disable_site() {
    local config="$1"

    if [[ "$APACHE_MODE" == "debian" ]]; then
        a2dissite "$(basename "$config")" >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------
# Config parsing
# ------------------------------------------------------------

get_site_configs() {

    find "$SITES_AVAILABLE" \
        -maxdepth 1 \
        -type f \
        -name '*.conf' \
        2>/dev/null |
        sort
}

config_servername() {
    local file="$1"

    awk '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*ServerName[[:space:]]+/ {
            print $2
            exit
        }
    ' "$file"
}

config_documentroot() {
    local file="$1"

    awk '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*DocumentRoot[[:space:]]+/ {
            line=$0
            sub(/^[[:space:]]*DocumentRoot[[:space:]]+/, "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$file"
}

config_certfile() {
    local file="$1"

    awk '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*SSLCertificateFile[[:space:]]+/ {
            line=$0
            sub(/^[[:space:]]*SSLCertificateFile[[:space:]]+/, "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$file"
}

config_keyfile() {
    local file="$1"

    awk '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*SSLCertificateKeyFile[[:space:]]+/ {
            line=$0
            sub(/^[[:space:]]*SSLCertificateKeyFile[[:space:]]+/, "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$file"
}

find_domain_config() {
    local domain="$1"
    local escaped_domain
    local file

    escaped_domain="${domain//./\\.}"

    while IFS= read -r file; do

        if grep -Eiq \
            "^[[:space:]]*(ServerName|ServerAlias)[[:space:]].*${escaped_domain}([[:space:]]|$)" \
            "$file"; then

            echo "$file"
            return 0
        fi

    done < <(get_site_configs)

    return 1
}

# ------------------------------------------------------------
# Certificate handling
# ------------------------------------------------------------

validate_certificate_pair() {

    local cert="$1"
    local key="$2"

    info "Validating certificate..."

    if ! openssl x509 \
        -in "$cert" \
        -noout \
        >/dev/null 2>&1; then

        error "Invalid Origin Certificate."
        return 1
    fi

    info "Validating private key..."

    if ! openssl pkey \
        -in "$key" \
        -noout \
        >/dev/null 2>&1; then

        error "Invalid private key."
        return 1
    fi

    local cert_pub
    local key_pub

    cert_pub="$(
        openssl x509 \
            -in "$cert" \
            -pubkey \
            -noout 2>/dev/null |
        openssl pkey \
            -pubin \
            -outform DER 2>/dev/null |
        sha256sum |
        awk '{print $1}'
    )"

    key_pub="$(
        openssl pkey \
            -in "$key" \
            -pubout \
            -outform DER 2>/dev/null |
        sha256sum |
        awk '{print $1}'
    )"

    if [[ -z "$cert_pub" || -z "$key_pub" ]]; then
        error "Unable to compare certificate and private key."
        return 1
    fi

    if [[ "$cert_pub" != "$key_pub" ]]; then
        error "Certificate and private key do NOT match."
        return 1
    fi

    ok "Certificate and private key match."

    return 0
}

collect_cloudflare_certificate() {

    local domain="$1"
    local cert_dir="$2"

    local temp_cert
    local temp_key
    local final_cert
    local final_key

    temp_cert="$(mktemp)"
    temp_key="$(mktemp)"

    chmod 600 "$temp_cert" "$temp_key"

    final_cert="$cert_dir/origin.pem"
    final_key="$cert_dir/origin.key"

    section "Cloudflare Origin Certificate"

    echo -e "${WHITE}Open Cloudflare Dashboard${NC}"
    echo
    echo "Select:"
    echo
    echo -e "    ${CYAN}$domain${NC}"
    echo
    echo "Then navigate to:"
    echo
    echo -e "    ${GREEN}SSL/TLS → Origin Server → Create Certificate${NC}"
    echo
    echo "Recommended settings:"
    echo
    echo "    Private key type : RSA (2048)"
    echo
    echo "    Hostnames        : $domain"
    echo "                       *.$domain"
    echo
    echo "Cloudflare will generate:"
    echo
    echo "    1. Origin Certificate"
    echo "    2. Private Key"
    echo
    echo -e "${YELLOW}Important:${NC}"
    echo "Cloudflare may only display the generated private key once."
    echo "Keep that browser page open until this process is finished."
    echo

    read -r -p "Press Enter when you have the certificate page open..."

    # Certificate

    section "Step 1 of 2 — Origin Certificate"

    echo "Copy the complete value shown under:"
    echo
    echo -e "    ${GREEN}Origin Certificate${NC}"
    echo
    echo "It should start with:"
    echo
    echo "    -----BEGIN CERTIFICATE-----"
    echo
    echo "and end with:"
    echo
    echo "    -----END CERTIFICATE-----"
    echo
    echo -e "${WHITE}Paste it below.${NC}"
    echo -e "When finished, press ${CYAN}Ctrl+D${NC}."
    echo

    cat > "$temp_cert"

    echo

    if ! grep -q '^-----BEGIN CERTIFICATE-----' "$temp_cert"; then
        rm -f "$temp_cert" "$temp_key"
        error "Certificate BEGIN marker was not found."
        return 1
    fi

    if ! grep -q '^-----END CERTIFICATE-----' "$temp_cert"; then
        rm -f "$temp_cert" "$temp_key"
        error "Certificate END marker was not found."
        return 1
    fi

    ok "Certificate received."

    # Private key

    section "Step 2 of 2 — Private Key"

    echo "Copy the complete value shown under:"
    echo
    echo -e "    ${GREEN}Private Key${NC}"
    echo
    echo "It normally starts with:"
    echo
    echo "    -----BEGIN PRIVATE KEY-----"
    echo
    echo "or:"
    echo
    echo "    -----BEGIN RSA PRIVATE KEY-----"
    echo
    echo -e "${WHITE}Paste it below.${NC}"
    echo -e "When finished, press ${CYAN}Ctrl+D${NC}."
    echo

    cat > "$temp_key"

    echo

    if ! grep -Eq '^-----BEGIN (RSA )?PRIVATE KEY-----' "$temp_key"; then
        rm -f "$temp_cert" "$temp_key"
        error "Private key BEGIN marker was not found."
        return 1
    fi

    if ! grep -Eq '^-----END (RSA )?PRIVATE KEY-----' "$temp_key"; then
        rm -f "$temp_cert" "$temp_key"
        error "Private key END marker was not found."
        return 1
    fi

    ok "Private key received."

    if ! validate_certificate_pair "$temp_cert" "$temp_key"; then
        rm -f "$temp_cert" "$temp_key"
        return 1
    fi

    mkdir -p "$cert_dir"
    chmod 700 "$cert_dir"

    install -m 644 "$temp_cert" "$final_cert"
    install -m 600 "$temp_key" "$final_key"

    rm -f "$temp_cert" "$temp_key"

    ok "Cloudflare certificate installed securely."

    echo
    echo "Certificate:"
    echo "    $final_cert"
    echo
    echo "Private key:"
    echo "    $final_key"

    return 0
}

# ------------------------------------------------------------
# Create default index
# ------------------------------------------------------------

create_default_index() {

    local root="$1"
    local domain="$2"

    if [[ -e "$root/index.php" || -e "$root/index.html" ]]; then
        return
    fi

    cat > "$root/index.php" <<EOF
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${domain}</title>
    <style>
        body {
            background: #111827;
            color: #f9fafb;
            font-family: system-ui, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
        }

        .box {
            text-align: center;
        }

        h1 {
            margin-bottom: 8px;
        }

        p {
            color: #9ca3af;
        }
    </style>
</head>
<body>
    <div class="box">
        <h1>${domain}</h1>
        <p>Apache + PHP + Cloudflare HTTPS is working.</p>
    </div>
</body>
</html>
EOF
}

# ------------------------------------------------------------
# Add website
# ------------------------------------------------------------

add_site() {

    banner
    section "Add HTTPS Website"

    local domain=""
    local root=""
    local default_root=""
    local cert_dir=""
    local cert=""
    local key=""
    local config=""
    local existing=""

    while true; do

        read -r -p "Domain name (example.com): " domain

        domain="$(trim "$domain")"
        domain="${domain,,}"

        if validate_domain "$domain"; then
            break
        fi

        warn "Please enter a valid domain name."
    done

    existing="$(find_domain_config "$domain" 2>/dev/null || true)"

    if [[ -n "$existing" ]]; then

        echo
        warn "A configuration for this domain already exists:"
        echo
        echo "    $existing"
        echo

        if ! confirm "Replace the existing configuration?"; then
            return
        fi

        backup_site_config "$existing"

        disable_site "$existing"
        rm -f "$existing"
    fi

    default_root="/var/www/$domain"

    echo
    read -r -p "Document root [$default_root]: " root

    root="$(trim "$root")"

    [[ -n "$root" ]] || root="$default_root"

    if [[ "$root" != /* ]]; then
        warn "Document root must be an absolute path."
        pause
        return
    fi

    if [[ ! -d "$root" ]]; then

        echo
        info "Document root does not exist:"
        echo
        echo "    $root"
        echo

        if ! confirm "Create this directory?"; then
            return
        fi

        mkdir -p "$root"

        ok "Created $root"
    fi

    # Permissions

    if id www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "$root"

    elif id apache >/dev/null 2>&1; then
        chown -R apache:apache "$root"
    fi

    create_default_index "$root" "$domain"

    # Certificate

    cert_dir="$CERT_BASE/$domain"

    if ! collect_cloudflare_certificate "$domain" "$cert_dir"; then
        error "Certificate setup failed."
        pause
        return
    fi

    cert="$cert_dir/origin.pem"
    key="$cert_dir/origin.key"

    # Apache config

    config="$SITES_AVAILABLE/$domain.conf"

    enable_required_modules

    section "Creating Apache Virtual Host"

    cat > "$config" <<EOF
# ============================================================
# Managed by Cloudflare Apache Site Manager
# Version: ${APP_VERSION}
# Domain : ${domain}
# Author : ${APP_AUTHOR}
# ============================================================

<VirtualHost *:80>

    ServerName ${domain}
    ServerAlias www.${domain}

    Redirect permanent / https://${domain}/

</VirtualHost>

<VirtualHost *:443>

    ServerName ${domain}
    ServerAlias www.${domain}

    DocumentRoot "${root}"

    SSLEngine on

    SSLCertificateFile "${cert}"
    SSLCertificateKeyFile "${key}"

    <Directory "${root}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined

</VirtualHost>
EOF

    enable_site "$config"

    info "Testing Apache configuration..."

    if ! apache_test; then

        echo
        error "Apache configuration test failed."

        disable_site "$config"
        rm -f "$config"

        warn "The new virtual host was removed."

        pause
        return
    fi

    ok "Apache configuration is valid."

    apache_reload

    ok "Apache reloaded successfully."

    section "Website Ready"

    echo -e "Domain:"
    echo -e "    ${GREEN}https://${domain}${NC}"
    echo
    echo "Document root:"
    echo "    $root"
    echo
    echo "Apache configuration:"
    echo "    $config"
    echo
    echo "Cloudflare certificate:"
    echo "    $cert"
    echo
    echo "Private key:"
    echo "    $key"

    section "Required Cloudflare Settings"

    echo "DNS records:"
    echo
    echo "    Type   Name   Content          Proxy"
    echo "    ────   ────   ──────────────   ─────────────"
    echo "    A      @      YOUR_VPS_IP      Proxied 🟠"
    echo "    A      www    YOUR_VPS_IP      Proxied 🟠"
    echo
    echo "Then set:"
    echo
    echo -e "    SSL/TLS → Overview → ${GREEN}Full (strict)${NC}"
    echo
    echo "Recommended:"
    echo
    echo -e "    SSL/TLS → Edge Certificates → ${GREEN}Always Use HTTPS: ON${NC}"
    echo

    pause
}

# ------------------------------------------------------------
# Backup configuration
# ------------------------------------------------------------

backup_site_config() {

    local config="$1"
    local backup_dir

    backup_dir="$BACKUP_BASE/$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$backup_dir"

    cp -a "$config" "$backup_dir/" 2>/dev/null || true

    echo "$backup_dir"
}

# ------------------------------------------------------------
# List websites
# ------------------------------------------------------------

list_sites() {

    banner
    section "Configured Apache Websites"

    local file
    local domain
    local root
    local cert
    local enabled
    local count=0

    while IFS= read -r file; do

        [[ -f "$file" ]] || continue

        count=$((count + 1))

        domain="$(config_servername "$file")"
        root="$(config_documentroot "$file")"
        cert="$(config_certfile "$file")"

        [[ -n "$domain" ]] || domain="(no ServerName)"
        [[ -n "$root" ]] || root="-"

        if [[ "$APACHE_MODE" == "debian" ]]; then

            if [[ -e "$SITES_ENABLED/$(basename "$file")" ]]; then
                enabled="${GREEN}Enabled${NC}"
            else
                enabled="${YELLOW}Disabled${NC}"
            fi

        else
            enabled="${GREEN}Enabled${NC}"
        fi

        echo -e "${WHITE}${count}) ${domain}${NC}"
        echo "   Config : $file"
        echo "   Root   : $root"
        echo -e "   Status : $enabled"

        if [[ -n "$cert" ]]; then
            echo "   SSL    : $cert"
        else
            echo "   SSL    : Not configured"
        fi

        echo

    done < <(get_site_configs)

    if [[ "$count" -eq 0 ]]; then
        warn "No Apache websites were found."
    fi

    pause
}

# ------------------------------------------------------------
# Remove website
# ------------------------------------------------------------

remove_site() {

    banner
    section "Remove Website"

    local configs=()
    local domains=()
    local roots=()
    local certs=()
    local keys=()

    local file
    local domain
    local root
    local cert
    local key

    local count=0

    while IFS= read -r file; do

        [[ -f "$file" ]] || continue

        domain="$(config_servername "$file")"
        root="$(config_documentroot "$file")"
        cert="$(config_certfile "$file")"
        key="$(config_keyfile "$file")"

        [[ -n "$domain" ]] || domain="(unknown)"

        configs+=("$file")
        domains+=("$domain")
        roots+=("$root")
        certs+=("$cert")
        keys+=("$key")

        count=$((count + 1))

        echo -e "${WHITE}${count}) ${domain}${NC}"
        echo "   Config: $file"

        [[ -n "$root" ]] && echo "   Root  : $root"

        echo

    done < <(get_site_configs)

    if [[ "$count" -eq 0 ]]; then
        warn "No Apache websites found."
        pause
        return
    fi

    local selection=""

    read -r -p "Select website number to remove: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        warn "Invalid selection."
        pause
        return
    fi

    if (( selection < 1 || selection > count )); then
        warn "Invalid selection."
        pause
        return
    fi

    local index=$((selection - 1))

    file="${configs[$index]}"
    domain="${domains[$index]}"
    root="${roots[$index]}"
    cert="${certs[$index]}"
    key="${keys[$index]}"

    section "Removal Summary"

    echo "Domain:"
    echo "    $domain"
    echo
    echo "Apache configuration:"
    echo "    $file"

    if [[ -n "$root" ]]; then
        echo
        echo "Document root:"
        echo "    $root"
    fi

    if [[ -n "$cert" ]]; then
        echo
        echo "Certificate:"
        echo "    $cert"
    fi

    if [[ -n "$key" ]]; then
        echo
        echo "Private key:"
        echo "    $key"
    fi

    echo

    if ! confirm "Remove this website configuration?"; then
        return
    fi

    local backup_dir

    backup_dir="$(backup_site_config "$file")"

    disable_site "$file"

    rm -f "$file"

    # Managed Cloudflare cert files

    if [[ -n "$cert" && "$cert" == "$CERT_BASE/"* ]]; then
        rm -f "$cert"
    fi

    if [[ -n "$key" && "$key" == "$CERT_BASE/"* ]]; then
        rm -f "$key"
    fi

    if [[ "$domain" != "(unknown)" && -d "$CERT_BASE/$domain" ]]; then
        rmdir "$CERT_BASE/$domain" 2>/dev/null || true
    fi

    # External certificate

    if [[ -n "$cert" && "$cert" != "$CERT_BASE/"* && -f "$cert" ]]; then

        echo
        warn "Certificate is outside the script-managed directory:"
        echo "    $cert"

        if confirm "Delete this certificate too?"; then
            cp -a "$cert" "$backup_dir/" 2>/dev/null || true
            rm -f "$cert"
        fi
    fi

    # External private key

    if [[ -n "$key" && "$key" != "$CERT_BASE/"* && -f "$key" ]]; then

        echo
        warn "Private key is outside the script-managed directory:"
        echo "    $key"

        if confirm "Delete this private key too?"; then
            cp -a "$key" "$backup_dir/" 2>/dev/null || true
            rm -f "$key"
        fi
    fi

    info "Testing Apache configuration..."

    if ! apache_test; then

        error "Apache configuration test failed after removal."

        local backup_config="$backup_dir/$(basename "$file")"

        if [[ -f "$backup_config" ]]; then

            cp -a "$backup_config" "$file"

            enable_site "$file"

            warn "Original Apache configuration restored."
        fi

        pause
        return
    fi

    apache_reload

    ok "Website configuration removed."

    # Website files

    if [[ -n "$root" && -d "$root" ]]; then

        section "Website Files"

        echo -e "${RED}${BOLD}WARNING:${NC}"
        echo
        echo "The document root still exists:"
        echo
        echo "    $root"
        echo
        echo "This may contain:"
        echo
        echo "    • PHP files"
        echo "    • WordPress files"
        echo "    • Uploaded files"
        echo "    • Application data"
        echo

        if confirm "Permanently DELETE the entire document root?"; then

            if safe_document_root "$root"; then

                rm -rf --one-file-system "$root"

                ok "Document root deleted."

            else

                warn "Refusing to delete dangerous system path:"
                echo
                echo "    $root"
            fi

        else

            info "Website files were kept."
        fi
    fi

    section "Removal Complete"

    echo "Apache backup:"
    echo
    echo "    $backup_dir"
    echo
    echo "If the domain is no longer used, remember to remove its"
    echo "DNS records from Cloudflare."
    echo

    pause
}

# ------------------------------------------------------------
# Apache information
# ------------------------------------------------------------

apache_info() {

    banner
    section "Apache Information"

    echo "Apache binary:"
    echo "    $APACHE_BIN"
    echo
    echo "Apache service:"
    echo "    $APACHE_SERVICE"
    echo
    echo "Apache platform:"
    echo "    $APACHE_MODE"
    echo
    echo "Apache configuration:"
    echo "    $APACHE_CONF_DIR"
    echo
    echo "Sites available:"
    echo "    $SITES_AVAILABLE"
    echo
    echo "Sites enabled:"
    echo "    $SITES_ENABLED"
    echo
    echo "Cloudflare certificates:"
    echo "    $CERT_BASE"

    section "Apache Virtual Host Detection"

    "$APACHE_BIN" -S 2>&1 || true

    pause
}

# ------------------------------------------------------------
# Validate all sites
# ------------------------------------------------------------

validate_apache() {

    banner
    section "Apache Configuration Test"

    if apache_test; then

        echo
        ok "Apache configuration is valid."

    else

        echo
        error "Apache configuration contains errors."
    fi

    pause
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

main_menu() {

    while true; do

        banner

        echo -e "${WHITE}${BOLD}Apache:${NC} $APACHE_SERVICE"
        echo -e "${WHITE}${BOLD}Config:${NC} $SITES_AVAILABLE"

        section "Main Menu"

        echo -e "  ${GREEN}1${NC}) Add HTTPS website"
        echo -e "  ${CYAN}2${NC}) List configured websites"
        echo -e "  ${RED}3${NC}) Remove website"
        echo -e "  ${BLUE}4${NC}) Apache information"
        echo -e "  ${MAGENTA}5${NC}) Test Apache configuration"
        echo
        echo -e "  ${GRAY}0${NC}) Exit"
        echo

        local choice=""

        read -r -p "Choose an option: " choice

        case "$choice" in

            1)
                add_site
                ;;

            2)
                list_sites
                ;;

            3)
                remove_site
                ;;

            4)
                apache_info
                ;;

            5)
                validate_apache
                ;;

            0)
                clear
                echo
                echo -e "${GREEN}Goodbye.${NC}"
                echo
                exit 0
                ;;

            *)
                warn "Invalid option."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Startup
# ------------------------------------------------------------

require_root
check_dependencies
detect_apache
main_menu
