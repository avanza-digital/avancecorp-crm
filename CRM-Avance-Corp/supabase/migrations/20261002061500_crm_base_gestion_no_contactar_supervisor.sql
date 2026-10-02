-- 20261002061500_crm_base_gestion_no_contactar_supervisor.sql
--
-- Base para gestión del analista · B2 (permisos). Decisión D5 de Miguel (02/10/2026): «quitar No contactar» pasa de
-- «solo Gerencia» a «Gerencia o Supervisión dentro de su ámbito». Plan B2 confirmado por Miguel el 02/10 («vamos si»),
-- incluida la regla «todos los leads de la persona en su equipo». Nota del vault: «Base para gestion del analista -
-- F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- QUÉ. `crm.levantar_no_contactar(uuid, text)` (texto vivo 20260906160000, md5 prosrc 3840a73f…) gana tres cosas y
--   nada más, por sustituciones exactas sobre el texto vivo (no se reteclea):
--   1. Gate: `v_rol in ('supervisor','gerencia')` (con `v_rol is null` rechazando). Analistas, coordinación y directorio: 42501.
--   2. Ámbito de Supervisión: ANTES de resolver la identidad o tomar candados, el lead pedido debe estar en su ámbito
--      (espejo de la policy `leads_select` sin la rama de gerencia) → si no, P0002 «no encontrado o fuera de tu ámbito»
--      (no revela si existe). Bajo candado se revalida y, además, TODOS los leads de la persona que se van a tocar
--      (`v_leads`: enlace ∪ puente ∪ sueltos ∪ el propio) deben estar en su equipo; si alguno es de otro equipo →
--      42501 «La persona tiene leads fuera de tu equipo: pídelo a Gerencia». La Ley 29571 trata el veto por persona:
--      Supervisión no puede levantar un veto que alcanza leads que no gestiona.
--   3. Historial: la actividad dice «por Gerencia» o «por Supervisión» y lleva `rol` en la metadata.
--   La resolución de identidad, los candados (documentos → persona → leads), las 40001 y la escritura bajo
--   `crm.op_privilegiada` quedan byte a byte como estaban. El motivo sigue siendo obligatorio.
--
-- QUÉ NO CAMBIA. `crm.marcar_no_contactar` (sellada por huella en assert_gestion_diaria_resultado) no se toca. La
--   función NO está fijada por ningún `private.assert_*` (solo anclas puntuales en 20260904130000 y 20260906200000,
--   que ya corrieron). ACL: se reafirma EXECUTE solo para `authenticated` (dueño postgres). RLS y policies intactas.
--   Para el analista no cambia nada: la RLS vigente ya limita lectura y escritura a sus propios leads, actividades y
--   tareas (B2 lo demuestra con `supabase/scripts/base-gestion/b2-rls.sql`, sin migración).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-no-contactar-supervisor.sql`: reinstala el texto vivo byte a byte
--   (md5 3840a73f…), reafirma la ACL y el comentario. No toca datos (los levantamientos hechos por Supervisión quedan
--   en el historial con su `rol`).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    to_regprocedure('crm.levantar_no_contactar(uuid,text)') is not null
    and (select count(*) from pg_proc where proname = 'levantar_no_contactar' and pronamespace = 'crm'::regnamespace) = 1
    and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)')) = '3840a73fc3a1db8f27ea921fad1bd65a'
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)')
                 and p.prosecdef and p.proconfig = array['search_path=""']::text[])
    and to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and to_regprocedure('private.rol_crm(uuid)') is not null
  ) is not true then
    raise exception 'PREFLIGHT: crm.levantar_no_contactar no es el texto vivo auditado (3840a73f…), tiene otra firma o faltan sus ayudantes';
  end if;
end;
$preflight$;

create or replace function crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean;
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  -- B2 · Base para gestión (D5, Miguel 02/10/2026): Gerencia o Supervisión. Supervisión solo dentro de su ámbito y
  -- solo si TODA la persona (sus leads) cae en su equipo; si no, lo pide a Gerencia. `v_rol is null` también rechaza.
  if v_uid is null or v_rol is null or v_rol not in ('supervisor', 'gerencia') then
    raise exception 'Solo Gerencia o Supervisión pueden levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
  -- Ámbito ANTES de resolver la identidad o tomar candados (el espejo de la policy leads_select, sin la rama de gerencia).
  if v_rol = 'supervisor' and not exists (
       select 1 from crm.leads l
        where l.id = p_lead_id
          and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
               or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);

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
  -- B2 (D5): bajo candado, el ámbito se revalida y se exige para TODOS los leads de la persona que se van a tocar.
  if v_rol = 'supervisor' then
    if not (v_lead.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
            or (v_lead.vendedor_id is null and v_lead.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))) then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from crm.leads l
                where l.id = any(v_leads)
                  and not (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                           or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
      raise exception 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia' using errcode = '42501';
    end if;
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
  values (p_lead_id, 'nota', 'Levantado No contactar por ' || case when v_rol = 'gerencia' then 'Gerencia' else 'Supervisión' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo), 'rol', v_rol),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$;
alter function crm.levantar_no_contactar(uuid, text) owner to postgres;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;
comment on function crm.levantar_no_contactar(uuid, text) is
  'Levanta No contactar (Ley 29571) de la persona del lead y de todos sus leads. Gerencia en toda la operación; Supervisión (B2, D5 02/10/2026) solo si el lead y TODOS los leads de la persona están en su equipo (si no, 42501: pídelo a Gerencia). Motivo obligatorio; queda en el historial con el rol. DEFINER: compone la identidad y escribe bajo crm.op_privilegiada; search_path vacío, dueño postgres, EXECUTE solo authenticated.';

do $postflight$
declare
  f constant text := 'crm.levantar_no_contactar(uuid,text)';
  v_src text;
  v_vend uuid;
  v_sup uuid;
  v_lead uuid;
begin
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure(f);
  -- 1. Cuerpo ENSAYADO (md5 medido en el banco), contrato intacto, ACL exacta.
  if (
    md5(v_src) = '2467b5068fc814ce42f18596d740ebcb'
    and v_src like '%Solo Gerencia o Supervisión pueden levantar No contactar%'
    and v_src like '%pídelo a Gerencia%'
    and v_src like '%''rol'', v_rol%'
    and (select count(*) from pg_proc where proname = 'levantar_no_contactar' and pronamespace = 'crm'::regnamespace) = 1
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure(f) and p.prosecdef
                 and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and has_function_privilege('authenticated', f, 'EXECUTE')
    and not has_function_privilege('anon', f, 'EXECUTE')
    and not has_function_privilege('service_role', f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(f)
                     and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                          or (a.grantee = 'authenticated'::regrole and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
  ) is not true then
    raise exception 'POSTFLIGHT: levantar_no_contactar no quedo con el cuerpo ensayado, el contrato DEFINER/postgres/search_path vacio o la ACL exacta';
  end if;
  -- 2. Negativos sin escribir (cada uno falla ANTES de tocar datos; se deshacen igual por sub-bloque).
  select e.perfil_id into v_vend from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'vendedor' and e.activo and p.activo order by e.perfil_id limit 1;
  select l.id into v_lead from crm.leads l where l.activo order by l.creado_en limit 1;
  if v_vend is not null and v_lead is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform crm.levantar_no_contactar(v_lead, 'postflight');
      raise exception 'POSTFLIGHT: un analista pudo llamar a levantar_no_contactar' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm not like 'Solo Gerencia o Supervisi%' then
        raise exception 'POSTFLIGHT: el analista fue rechazado por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
    end;
  else
    raise notice 'base_gestion B2: sin analista o lead activo en esta base; negativo del analista NO RUN';
  end if;
  -- Supervisión fuera de ámbito: un supervisor y un lead cuyo vendedor NO está en su subárbol (si existe el par).
  select e.perfil_id into v_sup from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'supervisor' and e.activo and p.activo order by e.perfil_id limit 1;
  if v_sup is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
      select l.id into v_lead from crm.leads l
       where l.activo and l.vendedor_id is not null
         and l.vendedor_id not in (select private.vendedor_ids_visibles(v_sup))
       order by l.creado_en limit 1;
      if v_lead is null then
        perform pg_catalog.set_config('request.jwt.claims', '', true);
        perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
        raise notice 'base_gestion B2: el primer supervisor ve todos los leads de esta base; negativo fuera de ambito NO RUN';
      else
        perform crm.levantar_no_contactar(v_lead, 'postflight');
        raise exception 'POSTFLIGHT: Supervision levanto fuera de su ambito' using errcode = 'P0001';
      end if;
    exception when no_data_found then
      if sqlerrm not like '%fuera de tu %mbito%' then
        raise exception 'POSTFLIGHT: Supervision fuera de ambito fue rechazada por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
    end;
  end if;
  raise notice 'base_gestion_no_contactar_supervisor OK: gate Gerencia|Supervision, ambito por persona, historial con rol, ACL exacta';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
