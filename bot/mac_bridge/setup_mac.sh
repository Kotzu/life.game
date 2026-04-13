#!/bin/bash
# Setup complet Mac pentru BotBridge iPhone
# Rulare: bash setup_mac.sh
# Dupa aceasta: MacBook-ul nu mai necesita interactiune

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()    { echo -e "\n${YELLOW}──── $1 ────${NC}"; }

echo ""
echo "  BotBridge Mac Setup"
echo "  ════════════════════"
echo ""

# ── 1. Verifica macOS ─────────────────────────────────────────────────────────
step "1. Verific sistemul"
[[ "$(uname)" == "Darwin" ]] || error "Trebuie rulat pe macOS!"
info "macOS $(sw_vers -productVersion)"

# ── 2. Homebrew ──────────────────────────────────────────────────────────────
step "2. Homebrew"
if ! command -v brew &>/dev/null; then
    warn "Instalez Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
info "Homebrew $(brew --version | head -1)"

# ── 3. Python3 ───────────────────────────────────────────────────────────────
step "3. Python3"
if ! command -v python3 &>/dev/null; then
    brew install python3
fi
info "Python $(python3 --version)"

# ── 4. tidevice (porneste XCTest pe iPhone via WiFi) ──────────────────────────
step "4. tidevice"
if ! python3 -c "import tidevice" 2>/dev/null; then
    pip3 install tidevice --quiet
fi
info "tidevice $(python3 -c 'import tidevice; print(tidevice.__version__)')"

# ── 5. XcodeGen (pentru build app) ────────────────────────────────────────────
step "5. XcodeGen"
if ! command -v xcodegen &>/dev/null; then
    brew install xcodegen --quiet
fi
info "xcodegen $(xcodegen --version)"

# ── 6. Instaleaza Mac Bridge LaunchAgent ─────────────────────────────────────
step "6. Mac Bridge autostart"
BRIDGE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/mac_bridge.py"

if [[ ! -f "$BRIDGE_SCRIPT" ]]; then
    error "mac_bridge.py nu a fost gasit la $BRIDGE_SCRIPT"
fi

python3 "$BRIDGE_SCRIPT" --install-launchagent
info "Mac Bridge va porni automat la boot"

# ── 7. Build BotBridge.app ────────────────────────────────────────────────────
step "7. Build iOS App"
IOS_APP_DIR="$(cd "$(dirname "$0")/../ios_app" && pwd)"

if [[ ! -f "$IOS_APP_DIR/project.yml" ]]; then
    warn "ios_app/project.yml negasit, skip build"
else
    cd "$IOS_APP_DIR"
    info "Generez proiect Xcode..."
    xcodegen generate --quiet

    info "Build app (unsigned, pentru AltStore)..."
    xcodebuild \
        -project BotBridge.xcodeproj \
        -scheme BotBridge \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath build/BotBridge.xcarchive \
        archive \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        -quiet 2>&1 | tail -5

    # Creeaza IPA
    mkdir -p build/Payload
    cp -r build/BotBridge.xcarchive/Products/Applications/BotBridge.app build/Payload/
    (cd build && zip -r BotBridge.ipa Payload/ -q)

    IPA_PATH="$IOS_APP_DIR/build/BotBridge.ipa"
    if [[ -f "$IPA_PATH" ]]; then
        info "IPA creat: $IPA_PATH"
        # Deschide folderul pentru AirDrop facil
        open "$(dirname "$IPA_PATH")"
    else
        warn "IPA nu a fost creat - verifica erorile Xcode"
    fi
fi

# ── 8. Activare Developer Mode ────────────────────────────────────────────────
step "8. Developer Mode pe iPhone"
echo ""
echo "  Conecteaza iPhone-ul via USB, apoi:"
echo "  1. Xcode se deschide automat → Trust this computer → Trust"
echo "  2. Settings iPhone → Privacy & Security → Developer Mode → ON"
echo "  3. Restart iPhone"
echo ""
read -p "  Apasa Enter dupa ce ai activat Developer Mode..."

# Verifica daca iPhone e detectat
if command -v tidevice &>/dev/null || python3 -m tidevice &>/dev/null 2>&1; then
    UDID=$(python3 -m tidevice list 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -n "$UDID" ]]; then
        info "iPhone detectat: $UDID"
    else
        warn "iPhone nedetectat. Verifica USB si Trust."
    fi
fi

# ── Final ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complet!${NC}"
echo ""
echo "  Ce trebuie sa faci mai departe:"
echo "  1. Instaleaza AltStore pe iPhone (altstore.io)"
echo "  2. Deschide AltStore → + → BotBridge.ipa (din Finder)"
echo "  3. Deschide BotBridge pe iPhone → pune API key → Porneste"
echo ""
echo "  Mac Bridge ruleaza automat la fiecare boot Mac."
echo "  Log: tail -f /tmp/macbridge.log"
echo ""
echo "  Dupa acest moment MacBook-ul nu mai necesita interactiune"
echo "  (trebuie doar sa fie pornit si pe acelasi WiFi pentru touch auto)"
echo -e "${GREEN}════════════════════════════════════════${NC}"
