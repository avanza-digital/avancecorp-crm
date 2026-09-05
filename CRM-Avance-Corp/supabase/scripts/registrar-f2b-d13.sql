-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-13]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.
-- Se niega si alguna de las 5 funciones vivas no es la de D-13, si la bandera está encendida o si la versión está registrada con OTRO contenido.
begin;
select pg_advisory_xact_lock(hashtext('crm_f2b_d13_un_solo_lead_todas_las_puertas'));
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text, p_excluir_lead_id uuid') is distinct from 'c5ed89a08461453c5a02f7ea559207d9' then
    raise exception 'REGISTRO D-13: private.verificar_disponibilidad_lead_impl(text,text,uuid) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_zz_enlaza_identidad' and pg_get_function_identity_arguments(p.oid)='') is distinct from '62cebe9fbebf0f9a1ac617acba4ac3d7' then
    raise exception 'REGISTRO D-13: private.trg_leads_zz_enlaza_identidad() VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='tomar_lead_libre' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '596ccbcb365923406d9a96efdc9f081a' then
    raise exception 'REGISTRO D-13: crm.tomar_lead_libre(text,text) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_perfil_id uuid') is distinct from '8bd4d8c94aeb79b92bf6638bb16aeea0' then
    raise exception 'REGISTRO D-13: crm.convertir_lead(uuid,uuid) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text') is distinct from '29d5bffdb76f47fe2048f450412c8be5' then
    raise exception 'REGISTRO D-13: crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text') is distinct from 'b006033723cb3f210dc8e73fd05087b9' then
    raise exception 'REGISTRO D-13: crm.marcar_efectos_conversion(uuid,uuid,text) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes' and pg_get_function_identity_arguments(p.oid)='p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean') is distinct from 'e65beebf90da4e03ac51e62755605bfd' then
    raise exception 'REGISTRO D-13: crm.rescatar_descartes(uuid[],uuid[],boolean) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion' and pg_get_function_identity_arguments(p.oid)='p_lead uuid') is distinct from '6d1612339d1ed900f73b32aeae227d43' then
    raise exception 'REGISTRO D-13: private.deshacer_descarte_implementacion(uuid) VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'REGISTRO D-13: la bandera resolver_en_puertas está ENCENDIDA';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905160000' and md5(statements[1]) <> 'aabd35b7df4edc9eabc4643b7848cd6d') then
    raise exception 'REGISTRO D-13: la versión 20260905160000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260905160000', 'crm_f2b_d13_un_solo_lead_en_todas_las_puertas', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-13] — «UN SOLO LEAD» Y «EL PUENTE
-- MANDA» EN TODAS LAS PUERTAS CON LA BANDERA ENCENDIDA (bloque 2; auditor D-10 M2, Codex D-10 #2/#3/#5)
-- ============================================================================
--
-- QUE (todo dentro de la rama ON; con la bandera APAGADA las ocho funciones responden como hoy):
--   * private.verificar_disponibilidad_lead_impl(tel, dni, excluir): la persona del DNI «ya es cliente» (via identidad)
--     si tiene OTRO lead por enlace vivo o por PUENTE (private.leads_de_identidades, b5) o si está EN CONVERSIÓN
--     (reserva por persona viva o sellada de otro lead, helper nuevo private.persona_en_conversion). `asesor` =
--     responsable de relación, o quien reservó, o 'sin asesor asignado'. Contrato del front intacto.
--   * private.trg_leads_zz_enlaza_identidad (INSERT): mismo conjunto → P0481 con el detalle de hoy. Serializado con la
--     reserva por el candado documental (inv_resolver:DNI:<doc>) que toma el trigger 000 antes: la carrera de la saga
--     (reserva → sellado → Auth → perfil → cerrar) ya no deja cuentas de portal huérfanas por un lead nacido en medio.
--   * crm.tomar_lead_libre: tras el lock del blanco y la membresía, si el documento (tecleado o del blanco) resuelve
--     a una persona con otro lead o en conversión → devuelve el veredicto fresco sin tomar (Codex D-10 #5).
--   * crm.convertir_lead y crm.convertir_lead_externo: «el puente del propio lead manda» (por la canónica), como ya
--     hace la reserva por persona desde D-10 (Codex D-10 #2); convertir_lead además rechaza convertir un lead reservado
--     para OTRA persona por la puerta directa (Codex D-13 #2).
--   * crm.marcar_efectos_conversion(lead, claim, token): «un solo lead» revalidado bajo el lock de la persona ANTES del
--     punto de no retorno (Codex D-13 #1): sin cuentas de portal huérfanas por un lead nacido/reabierto en medio.
--   * crm.rescatar_descartes y private.deshacer_descarte_implementacion: mismo juicio de identidad que la toma; y al
--     reabrir (o tomar) un lead con DNI de una persona reconocida, el lead queda ENLAZADO (como al nacer), para que la
--     reserva, el sellado y las conversiones lo vean por identidad (Codex D-13 #5/#6; auditor M1).
-- Generada desde el texto VIVO de producción (scripts/f2b/gen-d13.py, vivas/d13, huellas-d13-prod.txt): guardas
-- md5 EXACTAS, postflight byte a byte, grants comprobados. Independiente de D-10 (no comparten función).
-- Ensayo: scripts/oraculo-f2b-d13.sh. Reversa: scripts/rollback-f2b-d13.sql (restaura, suelta el helper, desregistra).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d13_un_solo_lead_todas_las_puertas'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('private.inversionista_canonica(uuid)') is null
     or to_regprocedure('private.toma_asienta_y_devuelve(uuid,text,text,text,jsonb)') is null
     or to_regprocedure('private.trg_leads_hereda_veto_persona()') is null then
    raise exception 'F2.b D-13: faltan b2 (20260904130000) o b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-13: la bandera resolver_en_puertas está ENCENDIDA';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                   where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_hereda_veto' and not t.tgisinternal and t.tgenabled = 'O'
                     and pg_get_triggerdef(t.oid) like '%BEFORE INSERT ON crm.leads%'
                     and strpos(p.prosrc, 'identidad_bloquear_documento') > 0) then
    raise exception 'F2.b D-13: falta la premisa de serialización: trg_leads_000_hereda_veto (BEFORE INSERT, habilitado) tomando private.identidad_bloquear_documento (b1)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '2421b2b78b02b8e93fd01598e2f54128' then
    raise exception 'F2.b D-13: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5)';
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text, p_excluir_lead_id uuid');
  if v_h is null then
    raise exception 'F2.b D-13: falta private.verificar_disponibilidad_lead_impl(text,text,uuid)';
  end if;
  if v_h is distinct from '5f99912dde92e5b0ff1720077377a172' and v_h is distinct from 'c5ed89a08461453c5a02f7ea559207d9' then
    raise exception 'F2.b D-13: private.verificar_disponibilidad_lead_impl(text,text,uuid) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_zz_enlaza_identidad' and pg_get_function_identity_arguments(p.oid)='');
  if v_h is null then
    raise exception 'F2.b D-13: falta private.trg_leads_zz_enlaza_identidad()';
  end if;
  if v_h is distinct from '7986b01ab6109bd15d228157cef3ef33' and v_h is distinct from '62cebe9fbebf0f9a1ac617acba4ac3d7' then
    raise exception 'F2.b D-13: private.trg_leads_zz_enlaza_identidad() no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='tomar_lead_libre' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.tomar_lead_libre(text,text)';
  end if;
  if v_h is distinct from '045d22cf0b5f62a98008cd5e04ae4d78' and v_h is distinct from '596ccbcb365923406d9a96efdc9f081a' then
    raise exception 'F2.b D-13: crm.tomar_lead_libre(text,text) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_perfil_id uuid');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.convertir_lead(uuid,uuid)';
  end if;
  if v_h is distinct from 'c30a0ac9be5f44bc1caa129bc90a2ea7' and v_h is distinct from '8bd4d8c94aeb79b92bf6638bb16aeea0' then
    raise exception 'F2.b D-13: crm.convertir_lead(uuid,uuid) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)';
  end if;
  if v_h is distinct from '0272febed241415d7c1cfcdf70bed37b' and v_h is distinct from '29d5bffdb76f47fe2048f450412c8be5' then
    raise exception 'F2.b D-13: crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.marcar_efectos_conversion(uuid,uuid,text)';
  end if;
  if v_h is distinct from '8ab20f7fb4842caaed5ad705db5e91b2' and v_h is distinct from 'b006033723cb3f210dc8e73fd05087b9' then
    raise exception 'F2.b D-13: crm.marcar_efectos_conversion(uuid,uuid,text) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes' and pg_get_function_identity_arguments(p.oid)='p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.rescatar_descartes(uuid[],uuid[],boolean)';
  end if;
  if v_h is distinct from '89778f4d57b3421a69628473520c6f41' and v_h is distinct from 'e65beebf90da4e03ac51e62755605bfd' then
    raise exception 'F2.b D-13: crm.rescatar_descartes(uuid[],uuid[],boolean) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion' and pg_get_function_identity_arguments(p.oid)='p_lead uuid');
  if v_h is null then
    raise exception 'F2.b D-13: falta private.deshacer_descarte_implementacion(uuid)';
  end if;
  if v_h is distinct from 'b14b91bf82827240a3a29e88a5b9e39f' and v_h is distinct from '6d1612339d1ed900f73b32aeae227d43' then
    raise exception 'F2.b D-13: private.deshacer_descarte_implementacion(uuid) no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 0. Helper: ¿la persona está EN CONVERSIÓN? (reserva por persona viva o sellada de un lead aún no convertido;
--    mismo predicado que private.fusion_bloqueos, b5). Los claims no cuentan: un claim abandonado sin reserva
--    lo retoma Gerencia y no debe bloquear a la persona para siempre.
-- ============================================================================
create or replace function private.persona_en_conversion(p_inv uuid, p_excluir_lead_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from crm.conversion_reservas r
    left join crm.leads l on l.id = r.lead_id
    where r.inversionista_id = p_inv
      and r.lead_id is distinct from p_excluir_lead_id
      and (r.expira_en > pg_catalog.now()
           or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))
  )
$$;
revoke all on function private.persona_en_conversion(uuid, uuid) from public, anon, authenticated, service_role;
comment on function private.persona_en_conversion(uuid, uuid) is
  'F2.b [D-13]: persona con reserva de conversión por persona viva o sellada (lead aún no convertido), excluido un lead. Solo la llaman las puertas definer.';

-- ============================================================================
-- 1. Verificador de disponibilidad (3 args): enlace vivo ∪ puente, y persona en conversión
-- ============================================================================
CREATE OR REPLACE FUNCTION private.verificar_disponibilidad_lead_impl(p_telefono text, p_dni text, p_excluir_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  -- documento normalizado IGUAL que el resolver (documento_normalizado es mayúsculas+alfanumérico)
  v_dni_norm text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_dni,''), '[^A-Za-z0-9]', '', 'g')), '');
  v_asesor_identidad text;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where l.id is distinct from p_excluir_lead_id
      and (l.no_contactar = true or (v_flag and coalesce(inv.no_contactar, false)))
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  )
  -- El veto es de la PERSONA (contrato §7.3): también si el documento EXACTO
  -- pertenece a una identidad vetada, aunque no tenga lead con ese teléfono.
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (el trigger de alta lo
  -- exige; contrato §18: CE/pasaporte se resuelven al convertir).
  or (v_flag and v_dni_norm is not null and exists (
    select 1
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and i.no_contactar = true
  )) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  -- Un solo lead TOTAL por persona (contrato #6, meta #3): si el DOCUMENTO exacto
  -- ya pertenece a una identidad que TIENE lead (Avance o cooperativa — aunque no
  -- tenga perfil de portal), esa persona ya es cliente / ya tiene su lead: no se
  -- crea otro. Solo el documento vincula (contrato #8). Gateado por bandera.
  if v_flag and v_dni_norm is not null then
    -- F2.b [D-13]: «los leads de una persona» = enlace vivo ∪ PUENTE (private.leads_de_identidades, b5: incluye
    -- históricos y soft-borrados, como ya contaba el join sin filtro de activo), y una persona EN CONVERSIÓN
    -- (reserva por persona viva o sellada de OTRO lead, private.persona_en_conversion) ya está naciendo como
    -- cliente: tampoco se le abre otro lead. `asesor` = responsable de relación, o quien reservó, o el centinela
    -- de siempre. Contrato del front intacto (mismas claves, mismo `via`).
    select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    left join lateral (
      select p.nombre_completo
      from crm.conversion_reservas r
      join public.perfiles p on p.id = r.reservado_por
      left join crm.leads lr on lr.id = r.lead_id
      where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
        and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
      order by r.reservado_en desc
      limit 1
    ) res on true
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and (exists (select 1 from private.leads_de_identidades(array[i.id]) x where x is distinct from p_excluir_lead_id)
           or private.persona_en_conversion(i.id, p_excluir_lead_id))
    limit 1;
    if found then
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', v_asesor_identidad, 'via', 'identidad');
    end if;
  end if;

  select
    l.id,
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde,
      -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
      -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
      -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
      -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
      -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
      'ultima_conversacion_en', (
        select pg_catalog.max(a.creado_en)
        from crm.actividades a
        where a.lead_id = v_lead.id
          and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
      )
    );
  end if;

  select
    l.id,
    l.activo,
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;

    -- ── F2: el descarte VENCIDO se parte (spec §5.6) ─────────────────────────
    -- Un enfriamiento vencido ya NO cae al 'libre' genérico: el contacto es
    -- REUTILIZABLE y su puerta es crm.tomar_lead_libre (el alta lo bloquea
    -- desde F1 — crear duplicaría). Dos excepciones deliberadas del plan:
    --   · activo=false jamás es reutilizable: un soft-borrado no se revive
    --     por esta puerta — cae a 'libre' y el alta crea de cero.
    --   · motivos con 0 días (pide_credito, datos_invalidos): CARENCIA de
    --     24 h SOLO para tomar (Miguel 2026-08-16 — protege el «Deshacer
    --     descarte 24h» del coordinador). Durante la ventana el veredicto
    --     sigue 'libre': el alta manual conserva su comportamiento de hoy.
    if v_lead.activo = true then
      if v_dias = 0
         and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
        return pg_catalog.jsonb_build_object('estado', 'libre');
      end if;
      v_quedo_libre_en := case
        when v_dias > 0 then v_disponible_desde
        else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
      end;
      return pg_catalog.jsonb_build_object(
        'estado', 'reutilizable',
        'motivo_descarte', v_lead.motivo_descarte,
        'descartado_en', v_lead.descartado_en,
        'quedo_libre_en', v_quedo_libre_en,
        'descartado_por', v_lead.descartado_por_nombre,
        'ultima_conversacion_en', (
          select pg_catalog.max(a.creado_en)
          from crm.actividades a
          where a.lead_id = v_lead.id
            and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
        )
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$function$
;

-- ============================================================================
-- 2. Trigger de nacimiento del lead (INSERT): mismo conjunto → P0481
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_leads_zz_enlaza_identidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_inv uuid;
  v_otro record;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.dni is not distinct from old.dni or v_priv then
      return new;
    end if;
    -- En UPDATE la fila del lead YA está bloqueada: aquí no se toma ningún lock de
    -- identidad (evitaría el orden documento->identidad->lead y podría abrazarse con
    -- marcar/levantar y la conversión). Se RECHAZA, no se enlaza: el documento de una
    -- persona enlazada, o un documento que resuelve a una persona reconocida, solo
    -- cambia por la corrección de Gerencia (bajo válvula, b5). Un DNI que no resuelve
    -- a nadie sigue editándose como hoy.
    -- F2.b [D-13] (Codex #7): un lead que está en el PUENTE de una persona (aunque no lleve enlace vivo) también es de
    -- una persona reconocida: su documento solo lo corrige Gerencia.
    if old.inversionista_id is not null
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id)
       or (nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
           and private.inversionista_por_documento('DNI', new.dni) is not null) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    return new;
  elsif v_priv and new.inversionista_id is not null then
    -- Una RPC bajo válvula que ya trae el enlace (p. ej. una fusión futura) manda.
    return new;
  end if;

  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- El advisory documental ya lo tomó el trigger 000 en esta misma sentencia.
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  -- F2.b [D-13]: enlace vivo ∪ PUENTE (private.leads_de_identidades, b5; el enlace vivo primero en el detalle)
  -- y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_identidades(array[v_inv]) x
  join crm.inversionistas i on i.id = v_inv
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where x is distinct from new.id
  order by (exists (select 1 from crm.leads l where l.id = x and l.inversionista_id = v_inv)) desc, x
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
  if private.persona_en_conversion(v_inv, new.id) then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad',
              'lead_id', (select r.lead_id from crm.conversion_reservas r
                           where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                           order by r.reservado_en desc limit 1))::text;
  end if;
  new.inversionista_id := v_inv;
  return new;
end;
$function$
;

-- ============================================================================
-- 3. tomar_lead_libre: el veredicto de identidad manda antes de tomar
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.tomar_lead_libre(p_telefono text, p_dni text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_tel text := private.normalizar_telefono(p_telefono);
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_veredicto_identidad jsonb;
  v_flag_d13 boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
  v_inv_reabre uuid;
  v_lead crm.leads%rowtype;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_ultima_conv timestamptz;
  v_propietario_anterior uuid;
  v_modo text;
  v_previo text;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La toma directa es del VENDEDOR para sí mismo (spec §7). Supervisor y
  -- gerencia ya tienen su puerta con destino elegible: el reparto.
  if v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'La toma directa es solo para vendedores; supervisión asigna por el reparto';
  end if;

  if v_tel is null or v_tel !~ '^\+519[0-9]{8}$' then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object(
        'estado', 'error',
        'detalle', 'telefono_invalido'
      ));
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  -- F2.b [D-13]: el candado documental del DNI TECLEADO va ANTES de bloquear filas (orden documento -> lead, el de la
  -- reserva por persona y el de marcar/levantar): así la toma lee las reservas DESPUÉS de que una reserva en vuelo por
  -- ese documento confirme o aborte. (Inerte con la bandera apagada.) El DNI del blanco solo se conoce tras su lock:
  -- ese brazo lee sin candado; el sellado de la conversión revalida «un solo lead» bajo el lock de la persona.
  perform private.identidad_bloquear_documento('DNI', v_dni);

  -- Vetos de contacto ANTES de bloquear filas: baratos, y el veredicto que
  -- devuelven es el mismo que daría la verificación.
  if exists (
    select 1
    from crm.leads l
    where (l.no_contactar = true or private.persona_vetada(l.id))  -- F2.b (b2): veto de la persona
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object('estado', 'no_contactar'));
  end if;

  if exists (
    select 1
    from public.perfiles per
    where per.rol = 'cliente'
      and per.activo = true
      and (
        private.normalizar_telefono(per.telefono) = v_tel
        or (v_dni is not null and per.dni = v_dni)
      )
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- El blanco, POR CONTACTO y el TELÉFONO manda (adenda 16/08-b del ledger):
  -- solo si el número no casa con nada se cae al DNI. FILA primero — el orden
  -- advisory→fila se abraza con «Deshacer descarte» (refutador del plan); las
  -- llaves advisory las toman los triggers del propio UPDATE, en el orden de
  -- los caminos vivos. ORDER BY determinista: la bolsa viva antes que los
  -- descartes, el descarte más reciente primero, id como desempate.
  select l.* into v_lead
  from crm.leads l
  where l.telefono = v_tel
    -- Codex R4: el veto DENTRO del predicado — EvalPlanQual lo re-evalúa
    -- sobre la versión nueva tras esperar la fila; el pre-chequeo solo no
    -- veía un no_contactar en vuelo.
    and l.no_contactar = false
    and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
    and (
      (l.activo = true
        and l.etapa not in ('convertido', 'descartado')
        and l.vendedor_id is null
        and l.asignado_supervisor_id is null)
      -- Espejo del impl: un descarte sin fecha es anomalía y no se toma.
      or (l.etapa = 'descartado' and l.descartado_en is not null)
    )
  order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
  limit 1
  for update;

  if not found and v_dni is not null then
    select l.* into v_lead
    from crm.leads l
    where l.dni = v_dni
      and l.no_contactar = false
      and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        -- Espejo EXACTO del brazo telefónico (auditor M1): sin este filtro un
        -- descarte-anomalía sin fecha entraba por el DNI saltándose
        -- enfriamiento y carencia.
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
    limit 1
    for update;
  end if;

  if not found then
    -- Nada tomable con ese contacto: el veredicto fresco explica qué pasa
    -- (tomado por otro, libre → alta nueva, etc.).
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- P-048: el permiso se re-consulta DESPUÉS del lock — una membresía
  -- revocada mientras esperaba la fila no alcanza a tomar al despertar. El
  -- FOR SHARE ancla la fila de equipo (Codex, carrera de offboarding): la
  -- desactivación la toma FOR UPDATE, así que o ella terminó (y aquí se ve
  -- inactivo) o espera a que esta toma termine (y su chequeo de dependencias
  -- verá el lead nuevo). Sin ciclo: la desactivación no bloquea crm.leads.
  perform 1
  from crm.equipo e
  where e.perfil_id = v_actor
  for share;
  if private.rol_crm(v_actor) is distinct from 'vendedor'
     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- F2.b [D-13]: con la identidad encendida se juzgan los DOS documentos (el tecleado y el del blanco, si difieren):
  -- si alguno resuelve a una persona que ya es cliente, ya tiene OTRO lead (enlace vivo o puente) o está en
  -- conversión, no se toma: manda el veredicto fresco, sea cual sea su vía (solo lecturas bajo el lock del blanco;
  -- el blanco queda excluido del juicio).
  if v_flag_d13 and (v_dni is not null or v_lead.dni is not null) then
    v_veredicto_identidad := null;
    if v_dni is not null then
      v_veredicto_identidad := private.verificar_disponibilidad_lead_impl(v_tel, v_dni, v_lead.id);
    end if;
    if coalesce(v_veredicto_identidad->>'estado', '') <> 'ya_es_cliente'
       and v_lead.dni is not null and v_lead.dni is distinct from v_dni then
      v_veredicto_identidad := private.verificar_disponibilidad_lead_impl(v_tel, v_lead.dni, v_lead.id);
    end if;
    if v_veredicto_identidad->>'estado' = 'ya_es_cliente' then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni, v_veredicto_identidad);
    end if;
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
  -- aunque nuestro blanco sea un descarte viejo: manda el veredicto fresco.
  -- El filtro de dueño es deliberado: una bolsa viva que casa solo por el OTRO
  -- dato no estorba (el teléfono manda) — sin él, el veredicto diría «en
  -- bolsa» y la toma rebotaría en bucle contra su propio blanco telefónico.
  if exists (
    select 1
    from crm.leads l
    where l.id <> v_lead.id
      and l.activo = true
      and l.etapa not in ('convertido', 'descartado')
      and (l.vendedor_id is not null or l.asignado_supervisor_id is not null)
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  v_propietario_anterior := coalesce(v_lead.vendedor_id, v_lead.asignado_supervisor_id);
  v_ultima_conv := (
    select pg_catalog.max(a.creado_en)
    from crm.actividades a
    where a.lead_id = v_lead.id
      and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
  );

  if v_lead.activo = true
     and v_lead.etapa not in ('convertido', 'descartado')
     and v_lead.vendedor_id is null
     and v_lead.asignado_supervisor_id is null then
    v_modo := 'bolsa';
    v_quedo_libre_en := null;
  elsif v_lead.etapa = 'descartado' then
    if v_lead.activo = false then
      -- Un soft-borrado no se revive por esta puerta (regla del plan).
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;
    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);
    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    if v_dias = 0
       and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
      -- Carencia de Miguel: un descarte de 0 días espera 24 h para TOMARSE.
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    v_modo := 'reutilizable';
    v_quedo_libre_en := case
      when v_dias > 0 then v_disponible_desde
      else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
    end;
  else
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- La válvula, SOLO alrededor del UPDATE, y quien la enciende la apaga.
  v_previo := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);

  if v_modo = 'bolsa' then
    update crm.leads l
       set vendedor_id = v_actor
     where l.id = v_lead.id
       and l.activo = true
       and l.no_contactar = false
       and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
       and l.etapa not in ('convertido', 'descartado')
       and l.vendedor_id is null
       and l.asignado_supervisor_id is null;
  else
    begin
      update crm.leads l
         set etapa = 'nuevo',
             vendedor_id = v_actor,
             asignado_supervisor_id = null,
             motivo_descarte = null
       where l.id = v_lead.id
         and l.activo = true
         and l.no_contactar = false
         and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
         and l.etapa = 'descartado';
    exception
      when unique_violation then
        -- Los índices de dedup (solo vivos) cazaron un vivo del mismo
        -- contacto: nadie roba, se responde la verdad fresca. El DNI del
        -- BLANCO entra en la consulta a propósito: el choque pudo venir por
        -- un dato que el vendedor no tecleó, y sin él el veredicto repetiría
        -- 'reutilizable' e invitaría a un bucle de reintentos.
        perform pg_catalog.set_config('crm.toma_directa', v_previo, true);
        return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
          private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
    end;
  end if;

  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);

  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;
  -- F2.b [D-13] (Codex #5): un lead vivo con el DNI de una persona reconocida queda ENLAZADO al tomarse (como al
  -- nacer): así la reserva, el sellado y las conversiones lo ven por identidad. Solo inversionista_id, bajo válvula
  -- (el trigger zz escribe el puente canónico). Si el lead ya está en el puente de OTRA persona, no se toma.
  if v_flag_d13 and v_lead.dni is not null and v_lead.inversionista_id is null then
    v_inv_reabre := private.inversionista_por_documento('DNI', v_lead.dni);
    if v_inv_reabre is not null then
      if exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = v_lead.id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv_reabre) then
        raise exception 'Este lead pertenece a otra persona según su puente: corrección o fusión de Gerencia' using errcode = 'P0409';
      end if;
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.leads set inversionista_id = v_inv_reabre where id = v_lead.id and inversionista_id is null;
      perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
    end if;
  end if;

  -- Traza §9 (además de la cascada, que ya asentó 'reasignacion' + ledger):
  -- la nota rica del evento, firmada por quien tomó.
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en)
  values (
    v_lead.id,
    'nota',
    case v_modo
      when 'bolsa' then 'Lead tomado desde la bolsa tras verificación de disponibilidad'
      else 'Lead tomado después de liberación por enfriamiento vencido'
    end,
    pg_catalog.jsonb_build_object(
      'evento', 'toma_directa',
      'modo', v_modo,
      'propietario_anterior', v_propietario_anterior,
      'ultima_conversacion', v_ultima_conv,
      'quedo_libre_en', v_quedo_libre_en,
      'motivo', case v_modo when 'bolsa' then 'toma_de_bolsa' else 'enfriamiento_vencido' end
    ),
    v_actor,
    pg_catalog.statement_timestamp()
  );

  -- La fila FINAL (los BEFORE ya subieron ciclo y renacieron tenencia).
  select l.* into v_lead from crm.leads l where l.id = v_lead.id;

  return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
    pg_catalog.jsonb_build_object(
      'estado', 'tomado_ok',
      'lead_id', v_lead.id,
      'modo', v_modo,
      'etapa', v_lead.etapa,
      'ciclo_actual', v_lead.ciclo_actual,
      'tenencia_desde', v_lead.tenencia_desde
    ));
end;
$function$
;

-- ============================================================================
-- 4. Conversiones: el puente del propio lead manda
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.convertir_lead(p_lead_id uuid, p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text := private.rol_crm((select auth.uid()));
  v_lead       crm.leads%rowtype;
  v_dni_perfil text;
  v_tipo_perfil text;
  v_asesor     uuid;
  v_flag       boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_inv        uuid;
  v_lead_canon uuid;
  v_clave      text;
  v_hash       text;
  v_prev       jsonb;
  v_res        jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- IDEMPOTENCIA (contrato §8.2, Codex #5): misma clave + mismo payload -> mismo
  -- resultado, sin efectos. Misma clave con otro payload -> P0409.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto, sin idempotencia.)
  if v_flag then
    v_clave := 'conversion:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object('lead', p_lead_id, 'perfil', p_perfil_id));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Con bandera ON el documento del perfil se lee ANTES del lead para tomar la
  -- identidad primero (orden identidad->lead). Con bandera OFF nada de esto corre
  -- y el perfil se lee DESPUÉS del lock del lead (idéntico a hoy, ver más abajo).
  if v_flag then
    select dni, tipo_documento, asesor_perfil_id
      into v_dni_perfil, v_tipo_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
    -- fail-closed (contrato §4.3): sin documento válido no se confirma identidad.
    if v_dni_perfil is null or pg_catalog.btrim(v_dni_perfil) = '' or v_tipo_perfil is null then
      raise exception 'No se puede convertir sin documento valido del cliente'
        using errcode = '22023';
    end if;
    -- Reusar la identidad del perfil si ya existe (una corrección de documento no
    -- parte a la persona); seguir la canónica si esa identidad está fusionada.
    select coalesce(inv.inversionista_canonico_id, inv.id)
      into v_inv
    from crm.inversionistas inv
    where inv.perfil_id = p_perfil_id
    order by (inv.estado <> 'fusionado') desc, inv.creado_en asc
    limit 1;
    -- Si el perfil aún no tiene identidad, EL PUNTO ÚNICO la resuelve/crea
    -- (advisory documental interno + índice único arbitran la carrera).
    if v_inv is null then
      v_inv := private.inversionista_resolver(v_tipo_perfil, v_dni_perfil, true, 'conversion');
    end if;
    -- Serializar por IDENTIDAD, no solo por documento: dos documentos vigentes de
    -- la misma persona convergen en esta fila y aquí se ordenan (Codex #3).
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b5) [Cx-15, E3-1]: una fusión pudo ganar mientras se esperaba este lock: la
    -- perdedora ya no convierte. Sin advisory documental AQUÍ a propósito: tomarlo después
    -- de la identidad invertiría el orden documento -> identidad que sigue la fusión.
    if exists (select 1 from crm.inversionistas i where i.id = v_inv and i.estado = 'fusionado') then
      raise exception 'La persona fue fusionada mientras se convertía; vuelve a intentarlo'
        using errcode = '40001';
    end if;
  end if;

  -- ── LEAD: ámbito + lock, y revalidación tras esperar ─────────────────────
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito (el lead ya se convirtió a ESTE perfil): mismo resultado,
  -- sin efectos. Si la clave no se alcanzó a guardar (caída), se guarda ahora.
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock, INCONDICIONALMENTE (Codex): si otro ya guardó la clave,
    -- se devuelve ESE resultado; si el payload difiere (p.ej. otro perfil para el
    -- mismo lead), idem_leer lanza P0409 aquí, ya serializado — no «lead ya cerrado».
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
    -- Sin clave guardada (conversión previa a este lote) y mismo perfil: mismo hecho.
    if v_lead.perfil_id = p_perfil_id then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', private.inversionista_canonica(v_lead.inversionista_id));
      perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Con bandera OFF: leer el perfil AHORA (tras el lock del lead), IDÉNTICO a la
  -- versión previa (misma precedencia de errores).
  if not v_flag then
    select dni, asesor_perfil_id
      into v_dni_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
  end if;

  if v_lead.dni is not null
     and v_dni_perfil is not null
     and v_lead.dni <> v_dni_perfil then
    raise exception 'El documento del cliente no coincide con el del lead';
  end if;

  if v_rol <> 'gerencia'
     and (
       v_asesor is null
       or v_asesor not in (
         select private.vendedor_ids_visibles((select auth.uid()))
       )
     )
     and not (
       v_lead.dni is not null
       and v_dni_perfil is not null
       and v_lead.dni = v_dni_perfil
     ) then
    raise exception 'Ese cliente no pertenece a tu cartera';
  end if;

  -- Invariante #6 (un solo lead total): si la identidad YA tiene otro lead, esta
  -- persona no puede abrir un segundo. Mensaje de negocio en vez del choque crudo
  -- con leads_inversionista_uidx. (Una nueva inversión sobre el cliente existente
  -- es F5, no una nueva conversión — decisión de Miguel 03/09.)
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon
    from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id
    limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva
  -- por persona (D-10): un lead que solo está en el puente pertenece a la persona de su puente.
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #2): una reserva viva o sellada de ESTE lead pertenece a UNA persona (b4): no se convierte para
  -- otra por la puerta directa; el cierre de la saga trae la misma persona y pasa.
  if v_flag and exists (select 1 from crm.conversion_reservas r
                         where r.lead_id = p_lead_id and r.inversionista_id is not null
                           and r.inversionista_id is distinct from v_inv
                           and (r.efectos_iniciados_en is not null or r.expira_en > pg_catalog.now())) then
    raise exception 'Este lead está reservado para otra persona: espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;

  -- ── EL CIERRE: etapa + perfil + inversionista_id EN EL MISMO UPDATE ──────
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         perfil_id = p_perfil_id,
         convertido_en = pg_catalog.now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- ── Reconocimiento de identidad (reemplaza al trigger 200000, solo bandera) ─
  if v_flag and v_inv is not null then
    -- Vincular perfil<->identidad y registrar el lead canónico.
    update crm.inversionistas set perfil_id = p_perfil_id
      where id = v_inv and perfil_id is null;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);

    -- Responsable de relación (asesor del perfil), si está activo y la persona no
    -- tiene tramo abierto. (Lo hacía el trigger 200000:125-131.)
    if v_asesor is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir
                        where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_asesor, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_asesor
        where id = v_inv and responsable_relacion_id is null;
    end if;

    -- no_contactar del lead se centraliza en la persona. (Trigger 200000:134-137.)
    if v_lead.no_contactar then
      update crm.inversionistas
        set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;

    -- El contrato/inversión Avance lo crea su propia puerta (crear_contrato), no
    -- esta función: aquí solo se reconoce la persona (contrato §8.2).
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido a cliente',
    pg_catalog.jsonb_build_object('perfil_id', p_perfil_id),
    v_uid
  );

  v_res := pg_catalog.jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'perfil_id', p_perfil_id,
    'inversionista_id', v_inv
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.convertir_lead_externo(p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text DEFAULT NULL::text, p_vence_en date DEFAULT NULL::date, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
  v_flag        boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_inv         uuid;
  v_lead_canon  uuid;
  v_clave       text;
  v_hash        text;
  v_prev        jsonb;
  v_res         jsonb;
begin
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- IDEMPOTENCIA (contrato §8.3, Codex #5): misma clave + mismo payload -> mismo
  -- resultado; misma clave con otro payload -> P0409. Se evalúa ANTES de validar
  -- para que un reintento idéntico ni siquiera toque el lead.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto.) El hash cubre
  -- TODO lo que se persiste (Codex), con el número de operación en MAYÚSCULAS como
  -- se compara y reclama.
  if v_flag then
    v_clave := 'conversion_coop:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object(
                 'lead', p_lead_id, 'coop', p_cooperativa, 'monto', p_monto, 'moneda', p_moneda,
                 'tipo', p_documento_tipo, 'doc', v_documento, 'trx', upper(v_transaccion),
                 'nombre', v_nombre, 'ref', v_referencia, 'vence', p_vence_en,
                 'nota', nullif(btrim(coalesce(p_nota,'')), '')));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;

  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- En cooperativas solo se invierte en soles. Se valida en vez de forzar: un
  -- bundle viejo que mande USD merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto como si fueran soles.
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Resolver ANTES del lock del lead (orden identidad->lead, comparte orden con
  -- la fusión y mata el deadlock). El documento ya se validó arriba. Con bandera
  -- APAGADA nada de esto corre (comportamiento idéntico a hoy).
  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b4): la PERSONA (no solo este lead) puede tener una conversión Avance en curso en OTRO
    -- lead: reserva viva o sellada con su inversionista_id. Lectura bajo el lock de la identidad
    -- (el sellado también lo toma desde b4): orden identidad -> lead -> reserva, sin cambios.
    if exists (select 1 from crm.conversion_reservas r
                where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                  and (r.efectos_iniciados_en is not null or r.expira_en > now())) then
      raise exception using
        errcode = 'P0409',
        message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
        hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
    end if;
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito: el lead ya se convirtió y su cierre lleva ESTE número de
  -- operación -> mismo resultado, sin efectos (idempotente).
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock (Codex): la clave guardada manda; payload distinto → P0409.
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (p.ej. conversión previa a este lote): mismo número de
    -- operación en su cierre = mismo hecho.
    select ce.id into v_cierre_id
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and upper(ce.numero_transaccion) = upper(v_transaccion)
    limit 1;
    if v_cierre_id is not null then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'cierre_id', v_cierre_id,
                                             'cooperativa', p_cooperativa);
      perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Un solo lead total (invariante #6, decisión Miguel 03/09): un 2.º lead de la
  -- misma persona no se convierte aquí; la nueva inversión sobre el cliente
  -- existente es F5. Mensaje de negocio en vez del choque con leads_inversionista_uidx.
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva
  -- por persona (D-10): un lead que solo está en el puente pertenece a la persona de su puente.
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por, inversionista_id
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, p_vence_en, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid, v_inv
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  -- Inversión (colgada de la identidad) + titular principal (solo bandera).
  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura'), false) then
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, ce.id, 'vigente',
           least((ce.creado_en at time zone 'America/Lima')::date, (pg_catalog.now() at time zone 'America/Lima')::date),
           not exists (select 1 from crm.inversiones inv2 where inv2.inversionista_id = v_inv),
           ce.creado_por
    from crm.cierres_externos ce join crm.empresas e on e.clave = ce.cooperativa
    where ce.id = v_cierre_id and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = ce.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = v_cierre_id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id = inv.id and it.rol='principal');
  end if;

  -- El cierre del lead. inversionista_id viaja en el MISMO UPDATE bajo la válvula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Reconocimiento de identidad (reemplaza al trigger 200000 para coop).
  if v_flag and v_inv is not null then
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);
    -- Responsable de relación = vendedor del cierre (si activo y sin tramo abierto).
    if v_lead.vendedor_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_lead.vendedor_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_lead.vendedor_id, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_lead.vendedor_id
        where id = v_inv and responsable_relacion_id is null;
    end if;
    -- no_contactar del lead se centraliza en la persona.
    if v_lead.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  v_res := jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$
;

-- ============================================================================
-- 5. Sellado de la conversión: «un solo lead» bajo el lock de la persona, antes del punto de no retorno
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid, p_claim_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_loc record;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token)
     or (v_loc.estado->>'lead_id')::uuid is distinct from p_lead_id then
    raise exception 'Saga: claim o token inválidos para este lead' using errcode = '42501';
  end if;
  -- La reserva de este lead debe ser de este claim y de su identidad (Codex E2 #5).
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead no corresponde a este claim' using errcode = 'P0409';
  end if;
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona del claim pudo fusionarse: reintentar (la fusión exige claims terminales).
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.estado = 'fusionado') then
    raise exception 'La persona de este claim fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (Codex #1): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno:
  -- un lead de esta persona nacido, reabierto o tomado mientras la reserva esperaba (o ya vencida) no deja cuentas
  -- de portal huérfanas: no se sella, y Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_identidades(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  return crm.marcar_efectos_conversion(p_lead_id);
end;
$function$
;

-- ============================================================================
-- 6. Reactivaciones (rescate de supervisión y deshacer descarte): juicio de identidad + enlazar al reabrir
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.rescatar_descartes(p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_destinos_validos uuid[];
  v_total_episodios integer;
  v_total_destinos integer;
  v_candidatos integer := 0;
  v_orden integer := 0;
  v_intento integer;
  v_destino uuid;
  v_fila record;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_veredicto jsonb;
  v_inv_reabre uuid;
begin
  if p_episodios is null
     or pg_catalog.array_length(p_episodios, 1) is null
     or pg_catalog.array_length(p_episodios, 1) = 0
     or pg_catalog.array_length(p_episodios, 1) > 100
     or pg_catalog.array_position(p_episodios, null) is not null then
    raise exception 'Selecciona entre 1 y 100 descartes válidos'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_episodios) as u(id)
  ) episodios_unicos) <> pg_catalog.array_length(p_episodios, 1) then
    raise exception 'Un descarte no se puede enviar dos veces en el mismo reparto'
      using errcode = '22023';
  end if;

  if p_analistas_destino is null
     or pg_catalog.array_length(p_analistas_destino, 1) is null
     or pg_catalog.array_length(p_analistas_destino, 1) = 0
     or pg_catalog.array_length(p_analistas_destino, 1) > 30
     or pg_catalog.array_position(p_analistas_destino, null) is not null then
    raise exception 'Selecciona al menos un asesor destino'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_analistas_destino) as u(id)
  ) destinos_unicos) <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'No repitas un asesor destino'
      using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede rescatar descartes'
      using errcode = '42501';
  end if;

  select pg_catalog.array_agg(destino.id order by destino.orden)
    into v_destinos_validos
  from (
    select u.id, u.orden
    from pg_catalog.unnest(p_analistas_destino) with ordinality as u(id, orden)
    join crm.equipo e on e.perfil_id = u.id
    join public.perfiles p on p.id = e.perfil_id
    where e.activo = true
      and p.activo = true
      and e.rol_crm = 'vendedor'
      and (
        v_rol = 'gerencia'
        or e.perfil_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
  ) destino;

  v_total_destinos := coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);  -- F2.b (b2): pg_catalog.coalesce no existe (bug desde 20/08)
  if v_total_destinos <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'Uno de los asesores destino no está activo o no pertenece a tu equipo'
      using errcode = '22023';
  end if;

  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id,
      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar,  -- veto de la PERSONA
      l.telefono, l.dni, l.inversionista_id
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and la.resultado_en is not null
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and (
        v_rol = 'gerencia'
        or la.analista_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
    order by la.resultado_en, la.id
    for update of l
  loop
    v_candidatos := v_candidatos + 1;
    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b (b2): también por documento exacto (lead suelto de una persona vetada).
    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b [D-13] (auditor M1 / Codex #6): con la identidad encendida, un descartado cuyo documento pertenece a una
    -- persona que ya es cliente, ya tiene OTRO lead (enlace vivo o puente) o está en conversión no se reactiva
    -- (todo el lote falla, como con el veto). Si el lead ya está en el puente de OTRA persona, tampoco.
    if v_flag and v_fila.dni is not null then
      v_veredicto := private.verificar_disponibilidad_lead_impl(v_fila.telefono, v_fila.dni, v_fila.lead_id);
      if v_veredicto->>'estado' = 'ya_es_cliente' then
        raise exception 'Uno de los leads pertenece a una persona que ya es cliente o ya tiene su lead y no puede reactivarse'
          using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', v_veredicto->>'via', 'lead_id', v_fila.lead_id)::text;
      end if;
      if v_fila.inversionista_id is null
         and exists (select 1 from crm.inversionista_leads il
                      where il.lead_id = v_fila.lead_id
                        and private.inversionista_canonica(il.inversionista_id) is distinct from private.inversionista_por_documento('DNI', v_fila.dni)) then
        raise exception 'Uno de los leads pertenece a otra persona según su puente: corrección o fusión de Gerencia'
          using errcode = 'P0409';
      end if;
    end if;
  end loop;

  v_total_episodios := pg_catalog.array_length(p_episodios, 1);
  if v_candidatos <> v_total_episodios then
    raise exception 'Uno de los descartes ya no está disponible para rescate'
      using errcode = 'P0002';
  end if;

  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id,
      l.dni, l.inversionista_id
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
    order by la.resultado_en, la.id
  loop
    v_destino := null;
    for v_intento in 0..(v_total_destinos - 1) loop
      v_destino := v_destinos_validos[((v_orden + v_intento) % v_total_destinos) + 1];
      exit when not p_evitar_asesor_origen or v_destino is distinct from v_fila.asesor_origen_id;
    end loop;

    if v_destino is null
       or (p_evitar_asesor_origen and v_destino = v_fila.asesor_origen_id) then
      raise exception 'No hay otro asesor destino para uno de los descartes seleccionados'
        using errcode = '22023';
    end if;

    update crm.leads
       set etapa = 'nuevo',
           motivo_descarte = null,
           vendedor_id = v_destino,
           asignado_supervisor_id = null
     where id = v_fila.lead_id;
  -- F2.b [D-13] (auditor M1 / Codex #6): un lead vivo con el DNI de una persona reconocida queda ENLAZADO al reabrirse
  -- (como al nacer). Solo inversionista_id, bajo válvula (el trigger zz escribe el puente canónico).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and v_fila.dni is not null and v_fila.inversionista_id is null then
    v_inv_reabre := private.inversionista_por_documento('DNI', v_fila.dni);
    if v_inv_reabre is not null then
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.leads set inversionista_id = v_inv_reabre where id = v_fila.lead_id and inversionista_id is null;
      perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
    end if;
  end if;

    v_orden := v_orden + 1;
  end loop;

  return pg_catalog.jsonb_build_object(
    'rescatados', v_candidatos,
    'asesores_destino', v_total_destinos
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION private.deshacer_descarte_implementacion(p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := (select auth.uid());
  v_ventana interval := interval '24 hours';
  v_lead    crm.leads%rowtype;
  v_veredicto jsonb;
  v_inv_reabre uuid;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede deshacer un descarte'
      using errcode = '42501';
  end if;

  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa = 'descartado'
    and l.descartado_por = v_actor
    and l.descartado_en > (statement_timestamp() - v_ventana)
  for update;
  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
  -- F2.b (b2): gemela de rescatar_descartes: una persona vetada no se reabre.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (auditor M1 / Codex #6): gemela de rescatar_descartes: con la identidad encendida, un descartado
  -- cuyo documento pertenece a una persona que ya es cliente, ya tiene OTRO lead o está en conversión no se reabre.
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and v_lead.dni is not null then
    v_veredicto := private.verificar_disponibilidad_lead_impl(v_lead.telefono, v_lead.dni, v_lead.id);
    if v_veredicto->>'estado' = 'ya_es_cliente' then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', v_veredicto->>'via', 'lead_id', v_lead.id)::text;
    end if;
    if v_lead.inversionista_id is null
       and exists (select 1 from crm.inversionista_leads il
                    where il.lead_id = v_lead.id
                      and private.inversionista_canonica(il.inversionista_id) is distinct from private.inversionista_por_documento('DNI', v_lead.dni)) then
      raise exception 'Este lead pertenece a otra persona según su puente: corrección o fusión de Gerencia' using errcode = 'P0409';
    end if;
  end if;

  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
     where id = p_lead and activo = true and etapa = 'descartado'
       and vendedor_id is null and asignado_supervisor_id is null;
    if not found then
      raise exception 'El descarte ya no se puede deshacer (carrera)'
        using errcode = 'P0002';
    end if;
  exception
    when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir'
        using errcode = '22023';
  end;

  -- F2.b [D-13] (auditor M1 / Codex #6): un lead vivo con el DNI de una persona reconocida queda ENLAZADO al reabrirse
  -- (como al nacer). Solo inversionista_id, bajo válvula (el trigger zz escribe el puente canónico).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and v_lead.dni is not null and v_lead.inversionista_id is null then
    v_inv_reabre := private.inversionista_por_documento('DNI', v_lead.dni);
    if v_inv_reabre is not null then
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.leads set inversionista_id = v_inv_reabre where id = p_lead and inversionista_id is null;
      perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
    end if;
  end if;

  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'etapa', v_lead.etapa,
    'ciclo_actual', v_lead.ciclo_actual,
    'reabierto_por', v_actor,
    'reabierto_en', statement_timestamp());
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text, p_excluir_lead_id uuid') is distinct from 'c5ed89a08461453c5a02f7ea559207d9' then
    raise exception 'POSTFLIGHT D-13: private.verificar_disponibilidad_lead_impl(text,text,uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_zz_enlaza_identidad' and pg_get_function_identity_arguments(p.oid)='') is distinct from '62cebe9fbebf0f9a1ac617acba4ac3d7' then
    raise exception 'POSTFLIGHT D-13: private.trg_leads_zz_enlaza_identidad() no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='tomar_lead_libre' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '596ccbcb365923406d9a96efdc9f081a' then
    raise exception 'POSTFLIGHT D-13: crm.tomar_lead_libre(text,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_perfil_id uuid') is distinct from '8bd4d8c94aeb79b92bf6638bb16aeea0' then
    raise exception 'POSTFLIGHT D-13: crm.convertir_lead(uuid,uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text') is distinct from '29d5bffdb76f47fe2048f450412c8be5' then
    raise exception 'POSTFLIGHT D-13: crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text') is distinct from 'b006033723cb3f210dc8e73fd05087b9' then
    raise exception 'POSTFLIGHT D-13: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes' and pg_get_function_identity_arguments(p.oid)='p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean') is distinct from 'e65beebf90da4e03ac51e62755605bfd' then
    raise exception 'POSTFLIGHT D-13: crm.rescatar_descartes(uuid[],uuid[],boolean) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion' and pg_get_function_identity_arguments(p.oid)='p_lead uuid') is distinct from '6d1612339d1ed900f73b32aeae227d43' then
    raise exception 'POSTFLIGHT D-13: private.deshacer_descarte_implementacion(uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '742d44fff6a8a742292c8de702812e60' then
    raise exception 'D-13: la sobrecarga de 2 argumentos del verificador (solo delega) cambió';
  end if;
  if exists (select 1 from unnest(array['private.verificar_disponibilidad_lead_impl(text,text,uuid)','private.verificar_disponibilidad_lead_impl(text,text)','private.trg_leads_zz_enlaza_identidad()']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure,'private.verificar_disponibilidad_lead_impl(text,text)'::regprocedure,'private.trg_leads_zz_enlaza_identidad()'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: las funciones privadas del verificador/trigger no pueden tener EXECUTE para la API ni PUBLIC';
  end if;
  if exists (select 1 from unnest(array['crm.tomar_lead_libre(text,text)','crm.convertir_lead(uuid,uuid)','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)','crm.marcar_efectos_conversion(uuid,uuid,text)','crm.rescatar_descartes(uuid[],uuid[],boolean)']) f(firma)
              where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.tomar_lead_libre(text,text)'::regprocedure,'crm.convertir_lead(uuid,uuid)'::regprocedure,'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure,'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure,'crm.rescatar_descartes(uuid[],uuid[],boolean)'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: los grants de las RPC transformadas cambiaron (solo authenticated)';
  end if;
  if exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, 'private.deshacer_descarte_implementacion(uuid)', 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.deshacer_descarte_implementacion(uuid)'::regprocedure and a.grantee = 0) then
    raise exception 'D-13: private.deshacer_descarte_implementacion no puede tener EXECUTE para la API ni PUBLIC';
  end if;
  if to_regprocedure('private.persona_en_conversion(uuid,uuid)') is null
     or exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, 'private.persona_en_conversion(uuid,uuid)', 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.persona_en_conversion(uuid,uuid)'::regprocedure and a.grantee = 0)
     or not exists (select 1 from pg_proc p where p.oid = 'private.persona_en_conversion(uuid,uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT D-13: el helper persona_en_conversion falta, tiene grants indebidos o perdió definer/search_path';
  end if;
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                   where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_hereda_veto' and not t.tgisinternal and t.tgenabled = 'O'
                     and pg_get_triggerdef(t.oid) like '%BEFORE INSERT ON crm.leads%'
                     and strpos(p.prosrc, 'identidad_bloquear_documento') > 0) then
    raise exception 'F2.b D-13: falta la premisa de serialización: trg_leads_000_hereda_veto (BEFORE INSERT, habilitado) tomando private.identidad_bloquear_documento (b1)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-13: la bandera resolver_en_puertas está ENCENDIDA';
  end if;
  raise notice 'F2.b D-13 OK: un solo lead (enlace vivo ∪ puente) y persona en conversión en el verificador, el nacimiento del lead y la toma; el puente del propio lead manda en las conversiones (rama ON). Bandera APAGADA.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;
