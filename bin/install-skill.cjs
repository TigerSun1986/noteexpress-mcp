#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const PACKAGE_ROOT = path.resolve(__dirname, '..');
const PACKAGE_ITEMS = ['SKILL.md', 'scripts', 'references', 'examples', 'README.md'];
const ALIASES = new Map([
  ['auto', 'auto'],
  ['standard', 'shared'],
  ['shared', 'shared'],
  ['codex', 'shared'],
  ['cursor', 'shared'],
  ['opencode', 'shared'],
  ['open-code', 'shared'],
  ['pi', 'shared'],
  ['claude', 'claude-code'],
  ['claude-code', 'claude-code'],
  ['claudecode', 'claude-code'],
  ['necode', 'necode']
]);

function usage() {
  console.log(`NoteExpress MCP Skill 安装器

用法：
  npx -y noteexpress-mcp-skill [选项]

选项：
  --client <auto|codex|cursor|claude-code|opencode|pi|necode>
  --agent <同 --client>
  --target <skills 根目录>
  --force                 更新已有安装的本包文件
  --help                  显示此帮助

默认行为：Claude Code shell 会话安装到 ~/.claude/skills；其他客户端安装到
~/.agents/skills（Codex、Cursor、OpenCode、Pi 使用的共用目录）。`);
}

function parseArgs(argv) {
  const parsed = { client: 'auto', target: null, force: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
    } else if (arg === '--force' || arg === '-f') {
      parsed.force = true;
    } else if (arg === '--client' || arg === '--agent') {
      if (!argv[i + 1]) throw new Error(`${arg} 后需要指定客户端。`);
      parsed.client = argv[++i];
    } else if (arg.startsWith('--client=') || arg.startsWith('--agent=')) {
      parsed.client = arg.slice(arg.indexOf('=') + 1);
    } else if (arg === '--target') {
      if (!argv[i + 1]) throw new Error('--target 后需要指定 Skills 根目录。');
      parsed.target = argv[++i];
    } else if (arg.startsWith('--target=')) {
      parsed.target = arg.slice('--target='.length);
    } else {
      throw new Error(`无法识别的选项：${arg}`);
    }
  }
  return parsed;
}

function resolveClient(requested) {
  const normalized = String(requested).toLowerCase();
  const client = ALIASES.get(normalized);
  if (!client) throw new Error(`不支持的客户端：${requested}`);
  if (client !== 'auto') return client;

  // Claude Code sets CLAUDECODE=1 in shells it creates. Other supported clients
  // share ~/.agents/skills, which is the safe default when no marker is present.
  if (process.env.CLAUDECODE === '1' || process.env.CLAUDE_CODE_ENTRYPOINT) {
    return 'claude-code';
  }
  return 'shared';
}

function resolveSkillsRoot(client, target) {
  if (target) return path.resolve(process.cwd(), target);
  if (client === 'claude-code') return path.join(os.homedir(), '.claude', 'skills');
  if (client === 'necode') {
    if (process.platform !== 'win32') {
      throw new Error('NeCode 的默认安装目录仅支持 Windows；请在 Windows 上运行，或通过 --target 指定目录。');
    }
    const appData = process.env.APPDATA;
    if (!appData) throw new Error('未找到 APPDATA 环境变量；请使用 --target 指定 Skills 根目录。');
    return path.join(appData, 'ai.necode.desktop', 'xdg-config', 'necode-desktop', 'skills');
  }
  return path.join(os.homedir(), '.agents', 'skills');
}

function copyTree(source, destination) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) throw new Error(`拒绝复制符号链接：${source}`);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const name of fs.readdirSync(source)) {
      copyTree(path.join(source, name), path.join(destination, name));
    }
    return;
  }
  if (!stat.isFile()) throw new Error(`不支持的文件类型：${source}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

function assertSafeCopy(source, destination) {
  if (!fs.existsSync(destination)) return;
  const targetStat = fs.lstatSync(destination);
  if (targetStat.isSymbolicLink()) throw new Error(`目标路径包含符号链接，拒绝写入：${destination}`);

  const sourceStat = fs.lstatSync(source);
  if (sourceStat.isDirectory()) {
    if (!targetStat.isDirectory()) throw new Error(`目标路径类型冲突：${destination}`);
    for (const name of fs.readdirSync(source)) {
      assertSafeCopy(path.join(source, name), path.join(destination, name));
    }
  } else if (!targetStat.isFile()) {
    throw new Error(`目标路径类型冲突：${destination}`);
  }
}

function detectNoteExpress() {
  if (process.platform !== 'win32') return null;

  const programRoots = [
    process.env.ProgramFiles,
    process.env['ProgramFiles(x86)'],
    process.env.LOCALAPPDATA
  ].filter(Boolean);
  const candidates = [];
  for (const root of programRoots) {
    candidates.push(path.join(root, 'NoteExpress', 'NoteExpress.exe'));
  }
  if (process.env.LOCALAPPDATA) {
    candidates.push(path.join(process.env.LOCALAPPDATA, 'Programs', 'NoteExpress', 'NoteExpress.exe'));
  }
  if (candidates.some(candidate => fs.existsSync(candidate))) return true;

  const tasklist = spawnSync('tasklist.exe', ['/FI', 'IMAGENAME eq NoteExpress.exe', '/NH'], {
    encoding: 'utf8',
    windowsHide: true
  });
  if (tasklist.status === 0 && /^\s*NoteExpress\.exe\s/im.test(tasklist.stdout || '')) return true;

  const uninstallKeys = [
    'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
    'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall',
    'HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall'
  ];
  for (const key of uninstallKeys) {
    const result = spawnSync('reg.exe', ['query', key, '/s', '/f', 'NoteExpress', '/d'], {
      encoding: 'utf8',
      windowsHide: true
    });
    if (result.status === 0 && /DisplayName\s+REG_SZ\s+NoteExpress\b/i.test(result.stdout || '')) return true;
  }
  return false;
}

function install(options) {
  const client = resolveClient(options.client);
  const skillsRoot = resolveSkillsRoot(client, options.target);
  const skillDirectoryName = client === 'necode' ? 'ne-mcp-guard' : 'noteexpress-mcp';
  const resolvedSkillsRoot = path.resolve(skillsRoot);
  const destination = path.resolve(resolvedSkillsRoot, skillDirectoryName);
  const relativeDestination = path.relative(resolvedSkillsRoot, destination);
  if (!relativeDestination || relativeDestination.startsWith('..') || path.isAbsolute(relativeDestination)) {
    throw new Error('安装目录越出 Skills 根目录，已停止。');
  }

  for (const item of PACKAGE_ITEMS) {
    if (!fs.existsSync(path.join(PACKAGE_ROOT, item))) {
      throw new Error(`npm 包内容不完整，缺少 ${item}。`);
    }
  }

  if (fs.existsSync(destination)) {
    const existing = fs.lstatSync(destination);
    if (existing.isSymbolicLink() || !existing.isDirectory()) {
      throw new Error(`目标不是普通目录，拒绝覆盖：${destination}`);
    }
    if (!options.force) {
      throw new Error(`目标目录已存在。检查后如需更新，请添加 --force：${destination}`);
    }
  }

  fs.mkdirSync(skillsRoot, { recursive: true });
  fs.mkdirSync(destination, { recursive: true });
  for (const item of PACKAGE_ITEMS) {
    assertSafeCopy(path.join(PACKAGE_ROOT, item), path.join(destination, item));
  }
  for (const item of PACKAGE_ITEMS) {
    copyTree(path.join(PACKAGE_ROOT, item), path.join(destination, item));
  }

  if (client === 'necode') {
    const skillPath = path.join(destination, 'SKILL.md');
    const skillText = fs.readFileSync(skillPath, 'utf8');
    const renamed = skillText.replace(/^name:\s*noteexpress-mcp\s*$/m, 'name: ne-mcp-guard');
    if (renamed === skillText) throw new Error('无法更新 NeCode Skill ID；请检查 SKILL.md frontmatter。');
    fs.writeFileSync(skillPath, renamed, 'utf8');
  }

  console.log(`已安装到：${destination}`);
  console.log('MCP 配置未修改。安装后请确认 NoteExpress MCP 已在客户端中单独注册。');
  const noteExpress = detectNoteExpress();
  if (noteExpress === true) {
    console.log('已检测到 NoteExpress。');
  } else if (noteExpress === false) {
    console.log('提醒：当前 Windows 电脑未检测到 NoteExpress。请访问 https://www.inoteexpress.com/ 下载适用于本机且包含 MCP 服务的版本，安装并启动后再配置 MCP。');
  } else {
    console.log('提醒：NoteExpress MCP 需要运行在 Windows 主机上。请访问 https://www.inoteexpress.com/ 在该主机安装适用且包含 MCP 服务的版本。');
  }
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    usage();
  } else {
    install(options);
  }
} catch (error) {
  console.error(`安装失败：${error.message}`);
  process.exitCode = 1;
}
