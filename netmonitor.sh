#!/usr/bin/env bash
# ==============================================================================
# SISTEMA DE MONITORAMENTO DE REDE LOCAL (RETRO NET-WATCH v1.0)
# Arquivo: netmonitor.sh
# Desenvolvido para redes locais Linux (Ubuntu, Linux Mint, Debian)
# Operação 100% autônoma e offline.
# ==============================================================================

# Forçar localização neutra para saídas previsíveis de comandos como ping
export LC_ALL=C

# Diretório base do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/hosts.conf"
SETTINGS_FILE="${SCRIPT_DIR}/settings.conf"
TMP_DIR="/dev/shm/netwatch_$$"

# Criação de diretório temporário em memória RAM (se disponível) ou /tmp
if [ ! -d "/dev/shm" ] || [ ! -w "/dev/shm" ]; then
    TMP_DIR="/tmp/netwatch_$$"
fi
mkdir -p "$TMP_DIR"

# ------------------------------------------------------------------------------
# TRATAMENTO DE ENCERRAMENTO E LIMPEZA
# ------------------------------------------------------------------------------
cleanup() {
    # Restaura o cursor e atributos normais do terminal
    tput cnorm 2>/dev/null || printf '\033[?25h'
    printf '\033[0m'
    # Remove arquivos temporários
    rm -rf "$TMP_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# VERIFICAÇÃO E INSTALAÇÃO DE PRÉ-REQUISITOS (OFFLINE FIRST)
# ------------------------------------------------------------------------------
verificar_pre_requisitos() {
    local pacotes_faltando=()
    local comandos=("ping:iputils-ping" "awk:gawk" "sed:sed" "grep:grep" "tput:ncurses-bin" "ip:iproute2")

    for item in "${comandos[@]}"; do
        local cmd="${item%%:*}"
        local pkg="${item##*:}"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            pacotes_faltando+=("$pkg")
        fi
    done

    if [ ${#pacotes_faltando[@]} -gt 0 ]; then
        echo "================================================================"
        echo "  [AVISO DO SISTEMA] Pré-requisitos essenciais não encontrados: "
        echo "  ${pacotes_faltando[*]}"
        echo "================================================================"
        echo "Tentando instalar dependências locais via gerenciador de pacotes..."
        
        if command -v apt-get >/dev/null 2>&1; then
            if [ "$EUID" -ne 0 ]; then
                sudo apt-get update -qq 2>/dev/null && sudo apt-get install -y "${pacotes_faltando[@]}"
            else
                apt-get update -qq 2>/dev/null && apt-get install -y "${pacotes_faltando[@]}"
            fi
        fi

        # Validação pós-tentativa
        for item in "${comandos[@]}"; do
            local cmd="${item%%:*}"
            if ! command -v "$cmd" >/dev/null 2>&1; then
                echo "ERRO CRÍTICO: Não foi possível disponibilizar o comando '$cmd'."
                echo "Em modo offline, instale o pacote correspondente via .deb ou mídia local."
                exit 1
            fi
        done
        echo "Instalação concluída com sucesso! Iniciando sistema..."
        sleep 1
    fi
}

# ------------------------------------------------------------------------------
# CONFIGURAÇÕES E TEMAS VISUAIS RETRÔ
# ------------------------------------------------------------------------------
carregar_configuracoes() {
    THEME="green"         # green (Fósforo Verde), amber (Âmbar CRT), classic (DOS/ANSI)
    REFRESH_RATE=10       # Segundos entre varreduras contínuas (padrão: 10s)
    BEEP_ON_CHANGE=0      # 1 para alerta sonoro do terminal em mudança de status
    AUTO_DISCOVERY=1      # 1 para autodescoberta contínua periódica de novas máquinas na rede
    
    if [ -f "$SETTINGS_FILE" ]; then
        # shellcheck source=/dev/null
        source "$SETTINGS_FILE"
    fi
    aplicar_tema
}

salvar_configuracoes() {
    cat <<EOF > "$SETTINGS_FILE"
# Configurações do RETRO NET-WATCH
THEME="${THEME}"
REFRESH_RATE=${REFRESH_RATE}
BEEP_ON_CHANGE=${BEEP_ON_CHANGE}
AUTO_DISCOVERY=${AUTO_DISCOVERY}
EOF
}

aplicar_tema() {
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    BLINK=$'\033[5m'

    case "$THEME" in
        amber)
            # Monocromático Âmbar (estilo DEC VT220 / fósforo âmbar)
            C_PRIMARY=$'\033[38;5;214m'
            C_BRIGHT=$'\033[38;5;220m'
            C_DIM=$'\033[38;5;130m'
            C_ONLINE=$'\033[38;5;220m'
            C_OFFLINE=$'\033[38;5;130m'
            C_BORDER=$'\033[38;5;208m'
            C_ACCENT=$'\033[38;5;226m'
            THEME_NAME="Âmbar CRT"
            ;;
        classic)
            # Clássico ANSI / DOS (Ciano, Verde, Vermelho)
            C_PRIMARY=$'\033[1;36m'
            C_BRIGHT=$'\033[1;37m'
            C_DIM=$'\033[0;37m'
            C_ONLINE=$'\033[1;32m'
            C_OFFLINE=$'\033[1;31m'
            C_BORDER=$'\033[1;34m'
            C_ACCENT=$'\033[1;33m'
            THEME_NAME="IBM DOS"
            ;;
        *)
            # Padrão: Fósforo Verde (Green CRT / Matrix Terminal)
            C_PRIMARY=$'\033[38;5;46m'
            C_BRIGHT=$'\033[38;5;82m'
            C_DIM=$'\033[38;5;28m'
            C_ONLINE=$'\033[38;5;46m'
            C_OFFLINE=$'\033[38;5;196m'
            C_BORDER=$'\033[38;5;34m'
            C_ACCENT=$'\033[38;5;118m'
            THEME="green"
            THEME_NAME="Fósforo Verde"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# DETECÇÃO DE TOPOLOGIA DA REDE LOCAL E AUTODESCOBERTA
# ------------------------------------------------------------------------------
detectar_configuracao_rede() {
    # 1. Identificar interface de saída conectada ao roteador / gateway
    NET_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    if [ -z "$NET_IFACE" ]; then
        NET_IFACE=$(ip -o -4 addr show up 2>/dev/null | awk -F': ' '$2 !~ /^(lo|docker|br-|veth)/ {print $2; exit}')
    fi

    # 2. IP do Gateway da rede local
    NET_GW=$(ip route show default dev "$NET_IFACE" 2>/dev/null | awk '/default/ {print $3}' | head -n 1)
    [ -z "$NET_GW" ] && NET_GW=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -n 1)

    # 3. IP local desta máquina
    LOCAL_IP=$(ip -o -4 addr show dev "$NET_IFACE" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 | head -n 1)
    [ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')

    # 4. CIDR e prefixo da sub-rede local (ex: 192.168.15.0/24)
    NET_CIDR=$(ip route show dev "$NET_IFACE" proto kernel scope link 2>/dev/null | awk '{print $1}' | head -n 1)
    if [ -z "$NET_CIDR" ]; then
        NET_CIDR=$(ip route show dev "$NET_IFACE" scope link 2>/dev/null | awk '{print $1}' | head -n 1)
    fi
    if [ -z "$NET_CIDR" ] && [ -n "$LOCAL_IP" ]; then
        NET_CIDR="$(echo "$LOCAL_IP" | cut -d'.' -f1-3).0/24"
    fi
    NET_PREFIX=$(echo "$LOCAL_IP" | cut -d'.' -f1-3)
}

resolver_nome_dispositivo() {
    local ip="$1"
    local hint_name="$2"

    if [ "$ip" = "$NET_GW" ]; then
        echo "Roteador Gateway Principal"
        return
    fi
    if [ "$ip" = "$LOCAL_IP" ]; then
        echo "Esta Maquina Local (${HOSTNAME:-Linux})"
        return
    fi

    # Se hint_name foi fornecido (ex: via nmap)
    if [ -n "$hint_name" ] && [ "$hint_name" != "_gateway" ] && [ "$hint_name" != "$ip" ]; then
        echo "$hint_name"
        return
    fi

    # Tenta resolução local via getent hosts
    local hname
    hname=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -n 1)
    if [ -n "$hname" ] && [ "$hname" != "_gateway" ] && [ "$hname" != "$ip" ]; then
        echo "$hname"
        return
    fi

    echo "Dispositivo Rede Local ($ip)"
}

descobrir_maquinas_rede() {
    local modo_silencioso="${1:-0}"
    detectar_configuracao_rede

    if [ -z "$NET_IFACE" ] || [ -z "$LOCAL_IP" ]; then
        [ "$modo_silencioso" -eq 0 ] && echo "Aviso: Nenhuma interface de rede local ativa detectada."
        return 1
    fi

    local metodo_scan="Ping Paralelo Nativo (100% Offline)"
    local ips_descobertos=()
    declare -A map_hints

    if [ "$modo_silencioso" -eq 0 ]; then
        printf "%s=== VARREDURA E AUTODESCOBERTA NA REDE LOCAL ===%s\n\n" "${C_ACCENT}" "${RESET}"
        printf "%s Sub-rede alvo: %s  •  Interface: %s%s\n" "${C_BRIGHT}" "${NET_CIDR:-LAN}" "${NET_IFACE}" "${RESET}"
        printf "%s Varrendo a rede local em busca de máquinas ativas... Aguarde.%s\n\n" "${C_DIM}" "${RESET}"
    fi

    # 1. Varredura nativa em Bash puro (dispara pings paralelos para popular tabela ARP do kernel)
    if [ -n "$NET_PREFIX" ]; then
        for i in $(seq 1 254); do
            ping -n -c 1 -W 1 "${NET_PREFIX}.${i}" >/dev/null 2>&1 &
        done
        wait 2>/dev/null
    fi

    # 2. Se nmap estiver disponível, aproveita para coletar nomes resolvidos
    if command -v nmap >/dev/null 2>&1 && [ -n "$NET_CIDR" ]; then
        metodo_scan="Nmap Discovery + Kernel ARP"
        while read -r linha; do
            if [[ "$linha" =~ Nmap\ scan\ report\ for\ (.+)\ \(([0-9.]+)\) ]]; then
                local h="${BASH_REMATCH[1]}"
                local ip="${BASH_REMATCH[2]}"
                ips_descobertos+=("$ip")
                map_hints["$ip"]="$h"
            elif [[ "$linha" =~ Nmap\ scan\ report\ for\ ([0-9.]+) ]]; then
                local ip="${BASH_REMATCH[1]}"
                ips_descobertos+=("$ip")
            fi
        done < <(nmap -sn -n --min-parallelism 100 "$NET_CIDR" 2>/dev/null)
    fi

    # Coletar vizinhos da tabela ARP do kernel (capta máquinas ativas mesmo que filtrem ping)
    while read -r linha; do
        local vip
        vip=$(echo "$linha" | awk '{print $1}')
        if [[ "$vip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ips_descobertos+=("$vip")
        fi
    done < <(ip -4 neigh show dev "$NET_IFACE" 2>/dev/null | grep -E "REACHABLE|DELAY|STALE")

    # Incluir sempre Gateway e IP local
    [ -n "$NET_GW" ] && ips_descobertos+=("$NET_GW")
    [ -n "$LOCAL_IP" ] && ips_descobertos+=("$LOCAL_IP")

    # Mapear máquinas já cadastradas em hosts.conf (incluindo linhas comentadas para respeitar escolhas do usuário)
    declare -A hosts_cadastrados
    if [ -f "$CONFIG_FILE" ]; then
        while IFS='|' read -r raw_ip raw_name || [ -n "$raw_ip" ]; do
            local clean_ip
            clean_ip=$(echo "$raw_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            clean_ip="${clean_ip#\#}"
            clean_ip=$(echo "$clean_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [[ "$clean_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                hosts_cadastrados["$clean_ip"]=1
            fi
        done < "$CONFIG_FILE"
    else
        cat <<EOF > "$CONFIG_FILE"
# ==============================================================================
# BASE DE COMPUTADORES LOCAIS (RETRO NET-WATCH)
# Formato: ENDERECO_IP | NOME_DESCRITIVO
# Linhas iniciadas com '#' são ignoradas.
# ==============================================================================
EOF
    fi

    # Ordenar e filtrar IPs únicos
    local ips_unicos=()
    while read -r ip_u; do
        [ -n "$ip_u" ] && ips_unicos+=("$ip_u")
    done < <(printf "%s\n" "${ips_descobertos[@]}" | sort -u -V)

    local novos_encontrados=0
    local total_encontrados=${#ips_unicos[@]}

    for ip in "${ips_unicos[@]}"; do
        if [ -z "${hosts_cadastrados[$ip]}" ]; then
            local nome_auto
            nome_auto=$(resolver_nome_dispositivo "$ip" "${map_hints[$ip]}")
            printf "%-16s | %s\n" "$ip" "$nome_auto" >> "$CONFIG_FILE"
            hosts_cadastrados["$ip"]=1
            ((novos_encontrados++))
            if [ "$modo_silencioso" -eq 0 ]; then
                printf " %s[+] NOVO COMPUTADOR IDENTIFICADO:%s %-16s -> %s\n" "${C_ONLINE}${BOLD}" "${RESET}" "$ip" "$nome_auto"
            fi
        else
            if [ "$modo_silencioso" -eq 0 ]; then
                printf " %s[•] COMPUTADOR JÁ REGISTRADO:%s    %-16s\n" "${C_DIM}" "${RESET}" "$ip"
            fi
        fi
    done

    if [ "$modo_silencioso" -eq 0 ]; then
        echo ""
        echo "───────────────────────────────────────────────────────────────────────────────"
        printf " %sMétodo utilizado:%s %s\n" "${C_PRIMARY}" "${RESET}" "$metodo_scan"
        printf " %sTotal de nós ativos na sub-rede:%s %d\n" "${C_PRIMARY}" "${RESET}" "$total_encontrados"
        printf " %sNovos computadores adicionados ao monitor:%s %d\n" "${C_ONLINE}" "${RESET}" "$novos_encontrados"
        echo "───────────────────────────────────────────────────────────────────────────────"
    fi

    return 0
}

# Inicialização da base de computadores com varredura automática da rede local
inicializar_hosts() {
    detectar_configuracao_rede
    if [ ! -f "$CONFIG_FILE" ]; then
        cat <<EOF > "$CONFIG_FILE"
# ==============================================================================
# BASE DE COMPUTADORES LOCAIS (RETRO NET-WATCH)
# Formato: ENDERECO_IP | NOME_DESCRITIVO
# Linhas iniciadas com '#' são ignoradas.
# ==============================================================================
EOF
        [ -n "$NET_GW" ] && printf "%-16s | %s\n" "$NET_GW" "Roteador Gateway Principal" >> "$CONFIG_FILE"
        [ -n "$LOCAL_IP" ] && printf "%-16s | %s\n" "$LOCAL_IP" "Esta Maquina Local (${HOSTNAME:-Linux})" >> "$CONFIG_FILE"
    fi
    # Executa varredura automática para identificar máquinas ativas na rede local
    descobrir_maquinas_rede 1
}

# ------------------------------------------------------------------------------
# ELEMENTOS GRÁFICOS RETRO
# ------------------------------------------------------------------------------
desenhar_cabecalho() {
    clear
    printf "%s" "${C_BORDER}"
    echo " ╔══════════════════════════════════════════════════════════════════════════════╗"
    printf " ║%s%s  ███╗   ██╗███████╗████████╗   ███╗   ███╗ ██████╗ ███╗   ██╗                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s%s  ████╗  ██║██╔════╝╚══██╔══╝   ████╗ ████║██╔═══██╗████╗  ██║                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s%s  ██╔██╗ ██║█████╗     ██║█████╗██╔████╔██║██║   ██║██╔██╗ ██║                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s%s  ██║╚██╗██║██╔══╝     ██║╚════╝██║╚██╔╝██║██║   ██║██║╚██╗██║                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s%s  ██║ ╚████║███████╗   ██║      ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s%s  ╚═╝  ╚═══╝╚══════╝   ╚═╝      ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝                 %s║\n" "${C_PRIMARY}" "${BOLD}" "${C_BORDER}"
    printf " ║%s             [ SISTEMA RETRO DE MONITORAMENTO DE REDE LOCAL ]                   %s║\n" "${C_DIM}" "${C_BORDER}"
    local info_linha
    info_linha=$(printf "  Rede: %-14s • IP Local: %-13s • Dev: %-6s • %-13s  " "${NET_CIDR:-LAN}" "${LOCAL_IP:-127.0.0.1}" "${NET_IFACE:-eth0}" "$THEME_NAME")
    printf " ║%s%s%s║\n" "${C_ACCENT}" "$info_linha" "${C_BORDER}"
    echo " ╚══════════════════════════════════════════════════════════════════════════════╝"
    printf "%s" "${RESET}"
}

# ------------------------------------------------------------------------------
# MOTOR DE VARREDURA EM PARALELO (ALTA VELOCIDADE & SEM TRAVAMENTOS)
# ------------------------------------------------------------------------------
testar_host_individual() {
    local ip="$1"
    local nome="$2"
    local idx="$3"
    local arq_saida="$TMP_DIR/host_${idx}.tmp"

    local saida_ping
    saida_ping=$(ping -n -c 1 -W 1 "$ip" 2>&1)
    local status_ping=$?

    if [ $status_ping -eq 0 ]; then
        local rtt
        rtt=$(echo "$saida_ping" | awk -F'/' '/rtt|round-trip/ {printf "%.1f", $5}')
        [ -z "$rtt" ] && rtt="<1.0"
        echo "UP|${rtt} ms|${ip}|${nome}" > "$arq_saida"
    else
        echo "DOWN|--- ms|${ip}|${nome}" > "$arq_saida"
    fi
}

executar_varredura_paralela() {
    rm -f "$TMP_DIR"/host_*.tmp 2>/dev/null

    local idx=0
    local pids=()

    while IFS='|' read -r raw_ip raw_name || [ -n "$raw_ip" ]; do
        local ip
        ip=$(echo "$raw_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        local nome
        nome=$(echo "$raw_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        [[ "$ip" =~ ^#.*$ ]] && continue
        [ -z "$ip" ] && continue
        [ -z "$nome" ] && nome="Dispositivo-${idx}"

        testar_host_individual "$ip" "$nome" "$idx" &
        pids+=($!)
        ((idx++))
    done < "$CONFIG_FILE"

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
}

renderizar_tabela_resultados() {
    local timestamp
    timestamp=$(date "+%H:%M:%S")

    printf "%s" "${C_BORDER}"
    echo " ┌────────────┬────────────┬─────────────────┬────────────────────────────────┐"
    printf " │%s  ESTADO    %s│%s  LATENCIA  %s│%s   ENDERECO IP   %s│%s  NOME DO COMPUTADOR / FUNCAO   %s│\n" \
        "${BOLD}" "${RESET}${C_BORDER}" \
        "${BOLD}" "${RESET}${C_BORDER}" \
        "${BOLD}" "${RESET}${C_BORDER}" \
        "${BOLD}" "${RESET}${C_BORDER}"
    echo " ├────────────┼────────────┼─────────────────┼────────────────────────────────┤"

    local total_online=0
    local total_offline=0
    local arqs=("$TMP_DIR"/host_*.tmp)

    if [ ! -e "${arqs[0]}" ]; then
        printf " │ %s%-74s%s │\n" "${C_OFFLINE}" "  [!] Nenhum computador configurado em hosts.conf." "${RESET}${C_BORDER}"
    else
        for arq in $(ls -1v "$TMP_DIR"/host_*.tmp 2>/dev/null); do
            [ ! -f "$arq" ] && continue

            IFS='|' read -r status latencia ip nome < "$arq"

            local tag_status
            local c_st
            local c_txt
            if [ "$status" = "UP" ]; then
                ((total_online++))
                if [ -n "$LOCAL_IP" ] && [ "$ip" = "$LOCAL_IP" ]; then
                    tag_status="[  LOCAL*  ]"
                else
                    tag_status="[  ONLINE  ]"
                fi
                c_st="${C_ONLINE}${BOLD}"
                c_txt="${C_BRIGHT}"
            else
                ((total_offline++))
                tag_status="[  OFFLINE ]"
                c_st="${C_OFFLINE}${BOLD}"
                c_txt="${C_DIM}"
            fi

            # Trunca nome se exceder 30 caracteres para manter alinhamento
            if [ ${#nome} -gt 30 ]; then
                nome="${nome:0:27}..."
            fi

            printf " │%s%s%s│%s   %-9s%s│%s %-16s%s│%s %-31s%s│\n" \
                "$c_st" "$tag_status" "${RESET}${C_BORDER}" \
                "$c_txt" "$latencia" "${RESET}${C_BORDER}" \
                "$c_txt" "$ip" "${RESET}${C_BORDER}" \
                "$c_txt" "$nome" "${RESET}${C_BORDER}"
        done
    fi

    echo " ├────────────┴────────────┴─────────────────┴────────────────────────────────┤"
    printf " │ %sTotal:%s %-3d │ %sOnline [LIGADOS]:%s %-3d │ %sOffline [DESLIGADOS]:%s %-4d │ %s%-8s%s │\n" \
        "${C_ACCENT}" "${RESET}${C_BORDER}" "$((total_online + total_offline))" \
        "${C_ONLINE}" "${RESET}${C_BORDER}" "$total_online" \
        "${C_OFFLINE}" "${RESET}${C_BORDER}" "$total_offline" \
        "${C_BRIGHT}" "$timestamp" "${RESET}${C_BORDER}"
    echo " └────────────────────────────────────────────────────────────────────────────┘"
    printf "%s" "${RESET}"

    if [ "$BEEP_ON_CHANGE" -eq 1 ] && [ "$total_offline" -gt 0 ]; then
        printf "\a"
    fi
}

# ------------------------------------------------------------------------------
# ROTINA 1: MONITORAMENTO CONTÍNUO AO VIVO (DASHBOARD)
# ------------------------------------------------------------------------------
monitoramento_continuo() {
    tput civis 2>/dev/null || printf '\033[?25l'
    local ciclo=1

    # Varredura inicial para garantir que todas as máquinas na rede local estejam identificadas
    desenhar_cabecalho
    printf "%s\n 🔍 Realizando varredura na rede local (%s) para identificar computadores...%s\n" "${C_ACCENT}" "${NET_CIDR:-LAN}" "${RESET}"
    descobrir_maquinas_rede 1

    local bg_discovery_pid=""

    while true; do
        # Se autodescoberta em segundo plano terminou, coleta status
        if [ -n "$bg_discovery_pid" ] && ! kill -0 "$bg_discovery_pid" 2>/dev/null; then
            wait "$bg_discovery_pid" 2>/dev/null
            bg_discovery_pid=""
        fi

        # A cada 3 ciclos (~30s), se AUTO_DISCOVERY estiver ativado, efetua nova varredura em background
        if [ "${AUTO_DISCOVERY:-1}" -eq 1 ] && [ $((ciclo % 3)) -eq 0 ] && [ -z "$bg_discovery_pid" ]; then
            ( descobrir_maquinas_rede 1 >/dev/null 2>&1 ) &
            bg_discovery_pid=$!
        fi

        executar_varredura_paralela
        desenhar_cabecalho
        renderizar_tabela_resultados

        local status_auto="Ativa"
        [ "${AUTO_DISCOVERY:-1}" -eq 0 ] && status_auto="Desativada"

        printf "%s" "${C_ACCENT}"
        printf " » MONITORAMENTO CONTÍNUO ATIVO (Varredura: %ds | Auto-Descoberta LAN: %s | Ciclo #%d)\n" "$REFRESH_RATE" "$status_auto" "$ciclo"
        echo " » Pressione [0] ou [Q] para interromper e voltar ao menu principal..."
        printf "%s" "${RESET}"

        local key=""
        read -r -t "$REFRESH_RATE" -n 1 key 2>/dev/null

        if [ "$key" = "0" ] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            break
        fi
        ((ciclo++))
    done

    # Finaliza processo em background caso ainda esteja rodando ao sair
    [ -n "$bg_discovery_pid" ] && kill "$bg_discovery_pid" 2>/dev/null

    tput cnorm 2>/dev/null || printf '\033[?25h'
}

# ------------------------------------------------------------------------------
# ROTINA 2: VARREDURA ÚNICA (SNAPSHOT RÁPIDO)
# ------------------------------------------------------------------------------
varredura_unica() {
    desenhar_cabecalho
    printf "%s 🔍 Executando varredura na rede local (%s) e identificando máquinas... Aguarde.%s\n\n" "${C_ACCENT}" "${NET_CIDR:-LAN}" "${RESET}"
    descobrir_maquinas_rede 1
    executar_varredura_paralela
    desenhar_cabecalho
    renderizar_tabela_resultados
    echo ""
    printf "%s Pressione [0] ou [ENTER] para retornar ao menu principal: %s" "${C_BRIGHT}" "${RESET}"
    read -r _
}

# ------------------------------------------------------------------------------
# ROTINA 3: GERENCIAMENTO DE COMPUTADORES
# ------------------------------------------------------------------------------
gerenciar_computadores() {
    while true; do
        desenhar_cabecalho
        printf "%s%s" "${C_PRIMARY}" "${BOLD}"
        echo " ┌──[ GERENCIAMENTO DE COMPUTADORES MONITORADOS ]───────────────────────────────┐"
        echo " │                                                                              │"
        echo " │  [1] Listar todos os computadores cadastrados                                │"
        echo " │  [2] Adicionar novo computador manualmente                                   │"
        echo " │  [3] Remover computador da lista                                             │"
        echo " │  [4] Diagnóstico detalhado de um computador (Ping Extendido)                 │"
        echo " │  [5] Varrer e autodescobrir máquinas na rede local agora                     │"
        printf " │  [6] Alternar Autodescoberta Contínua [Atual: %-10s]                   │\n" "$([ "${AUTO_DISCOVERY:-1}" -eq 1 ] && echo "ATIVADA" || echo "DESATIVADA")"
        echo " │                                                                              │"
        echo " │  [0] Voltar ao Menu Principal                                                │"
        echo " │                                                                              │"
        echo " └──────────────────────────────────────────────────────────────────────────────┘"
        printf "%s" "${RESET}"
        printf "%s Escolha uma opção [0-6]: %s" "${C_BRIGHT}" "${RESET}"
        read -r sub_opt

        case "$sub_opt" in
            1)
                desenhar_cabecalho
                printf "%s┌──[ LISTA DE COMPUTADORES EM HOSTS.CONF ]──────────────────────────────────────┐\n" "${C_BORDER}"
                local num=1
                while IFS='|' read -r raw_ip raw_name || [ -n "$raw_ip" ]; do
                    local ip
                    ip=$(echo "$raw_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    local nome
                    nome=$(echo "$raw_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    [[ "$ip" =~ ^#.*$ ]] && continue
                    [ -z "$ip" ] && continue
                    printf "│  %s[%02d]%s %-18s │ %-49s %s│\n" "${C_ACCENT}" "$num" "${RESET}" "$ip" "$nome" "${C_BORDER}"
                    ((num++))
                done < "$CONFIG_FILE"
                printf "└───────────────────────────────────────────────────────────────────────────────┘\n%s" "${RESET}"
                echo ""
                printf "%s Pressione [0] ou [ENTER] para voltar: %s" "${C_BRIGHT}" "${RESET}"
                read -r _
                ;;
            2)
                desenhar_cabecalho
                printf "%s=== ADICIONAR NOVO COMPUTADOR ===%s\n\n" "${C_ACCENT}" "${RESET}"
                printf "%sDigite o Endereço IP (ex: 192.168.15.25) ou [0] para cancelar: %s" "${C_BRIGHT}" "${RESET}"
                read -r novo_ip
                [ "$novo_ip" = "0" ] || [ -z "$novo_ip" ] && continue

                printf "%sDigite o Nome Descritivo (ex: Desktop Ubuntu Financeiro): %s" "${C_BRIGHT}" "${RESET}"
                read -r novo_nome
                [ -z "$novo_nome" ] && novo_nome="Estacao $novo_ip"

                echo "$novo_ip | $novo_nome" >> "$CONFIG_FILE"
                printf "\n%s[OK] Computador '%s' (%s) adicionado com sucesso!%s\n" "${C_ONLINE}" "$novo_nome" "$novo_ip" "${RESET}"
                sleep 1.5
                ;;
            3)
                desenhar_cabecalho
                printf "%s=== REMOVER COMPUTADOR ===%s\n\n" "${C_ACCENT}" "${RESET}"
                
                local lista_ips=()
                local lista_nomes=()
                local i=1
                while IFS='|' read -r raw_ip raw_name || [ -n "$raw_ip" ]; do
                    local ip
                    ip=$(echo "$raw_ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    local nome
                    nome=$(echo "$raw_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    [[ "$ip" =~ ^#.*$ ]] && continue
                    [ -z "$ip" ] && continue
                    lista_ips+=("$ip")
                    lista_nomes+=("$nome")
                    printf "  [%d] %-16s - %s\n" "$i" "$ip" "$nome"
                    ((i++))
                done < "$CONFIG_FILE"

                if [ ${#lista_ips[@]} -eq 0 ]; then
                    echo "Nenhum computador cadastrado para remover."
                    sleep 1.5
                    continue
                fi

                echo ""
                printf "%sSelecione o número para remover ou [0] para cancelar: %s" "${C_BRIGHT}" "${RESET}"
                read -r num_rem
                [ "$num_rem" = "0" ] || [ -z "$num_rem" ] && continue

                if [[ "$num_rem" =~ ^[0-9]+$ ]] && [ "$num_rem" -ge 1 ] && [ "$num_rem" -le "${#lista_ips[@]}" ]; then
                    local idx_alvo=$((num_rem - 1))
                    local ip_alvo="${lista_ips[$idx_alvo]}"
                    
                    grep -v -E "^[[:space:]]*${ip_alvo}[[:space:]]*\|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    printf "\n%s[OK] Computador %s removido com sucesso!%s\n" "${C_ONLINE}" "$ip_alvo" "${RESET}"
                else
                    printf "\n%s[ERRO] Opção inválida!%s\n" "${C_OFFLINE}" "${RESET}"
                fi
                sleep 1.5
                ;;
            4)
                desenhar_cabecalho
                printf "%s=== DIAGNÓSTICO DETALHADO (PING TEST) ===%s\n\n" "${C_ACCENT}" "${RESET}"
                printf "%sDigite o IP para teste detalhado ou [0] para voltar: %s" "${C_BRIGHT}" "${RESET}"
                read -r ip_teste
                [ "$ip_teste" = "0" ] || [ -z "$ip_teste" ] && continue

                echo ""
                printf "%sDisparando 5 pacotes ICMP para %s...%s\n\n" "${C_PRIMARY}" "$ip_teste" "${RESET}"
                ping -c 5 "$ip_teste"
                echo ""
                printf "%sPressione [0] ou [ENTER] para voltar: %s" "${C_BRIGHT}" "${RESET}"
                read -r _
                ;;
            5)
                desenhar_cabecalho
                descobrir_maquinas_rede 0
                echo ""
                printf "%s Pressione [0] ou [ENTER] para voltar: %s" "${C_BRIGHT}" "${RESET}"
                read -r _
                ;;
            6)
                if [ "${AUTO_DISCOVERY:-1}" -eq 1 ]; then
                    AUTO_DISCOVERY=0
                else
                    AUTO_DISCOVERY=1
                fi
                salvar_configuracoes
                desenhar_cabecalho
                printf "%s=== AUTODESCOBERTA CONTÍNUA ===%s\n\n" "${C_ACCENT}" "${RESET}"
                if [ "$AUTO_DISCOVERY" -eq 1 ]; then
                    printf "%s[OK] Autodescoberta contínua em segundo plano ATIVADA!%s\n" "${C_ONLINE}" "${RESET}"
                else
                    printf "%s[OK] Autodescoberta contínua em segundo plano DESATIVADA!%s\n" "${C_OFFLINE}" "${RESET}"
                fi
                sleep 1.5
                ;;
            0)
                break
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ROTINA 4: ESQUEMA VISUAL E EFEITOS RETRÔ
# ------------------------------------------------------------------------------
configurar_aparencia() {
    while true; do
        desenhar_cabecalho
        printf "%s%s" "${C_PRIMARY}" "${BOLD}"
        echo " ┌──[ CONFIGURAÇÃO DE TEMA RETRO E EFEITOS ]────────────────────────────────────┐"
        echo " │                                                                              │"
        echo " │  [1] Tema Fósforo Verde (Green CRT / Matrix style)                           │"
        echo " │  [2] Tema Âmbar Monocromático (Amber CRT / DEC VT220)                        │"
        echo " │  [3] Tema IBM DOS / ANSI Clássico                                            │"
        printf " │  [4] Alternar Alerta Sonoro de Terminal (Beep) [Atual: %d]                   │\n" "$BEEP_ON_CHANGE"
        echo " │                                                                              │"
        echo " │  [0] Voltar ao Menu Principal                                                │"
        echo " │                                                                              │"
        echo " └──────────────────────────────────────────────────────────────────────────────┘"
        printf "%s" "${RESET}"
        printf "%s Escolha uma opção [0-4]: %s" "${C_BRIGHT}" "${RESET}"
        read -r t_opt

        case "$t_opt" in
            1) THEME="green"; aplicar_tema; salvar_configuracoes ;;
            2) THEME="amber"; aplicar_tema; salvar_configuracoes ;;
            3) THEME="classic"; aplicar_tema; salvar_configuracoes ;;
            4) 
               if [ "$BEEP_ON_CHANGE" -eq 1 ]; then
                   BEEP_ON_CHANGE=0
               else
                   BEEP_ON_CHANGE=1
                   printf "\a"
               fi
               salvar_configuracoes
               ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ROTINA 5: INTERVALO DE ATUALIZAÇÃO
# ------------------------------------------------------------------------------
configurar_intervalo() {
    desenhar_cabecalho
    printf "%s=== INTERVALO DE ATUALIZAÇÃO DO MONITORAMENTO ===%s\n\n" "${C_ACCENT}" "${RESET}"
    printf "Intervalo atual: %s segundo(s)\n" "$REFRESH_RATE"
    printf "%sDigite o novo intervalo em segundos (ex: 5, 10, 15, 30) ou [0] para cancelar: %s" "${C_BRIGHT}" "${RESET}"
    read -r novo_int

    if [ "$novo_int" != "0" ] && [ -n "$novo_int" ]; then
        if [[ "$novo_int" =~ ^[0-9]+$ ]] && [ "$novo_int" -ge 1 ]; then
            REFRESH_RATE="$novo_int"
            salvar_configuracoes
            printf "\n%s[OK] Intervalo ajustado para %d segundo(s)!%s\n" "${C_ONLINE}" "$REFRESH_RATE" "${RESET}"
        else
            printf "\n%s[ERRO] Valor inválido! Insira um número inteiro >= 1.%s\n" "${C_OFFLINE}" "${RESET}"
        fi
        sleep 1.5
    fi
}

# ------------------------------------------------------------------------------
# MENU PRINCIPAL RETRO
# ------------------------------------------------------------------------------
menu_principal() {
    while true; do
        desenhar_cabecalho
        printf "%s%s" "${C_PRIMARY}" "${BOLD}"
        echo " ╔══════════════════════════════════════════════════════════════════════════════╗"
        echo " ║                            M E N U   P R I N C I P A L                       ║"
        echo " ╠══════════════════════════════════════════════════════════════════════════════╣"
        echo " ║                                                                              ║"
        echo " ║   [1] Iniciar Monitoramento Contínuo (Live CRT Dashboard)                    ║"
        echo " ║   [2] Executar Varredura Única (Snapshot Rápido)                             ║"
        echo " ║   [3] Gerenciar Computadores (Listar / Adicionar / Remover)                  ║"
        echo " ║   [4] Configurar Tema Visual Retrô (Verde / Âmbar / DOS)                     ║"
        printf " ║   [5] Ajustar Intervalo de Varredura (Atual: %-2ds)                           ║\n" "$REFRESH_RATE"
        echo " ║                                                                              ║"
        echo " ║   [0] Desconectar e Sair                                                     ║"
        echo " ║                                                                              ║"
        echo " ╚══════════════════════════════════════════════════════════════════════════════╝"
        printf "%s" "${RESET}"
        printf "%s DIGITE A OPÇÃO DESEJADA [0-5]: %s" "${C_BRIGHT}" "${RESET}"
        read -r opcao

        case "$opcao" in
            1) monitoramento_continuo ;;
            2) varredura_unica ;;
            3) gerenciar_computadores ;;
            4) configurar_aparencia ;;
            5) configurar_intervalo ;;
            0)
                desenhar_cabecalho
                printf "%s\n Encerrando sessão de monitoramento de rede...\n" "${C_PRIMARY}"
                printf "%s Sistema desativado com segurança. Até logo! [SYS_HALT]\n\n%s" "${C_DIM}" "${RESET}"
                exit 0
                ;;
            *)
                printf "\n%s Opção inválida. Tente novamente.%s\n" "${C_OFFLINE}" "${RESET}"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# PONTO DE ENTRADA DO SCRIPT
# ------------------------------------------------------------------------------
verificar_pre_requisitos
detectar_configuracao_rede
carregar_configuracoes
inicializar_hosts
menu_principal
