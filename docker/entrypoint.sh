#!/bin/bash

##########################################################################################
# SEÇÃO 1: INICIALIZAÇÃO E PREPARAÇÃO
# Esta seção carrega dependências, define o tratamento de erros e prepara o ambiente.
##########################################################################################

# "source" é como "importar" código de outros arquivos. Isso mantém o script principal limpo.
# Presumivelmente, estes arquivos contêm as funções usadas mais abaixo.
source /scripts/install.sh   # Provavelmente contém a função 'install_steamcmd' e 'configure_metamod'.
source /scripts/cleanup.sh   # Provavelmente contém 'clean_old_logs' e 'cleanup_and_update'.
source /scripts/update.sh    # Provavelmente contém 'version_check_loop'.
source /scripts/filter.sh    # Provavelmente contém 'setup_message_filter' e 'handle_server_output'.

# 'trap' é um "gatilho" para tratamento de erros.
# Se qualquer comando a partir daqui falhar (retornar um status de erro),
# ele executará a função 'handle_error', passando o número da linha e o comando que falhou.
# Isso torna o script muito mais robusto, pois ele não simplesmente "morre" em silêncio.
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# Muda o diretório de trabalho para /home/teranex.
# Este é o diretório padrão que o Painel Pterodactyl usa para todos os servidores de jogos.
cd /home/teranex
sleep 1 # Uma pequena pausa para garantir que o sistema de arquivos esteja pronto.

# Obtém o endereço IP interno do contêiner.
# Este comando encontra a rota padrão e extrai o IP de origem (o IP do próprio contêiner).
# Esse valor será usado para substituir a variável {{SERVER_IP}} do Pterodactyl.
INTERNAL_IP=$(ip route get 1 | awk '{print $NF;exit}')

# Chama funções dos scripts importados para fazer a configuração inicial.
install_steamcmd  # Garante que o SteamCMD (ferramenta de download da Steam) esteja instalado.
clean_old_logs    # Limpa logs antigos para economizar espaço.

##########################################################################################
# SEÇÃO 2: LÓGICA DE INSTALAÇÃO E ATUALIZAÇÃO DO SERVIDOR DE JOGO
# Este é o bloco mais complexo. Ele constrói o comando de atualização do SteamCMD
# dinamicamente com base nas variáveis de ambiente definidas no painel de controle.
##########################################################################################

# Verifica se um AppID de jogo foi fornecido e se a atualização não foi desativada.
if [ ! -z ${SRCDS_APPID} ] && [ ${SRCDS_STOP_UPDATE:-0} -eq 0 ]; then
    log_message "Iniciando SteamCMD para o AppID: ${SRCDS_APPID}" "running"

    # Declara a variável STEAMCMD que conterá o comando final.
    STEAMCMD=""

    # Este ninho de 'if/else' parece complicado, mas é apenas uma árvore de decisão
    # para montar a linha de comando do SteamCMD com os parâmetros corretos.
    
    # 1. O jogo tem uma branch BETA para instalar (`SRCDS_BETAID`)?
    if [ ! -z ${SRCDS_BETAID} ]; then
        # 1a. A beta precisa de uma SENHA (`SRCDS_BETAPASS`)?
        if [ ! -z ${SRCDS_BETAPASS} ]; then
            # 1a-i. O usuário quer VALIDAR os arquivos do servidor? (Verificar tudo e baixar de novo se necessário)
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                # Avisa o usuário que a validação pode apagar arquivos customizados.
                log_message "Flag de Validação do SteamCMD ativada! Validando instalação para o AppID: ${SRCDS_APPID}" "error"
                log_message "ISSO PODE APAGAR CONFIGURAÇÕES CUSTOMIZADAS! Pare o servidor se não for intencional." "error"
                # Usa login customizado ou anônimo?
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} validate +quit"
                fi
            else # Se não for validar...
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} -betapassword ${SRCDS_BETAPASS} +quit"
                fi
            fi
        else # 1b. Se a beta NÃO precisa de senha... (lógica similar)
            if [ ${SRCDS_VALIDATE} -eq 1 ]; then
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} validate +quit"
                fi
            else
                if [ ! -z ${SRCDS_LOGIN} ]; then
                    STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                else
                    STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} -beta ${SRCDS_BETAID} +quit"
                fi
            fi
        fi
    else # 2. Se NÃO for uma branch beta, é a versão padrão do jogo.
        if [ ${SRCDS_VALIDATE} -eq 1 ]; then
            log_message "Flag de Validação do SteamCMD ativada! Validando instalação para o AppID: ${SRCDS_APPID}" "error"
            log_message "ISSO PODE APAGAR CONFIGURAÇÕES CUSTOMIZADAS! Pare o servidor se não for intencional." "error"
            if [ ! -z ${SRCDS_LOGIN} ]; then
                STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} validate +quit"
            else
                STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} validate +quit"
            fi
        else
            if [ ! -z ${SRCDS_LOGIN} ]; then
                STEAMCMD="./steamcmd/steamcmd.sh +login ${SRCDS_LOGIN} ${SRCDS_LOGIN_PASS} +force_install_dir /home/teranex +app_update ${SRCDS_APPID} +quit"
            else
                STEAMCMD="./steamcmd/steamcmd.sh +login anonymous +force_install_dir /home/teranex +app_update ${SRCDS_APPID} +quit"
            fi
        fi
    fi

    # Loga o comando que será executado, mas censura a senha do usuário Steam por segurança.
    log_message "Comando SteamCMD: $(echo "$STEAMCMD" | sed -E 's/(\+login [^ ]+ )[^ ]+/\1****/')" "debug"
    
    # 'eval' executa a string contida na variável STEAMCMD como se fosse um comando digitado no terminal.
    eval ${STEAMCMD}

    # Alguns jogos precisam que o arquivo steamclient.so seja copiado para pastas específicas.
    # Este é um passo de compatibilidade comum.
    cp -f ./steamcmd/linux32/steamclient.so ./.steam/sdk32/steamclient.so
    cp -f ./steamcmd/linux64/steamclient.so ./.steam/sdk64/steamclient.so

    # Se houver mods para configurar (como Metamod), a função para isso é chamada aqui.
    configure_metamod
fi

##########################################################################################
# SEÇÃO 3: TAREFAS FINAIS E EXECUÇÃO DO SERVIDOR
# Prepara o comando final de inicialização, lida com logs e inicia o servidor.
##########################################################################################

# Chama mais funções de limpeza e configuração.
cleanup_and_update    # Outras tarefas de limpeza pós-instalação.
setup_message_filter  # Configura o filtro de mensagens que será usado na saída do servidor.

# Verifica se a reinicialização automática para atualizações está ativada.
if [ "${UPDATE_AUTO_RESTART:-0}" -eq 1 ]; then
    log_message "Auto-restart está ativado. O servidor reiniciará automaticamente se uma nova versão for detectada." "running"
    # O '&' no final executa a função 'version_check_loop' em SEGUNDO PLANO,
    # para que ela possa verificar atualizações enquanto o servidor está rodando.
    version_check_loop &
fi

# PREPARA O COMANDO DE INICIALIZAÇÃO. Esta é a parte "mágica" da integração com Pterodactyl.
# 1. A variável ${STARTUP} vem do painel e contém algo como: "./cs2 -dedicated +ip {{SERVER_IP}} +port {{SERVER_PORT}}"
# 2. O primeiro 'sed' transforma `{{VAR}}` em `${VAR}` (formato que o shell entende).
# 3. 'eval echo' executa a string resultante. O shell vê, por exemplo, `${SERVER_IP}` e substitui pelo valor da variável.
MODIFIED_STARTUP=$(eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g'))

# Adiciona 'unbuffer -p' ao início do comando. Isso força o programa do servidor a
# enviar seus logs linha por linha, sem esperar, o que é essencial para o console em tempo real do painel.
MODIFIED_STARTUP="unbuffer -p ${MODIFIED_STARTUP}"

# Loga o comando de inicialização que será usado, mas novamente, censura o GSLT (+sv_setsteamaccount) por segurança.
LOGGED_STARTUP=$(echo "${MODIFIED_STARTUP#unbuffer -p }" | \
    sed -E 's/(\+sv_setsteamaccount\s+[A-Z0-9]{32})/+sv_setsteamaccount ************************/g')
log_message "Iniciando servidor com o comando: ${LOGGED_STARTUP}" "running"

# EXECUTA O SERVIDOR E CAPTURA SUA SAÍDA (STDOUT e STDERR).
# `$MODIFIED_STARTUP`: Executa o comando final.
# `2>&1`: Redireciona a saída de erro (2) para a saída padrão (1).
# `| while ...`: Envia toda a saída, linha por linha, para o loop 'while'.
$MODIFIED_STARTUP 2>&1 | while IFS= read -r line; do
    # Remove espaços em branco no final da linha.
    line="${line%[[:space:]]}"
    # Ignora a mensagem "Segmentation fault" que às vezes aparece quando o servidor fecha.
    [[ "$line" =~ Segmentation\ fault.*"${GAMEEXE}" ]] && continue
    # Envia cada linha para a função 'handle_server_output', que pode colorir, filtrar ou
    # reagir a mensagens específicas (ex: "Server is shutting down").
    handle_server_output "$line"
done

# Quando o loop acima termina (ou seja, o processo do servidor de jogo foi encerrado),
# este comando finaliza quaisquer processos que este script tenha iniciado em segundo plano (como o version_check_loop).
pkill -P $$ 2>/dev/null || true

log_message "Servidor parado com sucesso." "success"