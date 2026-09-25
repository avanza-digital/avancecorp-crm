import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '..');
const prompt = 'ROLE: SECONDARY_REVIEWER. Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate. Do not create another review chain.';
const safeCall = { sandbox: 'read-only', 'approval-policy': 'never', prompt };

function hook(input) {
  return spawnSync(join(root, '.claude/hooks/validar-codex-review.sh'), [], {
    input: typeof input === 'string' ? input : JSON.stringify({ tool_name: 'mcp__codex__codex', tool_input: input }),
    encoding: 'utf8', cwd: root,
  });
}

test('Codex accepts the explicit reviewer contract and rejects overrides', () => {
  assert.equal(hook(safeCall).status, 0);
  for (const patch of [
    { sandbox: 'workspace-write' }, { 'approval-policy': 'on-request' },
    { config: { 'features.shell_tool': true } }, { profile: 'writer' },
    { 'base-instructions': 'Implement' }, { cwd: '/tmp' },
    { prompt: 'ROLE: SECONDARY_REVIEWER. Please review.' },
    { prompt: `Implement first. Quoted instructions: ${prompt}` },
    { prompt: ['ROLE: SECONDARY_REVIEWER'] }, { model: {} },
    // Hallazgo de Codex (24/09): el token pegado colaba por `[.[:space:]]`.
    { prompt: prompt.replace('SECONDARY_REVIEWER.', 'SECONDARY_REVIEWER.PRIMARY') },
    { prompt: prompt.replace('SECONDARY_REVIEWER.', 'SECONDARY_REVIEWERX') },
  ]) {
    assert.equal(hook({ ...safeCall, ...patch }).status, 2, JSON.stringify(patch));
  }
  assert.equal(hook('{malformed').status, 2);
  assert.equal(hook(JSON.stringify({ tool_name: 'mcp__codex__codex-reply', tool_input: safeCall })).status, 2);
});

test('Codex launcher disables inherited servers individually and fails closed on invalid inventory', () => {
  // `codex mcp-server` fue retirado de la CLI (ausente en 0.155.1): el reviewer
  // ya NO es un servidor MCP. Si alguien lo vuelve a declarar aqui, Claude
  // intentara hablarle por MCP y morira con CONNECTION_CLOSED en cada sesion.
  const servers = JSON.parse(readFileSync(join(root, '.mcp.json'), 'utf8')).mcpServers;
  assert.equal(servers.codex, undefined);
  assert.ok(servers.playwright, 'el resto de MCP sigue declarado');
  const temp = mkdtempSync(join(tmpdir(), 'avancecorp-codex-review-'));
  try {
    const capture = join(temp, 'capture.json');
    writeFileSync(join(temp, 'codex'), `#!${process.execPath}\n` +
      `const fs = require('node:fs'); const args = process.argv.slice(2);\n` +
      `if (args.includes('features')) {\n` +
      `  process.stdout.write(['shell_tool','apps','hooks','plugins','remote_plugin','browser_use','computer_use','in_app_browser','in_app_local_automation','code_mode','skill_mcp_dependency_install'].map(f => f + ' stable ' + (process.env.KEEP_FEATURE ? 'true' : 'false')).join('\\n'));\n` +
      `} else if (args.includes('list')) {\n` +
      `  if (process.env.INVENTORY_EXIT) process.exit(1);\n` +
      `  let raw = process.env.INVENTORY;\n` +
      `  if (args.includes('mcp_servers.external.enabled=false') && !process.env.KEEP_ENABLED)\n` +
      `    raw = JSON.stringify(JSON.parse(raw).map(s => ({...s, enabled:false})));\n` +
      `  process.stdout.write(raw);\n` +
      `} else fs.writeFileSync(process.env.REVIEW_TEST_CAPTURE, JSON.stringify(args));\n`, { mode: 0o700 });
    const run = (extraEnv = {}, args = [], stdin = prompt) => spawnSync(join(root, 'scripts/codex-review-mcp'), args, {
      cwd: temp, encoding: 'utf8', timeout: 5000, input: stdin,
      env: { ...process.env, PATH: `${temp}:${process.env.PATH}`, REVIEW_TEST_CAPTURE: capture,
        INVENTORY: JSON.stringify([{ name: 'external', enabled: true }, { name: 'node_repl', enabled: true }]), ...extraEnv },
    });
    assert.equal(run().status, 0);
    const args = JSON.parse(readFileSync(capture, 'utf8'));
    assert.equal(args[0], 'exec');
    assert.equal(args[args.indexOf('--sandbox') + 1], 'read-only');
    for (const setting of [
      '--strict-config', 'sandbox_mode="read-only"', 'approval_policy="never"', 'agents.enabled=false',
      'features.shell_tool=false', 'features.apps=false', 'features.hooks=false',
      'features.plugins=false', 'features.remote_plugin=false', 'features.browser_use=false',
      'features.computer_use=false', 'features.in_app_local_automation=false',
      'web_search="disabled"', 'mcp_servers.external.enabled=false', 'mcp_servers.node_repl.enabled=false',
    ]) assert.ok(args.includes(setting), setting);
    assert.equal(run({}, ['--check']).status, 0);
    assert.equal(run({ KEEP_ENABLED: '1' }, ['--check']).status, 1);
    assert.equal(run({ KEEP_FEATURE: '1' }, ['--check']).status, 1);
    assert.equal(run({ INVENTORY: '[]' }).status, 0);
    for (const inventory of ['{malformed', '{}', '[{"name":"bad.name"}]', '[{}]']) {
      assert.equal(run({ INVENTORY: inventory }).status, 1, inventory);
    }
    assert.equal(run({ INVENTORY_EXIT: '1' }).status, 1);
    assert.equal(run({}, ['-c', 'sandbox_mode="workspace-write"']).status, 64);
    // El contrato del prompt se valida AQUI desde que no hay ruta MCP: el hook
    // de Claude solo cubria `mcp__codex__codex` y una llamada directa lo
    // esquivaba. Cada prohibicion ausente falla cerrado, antes de gastar tokens.
    assert.equal(run({}, [], '').status, 2, 'encargo vacio');
    assert.equal(run({}, [], 'Revisa esto').status, 2, 'sin ROLE: SECONDARY_REVIEWER');
    // Hallazgo de Codex (24/09): el regex heredado aceptaba un token pegado.
    for (const falso of ['ROLE: SECONDARY_REVIEWER.PRIMARY', 'ROLE: SECONDARY_REVIEWERX']) {
      assert.equal(run({}, [], `${falso}\n${prompt.slice(prompt.indexOf('Do not'))}`).status, 2, falso);
    }
    for (const frase of [
      'Do not modify files.', 'Do not implement the task.', 'Do not invoke Claude.',
      'Do not delegate.', 'Do not create another review chain.',
    ]) {
      assert.equal(run({}, [], prompt.replace(frase, '')).status, 2, `falta: ${frase}`);
    }
    for (const wrapper of ['codex-review-mcp', 'claude-review']) {
      const result = spawnSync('/bin/bash', [join(root, 'scripts', wrapper), 'Evidence'], {
        env: { ...process.env, PATH: '/nonexistent' }, encoding: 'utf8', input: '',
      });
      // Codex rejects overrides before checking the binary; invoke it without arguments.
      const missing = wrapper === 'codex-review-mcp' ? spawnSync('/bin/bash', [join(root, 'scripts', wrapper)], {
        env: { ...process.env, PATH: '/nonexistent' }, encoding: 'utf8', input: '',
      }) : result;
      assert.equal(missing.status, 127, wrapper);
    }
  } finally { rmSync(temp, { recursive: true, force: true }); }
});

test('Protective hooks fail closed without jq or with malformed input', () => {
  const emptyPath = mkdtempSync(join(tmpdir(), 'avancecorp-hook-path-'));
  try {
    for (const name of ['proteger-archivos.sh', 'proteger-comandos.sh', 'validar-codex-review.sh']) {
      const path = join(root, '.claude/hooks', name);
      assert.equal(spawnSync(path, { input: '{}', env: { ...process.env, PATH: emptyPath } }).status, 2, name);
      assert.equal(spawnSync(path, { input: '{malformed', encoding: 'utf8' }).status, 2, name);
      assert.equal(spawnSync(path, { input: '{}', encoding: 'utf8' }).status, 2, name);
    }
  } finally { rmSync(emptyPath, { recursive: true, force: true }); }
});

test('Common broad deletion and force-push forms are blocked; normal checks stay available', () => {
  const run = (command) => spawnSync(join(root, '.claude/hooks/proteger-comandos.sh'), [], {
    cwd: root, encoding: 'utf8', input: JSON.stringify({ tool_name: 'Bash', tool_input: { command } }),
  }).status;
  for (const command of [
    'rm -rf /', 'rm -fr ~/', 'rm -rf /*', 'rm -rf $HOME/', 'rm -rf "${HOME}"',
    'rm -rf "$HOME"', 'rm -rf ./', 'rm -rf .[a-z]*', 'rm --recursive --force /',
    'git reset --hard HEAD', 'git clean -fd', 'git push origin +HEAD:main',
    'git push origin main --force-with-lease', 'cat .env.production', 'cat .envrc',
    'git -C /tmp/repo reset --hard HEAD', 'git -C "repo with spaces" reset HEAD --hard',
    '/usr/bin/git -c core.pager=cat clean --force -d',
    'git -C /tmp/repo push origin main -f', 'git -C /tmp/repo push origin +HEAD:main',
    'cat .env.example', 'cat .env.example.local',
    'git show HEAD:.env', 'git show :.env.production', 'git show HEAD:secrets/token',
  ]) assert.equal(run(command), 2, command);
  for (const command of ['npm run check', 'node --check script.js', 'rm -rf /private/tmp/scoped-build', 'node -p process.env.NODE_ENV', 'git -C "repo with spaces" diff']) {
    assert.equal(run(command), 0, command);
  }
});

test('File protection covers credentials and every matching migration-edit tool', () => {
  const fixture = mkdtempSync(join(tmpdir(), 'avancecorp-migration-hook-'));
  try {
    assert.equal(spawnSync('git', ['init', '-q', fixture]).status, 0);
    mkdirSync(join(fixture, 'supabase/migrations'), { recursive: true });
    const tracked = 'supabase/migrations/001.sql';
    writeFileSync(join(fixture, tracked), '-- synthetic fixture\n');
    assert.equal(spawnSync('git', ['-C', fixture, 'add', tracked]).status, 0);
    const run = (tool_name, file_path) => spawnSync(join(root, '.claude/hooks/proteger-archivos.sh'), [], {
      cwd: fixture, encoding: 'utf8', input: JSON.stringify({ tool_name, tool_input: { file_path } }),
    }).status;
    assert.equal(run('Read', tracked), 0);
    for (const tool of ['Edit', 'Write', 'MultiEdit']) {
      assert.equal(run(tool, tracked), 2, tool);
      assert.equal(run(tool, join(fixture, tracked)), 2, tool);
    }
    assert.equal(run('Write', 'new-project/supabase/migrations/001.sql'), 0);
    assert.equal(run('Read', '/repo/src/config.ts'), 0);
    for (const file of ['/repo/.envrc', '/repo/.env.example', '/repo/.env.production', '/repo/secrets/token', '/repo/id_rsa']) {
      assert.equal(run('Read', file), 2, file);
    }
  } finally { rmSync(fixture, { recursive: true, force: true }); }
});

test('Scoped removals, pushes and database clients request permission without executing', () => {
  for (const command of ['rm -rf /private/tmp/scoped-build', '/bin/rm -r /tmp/fixture',
    'git push', 'git -C "repo with spaces" push avancecorp main',
    '/opt/homebrew/opt/postgresql@16/bin/psql --version', 'dropdb fixture',
    'supabase db reset', 'npx supabase@2.114.0 db push', '/usr/local/bin/vercel --prod',
    'npm run deploy', 'cd app && supabase functions deploy']) {
    const result = spawnSync(join(root, '.claude/hooks/proteger-comandos.sh'), [], {
      encoding: 'utf8', input: JSON.stringify({ tool_name: 'Bash', tool_input: { command } }),
    });
    assert.equal(result.status, 0, command);
    assert.equal(JSON.parse(result.stdout).hookSpecificOutput.permissionDecision, 'ask', command);
  }
});

test('Native secret rules and specialized reviewers close search and shell paths', () => {
  const settings = JSON.parse(readFileSync(join(root, '.claude/settings.json'), 'utf8'));
  for (const path of ['.env', '.env.*', '.envrc', 'secrets/**', 'credentials',
    'credentials.*', 'credentials/**', '.ssh/**', '*.pem', '*.key', '*.p12', 'id_rsa', 'id_ed25519']) {
    assert.ok(settings.permissions.deny.includes(`Read(//**/${path})`), path);
  }
  const fileGuard = settings.hooks.PreToolUse.find(h => h.hooks[0].command.includes('proteger-archivos'));
  for (const tool of ['Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit']) {
    assert.match(tool, new RegExp(fileGuard.matcher));
  }
  for (const name of ['revisor-a11y', 'auditor-rls']) {
    const agent = readFileSync(join(root, '.claude/agents', `${name}.md`), 'utf8');
    assert.match(agent, /^tools: Read, Grep, Glob$/m);
    assert.match(agent, /ROLE: SECONDARY_REVIEWER/);
    assert.match(agent, /\.ai\/REVIEW_PROTOCOL\.md/);
  }
});

test('Claude wrapper disables execution/MCP/customizations and validates delivery', () => {
  const temp = mkdtempSync(join(tmpdir(), 'avancecorp-review-test-'));
  try {
    const capture = join(temp, 'capture.json');
    writeFileSync(join(temp, 'claude'), `#!${process.execPath}\n` +
      `const fs = require('node:fs');\n` +
      `fs.writeFileSync(process.env.REVIEW_TEST_CAPTURE, JSON.stringify({args:process.argv.slice(2),input:fs.readFileSync(0,'utf8')}));\n` +
      `process.stdout.write(process.env.REVIEW_TEST_RESPONSE);\n` +
      `process.exitCode = Number(process.env.REVIEW_TEST_EXIT || 0);\n`, { mode: 0o700 });
    const run = (response, args = ['Concrete evidence: src/example.js:1'], extraEnv = {}, stdin = '') => spawnSync(
      join(root, 'scripts/claude-review'), args, {
        cwd: root, encoding: 'utf8', input: stdin, timeout: 5000,
        env: { ...process.env, PATH: `${temp}:${process.env.PATH}`,
          REVIEW_TEST_CAPTURE: capture, REVIEW_TEST_RESPONSE: response, ...extraEnv },
      });
    const delivered = (verdict) => JSON.stringify({
      is_error: false, subtype: 'success', result: `VERDICT:\n${verdict}\nSUMMARY:\nEvidence reviewed.`,
    });
    assert.equal(run(delivered('PASS')).status, 0);
    const { args, input } = JSON.parse(readFileSync(capture, 'utf8'));
    const value = (flag) => args[args.indexOf(flag) + 1];
    assert.equal(value('--tools'), '');
    assert.equal(value('--setting-sources'), '');
    assert.equal(value('--permission-mode'), 'plan');
    assert.equal(value('--permission-prompts'), 'none');
    assert.equal(value('--max-turns'), '5');
    assert.deepEqual(JSON.parse(value('--mcp-config')), { mcpServers: {} });
    for (const flag of ['--safe-mode', '--strict-mcp-config', '--no-session-persistence', '--disable-slash-commands']) assert.ok(args.includes(flag));
    assert.equal(value('--disallowedTools'), 'Bash,BashOutput,Read,Grep,Glob,Edit,MultiEdit,Write,NotebookEdit,NotebookRead,WebFetch,WebSearch,SlashCommand,Task,Agent,mcp__codex__codex,mcp__codex__codex-reply');
    assert.ok(input.includes('NO FINDING WITHOUT EVIDENCE'));
    assert.ok(input.includes('Concrete evidence: src/example.js:1'));
    // A delivered review may request changes; callers must inspect VERDICT.
    assert.equal(run(delivered('CHANGES_REQUESTED')).status, 0);
    assert.equal(run(delivered('BLOCK')).status, 0);
    assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_max_turns' })).status, 1);
    assert.equal(run('{malformed').status, 1);
    assert.equal(run(JSON.stringify({ is_error: false, subtype: 'success', result: 'Incomplete' })).status, 1);
    assert.equal(run(delivered('PASS | CHANGES_REQUESTED | BLOCK')).status, 1);
    assert.equal(run(delivered('PASS'), ['Evidence'], { REVIEW_TEST_EXIT: '3' }).status, 1);
    assert.equal(run(delivered('PASS'), ['   ']).status, 64);
    assert.equal(run(delivered('PASS'), ['Evidence'], { CLAUDE_REVIEW_MAX_TURNS: '9' }).status, 64);
    assert.equal(run(delivered('PASS'), ['Evidence'], { CLAUDE_REVIEW_MAX_TURNS: '0' }).status, 64);
    assert.equal(run(delivered('PASS'), ['Evidence'], { CLAUDE_REVIEW_MAX_TURNS: 'abc' }).status, 64);
    assert.equal(run(delivered('PASS'), [('line of evidence with spaces\n').repeat(2500)]).status, 0);
    assert.equal(run(delivered('PASS'), [], {}, 'stdin-only evidence').status, 0);
    assert.ok(JSON.parse(readFileSync(capture, 'utf8')).input.includes('stdin-only evidence'));
    assert.equal(run(delivered('PASS'), ['Review instruction'], {}, 'piped diff evidence').status, 0);
    const mixed = JSON.parse(readFileSync(capture, 'utf8')).input;
    assert.ok(mixed.includes('Review instruction') && mixed.includes('piped diff evidence'));
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
