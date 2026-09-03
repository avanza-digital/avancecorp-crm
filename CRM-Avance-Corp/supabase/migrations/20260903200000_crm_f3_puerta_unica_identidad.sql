-- ============================================================================
-- P-055 · MULTIEMPRESA F3 — Una sola puerta para reconocer a la persona
-- ============================================================================
--
-- QUE, en una linea: al CONVERTIR un lead (Avance o cooperativa), el sistema
-- reconoce o crea la persona por el PUNTO UNICO (private.inversionista_resolver)
-- y la enlaza — pero SOLO si la bandera resolver_en_puertas esta encendida.
--
-- COMO, sin tocar las puertas: en vez de reescribir crm.convertir_lead y
-- crm.convertir_lead_externo (funciones criticas y enormes), se anade UN trigger
-- BEFORE UPDATE en crm.leads que actua unicamente en la transicion a
-- 'convertido'. Las puertas quedan INTACTAS; con la bandera apagada el trigger
-- retorna de inmediato y el comportamiento es identico a hoy. Reversa = soltar
-- el trigger, la funcion y apagar la bandera (nada vivo que restaurar).
--
-- INVARIANTES (la meta de F3):
--   * dos conversiones simultaneas del mismo documento -> UNA identidad (el
--     resolver serializa por documento + indice unico);
--   * una persona que vuelve reutiliza su identidad y su UNICO lead vivo;
--   * el resolver es el UNICO creador de identidad (sin EXECUTE para la API);
--     ninguna puerta paralela ni ruta de servicio crea persona por fuera;
--   * un reintento reutiliza lo existente (resolver idempotente + reservas);
--   * no_contactar del lead se centraliza; la oportunidad viva se respeta.
--
-- Orden de triggers BEFORE UPDATE en crm.leads (por nombre):
--   before_update (P4/inmutables) -> protege_inversionista_id (#4, no-op con
--   valvula) -> reconocer_identidad (este). Cuando este corre, perfil_id ya esta
--   fijado por la puerta y la valvula op_privilegiada esta 'on'.
--
-- Requiere F1 (20260903160000) y F2 (20260903180000). Reversa:
-- scripts/rollback-f3-puerta-unica.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f3_puertas'));

do $guard$
begin
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null
     or to_regclass('crm.multiempresa_flags') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F3: faltan F1/F2 (resolver o bandera resolver_en_puertas)';
  end if;
end
$guard$;

-- ============================================================================
-- 1. El trigger de reconocimiento de identidad al convertir
-- ============================================================================
create or replace function private.leads_reconocer_identidad_al_convertir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_inv uuid; v_tipo text; v_doc text; v_cierre_id uuid; v_resp uuid;
begin
  -- Solo en la transicion a convertido.
  if not (new.etapa = 'convertido' and old.etapa is distinct from 'convertido') then
    return new;
  end if;
  -- Solo si la puerta de identidad esta ENCENDIDA.
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  -- Ya enlazado (idempotencia).
  if new.inversionista_id is not null then
    return new;
  end if;

  -- De donde sale el documento: Avance por el perfil; cooperativa por el cierre.
  if new.perfil_id is not null then
    select tipo_documento, dni into v_tipo, v_doc from public.perfiles where id = new.perfil_id;
  else
    select ce.id, ce.documento_tipo, ce.documento into v_cierre_id, v_tipo, v_doc
    from crm.cierres_externos ce where ce.lead_id = new.id
    order by ce.creado_en desc, ce.id desc limit 1;
  end if;
  -- Sin documento valido: no se inventa identidad (queda a revision, como en F2).
  if v_doc is null or pg_catalog.btrim(v_doc) = '' then
    return new;
  end if;

  -- EL PUNTO UNICO. Serializa por documento; idempotente.
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'conversion');

  if new.perfil_id is not null then
    update crm.inversionistas set perfil_id = new.perfil_id
      where id = v_inv and perfil_id is null
        and not exists (select 1 from crm.inversionistas i2 where i2.perfil_id = new.perfil_id and i2.id <> v_inv);
    select asesor_perfil_id into v_resp from public.perfiles where id = new.perfil_id;
  end if;
  if v_cierre_id is not null then
    update crm.cierres_externos set inversionista_id = v_inv where id = v_cierre_id and inversionista_id is null;
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, ce.id, 'vigente',
           least((ce.creado_en at time zone 'America/Lima')::date, (pg_catalog.now() at time zone 'America/Lima')::date),
           true, ce.creado_por
    from crm.cierres_externos ce join crm.empresas e on e.clave = ce.cooperativa
    where ce.id = v_cierre_id and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = ce.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = v_cierre_id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id = inv.id and it.rol='principal');
    select vendedor_id into v_resp from crm.cierres_externos where id = v_cierre_id;
  end if;

  -- Un solo lead VIVO por persona: si otro lead suyo ya es el vivo, este va al
  -- puente como historico y NO toma el puntero (evita la unique parcial de F1).
  if exists (select 1 from crm.leads l2 where l2.inversionista_id = v_inv and l2.id <> new.id) then
    new.inversionista_id := null;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, new.id, 'historico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id);
  else
    new.inversionista_id := v_inv;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, new.id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id);
  end if;

  -- Responsable de relacion (asesor en Avance / vendedor en cooperativa), si el
  -- responsable esta activo y la persona no tiene tramo abierto.
  if v_resp is not null
     and exists (select 1 from crm.equipo e where e.perfil_id = v_resp and e.activo)
     and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
    insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
    values (v_inv, v_resp, 'conversion');
    update crm.inversionistas set responsable_relacion_id = v_resp where id = v_inv and responsable_relacion_id is null;
  end if;

  -- no_contactar del lead se centraliza en la persona.
  if new.no_contactar then
    update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
    where id = v_inv and no_contactar = false;
  end if;

  return new;
end
$fn$;
revoke all on function private.leads_reconocer_identidad_al_convertir() from public, anon, authenticated, service_role;

-- El trigger corre DESPUES de protege_inversionista_id (por nombre: 'r' > 'p'),
-- asi que puede fijar new.inversionista_id sin que la proteccion lo anule.
drop trigger if exists trg_leads_reconocer_identidad on crm.leads;
create trigger trg_leads_reconocer_identidad
  before update on crm.leads
  for each row execute function private.leads_reconocer_identidad_al_convertir();

-- ============================================================================
-- 2. Encender la puerta unica
-- ============================================================================
update crm.multiempresa_flags set activo = true, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = false;

-- ============================================================================
-- 3. Postflight
-- ============================================================================
do $post$
begin
  if to_regprocedure('private.leads_reconocer_identidad_al_convertir()') is null
     or not exists (select 1 from pg_trigger where tgname='trg_leads_reconocer_identidad' and not tgisinternal) then
    raise exception 'POSTFLIGHT F3: falta el trigger de reconocimiento';
  end if;
  if not (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'POSTFLIGHT F3: la puerta unica (resolver_en_puertas) no quedo encendida';
  end if;
  -- El resolver sigue sin EXECUTE para la API (unico creador de identidad).
  if has_function_privilege('authenticated','private.inversionista_resolver(text,text,boolean,text)','EXECUTE')
     or has_function_privilege('anon','private.inversionista_resolver(text,text,boolean,text)','EXECUTE')
     or has_function_privilege('service_role','private.inversionista_resolver(text,text,boolean,text)','EXECUTE') then
    raise exception 'POSTFLIGHT F3: el resolver quedo ejecutable por la Data API';
  end if;
  raise notice 'F3 OK: puerta unica encendida; conversion reconoce identidad; resolver privado.';
end
$post$;

commit;
