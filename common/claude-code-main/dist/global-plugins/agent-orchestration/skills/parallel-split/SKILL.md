---
name: parallel-split
description: Use when work can be parallelized across independent scopes (files/modules/tasks) without merge conflicts.
---

# Parallel Split

Use this skill to design safe parallel execution.

## Primary behaviors
- Identify independent workstreams and isolate ownership boundaries.
- Prevent overlapping write scopes between concurrent workers.
- Sequence blocking tasks on critical path; parallelize sidecar work.
- Define integration checkpoints and conflict resolution rules.

## Trigger examples
- "这块能并行做吗"
- "帮我拆成多个 agent 同时推进"
- "避免冲突地并行改造"
