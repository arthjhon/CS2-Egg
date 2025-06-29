#!/bin/bash

# ------------------------------------------------------------------
# Script de Verificação e Reinicialização Automática por Atualização
# ------------------------------------------------------------------
#
# Este script cria um loop em segundo plano para monitorar atualizações do jogo
# e automatizar o processo de reinicialização do servidor de forma segura e informativa.

# Importa as funções de logging.
# source /utils/logging.sh # (Omitido para focar no script atual, mas estaria aqui)

# ==================================================================
# SEÇÃO 1: VARIÁVEIS GLOBAIS DE CONTROLE
# Variáveis que mantêm o estado do processo de atualização.
# ==================================================================

LAST_NEWS_DATE=0      # Armazena o timestamp do último patch note visto.
UPDATE_IN_PROGRESS=0  # Uma flag (mutex) para indicar se uma atualização já está em andamento (0=Não, 1=Sim).

# ==================================================================
# SEÇÃO 2: FUNÇÃO DE CONTAGEM REGRESSIVA E REINICIALIZAÇÃO
# Esta função é o coração da automação, lidando com os avisos e a reinicialização.
# ==================================================================
start_update_countdown() {
    local required_version="$1"

    UPDATE_IN_PROGRESS=1 # Trava o processo, impedindo novos ciclos de atualização.

    # --- Validação das Variáveis da API do Pterodactyl ---
    if [ -z "$PTERODACTYL_API_TOKEN" ] || [ -z "$P_SERVER_UUID" ] || [ -z "$PTERODACTYL_URL" ]; then
        log_message "Faltando variáveis de API necessárias para a reinicialização" "error"
        UPDATE_IN_PROGRESS=0 # Libera a trava.
        return 1
    fi

    # --- Lógica de Comandos Programados ---
    # Verifica se o usuário definiu comandos customizados para a contagem regressiva.
    if [ -n "$UPDATE_COMMANDS" ]; then
        local start_time=$(date +%s)
        local commands

        # Usa 'jq' para transformar o JSON de comandos (ex: {"300": "say Aviso 1", "60": "say Aviso 2"})
        # em uma lista de 'segundos comando' (ex: 300 say Aviso 1\n60 say Aviso 2).
        commands=$(echo "$UPDATE_COMMANDS" | jq -r 'to_entries | .[] | .key + " " + .value')

        # Lê cada linha da lista de comandos.
        while IFS=' ' read -r seconds command || [ -n "$seconds" ]; do
            # Pula comandos programados para depois do tempo total da contagem regressiva.
            if [ "$seconds" -gt "$UPDATE_COUNTDOWN_TIME" ]; then continue; fi

            # --- Lógica de Temporização ---
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time)) # Tempo já decorrido.
            local target_wait=$((UPDATE_COUNTDOWN_TIME - seconds)) # Ponto no tempo em que o comando deve ser enviado.
            local wait_time=$((target_wait - elapsed)) # Quanto tempo real ainda precisa esperar.

            # Se o tempo de espera for positivo, dorme por esse período.
            if [ "$wait_time" -gt 0 ]; then
                sleep "$wait_time"
            fi

            # --- Envio do Comando via API ---
            if [ -n "$command" ]; then
                local response
                # Usa 'curl' para fazer uma chamada POST para a API do Pterodactyl, enviando o comando.
                response=$(curl -s -w "%{http_code}" -X POST \
                    -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{\"command\": \"$command\"}" \
                    "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/command")

                local http_code=${response: -3} # Extrai os 3 últimos caracteres da resposta (o código HTTP).
                if [[ $http_code -lt 200 || $http_code -gt 299 ]]; then
                    log_message "Falha ao enviar comando via Auto-Restart: HTTP $http_code" "error"
                    UPDATE_IN_PROGRESS=0
                    return 1
                fi
                log_message "Comando enviado via Auto-Restart: $command" "running"
            fi
        done <<< "$commands" # '<<<' é um "Here String", passa a variável 'commands' para o loop.
    else
        # Se não houver comandos customizados, simplesmente espera o tempo total da contagem.
        sleep "$UPDATE_COUNTDOWN_TIME"
    fi

    log_message "Reiniciando o servidor via Auto-Restart..." "running"

    # --- Envio do Sinal de Reinicialização via API ---
    local restart_response
    restart_response=$(curl -s -w "%{http_code}" "$PTERODACTYL_URL/api/client/servers/$P_SERVER_UUID/power" \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $PTERODACTYL_API_TOKEN" \
        -X POST \
        -d '{"signal": "restart"}') # Envia o sinal de "restart".

    local restart_code=${restart_response: -3}
    if [[ $restart_code -lt 200 || $restart_code -gt 299 ]]; then
        log_message "Falha ao reiniciar o servidor: HTTP $restart_code" "error"
        UPDATE_IN_PROGRESS=0
        return 1
    fi
}

# ==================================================================
# SEÇÃO 3: FUNÇÃO DE NOTIFICAÇÃO VIA DISCORD
# Envia uma mensagem formatada para um webhook do Discord.
# ==================================================================
send_discord_webhook() {
    # Se a URL do webhook não estiver definida, não faz nada.
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then return 0; fi

    local patch_date="$1"
    local countdown_time="$2"
    local formatted_date=$(date -d @"$patch_date" "+%Y-%m-%d %H:%M:%S") # Formata o timestamp Unix.
    local timestamp=$(date +%Y-%m-%dT%H:%M:%SZ) # Timestamp no formato ISO 8601 para o Discord.

    # 'cat <<EOF' (Here Document) para construir o payload JSON da mensagem do Discord.
    local payload
    payload=$(cat <<EOF
{
  "username": "Auto Restart",
  "avatar_url": "https://kitsune-lab.com/storage/images/server.png",
  "embeds": [ {
      "title": ":warning: Atualização do Servidor Agendada :warning:",
      "description": "Novo patch do jogo detectado. Iniciando contagem regressiva para atualização...",
      "color": 16753920,
      "fields": [
        {"name": ":calendar: Data do Patch", "value": "$formatted_date", "inline": true},
        {"name": ":hourglass: Contagem Regressiva", "value": "$countdown_time segundos", "inline": true}
      ],
      "footer": {"text": "Serviço de Auto Restart"},
      "timestamp": "$timestamp"
  } ]
}
EOF
)
    # Envia o payload para a URL do webhook.
    local response http_code
    response=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL")
    http_code="${response: -3}"
    if [ "$http_code" -lt 200 ] || [ "$http_code" -gt 299 ]; then
        log_message "Falha ao enviar webhook para o Discord: HTTP $http_code" "error"
    fi
}

# ==================================================================
# SEÇÃO 4: FUNÇÃO DE DETECÇÃO DE ATUALIZAÇÃO
# Verifica a API da Steam em busca de novos patch notes.
# ==================================================================
check_for_new_patchnotes() {
    # Não faz nada se uma atualização já estiver em andamento.
    if [ "$UPDATE_IN_PROGRESS" -eq 1 ]; then return 0; fi

    if [ -z "$STEAM_API_KEY" ]; then
        log_message "STEAM_API_KEY não está definida. Não é possível verificar atualizações." "error"
        return 1
    fi

    # URL da API de notícias da Steam para o CS2 (appid 730), pegando apenas o último patch note.
    local steam_api_url="http://api.steampowered.com/ISteamNews/GetNewsForApp/v0002/?appid=730&count=1&maxlength=300&format=json&tags=patchnotes&key=$STEAM_API_KEY"
    local response=$(curl -s "$steam_api_url")

    if [ -z "$response" ]; then log_message "Sem resposta da API da Steam." "error"; return 1; fi

    # Usa 'jq' para extrair a data do item de notícia. Se não encontrar, retorna 0.
    local news_date=$(echo "$response" | jq -r '.appnews.newsitems[0].date // 0')
    if [ "$news_date" -eq 0 ]; then log_message "Falha ao extrair data válida da API da Steam." "error"; return 1; fi

    # --- Lógica de Comparação ---
    # Na primeira execução, apenas armazena a data mais recente e sai.
    if [ "$LAST_NEWS_DATE" -eq 0 ]; then
        LAST_NEWS_DATE="$news_date"
        log_message "Dados iniciais do patch armazenados: $news_date" "debug"
        return 0
    fi

    # Se a data da notícia mais recente for MAIOR que a última data armazenada, um patch foi lançado!
    if [ "$news_date" -gt "$LAST_NEWS_DATE" ]; then
        log_message "Novo patch do jogo detectado: $news_date" "info"
        log_message "Iniciando contagem regressiva para atualização..." "info"

        # Aciona as notificações e o processo de reinicialização.
        send_discord_webhook "$news_date" "$UPDATE_COUNTDOWN_TIME"
        start_update_countdown "$news_date"

        # Atualiza a última data vista para a data do novo patch.
        LAST_NEWS_DATE="$news_date"
    fi
}

# ==================================================================
# SEÇÃO 5: FUNÇÃO DE LOOP PRINCIPAL
# A função que roda em segundo plano, chamando o verificador periodicamente.
# ==================================================================
version_check_loop() {
    # Define um intervalo padrão de 60s se não for definido ou for muito baixo.
    if [ -z "$VERSION_CHECK_INTERVAL" ] || [ "$VERSION_CHECK_INTERVAL" -lt 60 ]; then
        VERSION_CHECK_INTERVAL=60
        log_message "VERSION_CHECK_INTERVAL não definido ou menor que 1 min. Usando valor padrão: 1 min" "warning"
    fi

    # Loop infinito que só executa se a reinicialização automática estiver ligada E nenhuma atualização estiver em progresso.
    while [ "${UPDATE_AUTO_RESTART:-0}" -eq 1 ] && [ "$UPDATE_IN_PROGRESS" -eq 0 ]; do
        sleep "${VERSION_CHECK_INTERVAL}"
        check_for_new_patchnotes
    done
}