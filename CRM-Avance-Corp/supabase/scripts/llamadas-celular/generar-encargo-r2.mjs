#!/usr/bin/env node
// Genera el encargo de Codex r2 (última ronda) sobre la corrección de «Llamadas desde el celular»: la quinta, F4-a,
// la Edge y lo que dependa de ellas, TRANSCRITO con número de línea desde el blob de git (LF): el revisor no tiene
// shell, red ni base. Molde: docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1.md.
// El encargo lo corre Miguel (`scripts/codex-review-mcp < <encargo>`); el envoltorio exige que empiece por
// «ROLE: SECONDARY_REVIEWER.» y traiga las cinco prohibiciones.
//
// Uso (después de commitear todo lo que se revisa):
//   node supabase/scripts/llamadas-celular/generar-encargo-r2.mjs [ref=HEAD]
// Escribe docs/encargos/<fecha>-codex-llamadas-celular-correccion-r2.md
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = fileURLToPath(new URL('../../../..', import.meta.url)); // raíz del repo
const SUB = 'CRM-Avance-Corp/';
const REF = process.argv[2] ?? 'HEAD';
const git = (...a) => execFileSync('git', ['-C', RAIZ, ...a], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const blob = (ruta) => git('show', `${REF}:${ruta}`);
const existe = (ruta) => { try { git('cat-file', '-e', `${REF}:${ruta}`); return true; } catch { return false; } };
const commit = git('rev-parse', '--short', REF).trim();
const hoy = new Date().toISOString().slice(0, 10);

function numerar(texto, desde = 1) {
  const lineas = texto.replace(/\n$/, '').split('\n');
  // Sin espacio final en las líneas vacías (git diff --check; revisión de Miguel en el #190).
  return lineas.map((l, i) => `${String(desde + i).padStart(4)}|${l ? ` ${l}` : ''}`).join('\n');
}
// raiz = la ruta es desde la raíz del repo (p. ej. .ai/REVIEW_PROTOCOL.md), no desde CRM-Avance-Corp/.
function archivo(ruta, nota = '', raiz = false) {
  const texto = blob(raiz ? ruta : SUB + ruta);
  const n = texto.replace(/\n$/, '').split('\n').length;
  return `## Archivo: ${ruta} (${n} líneas)${nota ? ` — ${nota}` : ''}\n\`\`\`\n${numerar(texto)}\n\`\`\`\n`;
}
function tramo(ruta, desde, hasta, nota) {
  const lineas = blob(SUB + ruta).split('\n').slice(desde - 1, hasta);
  return `## Tramo: ${ruta}:${desde}–${hasta} — ${nota}\n\`\`\`\n${numerar(lineas.join('\n'), desde)}\n\`\`\`\n`;
}
// Una función completa (de su «create … function <nombre>(» hasta «$function$;»), con sus números de línea reales.
function funcion(ruta, nombre, nota = '') {
  const lineas = blob(SUB + ruta).split('\n');
  const re = new RegExp(`^create (or replace )?function ${nombre.replace('.', '\\.')}\\(`, 'i');
  const i = lineas.findIndex((l) => re.test(l));
  if (i < 0) throw new Error(`no encuentro ${nombre} en ${ruta}`);
  let j = i;
  while (j < lineas.length && !/^\$(function|\$)\$;\s*$/i.test(lineas[j]) && !/^\$\$;\s*$/.test(lineas[j])) j++;
  return tramo(ruta, i + 1, j + 1, nota || nombre);
}

const M = 'supabase/migrations/';
const QUINTA = `${M}20261005143843_crm_llamadas_celular_correccion.sql`;
const F4A = `${M}20261005155914_crm_llamadas_celular_enlace_exacto.sql`;
const SEPTIMA = `${M}20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql`;
const DATOS = `${M}20261001145242_crm_llamadas_celular_datos.sql`;
const NUCLEO = `${M}20261001160219_crm_llamadas_celular_nucleo.sql`;
const INGESTA = `${M}20261001212258_crm_llamadas_celular_ingesta.sql`;
const ELEGIB = `${M}20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql`;
const V4 = `${M}20260921153654_crm_resultado_llamada_seguimiento.sql`;
const DESHACER = `${M}20260920005000_crm_gestion_diaria_resultado_llamada.sql`;
const DISPONIBILIDAD = `${M}20260906200000_crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado.sql`;

const historia = git('log', '--format=%h %s', `origin/main..${REF}`, '--', `${SUB}supabase`, `${SUB}docs/plans/llamadas-celular`)
  .trim().split('\n').filter(Boolean).map((l) => `- ${l}`).join('\n');

const partes = [];
partes.push(`ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (transcrito al final).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí (los
archivos llevan número de línea). Formato: VERDICT (PASS/BLOCK), SUMMARY, RESPUESTA a cada pregunta P1–P10 (sí/no +
por qué, con evidencia archivo:línea del texto transcrito), FINDINGS P0–P3 nuevos, RIESGOS y test gaps, NEXT ACTIONS,
CONFIDENCE. Pídete REFUTAR: busca lo que el diff no cierra o lo que rompe, no lo que está bien.

# Encargo: «Llamadas desde el celular» — DIFF de la corrección de F2 + F3 (quinta migración, F4-a, séptima y Edge) — LEVEL 3
(datos, permisos, autenticación por credencial de dispositivo, migraciones, concurrencia).
**Ronda 2 de máx. 2 (la última de la tarea).** La ronda 1 revisó el diseño (BLOCK, 6 P2 + 1 P3); esta revisa el
código. Generado el ${hoy} desde \`${commit}\` (rama \`crm/llamadas-quinta-migracion-20261005\`, PR #190) con
\`supabase/scripts/llamadas-celular/generar-encargo-r2.mjs\`. Lo corre Miguel con \`scripts/codex-review-mcp\`.

## Qué es
CRM interno (Supabase/Postgres 17). Esquema \`crm\` expuesto por PostgREST (puertas = funciones no trigger de \`crm\`),
núcleo en \`private\`, tablas con RLS sin policies ni grants. Un celular corporativo (Android + MacroDroid) avisa cada
llamada del analista: POST a la Edge \`crm-llamadas-ingesta\` (verify_jwt=false) con la clave del celular en
\`x-celular-credencial\`; la Edge llama con service_role a \`crm.ingerir_llamada_celular_servicio\`. El analista registra
el resultado con su sesión (encuesta v4 en producción; con F4-a, la v5). Siete migraciones SIN aplicar: las cuatro de
F2 + F3 (en \`main\`), la quinta (corrección), F4-a y la séptima (enlace sin ciclo con Deshacer). Se publican juntas con
la Edge.

## Commits que se revisan (sobre \`origin/main\`)
${historia || '- (sin commits nuevos respecto de origin/main en las rutas revisadas)'}

## Decisiones de negocio vigentes
**Miguel (03/10, PR #175):** (1) F2 + F3 se publican junto con el enlace exacto F4-a; (2) entrantes bloqueadas, la #14
después; (3) llamada a un lead de otro analista = número sin lead; (4) sin resultado → 30 días desde \`recibido_en\`,
registradas se conservan como historial; (5) la pista por tiempo de respuesta es riesgo aceptado por escrito; (6) se
retira la bandeja vieja; (7) leads sin dueño y descartados reutilizables son candidatos (por revisar; quien llamó no
la ve; le aparece a quien lo tome). Confirmaciones: al deshacer, el enlace pasa al resultado corregido; la regla
«resultado posterior a la llamada» solo vale para el enlace manual; #12 = «la respuesta, el cupo y el estado no delatan;
el tiempo es riesgo aceptado».
**Jhosep (05/10):** la fusión del plan v2 (#179) cuenta como el OK de Miguel, con la N1 según la recomendación (la salud
del celular sin \`envios_hoy\` ni \`ultimo_envio_en\`); en F4-a un enlace imposible NO impide guardar el resultado
(responde \`no_enlazado\` con su motivo) y una llamada ambigua no se une por el camino exacto; las reversas solo corren
antes de dar de alta celulares (respuesta al [P2] del agente de Miguel, abajo).

## Calibración: dentro del CRM, saber si un teléfono existe NO es secreto
«Nuevo lead» le dice a cualquier analista con sesión si un teléfono ya es de un lead (en bolsa, tomado por alguien,
en enfriamiento o reutilizable). La protección del #12 es frente a quien tiene la clave de un celular SIN sesión del
CRM (una macro exportada, un exempleado). Transcrito más abajo: \`app/src/lib/disponibilidad-lead.ts\` y la regla de la
base \`private.verificar_disponibilidad_lead_impl\`.

## Preguntas para el revisor
- **P1 (fallo 1, #12).** Con la recepción antes de buscar el lead, el contrato \`{resultado, mensaje}\` y el cupo gastado
  por todo inválido (también el JSON mal formado que la Edge reenvía con la carga en null), ¿queda algún observable
  —código HTTP, cuerpo, cupo, estado o salud visibles— que distinga un número de lead de uno sin lead, aparte del
  tiempo (riesgo aceptado, incluido el 503 por espera de candado)?
- **P2 (id, P2-2/P2-3 de tu r1).** ¿La forma \`C<n>-<10 dígitos>\`, la etiqueta de la asignación, la ventana
  [−30 días, +1 día] y la recepción de 32 días cierran el teléfono en el id, la etiqueta reutilizada y la reaceptación
  de un id viejo? ¿Algún borde con la purga, la rotación o el cierre?
- **P3 (§2 candidatos).** ¿La identidad temporal del dueño vuelve en todos los caminos (éxito, error, dentro del bloque
  que atrapa 22023)? ¿Las condiciones (b) «en bolsa» y (c) «reutilizable» reproducen las de
  \`verificar_disponibilidad_lead_impl\`? ¿El efecto aceptado de (c) —el antiguo dueño de un descartado reutilizable ve
  la llamada de otro analista hasta que alguien lo tome— abre algo más?
- **P4 (§3 candados, P2-4/P10).** Con los órdenes de asociar, enlazar y descartar (quinta), de la v5 y del cumplimiento
  de la intención en la ingesta (F4-a), de Deshacer, de la v4, de la purga y de rotar/cerrar: ¿hay un ciclo posible?
  ¿El 40001 cubre el cambio de lead? ¿Falta alguna revalidación tras los candados?
- **P5 (F4-a).** ¿La v5 compone la v4 sellada sin alterar su semántica (replay por operación, recibo, candado del
  lead)? ¿La intención y su cumplimiento pueden perder o duplicar un enlace, o unir un resultado a la llamada
  equivocada? ¿Guardar el resultado cuando el enlace es imposible deja algún estado incoherente?
- **P6 (§5 retención).** ¿La purga respeta: sin resolver (identificadas sin enlace y ambiguas) a 30 días desde
  \`recibido_en\`; registradas (con enlace, aunque deshechas) se conservan; descartadas por su plazo; recepciones e
  intenciones a 32 días? ¿Está bien cubierto el caso de un enlace concurrente con la purga (relectura de la fila)?
- **P7 (reversas, [P2] del agente de Miguel).** ¿La guarda «sin asignaciones (ni cerradas), estado, recepciones,
  llamadas, enlaces ni intenciones, bajo candado» basta y es atómica? ¿Alguna ruta borra asignaciones o estado?
- **P8 (Edge, P2-1 de tu r1).** ¿El contrato de transporte deja algún inválido sin gastar cupo, alguna respuesta que
  dependa de lo que pasó dentro de la base, o algún orden 401/413 que distinga más de lo aceptado?
- **P9 (lecturas).** Salud, bandeja, detalle y asignaciones: ¿alguna deja ver llamadas personales, llamadas de leads dados
  de baja o de otro equipo?
- **P10 (pruebas).** El banco reducido usa la v4 como DOBLE declarado. El bloque \`testLlamadasCelular\` del gate
  (transcrito) usa la v4 REAL y sesiones reales, pero todavía NO SE CORRIÓ. ¿Qué prueba mal o le falta antes de
  publicar? Riesgos que el PRIMARY no pudo descartar sin correrlo: \`tomar_lead_libre\` sobre un reutilizable (nunca
  corrió en el gate; con \`resolver_en_puertas\` encendida decide el juicio de reapertura), la v4 real sobre un lead
  creado por inserción de admin y el descarte vencido fechado fuera de banda en \`replica\`.

## Tu r1 (BLOCK, 6 P2 + 1 P3) → dónde se cierra en el código
| Hallazgo r1 | Dónde mirar |
| --- | --- |
| P2-1 La Edge no acompaña el arreglo | \`handler.ts\` (contrato de transporte) y las puertas de servicio de la quinta |
| P2-2 El sha256 no protege un teléfono | quinta: id \`C<n>-<10 dígitos>\`, ventana y etiqueta (\`private.llamada_celular_ingerir\`) |
| P2-3 Etiqueta e id reutilizados | quinta: unicidad por id, recepción de 32 días, ventana |
| P2-4 Candados incompletos | quinta: asociar, enlazar, descartar; F4-a: v5, \`llamada_celular_cumplir_intencion\`, ingesta |
| P2-5 Reloj adelantado | F4-a: \`llamada_celular_enlazar_exacto\` sin la regla de 10 minutos |
| P2-6 Sin barrera si falla la quinta | precondiciones (tablas vacías bajo candado) y reversas |
| P3-7 Rotar reinicia el cupo | documentado (estado por asignación; solo gerencia rota) |

## Revisión puntual del agente de Miguel (05/10, sobre \`22e46f5b\`): CHANGES_REQUESTED, [P2] reproducido
La reversa de la quinta solo miraba recepciones y llamadas; la purga retira las recepciones a los 32 días, así que tras
un aviso ignorado y su caducidad la reversa volvía a correr con claves vigentes. Corregido en \`260c0a4a\` con su opción
conservadora: las reversas de la quinta y de F4-a exigen bajo candado que no haya asignaciones (ni cerradas), estado,
recepciones ni llamadas (y en F4-a, tampoco enlaces ni intenciones). Regresión (aviso ignorado → purga real → claves
rotadas y cerradas → la reversa se niega) y un mutante por reversa.

## Segunda revisión del agente de Miguel (05/10 18:13 UTC, sobre \`53a72f17\`): CHANGES_REQUESTED, [P2] reproducido
- **[P2] Interbloqueo entre cumplir la intención y Deshacer.** La ingesta toma el lead y, al crear el enlace, la llave
  foránea pide el resultado FOR KEY SHARE; Deshacer (20260920005000:649 y 682) tiene el resultado FOR UPDATE y espera el
  lead → 40P01. Corregido en la **séptima** (\`20261005182227\`, transcrita): el resultado se toma FOR KEY SHARE NOWAIT al
  cumplir la intención y en la v5; si lo tiene otro, la intención se retira sin enlace (la llamada va a la pestaña) o la
  v5 responde \`no_enlazado\` / \`resultado_en_uso\`. Se atrapa SOLO \`lock_not_available\`. Decisión de Jhosep (05/10): no
  esperar (la alternativa era tomar el resultado antes que el lead en la ingesta). Solo Deshacer bloquea un resultado FOR
  UPDATE (comprobado en todas las migraciones); la actualización de la v4 (FOR NO KEY UPDATE) no choca con FOR KEY SHARE.
- **[P3] Edge:** un corte al leer el cuerpo ya devuelve 503 controlado (reintentable), sin tocar la base, con su prueba.
- **Encargo:** el protocolo se transcribe desde la raíz del repo y las líneas vacías no llevan espacio final.
- **P7** quedó resuelta en esa revisión; **P4** tenía un ciclo demostrado: es el [P2] de arriba.

## Verificación ejecutada por el PRIMARY (no la repites: no tienes shell)
- \`npm run test:llamadas:local\` (PostgreSQL 17, banco reducido con copias reales de auditoría, ámbito, canonización
  e idempotencia, y la v4 como doble declarado): pasadas de las cuatro (160), de la quinta (oráculo, reversa con huella
  exacta del catálogo, 41 mutantes, 9 carreras con dos sesiones + 4 mutantes de candados) y de F4-a (oráculo, reversa
  con huella exacta, 26 mutantes, 4 carreras), más la regresión del [P2] — todo en verde en el commit generado.
- Edge: \`handler.test.ts\` 15/15 y 15 mutantes cazados; receptor de pruebas del PC 10/10.
- Séptima (pasadas 13 y 14): huella, oráculos, reversa exacta; carreras con Deshacer PAUSADO entre sus dos candados (el
  aviso o el reintento de la v5 en medio, los dos órdenes, Deshacer revertido) y un control sin la séptima que reproduce
  el \`deadlock detected\` de la revisión; 4 mutantes cazados por la carrera y 1 por el postflight. Banco: 308/308. Edge:
  16/16 y 17 mutantes (el corte al leer el cuerpo incluido).
- Gate: bloque \`testLlamadasCelular\` cotejado a mano con las migraciones (firmas, códigos, mensajes y formas de
  respuesta); \`node --check\` y oxlint limpios. La limpieza entre corridas, probada en un Postgres local.
- NOT RUN: gate \`test-rls.mjs\` con el esquema de producción, advisors, la v4 real y \`banco/verificar-hallazgos.sql\`
  (los corre Miguel en su banco).
`);

partes.push(archivo('.ai/REVIEW_PROTOCOL.md', 'protocolo de revisión', true));
partes.push(archivo('docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md', 'el plan v2 que el código implementa'));
partes.push(archivo(QUINTA, 'la quinta (lo que se revisa)'));
partes.push(archivo(F4A, 'F4-a (lo que se revisa)'));
partes.push(archivo(SEPTIMA, 'la séptima: enlace sin ciclo con Deshacer (lo que se revisa)'));
partes.push(archivo('supabase/functions/crm-llamadas-ingesta/handler.ts', 'la Edge (lo que se revisa)'));
partes.push(archivo('supabase/functions/crm-llamadas-ingesta/index.ts'));
partes.push(tramo('supabase/scripts/llamadas-celular/reversa-correccion.sql', 1, 50, 'cabecera y guarda de la reversa de la quinta (el resto son los cuerpos de las cuatro, copiados con un guion desde el blob y comprobados con la huella del catálogo)'));
partes.push(tramo('supabase/scripts/llamadas-celular/reversa-enlace-exacto.sql', 1, 70, 'cabecera y guardas de la reversa de F4-a'));
partes.push(tramo('supabase/scripts/llamadas-celular/reversa-enlace-sin-ciclo.sql', 1, 25, 'cabecera y precondición de la reversa de la séptima (el resto: los dos cuerpos y COMMENT de F4-a, copiados con un guion)'));
partes.push(archivo(DATOS, 'tablas, candados y purga original de F2-b (la quinta los enmienda)'));
for (const [ruta, nombre] of [
  [NUCLEO, 'private.llamada_celular_formas'], [NUCLEO, 'private.llamada_celular_candidatos'],
  [NUCLEO, 'private.llamada_celular_elegible'], [NUCLEO, 'private.llamada_celular_atencion_efectiva'],
  [NUCLEO, 'private.llamadas_celular_actor'], [NUCLEO, 'private.llamada_celular_detalle'],
  [NUCLEO, 'private.celular_asignar'], [NUCLEO, 'private.celular_cerrar'], [NUCLEO, 'private.celular_rotar_credencial'],
  [NUCLEO, 'private.celulares_asignaciones_listar'], [NUCLEO, 'crm.llamada_celular_detalle_fn'],
  [NUCLEO, 'crm.asociar_llamada_celular'], [NUCLEO, 'crm.enlazar_llamada_celular'], [NUCLEO, 'crm.descartar_llamada_celular'],
  [INGESTA, 'private.llamadas_celular_bandeja'], [INGESTA, 'crm.llamadas_celular_bandeja_fn'], [INGESTA, 'crm.celulares_salud_fn'],
  [ELEGIB, 'private.llamada_celular_elegible_dueno'],
  [V4, 'private.llamada_registrar_v4'], [V4, 'crm.registrar_llamada_v4'],
  [DESHACER, 'crm.deshacer_resultado_llamada'],
]) partes.push(funcion(ruta, nombre, `${nombre} (dependencia sin cambios; de ${ruta.replace(M, '')})`));
partes.push(tramo(DISPONIBILIDAD, 3620, 3731, '«en bolsa» y «reutilizable» de private.verificar_disponibilidad_lead_impl (la regla de «Nuevo lead»)'));
partes.push(archivo('app/src/lib/disponibilidad-lead.ts', '«Nuevo lead» en la pantalla'));
partes.push(archivo('supabase/tests/llamadas-celular/oraculo-correccion.sql', 'oráculo de la quinta'));
partes.push(archivo('supabase/tests/llamadas-celular/oraculo-enlace-exacto.sql', 'oráculo de F4-a'));
if (existe(`${SUB}supabase/scripts/test-rls.mjs`)) {
  const gate = blob(`${SUB}supabase/scripts/test-rls.mjs`).split('\n');
  const i = gate.findIndex((l) => /^async function testLlamadasCelular\(/.test(l));
  if (i >= 0) {
    let k = i;
    while (k > 0 && /^\/\//.test(gate[k - 1])) k--; // con su comentario de cabecera
    let j = i + 1;
    while (j < gate.length && !/^}\s*$/.test(gate[j])) j++;
    partes.push(tramo('supabase/scripts/test-rls.mjs', k + 1, j + 1, 'bloque testLlamadasCelular del gate (SIN CORRER)'));
  }
}
if (existe(`${SUB}supabase/scripts/banco/limpiar-entre-corridas.sql`)) {
  partes.push(archivo('supabase/scripts/banco/limpiar-entre-corridas.sql', 'limpieza del banco entre corridas del gate'));
}
if (existe(`${SUB}docs/plans/llamadas-celular/PUBLICAR-F2-F3.md`)) {
  partes.push(archivo('docs/plans/llamadas-celular/PUBLICAR-F2-F3.md', 'guía de publicación'));
}

const destino = join(RAIZ, SUB, `docs/encargos/${hoy}-codex-llamadas-celular-correccion-r2.md`);
const salida = partes.join('\n');
writeFileSync(destino, salida);
console.log(`encargo r2 generado: ${destino} (${salida.split('\n').length} líneas, desde ${commit})`);
