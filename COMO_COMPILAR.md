# Guia de Compilação Nativa para Linux (x86-64-v2 / Ivy Bridge / Intel HD 4000)

Este repositório contém o código-fonte adaptado do projeto **NSMB-Wii-Multiplayer-Recompilation** para rodar nativamente em Linux com arquiteturas legadas (baseline `x86-64-v2` / Intel Core i7 3ª Geração Ivy Bridge / HD 4000) utilizando **SFML 3.1.0** e **OpenGL 3.3 Core Profile**, dispensando a necessidade de Vulkan 1.1+ ou Direct3D 12.

---

## ⚠️ AVISO IMPORTANTE: Requisito Obrigatório da ROM

> [!IMPORTANT]
> **Este projeto NÃO contém nenhum arquivo protegido por direitos autorais da Nintendo** (nenhuma ROM, disco, áudio, textura ou binário do jogo).
>
> Para compilar o executável, você **DEVE** possuir a sua própria cópia limpa da **Revisão 1 Americana** do jogo:
>
> **`New Super Mario Bros. Wii (USA) (Rev 1)`**
> - **Game ID:** `SMNE01`
> - **Revision:** `1`
> - **Formatos aceitos:** `.rvz`, `.iso`, `.wbfs`
> - **Hash do `main.dol` limpo (Redump Rev 1):** `166eb6b7cca21418e316a6cfbf1bfbf0a213eb8f6396d42126a1482bb764a955`

### Por que precisa ser a Rev 1?
A recompilação estática mapeia cada função, offset de memória e ponteiro diretamente a partir dos binários compilados pela Nintendo. Versões diferentes (como Rev 0 / v1.00 ou Rev 2 / v1.02) possuem alinhamentos e tabelas de símbolos diferentes, fazendo com que a geração de código C++ falhe.

---

## 1. Pré-requisitos e Dependências do Sistema

Antes de iniciar a compilação, certifique-se de que os seguintes pacotes estejam instalados:

### CachyOS / Arch Linux:
```bash
sudo pacman -S --needed \
    dotnet-sdk \
    clang \
    ninja \
    cmake \
    sfml \
    sdl3 \
    crypto++ \
    pugixml \
    python
```

### Extração do Disco:
Para extrair automaticamente as imagens `.rvz`, instale o Dolphin pelo Flatpak (recomendado):
```bash
flatpak install flathub org.DolphinEmu.dolphin-emu
```
*(Caso prefira, você também pode usar o binário `dolphin-tool` nativo do sistema ou extrair o disco manualmente no Dolphin GUI).*

---

## 2. Como Compilar (Método Automático em 1 Passo)

O processo de compilação foi completamente automatizado pelo script `build.sh`.

### Opção A: Passando o arquivo `.rvz` / `.iso` como parâmetro
```bash
./build.sh "/caminho/para/New Super Mario Bros. Wii (USA) (En,Fr,Es) (Rev 1).rvz"
```

### Opção B: Colocando a ROM na pasta
1. Coloque a sua cópia da Rev 1 na raiz desta pasta (ou crie uma pasta chamada `rom/` e coloque nela).
2. Execute apenas:
```bash
./build.sh
```

### O que o script faz automaticamente:
1. **Compila o Tradutor .NET:** Gera o `Translator.Cli` a partir do código C#.
2. **Extrai e Pré-vincula os Módulos:** Extrai o disco usando o Dolphin, descompacta os 4 módulos REL (`d_profileNP`, `d_basesNP`, `d_enemiesNP`, `d_en_bossNP`) com o algoritmo LZ11 e gera o `nsmbw_linked.rel`.
3. **Preserva os Arquivos do Jogo:** Mantém os assets em `extracted_disc/DATA` para leitura em tempo de execução.
4. **Tradução Estática PowerPC → C++:** Converte as ~40.000 funções do jogo para shards de código C++.
5. **Compilação Nativa C++:** Utiliza Clang e Ninja com flags `-march=x86-64-v2` e apresenta a saída gráfica via SFML 3 / OpenGL Core.
6. **Bypass de Proteção Anticópia:** O binário já possui patch HLE nativo para `DVDCheckDiskBca`, garantindo que o jogo não trave na tela de erro de disco.

---

## 3. Como Jogar

Assim que a compilação for concluída, o executável final estará pronto em `build-linux/WiiCompiled`.

Para iniciar o jogo:
```bash
./build-linux/WiiCompiled
```

---

## 4. Controles Padrão

O jogo mapeia os controles por padrão simulando o **Wii Remote na horizontal**:

### Teclado:
| Tecla | Ação (Wii Remote) |
|---|---|
| **Setas Direcionais** | D-Pad (Mover, Agachar, Entrar em Canos) |
| **Z** | Botão 1 (Correr, Atirar Bolas de Fogo) |
| **X** | Botão 2 (Pular, Nadar) |
| **A** | Botão A |
| **S** | Botão B |
| **Enter** | Botão + (Pause / Iniciar) |
| **Backspace** | Botão - |
| **Barra de Espaço** | Chacoalhar Wii Remote (Giro no ar / Spin Jump) |

### Controles USB / Bluetooth:
O jogo possui suporte nativo a controles via **SDL3** (Xbox, DualShock 4, DualSense, Nintendo Switch Pro Controller, etc.). Ao conectar um controle compatível, ele será reconhecido automaticamente.

---

## 5. Estrutura de Arquivos

```
blcsmbwii/
├── build.sh                     # Script de entrada de compilação
├── COMO_COMPILAR.md             # Este guia
├── projects/                    # Configurações do recompilador e scripts de extração
│   └── nsmbw/tools/
│       ├── build-linux.sh       # Script completo de build Linux
│       ├── unpack_game.py       # Descompactador LZ11 de RELs e DOL
│       └── prelink_rels.py      # Vinculador de módulos de memória
├── runtime/                     # Código-fonte C++ do runtime nativo
│   ├── src/platform/
│   │   ├── sfml_presenter.h     # Camada de apresentação SFML 3 / OpenGL 3.3
│   │   └── sfml_presenter.cpp
│   └── src/host_cpu_baseline.cpp # Checagem de CPU com downgrade para x86-64-v2
└── translator/                  # Tradutor estático C# .NET (PowerPC -> C++)
```
