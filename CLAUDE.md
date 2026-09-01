# CLAUDE.md

## 项目简介
BeeMaster:运行在 OpenComputers 机器人上的 Minecraft 养蜂自动化程序,用于 Forestry 模组生态(GTNH 整合包)的蜜蜂突变、基因纯化与品种优化。

## 工作规则
- **未经用户明确允许,禁止自动执行 `git commit` / `git push` 等任何提交操作。**
- 完成改动后,先展示改动内容并说明,等待用户确认后才提交。
- 只有用户明确表示"提交"时才执行 git 提交。

## 技术栈
- Lua(OpenComputers 环境,模块化设计)
- 核心模块:`bee`(入口)、`bot`(机器人控制)、`strategy`(培育策略)、`beeData`(模板蜂与数据)、`apiary`(蜂箱调度)、`mutations`(突变数据)、`analyzeGenes`(基因解析)
- 运行时生成文件 `data.txt` 已加入 `.gitignore`
