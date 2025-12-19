#!/bin/bash

# Script para autorizar MACs manualmente desde el archivo de credenciales
# Uso: ./authorize_mac.sh [MAC_ADDRESS] [HOTSPOT_INTERFACE]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="$SCRIPT_DIR/captive_credentials.txt"  # Ahora en carpeta raíz para Monitoring
HOTSPOT_INTERFACE="${2:-wlan0}"

# Función para autorizar una MAC específica
authorize_mac() {
    local mac="$1"
    local interface="$2"
    
    echo "[+] 🔐 Autorizando MAC: $mac en interfaz: $interface"
    
    # 1. CRÍTICO: Permitir NAT bypass para esta MAC (saltar redirecciones del portal)
    echo "[+] 1. Configurando NAT bypass..."
    sudo iptables -t nat -I PREROUTING 1 -i "$interface" -m mac --mac-source "$mac" -j ACCEPT
    
    # 2. Permitir FORWARD completo para esta MAC (antes de la regla DROP)
    echo "[+] 2. Permitiendo FORWARD salida..."
    sudo iptables -I FORWARD 1 -i "$interface" -m mac --mac-source "$mac" -j ACCEPT
    
    # 3. Permitir FORWARD de retorno para esta MAC
    echo "[+] 3. Permitiendo FORWARD entrada..."
    sudo iptables -I FORWARD 1 -o "$interface" -m mac --mac-destination "$mac" -j ACCEPT
    
    # 4. Permitir INPUT desde esta MAC
    echo "[+] 4. Permitiendo INPUT..."
    sudo iptables -I INPUT 1 -i "$interface" -m mac --mac-source "$mac" -j ACCEPT
    
    echo "[+] ✅ MAC $mac autorizada para acceso completo a Internet"
    
    # Mostrar reglas aplicadas
    echo "[DEBUG] Primeras reglas NAT PREROUTING:"
    sudo iptables -t nat -L PREROUTING -n --line-numbers | head -8
    echo
    echo "[DEBUG] Primeras reglas FORWARD:"
    sudo iptables -L FORWARD -n --line-numbers | head -8
    echo
    echo "[+] 🌐 El dispositivo con MAC $mac debería tener acceso completo a Internet ahora"
}

# Función para autorizar todas las MACs del archivo de credenciales
authorize_all_from_file() {
    echo "[+] 📄 Leyendo credenciales de: $CREDENTIALS_FILE"
    
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo "[!] ❌ Archivo de credenciales no encontrado: $CREDENTIALS_FILE"
        exit 1
    fi
    
    # Leer todas las MACs únicas del archivo
    local macs=$(awk -F'|' '{print $5}' "$CREDENTIALS_FILE" | sort | uniq | grep -v '^$')
    
    if [[ -z "$macs" ]]; then
        echo "[!] ⚠️  No se encontraron MACs en el archivo de credenciales"
        exit 1
    fi
    
    echo "[+] 📋 MACs encontradas en el archivo:"
    echo "$macs" | nl -w2 -s'. '
    echo
    
    # Autorizar cada MAC
    while IFS= read -r mac; do
        if [[ -n "$mac" && "$mac" != "00:00:00:00:00:00" ]]; then
            authorize_mac "$mac" "$HOTSPOT_INTERFACE"
            echo "----------------------------------------"
            sleep 1
        fi
    done <<< "$macs"
    
    echo "[+] ✅ Todas las MACs del archivo han sido autorizadas"
}

# Función para mostrar ayuda
show_help() {
    echo "🔐 Script de autorización manual de MACs"
    echo
    echo "Uso:"
    echo "  $0 [MAC_ADDRESS] [INTERFACE]    - Autorizar MAC específica"
    echo "  $0 --all [INTERFACE]           - Autorizar todas las MACs del archivo"
    echo "  $0 --list                      - Mostrar MACs en el archivo"
    echo "  $0 --help                      - Mostrar esta ayuda"
    echo
    echo "Ejemplos:"
    echo "  $0 aa:bb:cc:dd:ee:ff wlan0"
    echo "  $0 --all wlan0"
    echo "  $0 --list"
}

# Función para listar MACs
list_macs() {
    echo "[+] 📄 MACs en el archivo de credenciales:"
    echo
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        awk -F'|' '{
            if (NF >= 5) {
                timestamp = $1
                site = $2
                email = $3
                mac = $5
                ip = $6
                hostname = $7
                printf "%-19s | %-17s | %-15s | %-9s | %s\n", timestamp, mac, ip, site, email
            }
        }' "$CREDENTIALS_FILE" | column -t
    else
        echo "[!] ❌ Archivo de credenciales no encontrado: $CREDENTIALS_FILE"
    fi
}

# Main script
case "$1" in
    --all)
        authorize_all_from_file
        ;;
    --list)
        list_macs
        ;;
    --help|-h)
        show_help
        ;;
    "")
        echo "[!] ⚠️  Falta especificar MAC o usar --all"
        echo
        show_help
        exit 1
        ;;
    *)
        if [[ "$1" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$ ]]; then
            authorize_mac "$1" "$HOTSPOT_INTERFACE"
        else
            echo "[!] ❌ Formato de MAC inválido: $1"
            echo "    Formato esperado: aa:bb:cc:dd:ee:ff"
            exit 1
        fi
        ;;
esac
