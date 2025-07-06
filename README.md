<a name="readme-top"></a>

![GitHub tag (with filter)](https://img.shields.io/github/v/tag/arthjhon/CS2-Egg?style=for-the-badge&label=Version)
![GitHub Repo stars](https://img.shields.io/github/stars/arthjhon/CS2-Egg?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/arthjhon/CS2-Egg?style=for-the-badge)
![GitHub](https://img.shields.io/github/license/arthjhon/CS2-Egg?style=for-the-badge)
![GitHub contributors](https://img.shields.io/github/contributors/arthjhon/CS2-Egg?style=for-the-badge)
![GitHub all releases](https://img.shields.io/github/downloads/arthjhon/CS2-Egg/total?style=for-the-badge)
![GitHub last commit (branch)](https://img.shields.io/github/last-commit/arthjhon/CS2-Egg/dev?style=for-the-badge)


# 🥚 CS2 - Pelican Panel Egg

Este repositório contém um **Egg** personalizado para facilitar a implantação de servidores **Counter-Strike 2** (CS2) utilizando o **Pelican Panel**.

## 🎮 Sobre o Counter-Strike 2

> Por mais de duas décadas, Counter-Strike ofereceu uma experiência competitiva de elite moldada por milhões de jogadores ao redor do mundo. Agora, com o CS2, a próxima geração dessa história está pronta para começar.

## 📦 Recursos da Egg

- Baseada na imagem `SteamRT3` compatível com CS2
- Instalação automática do servidor via SteamCMD
- Suporte a atualizações via script
- Otimizada para uso com containers Docker no Pelican
- Pronta para uso com parâmetros personalizáveis
- Suporte a configurações de workshop, mapas e mods

## 🛠️ Requisitos

- Pelican Panel instalado e funcional
- Docker e Docker Compose atualizados
- Host compatível com os requisitos mínimos de CS2 (CPU, RAM, etc.)
- Token do Game Server Account (GSLT) da Steam

## 🚀 Instalação

1. No painel administrativo do Pelican, vá até **Nests > Import**.
2. Importe o arquivo `egg-cs2.json` deste repositório.
3. Atribua o Egg ao Nest desejado ou crie um novo.
4. Crie um novo servidor com base nesta Egg.
5. Preencha os campos obrigatórios como GSLT, portas, etc.

## 🔧 Configurações Suportadas

- `SRCDS_APPID`: `730` (CS2)
- `GSLT_TOKEN`: Token do servidor (obrigatório)
- `MAP`: Mapa inicial (ex: `de_dust2`)
- `GAME_MODE`: Modo de jogo (ex: `competitive`)
- `MAX_PLAYERS`: Número máximo de jogadores

## 📣 Créditos

- [Valve](https://www.valvesoftware.com/) pelo CS2
- [Pelican Panel](https://github.com/pelican-panel) pela plataforma
- Comunidade open source de CS2 por manter a chama acesa 🔥
- [K4ryuu](https://github.com/K4ryuu/CS2-Egg/tree/dev) Pelos scripts e base do nosso Egg.

## 📄 Licença

Este projeto está licenciado sob a **MIT License**. Veja o arquivo [LICENSE](./LICENSE) para mais detalhes.
