-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-10] — LA RESERVA POR PERSONA
-- CUENTA EL PUENTE EN «UN SOLO LEAD» (Codex B2, como ya hacen las dos conversiones desde b5)
-- ============================================================================
--
-- QUE: con la bandera ENCENDIDA, crm.reservar_conversion_lead(lead, tipo, documento, payload) rechazaba una
-- segunda conversión de la misma persona SOLO si el otro lead llevaba el enlace vivo (leads.inversionista_id).
-- Los leads que solo están en el PUENTE (crm.inversionista_leads, históricos del backfill de F2 sin enlace vivo)
-- no contaban: la reserva —que es el preflight de la conversión Avance— abría claim y reserva para una persona
-- que las dos conversiones (b5) después rechazan. Ahora, si no hay OTRO enlace vivo, cuenta también el PUENTE
-- (private.leads_de_identidades) —espejo de b5: el enlace vivo primero, y un lead ya cerrado conserva sus
-- respuestas de hoy— con el MISMO error P0409 y el MISMO detalle (estado ya_es_cliente, lead_id): el front no cambia.
-- Transformada desde el texto VIVO de producción (scripts/f2b/gen-d10.py, guarda md5 EXACTA, postflight byte a byte).
-- Con la bandera APAGADA la sobrecarga sigue inerte (P0409 apagada antes de leer argumentos): aterriza apagada.
-- Ensayo: scripts/oraculo-f2b-d10-d11.sh (incluye [D-11]: replay de un claim terminal tras una fusión).
-- Reversa: scripts/rollback-f2b-d10.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d10_reserva_cuenta_puente'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is null then
    raise exception 'F2.b D-10: falta b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-10: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
  v_h := null;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb';
  if v_h is null then
    raise exception 'F2.b D-10: falta crm.reservar_conversion_lead(uuid,text,text,jsonb) (b4, 20260905110000)';
  end if;
  if v_h is distinct from '6242dfc993a3900ded3e084c9d4a1221' and v_h is distinct from 'b6c1863eec07df43e2023e7e8d729d05' then
    raise exception 'F2.b D-10: crm.reservar_conversion_lead(uuid,text,text,jsonb) no es ni el texto vivo de producción ni el de D-10 (%)', v_h;
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '2421b2b78b02b8e93fd01598e2f54128'
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-10: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.reservar_conversion_lead(uuid,text,text,jsonb): «un solo lead» = enlace vivo ∪ puente
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
    select x into v_otro from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id order by x limit 1;
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
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb') is distinct from 'b6c1863eec07df43e2023e7e8d729d05' then
    raise exception 'POSTFLIGHT D-10: crm.reservar_conversion_lead(uuid,text,text,jsonb) no quedó byte a byte como la genera gen-d10.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid') is distinct from 'a067183bfe986cf7bd5f82b4ed6674d7' then
    raise exception 'POSTFLIGHT D-10: la reserva de 1 argumento (camino de hoy, bandera apagada) cambió';
  end if;
  if has_function_privilege('anon', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.reservar_conversion_lead(uuid,text,text,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-10: los grants de la reserva por persona cambiaron (solo authenticated; ni anon, ni service_role, ni PUBLIC)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '2421b2b78b02b8e93fd01598e2f54128'
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-10: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-10: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-10 OK: la reserva por persona cuenta el puente en «un solo lead» (rama ON). Bandera APAGADA.';
end
$post$;
commit;
