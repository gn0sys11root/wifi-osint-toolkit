# WiFi Hotspot Multiuso - OSINT + DNS Spoofing + Captive Portal

![Panel de Control WiFi Hotspot](Screenshot_2025-12-17_06_32_14.png)

Herramienta avanzada para crear un hotspot WiFi con capacidades de monitoreo OSINT, DNS Spoofing y portal cautivo educativo. Diseñada para pentesting y demostraciones educativas de seguridad.

## Características Principales

- **Hotspot WiFi Configurable**: Punto de acceso personalizable con WPA2/WPA3 o redes abiertas
- **Monitoreo OSINT**: Captura de tráfico en tiempo real, logs DNS/HTTP, análisis de dispositivos
- **DNS Spoofing**: Redirección de dominios con páginas falsas para demostraciones
- **Portal Cautivo**: Portal de autenticación web con captura de credenciales
- **Captura de Handshakes WPA**: Detección y captura automática de handshakes 4-way
- **Panel Web de Control**: Interfaz moderna con monitoreo en tiempo real en `http://localhost:5000`

## Requerimientos del Sistema

### Sistema Operativo
- Linux (Kali Linux recomendado)
- Debian/Ubuntu y derivados

### Dependencias del Sistema

Instalar todas las dependencias con un solo comando:

```bash
sudo apt-get update
sudo apt-get install -y hostapd dnsmasq tcpdump tshark iptables expect python3-flask python3-flask-socketio
```

**Descripción de cada paquete:**

- **hostapd**: Software para crear puntos de acceso WiFi
- **dnsmasq**: Servidor DHCP y DNS
- **tcpdump**: Captura de paquetes de red
- **tshark**: Herramienta de análisis de tráfico (Wireshark CLI)
- **iptables**: Firewall y NAT de Linux
- **expect**: Automatización de scripts interactivos
- **python3-flask**: Framework web para Python
- **python3-flask-socketio**: Comunicación en tiempo real WebSocket

### Hardware Requerido
- Adaptador WiFi con capacidad de modo AP (Access Point)
- Conexión a internet (para NAT y acceso upstream)

## Instalación

1. **Navegar al directorio del proyecto**
```bash
cd /ruta/al/proyecto
```

2. **Instalar dependencias**
```bash
sudo apt-get update
sudo apt-get install -y hostapd dnsmasq tcpdump tshark iptables expect python3-flask python3-flask-socketio
```

3. **Verificar interfaces de red**
```bash
ip link show
# Identificar tu interfaz WiFi (ej: wlan0, wlan1)
```

4. **Dar permisos de ejecución**
```bash
chmod +x wifi_hotspot_osint.sh
chmod +x spoof_functions.sh
```

## Uso

### Panel Web (Recomendado)

1. Iniciar el panel de control web:
```bash
sudo python3 hotspot_control_web.py
```

2. Acceder al panel en `http://localhost:5000`
3. Configurar opciones del hotspot y hacer clic en "Iniciar Hotspot"

### Línea de Comandos

```bash
sudo ./wifi_hotspot_osint.sh
```

Seguir el menú interactivo para configurar e iniciar el hotspot.

## Configuración Básica

- **SSID**: Nombre de la red WiFi
- **Contraseña**: Dejar vacío para red abierta, mínimo 8 caracteres para WPA2
- **Canal**: Canal WiFi (1-11 para 2.4GHz, recomendado: 6)
- **Portal**: Activar/desactivar portal cautivo
- **MAC Spoofing**: Aleatorio, personalizado o desactivado

## Estructura de Archivos

```
proyecto/
├── wifi_hotspot_osint.sh          # Script principal
├── spoof_functions.sh             # Funciones de DNS Spoofing
├── hotspot_control_web.py         # Panel web de control
├── webcautivo/                    # Templates del portal cautivo
├── logs/                          # Logs generados automáticamente
│   ├── traffic_YYYYMMDD.pcap      # Capturas de red
│   ├── dns_queries_YYYYMMDD.log   # Logs DNS
│   ├── captive_credentials.txt    # Credenciales capturadas
│   └── handshake_*.cap            # Handshakes WPA
└── README.md
```

## Consideraciones de Seguridad

**USO EDUCATIVO ÚNICAMENTE**

Esta herramienta está diseñada exclusivamente para:
- Entornos de prueba controlados
- Demostraciones educativas de seguridad
- Pentesting autorizado
- Investigación en seguridad informática

**ADVERTENCIAS LEGALES**

- NO usar sin autorización explícita
- NO capturar credenciales reales sin consentimiento
- NO interceptar comunicaciones privadas
- NO usar en redes públicas o ajenas
- El uso indebido puede ser ILEGAL y resultar en sanciones

## Detener el Hotspot

Desde el panel web: Hacer clic en "Detener Hotspot"

Desde terminal:
```bash
# Presionar Ctrl + C o:
sudo killall hostapd dnsmasq tcpdump
sudo iptables -F
sudo iptables -t nat -F
```

## Licencia

**USO EDUCATIVO Y DE INVESTIGACIÓN ÚNICAMENTE**

Esta herramienta se proporciona "tal cual" sin garantías. El autor no se hace responsable del uso indebido o ilegal de este software.

**IMPORTANTE:** Obtener siempre autorización explícita antes de realizar cualquier prueba de seguridad.

---

**Versión:** 2.0  
**Última actualización:** Diciembre 2024
