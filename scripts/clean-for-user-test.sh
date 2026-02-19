#!/bin/bash
set -e

echo "🧹 Cleaning up for fresh end-user experience test..."

ENTROPIC_COLIMA_HOME="${ENTROPIC_COLIMA_HOME:-$HOME/.entropic/colima-dev}"
LEGACY_COLIMA_HOME="$HOME/.entropic/colima"
ENTROPIC_RUNTIME_HOME="${ENTROPIC_RUNTIME_HOME:-$HOME}"
USER_UID="$(id -u)"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
if [[ -z "$TMP_BASE" ]]; then
    TMP_BASE="/tmp"
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FALLBACK_COLIMA_HOME_SHARED="/Users/Shared/entropic/colima-${USER_UID}"
FALLBACK_COLIMA_HOME_TMP="${TMP_BASE}/entropic-colima-${USER_UID}"
FALLBACK_RUNTIME_HOME_SHARED="/Users/Shared/entropic/home-${USER_UID}"
FALLBACK_RUNTIME_HOME_TMP="${TMP_BASE}/entropic-home-${USER_UID}"
LEGACY_FALLBACK_COLIMA_HOME_TMP="/tmp/entropic-colima-${USER_UID}"
LEGACY_FALLBACK_RUNTIME_HOME_TMP="/tmp/entropic-home-${USER_UID}"
ENTROPIC_APP_DATA_DIR_MAC="$HOME/Library/Application Support/ai.openclaw.entropic"
LEGACY_NOVA_APP_DATA_DIR_MAC="$HOME/Library/Application Support/ai.openclaw.nova"
ENTROPIC_APP_DATA_DIR_LINUX="$HOME/.local/share/ai.openclaw.entropic"
LEGACY_NOVA_APP_DATA_DIR_LINUX="$HOME/.local/share/ai.openclaw.nova"
echo ""

is_safe_entropic_runtime_home_for_cleanup() {
    local target="$1"
    if [[ -z "$target" ]]; then
        return 1
    fi
    case "$target" in
        "/"|"/Users"|"/tmp"|"$HOME")
            return 1
            ;;
        "$FALLBACK_RUNTIME_HOME_SHARED"|"$FALLBACK_RUNTIME_HOME_TMP"|"$LEGACY_FALLBACK_RUNTIME_HOME_TMP"|"$HOME/.entropic/"*|"/Users/Shared/entropic/"*|"${TMP_BASE}/entropic-home-"*|"${TMP_BASE}/entropic-"*|"/tmp/entropic-home-"*|"/tmp/entropic-"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================
# 1. KILL RUNNING ENTROPIC PROCESSES & UNMOUNT DMGS
# ============================================

echo "🛑 Stopping all Entropic processes..."

# Kill all Entropic app instances
echo "  → Killing Entropic processes..."
pkill -9 -i entropic 2>/dev/null || true

# Kill Colima and Lima processes
echo "  → Killing Colima/Lima processes..."
pkill -9 limactl 2>/dev/null || true
pkill -9 colima 2>/dev/null || true

# Unmount any mounted Entropic DMGs
echo "  → Unmounting Entropic DMGs..."
for dmg in "/Volumes/Entropic"*; do
    if [ -d "$dmg" ]; then
        hdiutil detach "$dmg" -force 2>/dev/null || true
    fi
done

echo "✅ All processes stopped and DMGs unmounted"

# ============================================
# 2. CLEAN ENTROPIC'S ISOLATED RUNTIME
# ============================================

echo "🗑️  Cleaning Entropic's isolated runtime..."

# Entropic uses ENTROPIC_COLIMA_HOME as isolated home - just delete it
echo "  → Removing $ENTROPIC_COLIMA_HOME..."
rm -rf "$ENTROPIC_COLIMA_HOME"

# Backward-compatible cleanup for legacy paths
echo "  → Removing legacy $LEGACY_COLIMA_HOME..."
rm -rf "$LEGACY_COLIMA_HOME"

# Cleanup fallback Colima homes used when user home contains whitespace
echo "  → Removing fallback $FALLBACK_COLIMA_HOME_SHARED..."
rm -rf "$FALLBACK_COLIMA_HOME_SHARED"
echo "  → Removing fallback $FALLBACK_COLIMA_HOME_TMP..."
rm -rf "$FALLBACK_COLIMA_HOME_TMP"
if [[ "$LEGACY_FALLBACK_COLIMA_HOME_TMP" != "$FALLBACK_COLIMA_HOME_TMP" ]]; then
    echo "  → Removing legacy fallback $LEGACY_FALLBACK_COLIMA_HOME_TMP..."
    rm -rf "$LEGACY_FALLBACK_COLIMA_HOME_TMP"
fi

# Cleanup fallback runtime HOME locations used by bundled Colima/Lima commands
if [[ "$ENTROPIC_RUNTIME_HOME" != "$HOME" ]]; then
    if is_safe_entropic_runtime_home_for_cleanup "$ENTROPIC_RUNTIME_HOME"; then
        echo "  → Removing ENTROPIC_RUNTIME_HOME override $ENTROPIC_RUNTIME_HOME..."
        rm -rf "$ENTROPIC_RUNTIME_HOME"
    else
        echo "  ⚠️  Skipping unsafe ENTROPIC_RUNTIME_HOME cleanup target: $ENTROPIC_RUNTIME_HOME"
    fi
fi
echo "  → Removing fallback $FALLBACK_RUNTIME_HOME_SHARED..."
rm -rf "$FALLBACK_RUNTIME_HOME_SHARED"
echo "  → Removing fallback $FALLBACK_RUNTIME_HOME_TMP..."
rm -rf "$FALLBACK_RUNTIME_HOME_TMP"
if [[ "$LEGACY_FALLBACK_RUNTIME_HOME_TMP" != "$FALLBACK_RUNTIME_HOME_TMP" ]]; then
    echo "  → Removing legacy fallback $LEGACY_FALLBACK_RUNTIME_HOME_TMP..."
    rm -rf "$LEGACY_FALLBACK_RUNTIME_HOME_TMP"
fi
echo "  → Removing runtime state roots ~/.entropic and ~/.nova..."
rm -rf "$HOME/.entropic" "$HOME/.nova"

echo "✅ Entropic runtime cleaned"

# ============================================
# 3. CLEAN PERSISTED APP DATA (SETTINGS/AUTH/OAUTH)
# ============================================

echo ""
echo "🗃️  Cleaning persisted app data..."

for app_data_dir in \
    "$ENTROPIC_APP_DATA_DIR_MAC" \
    "$LEGACY_NOVA_APP_DATA_DIR_MAC" \
    "$ENTROPIC_APP_DATA_DIR_LINUX" \
    "$LEGACY_NOVA_APP_DATA_DIR_LINUX"
do
    if [ -e "$app_data_dir" ]; then
        echo "  → Removing $app_data_dir..."
        rm -rf "$app_data_dir"
    fi
done

echo "✅ Persisted app data cleaned"

# ============================================
# 4. CLEAN GLOBAL COLIMA (optional)
# ============================================

echo ""
echo "🌍 Cleaning global Colima state (if any)..."

# Try to stop global colima if command exists
if command -v colima &> /dev/null; then
    echo "  → Stopping global colima..."
    colima stop 2>/dev/null || true
    colima delete -f 2>/dev/null || true
    echo "  → Global colima stopped"
fi

# Remove directories even if command doesn't exist
rm -rf ~/.colima
rm -rf ~/.lima

echo "✅ Global Colima state cleaned"

# ============================================
# 5. DOCKER CLEANUP
# ============================================

echo ""
echo "🐳 Cleaning Docker resources..."

# Make sure we're using a working Docker context
docker context use desktop-linux 2>/dev/null || docker context use default 2>/dev/null || true

# Check if Docker is accessible
if docker info &> /dev/null; then
    # Stop and remove entropic containers
    echo "  → Stopping Entropic containers..."
    ENTROPIC_CONTAINERS=$(docker ps -aq --filter "name=entropic" 2>/dev/null)
    if [ -n "$ENTROPIC_CONTAINERS" ]; then
        echo "$ENTROPIC_CONTAINERS" | xargs docker stop 2>/dev/null || true
        echo "$ENTROPIC_CONTAINERS" | xargs docker rm -f 2>/dev/null || true
    fi
    
    OPENCLAW_CONTAINERS=$(docker ps -aq --filter "name=openclaw" 2>/dev/null)
    if [ -n "$OPENCLAW_CONTAINERS" ]; then
        echo "$OPENCLAW_CONTAINERS" | xargs docker rm -f 2>/dev/null || true
    fi
    
    # Remove entropic images (but keep openclaw-runtime:latest for bundling)
    echo "  → Removing Entropic images (keeping openclaw-runtime for bundling)..."
    ENTROPIC_IMAGES=$(docker images -q "entropic-*" 2>/dev/null)
    if [ -n "$ENTROPIC_IMAGES" ]; then
        echo "$ENTROPIC_IMAGES" | xargs docker rmi -f 2>/dev/null || true
    fi
    
    # Remove entropic volumes
    echo "  → Removing Entropic volumes..."
    ENTROPIC_VOLUMES=$(docker volume ls -q --filter "name=entropic" 2>/dev/null)
    if [ -n "$ENTROPIC_VOLUMES" ]; then
        echo "$ENTROPIC_VOLUMES" | xargs docker volume rm 2>/dev/null || true
    fi
    
    # Remove entropic networks
    echo "  → Removing Entropic networks..."
    docker network rm entropic-net 2>/dev/null || true
    
    echo "✅ Docker resources cleaned"
else
    echo "  ⚠️  Docker not accessible (this is OK for testing)"
fi

# ============================================
# 6. PROJECT BUILD ARTIFACTS
# ============================================

echo ""
echo "📦 Cleaning project build artifacts..."

cd "$PROJECT_ROOT"

# JavaScript artifacts
echo "  → Removing node_modules..."
rm -rf node_modules

echo "  → Removing dist..."
rm -rf dist

echo "  → Removing .build..."
rm -rf .build

# Rust artifacts (large!)
echo "  → Removing Rust target directory (~14GB)..."
rm -rf src-tauri/target

echo "  → Removing generated files..."
rm -rf src-tauri/gen

# Cargo clean
echo "  → Running cargo clean..."
cargo clean --manifest-path src-tauri/Cargo.toml 2>/dev/null || true

# ============================================
# 7. REMOVE OLD BUNDLED RESOURCES
# ============================================

echo ""
echo "🗑️  Removing old bundled resources..."
rm -rf src-tauri/resources/bin/*
rm -rf src-tauri/resources/share/*
rm -f src-tauri/resources/openclaw-runtime.tar.gz
rm -f src-tauri/resources/entropic-skill-scanner.tar.gz

# ============================================
# 8. CLEAN APP LOGS
# ============================================

echo ""
echo "📝 Cleaning runtime logs..."
rm -f ~/entropic-runtime.log

# ============================================
# DONE
# ============================================

echo ""
echo "✅ Complete cleanup done!"
echo ""
echo "📊 Current state:"
echo "  • ${ENTROPIC_COLIMA_HOME}: $([ -d "$ENTROPIC_COLIMA_HOME" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${LEGACY_COLIMA_HOME}: $([ -d "$LEGACY_COLIMA_HOME" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${FALLBACK_COLIMA_HOME_SHARED}: $([ -d "$FALLBACK_COLIMA_HOME_SHARED" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${FALLBACK_COLIMA_HOME_TMP}: $([ -d "$FALLBACK_COLIMA_HOME_TMP" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${FALLBACK_RUNTIME_HOME_SHARED}: $([ -d "$FALLBACK_RUNTIME_HOME_SHARED" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${FALLBACK_RUNTIME_HOME_TMP}: $([ -d "$FALLBACK_RUNTIME_HOME_TMP" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${ENTROPIC_APP_DATA_DIR_MAC}: $([ -d "$ENTROPIC_APP_DATA_DIR_MAC" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ${LEGACY_NOVA_APP_DATA_DIR_MAC}: $([ -d "$LEGACY_NOVA_APP_DATA_DIR_MAC" ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • ~/.colima: $([ -d ~/.colima ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • src-tauri/target: $([ -d src-tauri/target ] && echo "EXISTS" || echo "REMOVED ✓")"
echo "  • node_modules: $([ -d node_modules ] && echo "EXISTS" || echo "REMOVED ✓")"
echo ""
echo "🎯 Next steps:"
echo ""
echo "1. Make sure Docker is running:"
echo "   docker context use desktop-linux"
echo "   # Open Docker Desktop if not running"
echo ""
echo "2. Run the build:"
echo "   ./scripts/build-for-user-test.sh"
