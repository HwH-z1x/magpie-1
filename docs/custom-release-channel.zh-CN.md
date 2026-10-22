# 分支发行与重启更新

## 更新的是什么

客户端每次更新下载的都是“上游正式版源码 + 本分支修改”重新编译后的完整程序，而不是下载官方 exe 再打补丁。当前仅发布 Windows x64 桌面版，更新渠道标识为 `request-intent`（实验发行）。每个 Release 附带的 `build.json` 会公开当次构建已执行的检查范围与未验项目。

Windows x64 发行版已在 [分支 Releases](https://github.com/HwH-z1x/magpie-1/releases?q=request-v&expanded=true) 持续发布，构建记录可在 [Actions](https://github.com/HwH-z1x/magpie-1/actions/workflows/custom-release.yml) 查看。请勿用官方原版安装包替代分支发行包。

最新通过发布检查的安装包会标记为 GitHub 的 Latest，显示在仓库首页。这个标记用于提供下载入口，验证范围仍以发行说明和 `build.json` 为准。早期版本曾标为 Pre-release，因此首页没有 Latest；维护者可手动运行 `Show Current Fork Release`，校验当前更新渠道中的安装包后恢复首页入口。

## 用户操作

1. 从带 `request-v` 前缀的分支 Release 下载 `magpie-windows-amd64.exe`，核对同页 `SHA256SUMS`，先退出原版并备份数据。
2. 将 exe 放到专属目录（可改名为 `magpie-custom.exe`）。如需隔离配置，在同目录新建 `.portable` 文件；便携模式不会自动迁移原有账号。
3. 首次从原版或本地开发版切换时需手动替换一次。之后直接在软件内点击“检查 / 下载 / 重启更新”即可，本机无需安装 Git 或 Go。
4. 设置页版本行的悬停提示与 Release 说明都会标注分支渠道、对应的上游版本号和源码提交。分支版本号 `1.0.N` 独立递增，不等同于上游版本号。

原有的自动检查频率、仅通知或自动下载、网关忙时等待等设置保持不变。即使修改了本地 exe 文件名，更新器仍会按当前 GUI 平台匹配对应的发行资产。开发构建（如 `custom-<sha>`）、元数据不完整的构建及其他平台仍显示手动维护说明。

## 分支布局

- `main`：默认分支，也是唯一维护和发行主线，直接展示每请求意图路由功能。
- `request-update`：仅存放客户端在线更新的 JSON 清单，不是另一套程序源码。
- `custom/request-intent`：旧链接兼容入口，迁移时指向同一修改版；不再由自动发布脚本推进。新 clone、贡献和更新都使用 `main`。
- 原版代码从 `upstream` 远程或 `yetone/magpie` 的正式标签读取，原版项目介绍仅以折叠超链接保留。

## GitHub 维护流程

自动发布入口为 `.github/workflows/custom-release.yml`：北京时间每天 **08:00–23:00 每小时整点**检查一次，00:00–08:00 暂停自动检查。`main` 分支有新提交时也会触发，并遵守相同的夜间静默规则；手动触发（`workflow_dispatch`）不受时段限制。由于 GitHub 定时调度可能存在延迟，工作流在入口和查询前都会复核北京时间，但已启动的构建不会因跨过午夜而中断。

仓库须启用 Actions，允许本仓库工作流请求 `contents: write`。只使用内置 `GITHUB_TOKEN`，不需要个人 PAT、官方签名密钥或租用服务器。GitHub 对 fork、可复用工作流和第三方 Actions 的仓库/组织限制仍适用。定时任务只由默认分支触发；长时间无仓库活动时也可能被 GitHub 停用，可从 Actions 重新启用。

流水线按下列顺序执行：

1. 读取 `yetone/magpie-releases` 当前标记的正式 Latest，固定 `yetone/magpie` 同名源码标签的提交。
2. 在 runner 的候选 checkout 合并它。仅两份 README 明确保留分支介绍；代码冲突不会自动偏向任一边，直接失败。
3. 运行 Go 格式检查、Windows vet、现有 Go suite 的编译检查、现有 update 套件，以及 Chromium/WebKit 上现有更新界面和翻译检查。不生成或修改任何测试代码。这不是完整套件通过的承诺。
4. 生成 Windows 资源、production exe 和来源元数据。分支版本为独立递增的 `1.0.N`，标签为 `request-v1.0.N`，不会触发原版的 `v*` 发布工作流。
5. 再确认维护分支和更新渠道没有被其他提交推进，快进维护分支并创建实验 Release，上传 exe、校验值、来源记录和该版更新清单。
6. 从 GitHub 回读 exe 验证 SHA256，才公开 Release；最后用一次 Git 提交同时推进 `request-update` 分支的 `latest.json` 与 `notes.json`。

继承自上游的官方发布、Docker、隐私模型、官方全平台 CI 和截图工作流在本 fork 中不执行；本 fork 的检查与发行由 `custom-release` 流水线负责。没有新增测试代码，也没有把仅选定检查通过改写为完整套件通过。

同一渠道串行发布。没有源码或上游变化时退出；不重建相同版本、不覆盖既有标签或安装包。已占用的失败版本需要启动一次新的工作流运行，不能重跑后覆盖资产。合并或检查失败时维护分支和渠道不变；发布后半段失败可能留下候选提交或草稿，但客户端仍用原渠道。诊断和候选产物保留为 Actions artifact。

首次运行和后续运行均以 Actions 的实际结果为准。GitHub 配额、runner、网络、上游冲突或现有检查失败都会阻止更新；“最新”指最新成功集成并发布的上游版本，不保证与官方同步上线。

## 客户端信任边界

- 更新清单固定为 `https://raw.githubusercontent.com/HwH-z1x/magpie-1/request-update/latest.json`，历史说明为同分支 `notes.json`。不依赖 GitHub Pages，也不把 Releases API 当成 Magpie 清单。
- 官方或环境变量覆盖的更新源不被使用。清单必须带 `request-intent` 标记、合法发行版本和源码提交，下载地址必须精确指向本仓库对应 `request-v` Release 的唯一 Windows x64 资产。
- 校验值的权威清单直接从 GitHub HTTPS 获取，不经不可信镜像回退。exe 下载仍可使用已有下载镜像，但必须匹配清单哈希；安装前再与当前进程记录的可信哈希核对。旧官方 `.new` 不能直接安装，管理员替换也一样。
- 信任依赖本仓库权限和 GitHub HTTPS，不是独立签名体系。请保护 GitHub 账号；Windows 安装包目前没有承诺 Authenticode 签名。SHA256 不能抵御仓库/发布账号被攻陷。

## 故障处理和回退

合并冲突需维护者在源码分支解决并提交，下一次运行重新检查。不要只同步官方 exe。遇到下载或校验错误保留当前程序，修复网络或渠道后重试。

更新器复用上游的文件替换和新二进制启动检查；启动被 Windows 安全策略阻止时，原有恢复机制仍适用。但**这不是配置数据库事务或数据迁移回滚**。升级前保留数据备份；需要降级时退出程序，手动下载旧 `request-v` 资产，按必要情况恢复配套数据。自动版本比较不会推送较低版本；旧包、较新数据和备份不要混着覆盖。

外部安装器、另一份官方程序和错误的快捷方式不在当前进程的保护范围内。实际安装和原生 GUI 重启尚需在隔离便携目录确认，不能把已有 GUI fixture 检查当成真实升级演练。
