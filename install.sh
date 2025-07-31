#!/bin/bash

# --- Colores para la Salida ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Comprobación de seguridad
if [ "$(id -u)" -ne 0 ]; then
    clear
    echo -e "${RED}Error: Este script debe ser ejecutado con privilegios de root (sudo).${NC}"
    sleep 20
    exit 1
fi

while true; do
    cd /home/rdp
    CONFIG_FILE="rdp.ini"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        echo -e "${RED}Error: El archivo de configuración '$CONFIG_FILE' no se encuentra.${NC}"
        sleep 20
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    DECRYPT_PASSPHRASE='tu-frase-secreta-maestra-muy-segura'
    RDP_PASS=$(/usr/bin/openssl enc -d -aes-256-cbc -pbkdf2 -a -in "rdp.pass.enc" -pass pass:"$DECRYPT_PASSPHRASE" 2>/dev/null)
    
    if [ -z "$RDP_PASS" ]; then
        clear
        echo -e "${RED}Error al descifrar la contraseña. Verifique la configuración.${NC}"
        sleep 10
        exit 1
    fi
    
    SERVER_CONNECTION="/v:${RDP_SERVER}"
    if [ -n "$RDP_PORT" ] && [ "$RDP_PORT" != "3389" ]; then
        SERVER_CONNECTION="${SERVER_CONNECTION}:${RDP_PORT}"
    fi
    
    SECURITY_MODE=${RDP_SECURITY:-nla}
    LOG_FILE="/tmp/xrdp_run.log"

    # --- ¡LÓGICA DE EJECUCIÓN SIMPLIFICADA! ---
    # Se pasa el comando xfreerdp y sus argumentos directamente a xinit.
    # Se captura el código de salida de xinit.
    
    /usr/bin/xinit /usr/bin/xfreerdp /u:"$RDP_USER" /p:"$RDP_PASS" "$SERVER_CONNECTION" /f /cert:ignore /sec:$SECURITY_MODE -- :1 > "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    
    unset RDP_PASS
    clear
    
    if [ $EXIT_CODE -eq 0 ]; then
        # Éxito: El usuario cerró la sesión normalmente
        echo -e "${GREEN}=================================${NC}"
        echo -e "        ${GREEN}SESIÓN FINALIZADA${NC}"
        echo -e "${GREEN}=================================${NC}"
    else
        # Fracaso: xfreerdp terminó con un error
        echo -e "${RED}=================================================================${NC}"
        echo -e "          ${RED}ERROR DE CONEXIÓN (Código: $EXIT_CODE)${NC}"
        echo -e "${RED}=================================================================${NC}"
        echo ""
        echo "  El cliente RDP terminó con un error. Detalles:"
        echo -e "${YELLOW}-----------------------------------------------------------------${NC}"
        tail -n 15 "$LOG_FILE"
        echo -e "${YELLOW}-----------------------------------------------------------------${NC}"
        echo ""
        echo -e "  ${YELLOW}Causas comunes:${NC} Usuario/contraseña incorrectos, servidor no"
        echo -e "  disponible o problema de seguridad (pruebe NLA/RDP en la web)."
        echo ""
        echo -e "  Volviendo al menú en 20 segundos..."
        echo -e "${RED}=================================================================${NC}"
        sleep 20
    fi
    
    # Menú de opciones
    echo ""
    echo -e "  [${YELLOW}1${NC}] Volver a conectar"
    echo -e "  [${YELLOW}2${NC}] Apagar el equipo"
    echo ""
    echo "================================="
    read -n 1 -p "Seleccione una opción: " opcion
    echo ""
    case $opcion in
        1) echo "Reconectando..."; sleep 1; continue ;;
        2) echo "Apagando el equipo..."; sleep 2; /sbin/shutdown -h now; break ;;
        *) echo "Reconectando..."; sleep 3; continue ;;
    esac
done

exit 0