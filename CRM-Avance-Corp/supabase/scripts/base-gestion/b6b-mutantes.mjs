// B6b · mutantes de la suite b6b-vetados.sql: cada uno neutraliza UNA defensa de la migración 20261004045038 (o del
// resumen que la envuelve) y la suite tiene que FALLAR en el caso que la prueba. Si un mutante sobrevive, esa defensa NO
// está probada. Todo corre en la transacción de la suite, que termina en ROLLBACK: el banco no cambia.
// Solo apunta a un banco LOCAL (127.0.0.1) con B6b aplicada y los actores de seed:demo; no acepta URL ni credenciales
// (la contraseña es la del Postgres local de Docker, PGPASSWORD; por defecto «postgres»).
// Uso: node supabase/scripts/base-gestion/b6b-mutantes.mjs --puerto 58122 [--solo-suite]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b6b-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)') is not null and to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)') is not null)::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B6b aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b6b-vetados.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004045038_crm_base_gestion_ver_vetados.sql', AQUI), 'utf8');
const b3c = readFileSync(new URL('../../migrations/20261003162300_crm_base_gestion_conteos_fuera_del_censo.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (texto, inicio) => {
  const i = texto.indexOf(inicio);
  if (i < 0 || texto.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = texto.indexOf('$function$;', texto.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return texto.slice(i, j).replace(/^create (or replace )?function/, 'create or replace function');
};
const FUENTES = {
  obtener: bloque(migracion, 'create function crm.obtener_base_gestion('),
  detalle: bloque(migracion, 'create function crm.base_gestion_resumen_detalle('),
  resumen: bloque(b3c, 'create or replace function crm.base_gestion_resumen()'),
};

// El CTE de la marca de r1 (ancla por hora + holgura de postventa), para el mutante «vuelve la regla por hora».
const MARCA_R1 = "  marca as (\n    -- B6b: cuándo, por qué y quién marcó «No contactar»: la ÚLTIMA actividad del veto del propio lead, si es un «marcar» del\n    -- periodo de veto VIGENTE de su persona (marcar/levantar cambian todos los leads de la persona y escriben la nota en uno\n    -- solo). NULL si lo último fue «levantar», si no hay nota propia o si es de un periodo anterior. La postventa guarda el\n    -- motivo en el detalle («No contactar: …») y fija no_contactar_en con clock_timestamp(): más tarde que el now() de su nota.\n    select b.id as lead_id, x.creado_en, x.motivo, x.creado_por\n    from base b\n    cross join lateral (\n      select a.creado_en, a.metadata->>'accion' as accion, a.creado_por,\n             coalesce(a.metadata->>'motivo',\n                      case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo,\n             a.metadata ? 'postventa_gestion_id' as postventa\n        from crm.actividades a\n       where a.lead_id = b.id and a.metadata->>'evento' = 'no_contactar'\n       order by a.creado_en desc, a.id desc\n       limit 1\n    ) x\n    cross join lateral (\n      -- La persona del lead como la resuelven marcar/levantar: el enlace o, si no hay, el puente (canónica).\n      select coalesce(b.inversionista_id,\n                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il\n                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1)) as id\n    ) pe\n    left join crm.inversionistas i on i.id = pe.id\n    where b.no_contactar and x.accion = 'marcar'\n      and (pe.id is null                                                    -- residuo: sin enlace ni puente, manda la nota propia\n           or i.no_contactar is not true or i.no_contactar_en is null       -- la persona no está vetada: el veto es solo del lead\n           or x.creado_en >= i.no_contactar_en                              -- la nota es del periodo de veto vigente\n           or (x.postventa and x.creado_en >= i.no_contactar_en - interval '1 minute'))  -- postventa: clock_timestamp() vs now()\n  )\n";
// El CTE vigente, leído del archivo de la migración (así el mutante no se queda viejo si la migración cambia).
const MARCA_R2 = migracion.slice(migracion.indexOf('  marca as (\n'), migracion.indexOf('  )\n', migracion.indexOf('nada de otro equipo')) + '  )\n'.length);
const MUTANTES = [
  { nombre: 'quitar el 42501 de los vetados', objeto: 'obtener', buscar: "if v_vetados and (v_rol in ('supervisor', 'gerencia')) is not true then", poner: 'if false then', cae: /^V1 pide los vetados → 42501$/ },
  { nombre: 'quitar el filtro de vetados', objeto: 'obtener', buscar: "and (not l.no_contactar or v_vetados)", poner: 'and true', cae: /^V1: false = B5$/ },
  { nombre: 'el resumen cuenta vetados', objeto: 'resumen', buscar: 'from crm.obtener_base_gestion() g', poner: 'from crm.obtener_base_gestion(null, true) g', cae: /^S1 resumen de V1: en base = su lista sin vetados/ },
  { nombre: 'detalle ≠ cifra (intentos sin el filtro del día)', objeto: 'detalle',
    buscar: "\n       and a.creado_en >= (v_hoy::timestamp at time zone 'America/Lima')\n       and (a.creado_en at time zone 'America/Lima')::date = v_hoy", poner: '', cae: /^S1: detalle = cifra en TODO analista/ },
  { nombre: 'un vetado en descanso no se ve', objeto: 'obtener', buscar: ' or (v_vetados and l.no_contactar))', poner: ')', cae: /^S1: LVD \(vetado en descanso\) se ve$/ },
  { nombre: 'un vetado entra en «Llamar hoy»', objeto: 'obtener',
    buscar: "(not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b",
    poner: "(b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b", cae: /^S1: LVR \(vetado con rellamada de hoy\) → rellamada_hoy false$/ },
  { nombre: 'los vetados no van al final', objeto: 'obtener', buscar: 'order by b.no_contactar,\n           ', poner: 'order by ', cae: /^S1: los vetados van al final$/ },
  { nombre: 'la marca no mira la acción (un «levantar» pasa por marca)', objeto: 'obtener', buscar: "where b.no_contactar and ev.accion = 'marcar'", poner: 'where b.no_contactar', cae: /^S1: LVL \(lo último del lead fue «levantar»\) → marca NULL$/ },
  { nombre: 'null = true', objeto: 'obtener', buscar: 'coalesce(p_incluir_vetados, false)', poner: 'coalesce(p_incluir_vetados, true)', cae: /^(V1|S1|G): null = false/ },
  { nombre: 'la detalle sin el ámbito del resumen', objeto: 'detalle',
    buscar: 'if not exists (select 1 from crm.base_gestion_resumen() r where r.vendedor_id = p_vendedor_id) then', poner: 'if false then', cae: /^S1 detalle de V3 \(otro equipo\) → P0002$/ },
  // r2 (Codex r2 + auditor-rls r2, 04/10): evento vigente de la persona, visibilidad, resolución por puente y DNI, postventa.
  { nombre: 'sin evento de persona (solo la nota del propio lead)', objeto: 'obtener',
    buscar: "        from (select b.id as lid\n              union\n              select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s  -- el conjunto de las puertas",
    poner: '        from (select b.id as lid) s', cae: /^r2 \(a\) contraejemplo 1: X \(enlace\) muestra la marca de Y/ },
  { nombre: 'evento de persona aunque la persona NO esté vetada', objeto: 'obtener',
    buscar: 'select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s', poner: 'select x from private.leads_de_persona_veto(pe.id) x) s',
    cae: /^r2 \(e\) veto solo del lead/ },
  { nombre: 'sin filtro de visibilidad del lead del evento', objeto: 'obtener',
    buscar: '\n      and le.activo and private.base_gestion_lead_visible(v_uid, v_rol, le.vendedor_id, le.asignado_supervisor_id)  -- nada de otro equipo',
    poner: '', cae: /^r2 \(d\) el evento vigente está en un lead de OTRO equipo/ },
  { nombre: 'persona sin el paso DNI', objeto: 'obtener',
    buscar: ",\n                      private.inversionista_por_documento('DNI', b.dni)) as id", poner: ') as id', cae: /^r2 \((a|b)\) Z2? \(DNI suelto\)/ },
  { nombre: 'persona sin el paso del puente', objeto: 'obtener',
    buscar: "\n                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il\n                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1),",
    poner: '', cae: /^r2 \(c\) Y5 \(puente\)/ },
  { nombre: 'postventa sin motivo (solo metadata.motivo)', objeto: 'obtener',
    buscar: "coalesce(a.metadata->>'motivo',\n                          case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo",
    poner: "a.metadata->>'motivo' as motivo", cae: /^r2 \(f\) postventa vigente/ },
  { nombre: 'vuelve la regla por hora con holgura (la de r1)', objeto: 'obtener',
    buscar: MARCA_R2, poner: MARCA_R1, cae: /^r2 \((a|b)\) contraejemplo/ },
  { nombre: 'la detalle muestra el nombre de un lead retirado (intentos)', objeto: 'detalle',
    buscar: "select a.lead_id, case when l.activo then l.nombre_completo end, a.creado_en, a.metadata->>'resultado'",
    poner: "select a.lead_id, l.nombre_completo, a.creado_en, a.metadata->>'resultado'", cae: /^S1 detalle de V1, intentos de hoy/ },
  { nombre: 'la detalle muestra el nombre de un lead retirado (reactivaciones)', objeto: 'detalle',
    buscar: 'select a.lead_id, case when l.activo then l.nombre_completo end, a.creado_en, case when l.activo then a.detalle end',
    poner: 'select a.lead_id, l.nombre_completo, a.creado_en, case when l.activo then a.detalle end', cae: /^r1 retirado: su reactivación del mes sale sin nombre ni nota$/ },
  { nombre: 'la detalle muestra la nota de un lead retirado', objeto: 'detalle',
    buscar: 'case when l.activo then a.detalle end', poner: 'a.detalle', cae: /^r1 retirado: su reactivación del mes sale sin nombre ni nota$/ },
];

const correr = (ddl) => {
  const r = psql(suite.replace('-- @@MUTANTE@@', ddl));
  const lineas = (r.stdout || '').split('\n');
  return { status: r.status, fallos: lineas.filter((l) => l.startsWith('FAIL ')), total: lineas.find((l) => l.startsWith('TOTAL:')) ?? '(sin total)', err: (r.stderr || '').trim().split('\n').slice(-2).join(' | ') };
};

const base = correr('-- sin mutante');
console.log(`suite sin mutante: ${base.total} (salida ${base.status})`);
if (base.status !== 0 || base.fallos.length) {
  for (const f of base.fallos) console.log(`  ${f}`);
  console.error(`ABORTADO: la suite sin mutante no pasa (${base.err})`);
  process.exit(1);
}
if (args.includes('--solo-suite')) process.exit(0);

let vivos = 0;
for (const m of MUTANTES) {
  const fuente = FUENTES[m.objeto];
  if (fuente.split(m.buscar).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez en ${m.objeto}`);
  const r = correr(fuente.replace(m.buscar, m.poner));
  const casos = r.fallos.map((l) => l.slice(5).split(' · esperado ')[0]);
  const cayoDonde = casos.some((c) => m.cae.test(c));
  if (r.status !== 0 && cayoDonde) console.log(`CAE  ${m.nombre} — ${r.total}; entre ellos el esperado (${casos.filter((c) => m.cae.test(c)).join(' / ')})`);
  else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; casos en FAIL: ${casos.join(' / ') || 'ninguno'} ${r.err}`); }
}
console.log(vivos === 0 ? `MUTANTES: ${MUTANTES.length}/${MUTANTES.length} caen` : `MUTANTES: ${vivos} de ${MUTANTES.length} SOBREVIVEN`);
process.exit(vivos === 0 ? 0 : 1);
