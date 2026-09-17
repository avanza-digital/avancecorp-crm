// Análisis estático del front del CRM: pantalla -> símbolos -> llamadas al servidor.
// Uso: node analyze-front.mjs <app/src> <salida.json>
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const SRC = path.resolve(process.argv[2])
const OUT = process.argv[3]
const require = createRequire(path.join(SRC, '..', 'package.json'))
const ts = require('typescript')

const SKIP_RE = /(\.test\.|\.spec\.|\/test\/|\/prototypes\/|\.d\.ts$|\.fixture\.|\.stories\.)/
const rel = (f) => path.relative(SRC, f)
// Archivos cuyo contenido se indexa también en ámbitos anidados (proveedores con objetos de API construidos dentro del componente)
const NESTED_SCOPE_FILES = new Set(['lib/store.tsx'])
// hook de contexto -> (archivo proveedor, prefijo del objeto cuyas propiedades expone)
const PROVIDER_MAP = {
  'lib/store-context.ts#useCRMData': ['lib/store.tsx', 'api.'],
  'lib/store-context.ts#usePanelesActions': ['lib/store.tsx', 'panelActions.'],
  'lib/store-context.ts#usePanelesState': ['lib/store.tsx', 'panelState.'],
  'lib/store-context.ts#useStoreEstado': ['lib/store.tsx', 'estado.'],
}
// Funciones envoltorio cuyo literal en un argumento decide la tabla/RPC real (evita el <dinámico>)
const WRAPPERS = { leerListadoCarteraCompleto: { arg: 0, kind: 'table', schema: 'crm' }, ejecutarComandoSla: { arg: 1, kind: 'rpc', schema: 'crm' } }
const BOUNDARY = new Set(['lib/store.tsx#StoreProvider'])
const SHELL_FILES = new Set(['App.tsx', 'main.tsx', 'lib/auth.tsx', 'lib/auth-context.ts', 'lib/alertas-provider.tsx', 'lib/respuestas-tasa-context.ts', 'components/app/respuestas-tasa.tsx', 'lib/notificaciones-tasa.ts'].map((f) => path.join(SRC, f)))

const files = []
;(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name)
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p) }
    else if (/\.(ts|tsx)$/.test(e.name) && !SKIP_RE.test(p)) files.push(p)
  }
})(SRC)

function resolveModule(fromFile, spec) {
  let base
  if (spec.startsWith('@/')) base = path.join(SRC, spec.slice(2))
  else if (spec.startsWith('.')) base = path.resolve(path.dirname(fromFile), spec)
  else return null
  for (const c of [base, base + '.ts', base + '.tsx', path.join(base, 'index.ts'), path.join(base, 'index.tsx')]) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) return c
  }
  return null
}

const modules = new Map()

function literalOf(expr, topConsts) {
  if (!expr) return null
  if (ts.isStringLiteral(expr) || ts.isNoSubstitutionTemplateLiteral(expr)) return expr.text
  if (ts.isIdentifier(expr) && topConsts.has(expr.text)) return topConsts.get(expr.text)
  if (ts.isTemplateExpression(expr)) return expr.head.text + expr.templateSpans.map((s) => '${…}' + s.literal.text).join('')
  return null
}

function chainInfo(callee) {
  let schema = null, storage = false, root = null
  let e = callee.expression
  while (e) {
    if (ts.isCallExpression(e)) {
      if (ts.isPropertyAccessExpression(e.expression)) {
        const n = e.expression.name.text
        if (n === 'schema' && e.arguments[0] && ts.isStringLiteral(e.arguments[0])) schema = e.arguments[0].text
        e = e.expression.expression
        continue
      }
      if (ts.isIdentifier(e.expression)) { root = e.expression.text; break }
      e = e.expression; continue
    }
    if (ts.isPropertyAccessExpression(e)) {
      if (e.name.text === 'storage') storage = true
      e = e.expression; continue
    }
    if (ts.isIdentifier(e)) { root = e.text; break }
    if (ts.isAwaitExpression(e) || ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e)) { e = e.expression; continue }
    break
  }
  return { schema, storage, root }
}

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8')
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, file.endsWith('x') ? ts.ScriptKind.TSX : ts.ScriptKind.TS)
  const mod = { sf, symbols: new Map(), imports: new Map(), exports: new Map(), star: [], topConsts: new Map() }
  modules.set(file, mod)
  for (const st of sf.statements) {
    if (ts.isVariableStatement(st)) for (const d of st.declarationList.declarations) {
      if (ts.isIdentifier(d.name) && d.initializer && (ts.isStringLiteral(d.initializer) || ts.isNoSubstitutionTemplateLiteral(d.initializer))) mod.topConsts.set(d.name.text, d.initializer.text)
    }
  }
  const declare = (name, node, exported) => {
    if (mod.symbols.has(name)) return
    const sym = { refs: new Set(), calls: [], line: sf.getLineAndCharacterOfPosition(node.getStart()).line + 1 }
    mod.symbols.set(name, sym)
    if (exported) mod.exports.set(name, { local: name })
    collect(node, sym)
  }
  function collect(node, sym) {
    const aliases = new Map() // variable local -> hook (const d = useX())
    const visit = (n) => {
      if (ts.isTypeNode(n) || ts.isTypeAliasDeclaration(n) || ts.isInterfaceDeclaration(n)) return
      if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) return
      if (ts.isVariableDeclaration(n) && n.initializer && ts.isCallExpression(n.initializer) && ts.isIdentifier(n.initializer.expression)) {
        const hook = n.initializer.expression.text
        if (ts.isObjectBindingPattern(n.name)) {
          for (const el of n.name.elements) if (ts.isBindingElement(el)) { const key = el.propertyName && ts.isIdentifier(el.propertyName) ? el.propertyName.text : (ts.isIdentifier(el.name) ? el.name.text : null); if (key) sym.refs.add(hook + '#' + key) }
        } else if (ts.isIdentifier(n.name)) aliases.set(n.name.text, hook)
      }
      if (ts.isIdentifier(n)) {
        const p = n.parent
        const isPropName = (ts.isPropertyAccessExpression(p) && p.name === n) || (ts.isPropertyAssignment(p) && p.name === n) || (ts.isMethodDeclaration(p) && p.name === n) || (ts.isPropertyDeclaration(p) && p.name === n) || (ts.isJsxAttribute(p) && p.name === n) || (ts.isBindingElement(p) && p.propertyName === n) || (ts.isEnumMember(p) && p.name === n) || (ts.isPropertySignature(p) && p.name === n) || (ts.isParameter(p) && p.name === n) || (ts.isVariableDeclaration(p) && p.name === n) || (ts.isFunctionDeclaration(p) && p.name === n) || ts.isTypeReferenceNode(p)
        if (!isPropName) sym.refs.add(n.text)
        if (ts.isPropertyAccessExpression(p) && p.expression === n) {
          if (mod.imports.get(n.text)?.name === '*') sym.refs.add(n.text + '.' + p.name.text)
          if (aliases.has(n.text)) sym.refs.add(aliases.get(n.text) + '#' + p.name.text)
        }
        return
      }
      if (ts.isCallExpression(n) && n.expression.kind === ts.SyntaxKind.ImportKeyword && n.arguments[0] && ts.isStringLiteral(n.arguments[0])) {
        const t = resolveModule(file, n.arguments[0].text)
        if (t) sym.refs.add('@dyn:' + t)
      }
      if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && WRAPPERS[n.expression.text]) {
        const w = WRAPPERS[n.expression.text]
        const lit = literalOf(n.arguments[w.arg], mod.topConsts)
        if (lit != null) sym.calls.push({ kind: w.kind, name: lit, schema: w.schema, line: sf.getLineAndCharacterOfPosition(n.getStart()).line + 1, via: 'wrapper:' + n.expression.text })
      }
      if (ts.isCallExpression(n) && ts.isPropertyAccessExpression(n.expression)) {
        const name = n.expression.name.text
        if (name === 'rpc' || name === 'from' || name === 'invoke') {
          const lit = literalOf(n.arguments[0], mod.topConsts)
          const info = chainInfo(n.expression)
          const line = sf.getLineAndCharacterOfPosition(n.getStart()).line + 1
          if (lit != null) {
            if (name === 'invoke') sym.calls.push({ kind: 'edge', name: lit, line })
            else if (info.storage) sym.calls.push({ kind: 'storage', name: lit, line })
            else if (name === 'from' && !/^[a-z0-9_]+$/.test(lit)) { /* gsap .from('[data-x]') */ }
            else sym.calls.push({ kind: name === 'rpc' ? 'rpc' : 'table', name: lit, schema: info.schema, root: info.root, line })
          } else if (name !== 'from' || (info.root && /^(cliente|sb|supabase|clienteSupabase|consulta|admin|userClient|adminClient)$/.test(info.root))) {
            sym.calls.push({ kind: name, name: '<dinámico>', line, raw: n.arguments[0] ? n.arguments[0].getText().slice(0, 80) : '' })
          }
        }
      }
      ts.forEachChild(n, visit)
    }
    ts.forEachChild(node, visit)
    const t = node.getText()
    for (const m of t.matchAll(/functions\/v1\/([a-z0-9-]+)/g)) sym.calls.push({ kind: 'edge', name: m[1], line: sym.line, via: 'url' })
    for (const m of t.matchAll(/rest\/v1\/(rpc\/)?([a-z0-9_]+)/g)) sym.calls.push({ kind: m[1] ? 'rpc' : 'table', name: m[2], schema: null, line: sym.line, via: 'url' })
  }
  for (const st of sf.statements) {
    if (ts.isImportDeclaration(st)) {
      const spec = st.moduleSpecifier.text
      const target = resolveModule(file, spec)
      if (!target || !st.importClause) continue
      const ic = st.importClause
      if (ic.isTypeOnly) continue
      if (ic.name) mod.imports.set(ic.name.text, { file: target, name: 'default' })
      if (ic.namedBindings) {
        if (ts.isNamespaceImport(ic.namedBindings)) mod.imports.set(ic.namedBindings.name.text, { file: target, name: '*' })
        else for (const el of ic.namedBindings.elements) { if (el.isTypeOnly) continue; mod.imports.set(el.name.text, { file: target, name: (el.propertyName ?? el.name).text }) }
      }
      continue
    }
    if (ts.isExportDeclaration(st)) {
      const target = st.moduleSpecifier ? resolveModule(file, st.moduleSpecifier.text) : null
      if (st.exportClause && ts.isNamedExports(st.exportClause)) {
        for (const el of st.exportClause.elements) {
          const exported = el.name.text, local = (el.propertyName ?? el.name).text
          mod.exports.set(exported, target ? { file: target, name: local } : { local })
        }
      } else if (!st.exportClause && target) mod.star.push(target)
      continue
    }
    const mods = ts.canHaveModifiers(st) ? ts.getModifiers(st) : undefined
    const exported = !!mods?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)
    const isDefault = !!mods?.some((m) => m.kind === ts.SyntaxKind.DefaultKeyword)
    if (ts.isFunctionDeclaration(st) && st.name) { declare(st.name.text, st, exported); if (isDefault) mod.exports.set('default', { local: st.name.text }) }
    else if (ts.isClassDeclaration(st) && st.name) { declare(st.name.text, st, exported); if (isDefault) mod.exports.set('default', { local: st.name.text }) }
    else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        if (ts.isIdentifier(d.name)) declare(d.name.text, d, exported)
        else {
          const names = []
          const dig = (b) => { if (ts.isIdentifier(b.name)) names.push(b.name.text); else for (const e of b.name.elements) if (ts.isBindingElement(e)) dig(e) }
          for (const e of d.name.elements) if (ts.isBindingElement(e)) dig(e)
          for (const nm of names) declare(nm, d, exported)
        }
      }
    }
    else if (ts.isExportAssignment(st)) { declare('default', st, true) }
    else if (ts.isExpressionStatement(st) || ts.isIfStatement(st)) { declare('<top:' + st.getStart() + '>', st, false) }
  }
  // Ámbitos anidados (proveedor del store): cada declaración interna es un símbolo; los objetos literales exponen `nombre.<prop>`
  if (NESTED_SCOPE_FILES.has(rel(file))) {
    const objectOf = (init) => {
      if (!init) return null
      if (ts.isObjectLiteralExpression(init)) return init
      if (ts.isCallExpression(init) && ts.isIdentifier(init.expression) && init.expression.text === 'useMemo' && init.arguments[0] && ts.isArrowFunction(init.arguments[0])) {
        const body = init.arguments[0].body
        if (ts.isParenthesizedExpression(body) && ts.isObjectLiteralExpression(body.expression)) return body.expression
        if (ts.isObjectLiteralExpression(body)) return body
        if (ts.isBlock(body)) for (const s of body.statements) if (ts.isReturnStatement(s) && s.expression && ts.isObjectLiteralExpression(s.expression)) return s.expression
      }
      return null
    }
    const deep = (n) => {
      if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name)) {
        declare(n.name.text, n, false)
        const obj = objectOf(n.initializer)
        if (obj) for (const prop of obj.properties) {
          const key = prop.name && ts.isIdentifier(prop.name) ? prop.name.text : null
          if (!key) continue
          const nm = n.name.text + '.' + key
          if (ts.isShorthandPropertyAssignment(prop)) { const s = { refs: new Set([key]), calls: [], line: sf.getLineAndCharacterOfPosition(prop.getStart()).line + 1 }; mod.symbols.set(nm, s) }
          else declare(nm, prop, false)
        }
      } else if (ts.isFunctionDeclaration(n) && n.name) declare(n.name.text, n, false)
      else if (ts.isExpressionStatement(n) && ts.isCallExpression(n.expression) && ts.isIdentifier(n.expression.expression) && /^use(Layout)?Effect$/.test(n.expression.expression.text)) declare('<effect:' + (sf.getLineAndCharacterOfPosition(n.getStart()).line + 1) + '>', n, false)
      ts.forEachChild(n, deep)
    }
    ts.forEachChild(sf, deep)
  }
}

function resolveExport(file, name, seen = new Set()) {
  const key = file + '#' + name
  if (seen.has(key)) return null
  seen.add(key)
  const mod = modules.get(file)
  if (!mod) return null
  const ex = mod.exports.get(name)
  if (ex) { if (ex.local) return { file, name: ex.local }; return resolveExport(ex.file, ex.name, seen) }
  for (const s of mod.star) { const r = resolveExport(s, name, seen); if (r) return r }
  return null
}

function resolveLocal(mod, file, r) {
  if (mod.symbols.has(r)) return { file, name: r }
  const imp = mod.imports.get(r)
  if (imp && imp.name !== '*') return resolveExport(imp.file, imp.name)
  return null
}

function neighbors(file, symName) {
  const mod = modules.get(file)
  const sym = mod?.symbols.get(symName)
  if (!sym) return []
  const out = []
  for (const r of sym.refs) {
    if (r.startsWith('@dyn:')) {
      const m = modules.get(r.slice(5))
      if (m) for (const ex of m.exports.keys()) { const t = resolveExport(r.slice(5), ex); if (t) out.push(t) }
      continue
    }
    if (r.includes('#')) {
      const [hook, key] = r.split('#')
      const h = resolveLocal(mod, file, hook)
      if (!h) continue
      const pm = PROVIDER_MAP[rel(h.file) + '#' + h.name]
      if (pm) { const pf = path.join(SRC, pm[0]); if (modules.get(pf)?.symbols.has(pm[1] + key)) out.push({ file: pf, name: pm[1] + key }) }
      continue
    }
    if (r.includes('.')) {
      const [ns, member] = r.split('.')
      const imp = mod.imports.get(ns)
      if (imp) { const t = resolveExport(imp.file, member); if (t) out.push(t) }
      continue
    }
    if (r === symName) continue
    const t = resolveLocal(mod, file, r)
    if (t) out.push(t)
  }
  return out
}

function bfs(roots, stopAtShell) {
  const seen = new Set(), calls = [], queue = [...roots]
  while (queue.length) {
    const { file, name } = queue.shift()
    const key = file + '#' + name
    if (seen.has(key)) continue
    seen.add(key)
    if (stopAtShell && SHELL_FILES.has(file)) continue
    if (BOUNDARY.has(rel(file) + '#' + name)) continue
    const sym = modules.get(file)?.symbols.get(name)
    if (!sym) continue
    for (const c of sym.calls) calls.push({ ...c, file: rel(file), symbol: name })
    for (const nb of neighbors(file, name)) queue.push(nb)
  }
  const uniq = new Map()
  for (const c of calls) { const k = [c.kind, c.schema ?? '', c.name, c.file, c.line].join('|'); if (!uniq.has(k)) uniq.set(k, c) }
  return { symbols: seen.size, calls: [...uniq.values()] }
}

const pantallas = JSON.parse(fs.readFileSync(path.join(path.dirname(OUT), 'pantallas.json'), 'utf8'))
const result = { pantallas: [], shell: null, dinamicos: [], simbolosStore: modules.get(path.join(SRC, 'lib/store.tsx'))?.symbols.size }
for (const p of pantallas) {
  const roots = p.roots.map((r) => { const f = path.join(SRC, r.file); return resolveExport(f, r.name) ?? { file: f, name: r.name } })
  const r = bfs(roots, true)
  result.pantallas.push({ id: p.id, titulo: p.titulo, roots: p.roots, simbolos: r.symbols, calls: r.calls })
}
const shellRoots = []
for (const f of SHELL_FILES) { const m = modules.get(f); if (m) for (const s of m.symbols.keys()) shellRoots.push({ file: f, name: s }) }
{ const sm = modules.get(path.join(SRC, 'lib/store.tsx')); if (sm) for (const s of sm.symbols.keys()) if (s.startsWith('<effect:') || s.startsWith('<top:')) shellRoots.push({ file: path.join(SRC, 'lib/store.tsx'), name: s }) }
result.shell = bfs(shellRoots, false)
for (const [f, m] of modules) for (const [s, sym] of m.symbols) for (const c of sym.calls) if (c.name === '<dinámico>') result.dinamicos.push({ file: rel(f), symbol: s, ...c })
// Inventario total de llamadas del front (para contrastar con el grep)
const todas = new Map()
for (const [f, m] of modules) for (const [s, sym] of m.symbols) for (const c of sym.calls) { const k = c.kind + ':' + (c.schema ?? '') + ':' + c.name; todas.set(k, (todas.get(k) ?? 0) + 1) }
result.inventario = [...todas.keys()].sort()
fs.writeFileSync(OUT, JSON.stringify(result, null, 1))
console.log('archivos', files.length, 'pantallas', result.pantallas.length, 'shell calls', result.shell.calls.length, 'dinámicos', result.dinamicos.length, 'símbolos store', result.simbolosStore, 'inventario', result.inventario.length)
for (const p of result.pantallas) console.log(p.id.padEnd(22), 'símbolos', String(p.simbolos).padStart(4), 'llamadas', String(p.calls.length).padStart(3), [...new Set(p.calls.map((c) => c.kind + ':' + (c.schema ?? '-') + ':' + c.name))].slice(0, 6).join(' '))
