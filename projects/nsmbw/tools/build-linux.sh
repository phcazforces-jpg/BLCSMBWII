#!/usr/bin/env bash
# Build New Super Mario Bros. Wii Recompilation natively on Linux (x86-64-v2 / Ivy Bridge / Intel HD 4000)
set -euo pipefail
export DOTNET_ROLL_FORWARD=LatestMajor

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workspace=$(cd "$script_dir/../../.." && pwd)
cd "$workspace"

echo "=== NSMB Wii Multiplayer Recompilation - Linux Build (Ivy Bridge / HD 4000) ==="

# 1. Build Translator
echo "[1/4] Building Translator (.NET)..."
dotnet build translator/Translator.sln -c Release

TRANSLATOR="$workspace/translator/src/Translator.Cli/bin/Release/net8.0/Translator.Cli.dll"
PROJECT="projects/nsmbw/recomp.yml"

# Ensure game directory links exist whether placed in repo/game or ../game
if [ ! -e "game" ] && [ -d "../game" ]; then
    ln -s ../game game
elif [ -d "game" ] && [ ! -e "../game" ]; then
    ln -s "$workspace/game" "$workspace/../game"
fi

# 1.5 Optional auto-extraction from ISO/WBFS/RVZ argument or auto-detection
ISO_INPUT="${1:-}"
if [ -z "$ISO_INPUT" ] && [ ! -f "game/main.dol" ] && [ ! -f "../game/main.dol" ]; then
    for candidate in \
        ./*[Rr]ev*1*.[Rr][Vv][Zz] ./*[Rr]ev*1*.[Ii][Ss][Oo] ./*[Rr]ev*1*.[Ww][Bb][Ff][Ss] \
        ./rom/*[Rr]ev*1*.[Rr][Vv][Zz] ./rom/*[Rr]ev*1*.[Ii][Ss][Oo] ./rom/*[Rr]ev*1*.[Ww][Bb][Ff][Ss] \
        ./rom/*.rvz ./rom/*.iso ./rom/*.wbfs \
        ./*.rvz ./*.iso ./*.wbfs \
        ../wiigames/*[Rr]ev*1*.[Rr][Vv][Zz] ../wiigames/*[Rr]ev*1*.[Ii][Ss][Oo] ../wiigames/*[Rr]ev*1*.[Ww][Bb][Ff][Ss] \
        ../wiigames/*.rvz ../wiigames/*.iso ../wiigames/*.wbfs \
        "$HOME/Downloads/wiigames/"*[Rr]ev*1*.[Rr][Vv][Zz] "$HOME/Downloads/wiigames/"*[Rr]ev*1*.[Ii][Ss][Oo] \
        "$HOME/Downloads/"*[Rr]ev*1*.[Rr][Vv][Zz] "$HOME/Downloads/"*[Rr]ev*1*.[Ii][Ss][Oo]; do
        if [ -f "$candidate" ]; then
            ISO_INPUT="$candidate"
            break
        fi
    done
fi

if [ -n "$ISO_INPUT" ] && [ -f "$ISO_INPUT" ] && [ ! -f "game/main.dol" ] && [ ! -f "../game/main.dol" ]; then
    echo "[*] Imagem de jogo detectada: $ISO_INPUT"
    echo "[*] Extraindo partição do jogo usando dolphin-tool..."
    TEMP_EXTRACT="/tmp/nsmbw_auto_extract"
    rm -rf "$TEMP_EXTRACT"
    mkdir -p "$TEMP_EXTRACT"
    
    if flatpak info org.DolphinEmu.dolphin-emu &>/dev/null; then
        flatpak run --filesystem=host --filesystem=/tmp \
            --command=dolphin-tool org.DolphinEmu.dolphin-emu \
            extract -i "$ISO_INPUT" -o "$TEMP_EXTRACT"
    elif command -v dolphin-tool &>/dev/null; then
        dolphin-tool extract -i "$ISO_INPUT" -o "$TEMP_EXTRACT"
    else
        echo "[!] dolphin-tool não encontrado para extração automática."
    fi

    if [ -d "$TEMP_EXTRACT/DATA" ]; then
        mkdir -p game extracted_disc
        echo "[*] Preservando arquivos do disco para extracted_disc/DATA..."
        cp -rn "$TEMP_EXTRACT/DATA" extracted_disc/ || true
        if python3 projects/nsmbw/tools/unpack_game.py "$TEMP_EXTRACT" game; then
            python3 projects/nsmbw/tools/prelink_rels.py game
        fi
    fi
    rm -rf "$TEMP_EXTRACT"
fi

# Se já houver extracted_disc mas não game/main.dol, descompacta os binários
if [ ! -f "game/main.dol" ] || [ ! -f "game/nsmbw_linked.rel" ]; then
    if [ -d "extracted_disc/DATA" ] || [ -d "extracted_disc/files" ]; then
        echo "[*] Encontrada pasta extracted_disc. Descompactando binários do jogo..."
        mkdir -p game
        if python3 projects/nsmbw/tools/unpack_game.py extracted_disc game; then
            python3 projects/nsmbw/tools/prelink_rels.py game
        fi
    fi
fi

# 2. Check game inputs and translate if game/ exists
GAME_DIR=""
if [ -f "game/main.dol" ] && [ -f "game/nsmbw_linked.rel" ]; then
    GAME_DIR="game"
elif [ -f "../game/main.dol" ] && [ -f "../game/nsmbw_linked.rel" ]; then
    GAME_DIR="../game"
fi

if [ -n "$GAME_DIR" ]; then
    echo "[2/4] Generating C++ code from DOL and REL in $GAME_DIR..."
    mkdir -p generated/functions build/base
    dotnet "$TRANSLATOR" translate-recursive 0x80004050 \
        --project "$PROJECT" \
        --outdir generated/functions \
        --output-metadata generated/base_translation_output.json \
        --production-source-bundle generated/base_translation_sources.bin \
        --no-function-files --prune-stale --threads "$(nproc)"
    dotnet "$TRANSLATOR" emit-base-manifest \
        --project "$PROJECT" \
        --out build/base \
        --functions-dir generated/functions \
        --translation-output-metadata generated/base_translation_output.json \
        --region E
    dotnet "$TRANSLATOR" generate-data-init --project "$PROJECT"
    dotnet "$TRANSLATOR" emit-build-shards \
        --project "$PROJECT" \
        --base-metadata generated/base_translation_output.json \
        --base-functions-dir generated/functions \
        --native-source-dir runtime/src \
        --out generated/build_shards
else
    echo "[2/4] Note: game/main.dol or game/nsmbw_linked.rel not found yet."
    echo "      Para compilar o WiiCompiled, você precisa de uma cópia limpa do SMNE01 Rev 1."
fi

# 3. Configure Native Build via CMake with Clang & Ninja
BUILD_DIR="${BUILD_DIR:-build-linux}"
if [ -f "generated/build_shards/shards.cmake" ]; then
    BUILD_PRODUCTS_OPT="-DMKW_BUILD_PRODUCTS=ON"
    echo "[3/4] Configuring full product with CMake (x86-64-v2 / SFML 3 / OpenGL Core)..."
else
    BUILD_PRODUCTS_OPT="-DMKW_BUILD_PRODUCTS=OFF"
    echo "[3/4] Configuring runtime libraries and tests with CMake (WiiCompiled disabled until game shards are generated)..."
fi

cmake -S runtime -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DMKW_BASELINE_ARCH_FLAG="-march=x86-64-v2" \
    "$BUILD_PRODUCTS_OPT" \
    -DMKW_ENABLE_SFML=ON \
    -DDAWN_ENABLE_VULKAN=ON \
    -DDAWN_ENABLE_DESKTOP_GL=ON \
    -DDAWN_ENABLE_NULL=ON

# 4. Build target
echo "[4/4] Building target with Ninja..."
if [ -f "generated/build_shards/shards.cmake" ]; then
    ninja -C "$BUILD_DIR" WiiCompiled
    echo "Build complete! Executable is at: $BUILD_DIR/WiiCompiled"
else
    ninja -C "$BUILD_DIR"
    echo ""
    echo "=========================================================================="
    echo " Runtime construído com sucesso! (x86-64-v2 / SFML 3 / Ivy Bridge)"
    echo " Para gerar o executável final 'WiiCompiled', siga as etapas abaixo:"
    echo " 1. Obtenha a cópia do New Super Mario Bros. Wii (USA Rev 1 / SMNE01 v1)."
    echo " 2. Extraia a partição do jogo para uma pasta temporária (ex: com dolphin-tool):"
    echo "    flatpak run --filesystem=/home/pedroc/Downloads --command=dolphin-tool \\"
    echo "      org.DolphinEmu.dolphin-emu extract -i /caminho/jogo.iso -o /tmp/nsmbw"
    echo " 3. Descompacte e pré-linke os RELs:"
    echo "    python3 projects/nsmbw/tools/unpack_game.py /tmp/nsmbw game"
    echo "    python3 projects/nsmbw/tools/prelink_rels.py"
    echo " 4. Execute novamente: ./projects/nsmbw/tools/build-linux.sh"
    echo "=========================================================================="
fi
