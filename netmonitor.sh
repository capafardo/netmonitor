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
            THEME_NAME="Âmbar CRT (Monocromático)"
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
            THEME_NAME="IBM DOS / ANSI Color"
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
            THEME_NAME="Fósforo Verde (Green CRT)"
            ;;
    esac
}

# Inicialização da base de computadores caso não exista (sem IPs fictícios)
inicializar_hosts() {
    if [ ! -f "$CONFIG_FILE" ]; then
        local gw
        gw=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -n 1)

        cat <<EOF > "$CONFIG_FILE"
# ==============================================================================
# BASE DE COMPUTADORES LOCAIS (RETRO NET-WATCH)
# Formato: ENDERECO_IP | NOME_DESCRITIVO
# Linhas iniciadas com '#' são ignoradas.
# ==============================================================================
EOF
        # Adiciona o Gateway real se detectado
        if [ -n "$gw" ]; then
            echo "$gw | Roteador Gateway Principal" >> "$CONFIG_FILE"
        fi

        # Adiciona vizinhos reais presentes na tabela ARP local
        while read -r linha; do
            local vip
            vip=$(echo "$linha" | awk '{print $1}')
            if [[ "$vip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$vip" != "$gw" ]; then
                echo "$vip | Dispositivo Rede Local ($vip)" >> "$CONFIG_FILE"
            fi
        done < <(ip -4 neigh show 2>/dev/null | grep -E "REACHABLE|DELAY|STALE")
    fi
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
    printf " ║%s   Ambiente: 100%% Offline  •  Tema: %-26s  •  v1.0   %s║\n" "${C_ACCENT}" "$THEME_NAME" "${C_BORDER}"
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
        local total_arquivos
        total_arquivos=$(ls -1v "$TMP_DIR"/host_*.tmp 2>/dev/null | wc -l)

        for ((i=0; i<total_arquivos; i++)); do
            local arq="$TMP_DIR/host_${i}.tmp"
            [ ! -f "$arq" ] && continue

            IFS='|' read -r status latencia ip nome < "$arq"

            local tag_status
            local c_st
            local c_txt
            if [ "$status" = "UP" ]; then
                ((total_online++))
                tag_status="[  ONLINE  ]"
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

    while true; do
        executar_varredura_paralela
        desenhar_cabecalho
        renderizar_tabela_resultados

        printf "%s" "${C_ACCENT}"
        printf " » MONITORAMENTO CONTÍNUO ATIVO (Varredura a cada %ds | Ciclo #%d)\n" "$REFRESH_RATE" "$ciclo"
        echo " » Pressione [0] ou [Q] para interromper e voltar ao menu principal..."
        printf "%s" "${RESET}"

        local key=""
        read -r -t "$REFRESH_RATE" -n 1 key 2>/dev/null

        if [ "$key" = "0" ] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            break
        fi
        ((ciclo++))
    done

    tput cnorm 2>/dev/null || printf '\033[?25h'
}

# ------------------------------------------------------------------------------
# ROTINA 2: VARREDURA ÚNICA (SNAPSHOT RÁPIDO)
# ------------------------------------------------------------------------------
varredura_unica() {
    desenhar_cabecalho
    printf "%s Executando varredura rápida na rede local... Aguarde.%s\n\n" "${C_ACCENT}" "${RESET}"
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
        echo " │  [2] Adicionar novo computador                                               │"
        echo " │  [3] Remover computador da lista                                             │"
        echo " │  [4] Diagnóstico detalhado de um computador (Ping Extendido)                 │"
        echo " │  [5] Autodescobrir dispositivos vizinhos na rede local                       │"
        echo " │                                                                              │"
        echo " │  [0] Voltar ao Menu Principal                                                │"
        echo " │                                                                              │"
        echo " └──────────────────────────────────────────────────────────────────────────────┘"
        printf "%s" "${RESET}"
        printf "%s Escolha uma opção [0-5]: %s" "${C_BRIGHT}" "${RESET}"
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
                printf "%s=== AUTODESCOBERTA DE VIZINHOS NA REDE LOCAL (ARP CACHE) ===%s\n" "${C_ACCENT}" "${RESET}"
                printf "%sConsulta a tabela de vizinhos do kernel Linux (100%% offline e seguro)%s\n\n" "${C_DIM}" "${RESET}"
                
                local vizinhos=()
                while read -r linha; do
                    local vip
                    vip=$(echo "$linha" | awk '{print $1}')
                    if [[ "$vip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        vizinhos+=("$vip")
                    fi
                done < <(ip -4 neigh show 2>/dev/null | grep -E "REACHABLE|DELAY|STALE")

                if [ ${#vizinhos[@]} -eq 0 ]; then
                    echo "Nenhum vizinho ativo detectado no cache ARP imediato."
                else
                    echo "Dispositivos detectados na rede local:"
                    local c=1
                    for v in "${vizinhos[@]}"; do
                        printf "  [%d] %s\n" "$c" "$v"
                        ((c++))
                    done
                    echo ""
                    printf "%sDeseja adicionar algum IP à lista de monitoramento? (digite o IP ou [0] para voltar): %s" "${C_BRIGHT}" "${RESET}"
                    read -r add_vip
                    if [ "$add_vip" != "0" ] && [ -n "$add_vip" ]; then
                        printf "%sNome descritivo para %s: %s" "${C_BRIGHT}" "$add_vip" "${RESET}"
                        read -r vnome
                        [ -z "$vnome" ] && vnome="Dispositivo $add_vip"
                        echo "$add_vip | $vnome" >> "$CONFIG_FILE"
                        printf "%s[OK] Adicionado!%s\n" "${C_ONLINE}" "${RESET}"
                        sleep 1
                    fi
                fi
                echo ""
                printf "%sPressione [0] ou [ENTER] para voltar: %s" "${C_BRIGHT}" "${RESET}"
                read -r _
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
inicializar_hosts
carregar_configuracoes
menu_principal
