# WiFi Hotspot Multiuso - OSINT + DNS Spoofing + Captive Portal

Herramienta avanzada para crear un hotspot WiFi con capacidades de monitoreo OSINT, DNS Spoofing y portal cautivo educativo. Diseñada para pentesting y demostraciones educativas de seguridad.

## 🎯 Características Principales

### 1. **Hotspot WiFi Configurable**
- Creación de punto de acceso WiFi personalizable
- Soporte para WPA2/WPA3 o redes abiertas
- MAC Spoofing integrado para anonimato
- Configuración flexible de canal y SSID

### 2. **Monitoreo OSINT (Open Source Intelligence)**
- Captura de tráfico de red en tiempo real (PCAP)
- Registro de consultas DNS
- Monitoreo de peticiones HTTP
- Análisis de dispositivos conectados
- Identificación de clientes (MAC, IP, hostname)
- Generación de reportes HTML

### 3. **DNS Spoofing**
- Redirección de dominios específicos (Facebook, Google, etc.)
- Servidor web personalizado para páginas falsas
- Captura de credenciales para demostraciones
- Soporte HTTP/HTTPS con certificados autofirmados

### 4. **Portal Cautivo Personalizado**
- Portal de acceso web configurable
- Páginas de login falsas (Facebook, Instagram)
- Captura de credenciales educativas
- Redirección automática después de autenticación
- Autorización de MACs para acceso a internet

### 5. **Captura de Handshakes WPA**
- Captura automática de handshakes 4-way
- Detección de intentos de conexión
- Generación de archivos para herramientas de cracking
- Monitoreo de eventos de autenticación

### 6. **Panel Web de Control**
- Interfaz web moderna en modo oscuro
- Control en tiempo real del hotspot
- Visualización de logs en vivo (SocketIO)
- Monitoreo de clientes conectados
- Gestión de credenciales capturadas
- Puerto: `http://localhost:5000`

## 📋 Requerimientos del Sistema

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

## 🚀 Instalación

1. **Clonar o descargar el proyecto**
```bash
cd /home/kali/Downloads/versiones
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

## 🎮 Uso

### Modo 1: Panel Web (Recomendado)

1. **Iniciar el panel de control web**
```bash
sudo python3 hotspot_control_web.py
```

2. **Acceder al panel**
- Abrir navegador: `http://localhost:5000`
- Configurar opciones del hotspot
- Hacer clic en "Iniciar Hotspot"

3. **Monitorear actividad**
- Ver logs en tiempo real en la interfaz
- Revisar clientes conectados
- Consultar credenciales capturadas

### Modo 2: Línea de Comandos

```bash
sudo ./wifi_hotspot_osint.sh
```

Seguir el menú interactivo para:
- Configurar SSID y contraseña
- Seleccionar modo de operación
- Activar/desactivar funciones

## 🔧 Configuración

### Configuración Básica del Hotspot

**En el panel web o script, configurar:**

- **SSID**: Nombre de la red WiFi (ej: "WiFi-Gratis")
- **Contraseña**: Dejar vacío para red abierta, mínimo 8 caracteres para WPA2
- **Canal**: Canal WiFi (1-11 para 2.4GHz, recomendado: 6)
- **Interfaz**: Adaptador WiFi a usar (auto-detectado)

### Configuración del Portal Cautivo

- **Activar Portal**: Sí/No
- **Dominio Ficticio**: Dominio para el portal (ej: `conectate-wifi.com`)
- **URL de Redirección**: URL después de autenticación (ej: `https://google.com`)
- **Puerto**: Puerto del servidor cautivo (default: 8080)

### MAC Spoofing

Opciones disponibles:
- No cambiar MAC
- MAC aleatoria
- MAC personalizada (formato: `XX:XX:XX:XX:XX:XX`)

## 📁 Estructura de Archivos

```
/home/kali/Downloads/versiones/
├── wifi_hotspot_osint.sh          # Script principal
├── spoof_functions.sh             # Funciones de DNS Spoofing
├── hotspot_control_web.py         # Panel web de control
├── webcautivo/                    # Templates del portal cautivo
│   ├── index.html                 # Página principal del portal
│   ├── facebook.html              # Login falso de Facebook
│   └── instagram.html             # Login falso de Instagram
├── logs/                          # Directorio de logs (auto-creado)
│   ├── config/                    # Archivos de configuración
│   │   ├── hostapd.conf
│   │   └── dnsmasq.conf
│   ├── captive_portal/            # Portal cautivo activo
│   ├── hostapd.log                # Logs de hostapd
│   ├── dnsmasq.log                # Logs de dnsmasq
│   ├── hotspot_YYYYMMDD.log       # Log de sesión
│   ├── clients_YYYYMMDD.txt       # Clientes conectados
│   ├── traffic_YYYYMMDD.pcap      # Captura de tráfico
│   ├── dns_queries_YYYYMMDD.log   # Consultas DNS
│   ├── http_requests_YYYYMMDD.log # Peticiones HTTP
│   ├── handshake_*.cap            # Handshakes capturados
│   ├── captive_credentials.txt    # Credenciales del portal
│   └── captured_credentials_*.txt # Credenciales de phishing
└── README.md                      # Este archivo
```

## 🎨 Modos de Operación

### 1. **Modo OSINT**
Monitoreo pasivo de red:
- Captura todo el tráfico
- Análisis de dispositivos
- Generación de reportes
- Sin manipulación de datos

### 2. **Modo DNS Spoofing**
Redirección de dominios:
- Spoofing de sitios específicos
- Páginas falsas educativas
- Captura de credenciales de prueba
- Alertas de seguridad visibles

### 3. **Modo Captive Portal**
Portal de autenticación:
- Requiere login para internet
- Captura de emails/credenciales
- Redirección post-autenticación
- Gestión de MACs autorizadas

## 🔒 Consideraciones de Seguridad

### ⚠️ USO EDUCATIVO ÚNICAMENTE

Esta herramienta está diseñada exclusivamente para:
- Entornos de prueba controlados
- Demostraciones educativas de seguridad
- Pentesting autorizado
- Investigación en seguridad informática

### ⛔ ADVERTENCIAS LEGALES

- **NO** usar sin autorización explícita
- **NO** capturar credenciales reales sin consentimiento
- **NO** interceptar comunicaciones privadas
- **NO** usar en redes públicas o ajenas
- El uso indebido puede ser **ILEGAL** y resultar en sanciones

### 🛡️ Protección Implementada

- Alertas visibles en páginas falsas
- Advertencias sobre certificados SSL
- Mensajes educativos en capturas
- Logs detallados para auditoría

## 📊 Análisis de Datos

### Logs Generados

**Archivos de Captura:**
- `traffic_YYYYMMDD.pcap`: Analizar con Wireshark
- `handshake_*.cap`: Usar con aircrack-ng o hashcat
- `dns_queries_*.log`: Dominios visitados
- `http_requests_*.log`: URLs accedidas

**Análisis de PCAP:**
```bash
# Abrir con Wireshark
wireshark logs/traffic_YYYYMMDD.pcap

# Filtros útiles:
# - dns: Solo consultas DNS
# - http: Solo tráfico HTTP
# - wlan.fc.type_subtype == 0x08: Beacons
```

**Crackeo de Handshakes:**
```bash
# Con aircrack-ng
aircrack-ng -w wordlist.txt logs/handshake_SSID.cap

# Con hashcat
hashcat -m 22000 logs/hash_MACADDR.22000 wordlist.txt
```

## 🐛 Solución de Problemas

### Hotspot no inicia

**Problema:** hostapd falla al iniciar
**Solución:**
```bash
# Verificar que la interfaz esté up
sudo ip link set wlan0 up

# Matar procesos conflictivos
sudo killall hostapd dnsmasq NetworkManager

# Verificar logs
cat logs/hostapd.log
```

### Clientes no obtienen IP

**Problema:** DHCP no funciona
**Solución:**
```bash
# Verificar dnsmasq
cat logs/dnsmasq.log

# Verificar que la interfaz tenga IP
ip addr show wlan0

# Debe mostrar: 192.168.50.1/24
```

### Portal cautivo no redirige

**Problema:** Clientes no ven el portal
**Solución:**
```bash
# Verificar iptables
sudo iptables -t nat -L -n -v

# Debe haber reglas REDIRECT al puerto del portal

# Verificar servidor del portal
cat logs/captive_server.log
```

### Permisos denegados

**Problema:** "Permission denied"
**Solución:**
```bash
# Ejecutar siempre con sudo
sudo python3 hotspot_control_web.py
sudo ./wifi_hotspot_osint.sh

# Verificar permisos de logs
sudo chmod -R 755 logs/
```

## 🔄 Detener el Hotspot

### Desde el Panel Web
- Hacer clic en "Detener Hotspot"
- Esperar confirmación

### Desde Terminal
```bash
# Si está en modo interactivo
Ctrl + C

# Limpieza manual
sudo killall hostapd dnsmasq tcpdump
sudo iptables -F
sudo iptables -t nat -F
```

## 📝 Ejemplos de Uso

### Ejemplo 1: Red WiFi Simple con Monitoreo

```bash
# Iniciar panel web
sudo python3 hotspot_control_web.py

# En el navegador (localhost:5000):
# - SSID: "WiFi-Test"
# - Contraseña: "password123"
# - Portal Cautivo: Desactivado
# - Iniciar Hotspot

# Los logs se guardarán automáticamente en logs/
```

### Ejemplo 2: Portal Cautivo Educativo

```bash
# Configuración en el panel web:
# - SSID: "Hotel-WiFi-Gratis"
# - Sin contraseña (red abierta)
# - Portal Cautivo: Activado
# - Dominio: "login-wifi.com"
# - Redirección: "https://google.com"

# Los usuarios verán el portal al conectarse
# Las credenciales se guardan en logs/captive_credentials.txt
```

### Ejemplo 3: Captura de Handshakes

```bash
# Configurar como Evil Twin:
# - SSID: "NetworkTarget" (nombre de red objetivo)
# - Contraseña: cualquiera (incorrecta a propósito)
# - Esperar intentos de conexión

# Los handshakes se guardan en:
# logs/handshake_NetworkTarget_TIMESTAMP.cap
```

## 🆘 Soporte y Contribuciones

### Reporte de Bugs
- Incluir logs completos
- Describir pasos para reproducir
- Especificar sistema operativo

### Características del Sistema
```bash
# Información útil para debug
uname -a                    # Versión del kernel
ip link show               # Interfaces de red
hostapd -v                 # Versión de hostapd
python3 --version          # Versión de Python
```

## 📚 Recursos Adicionales

### Documentación Relacionada
- [hostapd documentation](https://w1.fi/hostapd/)
- [dnsmasq man page](http://www.thekelleys.org.uk/dnsmasq/doc.html)
- [Flask documentation](https://flask.palletsprojects.com/)
- [iptables tutorial](https://www.netfilter.org/documentation/)

### Herramientas Complementarias
- **Wireshark**: Análisis gráfico de PCAPs
- **aircrack-ng**: Suite de cracking WiFi
- **hashcat**: Cracking de passwords
- **ettercap**: MITM attacks

## 📄 Licencia

**USO EDUCATIVO Y DE INVESTIGACIÓN ÚNICAMENTE**

Esta herramienta se proporciona "tal cual" sin garantías. El autor no se hace responsable del uso indebido o ilegal de este software.

**IMPORTANTE:** Obtener siempre autorización explícita antes de realizar cualquier prueba de seguridad.

---

## 🔑 Características Técnicas Avanzadas

### Networking
- NAT con iptables
- Port forwarding dinámico
- DNS forwarding selectivo
- DHCP con lease management

### Seguridad
- WPA2-PSK con hostapd
- MAC filtering opcional
- Traffic isolation
- Logging exhaustivo

### Performance
- Soporte multi-cliente
- Buffer optimization para capturas
- Real-time log streaming con SocketIO
- Async operations en Python

---

**Versión:** 2.0  
**Última actualización:** Diciembre 2024  
**Autor:** Herramienta educativa de pentesting WiFi
