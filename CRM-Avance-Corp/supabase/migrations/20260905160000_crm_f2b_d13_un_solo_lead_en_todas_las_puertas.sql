-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-13] — «UN SOLO LEAD» Y «EL PUENTE
-- MANDA» EN TODAS LAS PUERTAS CON LA BANDERA ENCENDIDA (bloque 2; auditor D-10 M2, Codex D-10 #2/#3/#5, Codex D-13 #1-#9)
-- ============================================================================
--
-- QUE (todo dentro de la rama ON; con la bandera APAGADA las nueve funciones responden como hoy, el trigger es inerte y la puerta del DNI es el UPDATE de hoy):
--   * «Los leads de una persona» = enlace vivo ∪ puente ∪ SUELTOS vivos con un documento vigente de la persona (nacieron
--     antes de que existiera la persona): private.leads_de_personas. Cuenta en el verificador de disponibilidad, el
--     nacimiento del lead, la toma, el rescate, el deshacer, el sellado, las dos conversiones y la reserva por persona (D-10).
--   * Una persona EN CONVERSIÓN (reserva viva o sellada de otro lead) o que YA ES CLIENTE (perfil, activo o no) no recibe otro lead.
--   * Reabrir o tomar un lead lo ENLAZA a su persona (documento o puente), como al nacer; el juicio es único
--     (private.juicio_reapertura) y los candados van ANTES de la fila (documento -> persona -> lead, el orden de la reserva,
--     el sellado y la fusión): private.bloquear_personas_de_leads. Reabrir un descarte con la bandera encendida solo se
--     puede por esas puertas (trigger trg_leads_zz_reapertura_solo_rpc); el UPDATE directo de etapa no.
--   * El sellado de la conversión toma los documentos de la persona, bloquea a la persona, revalida la pareja
--     (lead, claim, persona) bajo el lock de la reserva, el estado del lead y «un solo lead» ANTES del punto de no retorno.
--   * Las conversiones respetan el puente del propio lead; convertir_lead no convierte un lead reservado para otra persona ni
--     mientras la persona tiene otra conversión Avance en curso (como la coop).
--   * El DNI de un lead se FIJA por su puerta (crm.fijar_dni_lead_fn: candado del documento y persona ANTES de la fila,
--     juicio de la persona, enlace si existe); el UPDATE directo de dni queda cerrado con la bandera encendida.
-- Generada desde el texto VIVO (scripts/f2b/gen-d13.py, vivas/d13, huellas-d13-prod.txt): 8 funciones de producción y la
-- reserva por persona tal como la deja D-10 (20260905150000), que por eso es REQUISITO. Guardas md5 EXACTAS, postflight byte
-- a byte, grants comprobados. Ensayo: scripts/oraculo-f2b-d13.sh. Reversa: scripts/rollback-f2b-d13.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d13_un_solo_lead_todas_las_puertas'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('private.identidad_bloquear_documento(text,text)') is null
     or to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null
     or to_regprocedure('private.inversionista_canonica(uuid)') is null
     or to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.toma_asienta_y_devuelve(uuid,text,text,text,jsonb)') is null
     or to_regprocedure('private.trg_leads_hereda_veto_persona()') is null then
    raise exception 'F2.b D-13: faltan b1 (20260904120000), b2 (20260904130000) o b5 (20260905120000)';
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
  if v_h is distinct from '5f99912dde92e5b0ff1720077377a172' and v_h is distinct from '4a2d7b8b3d1030d6ab96009e933af6cc' then
    raise exception 'F2.b D-13: private.verificar_disponibilidad_lead_impl(text,text,uuid) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_zz_enlaza_identidad' and pg_get_function_identity_arguments(p.oid)='');
  if v_h is null then
    raise exception 'F2.b D-13: falta private.trg_leads_zz_enlaza_identidad()';
  end if;
  if v_h is distinct from '7986b01ab6109bd15d228157cef3ef33' and v_h is distinct from 'd6fa34cabc1ada619e50ecb114f5255b' then
    raise exception 'F2.b D-13: private.trg_leads_zz_enlaza_identidad() no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='tomar_lead_libre' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.tomar_lead_libre(text,text)';
  end if;
  if v_h is distinct from '045d22cf0b5f62a98008cd5e04ae4d78' and v_h is distinct from 'cf1c6d953df901c3373304206a3560ab' then
    raise exception 'F2.b D-13: crm.tomar_lead_libre(text,text) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_perfil_id uuid');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.convertir_lead(uuid,uuid)';
  end if;
  if v_h is distinct from 'c30a0ac9be5f44bc1caa129bc90a2ea7' and v_h is distinct from '1d3f437cafe73d2e4076bb68158af812' then
    raise exception 'F2.b D-13: crm.convertir_lead(uuid,uuid) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)';
  end if;
  if v_h is distinct from '0272febed241415d7c1cfcdf70bed37b' and v_h is distinct from '3ff4aa7ec25751ba028af596c9fed6a2' then
    raise exception 'F2.b D-13: crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.marcar_efectos_conversion(uuid,uuid,text)';
  end if;
  if v_h is distinct from '8ab20f7fb4842caaed5ad705db5e91b2' and v_h is distinct from '511c059250774b625c8bc3274523e61a' then
    raise exception 'F2.b D-13: crm.marcar_efectos_conversion(uuid,uuid,text) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes' and pg_get_function_identity_arguments(p.oid)='p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.rescatar_descartes(uuid[],uuid[],boolean)';
  end if;
  if v_h is distinct from '89778f4d57b3421a69628473520c6f41' and v_h is distinct from '38d5869195a00c82437cbfb3298df8e7' then
    raise exception 'F2.b D-13: crm.rescatar_descartes(uuid[],uuid[],boolean) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion' and pg_get_function_identity_arguments(p.oid)='p_lead uuid');
  if v_h is null then
    raise exception 'F2.b D-13: falta private.deshacer_descarte_implementacion(uuid)';
  end if;
  if v_h is distinct from 'b14b91bf82827240a3a29e88a5b9e39f' and v_h is distinct from '5e343627436b8532215501d38aecafeb' then
    raise exception 'F2.b D-13: private.deshacer_descarte_implementacion(uuid) no es ni el texto vivo esperado (producción) ni el de D-13 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb');
  if v_h is null then
    raise exception 'F2.b D-13: falta crm.reservar_conversion_lead(uuid,text,text,jsonb)';
  end if;
  if v_h is distinct from 'b6c1863eec07df43e2023e7e8d729d05' and v_h is distinct from '8ec13410c8f18a3b3004a7321afe9398' then
    raise exception 'F2.b D-13: crm.reservar_conversion_lead(uuid,text,text,jsonb) no es ni el texto vivo esperado (D-10) ni el de D-13 (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 0. Helpers privados (definer, search_path '', sin EXECUTE a la API)
-- ============================================================================
-- 0.1 ¿La persona está EN CONVERSIÓN? Reserva por persona viva o sellada de un lead aún no convertido (mismo predicado
--     que private.fusion_bloqueos, b5). Los claims no cuentan: un claim abandonado sin reserva no debe bloquear para siempre.
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

-- 0.2 «Los leads de una persona» = enlace vivo ∪ puente (private.leads_de_identidades, b5) ∪ los SUELTOS que llevan un
--     documento vigente de la persona (nacieron antes de que existiera la persona, o su DNI llegó después): vivos o convertidos,
--     no los descartados (esos los ofrece el camino «reutilizable» y los juzga la reapertura). Codex D-13 #1/#3/#6.
create or replace function private.leads_de_personas(p_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x from private.leads_de_identidades(p_ids) x
  union
  select l.id
  from crm.leads l
  join crm.inversionista_identificadores d
    on d.tipo_documento = 'DNI' and d.estado = 'vigente' and d.verificado = true and d.documento_normalizado = l.dni
  where d.inversionista_id = any(p_ids)
    and l.inversionista_id is null
    and l.activo = true
    and l.etapa <> 'descartado'
$$;
revoke all on function private.leads_de_personas(uuid[]) from public, anon, authenticated, service_role;

-- 0.3 La persona de un lead a efectos de reapertura: su enlace (por la canónica), o la del documento, o la de su puente.
create or replace function private.lead_persona_reabrir(p_lead_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select private.inversionista_canonica(l.inversionista_id) from crm.leads l where l.id = p_lead_id and l.inversionista_id is not null),
    (select private.inversionista_por_documento('DNI', l.dni) from crm.leads l where l.id = p_lead_id and l.dni is not null),
    (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
      where il.lead_id = p_lead_id order by (il.rol = 'canonico') desc, il.id limit 1))
$$;
revoke all on function private.lead_persona_reabrir(uuid) from public, anon, authenticated, service_role;

-- 0.4 Candados ANTES de tocar filas (orden total documento → persona → lead, el de la reserva, el sellado y la fusión):
--     todos los documentos implicados (los de los leads, el tecleado y los vigentes de sus personas) en orden de texto, y las
--     personas FOR SHARE en orden de id. Devuelve {personas, claves} bloqueadas para que el llamador verifique tras tomar la fila
--     que el documento actual del lead está entre las claves y su persona entre las personas (ABA cerrado, Codex v4.2).
--     Inerte con la bandera apagada.
create or replace function private.bloquear_personas_de_leads(p_leads uuid[], p_dni_extra text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_personas uuid[]; v_claves text[]; v_k text;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Codex v4.3 [2]: la comprobación «sigue dentro de lo bloqueado» relee tras esperar y eso solo vale en READ COMMITTED
  -- (en REPEATABLE READ el snapshot viejo esconde a una persona confirmada por otra transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  select pg_catalog.array_agg(distinct p order by p) into v_personas
  from (select private.lead_persona_reabrir(l.id) as p from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[]))
        union select private.inversionista_por_documento('DNI', p_dni_extra) where p_dni_extra is not null) s
  where p is not null;
  select pg_catalog.array_agg(distinct k order by k) into v_claves
  from (select 'DNI:' || l.dni as k from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[])) and l.dni is not null
        union select 'DNI:' || p_dni_extra where p_dni_extra is not null
        union select d.tipo_documento || ':' || d.documento_normalizado
                from crm.inversionista_identificadores d
               where d.inversionista_id = any(coalesce(v_personas, '{}'::uuid[])) and d.estado = 'vigente') s;
  if v_claves is not null then
    foreach v_k in array v_claves loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  if v_personas is not null then
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share;
  end if;
  -- Codex v4.3 [1]: identidad_bloquear_documento es un no-op si la bandera está APAGADA; si alguien la apagó entre la primera
  -- lectura y los candados, no hay candados reales → no se declara nada bloqueado (el llamador da veredicto fresco / 40001).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Devuelve lo que REALMENTE bloqueó (Codex v4.2, ABA): el llamador, tras tomar la fila, exige que el documento actual
  -- del lead esté entre las claves bloqueadas y su persona entre las bloqueadas; si no, veredicto fresco / 40001.
  return pg_catalog.jsonb_build_object('personas', pg_catalog.to_jsonb(coalesce(v_personas, '{}'::uuid[])),
                                       'claves', pg_catalog.to_jsonb(coalesce(v_claves, '{}'::text[])));
end;
$$;
revoke all on function private.bloquear_personas_de_leads(uuid[], text) from public, anon, authenticated, service_role;

-- 0.4b ¿El lead, ya bloqueado, sigue dentro de lo que se bloqueó? (documento actual entre las claves y persona entre las personas)
create or replace function private.lead_dentro_de_bloqueo(p_lead_id uuid, p_bloqueo jsonb)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select (l.dni is null or ('DNI:' || l.dni) in (select x from pg_catalog.jsonb_array_elements_text(p_bloqueo->'claves') x))
       and (private.lead_persona_reabrir(l.id) is null
            or private.lead_persona_reabrir(l.id)::text in (select x from pg_catalog.jsonb_array_elements_text(p_bloqueo->'personas') x))
    from crm.leads l where l.id = p_lead_id), false)
$$;
revoke all on function private.lead_dentro_de_bloqueo(uuid, jsonb) from public, anon, authenticated, service_role;

-- 0.5a Juicio de PERSONA: NULL si a la persona se le puede dar/reabrir el lead indicado; si no, el veredicto
--      (no_contactar si está vetada; ya_es_cliente si tiene OTRO lead, está en conversión o ya es cliente —perfil, activo o no—).
create or replace function private.juicio_persona(p_inv uuid, p_excluir_lead_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_asesor text;
begin
  if p_inv is null then return null; end if;
  if exists (select 1 from crm.inversionistas i where i.id = p_inv and i.no_contactar) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;
  select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado') into v_asesor
  from crm.inversionistas i
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  left join lateral (
    select p.nombre_completo from crm.conversion_reservas r join public.perfiles p on p.id = r.reservado_por
    left join crm.leads lr on lr.id = r.lead_id
    where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
      and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
    order by r.reservado_en desc limit 1) res on true
  where i.id = p_inv;
  if exists (select 1 from private.leads_de_personas(array[p_inv]) x where x is distinct from p_excluir_lead_id)
     or private.persona_en_conversion(p_inv, p_excluir_lead_id)
     or exists (select 1 from crm.inversionistas i where i.id = p_inv and i.perfil_id is not null) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_asesor, 'sin asesor asignado'), 'via', 'identidad');
  end if;
  return null;
end;
$$;
revoke all on function private.juicio_persona(uuid, uuid) from public, anon, authenticated, service_role;

-- 0.5 El JUICIO único de reapertura/toma: NULL si el lead puede reabrirse/tomarse; si no, el veredicto (forma del front:
--     estado ya_es_cliente, asesor, via identidad) que explica por qué. Reglas: cualquier ya_es_cliente del verificador con el
--     documento tecleado o con el del blanco; las personas halladas (enlace, documento tecleado, documento del blanco, puente)
--     deben ser UNA; la persona no puede tener OTRO lead (enlace ∪ puente ∪ suelto vivo con su documento), ni estar en
--     conversión, ni ser ya cliente (perfil, activo o no). Solo lecturas: se llama bajo los candados de 0.4 y la fila del lead.
create or replace function private.juicio_reapertura(p_lead_id uuid, p_telefono text, p_dni_tecleado text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lead crm.leads%rowtype; v_v jsonb; v_inv uuid; v_inv_tec uuid; v_inv_doc uuid; v_inv_puente uuid; v_asesor text;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then return null; end if;
  if p_dni_tecleado is not null then
    v_v := private.verificar_disponibilidad_lead_impl(p_telefono, p_dni_tecleado, p_lead_id);
    if v_v->>'estado' = 'ya_es_cliente' then return v_v; end if;
  end if;
  if v_lead.dni is not null and v_lead.dni is distinct from p_dni_tecleado then
    v_v := private.verificar_disponibilidad_lead_impl(p_telefono, v_lead.dni, p_lead_id);
    if v_v->>'estado' = 'ya_es_cliente' then return v_v; end if;
  end if;
  v_inv_tec := case when p_dni_tecleado is not null then private.inversionista_por_documento('DNI', p_dni_tecleado) end;
  v_inv_doc := case when v_lead.dni is not null then private.inversionista_por_documento('DNI', v_lead.dni) end;
  select private.inversionista_canonica(il.inversionista_id) into v_inv_puente
    from crm.inversionista_leads il where il.lead_id = p_lead_id order by (il.rol = 'canonico') desc, il.id limit 1;
  v_inv := coalesce(private.inversionista_canonica(v_lead.inversionista_id), v_inv_doc, v_inv_puente, v_inv_tec);
  -- Un CLIENTE del Portal con ese documento, aunque esté inactivo y sin ficha de persona, ya es cliente (Codex v3 M2).
  if exists (select 1 from public.perfiles per where per.rol = 'cliente' and per.dni is not null
              and coalesce(nullif(pg_catalog.btrim(per.tipo_documento), ''), 'DNI') = 'DNI'
              and per.dni in (p_dni_tecleado, v_lead.dni)) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente',
      'asesor', coalesce((select a.nombre_completo from public.perfiles per join public.perfiles a on a.id = per.asesor_perfil_id
                           where per.rol = 'cliente' and coalesce(nullif(pg_catalog.btrim(per.tipo_documento), ''), 'DNI') = 'DNI'
                             and per.dni in (p_dni_tecleado, v_lead.dni) limit 1), 'sin asesor asignado'),
      'via', 'identidad');
  end if;
  -- Una reserva viva o sellada (sin convertir) de ESTE lead también lo hace no reabrible/no tomable (auditor v3 N3).
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente',
      'asesor', coalesce((select p.nombre_completo from crm.conversion_reservas r join public.perfiles p on p.id = r.reservado_por where r.lead_id = p_lead_id), 'sin asesor asignado'),
      'via', 'identidad');
  end if;
  if v_inv is null then return null; end if;
  select coalesce(resp.nombre_completo, 'sin asesor asignado') into v_asesor
  from crm.inversionistas i left join public.perfiles resp on resp.id = i.responsable_relacion_id where i.id = v_inv;
  if (v_inv_tec is not null and v_inv_tec is distinct from v_inv)
     or (v_inv_doc is not null and v_inv_doc is distinct from v_inv)
     or (v_inv_puente is not null and v_inv_puente is distinct from v_inv)
     or (v_lead.inversionista_id is not null and private.inversionista_canonica(v_lead.inversionista_id) is distinct from v_inv) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_asesor, 'sin asesor asignado'), 'via', 'identidad');
  end if;
  -- Veto de la persona (también la hallada solo por puente, Codex v3 M1), otro lead, conversión en curso, ya cliente.
  return private.juicio_persona(v_inv, p_lead_id);
end;
$$;
revoke all on function private.juicio_reapertura(uuid, text, text) from public, anon, authenticated, service_role;

-- 0.6 Enlazar un lead reabierto/tomado a su persona (como al nacer), bajo válvula y restaurándola; el trigger zz escribe el
--     puente canónico si no existe, y un puente histórico del propio lead pasa a canónico si la persona no tiene otro (Codex 13).
create or replace function private.enlazar_lead_reabierto(p_lead_id uuid, p_inv uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_previo text;
begin
  if p_inv is null or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inv where id = p_lead_id and inversionista_id is null;
  update crm.inversionista_leads il set rol = 'canonico'
   where il.lead_id = p_lead_id and il.rol = 'historico'
     and not exists (select 1 from crm.inversionista_leads il2 where il2.inversionista_id = il.inversionista_id and il2.rol = 'canonico');
  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
end;
$$;
revoke all on function private.enlazar_lead_reabierto(uuid, uuid) from public, anon, authenticated, service_role;

-- 0.6b Puerta para fijar/cambiar el DNI de un lead con la identidad encendida (Codex v3 B1/B2): candado del documento nuevo y
--      persona FOR SHARE ANTES de la fila (orden documento -> persona -> lead), juicio de la persona, GUC para el trigger y
--      enlace si la persona existe. Ámbito: el de la policy leads_update. Con la bandera apagada: el UPDATE de hoy.
create or replace function crm.fijar_dni_lead_fn(p_lead_id uuid, p_dni text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_lead crm.leads%rowtype; v_inv uuid; v_v jsonb; v_previo text; v_k text; v_claves text[] := '{}';
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'Acceso CRM revocado' using errcode = '42501';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception 'El DNI debe tener exactamente 8 digitos' using errcode = '22023';
  end if;
  -- Ámbito ANTES de cualquier candado (auditor v4 M1): un lead ajeno o inexistente muere aquí sin sondear a nadie.
  if not exists (select 1 from crm.leads l
                  where l.id = p_lead_id and l.activo = true
                    and (v_rol = 'gerencia'
                         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_flag then
    -- Candados del documento ANTERIOR y del nuevo, en orden de texto (Codex v4.1): una toma o reapertura en vuelo que
    -- bloqueó el documento anterior termina antes de que este cambio lo deje obsoleto; y quien llegue después ve el nuevo.
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    for v_k in select k from (select l.dni as k from crm.leads l where l.id = p_lead_id and l.dni is not null
                              union select v_dni where v_dni is not null) s order by k loop
      perform private.identidad_bloquear_documento('DNI', v_k);
      v_claves := v_claves || v_k;
    end loop;
    if v_dni is not null then
      v_inv := private.inversionista_por_documento('DNI', v_dni);
      if v_inv is not null then
        perform 1 from crm.inversionistas i where i.id = v_inv for share;
      end if;
    end if;
  end if;
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
  if v_lead.dni is not distinct from v_dni then
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'sin_cambios', true);
  end if;
  if v_flag then
    -- Codex v4.3 [1]: si la bandera se apagó en medio, los candados de documento fueron no-ops: no se escribe con una lista vacía.
    if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
      raise exception 'La identidad unificada se apagó durante la operación; vuelve a intentarlo' using errcode = '40001';
    end if;
    -- El documento anterior ACTUAL debe ser uno de los bloqueados (Codex v4.2: otra llamada pudo cambiarlo mientras se esperaba).
    if v_lead.dni is not null and not (v_lead.dni = any(v_claves)) then
      raise exception 'El documento de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    if v_lead.inversionista_id is not null or exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id) then
      raise exception 'El documento de un lead ya reconocido solo lo corrige Gerencia (corrección de documento)' using errcode = 'P0409';
    end if;
    if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
      raise exception 'Este lead tiene una conversión en curso: no se cambia su documento' using errcode = 'P0409';
    end if;
    if v_inv is not null then
      v_v := private.juicio_persona(v_inv, p_lead_id);
      if v_v is not null then
        if v_v->>'estado' = 'no_contactar' then
          raise exception 'La persona de ese documento tiene la restricción «No insistir»' using errcode = 'P0429';
        end if;
        raise exception 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este'
          using errcode = 'P0409', detail = v_v::text;
      end if;
    end if;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off');
  perform pg_catalog.set_config('crm.dni_por_puerta', 'on', true);
  update crm.leads set dni = v_dni where id = p_lead_id;
  perform pg_catalog.set_config('crm.dni_por_puerta', v_previo, true);
  if v_flag and v_inv is not null then
    perform private.enlazar_lead_reabierto(p_lead_id, v_inv);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni', v_dni,
    'inversionista_id', case when v_flag then v_inv end, 'enlazado', v_flag and v_inv is not null);
end;
$$;
revoke all on function crm.fijar_dni_lead_fn(uuid, text) from public, anon, service_role;
grant execute on function crm.fijar_dni_lead_fn(uuid, text) to authenticated;
comment on function crm.fijar_dni_lead_fn(uuid, text) is
  'F2.b [D-13]: fija el DNI de un lead. Con la identidad encendida: candado del documento y persona antes de la fila, juicio de la persona, enlace si existe. Apagada: el UPDATE de hoy.';

-- 0.7 Trigger: con la bandera encendida, un descarte (o un lead inactivo) solo se reabre por sus puertas (tomar, rescatar,
--     deshacer), que juzgan a la persona y enlazan; el UPDATE directo de etapa no (Codex D-13 #7). Gerencia bajo válvula pasa.
create or replace function private.trg_leads_zz_reapertura_solo_rpc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if v_priv or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  if ((old.etapa = 'descartado' and new.etapa is distinct from 'descartado') or (old.activo = false and new.activo = true))
     and coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, un descarte se reabre solo por sus puertas (tomar, rescatar o deshacer): juzgan a la persona y enlazan el lead'
      using errcode = 'P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_zz_reapertura_solo_rpc() from public, anon, authenticated, service_role;
drop trigger if exists trg_leads_zz_reapertura_solo_rpc on crm.leads;
create trigger trg_leads_zz_reapertura_solo_rpc
  before update of etapa, activo on crm.leads
  for each row execute function private.trg_leads_zz_reapertura_solo_rpc();
comment on trigger trg_leads_zz_reapertura_solo_rpc on crm.leads is
  'F2.b [D-13]: con resolver_en_puertas encendida, descartado -> vivo (o activo false -> true) solo bajo crm.reapertura_identidad=on (tomar/rescatar/deshacer) o válvula. Apagada: inerte.';

-- ============================================================================
-- 1. Verificador de disponibilidad (3 args)
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
    -- F2.b [D-13]: «los leads de una persona» = enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas;
    -- incluye históricos y soft-borrados enlazados, como ya contaba el join sin filtro de activo); una persona EN CONVERSIÓN
    -- (reserva por persona viva o sellada de OTRO lead) o que YA ES CLIENTE (perfil enlazado, activo o no) tampoco recibe
    -- otro lead. `asesor` = responsable de relación, o quien reservó (reserva vigente), o el centinela. Contrato del front intacto.
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
      and (exists (select 1 from private.leads_de_personas(array[i.id]) x where x is distinct from p_excluir_lead_id)
           or private.persona_en_conversion(i.id, p_excluir_lead_id)
           or i.perfil_id is not null)
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
-- 2. Trigger de nacimiento del lead
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
    if old.inversionista_id is not null
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    -- F2.b [D-13] (Codex v3 B1, auditor v4 A1): con la identidad encendida, el DNI de un lead se FIJA por su puerta
    -- (crm.fijar_dni_lead_fn), que toma el candado del documento y a la persona ANTES de la fila (orden documento ->
    -- persona -> lead), juzga a la persona y enlaza si procede: por la puerta, el trigger deja pasar. El UPDATE directo
    -- (fila ya bloqueada, sin serialización posible con una reserva en vuelo) se rechaza: hacia una persona reconocida
    -- con el mensaje de siempre; hacia un documento sin dueño, «por su puerta».
    if coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off') = 'on' then
      return new;
    end if;
    if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
       and private.inversionista_por_documento('DNI', new.dni) is not null then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    raise exception 'Con la identidad unificada encendida, el DNI de un lead se fija por su puerta (fijar_dni_lead_fn) o lo corrige Gerencia'
      using errcode = 'P0409';
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
  -- F2.b [D-13]: enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas; el enlace vivo primero en
  -- el detalle) y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva; b1).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_personas(array[v_inv]) x
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
  if private.persona_en_conversion(v_inv, new.id)
     or exists (select 1 from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null) then   -- ya cliente (Codex v3 M2)
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                    left join crm.leads lr on lr.id = r.lead_id
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                     and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad',
              'lead_id', (select r.lead_id from crm.conversion_reservas r
                           left join crm.leads lr on lr.id = r.lead_id
                           where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                             and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
                           order by r.reservado_en desc limit 1))::text;
  end if;
  new.inversionista_id := v_inv;
  return new;
end;
$function$
;

-- ============================================================================
-- 3. tomar_lead_libre: candados antes de la fila, juicio único, enlace al tomar
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
  v_candidato uuid;
  v_bloqueo jsonb;
  v_previo_reab text;
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
  -- F2.b [D-13]: los candados de PERSONA van ANTES de la fila (orden total documento -> persona -> lead, el de la reserva,
  -- el sellado y la fusión). El blanco se localiza SIN lock con el mismo criterio de abajo (teléfono manda; si no, DNI),
  -- se bloquean sus documentos y su persona (y los del DNI tecleado), y después se toma la fila; si la fila ya no es la
  -- misma o su persona cambió, manda el veredicto fresco. Inerte con la bandera apagada.
  if v_flag_d13 then
    select l.id into v_candidato
    from crm.leads l
    where l.telefono = v_tel
      and l.no_contactar = false
      and not private.persona_vetada(l.id)
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
    limit 1;
    if v_candidato is null and v_dni is not null then
      select l.id into v_candidato
      from crm.leads l
      where l.dni = v_dni
        and l.no_contactar = false
        and not private.persona_vetada(l.id)
        and (
          (l.activo = true
            and l.etapa not in ('convertido', 'descartado')
            and l.vendedor_id is null
            and l.asignado_supervisor_id is null)
          or (l.etapa = 'descartado' and l.descartado_en is not null)
        )
      order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
      limit 1;
    end if;
    v_bloqueo := private.bloquear_personas_de_leads(case when v_candidato is null then '{}'::uuid[] else array[v_candidato] end, v_dni);
  end if;

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

  -- F2.b [D-13]: la fila tomada debe ser el candidato bloqueado y seguir DENTRO de lo bloqueado: su documento actual entre las
  -- claves y su persona entre las personas (Codex v4.1/v4.2: un cambio de DNI en medio, incluso A->B->A, dejaría obsoleto el
  -- candado); si no, veredicto fresco.
  if v_flag_d13 and (v_lead.id is distinct from v_candidato or not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo)) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
  end if;
  -- F2.b [D-13]: el JUICIO único de reapertura/toma (documento tecleado, documento del blanco, puente, enlace; otro lead de la
  -- persona, conversión en curso, ya cliente): con veredicto asentado y sin escribir nada.
  if v_flag_d13 then
    v_veredicto_identidad := private.juicio_reapertura(v_lead.id, v_tel, v_dni);
    if v_veredicto_identidad is not null then
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
  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);

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
        perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
        return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
          private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
    end;
  end if;

  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);
  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);

  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;
  -- F2.b [D-13] (Codex #5): un lead con DNI (o puente) de una persona reconocida queda ENLAZADO al tomarse, como al nacer:
  -- así la reserva, el sellado y las conversiones lo ven por identidad. La persona ya está bloqueada FOR SHARE (arriba).
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(v_lead.id, private.lead_persona_reabrir(v_lead.id));
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
-- 4. Conversiones: puente del propio lead, sueltos por documento, reserva ajena
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
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #2): una reserva viva o sellada de ESTE lead pertenece a UNA persona (b4): no se convierte para otra
  -- por la puerta directa; el cierre de la saga trae la misma persona y pasa.
  if v_flag and exists (select 1 from crm.conversion_reservas r
                         where r.lead_id = p_lead_id and r.inversionista_id is not null
                           and r.inversionista_id is distinct from v_inv
                           and (r.efectos_iniciados_en is not null or r.expira_en > pg_catalog.now())) then
    raise exception 'Este lead está reservado para otra persona: espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex v3 B4): una conversión Avance en curso en OTRO lead de la misma persona (reserva viva o sellada)
  -- también rechaza la puerta directa, como ya hace convertir_lead_externo; el cierre de la saga trae su propio lead y pasa.
  if v_flag and v_inv is not null and private.persona_en_conversion(v_inv, p_lead_id) then
    raise exception 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead' using errcode = 'P0409';
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
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
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
-- 5. Sellado de la conversión: documentos -> persona; pareja, estado del lead y «un solo lead» antes del punto de no retorno
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
  -- F2.b [D-13]: los documentos vigentes de la persona ANTES de su lock (orden documento -> persona, el de la reserva, la toma
  -- y la fusión): una toma/reapertura por ese documento en vuelo termina antes o después de este sellado, nunca en medio.
  perform private.identidad_bloquear_documentos_de(array[v_loc.inversionista_id]);
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona del claim pudo fusionarse: reintentar (la fusión exige claims terminales).
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.estado = 'fusionado') then
    raise exception 'La persona de este claim fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (Codex #4, auditor v3 M1): el lead FOR SHARE tras la persona y ANTES de la reserva (orden persona -> lead ->
  -- reserva, el mismo de la reserva por persona, la conversión coop y la fusión: sin arista nueva).
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- F2.b [D-13] (Codex #5): la pareja (lead, claim, persona) se revalida bajo el lock de la RESERVA: tras esperar, otra reserva
  -- del mismo lead para otra persona no se sella con este claim.
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead cambió mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex v3 B3): el token se relee tras los locks: una reanudación de la reserva mientras se esperaba rota el
  -- token del mismo claim, y esa ejecución vieja no debe autorizar efectos.
  perform 1 from crm.multiempresa_idempotencia m where m.clave = v_loc.clave for share;   -- orden reserva -> claim (b4)
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'El claim cambió (token rotado) mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex #4): el lead debe seguir vivo y sin otra persona (una conversión directa para otra persona, o un
  -- descarte, mientras la reserva esperaba, no se sella).
  if not exists (select 1 from crm.leads l where l.id = p_lead_id and l.activo
                  and l.etapa not in ('convertido', 'descartado')
                  and (l.inversionista_id is null or private.inversionista_canonica(l.inversionista_id) = v_loc.inversionista_id)
                  and (l.dni is null or private.inversionista_por_documento('DNI', l.dni) = v_loc.inversionista_id)) then   -- Codex v3 B2
    raise exception 'El lead ya no está disponible para esta conversión (convertido, descartado, con otro documento o de otra persona): no se sella'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1/#3): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno, contando
  -- enlace, puente y sueltos vivos con su documento: un lead de esta persona nacido, reabierto o tomado mientras la reserva
  -- esperaba (o ya vencida) no deja cuentas de portal huérfanas; Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_personas(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  return crm.marcar_efectos_conversion(p_lead_id);
end;
$function$
;

-- ============================================================================
-- 6. Reactivaciones (rescate de supervisión y deshacer descarte)
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
  v_bloqueo jsonb;
  v_previo_reab text;
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

  -- F2.b [D-13]: candados de PERSONA antes de las filas (documento -> persona -> lead): documentos y personas de todos los
  -- leads del lote, en orden; luego las filas. Si tras tomarlas la persona de un lead no está entre las bloqueadas -> 40001.
  v_bloqueo := private.bloquear_personas_de_leads(
    (select pg_catalog.array_agg(la.lead_id) from crm.lead_asignaciones la where la.id = any(p_episodios)), null);
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
    -- F2.b [D-13] (auditor M1 / Codex #6): con la identidad encendida, el JUICIO único de reapertura por lead; todo el lote
    -- falla, como con el veto. La persona debe ser una de las bloqueadas antes de las filas (si no, 40001).
    if v_flag then
      if not private.lead_dentro_de_bloqueo(v_fila.lead_id, v_bloqueo) then
        raise exception 'El documento o la persona de uno de los leads cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
      end if;
      v_veredicto := private.juicio_reapertura(v_fila.lead_id, v_fila.telefono, null);
      if v_veredicto->>'estado' = 'no_contactar' then
        raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
          using errcode = 'P0429';
      end if;
      if v_veredicto is not null then
        raise exception 'Uno de los leads pertenece a una persona que ya es cliente o ya tiene su lead y no puede reactivarse'
          using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_fila.lead_id)::text;
      end if;
    end if;
  end loop;

  v_total_episodios := pg_catalog.array_length(p_episodios, 1);
  if v_candidatos <> v_total_episodios then
    raise exception 'Uno de los descartes ya no está disponible para rescate'
      using errcode = 'P0002';
  end if;

  -- F2.b [D-13]: la reapertura pasa por la puerta (trigger «solo por RPC»).
  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id
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
    -- F2.b [D-13] (auditor M1 / Codex #6): el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
    if v_flag then
      perform private.enlazar_lead_reabierto(v_fila.lead_id, private.lead_persona_reabrir(v_fila.lead_id));
    end if;

    v_orden := v_orden + 1;
  end loop;
  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);

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
  v_bloqueo jsonb;
  v_previo_reab text;
  v_flag_d13 boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
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

  -- F2.b [D-13]: candados de PERSONA antes de la fila (documento -> persona -> lead); inerte con la bandera apagada.
  v_bloqueo := private.bloquear_personas_de_leads(array[p_lead], null);
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
  -- F2.b [D-13] (auditor M1 / Codex #6): gemela de rescatar_descartes: el JUICIO único de reapertura con la identidad encendida.
  if v_flag_d13 then
    if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
      raise exception 'El documento o la persona de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    v_veredicto := private.juicio_reapertura(v_lead.id, v_lead.telefono, null);
    if v_veredicto->>'estado' = 'no_contactar' then
      raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
    end if;
    if v_veredicto is not null then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_lead.id)::text;
    end if;
  end if;

  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
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

  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
  -- F2.b [D-13]: el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(p_lead, private.lead_persona_reabrir(p_lead));
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

-- ============================================================================
-- 7. Reserva por persona (texto de D-10): también los sueltos por documento
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  v_tope     interval := interval '30 minutes';
  v_tipo     text := coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_tipo_documento)), ''), 'DNI');
  v_doc      text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g')), '');
  v_inv      uuid; v_veto boolean; v_otro uuid; v_perfil uuid; v_perfil_activo boolean;
  v_hash     text; v_hash_payload jsonb; v_saga jsonb; v_claim uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: usa la reserva por lead' using errcode = 'P0409';
  end if;
  if v_doc is null then
    raise exception 'El documento es obligatorio para reservar la conversión' using errcode = '22023';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;

  -- documento -> identidad -> lead (ámbito, VERBATIM de la viva) -> revalidaciones de la persona.
  -- El ámbito va ANTES de cualquier lectura sobre la persona: un vendedor no puede sondear
  -- documentos ajenos con un lead que no es suyo (auditor b4 A1).
  perform private.identidad_bloquear_documento(v_tipo, v_doc);
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'reserva_conversion');
  select i.no_contactar, i.perfil_id into v_veto, v_perfil from crm.inversionistas i where i.id = v_inv for update;
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


  -- El documento tecleado debe ser el de la persona de ESTE lead (misma regla que convertir_lead, adelantada a antes de Auth).
  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
  -- F2.b [D-10] (Codex #2): el PUENTE de ESTE lead también manda. Un lead que solo está en el puente (sin enlace vivo
  -- ni DNI) pertenece a la persona de su puente; con un documento que resuelve a otra persona no se reserva
  -- (la Gerencia lo corrige o fusiona), igual que ya exige crm.enlazar_lead_inversionista_fn (b5). Por la canónica.
  if exists (select 1 from crm.inversionista_leads il
              where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and v_lead.dni is not null and v_lead.dni <> v_doc then
    raise exception 'El documento no coincide con el del lead' using errcode = 'P0409';
  end if;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
  -- F2.b [D-10] (Codex B2): si no hay OTRO enlace vivo, «un solo lead» cuenta también el PUENTE (crm.inversionista_leads,
  -- históricos del backfill sin enlace vivo), como ya hacen las dos conversiones desde b5; el propio lead no cuenta.
  -- Espejo de b5 (auditor D-10 M1): el enlace vivo se comprueba PRIMERO (el detalle señala el lead canónico cuando existe)
  -- y un lead ya cerrado conserva las respuestas de hoy (enlazado / «ya esta cerrado», más abajo). Mismo error y mismo
  -- detalle que hoy (el front no cambia).
  if v_otro is null and v_lead.etapa not in ('convertido', 'descartado') then
    -- F2.b [D-13] (Codex #1): también los SUELTOS vivos con un documento vigente de la persona (private.leads_de_personas).
    select x into v_otro from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id order by x limit 1;
  end if;
  if v_otro is not null then
    raise exception 'Esta persona ya tiene su lead: la nueva inversión sobre un cliente existente no es una conversión'
      using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_otro)::text;
  end if;
  if v_perfil is null then
    -- Perfil cliente con ese documento creado antes de la identidad: se reutiliza (dedup de hoy, por identidad).
    select p.id into v_perfil from public.perfiles p
     where p.rol = 'cliente' and p.dni = v_doc and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
     limit 1;
  end if;
  if v_perfil is not null then
    select p.activo into v_perfil_activo from public.perfiles p where p.id = v_perfil;
    if v_perfil_activo is distinct from true then
      raise exception 'Ese cliente existe pero está inactivo en el portal' using errcode = 'P0409';
    end if;
  end if;

  -- Conversión ya consumada cuya respuesta se perdió (Codex E2 #4): la saga manda.
  if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null and v_lead.inversionista_id = v_inv
     and exists (select 1 from crm.multiempresa_idempotencia i where i.clave = 'auth_persona:' || v_inv::text
                 and i.resultado->>'estado' <> 'enlazado' and i.resultado->>'tipo' = 'conversion'
                 and (i.resultado->>'lead_id')::uuid = p_lead_id
                 and coalesce((i.resultado->>'auth_user_id')::uuid, v_lead.perfil_id) = v_lead.perfil_id) then
    update crm.multiempresa_idempotencia
       set resultado = resultado || pg_catalog.jsonb_build_object('estado', 'enlazado', 'perfil_id', v_lead.perfil_id, 'actualizado_en', pg_catalog.now()),
           version = version + 1
     where clave = 'auth_persona:' || v_inv::text;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null then
      return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'estado', 'enlazado', 'reanudar', true,
        'inversionista_id', v_inv, 'perfil_id', v_lead.perfil_id, 'ya_existia', true);
    end if;
    raise exception 'El lead ya esta cerrado';
  end if;
  -- Reserva viva o sellada de OTRO lead de la misma persona (Avance en curso en otro lead).
  if exists (select 1 from crm.conversion_reservas r
              where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception using errcode = 'P0409',
      message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
      hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
  end if;

  -- Una reserva viva o sellada de este lead pertenece a UNA persona: no se cambia de identidad
  -- sin compensar (Codex E2 #5).
  if exists (select 1 from crm.conversion_reservas r
              where r.lead_id = p_lead_id and r.inversionista_id is not null and r.inversionista_id <> v_inv
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception 'Este lead ya está reservado para otra persona; espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- Huella canónica SIN documento (Codex E2 #10).
  v_hash_payload := pg_catalog.jsonb_build_object('v', 1, 'inv', v_inv,
    'correo', pg_catalog.lower(coalesce(p_payload->>'correo','')), 'nombre', coalesce(p_payload->>'nombre_completo',''),
    'apellidos', coalesce(p_payload->>'apellidos',''), 'nombres', coalesce(p_payload->>'nombres',''),
    'telefono', coalesce(p_payload->>'telefono',''), 'domicilio', coalesce(p_payload->'domicilio', 'null'::jsonb),
    'bancarios', coalesce(p_payload->'bancarios', 'null'::jsonb));
  v_hash := private.idem_hash(v_hash_payload);

  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en, inversionista_id, hash_payload)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope, v_inv, v_hash)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         inversionista_id = v_inv,
         hash_payload  = v_hash,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;


  -- Persona YA cliente del portal (identidad enlazada o perfil con el documento exacto): sin Auth y
  -- sin saga; el edge convierte con convertir_lead_con_domicilio como hoy (auditor b4 A2).
  if v_perfil is not null then
    update crm.conversion_reservas r set claim_id = null where r.lead_id = p_lead_id;
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
      'inversionista_id', v_inv, 'perfil_id', v_perfil, 'ya_existia', true, 'estado', 'ya_existia', 'reanudar', false);
  end if;
  -- Claim de la saga (o reanudación con token / lease vencido).
  v_saga := private.saga_auth_reclamar(v_inv, 'conversion', v_hash_payload, p_lead_id, p_payload->>'token');
  v_claim := (v_saga->>'claim_id')::uuid;
  update crm.conversion_reservas r set claim_id = v_claim where r.lead_id = p_lead_id;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
    'inversionista_id', v_inv, 'perfil_id', (v_saga->>'perfil_id')::uuid, 'ya_existia', false)
    || (v_saga - 'inversionista_id' - 'perfil_id');
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text, p_excluir_lead_id uuid') is distinct from '4a2d7b8b3d1030d6ab96009e933af6cc' then
    raise exception 'POSTFLIGHT D-13: private.verificar_disponibilidad_lead_impl(text,text,uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_zz_enlaza_identidad' and pg_get_function_identity_arguments(p.oid)='') is distinct from 'd6fa34cabc1ada619e50ecb114f5255b' then
    raise exception 'POSTFLIGHT D-13: private.trg_leads_zz_enlaza_identidad() no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='tomar_lead_libre' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from 'cf1c6d953df901c3373304206a3560ab' then
    raise exception 'POSTFLIGHT D-13: crm.tomar_lead_libre(text,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_perfil_id uuid') is distinct from '1d3f437cafe73d2e4076bb68158af812' then
    raise exception 'POSTFLIGHT D-13: crm.convertir_lead(uuid,uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text') is distinct from '3ff4aa7ec25751ba028af596c9fed6a2' then
    raise exception 'POSTFLIGHT D-13: crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_claim_id uuid, p_token text') is distinct from '511c059250774b625c8bc3274523e61a' then
    raise exception 'POSTFLIGHT D-13: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='rescatar_descartes' and pg_get_function_identity_arguments(p.oid)='p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean') is distinct from '38d5869195a00c82437cbfb3298df8e7' then
    raise exception 'POSTFLIGHT D-13: crm.rescatar_descartes(uuid[],uuid[],boolean) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='deshacer_descarte_implementacion' and pg_get_function_identity_arguments(p.oid)='p_lead uuid') is distinct from '5e343627436b8532215501d38aecafeb' then
    raise exception 'POSTFLIGHT D-13: private.deshacer_descarte_implementacion(uuid) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb') is distinct from '8ec13410c8f18a3b3004a7321afe9398' then
    raise exception 'POSTFLIGHT D-13: crm.reservar_conversion_lead(uuid,text,text,jsonb) no quedó byte a byte como la genera gen-d13.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '742d44fff6a8a742292c8de702812e60' then
    raise exception 'D-13: la sobrecarga de 2 argumentos del verificador (solo delega) cambió';
  end if;
  if exists (select 1 from unnest(array['private.verificar_disponibilidad_lead_impl(text,text,uuid)','private.verificar_disponibilidad_lead_impl(text,text)','private.trg_leads_zz_enlaza_identidad()','private.deshacer_descarte_implementacion(uuid)']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure,'private.verificar_disponibilidad_lead_impl(text,text)'::regprocedure,'private.trg_leads_zz_enlaza_identidad()'::regprocedure,'private.deshacer_descarte_implementacion(uuid)'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: las funciones privadas transformadas no pueden tener EXECUTE para la API ni PUBLIC';
  end if;
  if exists (select 1 from unnest(array['crm.tomar_lead_libre(text,text)','crm.convertir_lead(uuid,uuid)','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)','crm.marcar_efectos_conversion(uuid,uuid,text)','crm.rescatar_descartes(uuid[],uuid[],boolean)','crm.reservar_conversion_lead(uuid,text,text,jsonb)','crm.fijar_dni_lead_fn(uuid,text)']) f(firma)
              where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.tomar_lead_libre(text,text)'::regprocedure,'crm.convertir_lead(uuid,uuid)'::regprocedure,'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure,'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure,'crm.rescatar_descartes(uuid[],uuid[],boolean)'::regprocedure,'crm.reservar_conversion_lead(uuid,text,text,jsonb)'::regprocedure,'crm.fijar_dni_lead_fn(uuid,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: los grants de las RPC transformadas cambiaron (solo authenticated)';
  end if;
  if exists (select 1 from unnest(array['private.persona_en_conversion(uuid,uuid)','private.leads_de_personas(uuid[])','private.lead_persona_reabrir(uuid)','private.bloquear_personas_de_leads(uuid[],text)','private.lead_dentro_de_bloqueo(uuid,jsonb)','private.juicio_persona(uuid,uuid)','private.juicio_reapertura(uuid,text,text)','private.enlazar_lead_reabierto(uuid,uuid)','private.trg_leads_zz_reapertura_solo_rpc()']) f(firma) where to_regprocedure(f.firma) is null)
     or exists (select 1 from unnest(array['private.persona_en_conversion(uuid,uuid)','private.leads_de_personas(uuid[])','private.lead_persona_reabrir(uuid)','private.bloquear_personas_de_leads(uuid[],text)','private.lead_dentro_de_bloqueo(uuid,jsonb)','private.juicio_persona(uuid,uuid)','private.juicio_reapertura(uuid,text,text)','private.enlazar_lead_reabierto(uuid,uuid)','private.trg_leads_zz_reapertura_solo_rpc()']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.persona_en_conversion(uuid,uuid)'::regprocedure,'private.leads_de_personas(uuid[])'::regprocedure,'private.lead_persona_reabrir(uuid)'::regprocedure,'private.bloquear_personas_de_leads(uuid[],text)'::regprocedure,'private.lead_dentro_de_bloqueo(uuid,jsonb)'::regprocedure,'private.juicio_persona(uuid,uuid)'::regprocedure,'private.juicio_reapertura(uuid,text,text)'::regprocedure,'private.enlazar_lead_reabierto(uuid,uuid)'::regprocedure,'private.trg_leads_zz_reapertura_solo_rpc()'::regprocedure) and a.grantee = 0)
     or exists (select 1 from unnest(array['private.persona_en_conversion(uuid,uuid)','private.leads_de_personas(uuid[])','private.lead_persona_reabrir(uuid)','private.bloquear_personas_de_leads(uuid[],text)','private.lead_dentro_de_bloqueo(uuid,jsonb)','private.juicio_persona(uuid,uuid)','private.juicio_reapertura(uuid,text,text)','private.enlazar_lead_reabierto(uuid,uuid)','private.trg_leads_zz_reapertura_solo_rpc()']) f(firma) where not exists (select 1 from pg_proc p where p.oid = f.firma::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT D-13: algún helper falta, tiene grants indebidos o perdió definer/search_path';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_reapertura_solo_rpc' and not tgisinternal and tgenabled='O'
                   and pg_get_triggerdef(oid) = 'CREATE TRIGGER trg_leads_zz_reapertura_solo_rpc BEFORE UPDATE OF etapa, activo ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_zz_reapertura_solo_rpc()') then
    raise exception 'POSTFLIGHT D-13: el trigger de reapertura solo por RPC falta, está deshabilitado o no tiene la definición esperada';
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
  raise notice 'F2.b D-13 OK: un solo lead (enlace ∪ puente ∪ sueltos por documento) y persona en conversión en todas las puertas; reabrir/tomar enlaza y solo por RPC; el sellado revalida (rama ON). Bandera APAGADA.';
end
$post$;
commit;
