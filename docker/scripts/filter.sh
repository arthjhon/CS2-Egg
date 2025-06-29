#!/bin/bash

# ------------------------------------------------------------------
# Script de Filtragem e Manipulação de Saída do Servidor
# ------------------------------------------------------------------
#
# Este script tem duas funções principais:
# 1. setup_message_filter: Carrega regras de um arquivo de configuração para silenciar ou mascarar mensagens.
# 2. handle_server_output: Processa cada linha de saída do servidor, aplicando as regras de filtragem.

# Importa a função de logging para mensagens padronizadas.
source /utils/logging.sh

# ==================================================================
# FUNÇÃO: setup_message_filter
# Prepara o filtro carregando padrões de um arquivo de configuração.
# ==================================================================
setup_message_filter() {
    # Verifica a variável de ambiente. Se o filtro não estiver ativado, a função encerra.
    if [ "${ENABLE_FILTER:-0}" != "1" ]; then
        log_message "Filtro está desativado. Nenhuma mensagem será bloqueada." "running"
        return 0
    fi

    # --- Criação de Configuração Padrão ---
    # Se o arquivo de configuração não existir, cria um com exemplos.
    # Isso ajuda o usuário a começar a usar o recurso sem precisar criar o arquivo manualmente.
    if [ ! -f "/home/teranex/game/mute_messages.cfg" ]; then
        # 'cat' com '<<'EOL'' (Here Document) é uma forma limpa de escrever múltiplas linhas em um arquivo.
        cat > "/home/teranex/game/mute_messages.cfg" <<'EOL'
# Arquivo de Configuração para Silenciar Mensagens
# Use @ no início para correspondência exata, caso contrário, será tratado como "contém".
# Exemplo: @correspondência exata
# Exemplo: contém isso em qualquer lugar
Certificate expires
EOL
        log_message "Arquivo padrão mute_messages.cfg foi criado" "running"
    fi

    # --- Pré-processamento dos Padrões ---
    # Usa arrays associativos para armazenar os padrões.
    # Isso é MUITO mais eficiente para busca do que ler o arquivo a cada linha.
    # 'declare -gA' cria um array associativo global, acessível em outras funções.
    declare -gA EXACT_PATTERNS=()
    declare -gA CONTAINS_PATTERNS=()

    # Adiciona o token da Steam (GSLT) aos padrões para ser mascarado, se ele existir.
    # A chave é o token, e o valor é a máscara de asteriscos.
    if [ ! -z "${STEAM_ACC}" ]; then
        CONTAINS_PATTERNS["${STEAM_ACC}"]="********************************"
    fi

    # --- Leitura do Arquivo de Configuração ---
    local pattern_count=0
    # Loop 'while' para ler o arquivo linha por linha de forma segura.
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Pula comentários (linhas que começam com #) e linhas vazias.
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Processa o padrão da linha.
        if [[ $line == @* ]]; then
            # Se a linha começa com '@', é uma correspondência exata.
            # Adiciona a linha (sem o '@') ao array de padrões exatos.
            EXACT_PATTERNS["${line#@}"]="1"
        else
            # Caso contrário, é uma correspondência de "contém".
            # Adiciona a linha ao array de padrões de conteúdo.
            CONTAINS_PATTERNS["$line"]="1"
        fi
        ((pattern_count++))
    done < "./game/mute_messages.cfg"

    log_message "Carregados $pattern_count padrões de filtro (${#EXACT_PATTERNS[@]} exatos, ${#CONTAINS_PATTERNS[@]} de conteúdo). Modifique mute_messages.cfg para adicionar mais." "running"
}

# ==================================================================
# FUNÇÃO: handle_server_output
# É chamada para CADA linha de saída do servidor de jogo.
# ==================================================================
handle_server_output() {
    local line="$1"

    # Retorno rápido para linhas vazias para evitar processamento desnecessário.
    [[ -z "$line" ]] && {
        printf '%s\n' "$line"
        return
    }

    # --- Lógica de Gatilho ---
    # Verifica se a linha indica que a conexão com a Steam foi bem-sucedida.
    # Se sim, e se a reinicialização automática estiver ligada, inicia o loop de verificação de versão em segundo plano.
    # Isso garante que a verificação de updates só comece quando o servidor estiver totalmente online.
    if [[ "$line" == "SV:  Connection to Steam servers successful." && "${UPDATE_AUTO_RESTART:-0}" -eq 1 ]]; then
        log_message "Auto-Restart ativado. O servidor será reiniciado ao detectar uma atualização do jogo." "running"
        version_check_loop & # O '&' executa o comando em segundo plano.
    fi

    # Se o filtro estiver desativado, apenas imprime a linha e retorna.
    if [ "${ENABLE_FILTER:-0}" != "1" ]; then
        printf '%s\n' "$line"
        return
    fi

    # --- Lógica de Filtragem ---
    local blocked=false
    local modified_line="$line"

    # 1. Verifica correspondências exatas primeiro (geralmente mais rápido).
    for pattern in "${!EXACT_PATTERNS[@]}"; do
        if [[ "$line" == "$pattern" ]]; then
            blocked=true
            break # Encontrou uma correspondência, não precisa continuar.
        fi
    done

    # 2. Se a linha não foi bloqueada, verifica as correspondências de "contém".
    if [[ "$blocked" == false ]]; then
        for pattern in "${!CONTAINS_PATTERNS[@]}"; do
            if [[ $line == *"$pattern"* ]]; then
                # Verifica se o padrão tem um valor de substituição associado.
                if [ -n "${CONTAINS_PATTERNS[$pattern]}" ] && [ "${CONTAINS_PATTERNS[$pattern]}" != "1" ]; then
                    # Se tiver (ex: a máscara de asteriscos do token), substitui o padrão na linha.
                    modified_line=${modified_line//$pattern/${CONTAINS_PATTERNS[$pattern]}}
                else
                    # Se não tiver valor de substituição, apenas bloqueia a linha.
                    blocked=true
                    break
                fi
            fi
        done
    fi

    # --- Saída Final ---
    if [[ "$blocked" == true ]]; then
        # Se a linha foi bloqueada, verifica se o "modo de pré-visualização" está ativo.
        # Se estiver, loga a mensagem que foi bloqueada, útil para depurar os filtros.
        if [ "${FILTER_PREVIEW_MODE:-0}" = "1" ]; then
            log_message "Mensagem bloqueada: $line" "debug"
        fi
        # Se não estiver no modo de pré-visualização, não faz nada (silencia a mensagem).
    else
        # Se a linha não foi bloqueada, imprime a versão original ou modificada.
        printf '%s\n' "$modified_line"
    fi
}