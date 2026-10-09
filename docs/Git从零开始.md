# Git 从零开始：三人 FPGA 项目

适用目录：D:\FPGA\fpga_synth_team。共享平台按用户选择为 GitHub，建议私有仓库。2026-10-07 已创建项目框架、说明、忽略规则和单音参考副本；尚未创建 .git、提交或上传。

## 1. 先理解四件事

- 工作文件夹：你用 Gowin/编辑器实际修改的文件。
- Git 本地仓库：隐藏的 .git 目录保存提交历史；不要手工修改它。
- commit 提交：把选定内容保存为一个带说明的本地版本。Ctrl+S 不会自动 commit。
- GitHub 远程仓库：三人的共享副本。push 上传提交，pull 获取并整合远程更新。commit 不等于上传。

暂存区是“本次准备提交的内容”：git add 放进去，git diff --cached 查看，git commit 保存版本。如果 add 后又编辑，提交前要再 add 更新。

## 2. 在自己的 PowerShell 检查 Git

Windows 打开终端/PowerShell，输入：

```powershell
git --version
```

看到 git version ... 就能使用。若提示找不到 git，从 https://git-scm.com/install/windows 安装 Git for Windows。安装时选择允许从命令行及第三方软件使用 Git（Git from the command line and also from 3rd-party software），保留 Git Credential Manager，编辑器可选 Notepad。安装完成关闭旧终端、重新打开，再检查版本。

此次助手环境发现的是 Codex 自带 Git，不代表普通 PowerShell 已有可用的 Git。不要把 Codex 缓存目录手动加到系统 PATH。

## 3. 你先完成本地第一版（只有你运行 init）

以下每行单独输入，确认输出再继续。git config 的名字和邮箱必须换成你的信息；这是提交作者标识，不是登录密码。可用 GitHub 已验证邮箱或账号设置中的 noreply 邮箱。

```powershell
Set-Location 'D:\FPGA\fpga_synth_team'
git init -b main
git config user.name "你的姓名或昵称"
git config user.email "你的提交邮箱"
git status
```

配置仅作用于这个项目。克隆后的队友也分别配置自己的作者信息。

检查当前目录是 fpga_synth_team，第一次提示 main、尚无提交，以及 README.md、rtl 等未跟踪文件是正常的。

第一次框架提交可以选整个目录：

```powershell
git add .
git diff --cached --stat
git diff --cached
git commit -m "建立三人FPGA项目框架"
git status
git log --oneline -5
```

diff 如果进入分页器，按 q 返回。提交后应看到 working tree clean（工作区干净）。这不是说源码已验证，只表示当前文件与最近一次提交一致。

本框架没有 .fs、ZIP 大包或编译缓存，提交前仍应检查文件清单。后续优先按路径 add 自己实际修改的文件，避免把无关改动一起提交。

## 4. 练习第二次提交

用编辑器打开 README.md，末尾增加一行“Git练习：已学会保存本地版本。”，保存，然后：

```powershell
git status
git diff
git add README.md
git diff --cached
git commit -m "记录第一次Git练习"
git log --oneline -5
```

看到两条提交就完成本地练习。理解修改→保存→检查→暂存→提交，再进入共享阶段。

## 5. 你在 GitHub 建一个空私有仓库

登录 GitHub → 创建 New repository。仓库名可用 fpga-synth-team，选择 Private。因为本地已有 README 和提交，不勾选远程初始化 README，不添加远程 .gitignore 或 license，创建空仓库。

打开仓库的 HTTPS 地址，复制类似 https://github.com/你的账号/fpga-synth-team.git 的实际地址。以下命令里的账号与地址必须替换，不能原样使用：

```powershell
git remote add origin https://github.com/你的账号/fpga-synth-team.git
git remote -v
git push -u origin main
```

第一次可能由 Git Credential Manager 打开浏览器要求登录授权，按 GitHub 界面操作。GitHub HTTPS 不接受账户密码作为 Git 密码；若只出现密码提示且无法浏览器登录，先保留提示，按官方认证说明配置凭据，不要反复输入账户密码，也不把令牌写进 URL 或教程。

上传成功后刷新 GitHub，应能看到 README、rtl、docs、labs 等。若因网络/认证失败，本地提交仍保留，不需要重新 init。若远程不是空仓库而被拒绝，不用强制推送覆盖；先检查远程内容。

## 6. 邀请两名队员并让他们克隆

仓库 Settings → Collaborators（界面名称可能包含 access）→ Add people，输入队友 GitHub 用户名，他们接受邀请。三人各用自己的账号。

队友在自己的电脑准备 Git，在一个存放项目的父目录中克隆，目标目录不要提前放同名文件：

```powershell
Set-Location 'D:\FPGA'
git clone https://github.com/你的账号/fpga-synth-team.git fpga_synth_team
Set-Location '.\fpga_synth_team'
git config user.name "队员自己的昵称"
git config user.email "队员自己的提交邮箱"
git status
```

他们的磁盘可以不同，路径换成自己的。clone 自动建立本地 .git 和 origin，不要再 init 或另建一份远程仓库。不要只下载 ZIP 来代替 clone 做协作。

## 7. 三个人怎么同时开发

main 是共享主版本；分支是一条独立的修改线路，在同一工作文件夹中切换时，文件内容会跟着切换。第一轮各自创建任务分支：

- 队长：synth-dds，做 DDS。
- A：audio-tx，做输出。
- B：input-key，做输入。

以队长为例，在自己的项目目录，先确认工作区干净，再执行：

```powershell
git switch main
git pull --ff-only
git switch -c synth-dds
```

A/B 把最后一行分支名换成 audio-tx/input-key。-c 表示首次创建，已有同名分支时使用 git switch 分支名即可，不重复 -c。

队长写完自己的 DDS 和测试后：

```powershell
git status
git diff
git add rtl/synth tb/synth
git diff --cached
git commit -m "实现可变频DDS，440Hz和880Hz仿真通过"
git push -u origin synth-dds
```

这条提交说明只是示例：只有实际验证通过才能这样写。还未验证就写明未验证。A add 自己的 rtl/audio、tb/audio；B add rtl/input、tb/input；各人有脚本或文档时单独加入相应文件。

## 8. 合并到 main

在 GitHub 的 Pull requests 中创建请求，base 选 main、compare 选自己的任务分支。说明改了什么、接口是什么、怎么验证、还没做什么。

队长检查核心，A 主持工程集成，B 检查输入接线。检查后使用普通 Create a merge commit / Merge pull request 合并即可，第一轮不需要掌握 rebase、cherry-pick 或强制推送。

合并后每人保存自己未完成工作并提交，确认工作区干净，再更新主分支：

```powershell
git switch main
git pull --ff-only
```

下一项任务从更新的 main 创建新分支，例如 synth-adsr、audio-i2s、input-pressure。第一版建议一次 PR 对应一个小任务，完成后不继续使用已经结束的旧任务分支；旧分支不用急着删除。

切分支前若工作区不干净，先在当前任务分支完成/提交自己的工作；不要照搬丢弃改动命令。pull --ff-only 失败时先看状态和历史，不 force 或 reset 覆盖。

## 9. 冲突如何处理

两人修改同一个文件的同一段，Git 不一定能自动决定保留哪个，会出现冲突。这不是代码被自动删除。

减少冲突：队长主改 synth，A 主改 audio/top/工程/约束，B 主改 input，公共接口先协商。第一次出现冲突时，把涉及文件和状态给负责集成的 A，一起检查两份改动；不要直接选“全部保留我的”或强推 main。

## 10. 哪些文件要保存

必须保存：.v/.sv 源码、testbench、.cst/.sdc、.gprj、必要波表、生成/验证脚本、接口/接线/测试文档。

Gowin 有些构建配置存于 impl/*_process_config.json，CPU 等双用途引脚设置不能丢。本框架没有把整个 impl 目录忽略，只忽略 pnr、gwsynthesis、temp 等生成目录。A 建最终工程后必须验证必要配置全部可重建。

默认忽略：.gprj.user 个人设置、编译缓存、.fs/.bin、仿真中间结果与大波形。需要作为最终证据的图表/CSV/说明主动放 docs；.fs 在验证后作为交付附件归档，记录对应 git 提交号或版本标签。别提交卖家 ZIP、安装包或与项目无关的下载目录。

## 11. 每日使用习惯

开始：看 status，保存自己改动，更新 main，从 main 创建一个任务分支。

开发：只改相关模块，做独立验证，及时小提交；工作可以中途提交但说明未完成，不把未完成模块合入 main。

交付：push 分支，提出 PR，写明测试结果；合并后下次从新的 main 开始。周末三人联调，通过后再打清晰版本标签，例如 v0.1-one-note，并保存对应码流和测试记录。

## 官方资料

- Git Windows 安装：https://git-scm.com/install/windows
- Git 中文入门：https://git-scm.com/book/zh/v2
- GitHub 新建仓库：https://docs.github.com/zh/repositories/creating-and-managing-repositories/creating-a-new-repository
- GitHub 邀请协作者：https://docs.github.com/zh/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository
- GitHub 推送已有代码：https://docs.github.com/zh/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github
- GitHub 认证：https://docs.github.com/zh/authentication/keeping-your-account-and-data-secure/about-authentication-to-github
