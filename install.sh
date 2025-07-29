#!/bin/bash

# ==============================================================================
# INSTALADOR MAESTRO DE RDP Client 2026 v7.9 (Versión a Prueba de Fallos)
# ==============================================================================
# Esta es la versión final del proyecto.
# - Soluciona el problema de descarga del logo añadiendo la bandera
#   '--no-check-certificate' a wget para máxima compatibilidad.
# - Mantiene todas las características anteriores.
#
# Debe ejecutarse con privilegios de root (sudo).
# ==============================================================================

# --- Configuración y Seguridad ---
set -e

APP_USER="rdp"
APP_DIR="/opt/rdpclient"
NODE_APP_FILE="index.js"
PUBLIC_DIR="${APP_DIR}/public"
CONFIG_DEST_DIR="/home/${APP_USER}"
SERVICE_NAME="rdpclient-web"
ADMIN_CONFIG_FILE="${APP_DIR}/admin.conf"
LOGO_URL_RAW="https://raw.githubusercontent.com/ITSanchez/rdpclient2026/main/grub-logo.png"
LOGO_PATH_GRUB="/boot/grub/rdpclient-logo.png"
LOGO_PATH_WEB="${PUBLIC_DIR}/logo.png"

# --- Colores para la Salida ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Funciones de Ayuda ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================================================================
# PASO 0: VALIDACIONES PREVIAS
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
   log_error "Este script debe ejecutarse como root. Por favor, use 'sudo ./install.sh'"
fi
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if ! ([ "$ID" == "debian" ] && [ "$VERSION_ID" == "12" ]); then
        log_error "Este instalador está diseñado para Debian 12.x (bookworm)."
    fi
else
    log_error "No se pudo verificar la versión del sistema operativo."
fi
log_info "Sistema operativo verificado: Debian 12 (bookworm)."
log_info "Aviso: El script ha sido probado sobre una instalación mínima de Debian 12 en modo texto."

# ==============================================================================
# PASO 1: INSTALACIÓN DE DEPENDENCIAS
# ==============================================================================
log_info "Verificando dependencias del sistema..."
REQUIRED_PACKAGES=(xserver-xorg xinit freerdp2-x11 sudo wget ca-certificates grub2-common)
log_info "Actualizando índice de paquetes..."
apt-get update >/dev/null 2>&1
log_info "Instalando paquetes necesarios..."
log_warn "Esto puede demorar unos minutos dependiendo de su conexión a internet."
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        log_info "Instalando $pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
    else
        log_info "$pkg ya está instalado."
    fi
done
log_info "Todas las dependencias del sistema están presentes."

# ==============================================================================
# PASO 2: INSTALACIÓN DE NODE.JS (SI ES NECESARIO)
# ==============================================================================
log_info "Verificando instalación de Node.js..."
if command -v node &> /dev/null; then log_info "Node.js ya está instalado (versión $(node -v))."; else
    log_warn "Node.js no encontrado. Procediendo con la instalación..."
    PICHIP=$(uname -m); if [ "$PICHIP" == "aarch64" ]; then PICHIP="arm64"; fi
    ( cd /tmp; wget --quiet -O node-install "https://raw.githubusercontent.com/audstanley/NodeJs-Raspberry-Pi/master/build/node-install-"$PICHIP; chmod +x node-install; ./node-install -a > /dev/null; rm -f node-install )
    if ! command -v node &> /dev/null; then log_error "La instalación de Node.js falló."; fi
    log_info "Node.js ha sido instalado correctamente. Versión: $(node -v)"
fi

# ==============================================================================
# PASO 3: INSTALACIÓN DE LA APLICACIÓN RDP Client 2026
# ==============================================================================
log_info "Iniciando la instalación de la aplicación RDP Client 2026..."
if id -u "$APP_USER" &>/dev/null; then
    log_warn "El usuario '$APP_USER' ya existe."
else
    log_info "Creando usuario del sistema '$APP_USER' con home en $CONFIG_DEST_DIR...";
    /usr/sbin/useradd --system --create-home --shell /bin/bash --home-dir "$CONFIG_DEST_DIR" "$APP_USER"
fi

log_info "Configurando sudo para el usuario 'rdp'..."
SUDOERS_RDP_FILE="/etc/sudoers.d/010_rdp_user_permissions"
echo "${APP_USER} ALL=(ALL) NOPASSWD: /home/rdp/rdp.sh, /sbin/shutdown, /sbin/reboot" > "$SUDOERS_RDP_FILE"
/bin/chmod 0440 "$SUDOERS_RDP_FILE"

log_info "Creando directorios y restableciendo contraseña de admin..."
/bin/mkdir -p "$PUBLIC_DIR"
echo "Rdpclient2026" > "$ADMIN_CONFIG_FILE"
/bin/chown root:root "$ADMIN_CONFIG_FILE"; /bin/chmod 600 "$ADMIN_CONFIG_FILE"

log_info "Creando el Mensaje del Día personalizado en /etc/motd..."
cat << 'EOF' > /etc/motd

############################################################################
#                                                                          #
#                       RDP Client 2026                                    #
#       https://sourceforge.net/projects/rdpclient/                        #
#                                                                          #
#               Creado por Guillermo Sanchez                               #
#               gsanchez@itsanchez.com.ar                                  #
#                                                                          #
############################################################################

EOF

# ==============================================================================
# PASO 4: BRANDING DEL SISTEMA Y LA APLICACIÓN
# ==============================================================================
log_info "Descargando y configurando el fondo de arranque (GRUB)..."
# --- ¡CORRECCIÓN! --- Añadida la bandera --no-check-certificate
if wget --quiet --no-check-certificate -O "$LOGO_PATH_GRUB" "$LOGO_URL_RAW"; then
    log_info "Configurando GRUB para usar la imagen de fondo y timeout de 5s..."
    sed -i -e 's,^#\?GRUB_BACKGROUND=.*,GRUB_BACKGROUND="'"$LOGO_PATH_GRUB"'",g' \
           -e 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/g' /etc/default/grub
    log_info "Actualizando la configuración de GRUB..."
    /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
    log_info "Fondo de arranque y timeout actualizados."
else
    log_warn "No se pudo descargar el logo para GRUB. Se omitirá este paso."
fi
log_info "Descargando el logo para la interfaz web..."
# --- ¡CORRECCIÓN! --- Añadida la bandera --no-check-certificate
if ! wget --quiet --no-check-certificate -O "$LOGO_PATH_WEB" "$LOGO_URL_RAW"; then
    log_warn "No se pudo descargar el logo para la web."
fi

# ==============================================================================
# PASO 5: GENERACIÓN DE ARCHIVOS DEL PROYECTO
# ==============================================================================
log_info "Generando archivos del proyecto Node.js..."
# package.json
cat << 'EOF' > "${APP_DIR}/package.json"
{ "name": "rdp-client-2026", "version": "7.9.0", "description": "Consola de Administración para RDP Client 2026", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.19.2" } }
EOF
# index.js
cat << 'EOF' > "${APP_DIR}/${NODE_APP_FILE}"
const express = require('express');
const { exec } = require('child_process');
const fs = require('fs').promises;
const fsSync = require('fs');
const path =require('path');
const app = express(), PORT = 3000, LINUX_USER = 'rdp', CONFIG_DEST_DIR = `/home/${LINUX_USER}`, RDP_INI_PATH = path.join(CONFIG_DEST_DIR, 'rdp.ini'), ADMIN_CONFIG_FILE = path.join(__dirname, 'admin.conf'), HOSTS_FILE = '/etc/hosts';
app.use(express.static('public')); app.use(express.json());
const runCommand = (command) => new Promise((resolve, reject) => { exec(command, (error, stdout, stderr) => { if (error) { console.error(`Error en comando: ${command}\n${stderr}`); return reject(new Error(`Falló un comando del sistema.`)); } resolve(stdout.trim()); }); });
app.post('/login', async (req, res) => { try { const adminPassword = await fs.readFile(ADMIN_CONFIG_FILE, 'utf8'); if (req.body.username === 'rdpadmin' && req.body.password.trim() === adminPassword.trim()) { res.status(200).json({ message: 'Login exitoso' }); } else { res.status(401).json({ message: 'Credenciales incorrectas' }); } } catch (error) { res.status(500).json({ message: 'Error interno del servidor.' }); } });
app.get('/get-config', async (req, res) => { try { const data = await fs.readFile(RDP_INI_PATH, 'utf8'); const config = {}; data.split('\n').forEach(line => { if (line.includes('=')) { const [key, value] = line.split('='); config[key.trim()] = value.trim().replace(/"/g, ''); } }); res.status(200).json({ rdpServer: config.RDP_SERVER || '', rdpPort: config.RDP_PORT || '3389', rdpUser: config.RDP_USER || '' }); } catch (error) { res.status(200).json({ rdpServer: '', rdpPort: '3389', rdpUser: '' }); } });
app.post('/generate', async (req, res) => { const { rdpServer, rdpPort, rdpUser, rdpPass, linuxPass, autologinMode } = req.body; try { const iniContent = `RDP_SERVER="${rdpServer}"\nRDP_PORT="${rdpPort || '3389'}"\nRDP_USER="${rdpUser}"\nENCRYPTED_PASS_FILE="rdp.pass.enc"`; await fs.writeFile(RDP_INI_PATH, iniContent); if (rdpPass) { const passphrase = 'tu-frase-secreta-maestra-muy-segura'; const encryptCommand = `/bin/echo -n '${rdpPass}' | /usr/bin/openssl enc -aes-256-cbc -pbkdf2 -a -salt -out ${path.join(CONFIG_DEST_DIR, 'rdp.pass.enc')} -pass pass:${passphrase}`; await runCommand(encryptCommand); } if (linuxPass) { await runCommand(`/bin/bash -c "/bin/echo '${LINUX_USER}:${linuxPass}' | /usr/sbin/chpasswd"`); } await configureAutologin(autologinMode); await setConfigFileOwnership(); res.status(200).json({ message: '¡Configuración aplicada con éxito!' }); } catch (error) { res.status(500).json({ message: error.message }); } });
app.post('/change-admin-password', async (req, res) => { if (!req.body.newPassword || req.body.newPassword.length < 8) { return res.status(400).json({ message: 'La contraseña debe tener al menos 8 caracteres.' }); } try { await fs.writeFile(ADMIN_CONFIG_FILE, req.body.newPassword); res.status(200).json({ message: 'Contraseña de administrador cambiada.' }); } catch (error) { res.status(500).json({ message: 'Error al escribir el archivo.' }); } });
app.post('/reboot', (req, res) => { res.status(200).json({ message: 'Comando de reinicio enviado...' }); setTimeout(() => { runCommand('/sbin/reboot').catch(err => console.error("Fallo al reiniciar:", err)); }, 1000); });
app.get('/get-hostname', async (req, res) => { try { const hostname = await runCommand('hostname'); res.status(200).json({ hostname }); } catch (error) { res.status(500).json({ message: 'No se pudo obtener el hostname.' }); } });
app.post('/change-hostname', async (req, res) => { const { newHostname } = req.body; if (!newHostname || !/^[a-zA-Z0-9-]+$/.test(newHostname)) { return res.status(400).json({ message: 'Hostname inválido.' }); } try { const oldHostname = await runCommand('hostname'); await runCommand(`/bin/hostnamectl set-hostname ${newHostname}`); let hostsContent = await fs.readFile(HOSTS_FILE, 'utf8'); const regex = new RegExp(`(127\\.0\\.1\\.1\\s+)${oldHostname}`, 'g'); hostsContent = hostsContent.replace(regex, `$1${newHostname}`); await fs.writeFile(HOSTS_FILE, hostsContent); res.status(200).json({ message: `Hostname cambiado a '${newHostname}'.` }); } catch (error) { res.status(500).json({ message: 'Error al cambiar el hostname.' }); } });
async function configureAutologin(mode) { const overrideDir = `/etc/systemd/system/getty@tty1.service.d`, overrideFile = path.join(overrideDir, 'override.conf'); if (mode === 'text') { const overrideContent = `[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin ${LINUX_USER} --noclear %I $TERM\n`; await runCommand(`/bin/mkdir -p ${overrideDir}`); await fs.writeFile(overrideFile, overrideContent); } else { if (fsSync.existsSync(overrideFile)) { await runCommand(`/bin/rm ${overrideFile}`); } } await runCommand(`/bin/systemctl daemon-reload`); }
async function setConfigFileOwnership() { return runCommand(`/bin/chown -R ${LINUX_USER}:${LINUX_USER} ${CONFIG_DEST_DIR}`); }
app.listen(PORT, '0.0.0.0', () => { console.log(`Backend de RDP Client 2026 escuchando en http://0.0.0.0:${PORT}`); });
EOF
# HTML
cat << 'EOF' > "${PUBLIC_DIR}/index.html"
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>RDP Client 2026</title><link rel="stylesheet" href="styles.css"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&display=swap" rel="stylesheet"></head><body><div id="toast-container"></div><div class="container"><div class="header-logo-container"><img src="logo.png" alt="Logo RDP Client 2026" class="header-logo"></div><div id="login-form-container"><h1>RDP Client 2026</h1><form id="login-form"><input type="text" id="admin-user" value="rdpadmin" required><input type="password" id="admin-pass" placeholder="Contraseña" required><button type="submit">Ingresar</button></form></div><div id="main-content" class="hidden"><h1>RDP Client 2026</h1><form id="main-form"><div class="form-grid"><fieldset><legend>Datos de Conexión RDP</legend><input type="text" id="rdp-server" name="rdpServer" placeholder="Servidor RDP (IP o Dominio)" required><input type="text" id="rdp-port" name="rdpPort" placeholder="Puerto RDP" value="3389" required><input type="text" id="rdp-user" name="rdpUser" placeholder="Usuario RDP" required><input type="password" id="rdp-pass" name="rdpPass" placeholder="Contraseña RDP (dejar en blanco para no cambiar)"></fieldset><fieldset><legend>Configuración Local</legend><input type="password" id="linux-pass" name="linuxPass" placeholder="Contraseña para 'rdp' (dejar en blanco para no cambiar)"><label for="autologin-mode">Auto-Login al iniciar:</label><select id="autologin-mode" name="autologinMode"><option value="text" selected>Habilitado</option><option value="none">Deshabilitado</option></select></fieldset></div><div class="action-buttons-container"><button type="submit">Aplicar Configuración</button><button type="button" id="change-pass-btn">Pass Admin</button><button type="button" id="change-hostname-btn">Hostname</button><button type="button" id="reboot-btn" class="danger-button">Reiniciar</button></div></form><hr><div class="footer"><p><a href="https://sourceforge.net/projects/rdpclient/" target="_blank">Proyecto RDP Client 2026 en SourceForge</a></p><p>Creado por Guillermo Sanchez | <a href="mailto:gsanchez@itsanchez.com.ar">gsanchez@itsanchez.com.ar</a></p></div></div></div><div id="password-modal" class="modal hidden"><div class="modal-content"><span class="close-button">×</span><h2>Cambiar Contraseña de Administrador</h2><form id="change-pass-form"><input type="password" id="new-admin-pass" placeholder="Nueva Contraseña (mín. 8 caracteres)" required><input type="password" id="confirm-admin-pass" placeholder="Confirmar Nueva Contraseña" required><button type="submit">Confirmar Cambio</button></form></div></div><div id="hostname-modal" class="modal hidden"><div class="modal-content"><span class="close-button">×</span><h2>Cambiar Hostname</h2><form id="change-hostname-form"><p>Hostname actual: <strong id="current-hostname"></strong></p><input type="text" id="new-hostname" placeholder="Nuevo hostname" required><button type="submit">Confirmar Cambio</button></form></div></div></body><script src="client.js"></script></html>
EOF
# CSS
cat << 'EOF' > "${PUBLIC_DIR}/styles.css"
:root{--bg-color:#121212;--surface-color:#1e1e1e;--primary-color:#bb86fc;--text-color:#e1e1e1;--border-color:#444;--error-color:#cf6679;--success-color:#03dac6;--danger-color:#f44336}body{font-family:'Inter',sans-serif;background-color:var(--bg-color);color:var(--text-color);margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh}h1,h2{text-align:center;font-weight:700}.container{width:100%;max-width:800px;background-color:var(--surface-color);padding:2rem;border-radius:12px;box-shadow:0 10px 30px #0009;border:1px solid var(--border-color);z-index:10;}.header-logo-container{text-align:center;margin-bottom:1rem;}.header-logo{max-width:200px;height:auto;opacity:0.8;}input,select,button{width:100%;padding:14px;background-color:#2c2c2c;border:1px solid var(--border-color);border-radius:8px;color:var(--text-color);font-size:1rem;box-sizing:border-box;transition:all .2s ease}input:focus,select:focus{outline:0;border-color:var(--primary-color);box-shadow:0 0 0 3px #bb86fc40}button{background-color:var(--primary-color);color:#000;font-weight:500;cursor:pointer;font-size:0.9rem;}button:hover{filter:brightness(1.1)}button:disabled{background-color:#555;cursor:not-allowed}legend{color:var(--primary-color);font-weight:500;padding:0 10px}fieldset{border:1px solid var(--border-color);border-radius:8px;padding:1.5rem;margin:0;display:flex;flex-direction:column;gap:1rem}.form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1.5rem;margin-bottom:1.5rem}.action-buttons-container{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1rem;margin-top:1.5rem}.danger-button{background-color:var(--error-color);color:#fff}.hidden{display:none!important}hr{border:none;border-top:1px solid var(--border-color);margin:2rem 0 1rem 0;}.footer{text-align:center;font-size:0.9rem;color:#888}.footer a{color:var(--primary-color);text-decoration:none}.footer a:hover{text-decoration:underline}.modal{position:fixed;z-index:100;left:0;top:0;width:100%;height:100%;overflow:auto;background-color:#000000a0;display:flex;justify-content:center;align-items:center}.modal-content{background-color:var(--surface-color);margin:auto;padding:2rem;border:1px solid var(--border-color);width:90%;max-width:500px;border-radius:12px;position:relative;animation:modal-fade-in .3s}.close-button{color:#aaa;float:right;font-size:28px;font-weight:700;position:absolute;top:10px;right:20px}.close-button:hover,.close-button:focus{color:#fff;text-decoration:none;cursor:pointer}#toast-container{position:fixed;top:20px;right:20px;z-index:1000}.toast{background-color:#333;color:#fff;padding:1rem;border-radius:8px;margin-bottom:1rem;box-shadow:0 3px 10px #0009;opacity:0;transform:translateX(100%);animation:toast-in .5s forwards}.toast.success{background:linear-gradient(90deg,var(--success-color),#01b8a2)}.toast.error{background:linear-gradient(90deg,var(--error-color),#b84d60)}@keyframes toast-in{to{opacity:1;transform:translateX(0)}}@keyframes modal-fade-in{from{opacity:0;transform:translateY(-50px)}to{opacity:1;transform:translateY(0)}}
EOF
# client.js
cat << 'EOF' > "${PUBLIC_DIR}/client.js"
document.addEventListener('DOMContentLoaded', () => {
    const loginFormContainer = document.getElementById('login-form-container');
    const mainContent = document.getElementById('main-content');
    const loginForm = document.getElementById('login-form');
    const mainForm = document.getElementById('main-form');
    const changePassBtn = document.getElementById('change-pass-btn');
    const changeHostnameBtn = document.getElementById('change-hostname-btn');
    const rebootBtn = document.getElementById('reboot-btn');
    const passwordModal = document.getElementById('password-modal');
    const hostnameModal = document.getElementById('hostname-modal');
    const closeModalBtns = document.querySelectorAll('.close-button');
    const changePassForm = document.getElementById('change-pass-form');
    const changeHostnameForm = document.getElementById('change-hostname-form');

    function showToast(message, isError = false) {
        const container = document.getElementById('toast-container');
        const toast = document.createElement('div');
        toast.className = `toast ${isError ? 'error' : 'success'}`;
        toast.textContent = message;
        container.appendChild(toast);
        setTimeout(() => { toast.remove(); }, 5000);
    }

    const openModal = (modal) => modal.classList.remove('hidden');
    const closeModal = (modal) => modal.classList.add('hidden');

    changePassBtn.addEventListener('click', () => openModal(passwordModal));
    changeHostnameBtn.addEventListener('click', async () => {
        try {
            const response = await fetch('/get-hostname');
            const data = await response.json();
            document.getElementById('current-hostname').textContent = response.ok ? data.hostname : 'No disponible';
        } catch (error) { document.getElementById('current-hostname').textContent = 'Error'; }
        openModal(hostnameModal);
    });

    closeModalBtns.forEach(btn => btn.addEventListener('click', () => {
        closeModal(passwordModal); closeModal(hostnameModal);
    }));
    
    window.addEventListener('click', (event) => {
        if (event.target === passwordModal) closeModal(passwordModal);
        if (event.target === hostnameModal) closeModal(hostnameModal);
    });

    loginForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        try {
            const response = await fetch('/login', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username: 'rdpadmin', password: e.target.elements['admin-pass'].value }),
            });
            const result = await response.json();
            if (!response.ok) throw new Error(result.message);
            loginFormContainer.classList.add('hidden');
            mainContent.classList.remove('hidden');
            loadCurrentConfig();
        } catch (error) { showToast(error.message, true); }
    });

    async function loadCurrentConfig() {
        try {
            const response = await fetch('/get-config');
            const config = await response.json();
            if (response.ok) {
                document.getElementById('rdp-server').value = config.rdpServer;
                document.getElementById('rdp-port').value = config.rdpPort;
                document.getElementById('rdp-user').value = config.rdpUser;
            }
        } catch (error) { showToast('No se pudo cargar la config existente.', true); }
    }

    mainForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const data = Object.fromEntries(new FormData(e.target).entries());
        if (!data.rdpServer || !data.rdpPort || !data.rdpUser) {
            return showToast("Servidor, Puerto y Usuario RDP son requeridos.", true);
        }
        showToast('Aplicando configuración...');
        try {
            const response = await fetch('/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
            const result = await response.json();
            showToast(result.message, !response.ok);
        } catch (error) { showToast(error.message, true); }
    });

    changePassForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const newPasswordInput = e.target.elements['new-admin-pass'];
        const confirmPasswordInput = e.target.elements['confirm-admin-pass'];
        if (newPasswordInput.value !== confirmPasswordInput.value) { return showToast('Las contraseñas no coinciden.', true); }
        showToast('Cambiando contraseña...');
        try {
            const response = await fetch('/change-admin-password', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ newPassword: newPasswordInput.value }),
            });
            const result = await response.json();
            showToast(result.message, !response.ok);
            if (response.ok) { changePassForm.reset(); closeModal(passwordModal); }
        } catch (error) { showToast(error.message, true); }
    });
    
    changeHostnameForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const newHostname = e.target.elements['new-hostname'].value;
        showToast('Cambiando hostname...');
        try {
            const response = await fetch('/change-hostname', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ newHostname }),
            });
            const result = await response.json();
            showToast(result.message, !response.ok);
            if (response.ok) { changeHostnameForm.reset(); closeModal(hostnameModal); }
        } catch (error) { showToast(error.message, true); }
    });

    rebootBtn.addEventListener('click', async () => {
        if (!confirm('¿Está seguro de que desea reiniciar este equipo?')) return;
        showToast('Enviando comando de reinicio...');
        try {
            const response = await fetch('/reboot', { method: 'POST' });
            const result = await response.json();
            showToast(result.message, !response.ok);
        } catch (error) { showToast(error.message, true); }
    });
});
EOF
# rdp.sh y .bash_profile
cat << 'EOF' > "${CONFIG_DEST_DIR}/rdp.sh"
#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then clear; echo "Error: Este script debe ser ejecutado con privilegios de root (sudo)."; sleep 20; exit 1; fi
while true; do
    cd /home/rdp; CONFIG_FILE="rdp.ini"
    if [ ! -f "$CONFIG_FILE" ]; then clear; echo "Error: $CONFIG_FILE no encontrado."; sleep 20; exit 1; fi
    source "$CONFIG_FILE"
    DECRYPT_PASSPHRASE='tu-frase-secreta-maestra-muy-segura'
    RDP_PASS=$(/usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -a -in "rdp.pass.enc" -pass pass:"$DECRYPT_PASSPHRASE" 2>/dev/null)
    if [ -z "$RDP_PASS" ]; then clear; echo "Error al descifrar la contraseña."; sleep 10; exit 1; fi
    RDP_CONNECTION_STRING="/v:$RDP_SERVER"
    if [ -n "$RDP_PORT" ] && [ "$RDP_PORT" != "3389" ]; then RDP_CONNECTION_STRING="$RDP_CONNECTION_STRING:$RDP_PORT"; fi
    RDP_CMD="/usr/bin/xfreerdp /u:$RDP_USER /p:$RDP_PASS $RDP_CONNECTION_STRING /f /cert:ignore"
    WRAPPER_SCRIPT="/tmp/rdp-wrapper.sh.$$"
    echo "#!/bin/sh" > "$WRAPPER_SCRIPT" && echo "$RDP_CMD" >> "$WRAPPER_SCRIPT" && /bin/chmod +x "$WRAPPER_SCRIPT"
    /usr/bin/xinit "$WRAPPER_SCRIPT" -- :1
    /bin/rm -f "$WRAPPER_SCRIPT"; unset RDP_PASS
    clear; echo "================================="; echo "        SESIÓN FINALIZADA"; echo "================================="; echo ""; echo "  [1] Volver a conectar"; echo "  [2] Apagar el equipo"; echo ""; echo "================================="
    read -n 1 -p "Seleccione una opción: " opcion; echo ""
    case $opcion in
        1) echo "Reconectando..."; sleep 1; continue ;;
        2) echo "Apagando el equipo..."; sleep 2; /sbin/shutdown -h now; break ;;
        *) echo "Reconectando..."; sleep 3; continue ;;
    esac
done; exit 0
EOF
cat << 'EOF' > "${CONFIG_DEST_DIR}/.bash_profile"
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if [ -f /home/rdp/rdp.sh ]; then /usr/bin/sudo /home/rdp/rdp.sh; fi
fi
EOF

# Asignar permisos y dependencias
log_info "Asignando permisos e instalando dependencias de Node.js..."
/bin/chown -R "${APP_USER}:${APP_USER}" "${CONFIG_DEST_DIR}"
/bin/chmod 755 "${CONFIG_DEST_DIR}/rdp.sh"
(cd "$APP_DIR" && /usr/bin/npm install --production --silent)

# Crear y habilitar el servicio Systemd
log_info "Creando y habilitando el servicio systemd..."
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Backend para RDP Client 2026
After=network.target
[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/node ${NODE_APP_FILE}
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=${SERVICE_NAME}
[Install]
WantedBy=multi-user.target
EOF
/bin/systemctl daemon-reload
/bin/systemctl enable "${SERVICE_NAME}.service"
/bin/systemctl restart "${SERVICE_NAME}.service"

# --- Finalización ---
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then SERVER_IP="<IP-NO-DETECTADA>"; fi

log_info "${GREEN}======================================================"
log_info "                    RDP Client 2026"
log_info "      Instalación y configuración completadas."
log_info "======================================================${NC}"
log_warn "Accede a la consola de administración en:"
log_warn "  http://${SERVER_IP}:3000"
log_info ""
log_info "Credenciales de acceso web por defecto:"
log_info "  Usuario:    rdpadmin"
log_info "  Contraseña: Rdpclient2026"
log_info ""
log_info "Una vez configurado desde la web, ${RED}REINICIA EL EQUIPO${NC} para ver todos los cambios."
echo ""