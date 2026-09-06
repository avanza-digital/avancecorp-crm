-- ============================================================================
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
-- El front (store.reabrir) llama esta puerta en vez de actualizar la fila. Y la EDICIÓN de la ficha va por
-- crm.editar_lead_fn(lead, cambios) (INVOKER: el UPDATE de hoy con la RLS de quien edita, solo las columnas que manda la
-- ficha; con ON el DNI pasa antes por crm.fijar_dni_lead_fn en la MISMA transacción: todo o nada, dos ediciones no se mezclan). La bandera se lee bajo el advisory compartido crm_flag_resolver_en_puertas (D-5 pone el exclusivo
-- en el cambio de bandera): la llamada termina con la bandera que leyó. Ensayo: scripts/oraculo-f2b-d15.sh (UPDATE directo vs puerta, OFF y ON, mutante sin D-15).
-- Reversa: scripts/rollback-f2b-d15.sql (DROP). Registro: scripts/registrar-f2b-d15.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d15_reabrir_lead_por_puerta'));

do $guard$
begin
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-15: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.multiempresa_flags'::regclass and tgname = 'trg_multiempresa_flags_00_serializa_puertas' and tgenabled = 'O') then
    raise exception 'F2.b D-15: falta el trigger que serializa el cambio de bandera (D-5, 20260906140000): aplica D-5 ANTES que D-15';
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
$function$;
revoke all on function crm.reabrir_lead_fn(uuid) from public, anon, service_role;
grant execute on function crm.reabrir_lead_fn(uuid) to authenticated;
comment on function crm.reabrir_lead_fn(uuid) is 'F2.b [D-15]: la puerta del botón «Reabrir» (descartado → nuevo) para analista/supervisor/Gerencia sobre su ámbito. Apagada la identidad: el UPDATE de hoy. Encendida: candados documento → persona → lead, juicio de reapertura (veto P0429; otro lead/conversión/ya cliente P0409) y enlace a la persona.';

-- ============================================================================
-- 2. crm.editar_lead_fn(uuid, jsonb): la edición de la ficha en UNA transacción (INVOKER; el DNI por su puerta con ON)
-- ============================================================================
create or replace function crm.editar_lead_fn(p_lead_id uuid, p_cambios jsonb)
 returns jsonb
 language plpgsql
 security invoker
 set search_path to ''
 set lock_timeout to '5s'
as $function$
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
  if p_cambios = '{}'::jsonb then
    raise exception 'Sin cambios' using errcode = '22023';   -- auditor v5 #6: nunca un «ok» sin escribir
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
$function$;
revoke all on function crm.editar_lead_fn(uuid,jsonb) from public, anon, service_role;
grant execute on function crm.editar_lead_fn(uuid,jsonb) to authenticated;
comment on function crm.editar_lead_fn(uuid,jsonb) is 'F2.b [D-15]: la edición de la ficha del lead en UNA transacción (INVOKER: el UPDATE va con la RLS y los grants por columna de quien edita, solo las columnas que manda la ficha). Con la identidad encendida el DNI pasa antes por fijar_dni_lead_fn dentro de la misma transacción: si el resto falla, el DNI tampoco queda. Apagada: el UPDATE de hoy.';

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '65b4b0924da38eaa2c6b7dc42f44ee79') then
    raise exception 'POSTFLIGHT D-15: crm.reabrir_lead_fn no quedó como la genera gen-d15.py (cuerpo, definer, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reabrir_lead_fn(uuid)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.reabrir_lead_fn(uuid)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-15: los grants de la puerta no son «solo authenticated»';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.editar_lead_fn(uuid,jsonb)'::regprocedure and not p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'f2c1b7665ae58bea071499e04d970290') then
    raise exception 'POSTFLIGHT D-15: crm.editar_lead_fn no quedó como la genera gen-d15.py (cuerpo, INVOKER, dueño postgres, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('authenticated', 'crm.editar_lead_fn(uuid,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.editar_lead_fn(uuid,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.editar_lead_fn(uuid,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.editar_lead_fn(uuid,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-15: los grants de crm.editar_lead_fn no son «solo authenticated»';
  end if;
  if to_regprocedure('crm.bandera_activa(text)') is null or to_regprocedure('crm.fijar_dni_lead_fn(uuid,text)') is null then
    raise exception 'POSTFLIGHT D-15: faltan crm.bandera_activa(text) o crm.fijar_dni_lead_fn(uuid,text)';
  end if;
  raise notice 'F2.b D-15 OK: crm.reabrir_lead_fn y crm.editar_lead_fn creadas (solo authenticated); apagadas = el UPDATE de hoy.';
end
$post$;
commit;
