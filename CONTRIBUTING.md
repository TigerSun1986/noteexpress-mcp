# 维护者指南

本文仅供源码仓库维护者使用，不会随客户发布 ZIP 分发。

## 本地验证

测试和打包需要 PowerShell 5.1 或 PowerShell 7。Guard、工作流、包和安装器测试无需 Pester 或 NoteExpress；实时协议测试要求 NoteExpress MCP 端点在本机运行。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Workflows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Protocol.ps1
```

Guard 测试注入进程/套接字样例和模拟 JSON-RPC 服务。工作流测试检查文档描述的行为约定；安装测试使用隔离的临时目录。`Test-Protocol.ps1` 是实时只读兼容性检查，只发送 initialize、tools/list、noteexpress_version 和 ping 请求，不会创建或修改文献库记录。

## 生成客户发布包

不要把整个源码仓库压缩后当作客户安装包。使用白名单脚本生成精简 ZIP；测试、维护者文档、构建脚本和 Git 元数据不会被收进包中。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\New-ReleasePackage.ps1 -Version 1.0.0
```

默认产物为 `dist/noteexpress-mcp-v1.0.0.zip`。`dist/` 已加入 `.gitignore`。脚本仅在目标 ZIP 尚不存在时创建；重新打同一版本前，请先移走旧产物或改用新版本号。将此 ZIP 作为 GitHub Release 的下载资产提供给客户；GitHub 页面上的 Source code 压缩包对应整个源码仓库，仍会包含测试目录。

客户 ZIP 保留安装器所需的 `README.md`、`SKILL.md`、`install.ps1`、`uninstall.ps1`、`scripts/`、`references/` 和 `examples/`。其中的 `install.ps1` 会把 Skill 文件安装到客户端，不会安装 `tests/` 或维护者工具。

## 发布 npm npx 安装器

`package.json` 将包入口限定为 `bin/install-skill.cjs`，并通过 `files` 白名单包含安装器和 Skill 运行文件，不包含 `tests/`、`build/` 或本维护者文档。发布前需确认 npm 包名可用且账号有发布权限，确定许可证，并检查打包清单：

```powershell
npm pack --dry-run
```

当前 `package.json` 中的 `noteexpress-mcp-skill` 是候选包名；确定最终名称后再发布。发布到 npm 前，应先通过 `npm login` 登录有权发布该名称的账号，并按版本规则更新 `package.json`。
