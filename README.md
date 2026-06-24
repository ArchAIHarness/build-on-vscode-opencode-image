# build-on-vscode-opencode-image

> VS Code 网页版（code-server）+ OpenCode 基础镜像

通过编排 Dockerfile，把 **VS Code 网页版（code-server）** 与 **OpenCode** 集成在同一镜像中：预装 `sst-dev.opencode` 插件、Node.js 20、Python3、curl、git 等常用工具。**打开工作区即在主编辑区自动启动 opencode TUI、隐藏 CHAT 副边栏，开箱即用、界面精简。** 用于构建上层智能体/开发环境基础镜像。

## 镜像构成

| 组件 | 说明 |
|---|---|
| 基础镜像 | `codercom/code-server`（VS Code 网页版，自带 code-server 本体 / entrypoint / dumb-init） |
| 主进程 | code-server Web，监听 `8080` |
| OpenCode CLI | `opencode-ai` npm 全局安装，终端与插件均可调用 `opencode` |
| VS Code 插件 | 预装 `sst-dev.opencode`（来自 open-vsx.org），固定在 `/opt/code-server/extensions` |
| 运行时 | Node.js 20（NodeSource）、Python3 + pip + venv |
| 常用工具 | bash、curl、git、ca-certificates |

> 定位：**基础镜像**。只负责把编辑器 + OpenCode + 常用工具集成好并定义默认呈现，不引入进程编排、调度或鉴权耦合。

## 默认呈现

打开容器（浏览器访问 `8080`）后，无需任何手动操作：

1. opencode TUI 自动在**主编辑区**启动（folderOpen 自动任务）。
2. 右侧 CHAT 副边栏默认隐藏，界面最精简。
3. 左侧保留 EXPLORER 文件树。

## 基础镜像友好设计（关键）

工作目录与家目录都可能被业务挂载（NAS PV/PVC）覆盖。本镜像将所有**不可被覆盖**的运行依赖固定在 `/opt`，并由 entrypoint 对被挂载位置做 **seed-if-absent**（缺失才注入默认，业务自带配置一律尊重、不覆盖）：

| 内容 | 固定位置（不受挂载影响） | 说明 |
|---|---|---|
| VS Code 扩展 | `/opt/code-server/extensions` | `--extensions-dir`，业务挂载 `~` 不丢插件 |
| 编辑器用户数据/设置 | `/opt/code-server/user-data` | `--user-data-dir`，默认精简布局设置在此 |
| 配置模板 | `/opt/code-server/templates` | settings / tasks / AGENTS / opencode.json 模板源 |
| 插件离线包 | `/opt/extensions/*.vsix` | 扩展目录被清空时兜底重装 |

entrypoint 启动时：
- 扩展缺失 → 从离线 vsix 重装；
- `user-data/User/settings.json` 缺失 → 注入默认精简设置；
- `/workspace/AGENTS.md`、`/workspace/.opencode/opencode.json`、`/workspace/.vscode/tasks.json` 缺失 → 分别 seed 默认值。

> 业务自带同名文件时全部保留，不被覆盖。即「默认开箱即用，业务可完全接管」。

## 可覆盖的环境变量

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `BIND_ADDR` | `0.0.0.0:8080` | code-server 监听地址 |
| `WORKSPACE_DIR` | `/workspace` | 默认打开的工作目录 |
| `EXTENSIONS_DIR` | `/opt/code-server/extensions` | 扩展目录 |
| `USER_DATA_DIR` | `/opt/code-server/user-data` | 用户数据目录 |
| `DISABLE_AUTH` | `true` | 默认免登录；设 `false` 后配合 `PASSWORD` 启用鉴权 |
| `AUTO_START_OPENCODE` | `true` | 是否注入 folderOpen 自动任务 |

## 构建

```bash
docker build -t build-on-vscode-opencode-image:dev .

# 镜像加速源：
docker build \
  --build-arg CODE_SERVER_IMAGE=docker.1ms.run/codercom/code-server:latest \
  -t build-on-vscode-opencode-image:dev .

# 锁定插件版本：
docker build --build-arg OPENCODE_EXT_VERSION=0.0.13 -t build-on-vscode-opencode-image:dev .
```

### 构建参数

| ARG | 默认值 | 说明 |
|---|---|---|
| `CODE_SERVER_IMAGE` | `codercom/code-server:latest` | code-server 基础镜像，可切换加速源 |
| `OPENCODE_EXT_VERSION` | `0.0.13` | `sst-dev.opencode` 插件版本（open-vsx） |

## 本地运行

```bash
# 默认免登录、自动启动 opencode、精简界面
docker run -d --name bvoi -p 8080:8080 build-on-vscode-opencode-image:dev

# 业务挂载工作目录与家目录（基础镜像 seed 仍生效）
docker run -d --name bvoi -p 8080:8080 \
  -v /nas/userA/workspace:/workspace \
  -v /nas/userA/home:/home/coder \
  build-on-vscode-opencode-image:dev

# 启用鉴权
docker run -d --name bvoi -p 8080:8080 \
  -e DISABLE_AUTH=false -e PASSWORD=please-change-me \
  build-on-vscode-opencode-image:dev
```

浏览器打开 `http://localhost:8080` 即进入 VS Code Web，主区已自动运行 opencode。

> 安全提示：`PASSWORD` 仅用于演示，勿提交真实口令；生产环境由上游网关或 code-server 鉴权机制接管。

> 首次打开一个全新挂载的工作目录时，folderOpen 自动任务需等扩展宿主就绪（数秒）后才启动 opencode，属正常时序。

## 已验证

本地 Docker（arm64 / Apple Silicon，Docker 29.4.1）实测：

- **场景一·纯默认启动**（零参数、零挂载）：opencode TUI 自动占满主区、CHAT 隐藏、EXPLORER 保留。
- **场景二·业务挂载覆盖**（空卷挂到 `/workspace` 与 `/home/coder`）：entrypoint 自动 seed AGENTS.md / .opencode / .vscode/tasks.json 到挂载卷；扩展与设置因固定在 `/opt` 不受影响；默认呈现一致。
- 工具链：Node `v20.20.2`、npm `10.8.2`、Python `3.13.5`、pip `25.1.1`、curl `8.14.1`、git `2.47.3`、opencode `1.17.9`、扩展 `sst-dev.opencode`。
- `GET /healthz` → `200`。

## Kubernetes 单集群运行（参考）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vscode-opencode
spec:
  replicas: 1
  selector:
    matchLabels: { app: vscode-opencode }
  template:
    metadata:
      labels: { app: vscode-opencode }
    spec:
      containers:
        - name: code-server
          image: build-on-vscode-opencode-image:dev
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: vscode-opencode-workspace
```

> 本地单集群需让节点可拉取镜像：`kind load docker-image` / `minikube image load`，或推送到可访问仓库后引用。

## 目录结构

```text
build-on-vscode-opencode-image/
├── Dockerfile                      # code-server base + Node20 + Python3 + opencode + 插件 + 固定目录
├── docker/
│   ├── entrypoint.sh               # 扩展兜底 + seed-if-absent + 组装启动参数
│   ├── code-server-settings.json   # 默认精简布局设置模板
│   └── tasks.json                  # folderOpen 自动启动 opencode 的任务模板
├── .opencode/
│   └── opencode.json               # 默认 OpenCode 项目配置模板
├── AGENTS.md                       # 默认项目规则模板
├── .dockerignore
└── .gitignore
```

## 设计要点

- **挂载隔离**：扩展、用户数据、配置模板固定在 `/opt`，与工作目录/家目录挂载完全解耦。
- **seed-if-absent**：默认开箱即用，业务自带配置可完全接管，不被覆盖。
- **默认呈现固化**：精简布局 + 主区终端 + folderOpen 自动任务，全部由模板驱动，无需用户操作。
- **信号透传**：entrypoint 最终 `exec` code-server 官方入口，沿用基础镜像 dumb-init 与鉴权处理。

## 相关

- [code-server](https://github.com/coder/code-server)
- [OpenCode](https://opencode.ai)
- [sst-dev.opencode 插件](https://open-vsx.org/extension/sst-dev/opencode)
