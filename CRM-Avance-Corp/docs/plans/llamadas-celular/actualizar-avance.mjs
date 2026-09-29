// Regenera AVANCE.md y las casillas, estados y evidencias de PLAN.md a partir de estado.json.
// estado.json es el espejo del tablero vivo (https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M):
// Claude escribe ahí cada avance con evidencia y luego corre este script. Nadie edita PLAN.md a mano.
// Uso: node actualizar-avance.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const estado = JSON.parse(readFileSync(join(dir, 'estado.json'), 'utf8'));
const T = estado.tareas || {}, S = estado.subfases || {}, F = estado.fases || {};
const LABEL = { pendiente: 'pendiente', curso: 'en curso', hecha: 'hecha', bloqueada: 'bloqueada' };
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const derivado = (ok, tot) => (ok === 0 ? 'pendiente' : ok === tot ? 'hecha' : 'curso');
const done = (id) => !!(T[id] && T[id].done);
const cuenta = (ids) => ids.filter(done).length;

const lines = readFileSync(join(dir, 'PLAN.md'), 'utf8').split(/\r?\n/);

// 1) Estructura del plan: fase → subfases → tareas, leída de los IDs del propio PLAN.md.
const fases = [];
let f = null, s = null;
for (const l of lines) {
  let m;
  if ((m = l.match(/^## \d+\. (F\d) · (.+)$/))) { f = { codigo: m[1], titulo: m[2].trim(), subfases: [] }; fases.push(f); s = null; continue; }
  if (!f) continue;
  if (/^## /.test(l)) { f = null; s = null; continue; }
  if ((m = l.match(/^#{3,4} (F\d\.\d) · (.+)$/))) { s = { id: m[1], titulo: m[2].trim(), tareas: [] }; f.subfases.push(s); continue; }
  if ((m = l.match(/^- \[[ x]\] \*\*(F\d\.\d\.\d)\*\* /)) && s) s.tareas.push(m[1]);
}
const tareasDe = (fase) => fase.subfases.flatMap((x) => x.tareas);
const estadoSub = (sub) => (S[sub.id] && S[sub.id].estado) || derivado(cuenta(sub.tareas), sub.tareas.length);
const estadoFase = (fase) => (F[fase.codigo] && F[fase.codigo].estado) || derivado(cuenta(tareasDe(fase)), tareasDe(fase).length);

// 2) PLAN.md: casillas, líneas de estado, evidencias, seguimiento por fase y tabla de 5.1.
let curF = null, curS = null;
const out = lines.map((l) => {
  let m;
  if ((m = l.match(/^## \d+\. (F\d) · /))) { curF = fases.find((x) => x.codigo === m[1]) || null; curS = null; return l; }
  if (/^## /.test(l)) { curF = null; curS = null; return l; }
  if ((m = l.match(/^#{3,4} (F\d\.\d) · /)) && curF) { curS = curF.subfases.find((x) => x.id === m[1]) || null; return l; }
  if ((m = l.match(/^- \[[ x]\] \*\*(F\d\.\d\.\d)\*\* (.*)$/))) {
    const id = m[1], t = T[id] || {};
    const texto = m[2].replace(/ — (EN CURSO|BLOQUEADA|NO APLICA|NOT RUN)\b.*$/, '');
    if (t.done) return `- [x] **${id}** ${texto}`;
    const marca = t.estado === 'curso' ? 'EN CURSO' : t.estado === 'bloqueada' ? 'BLOQUEADA' : t.estado === 'na' ? 'NO APLICA' : t.estado === 'not_run' ? 'NOT RUN' : '';
    return `- [ ] **${id}** ${texto}${marca ? ` — ${marca}${t.nota ? `: ${t.nota}` : ''}` : ''}`;
  }
  if (/^\*\*Estado:\*\* .+ · \*\*Avance:\*\* \S+ · \*\*Responsable:\*\* /.test(l) && curS) {
    const so = S[curS.id] || {};
    return `**Estado:** ${LABEL[estadoSub(curS)]} · **Avance:** ${cuenta(curS.tareas)}/${curS.tareas.length} · **Responsable:** ${so.responsable || 'por asignar'}.`;
  }
  if (/^\*\*Evidencia \/ fecha de validación:\*\* /.test(l) && curS) {
    const so = S[curS.id] || {};
    return `**Evidencia / fecha de validación:** ${so.evidencia || 'pendiente'}.`;
  }
  if ((m = l.match(/^\*\*Seguimiento de (F\d):\*\* /))) {
    const fase = fases.find((x) => x.codigo === m[1]);
    if (!fase) return l;
    const fo = F[fase.codigo] || {};
    return `**Seguimiento de ${fase.codigo}:** ${cuenta(tareasDe(fase))}/${tareasDe(fase).length} tareas completadas · Estado: ${LABEL[estadoFase(fase)]} · Responsable nominal: ${fo.responsable || 'por asignar'}.`;
  }
  if ((m = l.match(/^\| (F\d) · ([^|]+)\| (\d+) \| \d+\/\d+ \| [^|]+\| (.*)\|$/))) {
    const fase = fases.find((x) => x.codigo === m[1]);
    if (!fase) return l;
    return `| ${m[1]} · ${m[2]}| ${m[3]} | ${cuenta(tareasDe(fase))}/${tareasDe(fase).length} | ${cap(LABEL[estadoFase(fase)])} | ${m[4]}|`;
  }
  return l;
});
writeFileSync(join(dir, 'PLAN.md'), out.join('\n'));

// 3) AVANCE.md: el resumen que se lee en un minuto.
const totalTareas = fases.reduce((n, x) => n + tareasDe(x).length, 0);
const totalHechas = fases.reduce((n, x) => n + cuenta(tareasDe(x)), 0);
const fasesHechas = fases.filter((x) => estadoFase(x) === 'hecha').length;
const fechaLima = (iso) => {
  const d = new Date(iso || '');
  return isNaN(d.getTime()) ? '' : d.toLocaleString('es-PE', { timeZone: 'America/Lima', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
};
const A = [];
A.push('# Avance — Llamadas desde el celular al CRM');
A.push('');
A.push(`Actualizado: ${fechaLima(estado.actualizado)} (hora de Lima). Generado por \`actualizar-avance.mjs\` desde \`estado.json\`; no se edita a mano.`);
A.push('');
A.push('Tablero vivo (el que vale, se actualiza al instante): https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M · Plan completo: `PLAN.md` en esta carpeta.');
A.push('');
if (estado.meta && estado.meta.novedad) { A.push(`**Lo último:** ${estado.meta.novedad}`); A.push(''); }
A.push(`**Total:** ${totalHechas} de ${totalTareas} tareas · ${fasesHechas} de ${fases.length} fases hechas.`);
A.push('');
A.push('| Fase | Tareas | Estado | Subfases hechas |');
A.push('| --- | --- | --- | --- |');
for (const fase of fases) {
  const subHechas = fase.subfases.filter((x) => estadoSub(x) === 'hecha').length;
  A.push(`| ${fase.codigo} · ${fase.titulo} | ${cuenta(tareasDe(fase))}/${tareasDe(fase).length} | ${cap(LABEL[estadoFase(fase)])} | ${subHechas}/${fase.subfases.length} |`);
}
A.push('');
A.push('## Detalle por subfase');
for (const fase of fases) {
  A.push('');
  const fo = F[fase.codigo] || {};
  A.push(`### ${fase.codigo} · ${fase.titulo} — ${cuenta(tareasDe(fase))}/${tareasDe(fase).length} · ${LABEL[estadoFase(fase)]}${fo.evidencia ? ` · ${fo.evidencia}` : ''}`);
  for (const sub of fase.subfases) {
    const so = S[sub.id] || {};
    const partes = [`${cuenta(sub.tareas)}/${sub.tareas.length}`, LABEL[estadoSub(sub)], `Responsable: ${so.responsable || 'por asignar'}`];
    if (so.nota) partes.push(so.nota);
    if (so.evidencia) partes.push(`Evidencia: ${so.evidencia}`);
    A.push(`- **${sub.id} · ${sub.titulo}** — ${partes.join(' · ')}`);
    for (const id of sub.tareas) {
      const t = T[id] || {};
      if (t.done || t.estado) A.push(`    - ${t.done ? '✓' : t.estado === 'bloqueada' ? '✕' : '◐'} ${id}${t.nota ? ` — ${t.nota}` : ''}${t.at ? ` (${fechaLima(t.at)})` : ''}`);
    }
  }
}
A.push('');
A.push('## Últimos cambios');
A.push('');
const cambios = (estado.cambios || []).slice().sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 15);
if (!cambios.length) A.push('- Sin cambios registrados.');
for (const c of cambios) A.push(`- ${fechaLima(c.at)} · ${c.texto}`);
A.push('');
writeFileSync(join(dir, 'AVANCE.md'), A.join('\n'));
console.log(`PLAN.md y AVANCE.md actualizados: ${totalHechas}/${totalTareas} tareas, ${fasesHechas}/${fases.length} fases hechas.`);
