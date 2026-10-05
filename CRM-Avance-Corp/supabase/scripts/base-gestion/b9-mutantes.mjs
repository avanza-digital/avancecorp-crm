// B9 · mutantes de la suite b9-repartir.sql: cada uno neutraliza UNA defensa de la migración 20261004222602 (rol, analista,
// motivos de «no se puede repartir», orden del bloque, faltantes, todo o nada, ya_asignado, B6 al mismo analista, ámbito,
// idempotencia y replay, recoger, estados de la lista, permisos, censo) y la suite tiene que FALLAR en el caso que la prueba.
// Si un mutante sobrevive, esa defensa NO está probada. Todo corre dentro de la transacción de la suite, que termina en
// ROLLBACK: el banco no cambia. Solo apunta a un banco LOCAL (127.0.0.1) con B7, B8 y B9 aplicadas y los actores de seed:demo;
// no acepta URL ni credenciales (PGPASSWORD del Postgres local, por defecto «postgres»).
// `--concurrencia` aplica (y CONFIRMA, luego restaura) cada mutante que solo se ve con dos sesiones y exige que
// b9-concurrencia.sh FALLE en su escenario. Escribe en el banco: limpiar después con limpiar-entre-corridas.sql.
// Al final, la reversa: sin deriva revierte (deshecho con ROLLBACK) y con cualquier deriva de lo PROPIO se niega y la nombra.
// Uso: node supabase/scripts/base-gestion/b9-mutantes.mjs --puerto 58122 [--solo-suite | --concurrencia]
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const AQUI = new URL('.', import.meta.url);
const args = process.argv.slice(2);
const puerto = Number(args[args.indexOf('--puerto') + 1]);
if (!args.includes('--puerto') || !Number.isInteger(puerto) || puerto < 1024) {
  console.error('Uso: b9-mutantes.mjs --puerto <puerto del Postgres local> [--solo-suite | --concurrencia]');
  process.exit(2);
}
const psql = (texto) => spawnSync('psql', ['-X', '-h', '127.0.0.1', '-p', String(puerto), '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { encoding: 'utf8', input: texto, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, PGPASSWORD: process.env.PGPASSWORD ?? 'postgres' } });

const aplicada = psql(`select (to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is not null
  and to_regprocedure('private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)') is not null)::int;`);
if (aplicada.status !== 0 || aplicada.stdout.trim() !== '1') {
  console.error(`ABORTADO: el banco de 127.0.0.1:${puerto} no tiene B9 aplicada (${(aplicada.stderr || aplicada.stdout).trim()})`);
  process.exit(2);
}

const suite = readFileSync(new URL('./b9-repartir.sql', AQUI), 'utf8');
if (suite.split('-- @@MUTANTE@@').length !== 2) throw new Error('la suite no tiene exactamente una línea @@MUTANTE@@');
const migracion = readFileSync(new URL('../../migrations/20261004222602_crm_bases_cargadas_repartir.sql', AQUI), 'utf8');
// El bloque create … $function$; de una función, como «create or replace» (misma firma: conserva dueño y ACL).
const bloque = (inicio) => {
  const i = migracion.indexOf(inicio);
  if (i < 0 || migracion.indexOf(inicio, i + 1) >= 0) throw new Error(`no encuentro UNA vez «${inicio}»`);
  const j = migracion.indexOf('$function$;', migracion.indexOf('$function$', i) + '$function$'.length) + '$function$;'.length;
  return migracion.slice(i, j).replace(/^create (or replace )?function/, () => 'create or replace function');
};
const FUENTES = {
  rol: bloque('create function private.bases_carga_reparto_rol('),
  analista: bloque('create function private.bases_carga_reparto_analista('),
  motivo: bloque('create function private.bases_carga_reparto_motivo('),
  hechos: bloque('create function private.bases_carga_reparto_hechos('),
  estado: bloque('create function private.bases_carga_reparto_estado('),
  repartir: bloque('create function private.bases_carga_repartir_core('),
  recoger: bloque('create function private.bases_carga_recoger_core('),
  contactos: bloque('create function private.bases_carga_contactos_core('),
  recogible: bloque('create function private.bases_carga_reparto_recogible('),
  constantes: bloque('create function private.bases_carga_reparto_constantes('),
  b6: bloque('create or replace function private.base_gestion_en_gestion_hasta('),
};

const MUTANTES = [
  // Rol y analista.
  { nombre: 'un analista (vendedor) también reparte', objeto: 'rol', buscar: "(v_rol in ('supervisor', 'gerencia'))", poner: "(v_rol in ('supervisor', 'gerencia', 'vendedor'))", cae: /^B3 / },
  { nombre: 'Supervisión reparte fuera del subárbol del dueño', objeto: 'analista',
    buscar: "  if p_rol is distinct from 'gerencia' and (p_analista_id = any (p_subarbol)) is not true then\n", poner: '  if false then\n', cae: /^C1 / },
  { nombre: 'el analista no tiene que estar activo ni ser vendedor', objeto: 'analista',
    buscar: "  if private.es_destino_crm_activo(p_analista_id, array['vendedor']::text[]) is not true then\n", poner: '  if false then\n', cae: /^C3 / },
  { nombre: 'el analista puede ser un supervisor', objeto: 'analista', buscar: "array['vendedor']::text[]", poner: "array['vendedor', 'supervisor']::text[]", cae: /^C4 / },
  { nombre: 'Gerencia también limitada al subárbol del dueño', objeto: 'analista',
    buscar: "  if p_rol is distinct from 'gerencia' and (p_analista_id = any (p_subarbol)) is not true then\n", poner: '  if (p_analista_id = any (p_subarbol)) is not true then\n', cae: /^C6 / },
  // Motivos de «no se puede repartir» (una sola definición).
  { nombre: 'reparte retirados', objeto: 'motivo', buscar: "           when p_activo is not true then 'inactivo'\n", poner: '', cae: /^E8 / },
  { nombre: 'reparte lo que salió del ámbito del dueño', objeto: 'motivo', buscar: "           when p_en_ambito is not true then 'fuera_de_ambito'\n", poner: '', cae: /^F13 / },
  { nombre: 'reparte lo que salió del descarte', objeto: 'motivo', buscar: "           when p_etapa is distinct from 'descartado' then 'no_descartado'\n", poner: '', cae: /^F14 / },
  { nombre: 'reparte un No contactar', objeto: 'motivo', buscar: "           when p_no_contactar is not false then 'no_contactar'\n", poner: '', cae: /^F1 / },
  { nombre: 'reparte un contacto en descanso', objeto: 'motivo', buscar: "           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'\n", poner: '', cae: /^F3 / },
  { nombre: 'ignora el seguimiento activo (B6)', objeto: 'motivo', buscar: "           when p_en_gestion is true then 'en_gestion'\n", poner: '', cae: /^F8 / },
  // Bloque.
  { nombre: 'el bloque elige los MÁS NUEVOS', objeto: 'repartir',
    buscar: 'pg_catalog.row_number() over (order by bl.creado_en, l.creado_en, l.id)', poner: 'pg_catalog.row_number() over (order by bl.creado_en desc, l.creado_en desc, l.id desc)', cae: /^D2 / },
  { nombre: 'el bloque reparte aunque no alcancen', objeto: 'repartir',
    buscar: "    if v_disponibles < v_total then\n      raise exception 'Solo hay % contactos disponibles para repartir en esta base (pediste %)', v_disponibles, v_total\n        using errcode = '22023', detail = v_disponibles::text;\n    end if;\n",
    poner: '', cae: /^D13 / },
  { nombre: 'el detail de los faltantes no es «disponibles»', objeto: 'repartir', buscar: 'detail = v_disponibles::text;', poner: 'detail = v_total::text;', cae: /^D13 / },
  { nombre: 'el bloque no informa los omitidos', objeto: 'repartir',
    buscar: "              from (select x.l, x.m from unnest(a_ev_lead, a_ev_motivo) as x(l, m) where x.m is not null\n", poner: "              from (select x.l, x.m from unnest(a_ev_lead, a_ev_motivo) as x(l, m) where false\n", cae: /^E2 / },
  { nombre: 'el bloque reparte un contacto con un intento DURANTE la operación (lo heredaría el analista)', objeto: 'repartir',
    buscar: "           and not exists (select 1 from crm.actividades a\n                            where a.lead_id = l.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())\n", poner: '', cae: /^H9y / },
  // Individual.
  { nombre: 'el individual no exige que el contacto sea visible (P0002), ni antes ni después del candado', objeto: 'repartir',
    reemplazos: [["                where not exists (select 1 from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.lead_id = u.id)\n                   or not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then",
                  "                where not exists (select 1 from crm.base_carga_leads bl where bl.base_id = p_base_id and bl.activo and bl.lead_id = u.id)) then"],
                 ["    if exists (select 1 from pg_catalog.unnest(a_lead) as u(id) where not private.bases_carga_lead_ref(p_actor, v_rol, u.id)) then", '    if false then']],
    cae: /^F12 / },
  { nombre: 'el individual reparte un contacto con un intento DURANTE la operación', objeto: 'repartir',
    buscar: "\n                   or exists (select 1 from crm.actividades a\n                               where a.lead_id = u.id and a.metadata ->> 'evento' = 'intento_base' and a.creado_en >= pg_catalog.statement_timestamp())", poner: '', cae: /^H9x / },
  { nombre: 'Gerencia no puede volver a repartir lo que B9 dio fuera del equipo del dueño', objeto: 'repartir',
    buscar: "\n                                                       or (c.bl_analista is not null and c.bl_analista = c.vendedor_id),", poner: ',', cae: /^F18 / },
  { nombre: 'el individual no es todo o nada (salta los rechazados)', objeto: 'repartir',
    buscar: "    if pg_catalog.jsonb_array_length(v_rechazos) > 0 then\n", poner: '    if false then\n', cae: /^F2 / },
  { nombre: 'el individual no reconoce el ya_asignado', objeto: 'repartir',
    buscar: '      elsif c.bl_analista is not distinct from c.analista_id and c.vendedor_id is not distinct from c.analista_id then\n', poner: '      elsif false then\n', cae: /^F4 / },
  { nombre: 'el individual exige «sin seguimiento activo» también para darlo al MISMO analista', objeto: 'repartir',
    buscar: '                                                     c.vendedor_id is distinct from c.analista_id\n                                                       and private.base_gestion_en_gestion_hasta(c.lead_id) is not null, v_hoy);',
    poner: '                                                     private.base_gestion_en_gestion_hasta(c.lead_id) is not null, v_hoy);', cae: /^F9 / },
  // Base y efectos.
  { nombre: 'repartir no exige ver la base', objeto: 'repartir',
    buscar: "  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then\n    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';\n  end if;\n  begin\n    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;\n  exception when lock_not_available then\n    raise exception 'Hay otra operación en curso de esta base; reintenta' using errcode = '55P03';\n  end;\n  if not v_base.activo then\n    raise exception 'La base está retirada: no se reparte'",
    poner: "  if not found then\n    raise exception 'Base no encontrada o fuera de tu ámbito' using errcode = 'P0002';\n  end if;\n  begin\n    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;\n  exception when lock_not_available then\n    raise exception 'Hay otra operación en curso de esta base; reintenta' using errcode = '55P03';\n  end;\n  if not v_base.activo then\n    raise exception 'La base está retirada: no se reparte'", cae: /^B22 / },
  { nombre: 'repartir en una base retirada', objeto: 'repartir', buscar: "  if not v_base.activo then\n    raise exception 'La base está retirada: no se reparte' using errcode = '22023';\n  end if;\n", poner: '', cae: /^B24 / },
  { nombre: 'repartir con el dueño inactivo', objeto: 'repartir',
    buscar: "    raise exception 'El supervisor dueño de la base ya no está activo: no se puede repartir' using errcode = '22023';", poner: '    null;', cae: /^B25 / },
  { nombre: 'el lead conserva la bandeja (el guard de tenencia lo rechaza)', objeto: 'repartir', buscar: 'set vendedor_id = x.analista, asignado_supervisor_id = null', poner: 'set vendedor_id = x.analista', cae: /^D1 / },
  { nombre: 'la pertenencia no recibe el analista', objeto: 'repartir', buscar: 'set analista_id = x.analista, asignado_en = v_ahora, asignado_por = p_actor', poner: 'set asignado_por = asignado_por', cae: /^D4 / },
  // Idempotencia.
  { nombre: 'el md5 del pedido ignora el reparto', objeto: 'repartir',
    buscar: "pg_catalog.jsonb_build_object('tipo', 'repartir', 'base_id', p_base_id, 'reparto', p_reparto)", poner: "pg_catalog.jsonb_build_object('tipo', 'repartir', 'base_id', p_base_id)", cae: /^D12 / },
  { nombre: 'el replay no vuelve a juzgar las referencias del recibo', objeto: 'repartir',
    buscar: "                where x ->> 'lead_id' is not null and not private.bases_carga_lead_ref(p_actor, v_rol, (x ->> 'lead_id')::uuid)) then",
    poner: "                where false) then", cae: /^I3 / },
  // Recoger.
  { nombre: 'recoger también lo tocado (analista activo)', objeto: 'recogible', buscar: '(p_baja is true or not h.intento)', poner: 'true', cae: /^G9b / },
  { nombre: 'recoger de un analista de baja exige «sin intento»', objeto: 'recogible', buscar: '(p_baja is true or not h.intento)', poner: '(not h.intento)', cae: /^G9 / },
  { nombre: 'recoger ignora el seguimiento activo (B6)', objeto: 'recogible', buscar: "\n                           and private.base_gestion_en_gestion_hasta(l.id) is null) is true", poner: ') is true', cae: /^G8 / },
  { nombre: 'recoger deshace lo movido por otra vía', objeto: 'recogible', buscar: " and l.vendedor_id = p_analista_id\n", poner: '\n', cae: /^G1 / },
  { nombre: 'recoger lo que salió del descarte', objeto: 'recogible', buscar: "(l.activo and l.etapa = 'descartado' and", poner: '(l.activo and', cae: /^H10 / },
  { nombre: 'recoger retirados', objeto: 'recogible', buscar: "(l.activo and l.etapa = 'descartado'", poner: "(l.etapa = 'descartado'", cae: /^H10 / },
  { nombre: 'recoger a la bandeja del ACTOR (no del dueño)', objeto: 'recoger', buscar: 'set vendedor_id = null, asignado_supervisor_id = v_base.supervisor_id', poner: 'set vendedor_id = null, asignado_supervisor_id = p_actor', cae: /^G12 / },
  { nombre: 'recoger de un analista de otro equipo', objeto: 'recoger',
    buscar: "  if v_rol is distinct from 'gerencia' and (p_analista_id = any (v_subarbol)) is not true then\n", poner: '  if false then\n', cae: /^G5 / },
  { nombre: 'recoger sin tope', objeto: 'recoger', buscar: '    v_falta := v_max - pg_catalog.cardinality(v_recoger);', poner: '    v_falta := 1000000 - pg_catalog.cardinality(v_recoger);', cae: /^G10 / },
  { nombre: 'recoger no exige ver la base', objeto: 'recoger',
    buscar: "  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then", poner: '  if not found then', cae: /^B27 / },
  { nombre: 'recoger con el dueño inactivo', objeto: 'recoger',
    buscar: "    raise exception 'El supervisor dueño de la base ya no está activo: no se puede recoger' using errcode = '22023';", poner: '    null;', cae: /^G11 / },
  { nombre: '«sin intento» cuenta intentos de ANTES del reparto', objeto: 'hechos', buscar: '     and a.creado_en >= p_desde;', poner: ';', cae: /^H9 / },
  // r2 · presupuesto de candados (Codex r2) y la regla de B6 afinada.
  { nombre: 'r2: el bloque no aborta al agotar el presupuesto de candados', objeto: 'repartir',
    buscar: "      if v_tomados >= v_presupuesto then\n        raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';\n      end if;\n", poner: '', cae: /^P1 / },
  { nombre: 'r2: el bloque solo cuenta los aceptados (no los rechazados bajo candado)', objeto: 'repartir',
    buscar: '      v_tomados := v_tomados + pg_catalog.cardinality(v_lote);\n', poner: '', cae: /^P1 / },
  { nombre: 'r2: recoger no aborta al agotar el presupuesto de candados', objeto: 'recoger',
    buscar: "    if v_tomados >= v_presupuesto then\n      raise exception 'Los contactos están cambiando; reintenta' using errcode = '55P03';\n    end if;\n", poner: '', cae: /^P4 / },
  { nombre: 'r2: recoger solo cuenta los aceptados', objeto: 'recoger',
    buscar: '    v_tomados := v_tomados + pg_catalog.cardinality(v_lote);\n', poner: '', cae: /^P4 / },
  { nombre: 'r2: holgura de candados enorme', objeto: 'constantes', buscar: 'select 500, 100, 50;', poner: 'select 500, 100, 100000;', cae: /^P1 / },
  { nombre: 'r2: B6 lee la rellamada de la columna del lead (la del dueño anterior)', objeto: 'b6',
    buscar: "               (i.proxima at time zone 'America/Lima')::date) as hasta", poner: "               (l.proxima_llamada_en at time zone 'America/Lima')::date) as hasta", cae: /^R8 / },
  { nombre: 'r2: una «reasignación» sin cambio de vendedor corta', objeto: 'b6',
    buscar: "\n             and (r.metadata->>'vendedor_anterior') is distinct from (r.metadata->>'vendedor_nuevo')", poner: '', cae: /^R10 / },
  // r1 · la regla nueva de B6 (Miguel, 04/10).
  { nombre: 'B6 vuelve a contar desde el descarte (la llamada de S1 antes del reparto bloquea a V1)', objeto: 'b6',
    buscar: '             and (t.desde is null or a.creado_en >= t.desde)\n', poner: '', cae: /^R1 / },
  // La lista y sus estados.
  { nombre: 'la lista trae contactos fuera del ámbito o retirados', objeto: 'contactos', buscar: '       and private.bases_carga_lead_ref(p_actor, v_rol, l.id)\n', poner: '', cae: /^E5 / },
  { nombre: 'la lista invierte el filtro', objeto: 'contactos', buscar: "(v_filtro = 'sin_repartir') = (bl.analista_id is null)", poner: "(v_filtro = 'sin_repartir') = (bl.analista_id is not null)", cae: /^H3 / },
  { nombre: 'la lista con filtro NULL trae todos', objeto: 'contactos', buscar: "coalesce(p_estado, 'sin_repartir')", poner: "coalesce(p_estado, 'todos')", cae: /^H4 / },
  { nombre: 'la lista no exige ver la base', objeto: 'contactos', buscar: "  if not found or not private.bases_carga_base_visible(p_actor, v_rol, v_sup) then", poner: '  if not found then', cae: /^B29 / },
  { nombre: 'estado: sin «no_contactar»', objeto: 'estado', buscar: "           when p_no_contactar is not false then 'no_contactar'\n", poner: '', cae: /^H1 / },
  { nombre: 'estado: repartido y otro lo tiene no es «movido»', objeto: 'estado', buscar: "           when p_analista_id is not null and p_vendedor_id is distinct from p_analista_id then 'movido_otra_via'\n", poner: '', cae: /^H1 / },
  { nombre: 'estado: sin repartir fuera del ámbito no es «movido»', objeto: 'estado', buscar: "           when p_analista_id is null and p_en_ambito is not true then 'movido_otra_via'\n", poner: '', cae: /^E6 / },
  { nombre: 'estado: sin «cita»', objeto: 'estado', buscar: "           when p_etapa is distinct from 'descartado' and p_cita is true then 'cita'\n", poner: '', cae: /^H1 / },
  { nombre: 'estado: sin «reactivado»', objeto: 'estado', buscar: "           when p_etapa is distinct from 'descartado' and p_reactivado is true then 'reactivado'\n", poner: '', cae: /^H1 / },
  { nombre: 'estado: sin «en_descanso»', objeto: 'estado', buscar: "           when p_enfriado_hasta is not null and p_enfriado_hasta > p_hoy then 'en_descanso'\n", poner: '', cae: /^H1 / },
  { nombre: 'estado: un sin repartir en gestión (B6) se ve «sin_repartir»', objeto: 'estado', buscar: "case when p_en_gestion is true then 'trabajado' else 'sin_repartir' end", poner: "'sin_repartir'", cae: /^E5 / },
  { nombre: 'estado: un repartido con intento se ve «sin_tocar»', objeto: 'estado', buscar: "           when p_intento is true then 'trabajado'\n", poner: '', cae: /^H1 / },
  // Permisos y censo.
  { nombre: 'EXECUTE del núcleo para authenticated', ddl: 'grant execute on function private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb) to authenticated;', cae: /^A2 / },
  { nombre: 'EXECUTE de una puerta para anon', ddl: 'grant usage on schema crm to anon; grant execute on function crm.repartir_base(uuid,uuid,jsonb) to anon;', cae: /^A1 / },
  // r3: el corte del candado se apoya en que la API no puede escribir una «reasignación» ni un intento de la base.
  { nombre: 'r3: la policy de INSERT de actividades admite la «reasignación» (sin excluir tipos)', ddl: 'alter policy actividades_insert on crm.actividades with check (creado_por = (select auth.uid()));', cae: /^Q11 / },
  { nombre: 'r3: sin el sello de las actividades de la base (el intento falso entra)', ddl: 'alter table crm.actividades disable trigger trg_00_actividades_base_gestion_solo_nucleo;', cae: /^Q12 / },
  { nombre: 'una función de B9 entra al censo (count( junto a crm.leads)', objeto: 'contactos',
    buscar: "  v_subarbol := array(select private.bases_carga_subarbol(v_sup));\n  -- Solo contactos", poner: "  perform count(*) from crm.leads where false;\n  v_subarbol := array(select private.bases_carga_subarbol(v_sup));\n  -- Solo contactos", cae: /^A3 / },
];

// Mutantes que SOLO ve la concurrencia: se aplican confirmados, se corre b9-concurrencia.sh (debe FALLAR en su escenario) y se
// restaura el cuerpo de la migración.
const MUTANTES_CONCURRENCIA = [
  { nombre: 'la fila de la base sin NOWAIT (la segunda operación espera)', objeto: 'repartir',
    buscar: "    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update nowait;", poner: "    select b.* into v_base from crm.bases_carga b where b.id = p_base_id for update;", cae: /FAIL \(1\)/ },
  { nombre: 'el bloque bloquea sin SKIP LOCKED (espera al lead tomado)', objeto: 'repartir',
    buscar: "               limit least(v_falta, v_presupuesto - v_tomados)\n                 for update of l skip locked) b;", poner: "               limit least(v_falta, v_presupuesto - v_tomados)\n                 for update of l) b;", cae: /FAIL \(4\)/ },
  { nombre: 'r1: el bloque bloquea TODOS los elegibles (no solo los que faltan)', objeto: 'repartir',
    buscar: "               limit least(v_falta, v_presupuesto - v_tomados)\n                 for update of l skip locked) b;", poner: "                 for update of l skip locked) b;", cae: /FAIL \(13\)/ },
  { nombre: 'el individual no falla con un contacto tomado (espera)', objeto: 'repartir',
    buscar: "                where not (u.id = any (v_bloqueados))\n", poner: "                where false\n", cae: /FAIL \(3\)/ },
  { nombre: 'repartir sin exigir READ COMMITTED', objeto: 'repartir',
    buscar: "  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then\n    raise exception 'Repartir requiere", poner: "  if false then\n    raise exception 'Repartir requiere", cae: /FAIL \(10\)/ },
  { nombre: 'recoger sin SKIP LOCKED (espera al lead tomado)', objeto: 'recoger',
    buscar: "             limit least(v_falta, v_presupuesto - v_tomados)\n               for update of l skip locked) b;", poner: "             limit least(v_falta, v_presupuesto - v_tomados)\n               for update of l) b;", cae: /FAIL \(8\)/ },
  { nombre: 'r1: recoger bloquea también lo que no se recoge', objeto: 'recoger',
    buscar: "              join unnest(v_recogibles) with ordinality as p(id, o) on p.id = l.id",
    poner: "              join unnest(array(select bl2.lead_id from crm.base_carga_leads bl2 where bl2.base_id = p_base_id and bl2.activo and bl2.analista_id = p_analista_id order by bl2.lead_id)) with ordinality as p(id, o) on p.id = l.id",
    cae: /FAIL \(14\)/ },
  { nombre: 'r2: el presupuesto de candados no cuenta los rechazados (la carrera acumula candados)', objeto: 'repartir',
    buscar: '      v_tomados := v_tomados + pg_catalog.cardinality(v_lote);\n', poner: '', cae: /FAIL \(17\)/ },
];

const correr = (ddl) => {
  // Reemplazo con FUNCIÓN: un texto de reemplazo interpretaría «$'» de los regex del SQL.
  const r = psql(suite.replace('-- @@MUTANTE@@', () => ddl));
  const lineas = (r.stdout || '').split('\n');
  return { status: r.status, fallos: lineas.filter((l) => l.startsWith('FAIL ')), total: lineas.find((l) => l.startsWith('TOTAL:')) ?? '(sin total)', err: (r.stderr || '').trim().split('\n').slice(-2).join(' | ') };
};

const base = args.includes('--concurrencia') ? { status: 0, fallos: [], total: '(no corre en --concurrencia)', err: '' } : correr('-- sin mutante');
console.log(`suite sin mutante: ${base.total} (salida ${base.status})`);
if (base.status !== 0 || base.fallos.length) {
  for (const f of base.fallos) console.log(`  ${f}`);
  console.error(`ABORTADO: la suite sin mutante no pasa (${base.err})`);
  process.exit(1);
}
if (args.includes('--solo-suite')) process.exit(0);
if (args.includes('--concurrencia')) {
  const arnes = new URL('./b9-concurrencia.sh', AQUI).pathname;
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
    if (r.status !== 0 && fallos.some((l) => m.cae.test(l))) console.log(`CAE  ${m.nombre} — ${fallos.length} FAIL en la concurrencia, entre ellos ${fallos.filter((l) => m.cae.test(l)).map((l) => l.slice(5, 70)).join(' / ')}`);
    else { vivosC += 1; console.log(`VIVE ${m.nombre} — salida ${r.status}; FAIL: ${fallos.map((l) => l.slice(5, 70)).join(' / ') || 'ninguno'}`); }
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

// ── Reversa: sin deriva revierte (y se deshace con ROLLBACK); con una deriva de lo PROPIO se NIEGA y la nombra, antes de borrar.
// Lo AJENO no tiene huellas de entorno: cambiar un comentario o una función ajena NO la niega (solo se exige que la reversa no
// lo cambie).
const reversa = readFileSync(new URL('./reversa-b9.sql', AQUI), 'utf8');
const ini = reversa.indexOf('\nbegin;\n');
const fin = reversa.lastIndexOf('commit;');
if (ini < 0 || fin < ini) throw new Error('reversa-b9.sql sin begin/commit');
const LINEA_AISLAMIENTO = 'set transaction isolation level read committed;\n';
const cuerpoReversa = reversa.slice(ini + '\nbegin;\n'.length, fin);
if (cuerpoReversa.split(LINEA_AISLAMIENTO).length !== 2) throw new Error('reversa-b9.sql: no encuentro UNA vez su set transaction');
const correrReversa = (deriva) => psql('begin;\n' + LINEA_AISLAMIENTO
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + deriva + '\n' + cuerpoReversa.replace(LINEA_AISLAMIENTO, () => '') + '\nrollback;\n');
const DERIVAS = [
  { nombre: 'el cuerpo del núcleo de repartir cambiado', ddl: FUENTES.repartir.replace('  return v_resp;\nend;', () => '  -- cambio posterior a B9\n  return v_resp;\nend;'), niega: /deriva en .*bases_carga_repartir_core/ },
  { nombre: 'EXECUTE de una puerta para service_role', ddl: 'grant execute on function crm.recoger_de_base(uuid,uuid,uuid) to service_role;', niega: /deriva en .*crm\.recoger_de_base/ },
  { nombre: 'el comentario de una puerta cambiado', ddl: "comment on function crm.contactos_de_base(uuid,text) is 'otro';", niega: /deriva en .*crm\.contactos_de_base/ },
  { nombre: 'la definición de estado cambiada', ddl: FUENTES.estado.replace("'sin_tocar'", () => "'sin_tocar' -- cambio"), niega: /deriva en .*bases_carga_reparto_estado/ },
  { nombre: 'la ayudante de B6 cambiada después de B9', ddl: FUENTES.b6.replace('    ) x\n', () => '    ) x -- cambio\n'), niega: /deriva en .*base_gestion_en_gestion_hasta/ },
  { nombre: 'una sobrecarga nueva del núcleo de B9', ddl: "create function private.bases_carga_reparto_rol(p text) returns text language sql as 'select p';", niega: /numero de funciones de B9/ },
  { nombre: 'una función de B10 usa una puerta de B9', ddl: "create function private.b10_falsa() returns setof record language sql as 'select * from crm.contactos_de_base(null, null)';", niega: /usan las puertas o el nucleo de B9/ },
  { nombre: 'una vista usa B9', ddl: "create view crm.b10_vista_falsa as select private.bases_carga_reparto_motivo(true, true, 'descartado', false, null, false, current_date) as m;", niega: /hay vistas que usan B9/ },
];
const CONTROLES = [
  { nombre: 'sin deriva', ddl: '-- sin deriva' },
  { nombre: 'otro comentario en un trigger ajeno (como difiere en producción)', ddl: "comment on trigger trg_leads_00_seguimiento_activo on crm.leads is 'comentario de otro entorno';" },
  { nombre: 'comentario cambiado en una función ajena de B8', ddl: "comment on function crm.cargar_base_lote(uuid,uuid,jsonb) is 'comentario de otro entorno';" },
  { nombre: 'con datos: un reparto confirmado en la transacción (la reversa no se niega ni toca filas)', ddl: '-- el reparto lo hace la comprobación de datos de abajo' },
];
let controlOk = true;
for (const c of CONTROLES) {
  const r = correrReversa(c.ddl);
  const ok = r.status === 0 && /REVERSA B9 OK/.test(r.stderr || '');
  controlOk = controlOk && ok;
  console.log(ok ? `REVERSA control (${c.nombre}): revierte (REVERSA B9 OK, deshecho con ROLLBACK)` : `REVERSA control (${c.nombre}): FALLA (${(r.stderr || '').trim().split('\n').slice(-2).join(' | ')})`);
}
// Con datos: una base con un contacto repartido (como sup1) y la reversa en la MISMA transacción: revierte y las filas quedan.
const SUP1 = "(select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe')";
const VEND1 = "(select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe')";
const conDatos = psql('begin;\n' + LINEA_AISLAMIENTO
  + `select set_config('request.jwt.claim.sub', ${SUP1}::text, true), set_config('request.jwt.claims', json_build_object('sub', ${SUP1}, 'role', 'authenticated')::text, true);\n`
  + `create temp table _b on commit drop as select (private.bases_carga_crear_core(${SUP1}, gen_random_uuid(), 'REVERSA B9 DATOS', 'archivo', null, 'r.csv')->>'base_id')::uuid id;\n`
  + `select private.bases_carga_cargar_lote_core(${SUP1}, gen_random_uuid(), (select id from _b), '[{"fila":1,"nombre":"R uno","telefono":"966990091"}]'::jsonb) is not null;\n`
  + `select private.bases_carga_repartir_core(${SUP1}, gen_random_uuid(), (select id from _b), jsonb_build_object('modo','bloque','asignaciones',jsonb_build_array(jsonb_build_object('analista_id', ${VEND1}, 'cantidad', 1)))) is not null;\n`
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + cuerpoReversa.replace(LINEA_AISLAMIENTO, () => '')
  + `\nselect 'FILAS ' || (select count(*) from crm.base_carga_leads bl where bl.base_id = (select id from _b) and bl.analista_id = ${VEND1})
     || ' ' || (select count(*) from crm.leads l where l.telefono = '+51966990091' and l.vendedor_id = ${VEND1});\nrollback;\n`);
const datosOk = conDatos.status === 0 && /REVERSA B9 OK: .* [1-9][0-9]* contactos repartidos/.test(conDatos.stderr || '') && /FILAS 1 1/.test(conDatos.stdout || '');
controlOk = controlOk && datosOk;
console.log(datosOk ? 'REVERSA con datos: revierte, avisa los contactos repartidos y la pertenencia y el lead quedan como estaban'
  : `REVERSA con datos: FALLA (${(conDatos.stderr || '').trim().split('\n').slice(-2).join(' | ')} ${(conDatos.stdout || '').trim().split('\n').slice(-1)})`);
let niegan = 0;
for (const d of DERIVAS) {
  const r = correrReversa(d.ddl);
  const err = (r.stderr || '').trim().split('\n').filter((l) => l.includes('ERROR')).join(' | ');
  if (r.status !== 0 && d.niega.test(err)) { niegan += 1; console.log(`NIEGA ${d.nombre} — ${err.slice(0, 160)}`); }
  else console.log(`PASA  ${d.nombre} — la reversa NO se negó como debía (salida ${r.status}) ${err.slice(0, 200)}`);
}
console.log(`REVERSA: ${niegan}/${DERIVAS.length} derivas rechazadas${controlOk ? ' · controles OK' : ' · CONTROL FALLA'}`);

// ── r1 (Codex P2): el PREFLIGHT de la migración se niega si un disparador del que depende cambió su DEFINICIÓN (un homónimo con
// WHEN (false), otro evento) o si la ayudante de B6 ya no es la de B6. Se corre tras la reversa (estado = B8 + B6), en una
// transacción deshecha; el control sin deriva pasa.
const pi = migracion.indexOf('do $preflight$');
const pf = migracion.indexOf('$preflight$;', pi + 'do $preflight$'.length) + '$preflight$;'.length;
if (pi < 0 || pf < pi) throw new Error('la migración no tiene su bloque $preflight$');
const preflight = migracion.slice(pi, pf);
const correrPreflight = (deriva) => psql('begin;\n' + LINEA_AISLAMIENTO
  + "select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);\n"
  + cuerpoReversa.replace(LINEA_AISLAMIENTO, () => '') + '\n' + deriva + '\n' + preflight + '\nrollback;\n');
const DERIVAS_PREFLIGHT = [
  { nombre: 'trg_01_gestion_lead_serializada homónimo con WHEN (false)', ddl: 'drop trigger trg_01_gestion_lead_serializada on crm.actividades; create trigger trg_01_gestion_lead_serializada before insert on crm.actividades for each row when (false) execute function private.trg_gestion_lead_serializada();' },
  { nombre: 'trg_leads_reasignacion solo para UPDATE OF etapa', ddl: 'drop trigger trg_leads_reasignacion on crm.leads; create trigger trg_leads_reasignacion before update of etapa on crm.leads for each row execute function private.trg_leads_reasignacion();' },
  { nombre: 'el candado B6 con otro WHEN', ddl: "drop trigger trg_leads_00_seguimiento_activo on crm.leads; create trigger trg_leads_00_seguimiento_activo before update on crm.leads for each row when (old.etapa = 'nuevo') execute function private.trg_leads_guard_seguimiento_activo();" },
  { nombre: 'el guard de tenencia deshabilitado', ddl: 'alter table crm.leads disable trigger trg_leads_00_guard_tenencia;' },
  { nombre: 'la ayudante de B6 con otro comentario', ddl: "comment on function private.base_gestion_en_gestion_hasta(uuid) is 'otro';" },
];
const ctl = correrPreflight('-- sin deriva');
const ctlOk = ctl.status === 0 && !/ERROR/.test(ctl.stderr || '');
console.log(ctlOk ? 'PREFLIGHT control (tras la reversa, sin deriva): pasa' : `PREFLIGHT control: FALLA (${(ctl.stderr || '').trim().split('\n').slice(-2).join(' | ')})`);
let niegaPre = 0;
for (const d of DERIVAS_PREFLIGHT) {
  const r = correrPreflight(d.ddl);
  const err = (r.stderr || '').trim().split('\n').filter((l) => l.includes('ERROR')).join(' | ');
  if (r.status !== 0 && /PREFLIGHT B9/.test(err)) { niegaPre += 1; console.log(`NIEGA (preflight) ${d.nombre}`); }
  else console.log(`PASA  (preflight) ${d.nombre} — el preflight NO se negó (salida ${r.status}) ${err.slice(0, 200)}`);
}
console.log(`PREFLIGHT: ${niegaPre}/${DERIVAS_PREFLIGHT.length} derivas rechazadas${ctlOk ? ' · control OK' : ' · CONTROL FALLA'}`);
process.exit(vivos === 0 && controlOk && niegan === DERIVAS.length && ctlOk && niegaPre === DERIVAS_PREFLIGHT.length ? 0 : 1);
