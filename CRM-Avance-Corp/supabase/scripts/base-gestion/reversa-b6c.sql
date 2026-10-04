-- REVERSA de 20261004123611_crm_base_gestion_reservar_nota_veto (B6c): borra el sello trg_00_actividades_no_contactar_solo_puerta
-- y su función, reinstala crm.levantar_no_contactar con el texto EXACTO de B2 (20261002061500; md5 prosrc 05df49be…; la
-- válvula se apaga antes de su nota), con su dueño, ACL y comentario de B2, y devuelve a crm.obtener_base_gestion(uuid, boolean)
-- el comentario EXACTO de B6b (el cuerpo no se tocó). No toca datos: las notas del veto escritas quedan. Tras revertir, la API
-- vuelve a poder insertar la nota del veto (el riesgo P2b de B6b). Va ANTES que reversa-b6b.sql.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;
do $pre$
begin
  if (
    (select md5(p.prosrc) = 'af83cbd67513122a325d2f159254bb3c' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()'))
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta')
    and (select md5(p.prosrc) = '663780d27e3c7aa8d086f9a376ab3c4b' from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
  ) is not true then
    raise exception 'REVERSA B6c: el estado vivo no es el de B6c (sello, levantar o comentario de la base); revisar antes de revertir';
  end if;
end;
$pre$;
drop trigger trg_00_actividades_no_contactar_solo_puerta on crm.actividades;
drop function private.trg_actividades_no_contactar_solo_puerta();
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
          and l.activo
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
  -- Las dos comprobaciones van con `is not true`: un lead sin vendedor cuyo supervisor no está en el ámbito da NULL
  -- (NULL in (...)) y un `not NULL` dejaría pasar (Codex B1+B2, P1). Fail-closed también ante NULL.
  if v_rol = 'supervisor' then
    if (v_lead.activo
        and (v_lead.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
             or (v_lead.vendedor_id is null and v_lead.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) is not true then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from crm.leads l
                where l.id = any(v_leads)
                  and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                       or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))) is not true) then
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
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. La nota de veto que actividades_insert deja escribir desde la API se cierra en B6c (decisión de Miguel 04/10). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select).';
do $post$
begin
  if (
    to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta')
    and (select md5(p.prosrc) = '05df49be43869cd8e5f75330fa592a84'
            and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
            and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '5325ff9e4d60af5816bc20aa899e4dd1'
       from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '469119616ab78df3eba406c7622d3888'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
  ) is not true then
    raise exception 'REVERSA B6c: no quedo el estado de B6b (levantar de B2, comentario de B6b, sin sello)';
  end if;
  raise notice 'REVERSA B6c OK: sin sello, levantar = B2 (05df49be...), comentario de la base = B6b';
end;
$post$;
notify pgrst, 'reload schema';
commit;
