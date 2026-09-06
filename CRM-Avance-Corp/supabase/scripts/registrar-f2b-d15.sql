-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-15]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.
-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige la puerta con su cuerpo, definer, search_path,
-- lock_timeout y grants exactos, los helpers vivos de D-13 que reutiliza, y se niega si la versión ya está registrada con OTRO contenido.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d15_reabrir_lead_por_puerta'));
do $chk$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '53a211b04192a853b154c5fba4fb9300') then
    raise exception 'REGISTRO D-15: crm.reabrir_lead_fn no quedó como la genera gen-d15.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and a.grantee = 0) then
    raise exception 'REGISTRO D-15: los grants de la puerta no son «solo authenticated»';
  end if;
  if to_regprocedure('private.bloquear_personas_de_leads(uuid[],text)') is null or left(md5(pg_get_functiondef('private.bloquear_personas_de_leads(uuid[],text)'::regprocedure)), 8) <> '781496f9' then
    raise exception 'REGISTRO D-15: private.bloquear_personas_de_leads(uuid[],text) falta o no es el texto vivo de producción (esperado 781496f9…)';
  end if;
  if to_regprocedure('private.lead_dentro_de_bloqueo(uuid,jsonb)') is null or left(md5(pg_get_functiondef('private.lead_dentro_de_bloqueo(uuid,jsonb)'::regprocedure)), 8) <> 'f1fc03b9' then
    raise exception 'REGISTRO D-15: private.lead_dentro_de_bloqueo(uuid,jsonb) falta o no es el texto vivo de producción (esperado f1fc03b9…)';
  end if;
  if to_regprocedure('private.juicio_reapertura(uuid,text,text)') is null or left(md5(pg_get_functiondef('private.juicio_reapertura(uuid,text,text)'::regprocedure)), 8) <> '47277cd6' then
    raise exception 'REGISTRO D-15: private.juicio_reapertura(uuid,text,text) falta o no es el texto vivo de producción (esperado 47277cd6…)';
  end if;
  if to_regprocedure('private.enlazar_lead_reabierto(uuid,uuid)') is null or left(md5(pg_get_functiondef('private.enlazar_lead_reabierto(uuid,uuid)'::regprocedure)), 8) <> 'c0c26159' then
    raise exception 'REGISTRO D-15: private.enlazar_lead_reabierto(uuid,uuid) falta o no es el texto vivo de producción (esperado c0c26159…)';
  end if;
  if to_regprocedure('private.lead_persona_reabrir(uuid)') is null or left(md5(pg_get_functiondef('private.lead_persona_reabrir(uuid)'::regprocedure)), 8) <> '027e19f2' then
    raise exception 'REGISTRO D-15: private.lead_persona_reabrir(uuid) falta o no es el texto vivo de producción (esperado 027e19f2…)';
  end if;
  if to_regprocedure('private.persona_vetada(uuid)') is null or left(md5(pg_get_functiondef('private.persona_vetada(uuid)'::regprocedure)), 8) <> 'a70efe77' then
    raise exception 'REGISTRO D-15: private.persona_vetada(uuid) falta o no es el texto vivo de producción (esperado a70efe77…)';
  end if;
  if to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()') is null or left(md5(pg_get_functiondef('private.trg_leads_zz_reapertura_solo_rpc()'::regprocedure)), 8) <> '39c49943' then
    raise exception 'REGISTRO D-15: private.trg_leads_zz_reapertura_solo_rpc() falta o no es el texto vivo de producción (esperado 39c49943…)';
  end if;
  if to_regprocedure('private.trg_leads_cambio_etapa()') is null or left(md5(pg_get_functiondef('private.trg_leads_cambio_etapa()'::regprocedure)), 8) <> '5e457384' then
    raise exception 'REGISTRO D-15: private.trg_leads_cambio_etapa() falta o no es el texto vivo de producción (esperado 5e457384…)';
  end if;
  if to_regprocedure('private.rol_crm(uuid)') is null or left(md5(pg_get_functiondef('private.rol_crm(uuid)'::regprocedure)), 8) <> '99827f3f' then
    raise exception 'REGISTRO D-15: private.rol_crm(uuid) falta o no es el texto vivo de producción (esperado 99827f3f…)';
  end if;
  if to_regprocedure('private.vendedor_ids_visibles(uuid)') is null or left(md5(pg_get_functiondef('private.vendedor_ids_visibles(uuid)'::regprocedure)), 8) <> '85544c70' then
    raise exception 'REGISTRO D-15: private.vendedor_ids_visibles(uuid) falta o no es el texto vivo de producción (esperado 85544c70…)';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_reapertura_solo_rpc' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'REGISTRO D-15: el trigger «reabrir solo por RPC» (D-13) (crm.leads.trg_leads_zz_reapertura_solo_rpc) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_cambio_etapa' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'REGISTRO D-15: el trigger que anota la actividad «cambio_etapa» (crm.leads.trg_leads_cambio_etapa) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'REGISTRO D-15: el trigger de disponibilidad en UPDATE (crm.leads.trg_leads_00_disponibilidad_update) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'crm.leads'::regclass and polname = 'leads_update' and polcmd = 'w'
                   and strpos(pg_get_expr(polqual, polrelid), 'vendedor_ids_visibles') > 0 and strpos(pg_get_expr(polqual, polrelid), '''gerencia''') > 0) then
    raise exception 'REGISTRO D-15: la policy crm.leads.leads_update no es la esperada (ámbito por vendedor_ids_visibles / gerencia)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260906150000' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '81d0ccf2d3ff9f0a7c878941284a51f6')) then
    raise exception 'REGISTRO D-15: la versión 20260906150000 ya está registrada con otro contenido (o incompleto)';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906150000', 'crm_f2b_d15_reabrir_lead_por_puerta', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-15] — EL BOTÓN «REABRIR» PASA POR UNA PUERTA SQL
-- (bloque 4 del plan de activación, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: el botón «Reabrir» de la ficha del lead (un descartado vuelve a «nuevo») hacía un UPDATE directo de etapa desde el
-- front. Con la identidad unificada ENCENDIDA, D-13 cierra esa vía (trigger «reabrir solo por RPC», P0409): reabrir un
-- descarte tiene que juzgar a la PERSONA (veto, otro lead suyo, conversión en curso, ya cliente) y enlazar el lead, como
-- ya hacen tomar, rescatar y deshacer. Esta migración crea la cuarta puerta:
--   crm.reabrir_lead_fn(p_lead_id uuid) → {ok, lead_id, etapa, inversionista_id, enlazado, reabierto_por, reabierto_en}
--   · SOLO authenticated con rol CRM vendedor/supervisor/gerencia, sobre un lead de su ámbito (el predicado de leads_update),
--     activo y descartado; ámbito ANTES de cualquier candado (auditor D-13 v4 M1).
--   · Con la bandera APAGADA: el MISMO UPDATE de hoy (etapa → nuevo, motivo → null) bajo los mismos triggers (sello del
--     descarte, actividad «cambio_etapa» atribuida a quien reabre, disponibilidad, SLA) e índices de contacto vivo (23505);
--     el juicio de la persona vetada (persona_vetada, b2/D-3) es inerte apagado, como en rescatar/deshacer: paridad total.
--   · Con la bandera ENCENDIDA: candados documento → persona → lead (bloquear_personas_de_leads), relectura de la bandera
--     y «lead dentro de lo bloqueado» (40001), el JUICIO único de reapertura (D-13: P0429 veto; P0409 otro lead de la
--     persona / conversión en curso / ya cliente, activo o no) y, tras el UPDATE bajo crm.reapertura_identidad, el lead
--     queda ENLAZADO a su persona (enlazar_lead_reabierto). Todo helper es el de D-13 (huellas de producción como guardas).
-- El front (store.reabrir) llama esta puerta en vez de actualizar la fila; la edición del DNI del lead va por
-- crm.fijar_dni_lead_fn (D-13). Ensayo: scripts/oraculo-f2b-d15.sh (UPDATE directo vs puerta, OFF y ON, mutante sin D-15).
-- Reversa: scripts/rollback-f2b-d15.sql (DROP). Registro: scripts/registrar-f2b-d15.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d15_reabrir_lead_por_puerta'));

do $guard$
begin
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-15: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if to_regprocedure('private.bloquear_personas_de_leads(uuid[],text)') is null or left(md5(pg_get_functiondef('private.bloquear_personas_de_leads(uuid[],text)'::regprocedure)), 8) <> '781496f9' then
    raise exception 'F2.b D-15: private.bloquear_personas_de_leads(uuid[],text) falta o no es el texto vivo de producción (esperado 781496f9…)';
  end if;
  if to_regprocedure('private.lead_dentro_de_bloqueo(uuid,jsonb)') is null or left(md5(pg_get_functiondef('private.lead_dentro_de_bloqueo(uuid,jsonb)'::regprocedure)), 8) <> 'f1fc03b9' then
    raise exception 'F2.b D-15: private.lead_dentro_de_bloqueo(uuid,jsonb) falta o no es el texto vivo de producción (esperado f1fc03b9…)';
  end if;
  if to_regprocedure('private.juicio_reapertura(uuid,text,text)') is null or left(md5(pg_get_functiondef('private.juicio_reapertura(uuid,text,text)'::regprocedure)), 8) <> '47277cd6' then
    raise exception 'F2.b D-15: private.juicio_reapertura(uuid,text,text) falta o no es el texto vivo de producción (esperado 47277cd6…)';
  end if;
  if to_regprocedure('private.enlazar_lead_reabierto(uuid,uuid)') is null or left(md5(pg_get_functiondef('private.enlazar_lead_reabierto(uuid,uuid)'::regprocedure)), 8) <> 'c0c26159' then
    raise exception 'F2.b D-15: private.enlazar_lead_reabierto(uuid,uuid) falta o no es el texto vivo de producción (esperado c0c26159…)';
  end if;
  if to_regprocedure('private.lead_persona_reabrir(uuid)') is null or left(md5(pg_get_functiondef('private.lead_persona_reabrir(uuid)'::regprocedure)), 8) <> '027e19f2' then
    raise exception 'F2.b D-15: private.lead_persona_reabrir(uuid) falta o no es el texto vivo de producción (esperado 027e19f2…)';
  end if;
  if to_regprocedure('private.persona_vetada(uuid)') is null or left(md5(pg_get_functiondef('private.persona_vetada(uuid)'::regprocedure)), 8) <> 'a70efe77' then
    raise exception 'F2.b D-15: private.persona_vetada(uuid) falta o no es el texto vivo de producción (esperado a70efe77…)';
  end if;
  if to_regprocedure('private.trg_leads_zz_reapertura_solo_rpc()') is null or left(md5(pg_get_functiondef('private.trg_leads_zz_reapertura_solo_rpc()'::regprocedure)), 8) <> '39c49943' then
    raise exception 'F2.b D-15: private.trg_leads_zz_reapertura_solo_rpc() falta o no es el texto vivo de producción (esperado 39c49943…)';
  end if;
  if to_regprocedure('private.trg_leads_cambio_etapa()') is null or left(md5(pg_get_functiondef('private.trg_leads_cambio_etapa()'::regprocedure)), 8) <> '5e457384' then
    raise exception 'F2.b D-15: private.trg_leads_cambio_etapa() falta o no es el texto vivo de producción (esperado 5e457384…)';
  end if;
  if to_regprocedure('private.rol_crm(uuid)') is null or left(md5(pg_get_functiondef('private.rol_crm(uuid)'::regprocedure)), 8) <> '99827f3f' then
    raise exception 'F2.b D-15: private.rol_crm(uuid) falta o no es el texto vivo de producción (esperado 99827f3f…)';
  end if;
  if to_regprocedure('private.vendedor_ids_visibles(uuid)') is null or left(md5(pg_get_functiondef('private.vendedor_ids_visibles(uuid)'::regprocedure)), 8) <> '85544c70' then
    raise exception 'F2.b D-15: private.vendedor_ids_visibles(uuid) falta o no es el texto vivo de producción (esperado 85544c70…)';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_reapertura_solo_rpc' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'F2.b D-15: el trigger «reabrir solo por RPC» (D-13) (crm.leads.trg_leads_zz_reapertura_solo_rpc) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_cambio_etapa' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'F2.b D-15: el trigger que anota la actividad «cambio_etapa» (crm.leads.trg_leads_cambio_etapa) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16) then
    raise exception 'F2.b D-15: el trigger de disponibilidad en UPDATE (crm.leads.trg_leads_00_disponibilidad_update) falta, está deshabilitado o no es BEFORE UPDATE';
  end if;
  if not exists (select 1 from pg_policy where polrelid = 'crm.leads'::regclass and polname = 'leads_update' and polcmd = 'w'
                   and strpos(pg_get_expr(polqual, polrelid), 'vendedor_ids_visibles') > 0 and strpos(pg_get_expr(polqual, polrelid), '''gerencia''') > 0) then
    raise exception 'F2.b D-15: la policy crm.leads.leads_update no es la esperada (ámbito por vendedor_ids_visibles / gerencia)';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.reabrir_lead_fn(uuid): la puerta del botón «Reabrir»
-- ============================================================================
create or replace function crm.reabrir_lead_fn(p_lead_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare
  v_uid     uuid := (select auth.uid());
  v_rol     text := private.rol_crm((select auth.uid()));
  v_lead    crm.leads%rowtype;
  v_bloqueo jsonb;
  v_v       jsonb;
  v_previo  text;
  v_inv     uuid;
  v_flag    boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
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
  if v_flag and pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
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
$function$;
revoke all on function crm.reabrir_lead_fn(uuid) from public, anon, service_role;
grant execute on function crm.reabrir_lead_fn(uuid) to authenticated;
comment on function crm.reabrir_lead_fn(uuid) is 'F2.b [D-15]: la puerta del botón «Reabrir» (descartado → nuevo) para analista/supervisor/Gerencia sobre su ámbito. Apagada la identidad: el UPDATE de hoy. Encendida: candados documento → persona → lead, juicio de reapertura (veto P0429; otro lead/conversión/ya cliente P0409) y enlace a la persona.';

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '53a211b04192a853b154c5fba4fb9300') then
    raise exception 'POSTFLIGHT D-15: crm.reabrir_lead_fn no quedó como la genera gen-d15.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-15: los grants de la puerta no son «solo authenticated»';
  end if;
  raise notice 'F2.b D-15 OK: crm.reabrir_lead_fn creada (solo authenticated); apagada = el UPDATE de hoy.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;
