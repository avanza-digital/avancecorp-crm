-- Revierte solo código de esta candidata. No deshace historial ni datos.
begin;
drop trigger if exists aaa_asesor_solo_nucleo on public.perfiles;
CREATE OR REPLACE FUNCTION "public"."proteger_campos_inmutables"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_f4_alinea boolean := false;
BEGIN
  -- Excepción de una única columna desde la revisión F4 del servidor. Las
  -- escrituras directas mantienen todas las congelaciones originales.
  IF TG_TABLE_NAME='perfiles' AND current_user='postgres'
     AND nullif(current_setting('crm.f4_revision_solicitud',true),'') IS NOT NULL THEN
    v_f4_alinea:=private.f4_alineacion_perfil_permitida(OLD.id,NEW.asesor_perfil_id);
  END IF;
  NEW.id         := OLD.id;
  NEW.creado_en  := OLD.creado_en;
  NEW.creado_por := OLD.creado_por;

  -- Campos privilegiados / de asignacion: se congelan para el usuario que edita su PROPIA
  -- fila (cliente) y TAMBIEN para un ANALISTA que edita la fila de un cliente. Antes solo se
  -- congelaban en la auto-edicion (NEW.id=auth.uid()), por eso un analista podia togglear
  -- activo / debe_cambiar_password / blanquear asesor_perfil_id de su cliente via UPDATE forjado.
  -- admin/superadmin quedan EXCLUIDOS (siguen reasignando/activando). service_role
  -- (auth.uid() IS NULL, no es_analista) NO se ve afectado -> las edges de alta/baja siguen igual.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND ( NEW.id = auth.uid() OR public.es_analista() ) THEN
    NEW.activo           := OLD.activo;
    NEW.rol              := OLD.rol;
    NEW.asesor_id        := OLD.asesor_id;
    IF NOT v_f4_alinea THEN NEW.asesor_perfil_id := OLD.asesor_perfil_id; END IF;
    NEW.cargo            := OLD.cargo;
    -- El flag de cambio de clave solo lo baja el PROPIO usuario (primer login);
    -- un analista editando a un cliente NO puede tocarlo.
    IF NEW.id <> auth.uid() THEN
      NEW.debe_cambiar_password := OLD.debe_cambiar_password;
    END IF;
  END IF;

  -- Asiento «Operaciones» (2026-08-21): edita al cliente y lo activa o desactiva,
  -- pero NO lo mueve de analista. El `rol` se congela ademas por si acaso: la
  -- politica ya lo acota a 'cliente', esto es la segunda linea de defensa.
  IF TG_TABLE_NAME = 'perfiles'
     AND NOT public.es_admin()
     AND public.es_operaciones()
     AND NEW.id <> auth.uid() THEN
    IF (NEW.asesor_perfil_id IS DISTINCT FROM OLD.asesor_perfil_id AND NOT v_f4_alinea)
       OR NEW.asesor_id IS DISTINCT FROM OLD.asesor_id THEN
      RAISE EXCEPTION 'El asiento Operaciones no puede reasignar el asesor de un cliente'
        USING ERRCODE = '42501';
    END IF;
    NEW.rol := OLD.rol;
  END IF;

  -- Ciclo de vida de contratos (2026-07-13): una vez cerrado un ciclo, el
  -- enlace de renovacion y los sellos de cierre quedan congelados para
  -- cualquier no-superadmin (correcciones = superadmin).
  IF TG_TABLE_NAME = 'contratos' AND NOT public.es_superadmin() THEN
    IF OLD.renovado_a_id IS NOT NULL THEN NEW.renovado_a_id := OLD.renovado_a_id; END IF;
    IF OLD.cerrado_en    IS NOT NULL THEN NEW.cerrado_en    := OLD.cerrado_en;    END IF;
    IF OLD.cerrado_por   IS NOT NULL THEN NEW.cerrado_por   := OLD.cerrado_por;   END IF;
  END IF;

  RETURN NEW;
END; $$;


drop function if exists private.trg_perfiles_asesor_por_nucleo();
CREATE OR REPLACE FUNCTION "crm"."reasignar_responsable_relacion_fn"("p_inversionista" "uuid", "p_nuevo_responsable" "uuid", "p_motivo" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "lock_timeout" TO '5s'
    AS $$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
  v_rol_nuevo text; v_leads uuid[] := array[]::uuid[]; v_leads_movidos integer := 0; v_perfil_movido boolean := false; v_tenencia text := 'sin_cambios';  -- F2.b [D-2]
begin
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) + Gerencia y destinatario revalidados bajo ella -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación (membresía revalidada)' using errcode = '42501';
  end if;
  if not coalesce(private.rol_crm(p_nuevo_responsable) in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial (rol efectivo)' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- F2.b [D-2] (Codex #12): el motivo se revalida contra los documentos BAJO el lock de la persona (la validación de
  -- arriba corre antes del lock y una corrección documental concurrente pudo cambiarlos).
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  -- F2.b [D-2]: capacidad operativa del nuevo responsable. Si puede tener cartera (vendedor/supervisor activo, rol
  -- efectivo), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su documento, D-13)
  -- pasan a su cartera y el perfil cliente de la persona también. Orden: persona (ya) → tramo (ya) → tareas
  -- pendientes → leads → perfil, como el veto (b2) y la fusión (b5). Con Gerencia como nuevo responsable no hay
  -- cartera que mover: solo el tramo (tenencia = 'sin_cambios').
  v_rol_nuevo := private.rol_crm(p_nuevo_responsable);
  if v_rol_nuevo in ('vendedor', 'supervisor') then
    select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_leads
    from (select l.id from crm.leads l
           where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
             and l.activo = true
             and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
             and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)
           order by l.id) s;
    -- (Codex N1/N4) tampoco se espera por una TAREA ni por el PERFIL: cerrar_tarea tiene la tarea y va tarea → lead/perfil;
    -- el Portal actualiza el perfil y su trigger va perfil → tareas. Con la persona y el tramo en la mano, todo lo demás
    -- se toma SIN esperar → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads) or (v_inv.perfil_id is not null and t.perfil_id = v_inv.perfil_id))
       order by t.id
       for update nowait;
      if v_inv.perfil_id is not null then
        perform 1 from public.perfiles p where p.id = v_inv.perfil_id for no key update nowait;
      end if;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando una tarea o la ficha de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    -- (Codex #1) tareas → leads es el orden de b2/D-3 y de cerrar_tarea; derivar y repartir van lead → tareas (por el
    -- trigger de sincronización) bajo el mismo interlock compartido. Como la fusión (b5, E3-9): los leads se toman
    -- SIN esperar; si otra sesión tiene uno → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    v_tenencia := 'movida';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  -- F2.b [D-2]: la cartera sigue al responsable (los triggers de leads llevan el ledger de asignaciones, la actividad
  -- «reasignacion», tenencia_desde y las tareas pendientes; el del perfil mueve las tareas de cliente y deja su actividad).
  if v_tenencia = 'movida' then
    if coalesce(pg_catalog.array_length(v_leads, 1), 0) > 0 then
      -- (auditor M2) se REVALIDA bajo los locks: sigue vivo, en etapa abierta y sigue siendo de la persona (un descarte o una
      -- conversión concurrentes solo bloquean el lead; la puerta del DNI de D-13 puede llevarse un suelto a otra persona).
      update crm.leads l
         set vendedor_id = p_nuevo_responsable,
             asignado_supervisor_id = null
       where l.id = any(v_leads)
         and l.activo = true
         and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and l.id in (select x from private.leads_de_personas(array[p_inversionista]) x);
      get diagnostics v_leads_movidos = row_count;
    end if;
    if v_inv.perfil_id is not null then
      update public.perfiles p
         set asesor_perfil_id = p_nuevo_responsable,
             actualizado_en = pg_catalog.clock_timestamp()
       where p.id = v_inv.perfil_id and p.rol = 'cliente' and p.activo is true
         and p.asesor_perfil_id is distinct from p_nuevo_responsable;
      v_perfil_movido := found;
    end if;
    -- (auditor N5) «movida» solo si algo se movió de verdad.
    if v_leads_movidos = 0 and not v_perfil_movido then
      v_tenencia := 'sin_cambios';
    end if;
  end if;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Responsable de relación reasignado (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable,
    'tenencia', pg_catalog.jsonb_build_object('estado', v_tenencia, 'leads_movidos', v_leads_movidos, 'perfil_movido', v_perfil_movido));  -- F2.b [D-2]
end;
$$;


CREATE OR REPLACE FUNCTION "public"."reasignar_analista_contrato"("p_contrato_id" "uuid", "p_analista_id" "uuid", "p_motivo" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_motivo text := btrim(p_motivo);
  v_row    public.contratos%rowtype;
  v_id     uuid;
begin
  -- El mismo conjunto que ya puede corregir cualquier contrato.
  if v_uid is null
     or not ((select public.es_gestor_cartera())
             or coalesce(v_rol = 'gerencia', false)) then
    raise insufficient_privilege using
      message = 'No autorizado para reasignar la venta';
  end if;
  -- P04: una membresia CRM revocada manda sobre el poder de portal.
  if (select private.membresia_crm_revocada()) then
    raise insufficient_privilege using
      message = 'Tu membresia CRM fue revocada; no puedes reasignar ventas';
  end if;

  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la reasignacion' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres' using errcode = '22023';
  end if;

  select * into v_row from public.contratos where id = p_contrato_id for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if v_row.es_demo then
    raise exception 'Un contrato de prueba no se atribuye a nadie' using errcode = '22023';
  end if;

  if p_analista_id is null then
    raise exception 'Elige el analista al que pasa la venta' using errcode = '22023';
  end if;
  -- Igual que en el alta: del equipo comercial, sin exigir que siga ACTIVO
  -- (decision 15: la venta de quien ya no esta cuenta igual). Los roles
  -- OFF-ROSTER (coordinador reparte la cola, directorio solo lee) no son filas
  -- del organigrama comercial por diseno documentado del sistema: una venta no
  -- puede ser suya (P1-2 de Codex).
  if not exists (select 1 from crm.equipo e
                 where e.perfil_id = p_analista_id
                   and e.rol_crm in ('vendedor','supervisor','gerencia')) then
    raise exception 'El analista tiene que ser del equipo comercial' using errcode = '22023';
  end if;
  if v_row.analista_cierre_id is not distinct from p_analista_id then
    raise exception 'Esa venta ya esta atribuida a esa persona' using errcode = 'P0409';
  end if;

  insert into crm.reasignaciones_analista (
    contrato_id, analista_de, analista_a, motivo, reasignado_por
  ) values (
    p_contrato_id, v_row.analista_cierre_id, p_analista_id, v_motivo, v_uid
  ) returning id into v_id;

  -- La valvula, solo para esta sentencia y solo en esta transaccion.
  perform set_config('crm.reasignando_analista', 'on', true);
  update public.contratos
     set analista_cierre_id = p_analista_id
   where id = p_contrato_id;
  perform set_config('crm.reasignando_analista', 'off', true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'de', v_row.analista_cierre_id,
    'a', p_analista_id,
    'reasignacion_id', v_id);
end;
$$;


drop function if exists crm.confirmar_cambio_responsabilidad_fn(text,uuid,uuid,text,text);
drop function if exists crm.previsualizar_cambio_responsabilidad_fn(text,uuid,uuid);
drop function if exists private.ejecutar_cambio_responsabilidad(text,uuid,uuid,text,text,boolean);
drop function if exists private.cambio_responsabilidad_previa(text,uuid,uuid);
drop function if exists private.analista_previsto_contrato(uuid,uuid,uuid,uuid,uuid,uuid);
drop function if exists private.cambiar_atencion_persona(uuid,uuid,text);
drop function if exists private.atencion_perfil_permitida(uuid,uuid);
drop function if exists private.puede_cambiar_atencion();
REVOKE ALL ON FUNCTION "crm"."reasignar_responsable_relacion_fn"("p_inversionista" "uuid", "p_nuevo_responsable" "uuid", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "crm"."reasignar_responsable_relacion_fn"("p_inversionista" "uuid", "p_nuevo_responsable" "uuid", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."proteger_campos_inmutables"() TO "anon";
GRANT ALL ON FUNCTION "public"."proteger_campos_inmutables"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."proteger_campos_inmutables"() TO "service_role";
GRANT EXECUTE ON FUNCTION "public"."proteger_campos_inmutables"() TO PUBLIC;
REVOKE ALL ON FUNCTION "public"."reasignar_analista_contrato"("p_contrato_id" "uuid", "p_analista_id" "uuid", "p_motivo" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reasignar_analista_contrato"("p_contrato_id" "uuid", "p_analista_id" "uuid", "p_motivo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reasignar_analista_contrato"("p_contrato_id" "uuid", "p_analista_id" "uuid", "p_motivo" "text") TO "service_role";
COMMENT ON FUNCTION public.proteger_campos_inmutables() IS NULL;
COMMENT ON FUNCTION public.reasignar_analista_contrato(uuid,uuid,text) IS NULL;
COMMENT ON FUNCTION crm.reasignar_responsable_relacion_fn(uuid,uuid,text) IS NULL;
commit;
