#!/bin/bash

# ------------------------------------------------------------------
# Script de Gerenciamento de Addons (Metamod, CounterStrikeSharp)
# ------------------------------------------------------------------
#
# Este script automatiza o download, extração, instalação e atualização
# de addons essenciais para o servidor de CS2.

# SEÇÃO 1: DEPENDÊNCIAS E VARIÁVEIS GLOBAIS
# Importa scripts utilitários e define caminhos importantes.
# ------------------------------------------------------------------

# Importa funções de outros arquivos para manter o código organizado.
source /utils/logging.sh   # Provavelmente contém a função 'log_message' para logs coloridos.
source /utils/version.sh   # Pode conter funções adicionais de versionamento.

# --- Diretórios ---
# Define os caminhos usados em todo o script como variáveis para fácil manutenção.
GAME_DIRECTORY="./game/csgo"              # Diretório principal do jogo. CS2 ainda usa o caminho 'csgo'.
OUTPUT_DIR="./game/csgo/addons"           # Onde os addons (Metamod, CSS) serão instalados.
TEMP_DIR="./temps"                        # Diretório temporário para downloads e extrações.
ACCELERATOR_DUMPS_DIR="$OUTPUT_DIR/AcceleratorCS2/dumps" # Diretório para logs de erro de um plugin específico.
VERSION_FILE="./game/versions.txt"        # Arquivo de texto para rastrear as versões instaladas dos addons.

# ------------------------------------------------------------------
# SEÇÃO 2: FUNÇÕES DE GERENCIAMENTO DE VERSÃO
# Funções para ler e escrever no arquivo 'versions.txt'.
# Isso evita baixar novamente um addon que já está atualizado.
# ------------------------------------------------------------------

# Obtém a versão atual de um addon lendo o arquivo versions.txt.
# Uso: get_current_version "Metamod"
get_current_version() {
    local addon="$1"
    if [ -f "$VERSION_FILE" ]; then
        # Usa 'grep' para encontrar a linha do addon e 'cut' para extrair apenas o valor da versão.
        grep "^$addon=" "$VERSION_FILE" | cut -d'=' -f2
    else
        echo "" # Retorna vazio se o arquivo não existir.
    fi
}

# Atualiza a versão de um addon no arquivo ou adiciona uma nova entrada se não existir.
# Uso: update_version_file "Metamod" "git1145"
update_version_file() {
    local addon="$1"
    local new_version="$2"
    # Verifica se a linha para o addon já existe.
    if grep -q "^$addon=" "$VERSION_FILE"; then
        # Se existe, usa 'sed' para substituir a versão antiga pela nova.
        sed -i "s/^$addon=.*/$addon=$new_version/" "$VERSION_FILE"
    else
        # Se não existe, adiciona uma nova linha no final do arquivo.
        echo "$addon=$new_version" >> "$VERSION_FILE"
    fi
}

# ------------------------------------------------------------------
# SEÇÃO 3: FUNÇÕES UTILITÁRIAS CENTRALIZADAS
# Funções robustas e reutilizáveis para tarefas comuns como download e verificação.
# ------------------------------------------------------------------

# Função centralizada para baixar e extrair arquivos.
# Lida com diferentes tipos de arquivos (.zip, .tar.gz) e inclui retentativas.
handle_download_and_extract() {
    local url="$1"
    local output_file="$2"
    local extract_dir="$3"
    local file_type="$4"  # "zip" ou "tar.gz"

    log_message "Baixando de: $url" "debug"

    # --- Lógica de Download com Retentativa ---
    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        # 'curl': -f (falha silenciosamente em erros de HTTP), -s (modo silencioso), -S (mostra erros), -L (segue redirecionamentos), -m 300 (timeout de 300s).
        if curl -fsSL -m 300 -o "$output_file" "$url"; then
            break # Sai do loop se o download for bem-sucedido.
        fi
        ((retry++))
        log_message "Tentativa de download $retry falhou, tentando novamente..." "error"
        sleep 5
    done

    # Verifica se todas as tentativas falharam.
    if [ $retry -eq $max_retries ]; then
        log_message "Falha no download após $max_retries tentativas" "error"
        return 1 # Retorna um código de erro.
    fi

    # Verifica se o arquivo baixado não está vazio.
    if [ ! -s "$output_file" ]; then
        log_message "O arquivo baixado está vazio" "error"
        return 1
    fi

    log_message "Extraindo para $extract_dir" "debug"
    mkdir -p "$extract_dir"

    # --- Lógica de Extração ---
    # Usa um 'case' para lidar com diferentes tipos de compactação.
    case $file_type in
        "zip")
            unzip -qq -o "$output_file" -d "$extract_dir" || {
                log_message "Falha ao extrair arquivo zip" "error"
                return 1
            }
            ;;
        "tar.gz")
            tar -xzf "$output_file" -C "$extract_dir" || {
                log_message "Falha ao extrair arquivo tar.gz" "error"
                return 1
            }
            ;;
    esac

    return 0 # Sucesso!
}

# Função centralizada para comparar versões e decidir se uma atualização é necessária.
check_version() {
    local addon="$1"
    local current="${2:-none}" # Versão atual (ou "none" se não definida)
    local new="$3"             # Nova versão encontrada

    if [ "$current" != "$new" ]; then
        log_message "Nova versão de $addon disponível: $new (instalada: $current)" "running"
        return 0 # Sucesso (significa "prossiga com a atualização").
    fi

    log_message "Nenhuma nova versão de $addon disponível. Instalada: $current" "debug"
    return 1 # Falha (significa "não precisa atualizar").
}

# ------------------------------------------------------------------
# SEÇÃO 4: FUNÇÕES DE ORQUESTRAÇÃO E ATUALIZAÇÃO
# Funções que unem tudo para verificar e instalar/atualizar os addons.
# ------------------------------------------------------------------

# Função principal que coordena a limpeza e as atualizações.
# Esta é provavelmente a função chamada pelo 'entrypoint.sh' principal.
cleanup_and_update() {
    # Verifica variáveis de ambiente para ver se a limpeza está ativada.
    if [ "${CLEANUP_ENABLED:-0}" = "1" ]; then
        cleanup # 'cleanup' provavelmente está em outro arquivo.
    fi

    mkdir -p "$TEMP_DIR" # Garante que o diretório temporário exista.

    # Atualiza o Metamod se a auto-atualização estiver ligada, ou se ele não estiver instalado.
    if [ "${METAMOD_AUTOUPDATE:-0}" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "${CSS_AUTOUPDATE:-0}" = "1" ]); then
        update_metamod
    fi

    # Atualiza o CounterStrikeSharp se a auto-atualização estiver ligada.
    if [ "${CSS_AUTOUPDATE:-0}" = "1" ]; then
        # Chama a função genérica de atualização para o CounterStrikeSharp.
        update_addon "roflmuffin/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi

    # Limpa o diretório temporário no final do processo.
    rm -rf "$TEMP_DIR"
}

# Função genérica para atualizar um addon a partir de um repositório GitHub.
update_addon() {
    local repo="$1"          # Ex: "roflmuffin/CounterStrikeSharp"
    local output_path="$2"   # Onde instalar (./game/csgo/addons)
    local temp_subdir="$3"   # Subdiretório temporário (css)
    local addon_name="$4"    # Nome para o arquivo de versão (CSS)
    local temp_dir="$TEMP_DIR/$temp_subdir"

    mkdir -p "$output_path" "$temp_dir"
    rm -rf "$temp_dir"/* # Limpa o diretório temporário do addon.

    # --- Lógica de API do GitHub ---
    # Usa a API do GitHub para obter informações sobre o último "release".
    local api_response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    if [ -z "$api_response" ]; then
        log_message "Falha ao obter informações do release para $repo" "error"
        return 1
    fi

    # Usa 'grep' com PCRE (-P) para extrair o 'tag_name' (versão) da resposta JSON.
    local new_version=$(echo "$api_response" | grep -oP '"tag_name": "\K[^"]+')
    local current_version=$(get_current_version "$addon_name")
    # Extrai a URL de download do asset que contém "with-runtime-linux".
    local asset_url=$(echo "$api_response" | grep -oP '"browser_download_url": "\K[^"]+-with-runtime-linux-[^"]+\.zip')

    # Chama a função de verificação. Se retornar 1, não há atualização e a função para.
    if ! check_version "$addon_name" "$current_version" "$new_version"; then
        return 0
    fi

    if [ -z "$asset_url" ]; then
        log_message "Nenhum arquivo de download compatível encontrado para $repo" "error"
        return 1
    fi

    # Chama a função de download/extração.
    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        # Se o download e a extração deram certo, copia os arquivos para o local final.
        cp -r "$temp_dir/addons/." "$output_path" && \
        update_version_file "$addon_name" "$new_version" && \
        log_message "Atualização de $repo concluída com sucesso" "success"
        return 0
    fi

    return 1 # Retorna erro se a atualização falhou.
}

# Função específica para atualizar o Metamod.
update_metamod() {
    if [ ! -d "$OUTPUT_DIR/metamod" ]; then
        log_message "Metamod não instalado. Instalando Metamod..." "running"
    fi

    # --- Lógica de Web Scraping ---
    # Em vez de uma API, baixa o HTML da página de downloads do Metamod e usa 'grep' para encontrar o nome do arquivo mais recente.
    local metamod_version=$(curl -sL https://mms.alliedmods.net/mmsdrop/2.0/ | grep -oP 'href="\K(mmsource-[^"]*-linux\.tar\.gz)' | tail -1)
    if [ -z "$metamod_version" ]; then
        log_message "Falha ao obter a versão do Metamod" "error"
        return 1
    fi

    local full_url="https://mms.alliedmods.net/mmsdrop/2.0/$metamod_version"
    # Extrai o número do 'git' do nome do arquivo para usar como versão.
    local new_version=$(echo "$metamod_version" | grep -oP 'git\d+')
    local current_version=$(get_current_version "Metamod")

    if ! check_version "Metamod" "$current_version" "$new_version"; then
        return 0
    fi

    if handle_download_and_extract "$full_url" "$TEMP_DIR/metamod.tar.gz" "$TEMP_DIR/metamod" "tar.gz"; then
        cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/" && \
        update_version_file "Metamod" "$new_version" && \
        log_message "Atualização do Metamod concluída com sucesso" "success"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------
# SEÇÃO 5: CONFIGURAÇÃO PÓS-INSTALAÇÃO
# Garante que o jogo carregue os addons instalados.
# ------------------------------------------------------------------

# Edita o arquivo 'gameinfo.gi' para que o CS2 carregue o Metamod na inicialização.
configure_metamod() {
    local GAMEINFO_FILE="/home/teranex/game/csgo/gameinfo.gi"
    local GAMEINFO_ENTRY="			Game	csgo/addons/metamod" # A linha exata a ser inserida.

    if [ -f "${GAMEINFO_FILE}" ]; then
        # Verifica se a linha do Metamod já não existe no arquivo.
        if ! grep -q "Game[[:blank:]]*csgo\/addons\/metamod" "$GAMEINFO_FILE"; then
            # Se não existe, usa 'awk' para inserir a linha de forma segura.
            # O script 'awk' encontra a linha que contém "Game_LowViolence" e insere a nossa nova linha logo depois dela.
            # Esta é a maneira padrão de habilitar o Metamod.
            # O resultado é salvo em um arquivo .tmp e depois renomeado, para evitar corromper o original.
            awk -v new_entry="$GAMEINFO_ENTRY" '
                BEGIN { found=0; }
                // {
                    if (found) {
                        print new_entry;
                        found=0;
                    }
                    print;
                }
                /Game_LowViolence/ { found=1; }
            ' "$GAMEINFO_FILE" > "$GAMEINFO_FILE.tmp" && mv "$GAMEINFO_FILE.tmp" "$GAMEINFO_FILE"
        fi
    fi
}