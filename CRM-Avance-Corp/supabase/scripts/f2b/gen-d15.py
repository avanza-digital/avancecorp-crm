# gen-d15.py — F2.b prerrequisito de activación [D-15]: el botón «Reabrir» del CRM pasa por una puerta SQL.
# Genera la migración 20260906150000, su reversa y el registro. No transforma ninguna función viva: crea
# crm.reabrir_lead_fn(uuid) (gemela de deshacer_descarte/rescatar_descartes de D-13, con el ámbito de la policy
# leads_update) y ancla las PREMISAS que reutiliza a las huellas de producción (huellas-d15-prod.txt).
# Uso: python3 gen-d15.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda s: hashlib.md5(s.encode('utf-8')).hexdigest()
VER = '20260906150000'; NAME = f'{VER}_crm_f2b_d15_reabrir_lead_por_puerta'; ADV = 'crm_f2b_d15_reabrir_lead_por_puerta'
FIRMA = 'crm.reabrir_lead_fn(uuid)'
# md5(pg_get_functiondef) en PRODUCCIÓN (= banco-f7, contrastado el 06/09) de lo que la puerta reutiliza o presupone.
H = {l.split()[0]: l.split()[1] for l in (S/'huellas-d15-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')}
TRG = {  # trigger: (tgtype esperado: BEFORE=2 | UPDATE=16), texto del error
  'trg_leads_zz_reapertura_solo_rpc': 'el trigger «reabrir solo por RPC» (D-13)',
  'trg_leads_cambio_etapa': 'el trigger que anota la actividad «cambio_etapa»',
  'trg_leads_00_disponibilidad_update': 'el trigger de disponibilidad en UPDATE',
}
BODY = """
declare
  v_uid     uuid := (select auth.uid());
  v_rol     text := private.rol_crm((select auth.uid()));
  v_lead    crm.leads%rowtype;
  v_bloqueo jsonb;
  v_v       jsonb;
  v_previo  text;
  v_inv     uuid;
  v_flag    boolean;
begin
  -- F2.b [D-15]: la puerta del botón «Reabrir» del CRM (analista, supervisor o Gerencia, sobre un lead de su ámbito).
  -- Sustituye el UPDATE directo de etapa que hacía el front, que con la identidad encendida cierra el trigger
  -- «reabrir solo por RPC» de D-13 (P0409): reabrir tiene que juzgar a la PERSONA y enlazar el lead, como tomar,
  -- rescatar y deshacer. Con la bandera apagada es EXACTAMENTE el UPDATE de hoy (mismos triggers, mismos índices).
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'Solo un analista, un supervisor o Gerencia reabre un lead' using errcode = '42501';
  end if;
  if p_lead_id is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;
  -- Ámbito ANTES de cualquier candado (auditor D-13 v4 M1): un lead ajeno o inexistente muere aquí sin sondear a nadie.
  -- Mismo predicado que la policy leads_update (el UPDATE que hacía el front).
  if not exists (select 1 from crm.leads l
                  where l.id = p_lead_id and l.activo = true
                    and (v_rol = 'gerencia'
                         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  -- Codex v4 #2: READ COMMITTED SIEMPRE antes de leer la bandera (una foto REPEATABLE READ anterior al encendido seguiría
  -- viendo la bandera vieja aunque tome el candado). Codex v3 #4 / auditor v4 #6: la bandera se lee bajo el candado
  -- COMPARTIDO por bandera (el cambio de bandera toma el exclusivo en su trigger, D-5) y DESPUÉS del ámbito: una llamada
  -- que entró apagada termina apagada aunque espere por el lead, y viceversa; un lead ajeno no espera por nada.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La reapertura requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
  -- Candados de PERSONA antes de la fila (documento → persona → lead), como tomar/rescatar/deshacer (D-13); inertes con la bandera apagada.
  v_bloqueo := private.bloquear_personas_de_leads(array[p_lead_id], null);
  select * into v_lead
  from crm.leads l
  where l.id = p_lead_id and l.activo = true
    and (v_rol = 'gerencia'
         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'Solo se puede reabrir un lead descartado (este está en «%»)', v_lead.etapa using errcode = 'P0409';
  end if;
  -- Gemela de rescatar/deshacer (b2/D-3): una persona vetada no se reabre (el propio lead, su persona, su puente o un
  -- suelto con el documento de una persona vetada). Inerte con la bandera apagada: el UPDATE de hoy tampoco lo mira.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
  end if;
  if v_flag then
    -- La bandera debe seguir encendida tras los candados (Codex D-13 v4.3 [1]): apagada a medias, los candados fueron no-ops.
    if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
      raise exception 'La identidad unificada se apagó durante la operación; vuelve a intentarlo' using errcode = '40001';
    end if;
    if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
      raise exception 'El documento o la persona de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    -- El JUICIO único de reapertura (D-13): veto, otro lead de la persona, conversión en curso, ya cliente (activo o no).
    v_v := private.juicio_reapertura(v_lead.id, v_lead.telefono, null);
    if v_v->>'estado' = 'no_contactar' then
      raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
    end if;
    if v_v is not null then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_lead.id)::text;
    end if;
  end if;
  -- El MISMO UPDATE que hacía el front (etapa → nuevo, sin motivo): los triggers de siempre (sello del descarte, actividad
  -- «cambio_etapa» atribuida a quien reabre, disponibilidad, SLA) y los índices de contacto VIVO (23505 si otro lead
  -- abierto ya tiene ese teléfono o DNI: el front lo traduce como hoy) deciden igual que antes. Bajo el GUC de reapertura
  -- para que el trigger «reabrir solo por RPC» (D-13) lo deje pasar con la bandera encendida.
  v_previo := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
  update crm.leads set etapa = 'nuevo', motivo_descarte = null
   where id = p_lead_id and activo = true and etapa = 'descartado';
  if not found then
    raise exception 'El lead ya no está descartado (carrera)' using errcode = 'P0002';
  end if;
  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo, true);
  -- Con la identidad encendida, el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
  if v_flag and v_lead.inversionista_id is null then
    v_inv := private.lead_persona_reabrir(p_lead_id);
    perform private.enlazar_lead_reabierto(p_lead_id, v_inv);
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'etapa', v_lead.etapa,
    'inversionista_id', v_lead.inversionista_id, 'enlazado', v_flag and v_lead.inversionista_id is not null,
    'reabierto_por', v_uid, 'reabierto_en', pg_catalog.statement_timestamp());
end;
"""
H_BODY = md5s(BODY)
FIRMA_E = 'crm.editar_lead_fn(uuid,jsonb)'
BODY_E = """
declare
  v_uid       uuid := (select auth.uid());
  v_flag      boolean;
  v_dni       text;
  v_dni_cambia boolean := false;
  v_por_puerta boolean := false;
  v_k         text;
  v_sets      text[] := '{}';
  v_n         integer;
  v_claves    constant text[] := array['nombre_completo','telefono','telefono_alternativo','correo','monto_estimado','moneda',
                                       'categoria_interes','origen','nota','dni','distrito','genero','fecha_nacimiento'];
begin
  -- F2.b [D-15] (Codex bloque 4 #1): la edición de la ficha del lead es UNA transacción. SECURITY INVOKER a propósito: el
  -- UPDATE corre con el rol y la RLS de quien edita (policy leads_update, grants por columna) y con EXACTAMENTE las
  -- columnas que manda la ficha, como el UPDATE directo de hoy. Con la identidad ENCENDIDA y el DNI cambiado, el documento
  -- pasa antes por su puerta (crm.fijar_dni_lead_fn, DEFINER: candados documento → persona → fila, juicio y enlace) DENTRO
  -- de la misma transacción: si el resto falla (teléfono duplicado, fila retenida, red), el DNI tampoco queda; dos ediciones
  -- simultáneas no se mezclan (gana la última entera, o falla entera). Apagada: un solo UPDATE, byte a byte el de hoy.
  if v_uid is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  if p_lead_id is null or p_cambios is null or pg_catalog.jsonb_typeof(p_cambios) <> 'object' then
    raise exception 'Cambios inválidos' using errcode = '22023';
  end if;
  for v_k in select k from pg_catalog.jsonb_object_keys(p_cambios) k loop
    if not (v_k = any(v_claves)) then
      raise exception 'Campo no editable desde la ficha: %', v_k using errcode = '22023';
    end if;
  end loop;
  -- READ COMMITTED siempre y la bandera bajo el candado COMPARTIDO (D-5): la edición termina con la bandera que leyó.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La edición requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := crm.bandera_activa('resolver_en_puertas');
  if p_cambios ? 'dni' then
    v_dni := nullif(pg_catalog.btrim(p_cambios->>'dni'), '');
    -- Bajo RLS: un lead ajeno no se ve → no «cambia» → el UPDATE de abajo no toca ninguna fila → P0002 sin sondear a nadie.
    v_dni_cambia := exists (select 1 from crm.leads l where l.id = p_lead_id and l.dni is distinct from v_dni);
  end if;
  if v_flag and v_dni_cambia then
    perform crm.fijar_dni_lead_fn(p_lead_id, v_dni);
    v_por_puerta := true;
  end if;
  -- El UPDATE de hoy: SOLO las columnas que manda la ficha (SET dinámico con la lista blanca), bajo la RLS del que edita.
  for v_k in select k from pg_catalog.jsonb_object_keys(p_cambios) k order by k loop
    if v_k = 'dni' and v_por_puerta then
      continue;   -- ya escrito por su puerta en esta misma transacción
    end if;
    v_sets := pg_catalog.array_append(v_sets, pg_catalog.format('%I = %L', v_k,
      case when v_k = 'dni' then v_dni else p_cambios->>v_k end));
  end loop;
  if pg_catalog.array_length(v_sets, 1) is null then
    -- Solo cambió el DNI (por su puerta): la puerta ya comprobó ámbito y existencia.
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni_por_puerta', v_por_puerta);
  end if;
  execute pg_catalog.format('update crm.leads set %s where id = $1', pg_catalog.array_to_string(v_sets, ', ')) using p_lead_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni_por_puerta', v_por_puerta);
end;
"""
H_BODY_E = md5s(BODY_E)
CREA_E = f"""create or replace function crm.editar_lead_fn(p_lead_id uuid, p_cambios jsonb)
 returns jsonb
 language plpgsql
 security invoker
 set search_path to ''
 set lock_timeout to '5s'
as $function${BODY_E}$function$;
revoke all on function {FIRMA_E} from public, anon, service_role;
grant execute on function {FIRMA_E} to authenticated;
comment on function {FIRMA_E} is 'F2.b [D-15]: la edición de la ficha del lead en UNA transacción (INVOKER: el UPDATE va con la RLS y los grants por columna de quien edita, solo las columnas que manda la ficha). Con la identidad encendida el DNI pasa antes por fijar_dni_lead_fn dentro de la misma transacción: si el resto falla, el DNI tampoco queda. Apagada: el UPDATE de hoy.';
"""
CREA = f"""create or replace function crm.reabrir_lead_fn(p_lead_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function${BODY}$function$;
revoke all on function {FIRMA} from public, anon, service_role;
grant execute on function {FIRMA} to authenticated;
comment on function {FIRMA} is 'F2.b [D-15]: la puerta del botón «Reabrir» (descartado → nuevo) para analista/supervisor/Gerencia sobre su ámbito. Apagada la identidad: el UPDATE de hoy. Encendida: candados documento → persona → lead, juicio de reapertura (veto P0429; otro lead/conversión/ya cliente P0409) y enlace a la persona.';
"""
GUARD_DEPS = ''.join(f"""  if to_regprocedure('{k}') is null or left(md5(pg_get_functiondef('{k}'::regprocedure)), 8) <> '{v}' then
    raise exception 'F2.b D-15: {k} falta o no es el texto vivo de producción (esperado {v}…)';
  end if;
""" for k, v in H.items())
GUARD_DEPS += ''.join(f"""  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = '{k}' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'F2.b D-15: {v} (crm.leads.{k}) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
""" for k, v in TRG.items())
GUARD_DEPS += """  if not exists (select 1 from pg_policy where polrelid = 'crm.leads'::regclass and polname = 'leads_update' and polcmd = 'w'
                   and strpos(pg_get_expr(polqual, polrelid), 'vendedor_ids_visibles') > 0 and strpos(pg_get_expr(polqual, polrelid), '''gerencia''') > 0) then
    raise exception 'F2.b D-15: la policy crm.leads.leads_update no es la esperada (ámbito por vendedor_ids_visibles / gerencia)';
  end if;
"""
POST = f"""  if not exists (select 1 from pg_proc p where p.oid = '{FIRMA}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{H_BODY}') then
    raise exception 'POSTFLIGHT D-15: crm.reabrir_lead_fn no quedó como la genera gen-d15.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', '{FIRMA}', 'EXECUTE')
     or has_function_privilege('anon', '{FIRMA}', 'EXECUTE')
     or has_function_privilege('service_role', '{FIRMA}', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = '{FIRMA}'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-15: los grants de la puerta no son «solo authenticated»';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = '{FIRMA_E}'::regprocedure and not p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{H_BODY_E}') then
    raise exception 'POSTFLIGHT D-15: crm.editar_lead_fn no quedó como la genera gen-d15.py (cuerpo, INVOKER, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', '{FIRMA_E}', 'EXECUTE')
     or has_function_privilege('anon', '{FIRMA_E}', 'EXECUTE')
     or has_function_privilege('service_role', '{FIRMA_E}', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = '{FIRMA_E}'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-15: los grants de crm.editar_lead_fn no son «solo authenticated»';
  end if;
  if to_regprocedure('crm.bandera_activa(text)') is null or to_regprocedure('crm.fijar_dni_lead_fn(uuid,text)') is null then
    raise exception 'POSTFLIGHT D-15: faltan crm.bandera_activa(text) o crm.fijar_dni_lead_fn(uuid,text)';
  end if;
"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-15] — EL BOTÓN «REABRIR» PASA POR UNA PUERTA SQL
-- (bloque 4 del plan de activación, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: el botón «Reabrir» de la ficha del lead (un descartado vuelve a «nuevo») hacía un UPDATE directo de etapa desde el
-- front. Con la identidad unificada ENCENDIDA, D-13 cierra esa vía (trigger «reabrir solo por RPC», P0409): reabrir un
-- descarte tiene que juzgar a la PERSONA (veto, otro lead suyo, conversión en curso, ya cliente) y enlazar el lead, como
-- ya hacen tomar, rescatar y deshacer. Esta migración crea la cuarta puerta:
--   crm.reabrir_lead_fn(p_lead_id uuid) → {{ok, lead_id, etapa, inversionista_id, enlazado, reabierto_por, reabierto_en}}
--   · SOLO authenticated con rol CRM vendedor/supervisor/gerencia, sobre un lead de su ámbito (el predicado de leads_update),
--     activo y descartado; ámbito ANTES de cualquier candado (auditor D-13 v4 M1).
--   · Con la bandera APAGADA: el MISMO UPDATE de hoy (etapa → nuevo, motivo → null) bajo los mismos triggers (sello del
--     descarte, actividad «cambio_etapa» atribuida a quien reabre, disponibilidad, SLA) e índices de contacto vivo (23505);
--     el juicio de la persona vetada (persona_vetada, b2/D-3) es inerte apagado, como en rescatar/deshacer: paridad total.
--   · Con la bandera ENCENDIDA: candados documento → persona → lead (bloquear_personas_de_leads), relectura de la bandera
--     y «lead dentro de lo bloqueado» (40001), el JUICIO único de reapertura (D-13: P0429 veto; P0409 otro lead de la
--     persona / conversión en curso / ya cliente, activo o no) y, tras el UPDATE bajo crm.reapertura_identidad, el lead
--     queda ENLAZADO a su persona (enlazar_lead_reabierto). Todo helper es el de D-13 (huellas de producción como guardas).
-- El front (store.reabrir) llama esta puerta en vez de actualizar la fila. Y la EDICIÓN de la ficha va por
-- crm.editar_lead_fn(lead, cambios) (INVOKER: el UPDATE de hoy con la RLS de quien edita, solo las columnas que manda la
-- ficha; con ON el DNI pasa antes por crm.fijar_dni_lead_fn en la MISMA transacción: todo o nada, dos ediciones no se mezclan). La bandera se lee bajo el advisory compartido crm_flag_resolver_en_puertas (D-5 pone el exclusivo
-- en el cambio de bandera): la llamada termina con la bandera que leyó. Ensayo: scripts/oraculo-f2b-d15.sh (UPDATE directo vs puerta, OFF y ON, mutante sin D-15).
-- Reversa: scripts/rollback-f2b-d15.sql (DROP). Registro: scripts/registrar-f2b-d15.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-15: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
{GUARD_DEPS}end
$guard$;

-- ============================================================================
-- 1. crm.reabrir_lead_fn(uuid): la puerta del botón «Reabrir»
-- ============================================================================
{CREA}
-- ============================================================================
-- 2. crm.editar_lead_fn(uuid, jsonb): la edición de la ficha en UNA transacción (INVOKER; el DNI por su puerta con ON)
-- ============================================================================
{CREA_E}
do $post$
begin
{POST}  raise notice 'F2.b D-15 OK: crm.reabrir_lead_fn y crm.editar_lead_fn creadas (solo authenticated); apagadas = el UPDATE de hoy.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-15] ({VER}): suelta crm.reabrir_lead_fn y desregistra la versión. Repetible dos veces.
-- Antes de revertir, publicar un front que vuelva al UPDATE directo (o el botón «Reabrir» responderá PGRST202 → «No se pudo
-- guardar el cambio» hasta que vuelva la puerta). Con la bandera encendida ese UPDATE directo lo cierra D-13.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $pre$
begin
  -- No se suelta a ciegas: solo la puerta que genera gen-d15.py (cuerpo {H_BODY[:8]}…). Otro cuerpo = otra versión: revisar antes.
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('{FIRMA}') and md5(p.prosrc) <> '{H_BODY}')
     or exists (select 1 from pg_proc p where p.oid = to_regprocedure('{FIRMA_E}') and md5(p.prosrc) <> '{H_BODY_E}') then
    raise exception 'REVERSA D-15: alguna puerta viva no tiene el cuerpo de gen-d15.py ({H_BODY[:8]}… / {H_BODY_E[:8]}…); no se suelta a ciegas';
  end if;
end
$pre$;
drop function if exists crm.reabrir_lead_fn(uuid);
drop function if exists crm.editar_lead_fn(uuid, jsonb);
do $post$
begin
  if to_regprocedure('{FIRMA}') is not null or to_regprocedure('{FIRMA_E}') is not null then
    raise exception 'REVERSA D-15: alguna puerta sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-15 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d15.sql').write_text(rb, encoding='utf-8')
rb = rb.replace('-- REVERSA de F2.b [D-15] ({VER}): suelta crm.reabrir_lead_fn y desregistra la versión.', '-- REVERSA de F2.b [D-15] ({VER}): suelta crm.reabrir_lead_fn y crm.editar_lead_fn y desregistra la versión.')
(W/'scripts'/'rollback-f2b-d15.sql').write_text(rb, encoding='utf-8')
H_MIG = md5s(mig)
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-15]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige la puerta con su cuerpo, definer, search_path,\n"
       "-- lock_timeout y grants exactos, los helpers vivos de D-13 que reutiliza, y se niega si la versión ya está registrada con OTRO contenido.\n"
       f"begin;\nset local lock_timeout = '5s';\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + POST.replace('POSTFLIGHT D-15', 'REGISTRO D-15') + GUARD_DEPS.replace('F2.b D-15', 'REGISTRO D-15')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-15: la versión {VER} ya está registrada con otro contenido (o incompleto)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d15.sql').write_text(reg, encoding='utf-8')
print('D-15 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG, '; cuerpo reabrir', H_BODY, '; cuerpo editar', H_BODY_E)
