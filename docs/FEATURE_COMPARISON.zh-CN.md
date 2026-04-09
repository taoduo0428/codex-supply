# 功能对照：普通 Codex vs 本增强版

[English](./FEATURE_COMPARISON.md) | [简体中文](./FEATURE_COMPARISON.zh-CN.md)

本文用于回答一个核心问题：你的这套方案相比普通 Codex 到底增强了什么。

基线定义：
- 普通 Codex：默认本地使用，不引入本仓库的 Win/WSL 全局引导、治理运行时、插件分发与自动化层。
- 本增强版：使用本仓库脚本与结构完成全局配置。

## 能力对照总表

| 维度 | 普通 Codex（基线） | 本增强版（当前仓库） | 直接收益 |
| --- | --- | --- | --- |
| 团队部署方式 | 常见是每人手工配置，步骤容易漂移 | 有固定入口脚本：`win/bootstrap_fresh_global_full.ps1`、`wsl/bootstrap_fresh_global_full.sh` | 同事按同一流程即可复现 |
| 跨平台一致性 | Win/WSL 往往各自维护 | Win/WSL 双脚本参数对齐、文档对齐、验证命令对齐 | 降低“只在我机器可用”概率 |
| 插件交付 | 插件来源分散、版本不统一 | `common/claude-code-main/dist/global-plugins/index.json` 统一声明 5 个插件并全局安装 | 插件集合可审计、可回滚 |
| MCP 工作区接线 | 手工改配置，容易漏改 | 脚本自动写入 `~/.codex/config.toml` 与各插件 `.mcp.json` 的 workspace | 减少路径不一致导致的失效 |
| 治理能力 | 多为静态提示词，执行约束弱 | 生成可执行治理脚本：preflight/doctor/regression/project-contract/crawler-smoke | 有“可执行的防线”和体检 |
| 原生 hooks | 经常未启用或手工维护 | 自动写入 `hooks.json` 并确保 `codex_hooks = true` | 工具调用前可做策略预检 |
| 安全策略注入 | 规则常散落且不可验证 | rules + AGENTS + ACTIVE 统一 marker 注入，非破坏式追加 | 可持续升级，减少覆盖冲突 |
| 自动化运维 | 依赖人工触发 | 内置 daily smoke、可选 git-review、可选 nightly-memory | 日常回归成本更低 |
| 高级能力扩展 | 接入成本高、路径不统一 | 标准 `external/*` 目录下默认自动启用 `superpowers`、`OpenSpace`、self-improving、proactive（也可参数覆盖）；若目录缺失会默认尝试子模块初始化 | 增强能力可组合启用 |
| 开源可移植性 | 常见残留个人路径/凭据风险 | 提供 `docs/PORTABILITY_CHECKS.md` 与 `docs/RELEASE_CHECKLIST.md` | 更适合公开发布和团队传播 |

## 逐项增强细节（含落地位置）

### 1) 标准化全局引导

- Windows 主入口：`win/bootstrap_fresh_global_full.ps1`
- WSL 主入口：`wsl/bootstrap_fresh_global_full.sh`
- 明确参数：`RepoRoot/WorkspacePath/SkillsSourcePath/...`（或对应 `--*` 参数）
- 作用：把“零散手工步骤”收敛为可复现命令。

### 2) 全局插件与运行资产统一分发

- 插件清单：`common/claude-code-main/dist/global-plugins/index.json`
- 安装器：`common/claude-code-main/dist/global-plugins/install_global.ps1`
- 回滚器：`common/claude-code-main/dist/global-plugins/rollback_global.ps1`
- 已集成插件：
  - `workspace-core`
  - `git-review`
  - `agent-orchestration`
  - `integration-runtime`
  - `personal-productivity`

### 3) MCP 与路径接线自动化

- 脚本会同步 `~/.codex/config.toml`（Windows 对应 `%USERPROFILE%\\.codex\\config.toml`）
- 同步项包含：
  - `filesystem/fetch/git/openaiDeveloperDocs/openspace` 等 MCP 段
  - `codex_hooks = true`
  - 与 `WorkspacePath` 对齐的仓库/工作区参数
- 价值：减少“脚本装好了但 MCP 还指向旧路径”的隐性问题。

### 4) 可执行治理运行时（非口号）

生成并校验这些脚本（Win/WSL 同名变体）：
- `codex_preflight_gate.*`
- `codex_doctor.*`
- `codex_regression_check.*`
- `codex_project_contract_init.*`
- `codex_project_contract_check.*`
- `codex_crawler_project_init.*`
- `codex_crawler_smoke_test.*`
- `codex_native_governance_hook.*`

这些能力让你在发布前、运行时、项目级契约检查上都有固定工具链。

### 5) hooks 与策略联动

- 自动维护：`~/.codex/hooks.json`
- 自动确保：`config.toml` 启用 `codex_hooks = true`
- hooks 事件包含：`SessionStart`、`UserPromptSubmit`、`PreToolUse`
- 价值：在关键动作前统一执行 preflight 策略，而不是靠人工记忆。

### 6) 非破坏式策略注入

- 规则写入：`~/.codex/rules/default.rules`（delete/risk guards）
- AGENTS/ACTIVE 采用 marker 块追加，不全量覆盖
- 价值：在保留用户已有内容基础上持续演进。

### 7) 自动化与回归

- Windows：`common/claude-code-main/scripts/automation_*.ps1`
- WSL：`wsl/automation/scripts/*.sh`
- 关键脚本：
  - `run_smoke_prompts`
  - `validate_global_runtime`
  - `automation_daily_smoke`
  - `automation_git_review`
  - `automation_self_improve_nightly`（WSL）
  - `automation_proactive_heartbeat`（WSL）

### 8) 可选高级模块接入

- `external/modules/mod-a`
- `external/modules/mod-b`
- `external/modules/mod-c`
- `external/modules/mod-d`

在标准 bundle 结构下，主脚本会自动发现并启用这些模块；若目录缺失会默认尝试执行 `git submodule update --init --recursive`（除非显式 skip-submodule-init）；只有目录不标准时才需要手动传 `SourcePath` 覆盖。

### 9) 团队可交付文档体系

- 快速上手：`win/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`、`wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- 深度指南：`win/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`、`wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- 发布前检查：`docs/RELEASE_CHECKLIST.md`
- 可移植性检查：`docs/PORTABILITY_CHECKS.md`

## 你现在这套方案的边界（避免过度承诺）

下面这些不属于“路径迁移”本身，仍需用户环境配合：
- OAuth/桌面密钥环登录态（如 WSL 的 `org.freedesktop.secrets` 相关依赖）
- 真实凭据（如 `GITHUB_TOKEN` / `GITHUB_PAT`）需要用户自己配置
- 外部服务波动可能影响 smoke（例如短时网络/API 5xx）

这部分已经在 Win/WSL guide 的 prerequisite / troubleshooting 中给出处理路径。

进一步细节（插件级/脚本级全量清单）见：
- `docs/FEATURE_MANUAL.zh-CN.md`
- `docs/FEATURE_MANUAL.md`

发布范围边界与子模块透明策略见：
- `docs/PUBLISHING_MODEL.zh-CN.md`
- `docs/PUBLISHING_MODEL.md`
