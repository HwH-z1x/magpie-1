# 每请求意图路由：定制版操作说明

本版本基于 `HwH-z1x/magpie-1` 的 `custom/request-intent` 分支。原始源码快照仍在上一级目录；实际 Git 工作区为 `custom-src`。用户明确要求不编写测试代码，因此本次没有新增或修改测试文件。现有检查可以继续执行，但不能证明新增模式已通过专门的自动回归验证。

## 使用

在“路由”页面编辑目标组，将“规则判断频率”设为“每请求”，配置分类模型和意图规则并保存。通用规则应放在意图规则之后，否则仍按第一条匹配规则执行，可能由通用规则决定模型。

同轮返回工具结果时也重新调用分类器。分类输入包括用户任务、最近的工具调用/结果和可见助手文本，有长度限制；不包括推理签名或二进制附件。相同输入不会命中本地分类结果缓存，分类失败也不会因分类层的冷却而跳过下一请求。供应商或账号自己的休息、额度和固定账号限制仍然有效。

每请求不代表每次必须切换模型，也不保证每次分类成功。分类失败时可沿用最近的有效意图，路由记录会说明。分类器的推理强度判断仍受原有缓存保温策略影响，可能保持较高强度。每次额外分类会产生延迟、用量以及可能的提示缓存损失。

子组独立设置频率；想全链路每请求判断，需要设置参与选择的各级组。手动路由保留手选模型。严格会话保持不能和同组的每请求规则组合，普通保持可用于成员内部账号选择。模型列表、健康检查等非生成接口不分类。分类器自己的请求不再递归分类，同一入站请求内部的供应商重试不重复分类。

也可执行：

```powershell
.\dist\magpie-custom.exe group set <组ID> rule-scope=request
.\dist\magpie-custom.exe group set <组ID> rule-scope=turn
```

路由动画沿用核心网关的真实记录，请求明细会标注当前请求分类、耗时、截断或降级；不需要安装额外的外部路由插件。

## 构建

源码要求的 Go 版本以 `go.mod` 为准。当前是 Go 1.26.8，便携工具链位于上一级的 `.toolchain/go`；缓存也在该目录，没有修改系统 Go 安装。

```powershell
$env:CGO_ENABLED = '0'
..\.toolchain\go\bin\go.exe run github.com/tc-hib/go-winres@v0.3.3 make --in build/windows/winres.json --arch amd64,arm64 --out rsrc --file-version 0.0.0 --product-version 0.0.0
..\.toolchain\go\bin\go.exe build -tags production -trimpath -ldflags '-s -w -H windowsgui -X main.version=custom-request-intent-dev' -o dist/magpie-custom.exe .
```

正式维护构建使用提交 SHA 的 `custom-<sha>` 版本，避免官方更新覆盖定制行为。构建出 exe 不等于实际供应商验证完成；运行前退出占用默认 3425 端口的官方版。

首次使用建议把 exe 放到专属目录，并在其旁新建 `.portable`，配置位于旁边的 `data`。这会建立独立配置，不会自动继承官方版账号。若希望迁移，先正常退出官方版、备份其实际数据目录，再按 Magpie 的备份/恢复能力迁移。不要在未确认便携/安装模式前覆盖数据。

## 获取上游更新

`origin` 指向个人 fork，`upstream` 指向 `yetone/magpie`。先提交本地定制改动，再执行：

```powershell
.\build\update-custom.ps1 -Action Check
.\build\update-custom.ps1 -Action Build -Go 'C:\Users\Hao\Desktop\magpie-main\.toolchain\go\bin\go.exe'
```

Build 在 Git 内部目录创建独立候选 worktree，合并固定的上游 SHA，运行已有 Go suite/vet，生成 Windows 资源和 exe。冲突时保留候选区并停止；源分支和正在使用的程序保持原样。候选目录包含 `manifest.json` 和校验值。

清单的 `remainingChecks` 列出 GUI、Linux、race、隔离 Agent 实测等未执行项；由维护者完成并记录实际结果后清空，才能部署。不能因只做了 Windows 构建就清空列表。脚本保留所有候选与诊断，不自动清理历史版本，不自动推送 GitHub、不建立定时任务，也不自动推进源码维护分支。

若候选验证合格，先在干净源码工作区合并候选清单里的 commit 并核对身份，再推送个人 fork。冲突解决或任何追加改动都需要重新构建验证，不能沿用旧候选清单。

## 部署与回退

脚本部署仅管理显式指定、已有 `.portable` 标记的专属便携目录，使用默认网关端口 3425。它不自动接管官方安装目录或其他数据位置。

```powershell
.\build\update-custom.ps1 -Action Deploy -Candidate '<候选package目录>' -RunDirectory '<专属运行目录>'
.\build\update-custom.ps1 -Action Rollback -RunDirectory '<专属运行目录>'
```

脚本只定位该路径的 `magpie-custom.exe`，请求正常退出；托盘程序不退出时提示手动退出，不强杀。停机后复制完整 data 并保留旧 exe，再在同卷替换文件；启动时检查网关监听进程归属和健康。新版本失败时尝试还原旧 exe 和部署前数据，若失败进程仍占用文件则停止并保留回滚状态，需退出程序后显式 Rollback。

`.backups` 保存部署前状态，`.failed-*` 保留回退时较新的数据。回滚会恢复部署前数据，之后产生的会话变化不会自动合并，但仍保存在 failed 目录。首次部署没有旧 exe 时回滚只恢复原来的空安装状态。不要删除备份直到确认新版本和数据正常。

当前脚本已经过语法解析；未在用户实际安装或账号上执行部署/回滚演练。它还需要在隔离便携目录中验证后才能用于日常更新。
