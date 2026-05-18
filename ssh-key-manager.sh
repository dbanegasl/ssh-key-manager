#!/usr/bin/env bash
# =============================================================================
# SSH Key Manager — Windows + WSL  v3.0
# Instala llaves SSH en múltiples servidores definidos en ~/.ssh/config
# Configuración externa en config.local.sh (nunca se sube al repo)
# =============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.local.sh"

# Variables de configuración (se cargan desde config.local.sh)
WIN_USERNAME=""
KEY_NAME="vsCODE"
SSH_USER=""
CONNECT_TIMEOUT=8

# Paths derivados (calculados en derive_paths() tras cargar config)
WIN_KEY=""
WIN_PRIV=""
WSL_KEY=""
WSL_PRIV=""
WIN_PRIV_TMP="/tmp/ssh_km_win_$$"
WIN_KEY_TMP="/tmp/ssh_km_win_pub_$$.pub"
WIN_AVAIL=0

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Arrays globales
SUCCESS=()
SKIPPED=()
FAILED=()
PARTIAL=()
HOSTS=()
HOSTS_DISPLAY=()

# =============================================================================
# Limpieza al salir
# =============================================================================
cleanup() { rm -f "$WIN_PRIV_TMP" "$WIN_KEY_TMP"; }
trap cleanup EXIT

# =============================================================================
# Calcular rutas desde las variables de configuración
# =============================================================================
derive_paths() {
    WIN_KEY="/mnt/c/Users/${WIN_USERNAME}/.ssh/${KEY_NAME}.pub"
    WIN_PRIV="/mnt/c/Users/${WIN_USERNAME}/.ssh/${KEY_NAME}"
    WSL_KEY="$HOME/.ssh/${KEY_NAME}.pub"
    WSL_PRIV="$HOME/.ssh/${KEY_NAME}"
}

# =============================================================================
# Cargar config.local.sh
# Retorna 0 si OK, 1 si falta o incompleta
# =============================================================================
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    derive_paths

    local missing=()
    [[ -z "$WIN_USERNAME" ]] && missing+=("WIN_USERNAME")
    [[ -z "$SSH_USER" ]]     && missing+=("SSH_USER")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}[CONFIG]${NC} Variables sin configurar en config.local.sh: ${missing[*]}"
        return 1
    fi
    return 0
}

# =============================================================================
# WIZARD DE CONFIGURACIÓN INICIAL
# =============================================================================
setup_wizard() {
    clear
    echo -e "${BOLD}${YELLOW}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║        SSH Key Manager — Configuración          ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "  ${YELLOW}Reconfiguración solicitada. Se sobreescribirá config.local.sh${NC}\n"
    else
        echo -e "  ${CYAN}No se encontró config.local.sh — iniciando configuración inicial.${NC}\n"
    fi

    # --- Paso 1: Usuario Windows ---
    echo -e "  ${BOLD}Paso 1/3 — Usuario de Windows${NC}"
    echo -e "  ${DIM}(ruta: /mnt/c/Users/<usuario>/.ssh/)${NC}\n"

    local win_users=()
    if [[ -d "/mnt/c/Users" ]]; then
        while IFS= read -r u; do
            [[ "$u" =~ ^(Public|Default.*|All\ Users|desktop\.ini)$ ]] && continue
            [[ -d "/mnt/c/Users/$u" ]] && win_users+=("$u")
        done < <(ls /mnt/c/Users/ 2>/dev/null)
    fi

    local chosen_win_user=""
    if [[ ${#win_users[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}No se detectaron usuarios en /mnt/c/Users/${NC}"
        echo -ne "  Ingresa tu usuario de Windows: "
        read -r chosen_win_user
    elif [[ ${#win_users[@]} -eq 1 ]]; then
        chosen_win_user="${win_users[0]}"
        echo -e "  Usuario detectado: ${GREEN}${chosen_win_user}${NC}"
        echo -ne "  ¿Correcto? [S/n]: "
        read -r confirm
        if [[ "${confirm,,}" == "n" ]]; then
            echo -ne "  Ingresa tu usuario de Windows: "
            read -r chosen_win_user
        fi
    else
        echo -e "  Usuarios detectados:\n"
        local i=1
        for u in "${win_users[@]}"; do
            echo -e "    ${CYAN}${i})${NC}  $u"
            (( i++ )) || true
        done
        echo -ne "\n  Selecciona número (o escribe el nombre): "
        read -r pick
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#win_users[@]} )); then
            chosen_win_user="${win_users[$((pick-1))]}"
        else
            chosen_win_user="$pick"
        fi
    fi

    # --- Paso 2: Nombre de la llave SSH ---
    echo -e "\n  ${BOLD}Paso 2/3 — Nombre del archivo de llave SSH${NC}"
    echo -e "  ${DIM}Busca <nombre>.pub y <nombre> (privada) en .ssh/  [default: vsCODE]${NC}\n"

    local wsl_keys=()
    while IFS= read -r f; do
        local base
        base="${f%.pub}"
        base="${base##*/}"
        wsl_keys+=("$base")
    done < <(ls "$HOME/.ssh/"*.pub 2>/dev/null)

    local chosen_key_name="vsCODE"
    if [[ ${#wsl_keys[@]} -gt 0 ]]; then
        echo -e "  Llaves encontradas en ~/.ssh/:\n"
        local i=1
        for k in "${wsl_keys[@]}"; do
            echo -e "    ${CYAN}${i})${NC}  $k"
            (( i++ )) || true
        done
        echo -ne "\n  Selecciona número o escribe el nombre [default: ${wsl_keys[0]}]: "
        read -r pick
        if [[ -z "$pick" ]]; then
            chosen_key_name="${wsl_keys[0]}"
        elif [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#wsl_keys[@]} )); then
            chosen_key_name="${wsl_keys[$((pick-1))]}"
        else
            chosen_key_name="$pick"
        fi
    else
        echo -ne "  Nombre de la llave [default: vsCODE]: "
        read -r pick
        [[ -n "$pick" ]] && chosen_key_name="$pick"
    fi

    # --- Paso 3: Usuario SSH del config ---
    echo -e "\n  ${BOLD}Paso 3/3 — Usuario SSH para filtrar hosts${NC}"
    echo -e "  ${DIM}Solo se procesarán hosts con  User = <este valor>  en ~/.ssh/config${NC}\n"

    local config_users=()
    if [[ -f "$HOME/.ssh/config" ]]; then
        while IFS= read -r u; do
            [[ "$u" == "git" ]] && continue
            config_users+=("$u")
        done < <(grep -i '^\s*User ' "$HOME/.ssh/config" | awk '{print $2}' | sort -u)
    fi

    local chosen_ssh_user=""
    if [[ ${#config_users[@]} -eq 0 ]]; then
        echo -ne "  Ingresa tu usuario SSH: "
        read -r chosen_ssh_user
    elif [[ ${#config_users[@]} -eq 1 ]]; then
        chosen_ssh_user="${config_users[0]}"
        echo -e "  Usuario detectado: ${GREEN}${chosen_ssh_user}${NC}"
        echo -ne "  ¿Correcto? [S/n]: "
        read -r confirm
        if [[ "${confirm,,}" == "n" ]]; then
            echo -ne "  Ingresa tu usuario SSH: "
            read -r chosen_ssh_user
        fi
    else
        echo -e "  Usuarios en ~/.ssh/config:\n"
        local i=1
        for u in "${config_users[@]}"; do
            echo -e "    ${CYAN}${i})${NC}  $u"
            (( i++ )) || true
        done
        echo -ne "\n  Selecciona número o escribe el nombre: "
        read -r pick
        if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#config_users[@]} )); then
            chosen_ssh_user="${config_users[$((pick-1))]}"
        else
            chosen_ssh_user="$pick"
        fi
    fi

    # --- Confirmar y guardar ---
    echo -e "\n  ${BOLD}──────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Resumen de configuración:${NC}\n"
    echo -e "    Usuario Windows : ${GREEN}${chosen_win_user}${NC}"
    echo -e "    Nombre de llave : ${GREEN}${chosen_key_name}${NC}"
    echo -e "    Usuario SSH     : ${GREEN}${chosen_ssh_user}${NC}"
    echo -e "\n    WIN key  → /mnt/c/Users/${chosen_win_user}/.ssh/${chosen_key_name}.pub"
    echo -e "    WSL key  → ~/.ssh/${chosen_key_name}.pub"
    echo -e "  ${BOLD}──────────────────────────────────────────────${NC}"
    echo -ne "\n  ¿Guardar configuración? [S/n]: "
    read -r confirm

    if [[ "${confirm,,}" == "n" ]]; then
        echo -e "\n  ${YELLOW}Configuración cancelada.${NC}\n"
        return 1
    fi

    cat > "$CONFIG_FILE" <<EOF
#!/usr/bin/env bash
# =============================================================================
# SSH Key Manager — Configuración local
# Generado automáticamente el $(date '+%Y-%m-%d %H:%M').
# Este archivo está en .gitignore — no se sube al repositorio.
# Para reconfigurar: ejecuta el script y usa la opción 6.
# =============================================================================

# Usuario de Windows (ruta /mnt/c/Users/<WIN_USERNAME>/.ssh/)
WIN_USERNAME="${chosen_win_user}"

# Nombre del archivo de llave SSH (sin extensión)
KEY_NAME="${chosen_key_name}"

# Usuario SSH para filtrar hosts desde ~/.ssh/config
SSH_USER="${chosen_ssh_user}"

# Timeout de conexión en segundos
CONNECT_TIMEOUT=8
EOF

    echo -e "\n  ${GREEN}✓ Configuración guardada en config.local.sh${NC}\n"
    sleep 1

    source "$CONFIG_FILE"
    derive_paths
    return 0
}

# =============================================================================
# Verificaciones previas (llaves y config SSH)
# =============================================================================
preflight_checks() {
    echo -e "\n${BOLD}  Verificando prerequisitos...${NC}\n"
    local ok=1

    if [[ ! -f "$WSL_KEY" ]]; then
        echo -e "  ${RED}[FAIL]${NC} Llave WSL no encontrada: $WSL_KEY"
        echo -e "         Genera una con: ssh-keygen -t ed25519 -f $WSL_PRIV"
        ok=0
    else
        echo -e "  ${GREEN}[OK]${NC}   Llave WSL:     $WSL_KEY"
    fi

    if [[ ! -f "$WIN_KEY" ]]; then
        echo -e "  ${YELLOW}[WARN]${NC} Llave Windows no encontrada: $WIN_KEY"
        echo -e "         ${DIM}(solo se instalará la llave WSL)${NC}"
    else
        # Copiar AMBOS archivos a /tmp con permisos correctos
        if ! cp "$WIN_PRIV" "$WIN_PRIV_TMP" 2>/dev/null; then
            echo -e "  ${RED}[FAIL]${NC} No se pudo copiar llave privada de Windows"
            ok=0
        elif ! cp "$WIN_KEY" "$WIN_KEY_TMP" 2>/dev/null; then
            echo -e "  ${RED}[FAIL]${NC} No se pudo copiar llave pública de Windows"
            ok=0
        else
            # Convertir CRLF → LF (problema común con claves de Windows)
            dos2unix "$WIN_PRIV_TMP" 2>/dev/null || sed -i 's/\r$//' "$WIN_PRIV_TMP"
            dos2unix "$WIN_KEY_TMP" 2>/dev/null || sed -i 's/\r$//' "$WIN_KEY_TMP"
            
            # Establecer permisos correctos
            chmod 600 "$WIN_PRIV_TMP"
            chmod 644 "$WIN_KEY_TMP"
            
            # Validar que la clave sea válida (usar .pub — no requiere passphrase)
            if ssh-keygen -l -f "$WIN_KEY_TMP" >/dev/null 2>&1; then
                WIN_AVAIL=1
                echo -e "  ${GREEN}[OK]${NC}   Llave Windows: $WIN_KEY (copiada y procesada)"
            else
                echo -e "  ${RED}[FAIL]${NC} Llave Windows inválida o corrupta"
                echo -e "         Verifica el archivo: $WIN_KEY"
                ok=0
            fi
        fi
    fi

    if [[ ! -f "$HOME/.ssh/config" ]]; then
        echo -e "  ${RED}[FAIL]${NC} No se encontró ~/.ssh/config"
        ok=0
    else
        echo -e "  ${GREEN}[OK]${NC}   Config SSH:    ~/.ssh/config"
    fi

    if [[ $ok -eq 0 ]]; then
        echo -e "\n  ${RED}Prerequisitos fallidos. Abortando.${NC}\n"
        exit 1
    fi
    echo ""
}

# =============================================================================
# Parsear ~/.ssh/config — extrae hosts filtrando por SSH_USER
# =============================================================================
parse_config() {
    local config="$HOME/.ssh/config"
    local cur_alias="" cur_hostname="" cur_port="22" cur_user=""

    _flush() {
        if [[ -n "$cur_alias" && "$cur_user" == "$SSH_USER" && -n "$cur_hostname" ]]; then
            HOSTS+=("${cur_alias}|${cur_hostname}|${cur_port}")
            HOSTS_DISPLAY+=("$(printf "%-42s \033[2m%s:%s\033[0m" "$cur_alias" "$cur_hostname" "$cur_port")")
        fi
    }

    while IFS= read -r line; do
        local key val
        read -r key val <<< "$line"
        case "${key,,}" in
            host)     _flush; cur_alias="$val"; cur_hostname=""; cur_port="22"; cur_user="" ;;
            hostname) cur_hostname="$val" ;;
            port)     cur_port="$val"     ;;
            user)     cur_user="$val"     ;;
        esac
    done < "$config"
    _flush
}

# =============================================================================
# Verificar conectividad TCP
# =============================================================================
check_port() {
    local host="$1" port="$2"
    timeout "$CONNECT_TIMEOUT" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
}

# =============================================================================
# Verificar si una llave ya da acceso sin contraseña (BatchMode)
# =============================================================================
key_installed() {
    local priv="$1" alias="$2"
    timeout 12 ssh \
        -i "$priv" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        "$alias" exit 2>/dev/null
}

# =============================================================================
# Instalar ambas llaves en un servidor
# =============================================================================
install_key() {
    local alias="$1"
    local r_win=0 r_wsl=0
    local win_skip=0 wsl_skip=0
    local host="" port=""

    for entry in "${HOSTS[@]}"; do
        if [[ "${entry%%|*}" == "$alias" ]]; then
            local rest="${entry#*|}"
            host="${rest%%|*}"
            port="${rest#*|}"
            break
        fi
    done

    echo ""
    echo -e "  ${BOLD}┌─────────────────────────────────────────────┐${NC}"
    printf  "  ${BOLD}│${NC}  ${CYAN}%-43s${NC}${BOLD}│${NC}\n" "$alias"
    printf  "  ${BOLD}│${NC}  ${DIM}%-43s${NC}${BOLD}│${NC}\n" "${host}:${port}"
    echo -e "  ${BOLD}└─────────────────────────────────────────────┘${NC}"

    echo -ne "  Conectividad ${host}:${port}... "
    if ! check_port "$host" "$port"; then
        echo -e "${RED}SIN RESPUESTA${NC}"
        FAILED+=("$alias  [sin conexión]")
        return
    fi
    echo -e "${GREEN}OK${NC}"

    # Llave Windows
    if [[ $WIN_AVAIL -eq 1 ]]; then
        echo -ne "  ${BLUE}[WIN]${NC} Verificando... "
        if key_installed "$WIN_PRIV_TMP" "$alias"; then
            echo -e "${CYAN}ya instalada${NC}"; win_skip=1
        else
            echo -e "${YELLOW}instalando...${NC}"
            # Verificar que el archivo temporal todavía existe (puede haberse limpiado)
            if [[ ! -f "$WIN_KEY_TMP" ]]; then
                cp "$WIN_KEY" "$WIN_KEY_TMP" 2>/dev/null && \
                { dos2unix "$WIN_KEY_TMP" 2>/dev/null || sed -i 's/\r$//' "$WIN_KEY_TMP"; } && \
                chmod 644 "$WIN_KEY_TMP"
            fi
            ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout="$CONNECT_TIMEOUT" \
                -o ServerAliveInterval=10 -i "$WIN_KEY_TMP" "$alias"
            r_win=$?
            [[ $r_win -eq 0 ]] \
                && echo -e "  ${BLUE}[WIN]${NC} ${GREEN}Instalada correctamente${NC}" \
                || echo -e "  ${BLUE}[WIN]${NC} ${RED}Error (código $r_win)${NC}"
        fi
    else
        echo -e "  ${BLUE}[WIN]${NC} ${DIM}Omitida (llave no disponible)${NC}"
    fi

    # Llave WSL
    echo -ne "  ${GREEN}[WSL]${NC} Verificando... "
    if key_installed "$WSL_PRIV" "$alias"; then
        echo -e "${CYAN}ya instalada${NC}"; wsl_skip=1
    else
        echo -e "${YELLOW}instalando...${NC}"
        ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
            -o ServerAliveInterval=10 -i "$WSL_KEY" "$alias"
        r_wsl=$?
        [[ $r_wsl -eq 0 ]] \
            && echo -e "  ${GREEN}[WSL]${NC} ${GREEN}Instalada correctamente${NC}" \
            || echo -e "  ${GREEN}[WSL]${NC} ${RED}Error (código $r_wsl)${NC}"
    fi

    # Clasificar resultado
    local win_ok=1 wsl_ok=1
    [[ $WIN_AVAIL -eq 1 && $r_win -ne 0 ]] && win_ok=0
    [[ $r_wsl -ne 0 ]] && wsl_ok=0

    if [[ $wsl_ok -eq 0 ]]; then
        # WSL falló → fallo real
        local detail=" [wsl=${r_wsl}]"
        [[ $WIN_AVAIL -eq 1 ]] && detail=" [win=${r_win} wsl=${r_wsl}]"
        FAILED+=("${alias}${detail}")
    elif [[ $WIN_AVAIL -eq 1 && $win_ok -eq 0 ]]; then
        # WSL OK pero WIN falló → parcial
        PARTIAL+=("$alias  ${DIM}[WIN no instalada]${NC}")
    elif [[ $win_skip -eq 1 && $wsl_skip -eq 1 ]]; then
        SKIPPED+=("$alias")
    else
        SUCCESS+=("$alias")
    fi
}

# =============================================================================
# Resumen final
# =============================================================================
print_summary() {
    local total=$(( ${#SUCCESS[@]} + ${#SKIPPED[@]} + ${#PARTIAL[@]} + ${#FAILED[@]} ))
    echo ""
    echo -e "  ${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}║           RESUMEN  FINAL                 ║${NC}"
    echo -e "  ${BOLD}╚══════════════════════════════════════════╝${NC}\n"

    printf "  ${GREEN}Instaladas ahora   (%d)${NC}\n" "${#SUCCESS[@]}"
    for s in "${SUCCESS[@]}"; do echo -e "    ${GREEN}✓${NC} $s"; done

    echo ""
    printf "  ${CYAN}Ya tenían la llave  (%d)${NC}\n" "${#SKIPPED[@]}"
    for s in "${SKIPPED[@]}"; do echo -e "    ${CYAN}↷${NC} $s"; done

    echo ""
    printf "  ${YELLOW}WSL ok / WIN falló (%d)${NC}\n" "${#PARTIAL[@]}"
    for p in "${PARTIAL[@]}"; do echo -e "    ${YELLOW}~${NC} $p"; done

    echo ""
    printf "  ${RED}Fallidas           (%d)${NC}\n" "${#FAILED[@]}"
    for f in "${FAILED[@]}"; do echo -e "    ${RED}✗${NC} $f"; done

    echo ""
    echo -e "  Total: ${BOLD}${total}${NC}  |  ${GREEN}${#SUCCESS[@]} nuevas${NC}  ${CYAN}${#SKIPPED[@]} skip${NC}  ${YELLOW}${#PARTIAL[@]} parcial${NC}  ${RED}${#FAILED[@]} fallo${NC}"
    echo ""
}

# =============================================================================
# Listar servidores
# =============================================================================
show_servers() {
    echo ""
    printf "  ${BOLD}  #   %-42s %s${NC}\n" "Alias" "Host:Puerto"
    echo -e "  ${DIM}  ─   ──────────────────────────────────────   ───────────────────${NC}"
    local i=1
    for h in "${HOSTS_DISPLAY[@]}"; do
        printf "  ${CYAN}%3d)${NC}  %b\n" "$i" "$h"
        (( i++ )) || true
    done
    echo ""
}

# =============================================================================
# Selección interactiva (soporta rangos: 1 3 5-8 o "all")
# =============================================================================
pick_servers() {
    show_servers
    echo -e "  ${BOLD}Ingresa números separados por espacios/comas, rangos o 'all'${NC}"
    echo -e "  ${DIM}Ejemplo: 1 3 5-8  |  2,4,7  |  all${NC}"
    echo -ne "\n  > "
    read -r selection

    SELECTED_INDEXES=()

    if [[ "${selection,,}" == "all" ]]; then
        for (( i=1; i<=${#HOSTS[@]}; i++ )); do SELECTED_INDEXES+=("$i"); done
        return
    fi

    for token in $(echo "$selection" | tr ',' ' '); do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for (( n=${BASH_REMATCH[1]}; n<=${BASH_REMATCH[2]}; n++ )); do
                SELECTED_INDEXES+=("$n")
            done
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
            SELECTED_INDEXES+=("$token")
        fi
    done
}

# =============================================================================
# Verificar estado de llaves sin instalar (dry-run)
# =============================================================================
check_status() {
    echo ""
    echo -e "  ${BOLD}Estado de llaves en ${#HOSTS[@]} servidores...${NC}"
    echo -e "  ${DIM}(puede tardar según cantidad de hosts)${NC}\n"
    printf "  ${BOLD}  #   %-42s  %-10s  %-10s${NC}\n" "Alias" "WIN" "WSL"
    echo -e "  ${DIM}  ─   ──────────────────────────────────────  ──────────  ──────────${NC}"

    local i=1
    for entry in "${HOSTS[@]}"; do
        local alias="${entry%%|*}"
        local rest="${entry#*|}"
        local host="${rest%%|*}"
        local port="${rest#*|}"

        printf "  ${CYAN}%3d)${NC}  %-42s  " "$i" "$alias"

        if ! check_port "$host" "$port" 2>/dev/null; then
            echo -e "${RED}sin conexión${NC}"
        else
            local win_st wsl_st
            if [[ $WIN_AVAIL -eq 1 ]]; then
                key_installed "$WIN_PRIV_TMP" "$alias" 2>/dev/null \
                    && win_st="${GREEN}✓ OK      ${NC}" || win_st="${RED}✗ NO      ${NC}"
            else
                win_st="${DIM}n/a       ${NC}"
            fi
            key_installed "$WSL_PRIV" "$alias" 2>/dev/null \
                && wsl_st="${GREEN}✓ OK${NC}" || wsl_st="${RED}✗ NO${NC}"
            echo -e "${win_st}  ${wsl_st}"
        fi
        (( i++ )) || true
    done
    echo ""
}

# =============================================================================
# Mostrar configuración activa
# =============================================================================
show_config() {
    echo ""
    echo -e "  ${BOLD}Configuración activa${NC}  ${DIM}(${CONFIG_FILE})${NC}\n"
    echo -e "    Usuario Windows : ${CYAN}${WIN_USERNAME}${NC}"
    echo -e "    Nombre de llave : ${CYAN}${KEY_NAME}${NC}"
    echo -e "    Usuario SSH     : ${CYAN}${SSH_USER}${NC}"
    echo -e "    Timeout         : ${CYAN}${CONNECT_TIMEOUT}s${NC}"
    echo ""
    echo -e "    WIN key  → ${DIM}${WIN_KEY}${NC}"
    echo -e "    WSL key  → ${DIM}${WSL_KEY}${NC}"
    echo ""
    local win_exists wsl_exists
    [[ -f "$WIN_KEY" ]] && win_exists="${GREEN}existe${NC}" || win_exists="${RED}no encontrada${NC}"
    [[ -f "$WSL_KEY" ]] && wsl_exists="${GREEN}existe${NC}" || wsl_exists="${RED}no encontrada${NC}"
    echo -e "    WIN .pub : ${win_exists}    WSL .pub : ${wsl_exists}"
    
    if [[ $WIN_AVAIL -eq 1 ]]; then
        echo -e "\n    ${BLUE}[WIN]${NC} Llave privada procesada y disponible en memoria"
    fi
    echo ""
}

# =============================================================================
# Reparar permisos SSH en servidores remotos
# =============================================================================
fix_ssh_permissions() {
    local targets=()

    echo -e "\n  ${BOLD}¿En qué servidores aplicar la reparación?${NC}"
    echo -e "  ${DIM}Corrige: permisos del home, ~/.ssh/ y deduplica authorized_keys${NC}\n"
    echo -e "    ${CYAN}1)${NC}  Todos los servidores  ${DIM}(${#HOSTS[@]} hosts)${NC}"
    echo -e "    ${CYAN}2)${NC}  Seleccionar servidores"
    echo -ne "\n  Opción: "
    read -r sub

    if [[ "$sub" == "1" ]]; then
        for entry in "${HOSTS[@]}"; do targets+=("${entry%%|*}"); done
    elif [[ "$sub" == "2" ]]; then
        SELECTED_INDEXES=()
        pick_servers
        for idx in "${SELECTED_INDEXES[@]}"; do
            (( idx >= 1 && idx <= ${#HOSTS[@]} )) && targets+=("${HOSTS[$((idx-1))]%%|*}")
        done
    else
        echo -e "  ${YELLOW}Cancelado.${NC}"; return
    fi

    [[ ${#targets[@]} -eq 0 ]] && echo -e "  ${YELLOW}No se seleccionó ningún servidor.${NC}" && return

    # Script remoto: corregir permisos y deduplicar authorized_keys
    local remote_cmd
    remote_cmd=$(cat <<'REMOTE'
result=""
# Permisos del home
home_perm=$(stat -c "%a" ~ 2>/dev/null)
if (( (8#$home_perm & 8#020) != 0 )); then
    chmod g-w ~ && result+="home:corregido($home_perm→$(stat -c '%a' ~)) "
else
    result+="home:ok($home_perm) "
fi
# Permisos de ~/.ssh
chmod 700 ~/.ssh 2>/dev/null && result+="ssh_dir:ok "
# Permisos de authorized_keys
if [[ -f ~/.ssh/authorized_keys ]]; then
    chmod 600 ~/.ssh/authorized_keys
    before=$(wc -l < ~/.ssh/authorized_keys)
    sort -u ~/.ssh/authorized_keys > /tmp/.ak_dedup_$$ && mv /tmp/.ak_dedup_$$ ~/.ssh/authorized_keys
    after=$(wc -l < ~/.ssh/authorized_keys)
    result+="keys:${before}→${after}unicas"
else
    result+="keys:no_existe"
fi
echo "$result"
REMOTE
)

    echo ""
    printf "  ${BOLD}  %-44s %-14s %s${NC}\n" "Alias" "Auth" "Resultado"
    echo -e "  ${DIM}  ──────────────────────────────────────────   ─────────────  ─────────────────────────${NC}"

    local fixed=0 failed=0
    for alias in "${targets[@]}"; do
        printf "  ${CYAN}  %-44s${NC}" "$alias"

        # Intentar con llave WSL (sin contraseña)
        local out
        if out=$(timeout 12 ssh \
                -i "$WSL_PRIV" \
                -o BatchMode=yes \
                -o StrictHostKeyChecking=no \
                -o ConnectTimeout="$CONNECT_TIMEOUT" \
                "$alias" "$remote_cmd" 2>/dev/null); then
            echo -e "${DIM}llave${NC}     ${GREEN}${out}${NC}"
            (( fixed++ )) || true
        else
            # Fallback: contraseña (interactivo)
            echo -e "${YELLOW}contraseña${NC}"
            if ssh \
                    -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=15 \
                    "$alias" "$remote_cmd"; then
                (( fixed++ )) || true
            else
                echo -e "    ${RED}✗ No se pudo conectar${NC}"
                (( failed++ )) || true
            fi
        fi
    done

    echo ""
    echo -e "  ${BOLD}Resultado:${NC}  ${GREEN}${fixed} reparados${NC}  ${RED}${failed} fallidos${NC}\n"
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
main_menu() {
    while true; do
        echo -e "\n${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}  ║         SSH Key Manager  —  WIN + WSL            ║${NC}"
        echo -e "${BOLD}  ╚══════════════════════════════════════════════════╝${NC}\n"
        echo -e "    ${CYAN}1)${NC}  Instalar en ${BOLD}todos${NC} los servidores  ${DIM}(${#HOSTS[@]} hosts)${NC}"
        echo -e "    ${CYAN}2)${NC}  Instalar en servidores ${BOLD}seleccionados${NC}"
        echo -e "    ${CYAN}3)${NC}  Ver lista de servidores"
        echo -e "    ${CYAN}4)${NC}  ${BOLD}Verificar estado${NC} WIN/WSL ${DIM}(dry-run)${NC}"
        echo -e "    ${CYAN}5)${NC}  Ver configuración activa"
        echo -e "    ${CYAN}6)${NC}  ${YELLOW}Reconfigurar${NC} ${DIM}(lanzar wizard)${NC}"
        echo -e "    ${CYAN}7)${NC}  ${BOLD}Reparar permisos SSH${NC} ${DIM}(home, ~/.ssh, dedup keys)${NC}"
        echo -e "    ${CYAN}0)${NC}  Salir"
        echo ""
        echo -ne "  Opción: "
        read -r opt

        SUCCESS=(); SKIPPED=(); FAILED=(); PARTIAL=()

        case "$opt" in
            1)
                echo -e "\n  ${YELLOW}Procesando ${#HOSTS[@]} servidores...${NC}"
                for entry in "${HOSTS[@]}"; do install_key "${entry%%|*}"; done
                print_summary
                ;;
            2)
                SELECTED_INDEXES=()
                pick_servers
                if [[ ${#SELECTED_INDEXES[@]} -eq 0 ]]; then
                    echo -e "\n  ${YELLOW}No se seleccionó ningún servidor.${NC}"
                    continue
                fi
                echo -e "\n  ${YELLOW}Procesando ${#SELECTED_INDEXES[@]} servidor(es)...${NC}"
                for idx in "${SELECTED_INDEXES[@]}"; do
                    if (( idx >= 1 && idx <= ${#HOSTS[@]} )); then
                        install_key "${HOSTS[$((idx-1))]%%|*}"
                    else
                        echo -e "  ${RED}Número inválido: $idx${NC}"
                    fi
                done
                print_summary
                ;;
            3) show_servers ;;
            4) check_status ;;
            5) show_config  ;;
            6)
                setup_wizard
                HOSTS=(); HOSTS_DISPLAY=()
                parse_config
                preflight_checks
                ;;
            7) fix_ssh_permissions ;;
            0)
                echo -e "\n  ${GREEN}Hasta luego.${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n  ${RED}Opción inválida. Usa 0-7.${NC}"
                ;;
        esac
    done
}

# =============================================================================
# INICIO
# =============================================================================
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║     SSH Key Manager  —  Windows + WSL  v3.0      ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Cargar config — si falta o incompleta, lanzar wizard automáticamente
if ! load_config; then
    setup_wizard || exit 1
fi

preflight_checks
parse_config

if [[ ${#HOSTS[@]} -eq 0 ]]; then
    echo -e "  ${RED}No se encontraron hosts con User=${SSH_USER} en ~/.ssh/config${NC}"
    echo -e "  ${DIM}Verifica SSH_USER en config.local.sh (opción 6 para reconfigurar)${NC}\n"
    exit 1
fi

echo -e "  ${GREEN}${#HOSTS[@]} servidores encontrados${NC}  ${DIM}(User=${SSH_USER})${NC}\n"

main_menu
