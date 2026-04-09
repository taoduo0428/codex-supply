# 功能全量手册（超详细）

[English](./FEATURE_MANUAL.md) | [简体中文](./FEATURE_MANUAL.zh-CN.md)

本文是发布版的“功能说明总账”，目标是回答三件事：
1. 你这套增强包到底包含什么能力。
2. 哪些能力现在是默认自动开启。
3. 哪些能力仍然需要用户提供凭据或环境条件。

## 1. 自动启用矩阵（当前版本）

| 能力 | 默认行为 | 自动启用条件 | 仍需手动时机 |
| --- | --- | --- | --- |
| 全局插件安装（5个） | 开启 | 提供 `RepoRoot` 或可自动定位到 `common/claude-code-main` | 目录非标准且无法自动定位 |
| 模块 `superpowers` | 开启 | `external/modules/mod-a` 存在 | 模块不在标准目录，需 `SourcePath` 覆盖 |
| 模块 `OpenSpace` | 开启 | `external/modules/mod-b` 存在且 host_skills 完整 | 非标准目录或缺失 host_skills |
| 模块 `self-improving` | 开启 | `external/modules/mod-c` 存在 | 非标准目录或脚本缺失 |
| 模块 `proactive` | 开启（元数据接入） | `external/modules/mod-d` 存在 | 非标准目录 |
| `external/*` 子模块自动初始化 | 自动尝试 | 检测到模块目录缺失 + bundle 是 git 仓库 + 本机有 git | 显式传了 skip-submodule-init，或本机/网络条件不满足 |
| GitReview 自动任务 | 默认开启 | 未设置 disable 标记 | 用户显式关闭 |
| NightlyMemory 自动任务 | 默认开启 | 未设置 disable 标记且脚本存在 | 用户显式关闭或脚本缺失 |
| rules/AGENTS/ACTIVE 策略注入 | 开启 | 未设置 skip 标记 | 用户显式 `skip-*` |
| 原生 hooks 管理 | 开启 | 未设置 skip 标记 | 用户显式 `skip-native-hooks` |
| WSL secret-service 快速初始化 | 尝试自动（非阻塞） | 存在 `setup_wsl_secret_service.sh` | 依赖缺失时需手动安装依赖 |

术语说明：
- “可选模块”是分发层概念（你可以决定是否把模块源纳入仓库）。
- “默认开启”是运行时概念（只要模块在标准路径存在，bootstrap 会自动启用）。

## 2. 仍需用户手动提供的内容（不可完全自动）

这部分不是脚本缺陷，而是安全/平台限制：

1. GitHub 认证凭据：`GITHUB_TOKEN` 或 `GITHUB_PAT`。
2. OAuth/桌面密钥环登录态（例如 WSL 中 `org.freedesktop.secrets` 依赖）。
3. 非标准目录布局下的自定义路径（可用 `SourcePath` 覆盖）。
4. 业务工作区选择（虽可自动兜底，但推荐明确传 `WorkspacePath`）。

## 3. 插件层能力清单（5个）

插件来源：`common/claude-code-main/dist/global-plugins`

### 3.1 `workspace-core`

- 职责边界：
  仓库探索、状态诊断、上下文整理、会话卫生。
- 典型触发：
  “先扫一遍仓库状态”“先总结风险再动手”“先整理会话上下文”。
- 示例提示词：
  - `扫描当前仓库并给出编码前风险摘要。`
  - `列出改动文件和当前上下文压力。`
  - `整理会话但保留未解决阻塞。`
- 输入依赖：
  可访问的工作区路径与基础读取权限。
- 典型输出：
  仓库状态摘要、风险清单、下一步建议。
- 常见误解：
  它不是发布门禁插件，不替代评审/上线检查。
- 故障排查：
  先确认 workspace 指向正确仓库且具备读取权限。

### 3.2 `git-review`

- 职责边界：
  diff 评审、提交边界治理、PR 准备、发布前质量门。
- 典型触发：
  “整理成可提 PR”“评估这次 diff 风险”“现在能不能发版”。
- 示例提示词：
  - `审查当前 diff 并给出提交拆分建议。`
  - `生成 PR 摘要，包含风险和测试说明。`
  - `对当前分支执行发布 go/no-go 检查。`
- 输入依赖：
  可访问的 git 仓库和历史/差异信息。
- 典型输出：
  提交拆分方案、评审摘要、发布风险提示。
- 常见误解：
  通过 `git-review` 不等于可直接上线，CI/集成验证仍必需。
- 故障排查：
  检查仓库是否可信、分支上下文是否明确、diff 是否可读取。

### 3.3 `agent-orchestration`

- 职责边界：
  任务拆解、阶段编排、并行流划分与归属边界定义。
- 典型触发：
  “先做分阶段方案”“帮我并行拆任务”“给里程碑和验收门槛”。
- 示例提示词：
  - `把这个需求拆成可执行阶段并标注依赖。`
  - `拆成不冲突的并行工作流并定义负责人。`
  - `给每个阶段设置验证关卡。`
- 输入依赖：
  清晰目标和约束条件。
- 典型输出：
  阶段计划、并行分工图、验证检查点。
- 常见误解：
  需求描述越模糊，拆解结果越泛；它不能替你补齐需求本身。
- 故障排查：
  先收敛目标边界和约束，再重新拆解。

### 3.4 `integration-runtime`

- 职责边界：
  MCP 与运行时接线、连接器故障诊断、配置一致性校验。
- 典型触发：
  “把 MCP 接起来”“为什么 connector 连不上”“检查 runtime 配置漂移”。
- 示例提示词：
  - `为当前工作区引导 MCP 并做连通性检查。`
  - `排查 github MCP 不可用的根因。`
  - `检查插件层和全局 config 的接线一致性。`
- 输入依赖：
  `node`/`npx`/MCP 工具、网络可达性、以及部分连接器的凭据。
- 典型输出：
  配置修补建议、健康检查结果、依赖缺口报告。
- 常见误解：
  接线成功不等于认证成功，token/OAuth 仍需用户提供。
- 故障排查：
  优先检查 token 环境变量、keyring 状态、连接器特定依赖。
- 内置 MCP 基线（重点）：
  `playwright`、`filesystem`、`fetch`、`git`、`github`（依赖 token）、`openaiDeveloperDocs`。

### 3.5 `personal-productivity`

- 职责边界：
  验证-排障闭环与记忆治理，提升长期稳定执行质量。
- 典型触发：
  “先验证再修”“反复失败要闭环”“把流程沉淀成可复用规则”。
- 示例提示词：
  - `运行 verify-debug 循环直到满足通过标准。`
  - `总结本轮修复后仍未消除的风险。`
  - `把本次可复用经验写成稳定记忆条目。`
- 输入依赖：
  可复现的验证路径（测试/lint/build/smoke）和可观察失败信号。
- 典型输出：
  通过标准、循环结果、残余风险、记忆更新建议。
- 常见误解：
  记忆整理不能替代可重复的工程测试。
- 故障排查：
  先明确 pass/fail 标准，并确保至少一个可复现检查存在。

### 3.6 运行时接线细节（按插件真实文件）

证据文件：
- `common/claude-code-main/dist/global-plugins/<plugin>/.mcp.json`
- `common/claude-code-main/dist/global-plugins/<plugin>/hooks.json`
- `common/claude-code-main/dist/global-plugins/<plugin>/.app.json`

当前实装形态：
- `workspace-core`：插件内未声明 MCP server；hooks/app 也为空。
- `git-review`：插件内未声明 MCP server；hooks/app 也为空。
- `agent-orchestration`：插件内未声明 MCP server；hooks/app 也为空。
- `personal-productivity`：插件内未声明 MCP server；hooks/app 也为空。
- `integration-runtime`：承载 MCP 基线（`playwright`、`filesystem`、`fetch`、`git`、`github`、`openaiDeveloperDocs`）。

这意味着：
- 运行时集成能力是集中在 `integration-runtime` 管理，排障路径更清晰。
- `github` server 虽然已配置，但是否可用仍取决于用户是否提供 token（`GITHUB_TOKEN`/`GITHUB_PAT`）。
- hook 实际执行入口主要来自全局 `~/.codex/hooks.json`，而不是各插件 `hooks.json` 内部条目。

## 4. 脚本层能力清单（Windows）

目录：`common/claude-code-main/scripts`

| 脚本 | 作用 | 关键输入 | 关键输出 |
| --- | --- | --- | --- |
| `bootstrap_fresh_global_full.ps1` | 全量全局引导（核心入口） | RepoRoot/WorkspacePath + 可选覆盖参数 | 插件、MCP、策略、hooks、自动任务 |
| `validate_global_runtime.ps1` | 检查全局安装完整性 | 期望工作区（可推断） | PASS/FAIL 检查报告 |
| `run_smoke_prompts.ps1` | 5 个能力域 smoke 测试 | 工作区/超时/重试 | case 级日志与结果 |
| `setup_automations.ps1` | 注册计划任务 | 时间参数、间隔参数 | DailySmoke/GitReview 任务 |
| `automation_daily_smoke.ps1` | 日常自动巡检 | workspace + 超时 | 日志 + 失败即非零退出 |
| `automation_git_review.ps1` | 自动生成 git review 报告 | workspace/timeout | `reports/git-review-*.md` |
| `set_active_repo.ps1` | 设置活跃仓库指针 | repo 路径 | `~/.agents/active-repo.txt` |
| `remove_automations.ps1` | 清理自动任务 | 无 | 删除任务 |
| `bootstrap_fresh_global.ps1` | 精简版引导入口 | 同类参数 | 基线安装（轻量） |

## 5. 脚本层能力清单（WSL）

目录：`wsl/automation/scripts`

| 脚本 | 作用 | 关键输入 | 关键输出 |
| --- | --- | --- | --- |
| `validate_global_runtime.sh` | 全局安装自检 | expected workspace | PASS/FAIL 明细 |
| `run_smoke_prompts.sh` | 5 能力域 smoke（带重试） | workspace/timeout/retry | case 日志与汇总 |
| `automation_daily_smoke.sh` | 每日自动巡检 | workspace + timeout | logs/daily-smoke-* |
| `automation_git_review.sh` | 自动 git 评审报告 | workspace + timeout | reports/git-review-* |
| `automation_self_improve_nightly.sh` | 夜间记忆管线 | 依赖 self-improving 脚本 | nightly status + log |
| `automation_proactive_heartbeat.sh` | 主动心跳与风险信号记录 | 风险阈值参数 | heartbeat json + context |
| `setup_automations.sh` | 注册 cron 任务 | 时间与开关参数 | Daily/GitReview/Nightly/Heartbeat |
| `setup_wsl_secret_service.sh` | WSL 密钥环修复/配置 | 可选安装与 shell 注入开关 | secret-service 初始化脚本 |
| `setup_proactive_heartbeat_task.sh` | 单独注册心跳任务 | 间隔小时 | 对应 cron 项 |
| `set_active_repo.sh` | 设置活跃仓库 | repo 路径 | `~/.agents/active-repo.txt` |
| `remove_automations.sh` | 删除自动化 cron | 无 | 清理 cron |
| `common.sh` | 公共函数与环境加载 | `.env` + 环境变量 | 被其它脚本复用 |

## 6. 治理运行时能力（Windows/WSL）

主目录：`~/.codex/runtime/governance`

固定能力集合：
- `codex_preflight_gate.*`：高风险命令前置判定。
- `codex_doctor.*`：运行时健康检查。
- `codex_regression_check.*`：分发与策略回归检查。
- `codex_project_contract_init.*` / `check.*`：项目契约初始化与校验。
- `codex_crawler_project_init.*` / `smoke_test.*`：爬虫项目模板与冒烟。
- `codex_native_governance_hook.*`：hook 入口转发。

配套配置：
- `~/.codex/hooks.json`（自动写入 hook 调用）
- `~/.codex/config.toml` 中 `codex_hooks = true`

## 7. 默认启动流程（摘要）

1. 脚本解析参数并自动探测标准目录。
2. 全局插件安装 + marketplace 注册。
3. MCP 与 config 注入（含 openspace 环境段）。
4. 安全规则 + AGENTS/ACTIVE marker 注入。
5. 自动任务/cron 注册（默认带 GitReview + NightlyMemory）。
6. 治理脚本与 native hooks 落地。
7. 运行 doctor/regression/smoke（按配置）。

## 8. 你最关心的“普通 Codex vs 本方案”一句话版

普通 Codex 通常是“会话级能力 + 手工环境维护”；  
本方案是“全局可复现能力包 + 可执行治理 + 自动回归与记忆管线”。

如果你对外开源，这份文档就是“功能账本 + 证据目录”。
