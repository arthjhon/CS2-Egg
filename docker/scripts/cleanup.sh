#!/bin/bash
# ------------------------------------------------------------------
# Script de Limpeza de Arquivos do Servidor
# ------------------------------------------------------------------
#
# Este script contém funções para verificar o espaço em disco, formatar tamanhos de arquivo
# e a função principal 'cleanup' que apaga arquivos antigos de forma segura e configurável.

# Importa utilitários de logging para mensagens padronizadas.
source /utils/logging.sh

# ==================================================================
# SEÇÃO 1: FUNÇÕES UTILITÁRIAS
# Funções de apoio que realizam tarefas específicas e reutilizáveis.
# ==================================================================

# --- Função para verificar o espaço livre no sistema de arquivos ---
check_filesystem() {
    local dir="$1"
    local required_space=1048576  # Define um limite de 1GB (em KB) como aviso.

    # Obtém informações do sistema de arquivos de forma segura.
    # 'df -k "$dir"': Mostra o espaço em disco em kilobytes para o diretório especificado.
    # '2>/dev/null': Suprime mensagens de erro se o comando falhar.
    # 'tail -n 1': Pega apenas a última linha, que contém os dados.
    local fs_info
    if ! fs_info=$(df -k "$dir" 2>/dev/null | tail -n 1); then
        log_message "Falha ao obter informações do sistema de arquivos para $dir" "error"
        return 1
    fi

    # Extrai a 4ª coluna (espaço disponível) usando 'awk'.
    local available
    available=$(echo "$fs_info" | awk '{print $4}')
    # Validação para garantir que o valor extraído é realmente um número. Essencial para evitar erros.
    if [[ ! "$available" =~ ^[0-9]+$ ]]; then
        log_message "Informação inválida do sistema de arquivos recebida" "error"
        return 1
    fi

    # Compara o espaço disponível com o limite e emite um aviso se for baixo.
    if [ "$available" -lt "$required_space" ]; then
        log_message "Aviso de pouco espaço em disco: Menos de 1GB disponível" "warning"
    fi

    return 0
}

# --- Função para formatar um tamanho em bytes para um formato legível (KB, MB, GB) ---
format_size() {
    local size="$1"
    # Valida se a entrada é um número.
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        echo "0 B"
        return 1
    fi

    # Usa 'bc' (calculadora de linha de comando) para fazer cálculos com casas decimais, algo que o shell não faz nativamente.
    if [ "$size" -ge 1073741824 ]; then
        printf "%.2f GB" "$(echo "scale=2; $size/1073741824" | bc)"
    elif [ "$size" -ge 1048576 ]; then
        printf "%.2f MB" "$(echo "scale=2; $size/1048576" | bc)"
    elif [ "$size" -ge 1024 ]; then
        printf "%.2f KB" "$(echo "scale=2; $size/1024" | bc)"
    else
        printf "%d B" "$size"
    fi
}

# ==================================================================
# SEÇÃO 2: FUNÇÃO PRINCIPAL DE LIMPEZA ('cleanup')
# Orquestra todo o processo de limpeza.
# ==================================================================
cleanup() {
    log_message "Iniciando limpeza..." "running"

    # --- Validações Iniciais ---
    # Garante que as variáveis essenciais estão definidas e que os diretórios existem.
    if [ -z "$GAME_DIRECTORY" ]; then
        log_message "A variável GAME_DIRECTORY não está definida" "error"
        return 1
    fi
    if [ ! -d "$GAME_DIRECTORY" ]; then
        log_message "O diretório GAME_DIRECTORY não existe: $GAME_DIRECTORY" "error"
        return 1
    fi

    # Chama a função de verificação de espaço como uma medida de segurança.
    if ! check_filesystem "$GAME_DIRECTORY"; then
        log_message "A verificação do sistema de arquivos falhou" "error"
        return 1
    fi

    # --- Configuração ---
    # Define os intervalos (em horas) para apagar diferentes tipos de arquivos.
    local BACKUP_ROUND_PURGE_INTERVAL=24      # Backups de round > 24h serão apagados.
    local DEMO_PURGE_INTERVAL=168             # Demos > 168h (7 dias) serão apagadas.
    local CSS_JUNK_PURGE_INTERVAL=72          # Logs do CSSharp > 72h (3 dias) serão apagados.
    local ACCELERATOR_DUMP_PURGE_INTERVAL=168 # Dumps de erro > 168h serão apagados.
    local ACCELERATOR_DUMPS_DIR="${OUTPUT_DIR:-$GAME_DIRECTORY}/AcceleratorCS2/dumps"

    # --- Estatísticas ---
    # Inicializa um array associativo para contar quantos arquivos de cada tipo foram apagados.
    declare -A stats=(
        ["backup_rounds"]=0
        ["demos"]=0
        ["css_logs"]=0
        ["accelerator_logs"]=0
        ["accelerator_dumps"]=0
    )
    local start_time=$(date +%s) # 'date +%s' retorna o tempo em segundos desde 1970 (Unix timestamp).
    local total_size=0
    local deleted_count=0

    # --- Função Aninhada para Deleção ---
    # Centraliza a lógica de apagar um arquivo e registrar a ação. É uma ótima prática de organização.
    log_deletion() {
        local file="$1"
        local category="$2"

        if [ ! -f "$file" ]; then return 1; fi

        # Obtém o tamanho do arquivo. O comando 'stat' varia entre sistemas (GNU vs BSD).
        # Este comando tenta as duas formas, garantindo a compatibilidade.
        local size
        size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)
        if [ $? -ne 0 ] || [[ ! "$size" =~ ^[0-9]+$ ]]; then size=0; fi

        # Tenta apagar o arquivo.
        if rm -f "$file"; then
            # Se conseguir, atualiza as estatísticas.
            total_size=$((total_size + size))
            ((stats[$category]++))
            ((deleted_count++))
            # Loga a ação em modo debug, mostrando o nome e o tamanho formatado.
            log_message "Apagado ${category}: ${file##*/} ($(format_size "$size"))" "debug"
        else
            log_message "Falha ao apagar: $file" "error"
        fi
    }

    # --- Processamento dos Arquivos ---
    # A forma mais segura de usar 'find' com 'while read' para lidar com nomes de arquivo com espaços ou caracteres especiais.
    # 'find ... -print0': Encontra os arquivos e os imprime separados por um caractere nulo.
    # 'while IFS= read -r -d '' file': Lê a entrada separada por caractere nulo.
    while IFS= read -r -d '' file; do
        if [[ "$file" == *"backup_round"* ]]; then
            log_deletion "$file" "backup_rounds"
        elif [[ "$file" == *.dem ]]; then
            log_deletion "$file" "demos"
        elif [[ "$file" == */addons/counterstrikesharp/logs/* ]]; then
            log_deletion "$file" "css_logs"
        fi
    done < <(find "$GAME_DIRECTORY" \( \
        -name "backup_round*.txt" -mmin "+$((BACKUP_ROUND_PURGE_INTERVAL*60))" -o \
        -name "*.dem" -mmin "+$((DEMO_PURGE_INTERVAL*60))" -o \
        \( -path "*/addons/counterstrikesharp/logs/*.txt" -mmin "+$((CSS_JUNK_PURGE_INTERVAL*60))" \) \
        \) -print0 2>/dev/null) # '-mmin' verifica a idade em minutos. Multiplicamos as horas por 60.

    # Bloco separado para lidar com os logs/dumps do "Accelerator".
    if [ -d "$ACCELERATOR_DUMPS_DIR" ]; then
        while IFS= read -r -d '' file; do
            if [[ "$file" == *.dmp.txt ]]; then
                log_deletion "$file" "accelerator_logs"
            else
                log_deletion "$file" "accelerator_dumps"
            fi
        done < <(find "$ACCELERATOR_DUMPS_DIR" \( -name "*.dmp.txt" -o -name "*.dmp" \) -mmin "+$((ACCELERATOR_DUMP_PURGE_INTERVAL*60))" -print0 2>/dev/null)
    fi

    # --- Relatório Final ---
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Imprime um resumo do que foi feito.
    if ((deleted_count > 0)); then
        log_message "Limpeza concluída com sucesso! Liberado $(format_size "$total_size") em $deleted_count arquivos em $duration segundos." "success"
        # Imprime um detalhamento por categoria em modo debug.
        for category in "${!stats[@]}"; do
            if ((stats[$category] > 0)); then
                log_message "- $category: ${stats[$category]} files" "debug"
            fi
        done
    else
        log_message "Limpeza concluída. Nenhum arquivo foi apagado." "success"
    fi

    return 0
}