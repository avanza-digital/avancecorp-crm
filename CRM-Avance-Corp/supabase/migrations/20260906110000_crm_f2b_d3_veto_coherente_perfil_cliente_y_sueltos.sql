-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-3] — EL VETO DE LA PERSONA ES COHERENTE:
-- TAREAS DE PERFIL, FICHA DEL CLIENTE (actividades_cliente) Y LEADS SUELTOS/PUENTE CON SU DOCUMENTO (bloque 2) — v3
-- ============================================================================
--
-- QUE (contrato §7.3, «No insistir» es de la PERSONA; todo en la rama ON, con OFF nada cambia):
--  · Tareas de PERFIL (cliente): trigger propio BEFORE INSERT en crm.tareas (00_0, corre primero): con la bandera
--    encendida y fuera de la válvula bloquea a la persona del perfil FOR SHARE (persona → perfil) y rechaza la tarea
--    si la persona está vetada (P0429), por el enlace perfil↔identidad o por el documento exacto del perfil.
--    private.trg_gestion_lead_serializada (compartido con actividades) queda byte a byte (v3).
--  · Ficha del cliente: trigger BEFORE INSERT en crm.actividades_cliente: contacto de una persona vetada → P0429;
--    notas y reasignaciones entran; writers internos y válvula exentos.
--  · marcar_no_contactar / levantar_no_contactar: la persona se resuelve por enlace, por el PUENTE (lead histórico sin
--    DNI) o por documento; DOCUMENTO → PERSONA (los documentos vigentes se bloquean antes que la persona y se releen:
--    40001 si cambiaron); «sus leads» = enlace ∪ puente ∪ sueltos con DNI vigente y verificado, más el propio;
--    los leads se toman SIN esperar (40001 si otra sesión tiene uno: derivar/repartir van lead → tareas); marcar veta
--    a todos y cancela sus tareas pendientes —incluidas las de CLIENTE de los perfiles de la persona (enlazado o por
--    documento)—; levantar los levanta; el motivo no puede llevar el documento.
--  · private.leads_vetados_persona (gate por lead) ve además el PUENTE.
-- Transformadas desde el texto VIVO de producción (scripts/f2b/gen-d3.py + vivas/bloque2/, guardas md5 EXACTAS,
-- postflight byte a byte). Aterriza APAGADA. Ensayo: scripts/oraculo-f2b-d3.sh. Reversa: scripts/rollback-f2b-d3.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d3_veto_coherente'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_vetados_persona(uuid[])') is null or to_regprocedure('private.leads_de_identidades(uuid[])') is null then
    raise exception 'F2.b D-3: falta b2 (20260904130000) o b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-3: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_no_contactar' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_motivo text');
  if v_h is null then
    raise exception 'F2.b D-3: falta crm.marcar_no_contactar(uuid,text)';
  end if;
  if v_h is distinct from '7eed841aeb8a18f1879122512f94a6b7' and v_h is distinct from '3801006e30ae81df9bd311872277626c' then
    raise exception 'F2.b D-3: crm.marcar_no_contactar(uuid,text) no es ni el texto vivo de producción ni el de D-3 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='levantar_no_contactar' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_motivo text');
  if v_h is null then
    raise exception 'F2.b D-3: falta crm.levantar_no_contactar(uuid,text)';
  end if;
  if v_h is distinct from '1b30a3027963b21df31c75cf8e152ca7' and v_h is distinct from '7d67b6012f9f1a44e435a14f574b7927' then
    raise exception 'F2.b D-3: crm.levantar_no_contactar(uuid,text) no es ni el texto vivo de producción ni el de D-3 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_vetados_persona' and pg_get_function_identity_arguments(p.oid)='p_lead_ids uuid[]');
  if v_h is null then
    raise exception 'F2.b D-3: falta private.leads_vetados_persona(uuid[])';
  end if;
  if v_h is distinct from 'cb977ab276742f698a4dc0de837ab357' and v_h is distinct from 'bb394fa911d01f687d62f17aa2e87b9c' then
    raise exception 'F2.b D-3: private.leads_vetados_persona(uuid[]) no es ni el texto vivo de producción ni el de D-3 (%)', v_h;
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure) is distinct from '2421b2b78b02b8e93fd01598e2f54128'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-3: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.trg_gestion_lead_serializada()'::regprocedure) is distinct from '7af0e66b8a4849566e43b514245e1b86' then
    raise exception 'F2.b D-3: private.trg_gestion_lead_serializada() no es el texto vivo de producción (D-3 v3 NO la toca)';
  end if;
  if to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null or to_regprocedure('private.inversionista_canonica(uuid)') is null then
    raise exception 'F2.b D-3: faltan private.identidad_bloquear_documentos_de (D-13) o private.inversionista_canonica (b5)';
  end if;
end
$guard$;

-- ============================================================================
-- 0. Helpers privados nuevos (definer, search_path vacío, sin EXECUTE para la API) y los dos triggers
-- ============================================================================
create or replace function private.leads_de_persona_veto(p_inv uuid)
 returns setof uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- F2.b [D-3]: los leads que heredan el VETO de una persona = enlace vivo ∪ puente (private.leads_de_identidades, b5)
  -- ∪ SUELTOS con su documento (DNI vigente y verificado, sin enlace), en cualquier etapa: el veto es de la persona.
  select x from private.leads_de_identidades(array[p_inv]) x
  union
  select l.id
  from crm.leads l
  join crm.inversionista_identificadores d
    on d.tipo_documento = 'DNI' and d.estado = 'vigente' and d.verificado = true and d.documento_normalizado = l.dni
  where d.inversionista_id = p_inv
    and l.inversionista_id is null
$function$;
revoke all on function private.leads_de_persona_veto(uuid) from public, anon, authenticated, service_role;

create or replace function private.persona_vetada_perfil(p_perfil_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- F2.b [D-3]: el veto de la PERSONA visto desde un perfil cliente (tareas de cliente, actividades_cliente): por el
  -- enlace perfil↔identidad (canónica) o por el documento exacto del perfil (identificador vigente y verificado).
  -- Con la bandera apagada es siempre false (paridad con hoy).
  select coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and (
       exists (select 1
               from crm.inversionistas i0
               join crm.inversionistas i on i.id = coalesce(i0.inversionista_canonico_id, i0.id)
               where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado' and i.no_contactar = true)
       or exists (select 1
                  from public.perfiles p
                  join crm.inversionista_identificadores idf
                    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
                   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
                   and idf.estado = 'vigente' and idf.verificado = true
                  join crm.inversionistas i on i.id = idf.inversionista_id
                  where p.id = p_perfil_id
                    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
                    and i.estado <> 'fusionado' and i.no_contactar = true)
     )
$function$;
revoke all on function private.persona_vetada_perfil(uuid) from public, anon, authenticated, service_role;

create or replace function private.personas_de_perfil(p_perfil_id uuid)
 returns setof uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- F2.b [D-3]: las identidades (canónicas, no fusionadas) de un perfil cliente: por el enlace o por su documento exacto.
  select coalesce(i0.inversionista_canonico_id, i0.id)
  from crm.inversionistas i0
  where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado'
  union
  select coalesce(i.inversionista_canonico_id, i.id)
  from public.perfiles p
  join crm.inversionista_identificadores idf
    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
   and idf.estado = 'vigente' and idf.verificado = true
  join crm.inversionistas i on i.id = idf.inversionista_id
  where p.id = p_perfil_id
    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
    and i.estado <> 'fusionado'
$function$;
revoke all on function private.personas_de_perfil(uuid) from public, anon, authenticated, service_role;

create or replace function private.trg_tareas_veto_persona_perfil()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_personas uuid[];
begin
  -- F2.b [D-3] (v3/v4, Codex #5/#10/N1): la tarea de PERFIL (cliente) respeta el veto de la PERSONA (contrato §7.3) igual
  -- que la de lead, en un trigger propio de crm.tareas (el trigger de gestión compartido con actividades sigue byte a byte).
  -- Corre ANTES que el resto (00_0): toma a las personas del perfil FOR SHARE —persona → perfil, el orden de reasignar—
  -- SIN ESPERAR: si alguien las tiene (veto, fusión, reasignación, baja) → 40001 y se reintenta (nunca se espera con una
  -- tarea en la mano: cerrar_tarea agenda la siguiente con la tarea bloqueada y marcar espera esa tarea con la persona
  -- bloqueada). Después revalida que lo bloqueado siga siendo lo actual (una fusión pudo mover el perfil de persona).
  -- Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or new.lead_id is not null or new.perfil_id is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  v_personas := array(select x from private.personas_de_perfil(new.perfil_id) x order by 1);
  begin
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share nowait;
  exception when lock_not_available then
    raise exception 'La persona del cliente está siendo actualizada (veto, fusión o reasignación); vuelve a intentarlo'
      using errcode = '40001';
  end;
  if array(select x from private.personas_de_perfil(new.perfil_id) x order by 1) is distinct from v_personas then
    raise exception 'La persona del cliente cambió mientras se agendaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if private.persona_vetada_perfil(new.perfil_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_tareas_veto_persona_perfil() from public, anon, authenticated, service_role;

create or replace function private.trg_actividades_cliente_veto_persona()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- F2.b [D-3]: el veto de la persona bloquea el SEGUIMIENTO también en la ficha del cliente (contrato §7.3): los tipos
  -- de CONTACTO. Notas y reasignaciones entran. Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or new.tipo not in ('llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada') then
    return new;
  end if;
  if private.persona_vetada_perfil(new.cliente_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
$function$;
revoke all on function private.trg_actividades_cliente_veto_persona() from public, anon, authenticated, service_role;

drop trigger if exists trg_tareas_00_0_veto_persona on crm.tareas;
create trigger trg_tareas_00_0_veto_persona
  before insert on crm.tareas
  for each row execute function private.trg_tareas_veto_persona_perfil();
drop trigger if exists trg_actividades_cliente_01_veto_persona on crm.actividades_cliente;
create trigger trg_actividades_cliente_01_veto_persona
  before insert on crm.actividades_cliente
  for each row execute function private.trg_actividades_cliente_veto_persona();

-- ============================================================================
-- 1. private.leads_vetados_persona(uuid[]): el veto visto desde un lead cuenta el PUENTE
-- ============================================================================
CREATE OR REPLACE FUNCTION private.leads_vetados_persona(p_lead_ids uuid[])
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select l.id
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)
  where l.id = any (coalesce(p_lead_ids, array[]::uuid[]))
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    and (
      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      -- F2.b [D-3]: un lead que está en el PUENTE de una persona vetada (histórico sin enlace vivo) también lo está.
      or exists (select 1
                 from crm.inversionista_leads il
                 join crm.inversionistas p0 on p0.id = il.inversionista_id
                 join crm.inversionistas p  on p.id  = coalesce(p0.inversionista_canonico_id, p0.id)
                 where il.lead_id = l.id and p.no_contactar = true)
      or (l.inversionista_id is null
          and nullif(pg_catalog.btrim(coalesce(l.dni,'')), '') is not null
          and exists (
            select 1
            from crm.inversionista_identificadores idf
            join crm.inversionistas i on i.id = idf.inversionista_id
            where idf.tipo_documento = 'DNI'
              and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(l.dni, '[^A-Za-z0-9]', '', 'g'))
              and idf.estado = 'vigente'
              and idf.verificado = true
              and i.estado <> 'fusionado'
              and i.no_contactar = true))
    )
$function$
;

-- ============================================================================
-- 2. crm.marcar_no_contactar(uuid,text): puente ∪ enlace ∪ sueltos + tareas de cliente, documento → persona, sin esperar leads
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.marcar_no_contactar(p_lead_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;

  -- F2.b (b2) [Codex E1 #2]: orden identidad -> TAREAS -> leads. crm.cerrar_tarea va
  -- tarea -> lead; cancelar las pendientes después de bloquear los leads formaría un ciclo.
  if v_flag then
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads)  /* F2.b [D-3]: enlace ∪ puente ∪ sueltos, y también las tareas de CLIENTE */
            or t.perfil_id = any(v_perfiles))
       order by t.id
       for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está cerrando una tarea de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (vendedor_id is null and asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;
  -- Revalidar tras esperar: si la identidad cambió (fusión/corrección), reintentar.
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(no_contactar_en, pg_catalog.now()),
           no_contactar_por = coalesce(no_contactar_por, v_uid)
     where id = v_inv and no_contactar = false;
    -- Todos los leads de la persona heredan el veto (id asc = orden determinista).
    for v_lead in
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
    loop
      if not v_lead.no_contactar then
        update crm.leads set no_contactar = true where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también hereda el veto.
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  -- F2.b (b2): con la bandera encendida se cancelan las tareas PENDIENTES de todos
  -- los leads de la persona (selladas como sistema). Levantar el veto NO las revive.
  if v_flag then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.estado = 'pendiente'
       and (t.lead_id = any(v_leads)  /* F2.b [D-3]: enlace ∪ puente ∪ sueltos, y también las tareas de CLIENTE */
            or t.perfil_id = any(v_perfiles));
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  -- La nota se inserta BAJO la válvula: el trigger de gestión exime la válvula del veto (F2.b b2).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$
;

-- ============================================================================
-- 3. crm.levantar_no_contactar(uuid,text): el mismo conjunto
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = false, no_contactar_en = null, no_contactar_por = null
     where id = v_inv and no_contactar = true;
    for v_lead in
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
    loop
      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también.
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    get diagnostics v_n = row_count;
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota', 'Levantado No contactar por Gerencia',
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo)),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_no_contactar' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_motivo text') is distinct from '3801006e30ae81df9bd311872277626c' then
    raise exception 'POSTFLIGHT D-3: crm.marcar_no_contactar(uuid,text) no quedó byte a byte como la genera gen-d3.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='levantar_no_contactar' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid, p_motivo text') is distinct from '7d67b6012f9f1a44e435a14f574b7927' then
    raise exception 'POSTFLIGHT D-3: crm.levantar_no_contactar(uuid,text) no quedó byte a byte como la genera gen-d3.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_vetados_persona' and pg_get_function_identity_arguments(p.oid)='p_lead_ids uuid[]') is distinct from 'bb394fa911d01f687d62f17aa2e87b9c' then
    raise exception 'POSTFLIGHT D-3: private.leads_vetados_persona(uuid[]) no quedó byte a byte como la genera gen-d3.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_persona_veto(uuid)'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '07ec934e427afe6990b26d6095dd36c3') then
    raise exception 'POSTFLIGHT D-3: private.leads_de_persona_veto(uuid) falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.persona_vetada_perfil(uuid)'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '597d76a6aa5f6ca75f0ffb86bd20497e') then
    raise exception 'POSTFLIGHT D-3: private.persona_vetada_perfil(uuid) falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.personas_de_perfil(uuid)'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '5e7be6428d6f1abd9eab8af181046f3e') then
    raise exception 'POSTFLIGHT D-3: private.personas_de_perfil(uuid) falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_tareas_veto_persona_perfil()'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '3826f7b7d9f19fa63b5f2515168c56cf') then
    raise exception 'POSTFLIGHT D-3: private.trg_tareas_veto_persona_perfil() falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'private.trg_actividades_cliente_veto_persona()'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '03d9b403c3de2ba9ea8dd83a8245fd46') then
    raise exception 'POSTFLIGHT D-3: private.trg_actividades_cliente_veto_persona() falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
  if exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol), unnest(array['private.leads_de_persona_veto(uuid)','private.persona_vetada_perfil(uuid)','private.personas_de_perfil(uuid)','private.trg_tareas_veto_persona_perfil()','private.trg_actividades_cliente_veto_persona()']) f(firma) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.leads_de_persona_veto(uuid)'::regprocedure,'private.persona_vetada_perfil(uuid)'::regprocedure,'private.personas_de_perfil(uuid)'::regprocedure,'private.trg_tareas_veto_persona_perfil()'::regprocedure,'private.trg_actividades_cliente_veto_persona()'::regprocedure) and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-3: un helper privado quedó con EXECUTE para la API o PUBLIC';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.tareas'::regclass and t.tgname = 'trg_tareas_00_0_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) is distinct from 'CREATE TRIGGER trg_tareas_00_0_veto_persona BEFORE INSERT ON crm.tareas FOR EACH ROW EXECUTE FUNCTION private.trg_tareas_veto_persona_perfil()'
     or (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.actividades_cliente'::regclass and t.tgname = 'trg_actividades_cliente_01_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) is distinct from 'CREATE TRIGGER trg_actividades_cliente_01_veto_persona BEFORE INSERT ON crm.actividades_cliente FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_cliente_veto_persona()' then
    raise exception 'POSTFLIGHT D-3: un trigger de D-3 no está montado tal cual o está deshabilitado';
  end if;
  if exists (select 1 from unnest(array['crm.marcar_no_contactar(uuid,text)','crm.levantar_no_contactar(uuid,text)']) f(firma)
             where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
                or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0))
     or exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol)
                where has_function_privilege(r.rol, 'private.leads_vetados_persona(uuid[])', 'EXECUTE')) then
    raise exception 'POSTFLIGHT D-3: los grants de marcar/levantar (solo authenticated) o del helper cambiaron';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure) is distinct from '2421b2b78b02b8e93fd01598e2f54128'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-3: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.trg_gestion_lead_serializada()'::regprocedure) is distinct from '7af0e66b8a4849566e43b514245e1b86' then
    raise exception 'F2.b D-3: private.trg_gestion_lead_serializada() no es el texto vivo de producción (D-3 v3 NO la toca)';
  end if;
  if to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null or to_regprocedure('private.inversionista_canonica(uuid)') is null then
    raise exception 'F2.b D-3: faltan private.identidad_bloquear_documentos_de (D-13) o private.inversionista_canonica (b5)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-3: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-3 OK (v3): veto coherente en tareas de perfil, ficha del cliente y leads sueltos/puente (rama ON). Bandera APAGADA.';
end
$post$;
commit;
