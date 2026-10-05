// B8 · mutantes de la suite b8-cargar.sql: cada uno neutraliza UNA defensa de la migración 20261004184501 (puertas, núcleo,
// «nace dormido», fecha del descarte, ciclo SLA, envoltorio de identidad, repetidas, ámbito, topes, idempotencia, armar) y la
// suite tiene que FALLAR en el caso que la prueba. Si un mutante sobrevive, esa defensa NO está probada. Todo corre dentro de
// la transacción de la suite, que termina en ROLLBACK: el banco no cambia. Solo apunta a un banco LOCAL (127.0.0.1) con B7 y B8
// aplicadas y los actores de seed:demo; no acepta URL ni credenciales (PGPASSWORD del Postgres local, por defecto «postgres»).
// Dobles controles a propósito (ver al final): se prueban con un mutante DOBLE.
// r2: `--concurrencia` aplica (y CONFIRMA, luego restaura) cada mutante que solo se ve con dos sesiones y exige que
// b8-concurrencia.sh FALLE en su escenario. Escribe en el banco: limpiar después con limpiar-entre-corridas.sql.
// Uso: node supabase/scripts/base-gestion/b8-mutantes.mjs --puerto 58122 [--solo-suite | --concurrencia]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b8-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
  and to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is not null)::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B8 aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b8-cargar.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004184501_crm_bases_cargadas_cargar.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (inicio) => {
  const i = migracion.indexOf(inicio);
  if (i < 0 || migracion.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = migracion.indexOf('$function$;', migracion.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return migracion.slice(i, j).replace(/^create (or replace )?function/, () => 'create or replace function');
};
const FUENTES = {
  dormido: bloque('create function private.bases_carga_nace_dormido('),
  fecha: bloque('create function private.trg_leads_sello_descarte_base_cargada('),
  rol: bloque('create function private.bases_carga_rol('),
  destino: bloque('create function private.bases_carga_supervisor_destino('),
  visible: bloque('create function private.bases_carga_base_visible('),
  previa: bloque('create function private.bases_carga_operacion_previa('),
  existente: bloque('create function private.bases_carga_contacto_existente('),
  ref: bloque('create function private.bases_carga_lead_ref('),
  subarbol: bloque('create function private.bases_carga_subarbol('),
  ensubarbol: bloque('create function private.bases_carga_en_subarbol('),
  fuera: bloque('create function private.bases_carga_fuera_de_ambito('),
  transitorio: bloque('create function private.bases_carga_error_transitorio('),
  lote: bloque('create function private.bases_carga_cargar_lote_core('),
  armar: bloque('create function private.bases_carga_armar_core('),
  alta: bloque('create or replace function private.leads_before_insert()'),
  disponibilidad: bloque('create or replace function private.trg_leads_disponibilidad_atomica()'),
  sla: bloque('create or replace function private.trg_leads_sla_versionado()'),
};

const MUTANTES = [
  // «Nace dormido»: cada condición de la definición única.
  { nombre: '«nace dormido» sin la válvula', objeto: 'dormido',
    buscar: "coalesce(pg_catalog.current_setting('crm.op_bases_carga', true), 'off') = 'on'\n          and ", poner: '', cae: /^A7 / },
  { nombre: '«nace dormido» sin el origen', objeto: 'dormido', buscar: "and p_origen = 'base_cargada' ", poner: '', cae: /^L3 / },
  { nombre: '«nace dormido» sin la etapa', objeto: 'dormido', buscar: "and p_etapa = 'descartado' ", poner: '', cae: /^L6 / },
  { nombre: '«nace dormido» sin el motivo', objeto: 'dormido', buscar: "and p_motivo = 'base_cargada' ", poner: '', cae: /^L4 / },
  { nombre: '«nace dormido» sin exigir activo', objeto: 'dormido', buscar: ' and p_activo) is true', poner: ') is true', cae: /^L5 / },
  // Las tres funciones del alta.
  { nombre: 'leads_before_insert sin la excepción del dormido (lo de B7)', objeto: 'alta',
    buscar: "    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')\n       and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then\n",
    poner: "    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then\n", cae: /^D1 / },
  { nombre: 'disponibilidad sin la excepción del dormido', objeto: 'disponibilidad',
    buscar: "         and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo)) then\n", poner: "         and true) then\n", cae: /^D1 / },
  { nombre: 'sla_versionado abre el ciclo también al dormido', objeto: 'sla',
    buscar: "  if (tg_op='INSERT' and not private.bases_carga_nace_dormido(new.origen,new.etapa,new.motivo_descarte,new.activo))\n", poner: "  if (tg_op='INSERT')\n", cae: /^E11 / },
  // Fecha del descarte.
  { nombre: 'sin el disparador de la fecha del descarte', ddl: 'drop trigger trg_leads_zz_sello_descarte_base_cargada on crm.leads;', cae: /^F1 / },
  { nombre: 'el disparador antedata el descarte 40 días', objeto: 'fecha',
    buscar: '    new.descartado_en := pg_catalog.statement_timestamp();\n', poner: "    new.descartado_en := pg_catalog.statement_timestamp() - interval '40 days';\n", cae: /^E2 / },
  { nombre: 'el disparador no anota quién cargó', objeto: 'fecha', buscar: '    new.descartado_por := (select auth.uid());\n', poner: '', cae: /^E2 / },
  // Núcleo del lote.
  { nombre: 'la válvula queda encendida al salir', objeto: 'lote',
    buscar: "    perform pg_catalog.set_config('crm.op_bases_carga', 'off', true);\n", poner: '', cae: /^E7 / },
  { nombre: 'sin el envoltorio de identidad (el «libre» del verificador carga)', objeto: 'lote',
    buscar: '          if v_ex.lead_id is not null then\n', poner: '          if false then\n', cae: /^D1 / },
  { nombre: 'sin las repetidas del lote (teléfono y DNI)', objeto: 'lote',
    buscar: "    elsif v_vistos ? ('t:' || v_tel) or (v_dni is not null and v_vistos ? ('d:' || v_dni)) then\n", poner: '    elsif false then\n', cae: /^D1 / },
  { nombre: 'las repetidas del lote solo por teléfono', objeto: 'lote',
    buscar: "    elsif v_vistos ? ('t:' || v_tel) or (v_dni is not null and v_vistos ? ('d:' || v_dni)) then\n", poner: "    elsif v_vistos ? ('t:' || v_tel) then\n", cae: /^D1 / },
  { nombre: 'sin la repetida en la base (lote anterior)', objeto: 'lote',
    buscar: "    if found then\n      v_ver := 'repetida'; v_mot := 'en_base';\n", poner: "    if false then\n      v_ver := 'repetida'; v_mot := 'en_base';\n", cae: /^G1 / },
  // r1 · referencias, ámbito y pertenencia viva.
  { nombre: 'la referencia devolvible sin exigir que el actor la vea', objeto: 'ref',
    buscar: 'l.activo and private.base_gestion_lead_visible(p_actor, p_rol, l.vendedor_id, l.asignado_supervisor_id)', poner: 'l.activo', cae: /^G6 / },
  { nombre: 'la referencia devolvible de un lead retirado', objeto: 'ref',
    buscar: 'l.activo and private.base_gestion_lead_visible(', poner: 'private.base_gestion_lead_visible(', cae: /^D1 / },
  { nombre: 'repetida/en_base devuelve el id sin el control', objeto: 'lote',
    buscar: '      if not private.bases_carga_lead_ref(p_actor, v_rol, v_ref) then\n        v_ref := null;\n      end if;\n', poner: '', cae: /^G6 / },
  { nombre: 'repetida/en_base cuenta pertenencias retiradas', objeto: 'lote',
    buscar: '     where bl.base_id = p_base_id and bl.activo\n', poner: '     where bl.base_id = p_base_id\n', cae: /^G7 / },
  { nombre: 'sin la regla «fuera del ámbito → solo ya_existia»', objeto: 'lote',
    buscar: '      if private.bases_carga_fuera_de_ambito(p_actor, v_rol, a_tel[i], a_dni[i]) then\n', poner: '      if false then\n', cae: /^D1 / },
  { nombre: '«fuera del ámbito» mirando solo la coincidencia más relevante', objeto: 'fuera',
    buscar: '  select coalesce(pg_catalog.bool_or(not private.base_gestion_lead_visible(p_actor, p_rol, x.vendedor_id, x.asignado_supervisor_id)), false)\n    from private.bases_carga_contacto_existente(p_telefono, p_dni) x\n',
    poner: '  select coalesce((select not private.base_gestion_lead_visible(p_actor, p_rol, x.vendedor_id, x.asignado_supervisor_id)\n    from private.bases_carga_contacto_existente(p_telefono, p_dni) x order by x.orden limit 1), false)\n', cae: /^D1 / },
  { nombre: 'el INSERT sin el respaldo fila a fila (el P0481 sale con su detail)', objeto: 'lote',
    buscar: "    exception when others then\n      get stacked diagnostics v_estado = returned_sqlstate;\n      -- r2 (Codex riesgo): lo transitorio aborta el lote entero, sin repetir (private.bases_carga_error_transitorio).\n      if private.bases_carga_error_transitorio(v_estado) then\n        raise exception using errcode = v_estado, message = pg_catalog.format('La carga se interrumpió (%s); reintenta', v_estado);\n      end if;\n      v_ins := null;  -- r1 (Codex, riesgo): la tanda chocó con un rechazo (una carrera); se repite fila a fila, abajo\n",
    poner: '', cae: /^T1 / },
  // r2 · lo transitorio aborta (sin repetir, sin detail) y el P0429 del respaldo con la regla del ámbito.
  { nombre: 'la tanda repite fila a fila también lo transitorio', objeto: 'lote',
    buscar: "      if private.bases_carga_error_transitorio(v_estado) then\n        raise exception using errcode = v_estado, message = pg_catalog.format('La carga se interrumpió (%s); reintenta', v_estado);\n      end if;\n      v_ins := null;",
    poner: '      v_ins := null;', cae: /^T6 / },
  { nombre: 'lo transitorio re-lanza la excepción tal cual (con el detail del disparador)', objeto: 'lote',
    buscar: "      if private.bases_carga_error_transitorio(v_estado) then\n        raise exception using errcode = v_estado, message = pg_catalog.format('La carga se interrumpió (%s); reintenta', v_estado);\n      end if;\n      v_ins := null;",
    poner: '      if private.bases_carga_error_transitorio(v_estado) then\n        raise;\n      end if;\n      v_ins := null;', cae: /^T6 / },
  { nombre: '40001 no cuenta como transitorio', objeto: 'transitorio', buscar: "p_sqlstate in ('40P01', '55P03', '57014', '40001', '25P02')", poner: "p_sqlstate in ('40P01', '55P03', '57014', '25P02')", cae: /^T6 / },
  { nombre: 'el respaldo convierte el P0429 en no_contactar sin mirar el ámbito', objeto: 'lote',
    buscar: "            a_ver[i] := case when private.bases_carga_fuera_de_ambito(p_actor, v_rol, a_tel[i], a_dni[i]) then 'ya_existia' else 'no_contactar' end;",
    poner: "            a_ver[i] := 'no_contactar';", cae: /^T7 / },
  // r2 · el replay vuelve a juzgar cada lead que nombra el recibo.
  { nombre: 'el replay de una carga sin volver a juzgar sus lead_id', objeto: 'previa',
    buscar: "              where x ? 'lead_id' and not private.bases_carga_lead_ref(p_actor, p_rol, (x ->> 'lead_id')::uuid))\n",
    poner: "              where false)\n", cae: /^RP1 / },
  { nombre: 'el replay de un armado sin volver a juzgar los incluidos', objeto: 'previa',
    buscar: '                   and (case when e.motivo is null then private.bases_carga_lead_ref(p_actor, p_rol, u.id)\n',
    poner: '                   and (case when e.motivo is null then true\n', cae: /^RP3 / },
  { nombre: 'el replay de un armado sin volver a juzgar los excluidos por su estado', objeto: 'previa',
    buscar: '                             else (select private.base_gestion_lead_visible(p_actor, p_rol, l.vendedor_id, l.asignado_supervisor_id)\n                                     from crm.leads l where l.id = u.id) end) is not true) then\n',
    poner: '                             else true end) is not true) then\n', cae: /^RP5 / },
  { nombre: 'el respaldo fila a fila re-lanza la excepción tal cual (con su detail)', objeto: 'lote',
    buscar: "            raise exception using errcode = v_estado, message = pg_catalog.format('No se pudo cargar la fila %s (%s)', a_fila[i], v_estado);\n",
    poner: '            raise;\n', cae: /^T4 / },
  { nombre: 'el respaldo convierte el veto (P0429) en «ya existía»', objeto: 'lote',
    buscar: "          when sqlstate 'P0481' or sqlstate 'P0409' then", poner: "          when sqlstate 'P0481' or sqlstate 'P0409' or sqlstate 'P0429' then", cae: /^T2 / },
  { nombre: 'el replay sin comprobar que el actor sigue viendo la base', objeto: 'previa',
    buscar: '  if private.bases_carga_base_visible(p_actor, p_rol, (select b.supervisor_id from crm.bases_carga b where b.id = v_op.base_id)) is not true then\n',
    poner: '  if false then\n', cae: /^R2 / },
  { nombre: 'sin el CHECK del enfriamiento base_cargada > 0', ddl: 'alter table crm.enfriamiento_politica drop constraint enfriamiento_politica_base_cargada_dias_positivos;', cae: /^E16 / },
  { nombre: 'la respuesta lleva el nombre de la fila', objeto: 'lote',
    buscar: "'fila', x.fila, 'veredicto', x.ver,", poner: "'fila', x.fila, 'nombre', a_nombre[x.pos], 'veredicto', x.ver,", cae: /^D5 / },
  { nombre: 'sin el ámbito de la base (P0002)', objeto: 'lote',
    buscar: '  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then\n', poner: '  if not found then\n', cae: /^C2 / },
  { nombre: 'el espejo de la policy deja a Supervisión ver cualquier base', objeto: 'visible',
    buscar: "(p_rol = 'supervisor' and p_supervisor_id in (select private.vendedor_ids_visibles(p_actor)))", poner: "p_rol = 'supervisor'", cae: /^C2 / },
  { nombre: 'sin el tope de 5000 por base', objeto: 'lote', buscar: '  if v_base.filas_recibidas + v_n > v_max_base then\n', poner: '  if false then\n', cae: /^C15 / },
  { nombre: 'sin el tope por lote', objeto: 'lote', buscar: '  if v_n < 1 or v_n > v_max_lote then\n', poner: '  if v_n < 1 then\n', cae: /^C9 / },
  { nombre: 'carga en una base retirada', objeto: 'lote', buscar: '  if not v_base.activo then\n', poner: '  if false then\n', cae: /^C12 / },
  { nombre: 'carga en una base de origen crm', objeto: 'lote', buscar: "  if v_base.origen <> 'archivo' then\n", poner: '  if false then\n', cae: /^C13 / },
  { nombre: 'carga aunque el dueño no sea un supervisor activo', objeto: 'lote',
    buscar: "  if private.es_destino_crm_activo(v_base.supervisor_id, array['supervisor']::text[]) is not true then\n", poner: '  if false then\n', cae: /^C14 / },
  { nombre: 'el dormido nace con alta_manual true', objeto: 'lote', buscar: 'true, p_actor, false\n', poner: 'true, p_actor, true\n', cae: /^E1 / },
  // Envoltorio de identidad.
  { nombre: 'el envoltorio solo mira leads activos', objeto: 'existente',
    buscar: '   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)\n', poner: '   where l.activo and (l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni))\n', cae: /^D1 / },
  { nombre: 'el envoltorio solo mira el teléfono', objeto: 'existente',
    buscar: '   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)\n', poner: '   where l.telefono = p_telefono\n', cae: /^Z1 / },
  // Idempotencia, roles y supervisor dueño.
  { nombre: 'el replay no compara el md5 del pedido', objeto: 'previa', buscar: ' or v_op.pedido_md5 is distinct from p_pedido_md5', poner: '', cae: /^B17 / },
  { nombre: 'el analista puede cargar y armar', objeto: 'rol', buscar: "(v_rol in ('supervisor', 'gerencia'))", poner: "(v_rol in ('supervisor', 'gerencia', 'vendedor'))", cae: /^C1 / },
  { nombre: 'un supervisor crea la base de otro', objeto: 'destino',
    buscar: '    if p_supervisor_id is not null and p_supervisor_id is distinct from p_actor then\n', poner: '    if false then\n', cae: /^B5 / },
  { nombre: 'Gerencia sin supervisor se queda con la base', objeto: 'destino',
    buscar: "      raise exception 'Gerencia debe elegir el supervisor dueño de la base' using errcode = '22023';\n", poner: '      return p_actor;\n', cae: /^B6 / },
  { nombre: 'Gerencia elige a cualquiera como supervisor', objeto: 'destino',
    buscar: "    if private.es_destino_crm_activo(p_supervisor_id, array['supervisor']::text[]) is not true then\n", poner: '    if false then\n', cae: /^B7 / },
  // Armar desde el CRM (E12).
  { nombre: 'armar evalúa lo que no bloqueó, sin ámbito', objeto: 'armar',
    buscar: "             when not (en.id = any (v_bloqueados)) then\n               case when l.id is not null and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)\n                    then 'ocupado' else 'no_encontrado' end\n",
    poner: "             when l.id is null then 'no_encontrado'\n", cae: /^H7 / },
  { nombre: 'armar con el ámbito del ACTOR en vez del supervisor dueño (Gerencia lo ve todo)', objeto: 'armar',
    reemplazos: [['             and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)\n           order by l.id\n',
                  '             and private.base_gestion_lead_visible(p_actor, v_rol, l.vendedor_id, l.asignado_supervisor_id)\n           order by l.id\n'],
                 ["               case when l.id is not null and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)\n",
                  "               case when l.id is not null and private.base_gestion_lead_visible(p_actor, v_rol, l.vendedor_id, l.asignado_supervisor_id)\n"]], cae: /^H14b / },
  { nombre: 'el subárbol del dueño sin sus equipos (sin recursión)', objeto: 'subarbol',
    buscar: '    union\n    select e.perfil_id from crm.equipo e join subarbol s on e.supervisor_id = s.perfil_id\n', poner: '', cae: /^H7 / },
  { nombre: '«en el subárbol» sin la bandeja (lead sin analista)', objeto: 'ensubarbol',
    buscar: ' or (p_vendedor_id is null and p_asignado_supervisor_id = any (p_subarbol))', poner: '', cae: /^H14c / },
  { nombre: 'armar acepta arreglos con otro límite inferior', objeto: 'armar',
    buscar: '  if v_n > 0 and (pg_catalog.array_ndims(p_lead_ids) is distinct from 1 or pg_catalog.array_lower(p_lead_ids, 1) is distinct from 1) then\n',
    poner: '  if false then\n', cae: /^H6b / },
  { nombre: 'armar incluye inactivos', objeto: 'armar', buscar: "             when not l.activo then 'inactivo'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar incluye leads vivos', objeto: 'armar', buscar: "             when l.etapa <> 'descartado' then 'no_descartado'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar incluye No contactar', objeto: 'armar', buscar: "             when l.no_contactar then 'no_contactar'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar incluye datos_invalidos', objeto: 'armar', buscar: "             when l.motivo_descarte = 'datos_invalidos' then 'datos_invalidos'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar incluye leads en descanso', objeto: 'armar', buscar: "             when l.enfriado_hasta is not null and l.enfriado_hasta > v_hoy then 'en_descanso'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar incluye leads con seguimiento activo (B6)', objeto: 'armar',
    buscar: "             when private.base_gestion_en_gestion_hasta(l.id) is not null then 'en_gestion'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar no marca los ids repetidos', objeto: 'armar', buscar: "             when not en.primera then 'repetido'\n", poner: '', cae: /^H7 / },
  { nombre: 'armar sin tope de 2000', objeto: 'armar', buscar: '  if v_n < 1 or v_n > v_max then\n', poner: '  if v_n < 1 then\n', cae: /^H5 / },
  { nombre: 'armar toca el lead', objeto: 'armar',
    buscar: '  v_n_ins := pg_catalog.cardinality(v_insertados);\n', poner: "  v_n_ins := pg_catalog.cardinality(v_insertados);\n  update crm.leads set nota = coalesce(nota, '') || '.' where id = any (v_insertados);\n", cae: /^H10 / },
  { nombre: 'armar crea la base aunque no haya elegibles', objeto: 'armar', buscar: '  if v_n_ins = 0 then\n', poner: '  if false then\n', cae: /^H13 / },
  // Doble control a propósito: el chequeo previo «en otra base viva» Y el ON CONFLICT de la base viva (este cubre la carrera
  // entre dos armados, que la suite de una sesión no ve: lo prueba b8-concurrencia.sh). Quitando los dos, cae.
  // Solo los ve la concurrencia (una sesión no se espera a sí misma): MUTANTES_CONCURRENCIA, abajo (`--concurrencia`).
  { nombre: 'armar sin el chequeo previo NI el ON CONFLICT (doble)', objeto: 'armar',
    reemplazos: [["             when exists (select 1 from crm.base_carga_leads bl where bl.lead_id = l.id and bl.activo) then 'en_otra_base'\n", ''],
                 ['    on conflict (lead_id) where activo do nothing\n', '']], cae: /^H7 / },
  // Permisos.
  { nombre: 'EXECUTE del núcleo para authenticated', ddl: 'grant execute on function private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb) to authenticated;', cae: /^A2 / },
  { nombre: 'EXECUTE de una puerta para anon', ddl: 'grant execute on function crm.cargar_base_lote(uuid,uuid,jsonb) to anon;', cae: /^A1 / },
];

// r2 · Mutantes que SOLO ve la concurrencia: se aplican confirmados, se corre b8-concurrencia.sh (debe FALLAR en su escenario) y
// se restaura el cuerpo de la migración.
const MUTANTES_CONCURRENCIA = [
  { nombre: 'armar evalúa TODOS los ids con el ámbito (r1: también lo que no bloqueó)', objeto: 'armar',
    buscar: "             when not (en.id = any (v_bloqueados)) then\n               case when l.id is not null and private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)\n                    then 'ocupado' else 'no_encontrado' end\n",
    poner: "             when l.id is null or not private.bases_carga_en_subarbol(v_subarbol, l.vendedor_id, l.asignado_supervisor_id)\n               then 'no_encontrado'\n",
    cae: /FAIL \(12\)/ },
  { nombre: 'armar sin candado (el conjunto sin FOR UPDATE SKIP LOCKED)', objeto: 'armar',
    buscar: '             for update of l skip locked) b;', poner: '             ) b;', cae: /FAIL \((7|8|9|10|13)\)/ },
  { nombre: 'la fila de la base sin NOWAIT (el segundo lote espera)', objeto: 'lote',
    buscar: 'for update nowait;', poner: 'for update;', cae: /FAIL \(1\) lote B/ },
];

const correr = (ddl) => {
  // Reemplazo con FUNCIÓN: un texto de reemplazo interpretaría «$'» de los regex del SQL (p. ej. '^\+519[0-9]{8}$').
  const r = psql(suite.replace('-- @@MUTANTE@@', () => ddl));
  const lineas = (r.stdout || '').split('\n');
  return { status: r.status, fallos: lineas.filter((l) => l.startsWith('FAIL ')), total: lineas.find((l) => l.startsWith('TOTAL:')) ?? '(sin total)', err: (r.stderr || '').trim().split('\n').slice(-2).join(' | ') };
};

// En --concurrencia la suite no corre antes (el arnés de concurrencia confirma datos y la suite exige un banco sin bases).
const base = args.includes('--concurrencia') ? { status: 0, fallos: [], total: '(no corre en --concurrencia)', err: '' } : correr('-- sin mutante');
console.log(`suite sin mutante: ${base.total} (salida ${base.status})`);
if (base.status !== 0 || base.fallos.length) {
  for (const f of base.fallos) console.log(`  ${f}`);
  console.error(`ABORTADO: la suite sin mutante no pasa (${base.err})`);
  process.exit(1);
}
if (args.includes('--solo-suite')) process.exit(0);
if (args.includes('--concurrencia')) {
  const arnes = new URL('./b8-concurrencia.sh', AQUI).pathname;
  let vivosC = 0;
  for (const m of MUTANTES_CONCURRENCIA) {
    const original = FUENTES[m.objeto];
    if (original.split(m.buscar).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez`);
    const aplicar = psql(original.replace(m.buscar, () => m.poner));
    if (aplicar.status !== 0) throw new Error(`mutante «${m.nombre}»: no se aplicó (${aplicar.stderr})`);
    const r = spawnSync('bash', [arnes, '--puerto', String(puerto)], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });
    const restaurar = psql(original);
    if (restaurar.status !== 0) throw new Error(`no se restauró ${m.objeto}: ${restaurar.stderr}`);
    const fallos = (r.stdout || '').split('\n').filter((l) => l.startsWith('FAIL '));
    if (r.status !== 0 && fallos.some((l) => m.cae.test(l))) console.log(`CAE  ${m.nombre} — ${fallos.length} FAIL en la concurrencia, entre ellos ${fallos.filter((l) => m.cae.test(l)).map((l) => l.slice(5, 60)).join(' / ')}`);
    else { vivosC += 1; console.log(`VIVE ${m.nombre} — salida ${r.status}; FAIL: ${fallos.map((l) => l.slice(5, 60)).join(' / ') || 'ninguno'}`); }
  }
  console.log(vivosC === 0 ? `MUTANTES DE CONCURRENCIA: ${MUTANTES_CONCURRENCIA.length}/${MUTANTES_CONCURRENCIA.length} caen` : `MUTANTES DE CONCURRENCIA: ${vivosC} SOBREVIVEN`);
  process.exit(vivosC === 0 ? 0 : 1);
}

let vivos = 0;
for (const m of MUTANTES) {
  let ddl = m.ddl;
  if (m.objeto) {
    let fuente = FUENTES[m.objeto];
    for (const [buscar, poner] of m.reemplazos ?? [[m.buscar, m.poner]]) {
      if (fuente.split(buscar).length !== 2) throw new Error(`mutante «${m.nombre}»: el texto a cambiar no aparece exactamente una vez en ${m.objeto}`);
      fuente = fuente.replace(buscar, () => poner);
    }
    ddl = fuente;
  }
  const r = correr(ddl);
  const casos = r.fallos.map((l) => l.slice(5).split(' · esperado ')[0]);
  const cayoDonde = casos.some((c) => m.cae.test(c));
  if (r.status !== 0 && cayoDonde) console.log(`CAE  ${m.nombre} — ${r.total}; entre ellos el esperado (${casos.filter((c) => m.cae.test(c)).join(' / ').slice(0, 160)})`);
  else { vivos += 1; console.log(`VIVE ${m.nombre} — ${r.total}; salida ${r.status}; casos en FAIL: ${casos.join(' / ').slice(0, 300) || 'ninguno'} ${r.err}`); }
}
console.log(vivos === 0 ? `MUTANTES: ${MUTANTES.length}/${MUTANTES.length} caen` : `MUTANTES: ${vivos} de ${MUTANTES.length} SOBREVIVEN`);

// ── Reversa: sin deriva revierte (y se deshace con ROLLBACK); con CUALQUIER deriva posterior a B8 o con datos se NIEGA y la
// nombra, antes de borrar nada. Exige un banco SIN bases ni contactos cargados (p. ej. tras limpiar-entre-corridas.sql).
const reversa = readFileSync(new URL('./reversa-b8.sql', AQUI), 'utf8');
const ini = reversa.indexOf('\nbegin;\n');
const fin = reversa.lastIndexOf('commit;');
if (ini < 0 || fin < ini) throw new Error('reversa-b8.sql sin begin/commit');
const LINEA_AISLAMIENTO = 'set transaction isolation level read committed;\n';
const cuerpoReversa = reversa.slice(ini + '\nbegin;\n'.length, fin);
if (cuerpoReversa.split(LINEA_AISLAMIENTO).length !== 2) throw new Error('reversa-b8.sql: no encuentro UNA vez su set transaction');
const correrReversa = (deriva) => psql('begin;\n' + LINEA_AISLAMIENTO
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + deriva + '\n' + cuerpoReversa.replace(LINEA_AISLAMIENTO, () => '') + '\nrollback;\n');
const SUP1 = "(select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe')";
const comoSup1 = `select set_config('request.jwt.claim.sub', ${SUP1}::text, true), set_config('request.jwt.claims', json_build_object('sub', ${SUP1}, 'role', 'authenticated')::text, true);\n`;
const DERIVAS = [
  { nombre: 'el cuerpo del núcleo del lote cambiado', ddl: FUENTES.lote.replace('  return v_resp;\nend;', () => '  -- cambio posterior a B8\n  return v_resp;\nend;'), niega: /deriva en .*bases_carga_cargar_lote_core/ },
  { nombre: 'EXECUTE de una puerta para service_role', ddl: 'grant execute on function crm.crear_base(uuid,text,text,uuid,text) to service_role;', niega: /deriva en .*crm\.crear_base/ },
  { nombre: 'el comentario de una puerta cambiado', ddl: "comment on function crm.armar_base_crm(uuid,text,uuid,uuid[]) is 'otro';", niega: /deriva en .*crm\.armar_base_crm/ },
  { nombre: 'el disparador de la fecha deshabilitado', ddl: 'alter table crm.leads disable trigger trg_leads_zz_sello_descarte_base_cargada;', niega: /deriva en .*trigger/ },
  { nombre: 'el comentario del disparador de B8 cambiado (r2)', ddl: "comment on trigger trg_leads_zz_sello_descarte_base_cargada on crm.leads is 'otro';", niega: /deriva en .*trigger/ },
  { nombre: 'leads_before_insert cambiada después de B8', ddl: FUENTES.alta.replace('  return new;\nend;', () => '  -- cambio posterior\n  return new;\nend;'), niega: /deriva en .*leads_before_insert/ },
  { nombre: 'el comentario de sla_versionado cambiado', ddl: "comment on function private.trg_leads_sla_versionado() is 'otro';", niega: /deriva en .*trg_leads_sla_versionado/ },
  { nombre: 'disponibilidad con otra ACL', ddl: 'grant execute on function private.trg_leads_disponibilidad_atomica() to service_role;', niega: /deriva en .*trg_leads_disponibilidad_atomica/ },
  { nombre: 'el CHECK del enfriamiento cambiado (r1)', ddl: "alter table crm.enfriamiento_politica drop constraint enfriamiento_politica_base_cargada_dias_positivos, add constraint enfriamiento_politica_base_cargada_dias_positivos check (motivo <> 'base_cargada' or dias > 1);", niega: /deriva en .*check/ },
  { nombre: 'el CHECK del enfriamiento quitado (r1)', ddl: 'alter table crm.enfriamiento_politica drop constraint enfriamiento_politica_base_cargada_dias_positivos;', niega: /deriva en .*check/ },
  { nombre: 'el núcleo del ámbito del dueño cambiado (r1)', ddl: FUENTES.subarbol.replace('  select s.perfil_id from subarbol s\n', () => '  select s.perfil_id from subarbol s -- cambio\n'), niega: /deriva en .*bases_carga_subarbol/ },
  { nombre: 'una sobrecarga nueva del núcleo', ddl: "create function private.bases_carga_rol(p text) returns text language sql as 'select p';", niega: /numero de funciones de B8/ },
  { nombre: 'una función de B9 usa una puerta de B8', ddl: "create function private.b9_falsa() returns jsonb language sql as 'select crm.cargar_base_lote(null, null, null)';", niega: /usan las puertas o el nucleo de B8/ },
  { nombre: 'otra función toca la válvula', ddl: "create function private.valvula_falsa() returns text language sql as $f$ select set_config('crm.op_bases_carga', 'on', true) $f$;", niega: /otra funcion usa la valvula/ },
  { nombre: 'hay una base creada', ddl: comoSup1 + "set local role authenticated;\nselect crm.crear_base(gen_random_uuid(), 'R', 'archivo', null, 'r.csv');\nreset role;\n", niega: /hay bases, filas, recibos o contactos/ },
  { nombre: 'hay un contacto cargado', ddl: "select set_config('crm.op_bases_carga', 'on', true);\n"
      + `insert into crm.leads (nombre_completo, telefono, origen, etapa, motivo_descarte, asignado_supervisor_id, monto_estimado, moneda, creado_por) values ('R', '966710091', 'base_cargada', 'descartado', 'base_cargada', ${SUP1}, null, 'PEN', ${SUP1});\n`
      + "select set_config('crm.op_bases_carga', 'off', true);", niega: /hay bases, filas, recibos o contactos/ },
];
// r2 (rama con datos): lo que difiere entre el banco y producción en objetos AJENOS (comentarios de otros triggers) no afecta.
const CONTROLES = [
  { nombre: 'sin deriva', ddl: '-- sin deriva' },
  { nombre: 'otro comentario en un trigger ajeno (como difiere en producción)', ddl: "comment on trigger trg_leads_00_seguimiento_activo on crm.leads is 'comentario de otro entorno';" },
  { nombre: 'sin comentario en un trigger ajeno', ddl: 'comment on trigger trg_leads_zz_reapertura_solo_rpc on crm.leads is null;' },
  { nombre: 'comentario nuevo en un trigger ajeno que no tenía', ddl: "comment on trigger trg_leads_before_insert on crm.leads is 'comentario de otro entorno';" },
];
let controlOk = true;
for (const c of CONTROLES) {
  const r = correrReversa(c.ddl);
  const ok = r.status === 0 && /REVERSA B8 OK/.test(r.stderr || '');
  controlOk = controlOk && ok;
  console.log(ok ? `REVERSA control (${c.nombre}): revierte (REVERSA B8 OK, deshecho con ROLLBACK)` : `REVERSA control (${c.nombre}): FALLA (${(r.stderr || '').trim().split('\n').slice(-2).join(' | ')})`);
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
