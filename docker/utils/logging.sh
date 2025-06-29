#!/bin/bash

# ------------------------------------------------------------------
# Script Utilitário de Logging e Tratamento de Erros
# ------------------------------------------------------------------
#
# Este script fornece um conjunto de funções para criar logs padronizados,
# coloridos e com níveis de prioridade, além de um manipulador de erros
# para ser usado com 'trap'.

# ==================================================================
# SEÇÃO 1: CONSTANTES E CONFIGURAÇÕES GLOBAIS
# ==================================================================

# Define códigos de escape ANSI para cores no terminal.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color (reseta a cor para o padrão).

# Define valores padrão para as variáveis de ambiente usando expansão de parâmetro.
# Se a variável não estiver definida, ela recebe o valor padrão.
LOG_FILE_ENABLED="${LOG_FILE_ENABLED:=0}"        # Habilitar log em arquivo? (0=Não, 1=Sim).
LOG_FILE="${LOG_FILE:=./egg.log}"                 # Caminho do arquivo de log.
LOG_RETENTION_HOURS="${LOG_RETENTION_HOURS:=48}"  # Por quantas horas manter os arquivos de log.
PREFIX="${PREFIX:=${RED}[KitsuneLab]${WHITE} > }" # Prefixo para todas as mensagens no console.

# ==================================================================
# SEÇÃO 2: GERENCIAMENTO DE NÍVEL DE LOG (Log Level)
# Permite controlar a verbosidade dos logs (ex: mostrar apenas erros, ou tudo incluindo debug).
# ==================================================================

# Declara um array associativo para mapear nomes de níveis de log a uma prioridade numérica.
declare -A log_levels=(
    ["debug"]=0
    ["info"]=1
    ["running"]=2 # 'running' e 'success' podem ter prioridades similares a 'info'.
    ["success"]=2
    ["warning"]=3
    ["error"]=4
)

# Função para converter a variável de ambiente LOG_LEVEL (ex: "INFO") em um número.
get_level_priority() {
    local log_level="${LOG_LEVEL:-INFO}" # Usa "INFO" como padrão.
    # Usa a expansão `${log_level^^}` para converter a string para maiúsculas, tornando a verificação case-insensitive.
    case "${log_level^^}" in
        "DEBUG") echo 0 ;;
        "INFO") echo 1 ;;
        "WARNING") echo 3 ;;
        "ERROR") echo 4 ;;
        *) echo 1 ;; # Padrão para INFO se o valor for inválido.
    esac
}

# Executa a função uma vez no início e armazena o resultado.
# Isso é mais eficiente do que chamar a função toda vez que uma mensagem é logada.
LOG_LEVEL_PRIORITY=$(get_level_priority)

# ==================================================================
# SEÇÃO 3: LIMPEZA DE LOGS ANTIGOS (Log Rotation)
# ==================================================================
clean_old_logs() {
    # '[[ ... ]]' é uma forma mais moderna e segura de fazer testes condicionais.
    # Se o log em arquivo não estiver habilitado, a função retorna imediatamente.
    [[ "${LOG_FILE_ENABLED}" == "1" ]] || return 0

    local log_dir
    local log_name

    # 'dirname' e 'basename' são comandos para extrair o diretório e o nome do arquivo de um caminho.
    log_dir="$(dirname "${LOG_FILE}")"
    log_name="$(basename "${LOG_FILE}")"

    if [[ -d "${log_dir}" ]]; then
        # Usa 'find' para localizar e apagar arquivos de log antigos.
        # -name "${log_name}*": Procura por 'egg.log', 'egg.log.1', etc.
        # -type f: Apenas arquivos.
        # -mmin "+$((...))": Modificados há mais de X minutos.
        # -delete: Apaga os arquivos encontrados.
        # '2>/dev/null' suprime erros (ex: permissão negada).
        find "${log_dir}" -name "${log_name}*" -type f -mmin "+$((LOG_RETENTION_HOURS * 60))" -delete 2>/dev/null
    fi
}

# ==================================================================
# SEÇÃO 4: FUNÇÃO PRINCIPAL DE LOGGING ('log_message')
# Esta é a função que todos os outros scripts chamam para exibir e salvar mensagens.
# ==================================================================
log_message() {
    local message="$1"
    local type="${2:-info}" # O tipo da mensagem, padrão "info".
    local msg_priority="${log_levels[$type]:-1}" # Obtém a prioridade da mensagem do array.

    # --- Verificação de Nível de Log ---
    # A linha mais importante para o controle de verbosidade.
    # Se a prioridade da mensagem for MENOR que a prioridade global definida, a função para aqui.
    # Ex: Se LOG_LEVEL_PRIORITY é 4 (ERROR), mensagens de INFO (1) ou DEBUG (0) não serão exibidas.
    [[ ${msg_priority} -ge ${LOG_LEVEL_PRIORITY} ]] || return 0

    # --- Formatação ---
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')" # Gera um timestamp formatado.
    message="${message%[[:space:]]}" # Remove quaisquer espaços em branco no final da mensagem.

    # --- Saída para o Console (com cores) ---
    # 'case' para aplicar a cor correta com base no tipo da mensagem.
    case "$type" in
        running) printf "%b%s%b\n" "${PREFIX}${YELLOW}" "$message" "${NC}" ;;
        error)   printf "%b%s%b\n" "${PREFIX}${RED}" "$message" "${NC}" ;;
        success) printf "%b%s%b\n" "${PREFIX}${GREEN}" "$message" "${NC}" ;;
        debug)   printf "%b[DEBUG] %s%b\n" "${PREFIX}${WHITE}" "$message" "${NC}" ;;
        *)       printf "%b%s%b\n" "${PREFIX}${WHITE}" "$message" "${NC}" ;;
    esac

    # --- Saída para o Arquivo (se habilitado) ---
    if [[ "${LOG_FILE_ENABLED}" == "1" ]]; then
        # 'echo' para escrever a mensagem (sem cores) no arquivo de log.
        # '>>' anexa ao final do arquivo em vez de sobrescrevê-lo.
        echo "[$timestamp] [$type] $message" >> "${LOG_FILE}"
    fi
}

# ==================================================================
# SEÇÃO 5: FUNÇÃO DE TRATAMENTO DE ERROS ('handle_error')
# Projetada para ser chamada pelo comando 'trap' quando um erro ocorre.
# ==================================================================
handle_error() {
    local exit_code=$? # '$?' captura o código de saída do último comando que falhou.
    local line_number="${1:-}"
    local last_command="${2:-$BASH_COMMAND}" # '$BASH_COMMAND' contém o comando que está sendo executado.

    # Lida com casos específicos de erro.
    case $exit_code in
        127) # Código de erro para "comando não encontrado".
            log_message "Comando não encontrado: $last_command" "error"
            log_message "Código de saída: 127" "error"
            ;;
        0) # Se o código for 0, é um sucesso, não faz nada.
            return 0
            ;;
        *) # Para todos os outros erros.
            # Condição especial para ignorar erros conhecidos e não críticos do steamcmd.sh.
            # O script do steamcmd às vezes retorna códigos de erro mesmo em operações normais.
            if [[ $last_command != *"eval ${STEAMCMD}"* ]]; then
                log_message "Erro na linha $line_number: $last_command" "error"
                log_message "Código de saída: $exit_code" "error"
            fi
            ;;
    esac

    # Retorna o código de erro original, permitindo que o script principal decida se deve parar.
    return $exit_code
}