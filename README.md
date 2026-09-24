<div align="center">

# 📟 RETRO NET-WATCH (`netmonitor.sh`)

**Monitor contínuo de disponibilidade em rede local com interface retrô (CRT / VT100 / BBS)**

[![Bash](https://img.shields.io/badge/Language-Bash_5.0+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Platform-Ubuntu_%7C_Linux_Mint_%7C_Debian-FCC624?logo=linux&logoColor=black)](https://kernel.org)
[![Offline](https://img.shields.io/badge/Operation-100%25_Offline-blue)](#-opera%C3%A7%C3%A3o-100-offline)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## 📺 Visão Geral

O **RETRO NET-WATCH** (`netmonitor.sh`) é um utilitário em Shell Script projetado para monitorar continuamente o status (ligado/desligado) e a latência de computadores em uma rede local (LAN).

Desenvolvido com foco em ambientes Linux (Ubuntu, Linux Mint, Debian), ele opera de forma **100% offline**, com **alta velocidade através de paralelismo assíncrono** e com um visual nostálgico inspirado nos terminais de fósforo verde e âmbar dos anos 80 e 90.

```text
 ╔══════════════════════════════════════════════════════════════════════════════╗
 ║  ███╗   ██╗███████╗████████╗   ███╗   ███╗ ██████╗ ███╗   ██╗                ║
 ║  ████╗  ██║██╔════╝╚══██╔══╝   ████╗ ████║██╔═══██╗████╗  ██║                ║
 ║  ██╔██╗ ██║█████╗     ██║█████╗██╔████╔██║██║   ██║██╔██╗ ██║                ║
 ║  ██║╚██╗██║██╔══╝     ██║╚════╝██║╚██╔╝██║██║   ██║██║╚██╗██║                ║
 ║  ██║ ╚████║███████╗   ██║      ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║                ║
 ║  ╚═╝  ╚═══╝╚══════╝   ╚═╝      ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝                ║
 ║             [ SISTEMA RETRO DE MONITORAMENTO DE REDE LOCAL ]                 ║
 ║   Ambiente: 100% Offline  •  Tema: Fósforo Verde (Green CRT)  •  v1.0        ║
 ╚══════════════════════════════════════════════════════════════════════════════╝
 ┌────────────┬────────────┬─────────────────┬────────────────────────────────┐
 │  ESTADO    │  LATENCIA  │   ENDERECO IP   │  NOME DO COMPUTADOR / FUNCAO   │
 ├────────────┼────────────┼─────────────────┼────────────────────────────────┤
 │[  ONLINE  ]│   3.4 ms   │ 192.168.15.1    │ Roteador Gateway Principal     │
 │[  ONLINE  ]│   0.1 ms   │ 192.168.15.9    │ Esta Maquina Local             │
 │[  ONLINE  ]│   3.5 ms   │ 192.168.15.19   │ Computador Rede Local 01       │
 │[  ONLINE  ]│   39.9 ms  │ 192.168.15.21   │ Computador Rede Local 02       │
 │[  OFFLINE ]│   --- ms   │ 192.168.15.23   │ Computador Rede Local 03       │
 │[  ONLINE  ]│  420.7 ms  │ 192.168.15.28   │ Computador Rede Local 04       │
 ├────────────┴────────────┴─────────────────┴────────────────────────────────┤
 │ Total: 6   │ Online [LIGADOS]: 5   │ Offline [DESLIGADOS]: 1    │ 13:38:04 │
 └────────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Principais Características

- **100% Offline & Autônomo:** Não envia dados para a internet, não depende de APIs de terceiros nem de softwares proprietários.
- **Autoverificação de Dependências:** Detecta comandos essenciais (`ping`, `awk`, `sed`, `grep`, `tput`, `ip`) e tenta instalá-los de forma transparente caso falte algum pacote básico.
- **Varredura Paralela Não-Bloqueante:** Todos os nós da rede são checados simultaneamente em segundo plano. Mesmo com vários computadores desligados, o ciclo de varredura leva apenas ~1 segundo.
- **Visual Retrô Customizável:**
  - 🟢 **Fósforo Verde:** Efeito CRT clássico estilo terminal Matrix / VT100.
  - 🟠 **Âmbar Monocromático:** Estilo DEC VT220 / fósforo âmbar dos anos 80.
  - 🔵 **IBM DOS / ANSI:** Cores clássicas estilo Norton Commander / MS-DOS.
  - 🔔 **Alerta Sonoro de Terminal:** Opção de Beep (`\a`) quando máquinas ficam inalcançáveis.
- **Menu Completo:** Convenção estrita e amigável: **digite `0` para voltar ou sair**.
- **Varredura e Autodescoberta Ativa na LAN:** Varre ativamente toda a sub-rede local (via detecção veloz com `nmap` ou varredura nativa paralela ICMP + ARP do kernel) para reconhecer automaticamente todas as máquinas na rede local e monitorá-las de forma constante. Novos computadores que entram na rede são identificados dinamicamente em segundo plano.

---

## 📦 Instalação e Execução

### 1. Clonar o repositório
```bash
git clone https://github.com/capafardo/netmonitor.git
cd netmonitor
```

### 2. Conceder permissão de execução
```bash
chmod +x netmonitor.sh
```

### 3. Iniciar o monitor
```bash
./netmonitor.sh
```

---

## 🧭 Menu de Navegação

```text
 ╔══════════════════════════════════════════════════════════════════════════════╗
 ║                            M E N U   P R I N C I P A L                       ║
 ╠══════════════════════════════════════════════════════════════════════════════╣
 ║   [1] Iniciar Monitoramento Contínuo (Live CRT Dashboard)                    ║
 ║   [2] Executar Varredura Única (Snapshot Rápido)                             ║
 ║   [3] Gerenciar Computadores (Listar / Adicionar / Remover)                  ║
 ║   [4] Configurar Tema Visual Retrô (Verde / Âmbar / DOS)                     ║
 ║   [5] Ajustar Intervalo de Varredura (Padrão: 10s)                           ║
 ║                                                                              ║
 ║   [0] Desconectar e Sair                                                     ║
 ╚══════════════════════════════════════════════════════════════════════════════╝
```

* **No Monitoramento Contínuo (`[1]`):** Pressione `0` ou `q` a qualquer momento para pausar e retornar ao menu.
* **No Gerenciador de Computadores (`[3]`):** Permite listar, adicionar novos IPs, remover ou usar a autodescoberta de vizinhos ativos na rede local.

---

## ⚙️ Configuração dos Computadores (`hosts.conf`)

Os hosts são armazenados localmente no arquivo `hosts.conf`. Você pode editá-lo pelo próprio menu interativo do script ou diretamente em qualquer editor de texto:

```text
# Formato: ENDERECO_IP | NOME_DESCRITIVO
192.168.15.1   | Roteador Gateway Principal
192.168.15.9   | Esta Maquina Local
192.168.15.19  | Computador Linux Mint 01
192.168.15.21  | Desktop Ubuntu Escritorio
192.168.15.28  | Servidor de Backup
```

> **Nota de Privacidade:** O arquivo `hosts.conf` e `settings.conf` estão incluídos no `.gitignore` para garantir que seus IPs e topologia de rede privada não sejam enviados publicamente para o GitHub. Um modelo exemplo é disponibilizado em `hosts.conf.example`.

---

## 🛠️ Tecnologias e Pré-requisitos

O script utiliza apenas ferramentas padrão incluídas na esmagadora maioria das distribuições Linux:

* `bash` (versão 4.0+)
* `iputils-ping` (`ping`)
* `iproute2` (`ip`)
* `gawk` / `awk`
* `sed` & `grep`
* `ncurses-bin` (`tput`)

---

## 📄 Licença

Distribuído sob a licença **MIT**. Veja o arquivo [`LICENSE`](LICENSE) para mais detalhes.
