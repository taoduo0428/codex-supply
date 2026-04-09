# Codex 全局引导包

[English](./README.md) | [简体中文](./README.zh-CN.md)

这是一个用于 Codex 全局运行环境的跨平台引导包。

仓库提供 Windows + WSL/Linux 的可移植团队配置，包含共享运行资产，以及通过 Git 子模块接入的可选增强模块。

## 仓库结构

- `win/`：Windows 引导脚本与同事说明文档
- `wsl/`：WSL/Linux 引导脚本、同事说明文档、自动化脚本
- `common/claude-code-main/`：必需的共享运行资产
- `external/`：可选增强模块（Git Submodule）
- `docs/`：发布与可移植性文档

## 功能总览

- 全局插件安装（`workspace-core`、`git-review`、`agent-orchestration`、`integration-runtime`、`personal-productivity`）
- 全局自动化脚本（smoke / validate / 定时任务）
- 全局 MCP 基线同步与工作区路径接线
- 治理运行时脚本（preflight / doctor / regression / project-contract）
- 可选增强：`superpowers`、`OpenSpace`、self-improving、proactive

## 5 个全局插件速览

| 插件 | 核心职责 | 典型触发 | 输入依赖 | 典型输出 | 边界/限制 |
| --- | --- | --- | --- | --- | --- |
| `workspace-core` | 工作区/会话基础能力 | “先看仓库状态”“先整理会话上下文” | 可读取的工作区路径 | 仓库状态与风险摘要、会话卫生处理建议 | 不替代发布级风险评审 |
| `git-review` | 代码评审与发布门禁 | “准备提 PR”“过一遍 diff 风险” | git 仓库与可访问 diff 历史 | 提交边界建议、PR 摘要、发布风险提示 | 不替代完整 CI/集成测试 |
| `agent-orchestration` | 任务规划与拆解编排 | “拆任务”“给分阶段执行计划”“并行推进” | 明确目标与约束 | 阶段计划、并行分工、验证关卡 | 需求不清晰时计划质量会下降 |
| `integration-runtime` | MCP/运行时接线与排障 | “把 MCP 接起来”“为什么工具连不上” | `node`/`npx`/MCP 二进制，部分能力需 token | 运行时配置修补、连通性诊断、能力清单 | 外部连接器仍依赖凭据和网络 |
| `personal-productivity` | 验证-排障闭环与记忆治理 | “先验证再修”“把流程沉淀成规则” | 可复现检查与可观察失败 | 失败路径图、verify-debug 循环、可复用记忆条目 | 无法弥补缺失测试或不可复现问题 |

## 术语说明：可选集成 vs 默认自动启用

- 可选集成模块：
  `superpowers`、`OpenSpace`、`self-improving`、`proactive` 在“分发层”是可选的，你可以选择是否把它们纳入仓库。
- 默认自动启用：
  只要这些模块在标准 `external/*` 路径存在，bootstrap 在“运行时”会自动发现并启用。

## `external/modules/mod-*` 映射表

| 本地中性路径 | 实际模块 | 上游地址 |
| --- | --- | --- |
| `external/modules/mod-a` | `superpowers` | https://github.com/obra/superpowers |
| `external/modules/mod-b` | `OpenSpace` | https://github.com/HKUDS/OpenSpace |
| `external/modules/mod-c` | `self-improving-for-codex` | https://github.com/cyjjjj-21/self-improving-for-codex |
| `external/modules/mod-d` | `ProactiveAgent` | https://github.com/thunlp/ProactiveAgent |

## 相比普通 Codex 的改进点

这里的“普通 Codex”是指：未使用本仓库这套全局引导脚本、治理运行时与插件包的常规本地配置。

1. 从“每台机器手工配置”升级为“可复现的一键团队引导”。
2. Windows 与 WSL/Linux 两端实现参数与验证口径基本一致。
3. 内置 5 个全局插件，不再依赖零散手工安装。
4. 自动把工作区路径写入 MCP 基线与插件 `.mcp.json`，减少路径错配。
5. 治理能力是可执行脚本（preflight/doctor/regression），不是只靠提示词。
6. 自动管理原生 hooks（`PreToolUse` / `SessionStart` / `UserPromptSubmit`）。
7. 通过 marker 机制把安全/风险策略写入 rules、AGENTS、ACTIVE，且非破坏式追加。
8. 附带自动化运行层（日常 smoke、可选 git-review、可选 nightly memory）。
9. 增强模块默认会从 `external/*` 自动启用（`superpowers`、`OpenSpace`、self-improving、proactive），也支持手动覆盖路径。
10. 自带发布前可移植性与安全检查清单，便于开源交付。

详细对照（含证据路径）：

- `docs/FEATURE_COMPARISON.zh-CN.md`
- `docs/FEATURE_COMPARISON.md`

## 用户必须自定义的配置项

每个用户都要按自己机器环境替换占位符。

| 参数 | 占位示例 | 是否必填 |
| --- | --- | --- |
| Bundle 根目录 | `C:\path\to\codex-bootstrap` / `/path/to/codex-bootstrap` | 是 |
| Workspace 路径 | `C:\path\to\your-main-workspace` / `/path/to/your-main-workspace` | 是 |
| 仓库地址 | `<YOUR_REPO_URL>` | 是 |
| 可选技能目录 | `C:\path\to\skills` / `/path/to/skills` | 否 |
| 可选模块路径覆盖 | `-SuperpowersSourcePath ...` / `--superpowers-source-path ...`（及其它模块参数） | 否 |
| GitHub Token（`GITHUB_TOKEN`/`GITHUB_PAT`） | `ghp_xxx`（仅占位） | 建议 |

## 快速开始

### 1) 克隆并初始化子模块（推荐）

```bash
git clone <YOUR_REPO_URL> codex-bootstrap
cd codex-bootstrap
git submodule update --init --recursive
```

请使用 `git clone`，不要用 GitHub 的 “Download ZIP”。ZIP 不包含 git 元数据和子模块信息，会导致增强模块无法可靠初始化。

如果你跳过这一步，脚本在检测到 `external/*` 模块缺失时也会自动尝试初始化子模块。

### 2) 运行引导脚本

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\win\bootstrap_fresh_global_full.ps1 `
  -RepoRoot ".\common\claude-code-main" `
  -WorkspacePath "C:\path\to\your-main-workspace"
```

WSL/Linux：

```bash
bash ./wsl/bootstrap_fresh_global_full.sh \
  --repo-root "./common/claude-code-main" \
  --workspace-path "/path/to/your-main-workspace"
```

默认行为：

- 若 `./external/*` 下存在对应目录，脚本会自动发现并启用 `superpowers`、`OpenSpace`、`self-improving`、`proactive`。
- 若这些目录缺失，脚本会自动尝试执行 `git submodule update --init --recursive`。
- 只有当模块目录不在标准位置时，才需要手动传 `SourcePath` 参数覆盖。
- `GitReview` 与 `NightlyMemory` 自动化默认开启。
- 只有你明确要关闭时，才传 `-DisableGitReview` / `--disable-git-review` 与 `-DisableNightlyMemory` / `--disable-nightly-memory`。
- 只有你明确不想自动初始化子模块时，才传 `-SkipSubmoduleInit` / `--skip-submodule-init`。

可选：同步自定义 skills（只有你有独立 skills 目录时才需要）：

- Windows：增加 `-SkillsSourcePath "C:\path\to\skills"`
- WSL/Linux：增加 `--skills-source-path "/path/to/skills"`

Smoke/验证说明：

- `run_smoke_prompts` 需要可信的 git 工作区 + 已登录认证的 codex 运行时。
- 如果日志出现 `401 Unauthorized: Missing bearer`，先完成 codex 登录再重试。

## 文档索引

- Windows 详细指南：`win/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- Windows 同事快速上手：`win/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- WSL 详细指南：`wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- WSL 同事快速上手：`wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- 功能对照（中文）：`docs/FEATURE_COMPARISON.zh-CN.md`
- 功能对照（英文）：`docs/FEATURE_COMPARISON.md`
- 功能全量手册（中文）：`docs/FEATURE_MANUAL.zh-CN.md`
- 功能全量手册（英文）：`docs/FEATURE_MANUAL.md`
- 发布模型与开源边界（英文）：`docs/PUBLISHING_MODEL.md`
- 发布模型与开源边界（中文）：`docs/PUBLISHING_MODEL.zh-CN.md`
- 发布检查清单：`docs/RELEASE_CHECKLIST.md`
- 可移植性检查：`docs/PORTABILITY_CHECKS.md`

## 安全

- 不要提交真实 token 或 `.env` 密钥。
- 文档和示例里只保留占位符（如 `ghp_xxx`）。
- 漏洞与安全问题请参考 `SECURITY.md`。

## 许可证

- 本仓库：MIT（`LICENSE`）
- 第三方组件与子模块：见 `THIRD_PARTY_NOTICES.md`
