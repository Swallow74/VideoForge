#!/bin/bash
set -e

# ============================================
# VideoEdit Pro - Installer delle dipendenze
# ============================================

APP_NAME="VideoEdit Pro"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     $APP_NAME - Installazione dipendenze     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Helper functions
check_cmd() { command -v "$1" &>/dev/null; }
install_brew() {
    if ! check_cmd brew; then
        echo -e "${YELLOW}📦 Installazione Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo -e "${GREEN}✅ Homebrew installato${NC}"
    else
        echo -e "${GREEN}✅ Homebrew già presente${NC}"
    fi
}

echo -e "${CYAN}[1/5] Homebrew${NC}"
install_brew
echo ""

echo -e "${CYAN}[2/5] ffmpeg${NC}"
if check_cmd ffmpeg; then
    echo -e "${GREEN}✅ ffmpeg già presente ($(ffmpeg -version 2>&1 | head -1))${NC}"
else
    echo -e "${YELLOW}📦 Installazione ffmpeg...${NC}"
    brew install ffmpeg
    echo -e "${GREEN}✅ ffmpeg installato${NC}"
fi
echo ""

echo -e "${CYAN}[3/5] Python 3.12${NC}"
if check_cmd python3; then
    echo -e "${GREEN}✅ Python già presente ($(python3 --version 2>&1))${NC}"
else
    echo -e "${YELLOW}📦 Installazione Python 3.12...${NC}"
    brew install python@3.12
    echo -e "${GREEN}✅ Python installato${NC}"
fi
echo ""

echo -e "${CYAN}[4/5] mlx-whisper (trascrizione AI locale)${NC}"
if python3 -c "import mlx_whisper" 2>/dev/null; then
    VER=$(python3 -c "import mlx_whisper; print(f'v{mlx_whisper.__version__}')" 2>/dev/null || echo "sconosciuta")
    echo -e "${GREEN}✅ mlx-whisper già presente ($VER)${NC}"
else
    echo -e "${YELLOW}📦 Installazione mlx-whisper...${NC}"
    pip3 install mlx-whisper
    echo -e "${GREEN}✅ mlx-whisper installato${NC}"
fi
echo ""

echo -e "${CYAN}[5/5] (Opzionale) Motore LLM per correzione testi${NC}"
echo -e "${YELLOW}Scegli un motore LLM per la correzione grammaticale:${NC}"
echo -e "  ${GREEN}1)${NC} omlx (consigliato) — brew install omlx + omlx serve --model qwen3-vl-8b"
echo -e "  ${GREEN}2)${NC} Ollama — brew install ollama + ollama pull qwen3:8b"
echo -e "  ${GREEN}3)${NC} LM Studio — scarica da https://lmstudio.ai"
echo -e "  ${GREEN}4)${NC} Salta (la trascrizione funziona lo stesso)"
echo ""
read -p "Scegli [1-4] (default 4): " llm_choice
case "${llm_choice:-4}" in
    1)
        if check_cmd omlx; then
            echo -e "${GREEN}✅ omlx già presente${NC}"
        else
            echo -e "${YELLOW}📦 Installazione omlx...${NC}"
            brew install omlx
            echo -e "${GREEN}✅ omlx installato${NC}"
        fi
        echo -e "${YELLOW}▶ Per avviare: omlx serve --model qwen3-vl-8b${NC}"
        ;;
    2)
        if check_cmd ollama; then
            echo -e "${GREEN}✅ Ollama già presente${NC}"
        else
            echo -e "${YELLOW}📦 Installazione Ollama...${NC}"
            brew install ollama
        fi
        echo -e "${YELLOW}▶ Per avviare: ollama pull qwen3:8b && ollama serve${NC}"
        ;;
    3)
        echo -e "${YELLOW}▶ Scarica LM Studio da: https://lmstudio.ai${NC}"
        echo -e "${YELLOW}   Poi imposta API URL nell'app su http://127.0.0.1:1234${NC}"
        ;;
esac
echo ""

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Installazione completata!                ║${NC}"
echo -e "${GREEN}║     Apri VideoEdit.app e inizia a usarla.     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📌 Nota: se macOS blocca l'app perché non certificata:${NC}"
echo -e "  1. Apri Terminale e incolla:"
echo -e "     ${CYAN}xattr -dr com.apple.quarantine /Applications/VideoEdit.app${NC}"
echo -e "  2. Oppure: Tasto destro sull'app → Apri"
echo ""