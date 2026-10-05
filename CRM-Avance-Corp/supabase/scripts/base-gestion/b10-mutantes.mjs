// B10 · mutantes de la suite b10-seguimiento.sql: cada uno neutraliza UNA defensa de la migración 20261004223253 (r2: la
// definición ÚNICA del estado en B9 y B10 —cada rama—, el bloque que solo elige «sin_repartir», el individual, la lista de B9 y
// recoger; la exclusión de la lista, la base viva del lead, cada cifra del seguimiento y sus bordes, el ámbito y las máscaras,
// el capital al reactivar y sus _v2) y la suite tiene que FALLAR en el caso que la prueba (o abortar con el error esperado). Si
// un mutante sobrevive, esa defensa NO está probada. Todo corre dentro de la transacción de la suite, que termina en ROLLBACK:
// el banco no cambia. Solo apunta a un banco LOCAL (127.0.0.1) con B7, B8, B9 r2 y B10 aplicadas, los actores de seed:demo y
// SIN bases; no acepta URL ni credenciales (PGPASSWORD del Postgres local, por defecto «postgres»).
// Al final, la reversa: sin deriva revierte (y se deshace con ROLLBACK); con cualquier deriva de B10 o un consumidor nuevo se
// NIEGA y la nombra, antes de borrar nada.
// Uso: node supabase/scripts/base-gestion/b10-mutantes.mjs --puerto 58222 [--solo-suite]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b10-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regprocedure('crm.seguimiento_bases()') is not null
  and to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is not null)::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B10 aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b10-seguimiento.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004223253_crm_bases_cargadas_seguimiento.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (inicio) => {
  const i = migracion.indexOf(inicio);
  if (i < 0 || migracion.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = migracion.indexOf('$function$;', migracion.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return migracion.slice(i, j).replace(/^create (or replace )?function/, () => 'create or replace function');
};
const FUENTES = {
  estado: bloque('create function private.bases_carga_estado_contacto('),
  motivoBloque: bloque('create function private.bases_carga_reparto_motivo_bloque('),
  contactos: bloque('create or replace function private.bases_carga_contactos_core('),
  recogible: bloque('create or replace function private.bases_carga_reparto_recogible('),
  repartir: bloque('create or replace function private.bases_carga_repartir_core('),
  cifras: bloque('create function private.bases_carga_seguimiento_cifras('),
  rol: bloque('create function private.bases_carga_seguimiento_rol('),
  exigir: bloque('create function private.bases_carga_seguimiento_exigir_base('),
  filas: bloque('create function private.bases_carga_seguimiento_filas('),
  obtener: bloque('create function crm.obtener_base_gestion('),
  bases: bloque('create function crm.seguimiento_bases('),
  base: bloque('create function crm.seguimiento_base('),
  detalle: bloque('create function crm.seguimiento_base_detalle('),
  nucleo: bloque('create function private.base_gestion_reactivar_capital_core('),
  envoltorio: bloque('create or replace function private.base_gestion_reactivar_core('),
  intento: bloque('create function private.base_gestion_intento_capital_core('),
  envoltorioIntento: bloque('create or replace function private.base_gestion_intento_core('),
  v2i: bloque('create function crm.registrar_intento_base_v2('),
  v2: bloque('create function crm.reactivar_lead_base_v2('),
};
// La llamada de B9 r2 (su motivo) que el bloque usaba antes de la definición única (para el mutante «el bloque vuelve a B9»).
const MOTIVO_B9 = "private.bases_carga_reparto_motivo(l.activo,\n"
  + "                                                      private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id),\n"
  + "                                                      l.etapa, l.no_contactar, l.enfriado_hasta,\n"
  + "                                                      private.base_gestion_en_gestion_hasta(l.id) is not null, v_hoy) as motivo";

const MUTANTES = [
  // ── r2/r3: la definición ÚNICA del estado (private.bases_carga_estado_contacto), en B9 y B10 ──
  { nombre: 'r3: el armado con su analista anterior vuelve a NO ser «sin repartir» (r2)', objeto: 'estado', buscar: "           else 'sin_repartir'\n", poner: "           when p_vendedor_id is not null then 'con_analista_previo'\n           else 'sin_repartir'\n", cae: /tabla de verdad|Armada|E1|el reparto REAL de .* no repartió 1/ },
  { nombre: 'r3: sin reparto y en seguimiento activo de su analista no es «trabajado»', objeto: 'estado', buscar: "           when p_vendedor_id is not null and private.base_gestion_en_gestion_hasta(p_lead_id) is not null then 'trabajado'\n", poner: '', cae: /candado de B9|trabajado/ },
  { nombre: 'sin mirar el veto', objeto: 'estado', buscar: "           when p_no_contactar is not false then 'no_contactar'\n", poner: '', cae: /tabla de verdad|F19|estado de CADA|Feria|Unica/ },
  { nombre: 'un veto NULL no veta', objeto: 'estado', buscar: "           when p_no_contactar is not false then 'no_contactar'\n", poner: "           when p_no_contactar is true then 'no_contactar'\n", cae: /tabla de verdad/ },
  { nombre: 'sin mirar el retiro', objeto: 'estado', buscar: "           when p_activo is not true then 'retirado'\n", poner: '', cae: /tabla de verdad|estado de CADA|Feria/ },
  { nombre: 'con reparto, sin mirar si sigue con su analista', objeto: 'estado', buscar: "           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'\n", poner: '', cae: /tabla de verdad|estado de CADA|Feria|movidos/ },
  { nombre: 'sin reparto, sin mirar el ámbito del dueño', objeto: 'estado', buscar: "                and private.bases_carga_en_subarbol(p_subarbol, p_vendedor_id, p_asignado_supervisor_id) is not true then 'movido_otra_via'\n", poner: "                and false then 'movido_otra_via'\n", cae: /tabla de verdad|F22|estado de CADA|Feria/ },
  { nombre: 'r3: sin reparto y fuera del descarte, siempre movido (r2; B9 dice cita/reactivado)', objeto: 'estado', buscar: "             case when p_cita is not null and p_reactivado is not null\n", poner: "             case when p_analista_id is null then 'movido_otra_via' when p_cita is not null and p_reactivado is not null\n", cae: /tabla de verdad|estado de CADA|Feria/ },
  { nombre: 'fuera del descarte = reactivado sin mirar los hechos pasados', objeto: 'estado', buscar: "then case when p_cita then 'cita' when p_reactivado then 'reactivado' else 'movido_otra_via' end", poner: "then case when p_cita then 'cita' else 'reactivado' end", cae: /tabla de verdad|estado de CADA|Feria|movidos/ },
  { nombre: 'fuera del descarte = reactivado sin mirar los hechos calculados', objeto: 'estado', buscar: "else (select case when h.cita is true then 'cita' when h.reactivado is true then 'reactivado' else 'movido_otra_via' end", poner: "else (select case when h.cita is true then 'cita' else 'reactivado' end", cae: /tabla de verdad/ },
  { nombre: 'trabajado sin mirar el intento pasado', objeto: 'estado', buscar: "case when p_intento then 'trabajado' else 'sin_tocar' end", poner: "case when false then 'trabajado' else 'sin_tocar' end", cae: /tabla de verdad|estado de CADA|estados|Feria/ },
  { nombre: 'trabajado (calculado) cuenta intentos ANTERIORES al reparto (recoger)', objeto: 'estado', buscar: "from private.bases_carga_reparto_hechos(p_lead_id, p_asignado_en) h)", poner: "from private.bases_carga_reparto_hechos(p_lead_id, p_asignado_en - interval '30 days') h)", cae: /recoger de vend1 en Feria/ },
  { nombre: 'sin el rastro de movimientos ajenos', objeto: 'estado', buscar: "                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)\n                and exists", poner: "                and false and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)\n                and exists", cae: /F17|estado de CADA|Feria|U4|Unica/ },
  { nombre: 'sin la excepción de la bandeja del dueño (un recogido saldría movido)', objeto: 'estado', buscar: "                and not (p_vendedor_id is null and p_asignado_supervisor_id is not distinct from p_dueno)\n                and exists", poner: "                and true\n                and exists", cae: /F21|estado de CADA|Feria|recoger/ },
  { nombre: 'los movimientos ANTES de entrar a la base cuentan', objeto: 'estado', buscar: 'a.creado_en >= p_agregado_en', poner: "a.creado_en >= p_agregado_en - interval '30 days'", cae: /Armada|D1/ },
  { nombre: 'el descanso que termina hoy sigue', objeto: 'estado', buscar: "p_enfriado_hasta > p_hoy then 'en_descanso'", poner: "p_enfriado_hasta >= p_hoy then 'en_descanso'", cae: /tabla de verdad|descanso|F13|Feria/ },
  { nombre: 'sin descanso', objeto: 'estado', buscar: "           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'\n", poner: '', cae: /tabla de verdad|F06|Unica|descanso/ },
  { nombre: 'nada es «sin repartir»', objeto: 'estado', buscar: "           else 'sin_repartir'\n", poner: "           else 'sin_tocar'\n", cae: /tabla de verdad|sin repartir|Feria|Unica/ },
  // ── r2: el bloque de B9 elige SOLO el estado sin_repartir ──
  { nombre: 'el bloque solo mira el motivo de B9 (lo movido por otra vía en el equipo se elegiría)', objeto: 'motivoBloque', buscar: "  return case when v_estado is not distinct from 'sin_repartir' then null else coalesce(v_estado, 'sin_estado') end;", poner: '  return null;', cae: /bloque de 3 en Unica|bloque de 2 en Unica/ },
  { nombre: 'el bloque vuelve al motivo de B9 (sin la definición única) en la foto Y bajo candado', objeto: 'repartir',
    buscar: ['private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) as motivo',
             'where private.bases_carga_reparto_motivo_bloque(l.id, l.activo, l.no_contactar, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.enfriado_hasta, bl.analista_id, bl.asignado_en, bl.creado_en, v_base.supervisor_id, v_subarbol, v_hoy) is null  -- B10 r2'],
    poner: [MOTIVO_B9, 'where ' + MOTIVO_B9.replace(' as motivo', ' is null')], cae: /bloque de 3 en Unica|bloque de 2 en Unica/ },
  { nombre: 'el individual acepta lo movido por otra vía', objeto: 'repartir', buscar: "        if (v_estado_c in ('sin_repartir', 'sin_tocar', 'trabajado')) is not true then\n          v_motivo := coalesce(v_estado_c, 'sin_estado');  -- r4 (auditor-rls P3-1): un estado NULL no se reparte\n        end if;\n", poner: '', cae: /U4 \(movido por otra vía\)/ },
  { nombre: 'el individual rechaza lo trabajado (a su propio analista)', objeto: 'repartir', buscar: "(v_estado_c in ('sin_repartir', 'sin_tocar', 'trabajado'))", poner: "(v_estado_c in ('sin_repartir', 'sin_tocar'))", cae: /el reparto REAL de .* no repartió 1|UA a vend1/ },
  // ── r4 (auditor-rls P3-1): un estado NULL nunca se reparte ──
  { nombre: 'r4: el bloque elige un estado NULL', objeto: 'motivoBloque', buscar: "  return case when v_estado is not distinct from 'sin_repartir' then null else coalesce(v_estado, 'sin_estado') end;", poner: "  return case when v_estado = 'sin_repartir' then null else v_estado end;", cae: /estado NULL \(doble\), el bloque/ },
  { nombre: 'r4: el individual acepta un estado NULL', objeto: 'repartir', buscar: "          v_motivo := coalesce(v_estado_c, 'sin_estado');  -- r4 (auditor-rls P3-1): un estado NULL no se reparte\n", poner: "          v_motivo := v_estado_c;\n", cae: /individual lo rechaza con el motivo sin_estado/ },
  // ── r4 (Codex r2, 2 P2): la fila anónima y el analista externo explícito ──
  { nombre: 'r4: los externos salen en una fila anónima POR analista (Codex P2-1)', objeto: 'base', buscar: "     group by 1\n", poner: "     group by x.analista_id, vis.ids\n", cae: /UNA sola fila anónima/ },
  { nombre: 'r4: la fila de un analista externo muestra su id', objeto: 'base', buscar: "case when v_rol = 'gerencia' or x.analista_id = any (vis.ids) then x.analista_id end as id", poner: 'x.analista_id as id', cae: /UNA sola fila anónima|auditor P3/ },
  { nombre: 'r4: el detalle no mira el ámbito del analista explícito (Codex P2-2)', objeto: 'detalle', buscar: "     and v_rol is distinct from 'gerencia'\n     and (p_analista_id in (select private.vendedor_ids_visibles(v_uid))) is not true then", poner: '     and false then', cae: /UUID de vend3/ },
  // ── r2/r3: la lista de B9 (crm.contactos_de_base) con el mismo estado y el filtro de B9 ──
  { nombre: 'r3: el filtro «sin_repartir» deja fuera a los vetados (no es el de B9)', objeto: 'contactos', buscar: "       and (v_filtro = 'todos' or (v_filtro = 'sin_repartir') = (bl.analista_id is null))", poner: "       and (v_filtro = 'todos' or (v_filtro = 'sin_repartir') = (bl.analista_id is null and not l.no_contactar))", cae: /filtro «sin_repartir»|filtro por defecto/ },
  { nombre: 'la lista de B9 clasifica sin el supervisor dueño', objeto: 'contactos', buscar: 'bl.asignado_en, bl.creado_en, v_sup, v_subarbol, v_hoy,', poner: 'bl.asignado_en, bl.creado_en, null, v_subarbol, v_hoy,', cae: /coherencia|Unica|estados|Armada/ },
  { nombre: 'la lista de B9 pasa otros hechos', objeto: 'contactos', buscar: 'h.intento, h.cita, h.reactivado)', poner: 'h.intento, h.reactivado, h.reactivado)', cae: /coherencia/ },
  { nombre: 'la lista de B9 sin el ámbito del lead (salen los retirados)', objeto: 'contactos', buscar: '       and private.bases_carga_lead_ref(p_actor, v_rol, l.id)\n', poner: '\n', cae: /retirados .* no salen|coherencia/ },
  // ── r2: recoger = el estado sin_tocar ──
  { nombre: 'recoger se lleva también un vetado sin intento (B9)', objeto: 'recogible', buscar: "= 'sin_tocar')", poner: "in ('sin_tocar', 'no_contactar'))", cae: /U recoger de vend2/ },
  // ── La lista de la base para gestión ──
  { nombre: 'la lista sin la exclusión', objeto: 'obtener', buscar: "is distinct from 'sin_repartir')", poner: "is distinct from 'nunca')", cae: /^D sup1: los dormidos|^D Gerencia: los dormidos|F21|U1/ },
  { nombre: 'r3: la lista vuelve a ocultar los ARMADOS sin repartir (r2)', objeto: 'obtener', buscar: "           or bl.procedencia is distinct from 'archivo'\n", poner: '', cae: /D4|armados|r3: lista|vend1 \(su analista anterior\)/ },
  { nombre: 'la exclusión sin el supervisor dueño (un recogido seguiría en la lista)', objeto: 'obtener', buscar: 'bl.asignado_en, bl.creado_en, bc.supervisor_id,', poner: 'bl.asignado_en, bl.creado_en, null,', cae: /F21|DISPONIBLES|U1/ },
  { nombre: 'base_nombre sin la máscara de la base (auditor P3)', objeto: 'obtener', buscar: 'case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.nombre end as base_nombre', poner: 'case when bc.id is not null then bc.nombre end as base_nombre', cae: /auditor P3|NINGUNA base/ },
  { nombre: 'base_nombre sin el analista del lead', objeto: 'obtener', buscar: 'case when bc.id is not null and (l.vendedor_id = v_uid or bc.id = any (v_bases)) then bc.nombre end as base_nombre', poner: 'case when bc.id is not null and bc.id = any (v_bases) then bc.nombre end as base_nombre', cae: /vend3 ve F16|vend1 ve sus|F17/ },
  { nombre: 'las bases visibles sin el ámbito (todas)', objeto: 'obtener', buscar: 'v_bases := array(select b.id from crm.bases_carga b where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id));', poner: 'v_bases := array(select b.id from crm.bases_carga b where b.activo);', cae: /auditor P3|NINGUNA base/ },
  { nombre: 'la base sin mirar si está viva (base retirada)', objeto: 'obtener', buscar: '     where b.activo\n  ),\n  base as (', poner: '     where true\n  ),\n  base as (', cae: /R1|base VIVA/ },
  { nombre: 'la pertenencia sin mirar si está viva (pertenencia retirada)', objeto: 'obtener', buscar: 'left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo', poner: 'left join crm.base_carga_leads bl on bl.lead_id = l.id', cae: /S02|base VIVA/ },
  { nombre: 'base_nombre con el id de la base', objeto: 'obtener', buscar: 'then bc.nombre end as base_nombre', poner: 'then bc.id::text end as base_nombre', cae: /con su base|base_nombre|base VIVA|vend1 ve sus/ },
  // ── Las cifras ──
  { nombre: 'los hechos cuentan desde ANTES del reparto', objeto: 'filas', buscar: 'cross join lateral private.bases_carga_reparto_hechos(bl.lead_id, coalesce(bl.asignado_en, bl.creado_en)) h', poner: "cross join lateral private.bases_carga_reparto_hechos(bl.lead_id, coalesce(bl.asignado_en, bl.creado_en) - interval '30 days') h", cae: /D3|Armada|F10|Feria/ },
  { nombre: 'el seguimiento pasa otros hechos a la definición única', objeto: 'filas', buscar: 'bs.subarbol, p_hoy, h.intento, h.cita, h.reactivado) as estado', poner: 'bs.subarbol, p_hoy, h.reactivado, h.cita, h.reactivado) as estado', cae: /estado de CADA|Feria|estados/ },
  { nombre: 'cita = reactivado', objeto: 'filas', buscar: "case when x.rep and x.cita is true then 'citas' end", poner: "case when x.rep and x.reactivado is true then 'citas' end", cae: /citas|Feria/ },
  { nombre: 'en descanso solo con reparto (r1)', objeto: 'filas', buscar: "case when x.estado = 'en_descanso' then 'en_descanso' end", poner: "case when x.rep and x.estado = 'en_descanso' then 'en_descanso' end", cae: /Unica \(contado a mano\)/ },
  { nombre: 'el estado del seguimiento sin el supervisor dueño', objeto: 'filas', buscar: 'bl.creado_en, bs.supervisor_id,', poner: 'bl.creado_en, null,', cae: /F21|Feria|estado de CADA|sin repartir/ },
  { nombre: 'el subárbol del dueño es solo el dueño', objeto: 'filas', buscar: 'array(select private.bases_carga_subarbol(b.supervisor_id)) as subarbol', poner: 'array[b.supervisor_id] as subarbol', cae: /Armada|D4|Unica/ },
  { nombre: 'rojo a los 2 días', objeto: 'filas', buscar: "case when x.estado = 'sin_tocar' and x.dias >= 3 then 'sin_tocar_3_dias' end", poner: "case when x.estado = 'sin_tocar' and x.dias >= 2 then 'sin_tocar_3_dias' end", cae: /rojo|Feria/ },
  { nombre: 'rojo pasado el tercer día', objeto: 'filas', buscar: "case when x.estado = 'sin_tocar' and x.dias >= 3 then 'sin_tocar_3_dias' end", poner: "case when x.estado = 'sin_tocar' and x.dias > 3 then 'sin_tocar_3_dias' end", cae: /rojo|Feria/ },
  { nombre: 'las pertenencias retiradas cuentan', objeto: 'filas', buscar: 'where bl.base_id = any (p_base_ids) and bl.activo', poner: 'where bl.base_id = any (p_base_ids)', cae: /Sur/ },
  { nombre: 'sin repartir = todo lo que no tiene reparto (r0)', objeto: 'filas', buscar: "case when x.estado = 'sin_repartir' then 'sin_repartir' end", poner: "case when not x.rep then 'sin_repartir' end", cae: /Feria|cuadra|coherencia/ },
  { nombre: 'las cifras sin «retirados»', objeto: 'cifras', buscar: "'movidos_otra_via', 'retirados', 'no_contactar']::text[];", poner: "'movidos_otra_via', 'no_contactar']::text[];", cae: /retirad|cuadra/ },
  // ── Las puertas del seguimiento: ámbito, máscaras, roles ──
  { nombre: 'seguimiento_bases lista bases retiradas', objeto: 'bases', buscar: '   where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id);', poner: '   where private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id);', cae: /^E sup1 ve|^E Gerencia ve|cuadra/ },
  { nombre: 'seguimiento_bases sin ámbito', objeto: 'bases', buscar: '   where b.activo and private.bases_carga_base_visible(v_uid, v_rol, b.supervisor_id);', poner: '   where b.activo;', cae: /^E sup1 ve|^E sup2 ve/ },
  { nombre: 'avance = trabajados / total', objeto: 'bases', buscar: 'pg_catalog.round(c.n_trabajados::numeric / c.n_repartidos, 4)', poner: 'pg_catalog.round(c.n_trabajados::numeric / c.n_total, 4)', cae: /^E Feria/ },
  { nombre: 'seguimiento_base muestra el nombre de otro equipo', objeto: 'base', buscar: '    left join public.perfiles p on p.id = c.id\n', poner: "    left join public.perfiles p on p.id = coalesce(c.id, (select bl.analista_id from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.analista_id is not null and not (bl.analista_id = any ((select vis.ids from vis))) limit 1))\n", cae: /auditor P3|UNA sola fila anónima/ },
  { nombre: 'el detalle sin máscara de identidad', objeto: 'detalle', buscar: 'select case when r.ve then x.lead_id end, case when r.ve then x.nombre_completo end,', poner: 'select x.lead_id, x.nombre_completo,', cae: /delatar|retirado \(F15\)|F22|\?,\?/ },
  { nombre: 'el detalle sin el filtro del analista', objeto: 'detalle', buscar: 'where (p_analista_id is null or x.analista_id = p_analista_id)', poner: 'where (true)', cae: /cuadra|estados|sin tocar de vend1/ },
  { nombre: 'el detalle sin P0002 para un analista ajeno a la base', objeto: 'detalle', buscar: '  if p_analista_id is not null\n     and not exists', poner: '  if false and p_analista_id is not null\n     and not exists', cae: /sin contactos en la base|MISMO mensaje que vend2/ },
  { nombre: 'el rol admite coordinación', objeto: 'rol', buscar: "(v_rol in ('supervisor', 'gerencia')) is not true", poner: "(v_rol in ('supervisor', 'gerencia', 'coordinador')) is not true", cae: /coordinador/ },
  { nombre: 'exigir_base admite bases retiradas', objeto: 'exigir', buscar: 'where b.id = p_base_id and b.activo and private.bases_carga_base_visible', poner: 'where b.id = p_base_id and private.bases_carga_base_visible', cae: /RETIRADA/ },
  { nombre: 'exigir_base sin ámbito', objeto: 'exigir', buscar: 'and b.activo and private.bases_carga_base_visible(p_actor, p_rol, b.supervisor_id)) then', poner: 'and b.activo) then', cae: /sup2 → Feria|anidado → Feria/ },
  // ── Capital al reactivar ──
  { nombre: 'el núcleo no exige el capital (23514 del CHECK)', objeto: 'nucleo', buscar: '  if v_lead.monto_estimado is null then\n    if p_monto_estimado is null then', poner: '  if v_lead.monto_estimado is null then\n    if false then', cae: /sin capital → 22023|agendó cita/ },
  { nombre: 'el núcleo pisa un capital que ya existe', objeto: 'nucleo', buscar: '  if v_lead.monto_estimado is null then\n    if p_monto_estimado is null then', poner: '  if v_lead.monto_estimado is null or p_monto_estimado is not null then\n    if p_monto_estimado is null then', cae: /G2|ignora/ },
  { nombre: 'el núcleo ignora la moneda', objeto: 'nucleo', buscar: 'moneda = coalesce(p_moneda, moneda)', poner: 'moneda = moneda', cae: /G4/ },
  { nombre: 'el núcleo pone PEN si no llega moneda', objeto: 'nucleo', buscar: 'moneda = coalesce(p_moneda, moneda)', poner: "moneda = coalesce(p_moneda, 'PEN')", cae: /G3/ },
  { nombre: 'el núcleo sin validar el monto', objeto: 'nucleo', buscar: '    if (p_monto_estimado > 0 and p_monto_estimado <= 9999999999.99 and p_monto_estimado = trunc(p_monto_estimado, 2)) is not true then', poner: '    if false then', cae: /capital 0|capital -5|capital 1\.001|capital 10000000000|NaN/ },
  { nombre: 'el núcleo sin validar la moneda', objeto: 'nucleo', buscar: "    if p_moneda is not null and (p_moneda in ('PEN', 'USD')) is not true then", poner: '    if false then', cae: /moneda EUR|moneda pen/ },
  { nombre: 'r1: el replay de reactivar no mira el capital (Codex)', objeto: 'nucleo', buscar: "       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then\n", poner: '       or false then\n', cae: /otro contenido/ },
  { nombre: 'r1: la respuesta de reactivar sin el capital efectivo', objeto: 'nucleo', buscar: "|| jsonb_build_object('monto_estimado', v_lead.monto_estimado, 'moneda', v_lead.moneda,", poner: "|| jsonb_build_object('monto_estimado', p_monto_estimado, 'moneda', v_lead.moneda,", cae: /capital EFECTIVO|G2/ },
  { nombre: 'r1: el replay del intento no mira el capital', objeto: 'intento', buscar: "       or (v_prev->>'solicitud_monto')::numeric is distinct from p_monto_estimado or v_prev->>'solicitud_moneda' is distinct from p_moneda then\n", poner: '       or false then\n', cae: /el intento responde/ },
  { nombre: 'la _v2 no pasa el capital', objeto: 'v2', buscar: 'p_nota, p_monto_estimado, p_moneda);', poner: 'p_nota, null, p_moneda);', cae: /G1|G3|G4|C F08|C F20/ },
  { nombre: '«agendó cita» no pasa el capital del intento', objeto: 'intento', buscar: '                                                           p_monto_estimado, p_moneda);', poner: '                                                           null, null);', cae: /G6|igual|MISMAS claves|el intento responde/ },
  { nombre: 'el núcleo de intentos de siempre pone un capital (la puerta publicada reactivaría sin pedirlo)', objeto: 'envoltorioIntento', buscar: 'p_proxima, null::numeric, null::text);', poner: 'p_proxima, 1::numeric, null::text);', cae: /agendó cita» sobre un lead sin capital/ },
  { nombre: 'la _v2 de intentos no pasa el capital', objeto: 'v2i', buscar: 'p_monto_estimado, p_moneda);', poner: 'null, null);', cae: /G6|igual|MISMAS claves|el intento responde/ },
  { nombre: 'el núcleo de 4 argumentos pone un capital (la puerta publicada reactivaría sin pedirlo)', objeto: 'envoltorio', buscar: 'p_nota, null::numeric, null::text);', poner: 'p_nota, 1::numeric, null::text);', cae: /puerta publicada, lead sin capital|agendó cita/ },
];

const correr = (ddl) => {
  // Reemplazo con FUNCIÓN: un texto de reemplazo interpretaría «$'» de los regex del SQL.
  const r = psql(suite.replace('-- @@MUTANTE@@', () => ddl));
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
  let fuente = FUENTES[m.objeto];
  const buscar = Array.isArray(m.buscar) ? m.buscar : [m.buscar];
  const poner = Array.isArray(m.poner) ? m.poner : [m.poner];
  buscar.forEach((b, k) => {
    if (fuente.split(b).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez en ${m.objeto}`);
    fuente = fuente.replace(b, () => poner[k]);
  });
  const r = correr(fuente);
  const casos = r.fallos.map((l) => l.slice(5).split(' · esperado ')[0]);
  const cayoDonde = casos.some((c) => m.cae.test(c)) || (casos.length === 0 && m.cae.test(r.err));
  if (r.status !== 0 && cayoDonde) console.log(`CAE  ${m.nombre} — ${r.total}; entre ellos el esperado (${casos.filter((c) => m.cae.test(c)).join(' / ').slice(0, 160)})`);
  else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; casos en FAIL: ${casos.join(' / ').slice(0, 300) || 'ninguno'} ${r.err}`); }
}
console.log(vivos === 0 ? `MUTANTES: ${MUTANTES.length}/${MUTANTES.length} caen` : `MUTANTES: ${vivos} de ${MUTANTES.length} SOBREVIVEN`);

// ── Reversa: sin deriva revierte (y se deshace con ROLLBACK); con una deriva de B10 o un consumidor nuevo se NIEGA y la nombra. ──
const reversa = readFileSync(new URL('./reversa-b10.sql', AQUI), 'utf8');
const ini = reversa.indexOf('\nbegin;\n');
const fin = reversa.lastIndexOf('commit;');
if (ini < 0 || fin < ini) throw new Error('reversa-b10.sql sin begin/commit');
const LINEA_AISLAMIENTO = 'set transaction isolation level read committed;\n';
const cuerpoReversa = reversa.slice(ini + '\nbegin;\n'.length, fin);
if (cuerpoReversa.split(LINEA_AISLAMIENTO).length !== 2) throw new Error('reversa-b10.sql: no encuentro UNA vez su set transaction');
const correrReversa = (deriva) => psql('begin;\n' + LINEA_AISLAMIENTO
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + deriva + '\n' + cuerpoReversa.replace(LINEA_AISLAMIENTO, () => '') + '\nrollback;\n');
const DERIVAS = [
  { nombre: 'el cuerpo de seguimiento_bases cambiado', ddl: FUENTES.bases.replace('  return query\n', () => '  -- cambio posterior a B10\n  return query\n'), niega: /deriva en .*crm\.seguimiento_bases/ },
  { nombre: 'EXECUTE de la _v2 para service_role', ddl: 'grant execute on function crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text) to service_role;', niega: /deriva en .*crm\.reactivar_lead_base_v2/ },
  { nombre: 'el comentario de la lista cambiado', ddl: "comment on function crm.obtener_base_gestion(uuid,boolean) is 'otro';", niega: /deriva en .*crm\.obtener_base_gestion/ },
  { nombre: 'el núcleo con capital cambiado', ddl: FUENTES.nucleo.replace('  return v_resp;\nend;', () => '  -- cambio posterior\n  return v_resp;\nend;'), niega: /deriva en .*base_gestion_reactivar_capital_core/ },
  { nombre: 'el núcleo de intentos con capital cambiado', ddl: FUENTES.intento.replace('  return v_resp;\nend;', () => '  -- cambio posterior\n  return v_resp;\nend;'), niega: /deriva en .*base_gestion_intento_capital_core/ },
  { nombre: 'la puerta publicada de intentos cambiada', ddl: "create or replace function crm.registrar_intento_base(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text default null, p_proxima_llamada timestamptz default null) returns jsonb language plpgsql security definer set search_path = '' as $f$ begin return private.base_gestion_intento_core((select auth.uid()), p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima_llamada); end $f$;", niega: /ya no son los de antes de B10/ },
  { nombre: 'el núcleo de 4 argumentos cambiado', ddl: FUENTES.envoltorio.replace('end;\n$function$;', () => '  -- cambio posterior\nend;\n$function$;'), niega: /deriva en .*base_gestion_reactivar_core\(uuid,uuid,uuid,text\)/ },
  { nombre: 'una sobrecarga nueva de seguimiento_base', ddl: "create function crm.seguimiento_base(p text) returns integer language sql as 'select 1';", niega: /numero de funciones de B10/ },
  { nombre: 'una función ajena usa el seguimiento (F6/B11)', ddl: "create function private.b11_falsa() returns bigint language sql as 'select count(*) from crm.seguimiento_bases()';", niega: /usan las puertas o los ayudantes de B10/ },
  { nombre: 'una vista usa la lista', ddl: 'create view crm.b11_vista_falsa as select g.lead_id from crm.obtener_base_gestion() g;', niega: /hay vistas que usan B10/ },
  { nombre: 'r2: el núcleo de reparto de B9 cambiado después de B10', ddl: FUENTES.repartir.replace('  return v_resp;\nend;', () => '  -- cambio posterior\n  return v_resp;\nend;'), niega: /deriva en .*bases_carga_repartir_core/ },
  { nombre: 'r2: el comentario de una puerta de B9 cambiado después de B10', ddl: "comment on function crm.repartir_base(uuid,uuid,jsonb) is 'otro';", niega: /deriva en .*crm\.repartir_base/ },
  { nombre: 'r2: la definición única cambiada', ddl: FUENTES.estado.replace("           else 'sin_repartir'\n", () => "           else 'sin_repartir'  -- cambio posterior\n"), niega: /deriva en .*bases_carga_estado_contacto/ },
  { nombre: 'r2: una función ajena usa la definición única', ddl: "create function private.b11_falsa2() returns text language sql as 'select private.bases_carga_estado_contacto(null, true, false, null, null, null, null, null, null, null, null, null, null)';", niega: /usan las puertas o los ayudantes de B10/ },
  { nombre: 'r2: el clasificador de B9 repuesto por otra migración', ddl: "create function private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date) returns text language sql as 'select null::text';", niega: /el clasificador de B9 ya existe/ },
  { nombre: 'la puerta publicada de reactivar cambiada', ddl: "create or replace function crm.reactivar_lead_base(p_operacion_id uuid, p_lead_id uuid, p_nota text default null) returns jsonb language plpgsql security definer set search_path = '' as $f$ begin return private.base_gestion_reactivar_core((select auth.uid()), p_operacion_id, p_lead_id, p_nota, 1, null); end $f$;", niega: /ya no son los de antes de B10/ },
];
const CONTROLES = [
  { nombre: 'sin deriva', ddl: '-- sin deriva' },
  { nombre: 'otro comentario en una función ajena (como difiere entre entornos)', ddl: "comment on function private.base_gestion_rol(uuid) is 'comentario de otro entorno';" },
];
let controlOk = true;
for (const c of CONTROLES) {
  const r = correrReversa(c.ddl);
  const ok = r.status === 0 && /REVERSA B10 OK/.test(r.stderr || '');
  controlOk = controlOk && ok;
  console.log(ok ? `REVERSA control (${c.nombre}): revierte (REVERSA B10 OK, deshecho con ROLLBACK)` : `REVERSA control (${c.nombre}): FALLA (${(r.stderr || '').trim().split('\n').slice(-2).join(' | ')})`);
}
let niegan = 0;
for (const d of DERIVAS) {
  const r = correrReversa(d.ddl);
  const err = (r.stderr || '').trim().split('\n').filter((l) => l.includes('ERROR')).join(' | ');
  if (r.status !== 0 && d.niega.test(err)) { niegan += 1; console.log(`NIEGA ${d.nombre} — ${err.slice(0, 160)}`); }
  else console.log(`PASA  ${d.nombre} — la reversa NO se negó como debía (salida ${r.status}) ${err.slice(0, 200)}`);
}
console.log(`REVERSA: ${niegan}/${DERIVAS.length} derivas rechazadas${controlOk ? ' · control OK' : ' · CONTROL FALLA'}`);
process.exit(vivos === 0 && controlOk && niegan === DERIVAS.length ? 0 : 1);
