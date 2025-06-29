#!/bin/bash

# ------------------------------------------------------------------
# Script de Instalação do SteamCMD
# ------------------------------------------------------------------
#
# Este script contém uma única função, 'install_steamcmd', responsável por
# baixar, extrair e configurar o SteamCMD de forma segura e robusta.

# Importa a função 'log_message' de um arquivo utilitário para logs padronizados.
source /utils/logging.sh

# Definição da função 'install_steamcmd'.
install_steamcmd() {

    # --- Verificação Inicial ---
    # Primeiro, verifica se o SteamCMD já está instalado.
    # Se o arquivo executável já existe, a função informa e termina com sucesso.
    if [ -f "./steamcmd/steamcmd.sh" ]; then
        log_message "SteamCMD já está instalado" "debug"
        return 0 # 'return 0' indica sucesso.
    fi

    log_message "Instalando SteamCMD..." "running"

    # --- Download com Retentativa ---
    local STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    local max_retries=3
    local retry=0

    # Cria os diretórios necessários antes de baixar.
    mkdir -p ./steamcmd    # Para os arquivos do SteamCMD.
    mkdir -p ./steamapps   # Diretório que o SteamCMD usará para baixar jogos.

    # Inicia um loop para tentar baixar o arquivo até 'max_retries' vezes.
    # Isso torna o script mais resiliente a falhas de rede temporárias.
    while [ $retry -lt $max_retries ]; do
        # 'curl': -s (silencioso), -S (mostra erros), -L (segue redirecionamentos).
        # --connect-timeout 30: tempo máximo para estabelecer a conexão.
        # --max-time 300: tempo máximo total para a operação de download.
        if curl -sSL --connect-timeout 30 --max-time 300 -o steamcmd.tar.gz "$STEAMCMD_URL"; then
            break # Se o download for bem-sucedido, sai do loop.
        fi
        ((retry++)) # Incrementa o contador de tentativas.
        log_message "Tentativa de download $retry falhou, tentando novamente..." "error"
        sleep 5 # Espera 5 segundos antes de tentar novamente.
    done

    # Se o loop terminou porque atingiu o número máximo de tentativas, a instalação falhou.
    if [ $retry -eq $max_retries ]; then
        log_message "Falha ao baixar o SteamCMD após $max_retries tentativas" "error"
        return 1 # 'return 1' indica erro.
    fi

    # --- Extração e Limpeza ---
    # Extrai o arquivo baixado para o diretório ./steamcmd.
    # 'tar': -x (extrair), -z (descomprimir gzip), -v (verboso, mostra os arquivos), -f (do arquivo).
    if ! tar -xzvf steamcmd.tar.gz -C ./steamcmd; then
        log_message "Falha ao extrair o SteamCMD" "error"
        return 1
    fi
    # Remove o arquivo .tar.gz baixado para economizar espaço.
    rm steamcmd.tar.gz

    # --- Configuração Pós-Extração ---
    # Verificação de sanidade para garantir que o diretório foi criado corretamente.
    if [ ! -d "./steamcmd" ]; then
        log_message "O diretório steamcmd não existe" "error"
        return 1
    fi

    # Inicializa o SteamCMD pela primeira vez.
    # Isso faz com que ele se auto-atualize e crie os arquivos de configuração necessários.
    # O comando '+quit' faz com que ele feche imediatamente após a atualização.
    ./steamcmd/steamcmd.sh +quit

    # --- Configuração das Bibliotecas Steam ---
    # Muitos servidores dedicados (especialmente os mais antigos) precisam de bibliotecas
    # de 32 e 64 bits em locais específicos para funcionar corretamente.

    # Cria o diretório para as bibliotecas de 32 bits.
    mkdir -p ./.steam/sdk32
    # Copia a biblioteca de 32 bits do SteamCMD para o local esperado.
    # O '||' executa o comando seguinte apenas se a cópia falhar.
    cp -v ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so || {
        log_message "Falha ao copiar bibliotecas de 32-bit" "warning"
    }

    # Cria o diretório para as bibliotecas de 64 bits.
    mkdir -p ./.steam/sdk64
    # Copia a biblioteca de 64 bits.
    cp -v ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so || {
        log_message "Falha ao copiar bibliotecas de 64-bit" "warning"
    }

    # --- Finalização ---
    log_message "SteamCMD instalado com sucesso" "success"
    return 0 # Sucesso!
}