# =============================================================================
# build-on-vscode-opencode-image
# VS Code 网页版 (code-server) + OpenCode 基础镜像
#
# - base: codercom/code-server（自带 code-server 本体 / entrypoint / dumb-init）
# - 叠加: Node.js 20 + Python3 + curl/git 等常用工具
# - 集成: opencode CLI（npm 全局）+ VS Code 内置 sst-dev.opencode 插件
# - 默认呈现: 打开即在主编辑区自动启动 opencode TUI，隐藏 CHAT 副边栏，最精简
#
# 基础镜像设计：扩展目录 / 用户数据目录 / 配置模板全部固化在 /opt，不依赖会被
# 业务挂载覆盖的工作目录或家目录；entrypoint 对被挂载位置做 seed-if-absent。
# =============================================================================

ARG CODE_SERVER_IMAGE=codercom/code-server:latest
FROM ${CODE_SERVER_IMAGE}

# ----- 系统层：root 安装常用工具与运行时 -----
USER root

ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# bash/curl/git/ca-certificates：常用基础工具
# python3 工具链：常用脚本与 OpenCode 工具依赖
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20（NodeSource），供 opencode CLI 与前端工具使用
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version \
    && npm --version

# OpenCode CLI（全局）
RUN npm install -g opencode-ai

# sst-dev.opencode 插件离线包（供 entrypoint 兜底安装）
ARG OPENCODE_EXT_VERSION=0.0.13
RUN mkdir -p /opt/extensions \
    && curl -fsSL -o /opt/extensions/sst-dev.opencode.vsix \
        "https://open-vsx.org/api/sst-dev/opencode/${OPENCODE_EXT_VERSION}/file/sst-dev.opencode-${OPENCODE_EXT_VERSION}.vsix"

# ----- 固化目录：扩展 / 用户数据 / 配置模板，全部在 /opt，不受挂载影响 -----
ENV EXTENSIONS_DIR=/opt/code-server/extensions \
    USER_DATA_DIR=/opt/code-server/user-data \
    WORKSPACE_DIR=/workspace \
    BIND_ADDR=0.0.0.0:8080 \
    DISABLE_AUTH=true \
    AUTO_START_OPENCODE=true

# 配置模板（settings / tasks / AGENTS / opencode.json）
COPY docker/code-server-settings.json /opt/code-server/templates/settings.json
COPY docker/tasks.json                /opt/code-server/templates/tasks.json
COPY AGENTS.md                        /opt/code-server/templates/AGENTS.md
COPY .opencode/opencode.json          /opt/code-server/templates/opencode.json

# 构建期把插件预装进固定扩展目录（开箱即用，且 entrypoint 仍会兜底校验）
RUN mkdir -p "${EXTENSIONS_DIR}" "${USER_DATA_DIR}/User" "${WORKSPACE_DIR}" \
    && code-server --extensions-dir "${EXTENSIONS_DIR}" \
        --install-extension /opt/extensions/sst-dev.opencode.vsix \
    && code-server --extensions-dir "${EXTENSIONS_DIR}" --list-extensions \
    && cp /opt/code-server/templates/settings.json "${USER_DATA_DIR}/User/settings.json" \
    && chown -R coder:coder /opt/code-server /opt/extensions "${WORKSPACE_DIR}"

# ----- 启动编排 -----
COPY docker/entrypoint.sh /usr/local/bin/runtime-entrypoint.sh
RUN chmod +x /usr/local/bin/runtime-entrypoint.sh

USER coder
WORKDIR /workspace

# 8080: code-server Web
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

# entrypoint 负责：扩展兜底 + 配置 seed-if-absent + 组装启动参数
# 业务可在 docker run/k8s 末尾追加 code-server 参数覆盖默认工作目录等
ENTRYPOINT ["/usr/local/bin/runtime-entrypoint.sh"]
CMD []
