#!/usr/bin/env bash
# runtime-entrypoint.sh
#
# 基础镜像启动引导。设计目标：默认开箱即用（自动启动 opencode TUI、最精简界面），
# 同时对「业务挂载工作目录 / 家目录」保持友好——任何被外部卷覆盖的位置都做
# seed-if-absent（缺失才注入默认配置），业务自带配置一律尊重、不覆盖。
#
# 关键隔离：
# - 扩展目录 / 用户数据目录固定在 /opt（EXTENSIONS_DIR / USER_DATA_DIR），
#   不在家目录，业务挂载 ~ 不会丢插件与编辑器设置。
# - 工作目录默认 /workspace（WORKSPACE_DIR），业务可挂载它；entrypoint 仅在
#   .vscode/tasks.json 缺失时注入默认自动任务。
set -euo pipefail

# ---- 可被业务通过环境变量覆盖的参数 ----
BIND_ADDR="${BIND_ADDR:-0.0.0.0:8080}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
EXTENSIONS_DIR="${EXTENSIONS_DIR:-/opt/code-server/extensions}"
USER_DATA_DIR="${USER_DATA_DIR:-/opt/code-server/user-data}"
DISABLE_AUTH="${DISABLE_AUTH:-true}"        # 基础镜像默认免登录；业务可设 false 后用 PASSWORD
AUTO_START_OPENCODE="${AUTO_START_OPENCODE:-true}"

# 固化的内置模板（不会被任何挂载覆盖）
TEMPLATE_DIR="/opt/code-server/templates"
OPENCODE_EXT_ID="sst-dev.opencode"
OPENCODE_EXT_VSIX="/opt/extensions/sst-dev.opencode.vsix"

log() { echo "[entrypoint] $*"; }

# 1) 扩展兜底：扩展目录被挂载覆盖或首次为空时，从离线 vsix 重装
ensure_opencode_extension() {
    mkdir -p "${EXTENSIONS_DIR}"
    if code-server --extensions-dir "${EXTENSIONS_DIR}" --list-extensions 2>/dev/null \
        | grep -qi "^${OPENCODE_EXT_ID}$"; then
        log "extension ${OPENCODE_EXT_ID} present"
        return 0
    fi
    if [ -f "${OPENCODE_EXT_VSIX}" ]; then
        log "installing ${OPENCODE_EXT_ID} from offline vsix into ${EXTENSIONS_DIR}"
        code-server --extensions-dir "${EXTENSIONS_DIR}" \
            --install-extension "${OPENCODE_EXT_VSIX}" \
            || log "WARN: failed to install ${OPENCODE_EXT_ID}, continuing"
    else
        log "WARN: offline vsix not found at ${OPENCODE_EXT_VSIX}"
    fi
}

# 2) 用户数据 seed：settings.json 缺失才注入默认（业务自带 settings 不覆盖）
seed_user_settings() {
    local user_dir="${USER_DATA_DIR}/User"
    mkdir -p "${user_dir}"
    if [ ! -f "${user_dir}/settings.json" ]; then
        log "seeding default settings.json -> ${user_dir}"
        cp "${TEMPLATE_DIR}/settings.json" "${user_dir}/settings.json"
    else
        log "settings.json exists, keep business config"
    fi
}

# 3) 工作目录 seed：注入默认 AGENTS.md / .opencode / 自动任务，均 seed-if-absent
seed_workspace() {
    mkdir -p "${WORKSPACE_DIR}"

    if [ ! -f "${WORKSPACE_DIR}/AGENTS.md" ]; then
        log "seeding default AGENTS.md -> ${WORKSPACE_DIR}"
        cp "${TEMPLATE_DIR}/AGENTS.md" "${WORKSPACE_DIR}/AGENTS.md" 2>/dev/null || true
    fi

    if [ ! -e "${WORKSPACE_DIR}/.opencode/opencode.json" ]; then
        log "seeding default .opencode/opencode.json -> ${WORKSPACE_DIR}"
        mkdir -p "${WORKSPACE_DIR}/.opencode"
        cp "${TEMPLATE_DIR}/opencode.json" "${WORKSPACE_DIR}/.opencode/opencode.json" 2>/dev/null || true
    fi

    if [ "${AUTO_START_OPENCODE}" = "true" ] && [ ! -f "${WORKSPACE_DIR}/.vscode/tasks.json" ]; then
        log "seeding folderOpen auto-start task -> ${WORKSPACE_DIR}/.vscode"
        mkdir -p "${WORKSPACE_DIR}/.vscode"
        cp "${TEMPLATE_DIR}/tasks.json" "${WORKSPACE_DIR}/.vscode/tasks.json"
    fi
}

ensure_opencode_extension
seed_user_settings
seed_workspace

log "node: $(node --version 2>/dev/null || echo n/a) | opencode: $(opencode --version 2>/dev/null || echo n/a)"

# ---- 启动 opencode web（后台，供 /agent/* API 代理） ----
OPENCODE_PORT="${OPENCODE_PORT:-4096}"
opencode web --port "${OPENCODE_PORT}" --hostname 0.0.0.0 --pure &
log "opencode web started on port ${OPENCODE_PORT} (background)"

# ---- 组装 code-server 启动参数 ----
ARGS=(
    --bind-addr "${BIND_ADDR}"
    --user-data-dir "${USER_DATA_DIR}"
    --extensions-dir "${EXTENSIONS_DIR}"
    --disable-workspace-trust
)
if [ "${DISABLE_AUTH}" = "true" ]; then
    ARGS+=(--auth none)
fi

# 业务可在 docker run/k8s 末尾追加自定义参数；默认打开 WORKSPACE_DIR
if [ "$#" -gt 0 ]; then
    ARGS+=("$@")
else
    ARGS+=("${WORKSPACE_DIR}")
fi

log "starting code-server (VSCode): ${ARGS[*]}"
exec /usr/bin/entrypoint.sh "${ARGS[@]}"
