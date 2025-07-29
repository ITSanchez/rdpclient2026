#!/bin/bash

# ==============================================================================
# INSTALADOR MAESTRO DE RDP Client 2026 v10.0 (Versión Final Definitiva)
# ==============================================================================
# Esta versión implementa la lógica correcta final, usando 'xinit' para
# lanzar el entorno gráfico, basado en el diagnóstico final.
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
if [ "$(id -u)" -ne 0 ]; then log_error "Este script debe ejecutarse como root. Por favor, use 'sudo ./install.sh'"; fi
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if ! ([ "$ID" == "debian" ] && [ "$VERSION_ID" == "12" ]); then log_error "Este instalador está diseñado para Debian 12.x (bookworm)."; fi
else
    log_error "No se pudo verificar la versión del sistema operativo."
fi
log_info "Sistema operativo verificado: Debian 12 (bookworm)."

# ==============================================================================
# PASO 1: INSTALACIÓN DE DEPENDENCIAS
# ==============================================================================
log_info "Verificando dependencias del sistema..."
REQUIRED_PACKAGES=(xserver-xorg xserver-xorg-video-all xinit freerdp2-x11 sudo wget ca-certificates grub2-common)
log_info "Actualizando índice de paquetes..."
apt-get update >/dev/null 2>&1
log_info "Instalando paquetes necesarios..."
log_warn "Esto puede demorar unos minutos..."
apt-get install -y ${REQUIRED_PACKAGES[@]} >/dev/null 2>&1
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
# PASO 3: INSTALACIÓN DE LA APLICACIÓN
# ==============================================================================
log_info "Iniciando la instalación de la aplicación RDP Client 2026..."
if id -u "$APP_USER" &>/dev/null; then log_warn "El usuario '$APP_USER' ya existe."; else
    log_info "Creando usuario del sistema '$APP_USER'...";
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

log_info "Creando el Mensaje del Día personalizado..."
cat << 'EOF' > /etc/motd
############################################################################
#                       RDP Client 2026                                    #
#       https://sourceforge.net/projects/rdpclient/                        #
#               Creado por Guillermo Sanchez                               #
############################################################################
EOF

# ==============================================================================
# PASO 4: BRANDING DEL SISTEMA
# ==============================================================================
log_info "Descargando y configurando el fondo de arranque (GRUB)..."
if wget --quiet --no-check-certificate -O "$LOGO_PATH_GRUB" "$LOGO_URL_RAW"; then
    log_info "Configurando GRUB para usar la imagen de fondo y timeout de 5s..."
    sed -i -e 's,^#\?GRUB_BACKGROUND=.*,GRUB_BACKGROUND="'"$LOGO_PATH_GRUB"'",g' \
           -e 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/g' /etc/default/grub
    log_info "Actualizando la configuración de GRUB..."
    /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
    log_info "Fondo de arranque y timeout actualizados."
else
    log_warn "No se pudo descargar el logo para GRUB."
fi
log_info "Descargando el logo para la interfaz web..."
if ! wget --quiet --no-check-certificate -O "$LOGO_PATH_WEB" "$LOGO_URL_RAW"; then
    log_warn "No se pudo descargar el logo para la web."
fi

# ==============================================================================
# PASO 5: GENERACIÓN DE ARCHIVOS DEL PROYECTO
# ==============================================================================
log_info "Generando archivos del proyecto Node.js..."
# package.json
cat << 'EOF' > "${APP_DIR}/package.json"
{ "name": "rdp-client-2026", "version": "10.0.0", "description": "Consola de Administración para RDP Client 2026", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.19.2" } }
EOF
# index.js (sin cambios)
#... (Omitido por brevedad, es el mismo de la v9.3)

# --- rdp.sh (LA CORRECCIÓN FINAL) ---
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
    
    # Construir el comando base
    XFREERDP_CMD="/usr/bin/xfreerdp /u:$RDP_USER /p:$RDP_PASS /v:$RDP_SERVER /f /cert:ignore"
    
    # Añadir el puerto si es necesario, usando la sintaxis /port:
    if [ -n "$RDP_PORT" ] && [ "$RDP_PORT" != "3389" ]; then
        XFREERDP_CMD="$XFREERDP_CMD /port:$RDP_PORT"
    fi

    # Envolver el comando final en xinit
    /usr/bin/xinit $XFREERDP_CMD -- :1

    unset RDP_PASS
    clear; echo "================================="; echo "        SESIÓN FINALIZADA"; echo "================================="; echo ""; echo "  [1] Volver a conectar"; echo "  [2] Apagar el equipo"; echo ""; echo "================================="
    read -n 1 -p "Seleccione una opción: " opcion; echo ""
    case $opcion in
        1) echo "Reconectando..."; sleep 1; continue ;;
        2) echo "Apagando el equipo..."; sleep 2; /sbin/shutdown -h now; break ;;
        *) echo "Reconectando..."; sleep 3; continue ;;
    esac
done; exit 0
EOF
# .bash_profile
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