#!/bin/sh
set -e

# Create auth-profiles.json from environment variables
# Keys stay in memory (tmpfs), never written to host disk

json_escape() {
    node -e 'const v = process.argv[1] ?? ""; process.stdout.write(JSON.stringify(v).slice(1,-1));' "$1"
}

append_auth_profile() {
    key="$1"
    provider="$2"
    value="$3"

    if [ -n "${AUTH_PROFILES}" ]; then
        AUTH_PROFILES="${AUTH_PROFILES},"
    fi
    AUTH_PROFILES="${AUTH_PROFILES}
    \"${key}\": { \"type\": \"api_key\", \"provider\": \"${provider}\", \"key\": \"${value}\" }"
}

AUTH_PROFILES=""

AUTH_DIR="/home/node/.openclaw/agents/main/agent"
mkdir -p "$AUTH_DIR"

if [ -n "$ANTHROPIC_API_KEY" ]; then
    append_auth_profile "anthropic:default" "anthropic" "$(json_escape "${ANTHROPIC_API_KEY}")"
fi
if [ -n "$OPENROUTER_API_KEY" ]; then
    append_auth_profile "openrouter:default" "openrouter" "$(json_escape "${OPENROUTER_API_KEY}")"
fi
if [ -n "$OPENAI_API_KEY" ]; then
    append_auth_profile "openai:default" "openai" "$(json_escape "${OPENAI_API_KEY}")"
fi
if [ -n "$GEMINI_API_KEY" ]; then
    append_auth_profile "google:default" "google" "$(json_escape "${GEMINI_API_KEY}")"
fi

cat > "$AUTH_DIR/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {${AUTH_PROFILES}
  }
}
EOF

# Create other directories OpenClaw needs
mkdir -p /home/node/.openclaw/canvas
mkdir -p /home/node/.openclaw/cron
mkdir -p /home/node/.openclaw/logs
mkdir -p /home/node/.openclaw/.cache/qmd
mkdir -p /data/qmd-models
ln -sfn /data/qmd-models /home/node/.openclaw/.cache/qmd/models

# Seed workspace directory expected by qmd plugins.
mkdir -p /home/node/.openclaw/workspace
ln -sfn /home/node/.bun/install/global/node_modules /home/node/.openclaw/workspace/node_modules

# Ensure qmd's workspace-local tsx resolver stays available even in ESM context.
if [ -d /home/node/.bun/install/global/node_modules/tsx ]; then
  mkdir -p /home/node/.openclaw/workspace/node_modules
  ln -sfn /home/node/.bun/install/global/node_modules/tsx /home/node/.openclaw/workspace/node_modules/tsx
fi

# qmd runtime environment for the bundled runtime image.
export HOME=/home/node/.openclaw
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/home/node/.openclaw/agents/main/qmd/xdg-config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/home/node/.openclaw/agents/main/qmd/xdg-cache}"
export NODE_PATH="/home/node/.bun/install/global/node_modules${NODE_PATH:+:$NODE_PATH}"

# Write a minimal config to select the primary model when provided
MEMORY_SLOT="${OPENCLAW_MEMORY_SLOT:-}"
MEMORY_CONFIG=""
PLUGIN_ENTRIES=""

if [ -z "$MEMORY_SLOT" ]; then
    if [ -d "/app/extensions/memory-core" ]; then
        MEMORY_SLOT="memory-core"
    elif [ -d "/app/extensions/memory-lancedb" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
        MEMORY_SLOT="memory-lancedb"
    else
        MEMORY_SLOT="none"
    fi
fi

if [ "$MEMORY_SLOT" = "memory-lancedb" ]; then
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        OPENAI_API_KEY_ESC="$(json_escape "${OPENAI_API_KEY}")"
        MEMORY_CONFIG="\"memory-lancedb\": { \"enabled\": true, \"config\": { \"embedding\": { \"apiKey\": \"${OPENAI_API_KEY_ESC}\", \"model\": \"text-embedding-3-small\" } } }"
    else
        MEMORY_SLOT="memory-core"
    fi
fi

# Note: The top-level "memory" config block was removed in OpenClaw >= 2026.1.29.
# The memory-core plugin now handles memory search internally via api.runtime.tools.

PLUGIN_ENTRIES="\"nova-integrations\": { \"enabled\": true }"
ALSO_ALLOW="\"nova-integrations\""

if [ -d "/app/extensions/nova-x" ] || [ -d "/data/nova-skills/nova-x" ]; then
    PLUGIN_ENTRIES="${PLUGIN_ENTRIES}, \"nova-x\": { \"enabled\": true }"
    ALSO_ALLOW="${ALSO_ALLOW}, \"x_search\", \"x_profile\", \"x_thread\", \"x_user_tweets\""
fi
if [ -n "$MEMORY_CONFIG" ]; then
    PLUGIN_ENTRIES="${PLUGIN_ENTRIES}, ${MEMORY_CONFIG}"
fi

if [ -n "${OPENCLAW_MODEL:-}" ]; then
    OPENCLAW_MODEL_ESC="$(json_escape "${OPENCLAW_MODEL}")"
    IMAGE_MODEL_BLOCK=""
    if [ -n "${OPENCLAW_IMAGE_MODEL:-}" ]; then
        OPENCLAW_IMAGE_MODEL_ESC="$(json_escape "${OPENCLAW_IMAGE_MODEL}")"
        IMAGE_MODEL_BLOCK=",
      \"imageModel\": { \"primary\": \"${OPENCLAW_IMAGE_MODEL_ESC}\" }"
    else
        OPENCLAW_IMAGE_MODEL_ESC=""
    fi
    TOOLS_BLOCK=",
  \"tools\": {
    \"alsoAllow\": [${ALSO_ALLOW}]"
    if [ -n "${NOVA_PROXY_MODE:-}" ] && [ -n "${NOVA_PROXY_BASE_URL:-}" ]; then
        NOVA_PROXY_BASE_URL_ESC="$(json_escape "${NOVA_PROXY_BASE_URL}")"
        TOOLS_BLOCK="${TOOLS_BLOCK},
    \"web\": {
      \"search\": {
        \"provider\": \"perplexity\",
        \"perplexity\": {
          \"baseUrl\": \"${NOVA_PROXY_BASE_URL_ESC}\"
        }
      }
    }"
    fi
    TOOLS_BLOCK="${TOOLS_BLOCK}
  }"

    MODELS_BLOCK=""
    LOAD_PATHS_BLOCK=""
    if [ -d "/data/nova-skills/nova-x" ]; then
        LOAD_PATHS_BLOCK=",
    \"load\": { \"paths\": [\"/data/nova-skills/nova-x\"] }"
    fi
    if [ -n "${NOVA_PROXY_BASE_URL:-}" ]; then
        NOVA_PROXY_BASE_URL_ESC="$(json_escape "${NOVA_PROXY_BASE_URL}")"
        MODEL_ID_RAW="${OPENCLAW_MODEL#openrouter/}"
        if [ "$MODEL_ID_RAW" = "free" ] || [ "$MODEL_ID_RAW" = "auto" ]; then
            MODEL_ID_RAW="${OPENCLAW_MODEL}"
        fi
        MODEL_ID_ESC="$(json_escape "${MODEL_ID_RAW}")"
        IMAGE_MODEL_ID_RAW=""
        IMAGE_MODEL_ID_ESC=""
        if [ -n "${OPENCLAW_IMAGE_MODEL:-}" ]; then
            IMAGE_MODEL_ID_RAW="${OPENCLAW_IMAGE_MODEL#openrouter/}"
            if [ "$IMAGE_MODEL_ID_RAW" = "free" ] || [ "$IMAGE_MODEL_ID_RAW" = "auto" ]; then
                IMAGE_MODEL_ID_RAW="${OPENCLAW_IMAGE_MODEL}"
            fi
            IMAGE_MODEL_ID_ESC="$(json_escape "${IMAGE_MODEL_ID_RAW}")"
        fi
        MODELS_BLOCK=",
  \"models\": {
    \"providers\": {
      \"openrouter\": {
        \"baseUrl\": \"${NOVA_PROXY_BASE_URL_ESC}\",
        \"api\": \"openai-completions\",
        \"models\": [
          { \"id\": \"${MODEL_ID_ESC}\", \"name\": \"${MODEL_ID_ESC}\" }${IMAGE_MODEL_ID_ESC:+,
          { \"id\": \"${IMAGE_MODEL_ID_ESC}\", \"name\": \"${IMAGE_MODEL_ID_ESC}\" }}
        ]
      }
    }
  }"
    fi

    cat > /home/node/.openclaw/openclaw.json << EOF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "${OPENCLAW_MODEL_ESC}"
      }${IMAGE_MODEL_BLOCK}
    }
  },
  "cron": {
    "store": "/data/cron/jobs.json"
  },
  "plugins": {
    "slots": {
      "memory": "${MEMORY_SLOT}"
    }${LOAD_PATHS_BLOCK},
    "entries": {
      ${PLUGIN_ENTRIES}
    }
  }${MODELS_BLOCK}${TOOLS_BLOCK}
}
EOF
fi

# Start the gateway
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
TOKEN_PARAM=""
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    TOKEN_PARAM="--token ${OPENCLAW_GATEWAY_TOKEN}"
fi
exec node /app/dist/index.js gateway --bind lan --port "${PORT}" --allow-unconfigured ${TOKEN_PARAM}
