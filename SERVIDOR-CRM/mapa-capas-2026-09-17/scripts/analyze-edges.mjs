// Referencias SQL dentro de las Edge Functions (Deno/TS): rpc y tablas, con esquema resuelto por cadena o por createClient({db:{schema}})
// Uso: node analyze-edges.mjs <salida.json> <dir1> <dir2> ...
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'
const require = createRequire('/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/package.json')
const ts = require('typescript')
const OUT = process.argv[2]
const DIRS = process.argv.slice(3)
const result = {}
for (const dir of DIRS) {
  for (const fn of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!fn.isDirectory() || fn.name.startsWith('_')) continue
    const files = []
    ;(function walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p) } else if (/\.(ts|mjs|js)$/.test(e.name) && !/\.test\.|pdfmake|vfs-fonts|_render-muestra/.test(e.name)) files.push(p) } })(path.join(dir, fn.name))
    const calls = []
    for (const file of files) {
      const text = fs.readFileSync(file, 'utf8')
      const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
      const consts = new Map()
      const defSchema = /db:\s*\{\s*schema:\s*["']([a-z]+)["']/.exec(text)?.[1] ?? 'public'
      for (const st of sf.statements) if (ts.isVariableStatement(st)) for (const d of st.declarationList.declarations) if (ts.isIdentifier(d.name) && d.initializer && ts.isStringLiteral(d.initializer)) consts.set(d.name.text, d.initializer.text)
      const lit = (e) => !e ? null : (ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)) ? e.text : (ts.isIdentifier(e) && consts.has(e.text)) ? consts.get(e.text) : null
      const chain = (callee) => { let schema = null, storage = false; let e = callee.expression; while (e) { if (ts.isCallExpression(e)) { if (ts.isPropertyAccessExpression(e.expression)) { if (e.expression.name.text === 'schema' && e.arguments[0] && ts.isStringLiteral(e.arguments[0])) schema = e.arguments[0].text; e = e.expression.expression; continue } break } if (ts.isPropertyAccessExpression(e)) { if (e.name.text === 'storage') storage = true; e = e.expression; continue } if (ts.isAwaitExpression(e) || ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e)) { e = e.expression; continue } break } return { schema, storage } }
      const visit = (n) => {
        if (ts.isCallExpression(n)) {
          const line = sf.getLineAndCharacterOfPosition(n.getStart()).line + 1
          if (ts.isPropertyAccessExpression(n.expression) && ['rpc', 'from'].includes(n.expression.name.text)) {
            const name = n.expression.name.text, l = lit(n.arguments[0]), c = chain(n.expression)
            if (l != null) { if (c.storage) calls.push({ kind: 'storage', name: l, file: path.basename(file), line }); else if (/^[a-z0-9_]+$/.test(l)) calls.push({ kind: name === 'rpc' ? 'rpc' : 'table', schema: c.schema ?? defSchema, name: l, file: path.basename(file), line }) }
            else calls.push({ kind: name, name: '<dinámico>', raw: n.arguments[0]?.getText().slice(0, 60), file: path.basename(file), line })
          }
          if (ts.isIdentifier(n.expression) && n.expression.text === 'rpc') { const l = lit(n.arguments[0]); if (l != null) calls.push({ kind: 'rpc', schema: 'crm', name: l, file: path.basename(file), line, via: 'wrapper rpc()' }) }
        }
        ts.forEachChild(n, visit)
      }
      visit(sf)
      for (const m of text.matchAll(/functions\/v1\/([a-z0-9-]+)/g)) calls.push({ kind: 'edge', name: m[1], file: path.basename(file), line: 0 })
      for (const m of text.matchAll(/rest\/v1\/(rpc\/)?([a-z0-9_]+)/g)) calls.push({ kind: m[1] ? 'rpc' : 'table', schema: null, name: m[2], file: path.basename(file), line: 0, via: 'url' })
    }
    const uniq = new Map(); for (const c of calls) { const k = [c.kind, c.schema ?? '', c.name].join('|'); if (!uniq.has(k)) uniq.set(k, { ...c, veces: 0 }); uniq.get(k).veces++ }
    result[fn.name] = { dir: path.relative('/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop', path.join(dir, fn.name)), archivos: files.length, calls: [...uniq.values()] }
  }
}
fs.writeFileSync(OUT, JSON.stringify(result, null, 1))
for (const [k, v] of Object.entries(result)) console.log(k.padEnd(26), v.calls.map((c) => c.kind + ':' + (c.schema ?? '-') + ':' + c.name).join(' '))
