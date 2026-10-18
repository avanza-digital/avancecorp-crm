-- F3-A: origen propio, contratos compatibles y mismo turno/peso que Formulario.
-- NO reclasifica datos ni normaliza importaciones legadas; activación separada después del frontend.
-- Cuerpos y ACL cotejados con producción 15/10/2026. Sin CASCADE, sin desactivar triggers/RLS.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtextextended('crm:formulario3:origen',0));
do $guardas$ begin
  if md5(pg_get_functiondef('private.leads_before_insert()'::regprocedure)) <> '65512988853c92ca30d9f116cd538d3b' then
    raise exception 'Preflight F3: cambió la función %', 'private.leads_before_insert()';
  end if;
  if md5(pg_get_functiondef('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure)) <> 'd1daa1c65f18b4b41a6c9ffa99372bcf' then
    raise exception 'Preflight F3: cambió la función %', 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)';
  end if;
  if md5(pg_get_functiondef('crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)'::regprocedure)) <> '37e4e2a13b50c757ffc7a8fdcb3c37b0' then
    raise exception 'Preflight F3: cambió la función %', 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)';
  end if;
  if md5(pg_get_functiondef('private.normalizar_campania_origen(jsonb,text)'::regprocedure)) <> '222c879d3201546c8eff5fee6d367346' then
    raise exception 'Preflight F3: cambió la función %', 'private.normalizar_campania_origen(jsonb,text)';
  end if;
  if md5(pg_get_functiondef('private.repartir_lead_implementacion(uuid,uuid)'::regprocedure)) <> '8da313cb59c04faba4499945e0e5e091' then
    raise exception 'Preflight F3: cambió la función %', 'private.repartir_lead_implementacion(uuid,uuid)';
  end if;
  if md5(pg_get_functiondef('crm.guardar_agenda_reparto_diaria(date,uuid,uuid)'::regprocedure)) <> '96fdda88874d775cc294a657414d3249' then
    raise exception 'Preflight F3: cambió la función %', 'crm.guardar_agenda_reparto_diaria(date,uuid,uuid)';
  end if;
  if md5(pg_get_functiondef('private.leads_por_repartir_implementacion()'::regprocedure)) <> '23b75b228a9ce96b06b46377687b1b5a' then
    raise exception 'Preflight F3: cambió la función %', 'private.leads_por_repartir_implementacion()';
  end if;
  if md5(pg_get_functiondef('crm.leads_por_repartir()'::regprocedure)) <> 'b52431bc89bdc0b382e167a938e06abb' then
    raise exception 'Preflight F3: cambió la función %', 'crm.leads_por_repartir()';
  end if;
  if md5(pg_get_functiondef('crm.agenda_reparto_diaria(date,integer)'::regprocedure)) <> '3e93fd64e169f111c37a2d926bdcfb93' then
    raise exception 'Preflight F3: cambió la función %', 'crm.agenda_reparto_diaria(date,integer)';
  end if;
  if md5(pg_get_functiondef('crm.reporte_derivaciones_coordinacion_fn(date,date)'::regprocedure)) <> '1c7380008403af7cfa2ade2a976f2cd4' then
    raise exception 'Preflight F3: cambió la función %', 'crm.reporte_derivaciones_coordinacion_fn(date,date)';
  end if;
  if md5(pg_get_functiondef('crm.rescate_descartes_mes(date)'::regprocedure)) <> 'dbafbce5560220a38cf4bd40f979dc3d' then
    raise exception 'Preflight F3: cambió la función %', 'crm.rescate_descartes_mes(date)';
  end if;
  if md5(pg_get_functiondef('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure)) <> '1e374f6b0d63d631272c675f66ed205a' then
    raise exception 'Preflight F3: cambió la función %', 'private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)';
  end if;
  if md5(pg_get_functiondef('private.conversion_origen_con_cierre(text)'::regprocedure)) <> '7bf760992c8c89d78a56cc21f6f0cced' then
    raise exception 'Preflight F3: cambió la función %', 'private.conversion_origen_con_cierre(text)';
  end if;
  if md5(pg_get_functiondef('private.conversion_origen_base_tope(text)'::regprocedure)) <> '7bb45889656cf4312e68fcd251a18bd3' then
    raise exception 'Preflight F3: cambió la función %', 'private.conversion_origen_base_tope(text)';
  end if;
  if md5(pg_get_functiondef('private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone)'::regprocedure)) <> '332deb67bae5fc50f37230b5ad971aaa' then
    raise exception 'Preflight F3: cambió la función %', 'private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone)';
  end if;
  if md5(pg_get_functiondef('private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'::regprocedure)) <> '1c7a7a3343766d392501fcee6b439da9' then
    raise exception 'Preflight F3: cambió la función %', 'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)';
  end if;
  if md5(pg_get_functiondef('private.ranking_origen_live(date,uuid,jsonb)'::regprocedure)) <> '6f55917b59a9fa4b476656c0011773fa' then
    raise exception 'Preflight F3: cambió la función %', 'private.ranking_origen_live(date,uuid,jsonb)';
  end if;
  if md5(pg_get_functiondef('private.conversion_divisor_empresa(date,date)'::regprocedure)) <> '31ddfbc997d846eac21d4422c6a1e01a' then
    raise exception 'Preflight F3: cambió la función %', 'private.conversion_divisor_empresa(date,date)';
  end if;
  if md5(pg_get_functiondef('private.conversion_divisor_empresa_totales(date,date)'::regprocedure)) <> '1620670d0b2db4c6d37f8db47a3a567e' then
    raise exception 'Preflight F3: cambió la función %', 'private.conversion_divisor_empresa_totales(date,date)';
  end if;
  if md5(pg_get_functiondef('crm.conversion_divisor_coordinacion_fn(date,date,date)'::regprocedure)) <> 'e688dba65cb20ee0a9eef6248f5aecd1' then
    raise exception 'Preflight F3: cambió la función %', 'crm.conversion_divisor_coordinacion_fn(date,date,date)';
  end if;
  if md5(pg_get_functiondef('crm.importar_lead_fn(jsonb)'::regprocedure)) <> '138e915834ae7768bb1023b2e2b38504' then
    raise exception 'Preflight F3: cambió la función %', 'crm.importar_lead_fn(jsonb)';
  end if;
  if md5(pg_get_functiondef('private.registrar_solicitud_cliente_fn(uuid,text,jsonb)'::regprocedure)) <> '29adbdeba4bc89454288114ed2b6f975' then
    raise exception 'Preflight F3: cambió la función %', 'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid='crm.origenes_capital_confirmados'::regclass and conname='origenes_capital_confirmados_origen_check') is distinct from 'CHECK ((origen = ANY (ARRAY[''landing''::text, ''formulario''::text, ''referido''::text, ''oficina''::text])))' then raise exception 'Preflight F3: cambió origenes_capital_confirmados_origen_check'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid='crm.leads'::regclass and conname='leads_origen_check') is distinct from 'CHECK ((origen = ANY (ARRAY[''referido''::text, ''landing''::text, ''formulario''::text, ''oficina''::text, ''otro''::text, ''web''::text, ''campania''::text, ''whatsapp''::text, ''base_cargada''::text])))' then raise exception 'Preflight F3: cambió leads_origen_check'; end if;
end; $guardas$;


create temporary table _f3_censo_antes on commit drop as select * from private.analitica_leads_citas_exenciones;

create temporary table _f3_censo_estado_antes on commit drop as select * from private.contadores_crudos_leads_citas();

create temporary table _f3_acl_antes on commit drop as select p.oid::regprocedure::text as firma, p.proacl, obj_description(p.oid,'pg_proc') as comentario from pg_proc p where p.oid in ('private.leads_before_insert()'::regprocedure,'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure,'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)'::regprocedure,'private.normalizar_campania_origen(jsonb,text)'::regprocedure,'private.repartir_lead_implementacion(uuid,uuid)'::regprocedure,'crm.guardar_agenda_reparto_diaria(date,uuid,uuid)'::regprocedure,'private.leads_por_repartir_implementacion()'::regprocedure,'crm.leads_por_repartir()'::regprocedure,'crm.agenda_reparto_diaria(date,integer)'::regprocedure,'crm.reporte_derivaciones_coordinacion_fn(date,date)'::regprocedure,'crm.rescate_descartes_mes(date)'::regprocedure,'private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)'::regprocedure,'private.conversion_origen_con_cierre(text)'::regprocedure,'private.conversion_origen_base_tope(text)'::regprocedure,'private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone)'::regprocedure,'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'::regprocedure,'private.ranking_origen_live(date,uuid,jsonb)'::regprocedure,'private.conversion_divisor_empresa(date,date)'::regprocedure,'private.conversion_divisor_empresa_totales(date,date)'::regprocedure,'crm.conversion_divisor_coordinacion_fn(date,date,date)'::regprocedure,'crm.importar_lead_fn(jsonb)'::regprocedure,'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)'::regprocedure);


-- Small, pure mappings. They neither authorize actors nor read/change CRM data.
create function private.origen_turno_reparto(p_origen text) returns text
language sql immutable set search_path = '' as $fn$
  select case when p_origen='landing' then 'landing'
    when p_origen in ('formulario','formulario_3') then 'formulario' end;
$fn$;
revoke all on function private.origen_turno_reparto(text) from public, anon, authenticated, service_role;
comment on function private.origen_turno_reparto(text) is 'Turno operativo, distinto del origen exacto: Formulario y Formulario 3 comparten la agenda Formulario.';

create function private.origen_episodio_lead(p_snapshot text, p_origen_actual text) returns text
language sql immutable set search_path = '' as $fn$
  select case when p_snapshot='formulario' and p_origen_actual='formulario_3'
    then 'formulario_3' else p_snapshot end;
$fn$;
revoke all on function private.origen_episodio_lead(text,text) from public, anon, authenticated, service_role;
comment on function private.origen_episodio_lead(text,text) is 'Proyección puntual de episodios legados F3. No reescribe el ledger ni atribuye el origen actual a episodios de otros canales.';

create function private.datos_solicitud_comparables(p_datos jsonb) returns jsonb
language sql immutable set search_path = '' as $fn$
  select case when p_datos->>'canal'='formulario_3'
      and (not p_datos ? 'campania_origen' or p_datos->'campania_origen'='null'::jsonb
        or p_datos->>'campania_origen'='Formulario 3')
    then p_datos || jsonb_build_object('canal','formulario','campania_origen','Formulario 3')
    else p_datos end;
$fn$;
revoke all on function private.datos_solicitud_comparables(jsonb) from public, anon, authenticated, service_role;
comment on function private.datos_solicitud_comparables(jsonb) is 'Compatibilidad de la huella de reingreso F3: solo al comparar, conserva el JSON legado formulario + campaña. No cambia notas ni otros orígenes.';


alter table crm.origenes_capital_confirmados drop constraint origenes_capital_confirmados_origen_check;
alter table crm.origenes_capital_confirmados add constraint origenes_capital_confirmados_origen_check CHECK ((origen = ANY (ARRAY['landing'::text, 'formulario'::text, 'formulario_3'::text, 'referido'::text, 'oficina'::text])));

alter table crm.leads drop constraint leads_origen_check;
alter table crm.leads add constraint leads_origen_check CHECK ((origen = ANY (ARRAY['referido'::text, 'landing'::text, 'formulario'::text, 'formulario_3'::text, 'oficina'::text, 'otro'::text, 'web'::text, 'campania'::text, 'whatsapp'::text, 'base_cargada'::text])));

drop function crm.leads_por_repartir();

drop function private.leads_por_repartir_implementacion();

drop function private.conversion_divisor_empresa_totales(date,date);

drop function private.conversion_divisor_empresa(date,date);

CREATE OR REPLACE FUNCTION private.leads_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Durante A se admite el cliente nuevo, pero se persiste la forma compatible
  -- con pestañas antiguas. B cambia esta traducción al origen canónico.
  if new.origen='formulario_3' then
    if (select auth.uid()) is not null then
      raise exception 'Formulario 3 estará disponible al completar la actualización. Inténtalo más tarde.' using errcode='42501';
    end if;
    if new.campania_origen is not null and new.campania_origen<>'Formulario 3' then
      raise exception 'El origen Formulario 3 no admite otra campaña' using errcode='22023';
    end if;
    new.origen := 'formulario';
    new.campania_origen := 'Formulario 3';
  end if;
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','formulario_3','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking';
  end if;
  if not v_priv then
    -- B8: el contacto de una base cargada nace DORMIDO (descartado, motivo base_cargada) solo bajo la válvula de la carga
    -- (private.bases_carga_nace_dormido, una sola definición). Cualquier otra alta sigue sin poder nacer terminal.
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$;


CREATE OR REPLACE FUNCTION crm.crear_lead_si_disponible(p_nombre_completo text, p_telefono text, p_origen text, p_monto_estimado numeric, p_moneda text, p_id uuid DEFAULT NULL::uuid, p_correo text DEFAULT NULL::text, p_dni text DEFAULT NULL::text, p_genero text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_distrito text DEFAULT NULL::text, p_etapa text DEFAULT 'nuevo'::text, p_categoria_interes text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_nota text DEFAULT NULL::text, p_telefono_alternativo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
  v_alt_bruto text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
  v_alt text;
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_correo text := nullif(pg_catalog.btrim(p_correo), '');
  v_genero text := nullif(pg_catalog.btrim(p_genero), '');
  v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
  v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
  v_nota text := nullif(pg_catalog.btrim(p_nota), '');
  v_vendedor uuid := p_vendedor_id;
  v_supervisor uuid;
  v_disponibilidad jsonb;
  v_existente crm.leads%rowtype;
  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_nombre is null then
    raise exception using errcode = '22023', message = 'El nombre es obligatorio';
  end if;
  if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  -- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,
  -- via la MISMA regla que el conector y el front. No participa del dedup: la
  -- identidad del lead sigue siendo `telefono`.
  if v_alt_bruto is not null then
    select c.e164 into v_alt from private.canonizar_contacto(v_alt_bruto) c;
    if v_alt is null then
      raise exception using
        errcode = '22023',
        message = 'Segundo telefono invalido: celular peruano, fijo peruano (014457890) o internacional con +codigo de pais';
    end if;
    -- Si repite al principal no aporta un canal nuevo: se guarda vacio en vez de
    -- enseñar el mismo numero dos veces en la ficha.
    if v_alt = v_telefono then
      v_alt := null;
    end if;
  end if;

  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario','formulario_3', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
  end if;

  -- Alta manual: cuatro canales concretos. Los heredados se leen,
  -- pero no se eligen al crear. Referido conserva sus permisos propios.
  if p_origen is null or p_origen not in ('referido', 'landing', 'formulario','formulario_3', 'oficina') then
    raise exception using
      errcode = '42501',
      message = 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking';
  end if;

  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;

  if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
  end if;
  if p_monto_estimado is null
     or p_monto_estimado <= 0
     or p_monto_estimado > 9999999999.99
     or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
    raise exception using errcode = '22023', message = 'Capital estimado invalido';
  end if;
  if p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda invalida';
  end if;
  if v_genero is not null and v_genero not in ('F', 'M') then
    raise exception using errcode = '22023', message = 'Genero invalido';
  end if;
  if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception using errcode = '22023', message = 'Categoria de interes invalida';
  end if;
  if p_fecha_nacimiento is not null
     and (
       p_fecha_nacimiento < date '1900-01-01'
       or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
     ) then
    raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
  end if;

  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then
    if v_vendedor is not null and v_vendedor is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
    end if;
    v_vendedor := v_actor;
    v_supervisor := null;
  elsif v_vendedor is null and v_rol = 'supervisor' then
    v_supervisor := v_actor;
  else
    v_supervisor := null;
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  -- La identidad optimista funciona también como llave idempotente: si el
  -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
  -- antes de una mutación posterior confirma el alta anterior en vez de
  -- pintarla como un contacto ajeno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
  );
  -- F2.b (b1): orden total documento -> identidad -> contactos. Con la bandera
  -- apagada el helper no toma ningún lock (paridad exacta).
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- Un administrador puede desactivar la membresia mientras esta sesion
  -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
  -- los locks para que una sesion revocada no alcance a insertar al despertar.
  v_rol_actual := private.rol_crm(v_actor);
  if v_rol_actual is distinct from v_rol
     or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  select l.* into v_existente
  from crm.leads l
  where l.id = v_id;

  if found then
    if v_existente.creado_por is not distinct from v_actor
       and v_existente.nombre_completo is not distinct from v_nombre
       and v_existente.telefono is not distinct from v_telefono
       -- El segundo numero entra en la comparacion idempotente: sin esto, un
       -- reintento que SOLO cambia el alternativo se confirmaria como «ya
       -- creado» y el dato nuevo se perderia sin decir nada.
       and v_existente.telefono_alternativo is not distinct from v_alt
       and v_existente.correo is not distinct from v_correo
       and v_existente.dni is not distinct from v_dni
       and v_existente.genero is not distinct from v_genero
       and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
       and v_existente.distrito is not distinct from v_distrito
       and v_existente.origen is not distinct from p_origen
       and v_existente.etapa is not distinct from p_etapa
       and v_existente.monto_estimado is not distinct from p_monto_estimado
       and v_existente.moneda is not distinct from p_moneda
       and v_existente.categoria_interes is not distinct from v_categoria
       and v_existente.vendedor_id is not distinct from v_vendedor
       and v_existente.asignado_supervisor_id is not distinct from v_supervisor
       and v_existente.nota is not distinct from v_nota
       and v_existente.activo = true then
      return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
    end if;

    raise exception using
      errcode = '22023',
      message = 'El identificador de esta alta ya fue usado con datos distintos';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    return v_disponibilidad;
  end if;

  insert into crm.leads (
    id,
    nombre_completo,
    telefono,
    telefono_alternativo,
    correo,
    dni,
    genero,
    fecha_nacimiento,
    distrito,
    origen,
    etapa,
    monto_estimado,
    moneda,
    categoria_interes,
    vendedor_id,
    asignado_supervisor_id,
    nota,
    activo,
    creado_por,
    alta_manual
  ) values (
    v_id,
    v_nombre,
    v_telefono,
    v_alt,
    v_correo,
    v_dni,
    v_genero,
    p_fecha_nacimiento,
    v_distrito,
    p_origen,
    p_etapa,
    p_monto_estimado,
    p_moneda,
    v_categoria,
    v_vendedor,
    v_supervisor,
    v_nota,
    true,
    v_actor,
    true
  );

  return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
end;
$function$;


CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_origen text DEFAULT NULL::text, p_procedencia text DEFAULT NULL::text, p_reasignados boolean DEFAULT false, p_gestion text DEFAULT NULL::text, p_potencial text DEFAULT NULL::text, p_campania_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
  v_potencial boolean;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','formulario_3','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
     -- rechaza, igual que arriba.
     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
     -- Campaña de origen: texto canónico, nunca un cambio del canal comercial.
     or (p_campania_origen is not null and
       (p_campania_origen <> btrim(p_campania_origen)
         or length(p_campania_origen) not between 1 and 80
         or p_campania_origen ~ '[[:cntrl:]]'
         or (lower(p_campania_origen) = 'formulario 3' and p_campania_origen <> 'Formulario 3')))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
  v_potencial := crm.bandera_activa('potencial_lead') is true
    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
  ), previa as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.campania_origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
      mk.nivel as potencial_nivel
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    left join marcas mk on mk.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or (case when l.origen='formulario' and l.campania_origen='Formulario 3' then 'formulario_3' else l.origen end) = p_origen)
      and (p_campania_origen is null or l.campania_origen = p_campania_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), base as not materialized (
    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
    select pv.* from previa pv
    where p_potencial is null
      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
      or pv.potencial_nivel = p_potencial
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),'campania_origen',p_campania_origen,
    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
          'filtro',p_potencial,
          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
          'frio',count(*) filter(where pv.potencial_nivel='frio'),
          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
        else '{}'::jsonb end)
  into v_salida;
  return v_salida;
end;
$function$;


CREATE OR REPLACE FUNCTION private.normalizar_campania_origen(p_valor jsonb, p_origen text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v text;
begin
  if p_valor is null or p_valor='null'::jsonb then
    return case when p_origen='formulario_3' then 'Formulario 3' end;
  end if;
  if pg_catalog.jsonb_typeof(p_valor)<>'string' then
    raise exception 'Campaña debe ser texto' using errcode='22023';
  end if;
  v := pg_catalog.btrim(p_valor #>> '{}');
  if pg_catalog.char_length(v) not between 1 and 80 or v ~ '[[:cntrl:]]' then
    raise exception 'Campaña debe tener de 1 a 80 caracteres sin controles' using errcode='22023';
  end if;
  if pg_catalog.lower(v)='formulario 3' then
    if p_origen is null or p_origen not in ('formulario','formulario_3') then
      raise exception 'Formulario 3 requiere el origen Formulario o Formulario 3' using errcode='22023';
    end if;
    v := 'Formulario 3';
  end if;
  if p_origen='formulario_3' and v<>'Formulario 3' then
    raise exception 'El origen Formulario 3 no admite otra campaña' using errcode='22023';
  end if;
  return v;
end;
$function$;


CREATE OR REPLACE FUNCTION private.repartir_lead_implementacion(p_lead uuid, p_supervisor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_reparto_libre boolean := private.reparto_libre_habilitado();
  v_hoy date := (pg_catalog.statement_timestamp() at time zone 'America/Lima')::date;
  v_lead crm.leads%rowtype;
  v_sup_nombre text;
  v_turno_supervisor uuid;
  v_turno_nombre text;
  v_origen_nombre text;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador', 'gerencia')
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads'
      using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios'
      using errcode = '22023';
  end if;

  select perfil.nombre_completo into v_sup_nombre
  from crm.equipo equipo
  join public.perfiles perfil on perfil.id = equipo.perfil_id
  where equipo.perfil_id = p_supervisor
    and equipo.rol_crm = 'supervisor'
    and equipo.activo = true
    and perfil.activo = true;

  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads lead
  where lead.id = p_lead
    and lead.activo = true
    and lead.vendedor_id is null
    and lead.asignado_supervisor_id is null
    and lead.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
  for update;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  -- F2.b (b2): el veto pertenece a la persona, no solo a esta fila de lead.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede repartir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- Gerencia puede habilitar el reparto libre para todo Coordinación.
  -- El permiso se verifica en cada llamada; el Superadmin conserva su excepción.
  -- La agenda y la trazabilidad siguen contando el destino real de cada entrega.
  if private.origen_turno_reparto(v_lead.origen) is not null then
    perform pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtextextended('agenda-reparto:' || v_hoy::text, 0)
    );

    select
      agenda.supervisor_id,
      coalesce(destino.alias, perfil.nombre_completo)
    into v_turno_supervisor, v_turno_nombre
    from private.agenda_reparto_diaria agenda
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id = agenda.supervisor_id
    left join public.perfiles perfil
      on perfil.id = agenda.supervisor_id
    where agenda.fecha = v_hoy
      and agenda.origen = private.origen_turno_reparto(v_lead.origen);

    v_origen_nombre := case v_lead.origen
      when 'landing' then 'Landing'
      else 'Formulario'
    end;

    if not found and not v_reparto_libre then
      raise exception 'Antes de repartir %, guarda el turno de hoy en «Coordinación → supervisores»',
        v_origen_nombre
        using errcode = '22023';
    end if;

    if not v_reparto_libre
       and p_supervisor is distinct from v_turno_supervisor then
      raise exception 'Según el turno de hoy, % corresponde a %. El destino no se cambió',
        v_origen_nombre,
        coalesce(v_turno_nombre, 'la supervisora programada')
        using errcode = '22023';
    end if;
  end if;

  update crm.leads
  set asignado_supervisor_id = p_supervisor
  where id = p_lead
    and activo = true
    and vendedor_id is null
    and asignado_supervisor_id is null;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return pg_catalog.jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'excepcion_turno', (
      v_reparto_libre
      and private.origen_turno_reparto(v_lead.origen) is not null
      and p_supervisor is distinct from v_turno_supervisor
    ),
    'repartido_en', pg_catalog.statement_timestamp()
  );
end;
$function$;


CREATE OR REPLACE FUNCTION crm.guardar_agenda_reparto_diaria(p_fecha date, p_landing uuid, p_formulario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_landing_anterior uuid;
  v_formulario_anterior uuid;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede guardar la agenda de reparto'
      using errcode = '42501';
  end if;

  if p_fecha is null or p_landing is null or p_formulario is null then
    raise exception 'Fecha, Landing y Formulario son obligatorios'
      using errcode = '22023';
  end if;

  if p_fecha < v_hoy then
    raise exception 'La agenda de días anteriores es un registro y no puede modificarse'
      using errcode = '22023';
  end if;

  if p_landing = p_formulario then
    raise exception 'Landing y Formulario deben quedar en supervisoras distintas'
      using errcode = '22023';
  end if;

  if (select count(*) from private.agenda_reparto_destinos destino
      join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
      join public.perfiles perfil on perfil.id = destino.supervisor_id
      where destino.supervisor_id in (p_landing, p_formulario)
        and equipo.rol_crm = 'supervisor'
        and equipo.activo = true
        and perfil.activo = true) <> 2 then
    raise exception 'La agenda solo puede usar a Carmen o Jor mientras estén activas'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('agenda-reparto:' || p_fecha::text, 0)
  );

  select supervisor_id into v_landing_anterior
  from private.agenda_reparto_diaria
  where fecha = p_fecha and origen = 'landing'
  for update;

  select supervisor_id into v_formulario_anterior
  from private.agenda_reparto_diaria
  where fecha = p_fecha and origen = 'formulario'
  for update;

  if p_fecha = v_hoy
    and v_landing_anterior is not null
    and v_landing_anterior is distinct from p_landing
    and exists (
      select 1
      from crm.actividades actividad
      join crm.leads lead on lead.id = actividad.lead_id
      where actividad.tipo = 'reasignacion'
        and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
        and lead.origen = 'landing'
        and actividad.creado_en >= (p_fecha::timestamp at time zone 'America/Lima')
        and actividad.creado_en < ((p_fecha + 1)::timestamp at time zone 'America/Lima')
    ) then
    raise exception 'Landing ya tiene derivaciones hoy; su plan quedó registrado'
      using errcode = '22023';
  end if;

  if p_fecha = v_hoy
    and v_formulario_anterior is not null
    and v_formulario_anterior is distinct from p_formulario
    and exists (
      select 1
      from crm.actividades actividad
      join crm.leads lead on lead.id = actividad.lead_id
      where actividad.tipo = 'reasignacion'
        and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
        and private.origen_turno_reparto(lead.origen) = 'formulario'
        and actividad.creado_en >= (p_fecha::timestamp at time zone 'America/Lima')
        and actividad.creado_en < ((p_fecha + 1)::timestamp at time zone 'America/Lima')
    ) then
    raise exception 'Formulario ya tiene derivaciones hoy; su plan quedó registrado'
      using errcode = '22023';
  end if;

  insert into private.agenda_reparto_diaria (
    fecha, origen, supervisor_id, creado_por, actualizado_por
  )
  values
    (p_fecha, 'landing', p_landing, v_actor, v_actor),
    (p_fecha, 'formulario', p_formulario, v_actor, v_actor)
  on conflict (fecha, origen) do update
  set supervisor_id = excluded.supervisor_id,
      actualizado_por = excluded.actualizado_por,
      actualizado_en = statement_timestamp();

  if v_landing_anterior is distinct from p_landing then
    insert into private.agenda_reparto_cambios (
      fecha, origen, supervisor_anterior_id, supervisor_nuevo_id, cambiado_por
    ) values (
      p_fecha, 'landing', v_landing_anterior, p_landing, v_actor
    );
  end if;

  if v_formulario_anterior is distinct from p_formulario then
    insert into private.agenda_reparto_cambios (
      fecha, origen, supervisor_anterior_id, supervisor_nuevo_id, cambiado_por
    ) values (
      p_fecha, 'formulario', v_formulario_anterior, p_formulario, v_actor
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'fecha', p_fecha,
    'guardado_en', statement_timestamp()
  );
end;
$function$;


CREATE OR REPLACE FUNCTION private.leads_por_repartir_implementacion()
 RETURNS TABLE(id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamp with time zone, clasificacion_auto text, comentario text, campania_origen text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := (select auth.uid());
        v_flag boolean := private.resolver_en_puertas_bajo_candado();
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en,
         l.clasificacion_auto,
         -- Comentario REDACTADO (correo/celular/documento fuera) y acotado a
         -- 400 caracteres: Rosa necesita leer la pregunta, no los datos de
         -- contacto. Mantiene la premisa "sin PII de contacto" de C1.
         nullif(left(private.redactar_pii(l.nota), 400), ''),
         l.campania_origen
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                     -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                               -- Ley 29571: nunca listar 'No Insista'
    and (not v_flag or coalesce(inv.no_contactar, false) = false) -- el veto es de la PERSONA (contrato §7.3)
    and not private.persona_vetada(l.id)                     -- F2.b (b2): también por documento exacto (lead suelto)
  order by l.creado_en asc;                                  -- FIFO justo
end;
$function$;


CREATE OR REPLACE FUNCTION crm.leads_por_repartir()
 RETURNS TABLE(id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamp with time zone, clasificacion_auto text, comentario text, campania_origen text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.puede_operar_reparto_crm() then
    raise insufficient_privilege using message = 'Solo Coordinacion o Gerencia puede ver la cola de reparto';
  end if;
  return query select * from private.leads_por_repartir_implementacion();
end;
$function$;


CREATE OR REPLACE FUNCTION crm.agenda_reparto_diaria(p_desde date DEFAULT ((statement_timestamp() AT TIME ZONE 'America/Lima'::text))::date, p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
begin
  if p_desde is null or p_dias is null or p_dias < 1 or p_dias > 14 then
    raise exception 'La agenda requiere una fecha y entre 1 y 14 días'
      using errcode = '22023';
  end if;

  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver la agenda de reparto'
      using errcode = '42501';
  end if;

  with
  dias as materialized (
    select serie::date as fecha
    from pg_catalog.generate_series(
      p_desde::timestamp,
      (p_desde + (p_dias - 1))::timestamp,
      interval '1 day'
    ) as serie
  ),
  destinos as materialized (
    select
      destino.supervisor_id,
      destino.alias,
      destino.orden,
      perfil.nombre_completo
    from private.agenda_reparto_destinos destino
    join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
    join public.perfiles perfil on perfil.id = destino.supervisor_id
    where equipo.rol_crm = 'supervisor'
      and equipo.activo = true
      and perfil.activo = true
  ),
  movimientos as materialized (
    select
      (actividad.creado_en at time zone 'America/Lima')::date as fecha,
      private.origen_turno_reparto(lead.origen) as origen,
      lead.origen as origen_lead,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', '') as supervisor_id,
      perfil.nombre_completo as supervisor_nombre,
      destino.alias as supervisor_alias,
      pg_catalog.count(*)::integer as derivados
    from crm.actividades actividad
    join crm.leads lead on lead.id = actividad.lead_id
    left join public.perfiles perfil
      on perfil.id::text = actividad.metadata ->> 'supervisor_nuevo'
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id::text = actividad.metadata ->> 'supervisor_nuevo'
    where actividad.tipo = 'reasignacion'
      and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
      and actividad.creado_en >= (p_desde::timestamp at time zone 'America/Lima')
      and actividad.creado_en < ((p_desde + p_dias)::timestamp at time zone 'America/Lima')
    group by
      (actividad.creado_en at time zone 'America/Lima')::date,
      private.origen_turno_reparto(lead.origen),
      lead.origen,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', ''),
      perfil.nombre_completo,
      destino.alias
  ),
  -- La foto original por destino se conserva, aunque un destino reciba varios orígenes.
  movimientos_totales as materialized (
    select fecha, origen, supervisor_id, supervisor_nombre, supervisor_alias,
           pg_catalog.sum(derivados)::integer as derivados
    from movimientos
    group by fecha, origen, supervisor_id, supervisor_nombre, supervisor_alias
  ),
  origenes as materialized (
    select movimiento.fecha, movimiento.origen, movimiento.origen_lead,
      pg_catalog.sum(movimiento.derivados)::integer as derivados,
      case when movimiento.origen is not null then coalesce(pg_catalog.sum(movimiento.derivados) filter (
        where movimiento.supervisor_id is distinct from plan.supervisor_id::text
      ), 0)::integer end as fuera_turno,
      pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'supervisor_id', nullif(movimiento.supervisor_id, ''),
        'supervisor_nombre', coalesce(movimiento.supervisor_nombre, 'Supervisor no disponible'),
        'supervisor_alias', movimiento.supervisor_alias,
        'derivados', movimiento.derivados,
        'coincide_turno', coalesce(movimiento.supervisor_id = plan.supervisor_id::text, false)
      ) order by coalesce(movimiento.supervisor_alias, movimiento.supervisor_nombre, movimiento.supervisor_id)) as entregas
    from movimientos movimiento
    left join private.agenda_reparto_diaria plan
      on plan.fecha = movimiento.fecha and plan.origen = movimiento.origen
    group by movimiento.fecha, movimiento.origen, movimiento.origen_lead
  ),
  agenda as materialized (
    select
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias as supervisor_alias,
      destino.nombre_completo as supervisor_nombre,
      coalesce(pg_catalog.sum(movimiento.derivados), 0)::integer as derivados,
      coalesce(
        pg_catalog.sum(movimiento.derivados) filter (
          where movimiento.supervisor_id is distinct from plan.supervisor_id::text
        ),
        0
      )::integer as fuera_turno,
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'supervisor_id', nullif(movimiento.supervisor_id, ''),
            'supervisor_nombre', coalesce(
              movimiento.supervisor_nombre,
              'Supervisor no disponible'
            ),
            'supervisor_alias', movimiento.supervisor_alias,
            'derivados', movimiento.derivados,
            'coincide_turno', coalesce(
              movimiento.supervisor_id = plan.supervisor_id::text,
              false
            )
          ) order by coalesce(
            movimiento.supervisor_alias,
            movimiento.supervisor_nombre,
            movimiento.supervisor_id
          )
        ) filter (where movimiento.derivados is not null),
        '[]'::jsonb
      ) as entregas
    from dias dia
    cross join (values ('landing'::text, 1), ('formulario'::text, 2)) as origen(origen, orden)
    left join private.agenda_reparto_diaria plan
      on plan.fecha = dia.fecha
      and plan.origen = origen.origen
    left join destinos destino
      on destino.supervisor_id = plan.supervisor_id
    left join movimientos_totales movimiento
      on movimiento.fecha = dia.fecha
      and movimiento.origen = origen.origen
    group by
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias,
      destino.nombre_completo
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'fecha_desde', p_desde,
    'reparto_libre', private.reparto_libre_habilitado(),
    'destinos', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'perfil_id', destino.supervisor_id,
          'nombre', destino.nombre_completo,
          'alias', destino.alias
        ) order by destino.orden
      )
      from destinos destino
    ), '[]'::jsonb),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', dia.fecha,
          'origenes', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'origen', detalle.origen_lead,
              'turno', detalle.origen,
              'derivados', detalle.derivados,
              'fuera_turno', detalle.fuera_turno,
              'entregas', detalle.entregas
            ) order by detalle.origen_lead)
            from origenes detalle where detalle.fecha = dia.fecha
          ), '[]'::jsonb),
          'asignaciones', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'origen', fila.origen,
                'supervisor_id', fila.supervisor_id,
                'supervisor_nombre', fila.supervisor_nombre,
                'supervisor_alias', fila.supervisor_alias,
                'derivados', fila.derivados,
                'fuera_turno', fila.fuera_turno,
                'entregas', fila.entregas,
                'origenes', coalesce((
                  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'origen', detalle.origen_lead,
                    'derivados', detalle.derivados,
                    'fuera_turno', detalle.fuera_turno,
                    'entregas', detalle.entregas
                  ) order by detalle.origen_lead)
                  from origenes detalle
                  where detalle.fecha = fila.fecha and detalle.origen = fila.origen
                ), '[]'::jsonb)
              ) order by fila.orden
            )
            from agenda fila
            where fila.fecha = dia.fecha
          ), '[]'::jsonb)
        ) order by dia.fecha
      )
      from dias dia
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;


CREATE OR REPLACE FUNCTION crm.reporte_derivaciones_coordinacion_fn(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_inicio_periodo timestamptz;
  v_fin_periodo timestamptz;
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar el reporte diario de derivaciones'
      using errcode = '42501';
  end if;

  if p_desde is null and p_hasta is null then
    v_desde := v_hoy - 1;
    v_hasta := v_hoy - 1;
  elsif p_desde is null or p_hasta is null then
    raise exception 'Indica ambas fechas del reporte'
      using errcode = '22023';
  else
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;

  if v_desde > v_hasta then
    raise exception 'La fecha inicial no puede ser posterior a la fecha final'
      using errcode = '22023';
  end if;
  if v_hasta > v_hoy then
    raise exception 'El reporte no admite fechas futuras'
      using errcode = '22023';
  end if;
  if v_hasta - v_desde > 365 then
    raise exception 'El rango máximo del reporte es de 366 días'
      using errcode = '22023';
  end if;

  v_inicio_periodo := v_desde::timestamp at time zone 'America/Lima';
  v_fin_periodo := (v_hasta + 1)::timestamp at time zone 'America/Lima';

  with dias as materialized (
    select serie::date as fecha
    from pg_catalog.generate_series(
      v_desde::timestamp,
      v_hasta::timestamp,
      interval '1 day'
    ) as serie
  ),
  episodios_periodo as materialized (
    select
      (asignacion.asignado_en at time zone 'America/Lima')::date as fecha,
      asignacion.analista_id,
      analista_perfil.nombre_completo as analista_nombre,
      asignacion.supervisor_origen_id as supervisor_id,
      supervisor_perfil.nombre_completo as supervisor_nombre,
      private.origen_episodio_lead(asignacion.origen, lead.origen) as origen
    from crm.lead_asignaciones asignacion
    left join crm.leads lead on lead.id = asignacion.lead_id
    join public.perfiles analista_perfil
      on analista_perfil.id = asignacion.analista_id
    join public.perfiles supervisor_perfil
      on supervisor_perfil.id = asignacion.supervisor_origen_id
    where asignacion.asignado_en >= v_inicio_periodo
      and asignacion.asignado_en < v_fin_periodo
      and asignacion.asignado_por = asignacion.supervisor_origen_id
      and asignacion.motivo_apertura in ('asignado', 'reasignado')
      and (
        asignacion.motivo_cierre is distinct from 'parqueado'
        or asignacion.supervisor_destino_id is distinct from asignacion.supervisor_origen_id
      )
  ),
  conteos_analista as materialized (
    select
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      pg_catalog.count(*)::integer as derivados
    from episodios_periodo episodio
    group by
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre
  ),
  conteos_origen as materialized (
    select
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      episodio.origen,
      pg_catalog.count(*)::integer as derivados
    from episodios_periodo episodio
    group by
      episodio.fecha,
      episodio.analista_id,
      episodio.analista_nombre,
      episodio.supervisor_id,
      episodio.supervisor_nombre,
      episodio.origen
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'periodo', pg_catalog.jsonb_build_object(
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', v_hasta - v_desde + 1,
      'zona', 'America/Lima'
    ),
    'total_derivados', (
      select pg_catalog.count(*)::integer from episodios_periodo
    ),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', dia.fecha,
          'total_derivados', coalesce((
            select pg_catalog.sum(conteo.derivados)::integer
            from conteos_analista conteo
            where conteo.fecha = dia.fecha
          ), 0),
          -- Compatibilidad con el consumidor publicado el 2026-09-04.
          'analistas', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'analista_id', conteo.analista_id,
                'analista_nombre', conteo.analista_nombre,
                'supervisor_id', conteo.supervisor_id,
                'supervisor_nombre', conteo.supervisor_nombre,
                'derivados', conteo.derivados
              )
              order by conteo.supervisor_nombre, conteo.analista_nombre,
                conteo.supervisor_id, conteo.analista_id
            )
            from conteos_analista conteo
            where conteo.fecha = dia.fecha
          ), '[]'::jsonb),
          -- Nuevo contrato: el mismo total, abierto por el origen histórico.
          'entregas', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'analista_id', conteo.analista_id,
                'analista_nombre', conteo.analista_nombre,
                'supervisor_id', conteo.supervisor_id,
                'supervisor_nombre', conteo.supervisor_nombre,
                'origen', conteo.origen,
                'derivados', conteo.derivados
              )
              order by conteo.supervisor_nombre, conteo.analista_nombre,
                conteo.origen, conteo.supervisor_id, conteo.analista_id
            )
            from conteos_origen conteo
            where conteo.fecha = dia.fecha
          ), '[]'::jsonb)
        )
        order by dia.fecha desc
      )
      from dias dia
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;


CREATE OR REPLACE FUNCTION crm.rescate_descartes_mes(p_mes date)
 RETURNS TABLE(episodio_id uuid, lead_id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, asesor_id uuid, asesor_nombre text, puede_rescatar boolean, estado text, en_gestion_por text, en_gestion_hasta date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_mes date := pg_catalog.date_trunc('month', p_mes)::date;
begin
  if p_mes is null then
    raise exception 'El mes es obligatorio' using errcode = '22023';
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
    raise exception 'Solo supervisión puede consultar Base para gestión'
      using errcode = '42501';
  end if;

  return query
  select
    la.id as episodio_id,
    l.id as lead_id,
    l.nombre_completo,
    l.distrito,
    private.origen_episodio_lead(la.origen, l.origen),
    la.categoria_interes,
    la.monto_estimado,
    la.moneda,
    la.motivo_descarte_cierre,
    la.resultado_en,
    la.analista_id,
    p_asesor.nombre_completo,
    (
      l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and l.no_contactar is not true
      and g.hasta is null  -- B6: con seguimiento activo del analista no se puede elegir
    ) as puede_rescatar,
    case
      when l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
        then 'pendiente'
      when exists (
        select 1
        from crm.lead_asignaciones la_posterior
        where la_posterior.lead_id = la.lead_id
          and la_posterior.asignado_en > la.resultado_en
      ) then 'rescatado'
      else 'historial'
    end as estado,
    p_gestiona.nombre_completo as en_gestion_por,
    g.hasta as en_gestion_hasta
  from crm.lead_asignaciones la
  join crm.leads l on l.id = la.lead_id
  join public.perfiles p_asesor on p_asesor.id = la.analista_id
  -- B6 (Miguel, 03/10/2026): seguimiento activo SOLO de los episodios que hoy se podrían rescatar (los demás son historial).
  left join lateral (
    select private.base_gestion_en_gestion_hasta(l.id) as hasta
     where l.activo = true
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
  ) g on true
  left join public.perfiles p_gestiona on p_gestiona.id = l.vendedor_id and g.hasta is not null
  where la.resultado = 'descartado'
    and la.resultado_en is not null
    and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
    and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
    and (
      v_rol = 'gerencia'
      or la.analista_id in (
        select private.vendedor_ids_visibles(v_actor)
      )
    )
  order by la.resultado_en desc, la.id desc;
end;
$function$;


CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- El límite se calcula por analista y mes completo de cierre.
  -- Un rango parcial selecciona después los aportes que caen en sus fechas.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- La base es el total de cierres referidos válidos del analista y mes.
  select c.*,
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    (c.fue_referido and not c.anulado) as es_referido,
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id=c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
), con_tope as (
  select m.*,
    count(*) filter (where m.es_referido) over
      (partition by m.analista_id,m.mes_cierre) as total_referidos,
    -- Se conserva el orden vigente: fecha comercial, acreditación y UUID.
    -- Cada cierre conserva su aporte previo; el último admitido puede ser parcial.
    coalesce(sum(m.aporte_numerador) filter (where m.es_referido) over (
      partition by m.analista_id,m.mes_cierre,m.es_referido
      order by m.fecha_numerador,m.registrado_en,m.lead_id
      rows between unbounded preceding and 1 preceding),0) as aporte_anterior_referidos,
    private.tope_referidos_conversion(m.mes_cierre) as tope_pct
  from marcados m
)
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario', 'formulario_3') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'formulario_3', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- Límite agregado exacto: total de cierres referidos válidos × porcentaje.
-- Se calcula sobre el mes completo antes de recortar el rango consultado.
-- Sin redondeo entero: 4 referidos con límite 15 % admiten un máximo de 0,60.
-- Los meses sin tope conservan su ponderación histórica.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
       then least(t.aporte_numerador,
         greatest(0::numeric,
           t.total_referidos * t.tope_pct / 100.0 - t.aporte_anterior_referidos))
       else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Desde octubre, el adicional de renovación cuenta como upgrade.
-- Solo cambia la categoría del aporte: el registro y el capital no se alteran.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.categoria_conversion, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.categoria_conversion = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.categoria_conversion = 'upgrade' then 1 else 0 end
from (
  select o0.*,
    case when o0.tipo = 'renovacion'
      and o0.periodo >= date '2026-10-01'
      and o0.capital_adicional > 0
      then 'upgrade' else o0.tipo end as categoria_conversion,
    row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) = any(p_visibles));
end;
$function$;


CREATE OR REPLACE FUNCTION private.conversion_origen_con_cierre(p_origen text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select p_origen in ('landing', 'formulario', 'formulario_3', 'referido', 'base_cargada')
$function$;


CREATE OR REPLACE FUNCTION private.conversion_origen_base_tope(p_origen text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select p_origen in ('landing', 'formulario', 'formulario_3')
$function$;


CREATE OR REPLACE FUNCTION private.ranking_llegadas_origen_filas(p_ini timestamp with time zone, p_fin timestamp with time zone)
 RETURNS TABLE(vendedor_id uuid, origen text, lead_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select primera.analista_id, l.origen, l.id
  from crm.leads l
  left join lateral (
    select la.analista_id
    from crm.lead_asignaciones la
    where la.lead_id = l.id
    order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
    limit 1
  ) primera on true
  where l.creado_en >= p_ini and l.creado_en < p_fin
    and l.origen in ('landing', 'formulario', 'formulario_3', 'referido', 'oficina')
    and primera.analista_id is not null;
$function$;


CREATE OR REPLACE FUNCTION private.ranking_conversion_origen_mes(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_factor numeric)
 RETURNS TABLE(vendedor_id uuid, origen text, leads integer, cierres integer, conversion_pct numeric, aporte numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with llegadas as (
    select f.vendedor_id, f.origen, count(*)::integer as leads
    from private.ranking_llegadas_origen_filas(p_ini, p_fin) f
    group by f.vendedor_id, f.origen
  ), cierres as (
    -- Los cierres salen del NÚCLEO (conversion_episodios), no de conversion_cierres: así el tope de referidos
    -- (07/10/2026) se aplica en un solo sitio. En un mes con tope el referido aporta lo que le dio el núcleo (1 o 0); en
    -- uno sin tope (agosto, septiembre), el peso p_factor de siempre. `cierres` cuenta TODOS los cierres, también los que
    -- el tope deja sin efecto; `aporte` es lo que suman al numerador.
    select c.analista_id as vendedor_id, c.origen,
      count(*)::integer as cierres,
      sum(case when c.origen = 'referido' then
            case when private.tope_referidos_conversion(
                   date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date) is not null
                 then c.aporte_numerador else p_factor end
          else 1::numeric end) as numerador
    from private.conversion_episodios(
      p_ini, p_fin, p_periodo, true, '{}'::uuid[], p_factor
    ) c
    where c.tipo = 'cierre' and not c.anulado
      and c.origen in ('landing', 'formulario', 'formulario_3', 'referido', 'oficina')
      and c.analista_id is not null
    group by c.analista_id, c.origen
  )
  select coalesce(l.vendedor_id, c.vendedor_id), coalesce(l.origen, c.origen),
    coalesce(l.leads, 0), coalesce(c.cierres, 0),
    case when coalesce(l.leads, 0) > 0
      and (coalesce(l.origen, c.origen) <> 'referido' or p_factor is not null)
      then round(100 * coalesce(c.numerador, 0) / l.leads, 2)
    end,
    coalesce(c.numerador, 0::numeric)
  from llegadas l full join cierres c
    on c.vendedor_id = l.vendedor_id and c.origen = l.origen;
$function$;


CREATE OR REPLACE FUNCTION private.ranking_origen_live(p_periodo date, p_vendedor_id uuid, p_detalles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ini timestamptz := p_periodo::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_periodo_id uuid;
  v_neto_pen numeric := 0;
  v_neto_usd numeric := 0;
  v_ajuste_pen numeric := 0;
  v_ajuste_usd numeric := 0;
  v_bruto_pen numeric := 0;
  v_bruto_usd numeric := 0;
  v_filas jsonb;
begin
  if p_detalles is null or jsonb_typeof(p_detalles) <> 'array' then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  select mp.id into v_periodo_id
  from crm.meta_periodos mp where mp.periodo = p_periodo
  order by mp.revision desc limit 1;

  select
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum((d.valor->>'capital_real')::numeric) filter (where d.valor->>'moneda' = 'USD'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'PEN'), 0),
    coalesce(sum(coalesce((d.valor->>'capital_ajuste')::numeric, 0)) filter (where d.valor->>'moneda' = 'USD'), 0)
  into v_neto_pen, v_neto_usd, v_ajuste_pen, v_ajuste_usd
  from jsonb_array_elements(p_detalles) d(valor);

  with capital_filas as materialized (
    select f.* from private.ranking_capital_origen_filas(v_ini, v_fin, v_periodo_id) f
    where f.vendedor_id = p_vendedor_id
  ), bruto as (
    select coalesce(sum(f.capital) filter (where f.moneda = 'PEN'), 0) as pen,
      coalesce(sum(f.capital) filter (where f.moneda = 'USD'), 0) as usd
    from capital_filas f
  ), capital as materialized (
    select c.origen,
      coalesce(sum(c.capital) filter (where c.moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(c.capital) filter (where c.moneda = 'USD'), 0) as capital_usd,
      count(*)::integer as contratos
    from capital_filas c
    group by c.origen
  ), conversion as materialized (
    select cv.origen, cv.leads, cv.cierres, cv.conversion_pct, cv.aporte
    from private.ranking_conversion_origen_mes(
      v_ini, v_fin, p_periodo, private.peso_referido_conversion(p_periodo)
    ) cv
    where cv.vendedor_id = p_vendedor_id
  ), origenes as (
    select unnest(array['landing','formulario','referido','oficina']) as origen
    union select c.origen from capital c
    union select cv.origen from conversion cv
    union select 'ajuste' where v_ajuste_pen <> 0 or v_ajuste_usd <> 0
  )
  select b.pen, b.usd, coalesce(jsonb_agg(jsonb_build_object(
    'origen', o.origen,
    'capital_pen', case when o.origen = 'ajuste' then -v_ajuste_pen else coalesce(c.capital_pen, 0) end,
    'capital_usd', case when o.origen = 'ajuste' then -v_ajuste_usd else coalesce(c.capital_usd, 0) end,
    'contratos', coalesce(c.contratos, 0),
    'leads', coalesce(cv.leads, 0),
    'cierres', coalesce(cv.cierres, 0),
    'conversion_pct', cv.conversion_pct,
    -- Tope de referidos (07/10/2026): lo que esos cierres SUMAN al numerador (el referido recortado por el tope
    -- aporta menos que sus `cierres`). Coordinación lo lee de la foto de un mes sellado.
    'aporte', coalesce(cv.aporte, 0)
  ) order by case o.origen
    when 'landing' then 1 when 'formulario' then 2 when 'formulario_3' then 3 when 'referido' then 4
    when 'oficina' then 5 when 'cartera' then 6 when 'ajuste' then 99 else 50 end,
    o.origen), '[]'::jsonb) into v_bruto_pen, v_bruto_usd, v_filas
  from bruto b
  cross join origenes o
  left join capital c on c.origen = o.origen
  left join conversion cv on cv.origen = o.origen
  group by b.pen, b.usd;

  if v_bruto_pen <> v_neto_pen + v_ajuste_pen
    or v_bruto_usd <> v_neto_usd + v_ajuste_usd then
    return jsonb_build_object('disponible', false, 'filas', '[]'::jsonb);
  end if;

  return jsonb_build_object('disponible', true, 'filas', v_filas);
end;
$function$;


CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa(p_desde date, p_hasta date)
 RETURNS TABLE(analista_id uuid, nombre text, supervisor_id uuid, supervisor_nombre text, en_nucleo boolean, divisor integer, divisor_formulario integer, divisor_landing integer, numerador numeric, conversion_pct numeric, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cierres_base_cargada integer, divisor_formulario_3 integer, cierres_formulario_3 integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_es_mes boolean;
  v_mes date;
  v_cierre crm.periodos_cerrados%rowtype;
  v_peso_renovacion numeric;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;

  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  -- Mes SELLADO: la foto por persona tal cual se selló. El desglose de cierres
  -- sale de lo que la foto guarda (origenes_ranking.filas y cartera) con los
  -- pesos sellados; el desglose por origen de las llegadas no está en la foto.
  if v_cierre.periodo is not null then
    v_peso_renovacion := coalesce(
      v_cierre.ponderacion_renovacion,
      case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
        then v_cierre.ponderacion_referido else 1 end);
    return query
    with foto as (
      select f.*,
        coalesce(
          coalesce((f.origenes_ranking ->> 'disponible')::boolean, false)
            and f.cartera ? 'conversiones_upgrade' and f.cartera ? 'conversiones_renovacion',
          false
        ) as con_desglose
      from crm.cierre_mes_vendedor f
      where f.periodo = p_desde
    ),
    por_origen as (
      select f.vendedor_id,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario')::integer as formulario,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'formulario_3')::integer as formulario_3,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'landing')::integer as landing,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'referido')::integer as referido,
        sum((o.fila ->> 'aporte')::numeric) filter (where o.fila ->> 'origen' = 'referido') as referido_aporte,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' = 'oficina')::integer as oficina,
        sum((o.fila ->> 'cierres')::integer) filter (where o.fila ->> 'origen' not in ('formulario', 'formulario_3', 'landing', 'referido', 'oficina', 'ajuste'))::integer as otros
      from foto f
      cross join lateral pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(f.origenes_ranking -> 'filas') = 'array'
          then f.origenes_ranking -> 'filas' else '[]'::jsonb end) as o(fila)
      where f.con_desglose
      group by f.vendedor_id
    )
    select f.vendedor_id,
           f.nombre_completo,
           f.supervisor_id,
           f.supervisor_nombre,
           true,
           f.divisor,
           null::integer,
           null::integer,
           f.numerador,
           f.conversion_pct,
           null::numeric,
           null::numeric,
           case when f.con_desglose then coalesce(o.formulario, 0) end,
           case when f.con_desglose then coalesce(o.landing, 0) end,
           case when f.con_desglose then coalesce(o.referido, 0) end,
           -- Con tope (mes sellado desde octubre de 2026) el aporte es el que guardó la foto, no peso × cierres.
           case when f.con_desglose then
             case when v_cierre.tope_referidos_pct is not null then coalesce(o.referido_aporte, 0)
               else coalesce(o.referido, 0) * v_cierre.ponderacion_referido end
           end,
           case when f.con_desglose then coalesce(o.oficina, 0) end,
           case when f.con_desglose then coalesce(o.otros, 0) end,
           -- `conversiones_*` (primera operación ELEGIBLE por cliente y mes) es lo que
           -- suma el numerador; `operaciones_*` cuenta todas y NO sirve aquí.
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_upgrade')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) end,
           case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) * v_peso_renovacion end,
           f.con_desglose,
           -- B11: la foto del cierre no guarda los cierres de base cargada: NULL (no se inventa un 0).
           null::integer,
           null::integer,
           case when f.con_desglose then o.formulario_3 end
    from foto f
    left join por_origen o on o.vendedor_id = f.vendedor_id
    order by f.nombre_completo;
    return;
  end if;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(v_mes);

  return query
  with base as materialized (
    -- LA CIFRA POR PERSONA sale de UNA sola pieza del núcleo según el modo (ver
    -- conversion_divisor_base): la misma que usa Metas para un mes, la de rango
    -- en vivo para cualquier otro tramo.
    select b.* from private.conversion_divisor_base(p_desde, p_hasta) b
  ),
  episodios as materialized (
    -- Mes exacto: p_periodo = ese mes (peso de renovación del período). Rango:
    -- p_periodo nulo, el núcleo pondera cada operación por su propio mes.
    select e.*
    from private.conversion_episodios(v_ini, v_fin, case when v_es_mes then p_desde end, true, null::uuid[], v_factor) e
  ),
  por_origen as materialized (
    -- El mismo aporte que suma el divisor, abierto por el origen del lead. Referido
    -- y alta manual aportan 0 en el núcleo, así que aquí tampoco pesan.
    select e.analista_id,
           (sum(e.aporte_divisor) filter (where e.origen = 'formulario'))::integer as divisor_formulario,
           (sum(e.aporte_divisor) filter (where e.origen = 'formulario_3'))::integer as divisor_formulario_3,
           (sum(e.aporte_divisor) filter (where e.origen = 'landing'))::integer as divisor_landing
    from episodios e
    where e.tipo = 'recibido'
    group by e.analista_id
  ),
  cierres as materialized (
    -- De dónde salen los cierres: los MISMOS episodios que suman el numerador,
    -- agrupados. Formulario, landing y base cargada (B11) aportan 1 por cierre; referido, su peso;
    -- oficina no pesa; upgrade aporta 1 y renovación su propio peso.
    select e.analista_id,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'formulario'))::integer as cierres_formulario,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'formulario_3'))::integer as cierres_formulario_3,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'landing'))::integer as cierres_landing,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'referido'))::integer as cierres_referido,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.origen = 'referido'), 0::numeric) as cierres_referido_aporte,
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'oficina'))::integer as cierres_oficina,
           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.
           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'formulario_3', 'landing', 'referido', 'oficina', 'base_cargada')))::integer as cierres_otros,
           -- B11: contactos de una base cargada por archivo. Pesan 1 y no están en el divisor.
           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'base_cargada'))::integer as cierres_base_cargada,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'upgrade'))::integer as upgrade,
           (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'))::integer as renovacion,
           coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'), 0::numeric) as renovacion_aporte
    from episodios e
    where e.tipo in ('cierre', 'operacion') and not e.anulado
    group by e.analista_id
  ),
  roster as materialized (
    -- El supervisor del MES de `hasta` (roster de metas de ese período), no el
    -- de hoy. Una fila por analista aunque el roster trajera repetidos.
    select distinct on (r.vendedor_id) r.vendedor_id, r.supervisor_id
    from private.roster_conversion_mensual(v_mes, true, null::uuid[]) r
    order by r.vendedor_id, r.supervisor_id nulls last
  )
  select b.analista_id,
         perfil.nombre_completo,
         case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end,
         jefe.nombre_completo,
         b.en_nucleo,
         b.divisor,
         coalesce(o.divisor_formulario, 0),
         coalesce(o.divisor_landing, 0),
         b.numerador,
         b.conversion_pct,
         b.numerador_bruto,
         b.ajuste_pendiente,
         coalesce(c.cierres_formulario, 0),
         coalesce(c.cierres_landing, 0),
         coalesce(c.cierres_referido, 0),
         coalesce(c.cierres_referido_aporte, 0::numeric),
         coalesce(c.cierres_oficina, 0),
         coalesce(c.cierres_otros, 0),
         coalesce(c.upgrade, 0),
         coalesce(c.renovacion, 0),
         coalesce(c.renovacion_aporte, 0::numeric),
         true,
         coalesce(c.cierres_base_cargada, 0),
         coalesce(o.divisor_formulario_3, 0),
         coalesce(c.cierres_formulario_3, 0)
  from base b
  left join por_origen o on o.analista_id is not distinct from b.analista_id
  left join cierres c on c.analista_id is not distinct from b.analista_id
  left join roster r on r.vendedor_id = b.analista_id
  left join crm.equipo equipo on equipo.perfil_id = b.analista_id
  left join public.perfiles perfil on perfil.id = b.analista_id
  left join public.perfiles jefe
    on jefe.id = case when r.vendedor_id is not null then r.supervisor_id else equipo.supervisor_id end
  order by perfil.nombre_completo nulls last;
end;
$function$;


CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa_totales(p_desde date, p_hasta date)
 RETURNS TABLE(sellado boolean, peso_referido numeric, peso_renovacion numeric, divisor integer, numerador numeric, conversion_pct numeric, divisor_formulario integer, divisor_landing integer, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cruza_sellados boolean, sin_analista_presente boolean, sin_analista_divisor integer, sin_analista_numerador numeric, cierres_base_cargada integer, divisor_formulario_3 integer, cierres_formulario_3 integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_cierre crm.periodos_cerrados%rowtype;
  v_es_mes boolean;
  v_mes date;
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  v_es_mes := p_desde = pg_catalog.date_trunc('month', p_desde)::date
    and p_hasta = (pg_catalog.date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_mes := pg_catalog.date_trunc('month', p_hasta)::date;
  if v_es_mes then
    select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_desde;
  end if;

  return query
  with filas as materialized (
    select f.* from private.conversion_divisor_empresa(p_desde, p_hasta) f
  ),
  fuera_foto as materialized (
    -- Mes sellado: la producción congelada fuera del ranking y la que no tuvo
    -- analista se suman al total de la empresa, igual que en la puerta mensual.
    -- Solo un OBJETO cuenta; un JSON null o la ausencia de la clave es ausencia.
    select e.value as fila
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'fuera_ranking') = 'array'
        then v_cierre.cobertura -> 'fuera_ranking' else '[]'::jsonb end
    ) e
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(e.value -> 'conversion') = 'object'
    union all
    select pg_catalog.jsonb_build_object('conversion', v_cierre.cobertura -> 'conversion_sin_analista')
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  ),
  suma as (
    select
      (coalesce(sum(f.divisor), 0)
        + coalesce((select sum((x.fila #>> '{conversion,divisor}')::integer) from fuera_foto x), 0))::integer as divisor,
      (coalesce(sum(f.numerador), 0::numeric)
        + coalesce((select sum((x.fila #>> '{conversion,numerador}')::numeric) from fuera_foto x), 0::numeric)) as numerador,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_formulario), 0)::integer end as divisor_formulario,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_formulario_3), 0)::integer end as divisor_formulario_3,
      case when v_cierre.periodo is null then coalesce(sum(f.divisor_landing), 0)::integer end as divisor_landing,
      case when v_cierre.periodo is null then coalesce(sum(f.numerador_bruto), 0::numeric) end as numerador_bruto,
      case when v_cierre.periodo is null then coalesce(sum(f.ajuste_pendiente), 0::numeric) end as ajuste_pendiente,
      -- Desglose de la empresa: suma de las filas con desglose. En un mes sellado
      -- solo si TODAS las filas de la foto lo traen Y el total no incluye producción
      -- congelada fuera de las filas (fuera_ranking / sin analista), que no tiene
      -- desglose: si no, la suma de partes no sería la del numerador.
      coalesce(bool_and(f.desglose_disponible), v_cierre.periodo is null)
        and (v_cierre.periodo is null or not exists (select 1 from fuera_foto)) as desglose_disponible,
      coalesce(sum(f.cierres_formulario), 0)::integer as cierres_formulario,
      case when v_cierre.periodo is null then coalesce(sum(f.cierres_formulario_3), 0)::integer
        when bool_and(f.cierres_formulario_3 is not null) then sum(f.cierres_formulario_3)::integer
      end as cierres_formulario_3,
      coalesce(sum(f.cierres_landing), 0)::integer as cierres_landing,
      coalesce(sum(f.cierres_referido), 0)::integer as cierres_referido,
      coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
      coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,
      -- B11: un mes sellado no la tiene en la foto (NULL); abierto o rango, la suma de las filas.
      case when v_cierre.periodo is null then coalesce(sum(f.cierres_base_cargada), 0)::integer end as cierres_base_cargada,
      coalesce(sum(f.upgrade), 0)::integer as upgrade,
      coalesce(sum(f.renovacion), 0)::integer as renovacion,
      coalesce(sum(f.renovacion_aporte), 0::numeric) as renovacion_aporte
    from filas f
  ),
  sin_analista as (
    select true as presente, f.divisor, f.numerador
    from filas f
    where v_cierre.periodo is null and f.analista_id is null
    union all
    select true,
      (v_cierre.cobertura #>> '{conversion_sin_analista,divisor}')::integer,
      (v_cierre.cobertura #>> '{conversion_sin_analista,numerador}')::numeric
    where v_cierre.periodo is not null
      and pg_catalog.jsonb_typeof(v_cierre.cobertura -> 'conversion_sin_analista') = 'object'
  )
  select
    v_cierre.periodo is not null,
    coalesce(v_cierre.ponderacion_referido, private.peso_referido_conversion(v_mes)),
    case when v_cierre.periodo is null then private.peso_renovacion_conversion(v_mes)
      else coalesce(v_cierre.ponderacion_renovacion,
        case when v_cierre.cobertura ->> 'modelo_conversion' = 'llegadas_v2'
          then v_cierre.ponderacion_referido else 1 end) end,
    s.divisor,
    s.numerador,
    case when s.divisor > 0 then pg_catalog.round(100.0 * s.numerador / s.divisor, 2) end,
    s.divisor_formulario,
    s.divisor_landing,
    s.numerador_bruto,
    s.ajuste_pendiente,
    case when s.desglose_disponible then s.cierres_formulario end,
    case when s.desglose_disponible then s.cierres_landing end,
    case when s.desglose_disponible then s.cierres_referido end,
    case when s.desglose_disponible then s.cierres_referido_aporte end,
    case when s.desglose_disponible then s.cierres_oficina end,
    case when s.desglose_disponible then s.cierres_otros end,
    case when s.desglose_disponible then s.upgrade end,
    case when s.desglose_disponible then s.renovacion end,
    case when s.desglose_disponible then s.renovacion_aporte end,
    s.desglose_disponible,
    -- Un rango libre que toca meses ya sellados se calcula EN VIVO (como la puerta
    -- de Gerencia) y puede discrepar de la foto: se declara para que la pantalla avise.
    (not v_es_mes) and exists (
      select 1 from crm.periodos_cerrados pc
      where pc.periodo between pg_catalog.date_trunc('month', p_desde)::date and v_mes
    ),
    coalesce((select sa.presente from sin_analista sa limit 1), false),
    (select sa.divisor from sin_analista sa limit 1),
    (select sa.numerador from sin_analista sa limit 1),
    case when s.desglose_disponible then s.cierres_base_cargada end,
    s.divisor_formulario_3,
    case when s.desglose_disponible then s.cierres_formulario_3 end
  from suma s;
end;
$function$;


CREATE OR REPLACE FUNCTION crm.conversion_divisor_coordinacion_fn(p_periodo date DEFAULT NULL::date, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_es_mes boolean;
  v_totales record;
  v_payload jsonb;
begin
  -- 1) Gate primero: un actor denegado recibe 42501 aunque el período sea inválido.
  --    `is not true`: un NULL del gate también deniega.
  if private.puede_operar_reparto_crm() is not true then
    raise exception 'Solo Coordinación o Gerencia activa puede consultar la conversión por analista'
      using errcode = '42501';
  end if;

  -- 2) Validación del período: mes (por defecto el vigente) o rango inclusivo.
  if p_desde is null and p_hasta is null then
    v_desde := coalesce(p_periodo, v_mes_actual);
    if v_desde <> pg_catalog.date_trunc('month', v_desde)::date then
      raise exception 'Periodo invalido: debe ser el primer dia del mes'
        using errcode = '22023';
    end if;
    if v_desde > v_mes_actual then
      raise exception 'Periodo invalido: el mes no puede ser futuro'
        using errcode = '22023';
    end if;
    v_hasta := (v_desde + interval '1 month' - interval '1 day')::date;
  else
    if p_periodo is not null then
      raise exception 'Periodo invalido: indica el mes o el rango, no los dos'
        using errcode = '22023';
    end if;
    if p_desde is null or p_hasta is null then
      raise exception 'Periodo invalido: indica ambas fechas del rango'
        using errcode = '22023';
    end if;
    if p_desde > p_hasta then
      raise exception 'Periodo invalido: la fecha inicial no puede ser posterior a la final'
        using errcode = '22023';
    end if;
    if p_hasta > v_hoy then
      raise exception 'Periodo invalido: el rango no admite fechas futuras'
        using errcode = '22023';
    end if;
    if p_hasta - p_desde > 365 then
      raise exception 'Periodo invalido: el rango maximo es de 366 dias'
        using errcode = '22023';
    end if;
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;
  v_es_mes := v_desde = pg_catalog.date_trunc('month', v_desde)::date
    and v_hasta = (pg_catalog.date_trunc('month', v_desde) + interval '1 month' - interval '1 day')::date;

  -- 3) Delegar: el núcleo decide mes/rango y abierto/sellado; aquí solo se da forma.
  select t.* into strict v_totales from private.conversion_divisor_empresa_totales(v_desde, v_hasta) t;

  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'alcance', 'global',
    'periodo', pg_catalog.jsonb_build_object(
      'modo', case when v_es_mes then 'mes' else 'rango' end,
      'mes', case when v_es_mes then pg_catalog.to_char(v_desde, 'YYYY-MM') end,
      'mes_nombre', case when v_es_mes then private.etiqueta_mes_es(v_desde) end,
      'anio', case when v_es_mes then extract(year from v_desde)::integer end,
      'zona', 'America/Lima',
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', (v_hasta - v_desde) + 1,
      'cruza_meses_sellados', v_totales.cruza_sellados
    ),
    'sellado', v_totales.sellado,
    'peso_referido', v_totales.peso_referido,
    -- Tope de referidos: el de la foto en un mes sellado; en vivo, el del mes del extremo final del rango.
    'tope_referidos_pct', case when v_totales.sellado
      then (select pc.tope_referidos_pct from crm.periodos_cerrados pc where pc.periodo = v_desde)
      else private.tope_referidos_conversion(pg_catalog.date_trunc('month', v_hasta)::date) end,
    'peso_renovacion', v_totales.peso_renovacion,
    'fuente', pg_catalog.jsonb_build_object(
      'divisor', 'private.conversion_neta_por_vendedor',
      'origen', 'private.conversion_episodios',
      'regla', 'una llegada por lead, por su alta original en Lima, en el primer analista asignado',
      -- 'foto' = mes sellado servido de crm.cierre_mes_vendedor; 'mensual' = mes abierto
      -- con la pieza de Metas (bruto, ajuste, neto); 'rango_vivo' = tramo libre calculado
      -- en vivo sin ajustes ni fotos (precedente: crm.metricas_conversiones_equipo_fn).
      'modo', case when v_totales.sellado then 'foto' when v_es_mes then 'mensual' else 'rango_vivo' end
    ),
    'empresa', pg_catalog.jsonb_build_object(
      'divisor', v_totales.divisor,
      'numerador', v_totales.numerador,
      'conversion_pct', v_totales.conversion_pct,
      'divisor_formulario', v_totales.divisor_formulario,
      'divisor_formulario_3', v_totales.divisor_formulario_3,
      'divisor_landing', v_totales.divisor_landing,
      'numerador_bruto', v_totales.numerador_bruto,
      'ajuste_pendiente', v_totales.ajuste_pendiente,
      'desglose_disponible', v_totales.desglose_disponible,
      'cierres', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'formulario', v_totales.cierres_formulario,
        'formulario_3', v_totales.cierres_formulario_3,
        'landing', v_totales.cierres_landing,
        'referido', v_totales.cierres_referido,
        'referido_aporte', v_totales.cierres_referido_aporte,
        'oficina', v_totales.cierres_oficina,
        'otros', v_totales.cierres_otros,
        'base_cargada', v_totales.cierres_base_cargada
      ) end,
      'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
        'upgrade', v_totales.upgrade,
        'renovacion', v_totales.renovacion,
        'renovacion_aporte', v_totales.renovacion_aporte
      ) end
    ),
    'sin_analista', case when v_totales.sin_analista_presente then pg_catalog.jsonb_build_object(
      'divisor', v_totales.sin_analista_divisor,
      'numerador', v_totales.sin_analista_numerador
    ) end,
    'analistas', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'analista_id', f.analista_id,
          'nombre', f.nombre,
          'supervisor_id', f.supervisor_id,
          'supervisor_nombre', f.supervisor_nombre,
          'en_nucleo', f.en_nucleo,
          'divisor', f.divisor,
          'divisor_formulario', f.divisor_formulario,
      'divisor_formulario_3', f.divisor_formulario_3,
          'divisor_landing', f.divisor_landing,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'numerador_bruto', f.numerador_bruto,
          'ajuste_pendiente', f.ajuste_pendiente,
          'desglose_disponible', f.desglose_disponible,
          'cierres', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'formulario', f.cierres_formulario,
        'formulario_3', f.cierres_formulario_3,
            'landing', f.cierres_landing,
            'referido', f.cierres_referido,
            'referido_aporte', f.cierres_referido_aporte,
            'oficina', f.cierres_oficina,
            'otros', f.cierres_otros,
            'base_cargada', f.cierres_base_cargada
          ) end,
          'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
            'upgrade', f.upgrade,
            'renovacion', f.renovacion,
            'renovacion_aporte', f.renovacion_aporte
          ) end
        )
        order by f.nombre nulls last, f.analista_id
      )
      from private.conversion_divisor_empresa(v_desde, v_hasta) f
      where f.analista_id is not null
    ), '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;


CREATE OR REPLACE FUNCTION crm.importar_lead_fn(p_fila jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_id         uuid := pg_catalog.gen_random_uuid();
  v_nombre     text := nullif(pg_catalog.btrim(p_fila->>'nombre_completo'), '');
  v_telefono   text := nullif(pg_catalog.btrim(p_fila->>'telefono'), '');
  v_alt        text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo'), '');
  v_alt_crudo  text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo_crudo'), '');
  v_correo     text := nullif(pg_catalog.btrim(p_fila->>'correo'), '');
  v_dni        text := nullif(pg_catalog.btrim(p_fila->>'dni'), '');
  v_genero     text := nullif(pg_catalog.btrim(p_fila->>'genero'), '');
  v_fecha      date;
  v_distrito   text := nullif(pg_catalog.btrim(p_fila->>'distrito'), '');
  v_campania   text;
  v_origen     text := nullif(pg_catalog.btrim(p_fila->>'origen'), '');
  v_monto      numeric;
  v_moneda     text := nullif(pg_catalog.btrim(p_fila->>'moneda'), '');
  v_categoria  text := nullif(pg_catalog.btrim(p_fila->>'categoria_interes'), '');
  v_nota       text := nullif(pg_catalog.btrim(p_fila->>'nota'), '');
  v_cons_en    timestamptz;
  v_cons_fuente text := nullif(pg_catalog.btrim(p_fila->>'consentimiento_fuente'), '');
  v_vendedor   uuid;
  v_detalle    text;
  v_constraint text;
  v_veredicto  jsonb;
  v_resultado  text;
  v_lead       uuid;
  v_reingreso  jsonb;
  v_datos      jsonb;
  v_prev       uuid;
  v_perfil     uuid;      -- F2.b [D-20]
  v_lead_vivo  uuid;      -- F2.b [D-20]
  v_solicitud  jsonb;     -- F2.b [D-20]
begin
  -- F2.b [D-4]: solo el importador (service_role, sin sesión de usuario), la misma regla que registrar_reingreso_lead_fn.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) usa esta puerta' using errcode = '42501';
  end if;
  -- Defensa en profundidad (auditor N5): esta puerta nunca corre como operación privilegiada, venga como venga la sesión.
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  if p_fila is null or pg_catalog.jsonb_typeof(p_fila) <> 'object' then
    raise exception 'Fila invalida' using errcode = '22023';
  end if;
  -- Los casts van DESPUÉS de la autorización (Codex v3 #6): un payload malformado no cambia el 42501 por un 22xxx.
  v_campania := private.normalizar_campania_origen(p_fila->'campania_origen', v_origen);
  v_fecha    := nullif(pg_catalog.btrim(p_fila->>'fecha_nacimiento'), '')::date;
  v_monto    := nullif(pg_catalog.btrim(p_fila->>'monto_estimado'), '')::numeric;
  v_cons_en  := nullif(pg_catalog.btrim(p_fila->>'consentimiento_en'), '')::timestamptz;
  v_vendedor := nullif(pg_catalog.btrim(p_fila->>'vendedor_id'), '')::uuid;
  -- La puerta NO valida el formato: lo hace la fila al nacer (trigger 00: teléfono y DNI → 22023 con el mismo texto de
  -- hoy; NOT NULL y CHECKs de la tabla), con la MISMA prioridad que el INSERT directo —el veto de la persona (000) va
  -- antes que el formato— (Codex v4 #9). El teléfono viaja crudo, como lo manda el edge; lo normaliza el trigger de la tabla.

  -- Orden TOTAL de candados (b1/D-13, el de crm.crear_lead_si_disponible): documento → persona → contactos → fila.
  -- El INSERT directo de hoy YA los toma en ese orden (triggers BEFORE 000 → 00, antes de tocar tupla e índice). Aquí
  -- se toman explícitos SOLO los de identidad (documento → persona; apagada la bandera no toman nada), antes del
  -- sub-bloque para que sobrevivan a su rollback y el reingreso corra con la persona retenida. Los de CONTACTO los toma
  -- el trigger 00 del INSERT, DESPUÉS del veto de la persona (000), exactamente como el INSERT directo: una persona
  -- vetada recibe su «no insistir» sin esperar por un teléfono retenido (Codex v3 #3). D-4 no cambia el orden: lo que
  -- aporta es un veredicto único sin parsear SQLSTATE y el reingreso en la misma transacción.
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);

  -- El CONTRATO del importador es el de la fila al nacer sin sesión humana (trigger de disponibilidad: «un escritor
  -- interno se serializa pero conserva su contrato especializado»): NO se consulta la disponibilidad comercial
  -- (enfriamiento, ficha de cliente, «no insistir» de un lead viejo) —el cliente que vuelve por la hoja es el mejor
  -- lead posible—; sí mandan el índice único de teléfono VIVO (duplicado) y, con la identidad encendida, los triggers
  -- de nacimiento: 000 (la persona vetada → P0429) y zz (la persona ya tiene lead o está en conversión → P0481 por
  -- identidad). Por eso la puerta hace el MISMO INSERT (payload exacto del edge: sin sesión, cola global, alta_manual
  -- por defecto) y convierte esos tres resultados en un veredicto en vez de una excepción.
  begin
    insert into crm.leads (
      id, nombre_completo, telefono, telefono_alternativo, telefono_alternativo_crudo, correo, dni, genero,
      fecha_nacimiento, distrito, origen, campania_origen, etapa, monto_estimado, moneda, categoria_interes, nota, no_contactar,
      consentimiento_en, consentimiento_fuente, vendedor_id, asignado_supervisor_id, activo, creado_por
    ) values (
      v_id, v_nombre, v_telefono, v_alt, v_alt_crudo, v_correo, v_dni, v_genero,
      v_fecha, v_distrito, v_origen, v_campania, 'nuevo', v_monto, v_moneda, v_categoria, v_nota, false,
      v_cons_en, v_cons_fuente, v_vendedor, null, true, null
    );
    return pg_catalog.jsonb_build_object('resultado', 'importado', 'lead_id', v_id, 'veredicto', null, 'reingreso', null);
  exception
    when unique_violation then
      -- uq_leads_telefono_vivo (o uq_leads_dni_vivo): ya hay un lead VIVO con ese contacto → DUPLICADO (hoy: 23505).
      -- Se devuelve el NOMBRE del índice, no el DETAIL (que lleva el teléfono o el DNI en claro; auditor N1).
      get stacked diagnostics v_constraint = constraint_name;
      v_veredicto := pg_catalog.jsonb_build_object('estado', 'duplicado', 'indice', coalesce(v_constraint, 'desconocido'));
      v_resultado := 'duplicado';
    when sqlstate 'P0481' then
      -- «Contacto no disponible» con el veredicto en DETAIL (hoy lo parsea el edge): ya_es_cliente por identidad
      -- (con lead_id) o en conversión → ya_cliente; cualquier otro → rechazado.
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := v_detalle::jsonb;
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_disponible', 'detalle', pg_catalog.left(coalesce(v_detalle, ''), 200));
      end;
      v_resultado := case when v_veredicto->>'estado' = 'ya_es_cliente' and v_veredicto->>'via' = 'identidad' then 'ya_cliente' else 'rechazado' end;
    when sqlstate 'P0429' then
      -- La persona tiene «No insistir» (trigger 000, identidad encendida) → RECHAZADO (hoy: P0429).
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := coalesce(nullif(v_detalle, '')::jsonb, pg_catalog.jsonb_build_object('estado', 'no_contactar'));
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_contactar');
      end;
      v_resultado := 'rechazado';
  end;

  v_lead := nullif(v_veredicto->>'lead_id', '')::uuid;
  -- F2.b [D-20] (auditor A1): `private.leads_de_personas` devuelve enlace ∪ puente ∪ sueltos, así que `v_lead`
  -- también trae leads CONVERTIDOS y descartados. Anotar el reingreso en uno cerrado es escribir donde nadie mira.
  -- La bifurcación va por el lead VIVO: solo ése es un trabajo que alguien tiene en su bandeja.
  -- Y no basta con mirar el lead que trae el veredicto: si ése está cerrado pero la persona conserva OTRO vivo, crear
  -- una tarea duplicaría el trabajo (Codex). Se busca cualquier lead vivo suyo, prefiriendo el del veredicto.
  select l.id into v_lead_vivo
    from crm.leads l
   where l.activo
     and l.etapa not in ('convertido', 'descartado')
     and (l.id = v_lead
          or (nullif(pg_catalog.btrim(coalesce(v_dni, '')), '') is not null and l.dni = v_dni)
          or (l.inversionista_id is not null
              and l.inversionista_id = private.inversionista_por_documento('DNI', v_dni)))
   order by (l.id = v_lead) desc, l.creado_en desc
   limit 1;
  if v_resultado = 'ya_cliente' and v_lead_vivo is not null then
    -- El reingreso en la MISMA transacción (hoy el edge lo pedía aparte tras leer el error). Si fallara de forma
    -- DEFINITIVA, la fila sigue siendo «ya cliente» y el edge lo dice en la hoja, como hoy.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- Ausente no añade una clave nula: se conserva la igualdad de solicitudes antiguas.
    if v_campania is not null then
      v_datos := v_datos || pg_catalog.jsonb_build_object('campania_origen', v_campania);
    end if;
    -- IDEMPOTENCIA (Codex v4 #7, v5 #3): si la hoja reenvía la MISMA fila (perdió la confirmación HTTP o el lote falló
    -- después), el reingreso ya anotado vale: no se escribe una segunda nota. Misma persona, mismo origen y los mismos
    -- DATOS —sin el número de fila, que cambia si alguien inserta una fila encima— en los últimos 7 días (una caída larga
    -- del CRM tampoco la burla). Es lo que registrar_reingreso_lead_fn guarda en metadata.datos.
    select a.id into v_prev
      from crm.actividades a
     where a.lead_id = v_lead_vivo
       and a.metadata->>'evento' = 'reingreso'
       and a.metadata->>'origen' = 'hoja'
       and private.datos_solicitud_comparables(a.metadata->'datos') - 'fila' = private.datos_solicitud_comparables(v_datos) - 'fila'
       and a.creado_en > pg_catalog.now() - interval '7 days'
     order by a.creado_en desc
     limit 1;
    if v_prev is not null then
      v_reingreso := pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_prev, 'repetido', true);
    else
      begin
        v_reingreso := crm.registrar_reingreso_lead_fn(v_lead_vivo, 'hoja', v_datos);
      exception when others then
        -- Solo los errores DE NEGOCIO quedan anotados como definitivos en la respuesta (datos 22xxx, integridad 23xxx y
        -- los P0xxx que levantan nuestras funciones: lead inexistente, origen inválido, identidad apagada). Cualquier
        -- otro —transacción, recursos, candado, cancelación, E/S, límites (54), internos, configuración— sube entero: el
        -- edge lo trata como temporal y la hoja reintenta la fila (auditor M4; Codex v4 #8 y v5 #4).
        if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
          raise;
        end if;
        v_reingreso := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
      end;
    end if;
  elsif v_resultado = 'ya_cliente' then
    -- F2.b [D-20]: es cliente y NO conserva lead vivo (el caso de 407 de los 424 clientes activos en producción al
    -- 06/09). Sin esta rama la solicitud se perdía: la hoja la daba por cerrada y en el CRM no quedaba nada. Se deja
    -- la huella donde el analista mira: nota en la ficha del cliente y tarea de llamada para el responsable de su
    -- cartera. Nunca las dos vías a la vez: si hubiera lead vivo, la rama de arriba ya anotó el reingreso.
    v_datos := pg_catalog.jsonb_build_object(
      'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
      'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
      'interes', v_categoria, 'nota', v_nota);
    -- Ausente no añade una clave nula: se conserva la igualdad de solicitudes antiguas.
    if v_campania is not null then
      v_datos := v_datos || pg_catalog.jsonb_build_object('campania_origen', v_campania);
    end if;
    -- La persona ya está reconocida (el veredicto lo dice), así que su ficha de cliente sale de la identidad. El
    -- respaldo por documento exacto cubre a un cliente cuya identidad todavía no lleva el perfil enlazado.
    select i.perfil_id into v_perfil
      from crm.inversionistas i
     where i.id = private.inversionista_por_documento('DNI', v_dni) and i.perfil_id is not null;
    if v_perfil is null and nullif(pg_catalog.btrim(coalesce(v_dni, '')), '') is not null then
      select p.id into v_perfil
        from public.perfiles p
       where p.rol = 'cliente' and p.activo
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' ||
              pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g')))
             = ('DNI:' || pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_dni, ''), '[^A-Za-z0-9]', '', 'g')))
       limit 1;
    end if;
    if v_perfil is not null then
      begin
        v_solicitud := private.registrar_solicitud_cliente_fn(v_perfil, 'hoja', v_datos);
      exception when others then
        -- Mismo criterio que el reingreso: solo los errores DE NEGOCIO se anotan como definitivos; cualquier otro
        -- sube entero para que la hoja reintente la fila.
        if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
          raise;
        end if;
        v_solicitud := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
      end;
    else
      v_solicitud := pg_catalog.jsonb_build_object('ok', false, 'error', 'no se pudo ubicar la ficha del cliente');
    end if;
  end if;

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso)
      || case when v_solicitud is null then '{}'::jsonb else pg_catalog.jsonb_build_object('solicitud', v_solicitud) end;
end;
$function$;


CREATE OR REPLACE FUNCTION private.registrar_solicitud_cliente_fn(p_perfil uuid, p_origen text, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_cliente   public.perfiles%rowtype;
  v_huella    text;
  v_detalle   text;
  v_prev_act  uuid;
  v_act       uuid;
  v_tarea     uuid;
  v_sin_asesor boolean := false;
  v_motivo    text;
  v_dest      uuid;      -- a nombre de quién queda la nota (la tabla exige responsable)
begin
  -- F2.b [D-20]. Solo el importador, la misma regla que registrar_reingreso_lead_fn: nunca una sesión humana.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) registra solicitudes de cliente' using errcode = '42501';
  end if;
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada: la solicitud no se registra' using errcode = 'P0409';
  end if;
  if p_origen is null or p_origen not in ('hoja', 'landing', 'web') then
    raise exception 'Origen inválido' using errcode = '22023';
  end if;
  select * into v_cliente from public.perfiles p where p.id = p_perfil and p.rol = 'cliente';
  if not found then
    raise exception 'Cliente inexistente' using errcode = 'P0002';
  end if;
  if not v_cliente.activo then
    raise exception 'Cliente inactivo: la solicitud no se registra' using errcode = 'P0409';
  end if;
  -- Auditor D-20 #A2: los dos triggers de veto se EXIMEN cuando no hay sesión (auth.uid() null), que es justo el caso
  -- del importador. La ley 29571 no puede depender de un razonamiento sobre el orden de los triggers: se comprueba aquí.
  if private.persona_vetada_perfil(p_perfil) then
    return pg_catalog.jsonb_build_object('ok', false, 'vetado', true, 'sin_tarea', true,
      'error', 'La persona tiene la restricción «No insistir»: no se registra seguimiento');
  end if;
  -- Auditor #M6: la idempotencia se sostiene sola. Hoy el importador ya serializa por persona, pero el ayudante no
  -- puede depender de quién lo llame.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('solicitud_cliente:' || p_perfil::text));

  -- Huella de la solicitud SIN el número de fila (que cambia si alguien inserta una fila encima), igual que el
  -- reingreso: si la hoja reenvía la misma fila porque perdió la confirmación, no se duplica ni la nota ni la tarea.
  v_huella := pg_catalog.md5(coalesce((private.datos_solicitud_comparables(p_datos) - 'fila')::text, ''));
  v_detalle := 'Pidió información por la web'
    -- Antes de la nota larga; la huella sigue al final y conserva la campaña.
    || coalesce(' · campaña: ' || nullif(p_datos->>'campania_origen', ''), '')
    || coalesce(' · interés: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'interes', '')), ''), '')
    || coalesce(' · capital: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'capital', '')), ''), '')
    || coalesce(' ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'moneda', '')), ''), '')
    || coalesce(' · distrito: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'distrito', '')), ''), '')
    || coalesce(' · canal: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'canal', '')), ''), '')
    || coalesce(' · teléfono: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'telefono', '')), ''), '')
    || coalesce(' · nota: ' || nullif(pg_catalog.btrim(coalesce(p_datos->>'nota', '')), ''), '');
  -- `detalle` y `nota` topan en 2000 caracteres, pero la nota del formulario no tiene límite: se recorta el cuerpo y
  -- la huella se añade DESPUÉS, porque recortar por el final la destruiría y con ella la idempotencia (auditor #M1).
  v_detalle := pg_catalog.left(v_detalle, 1900) || ' · Ref: ' || v_huella;

  select a.id into v_prev_act
    from crm.actividades_cliente a
   where a.cliente_id = p_perfil
     and a.tipo = 'nota'
     -- La comparación va contra la COLA, no contra el interior (Codex): el sufijo « · Ref: <huella>» lo añadimos
     -- nosotros SIEMPRE al final, mientras que la nota del visitante queda antes y recortada. Con `strpos`, un texto
     -- del formulario que contuviera «Ref: <huella>» podía hacer pasar por repetida una solicitud jamás registrada.
     and pg_catalog.right(coalesce(a.detalle, ''), pg_catalog.length(' · Ref: ' || v_huella)) = ' · Ref: ' || v_huella
     and a.creado_por is null   -- auditor #M2: solo cuenta la nota que escribió el importador, no una copiada a mano
     and a.creado_en > pg_catalog.now() - interval '7 days'
   order by a.creado_en desc
   limit 1;
  if v_prev_act is not null then
    return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_prev_act, 'repetido', true);
  end if;

  -- `actividades_cliente` exige responsable en toda nota (CHECK) y que ese responsable esté en el equipo (FK). El
  -- analista de la cartera es el destino natural; si el perfil no lo tiene, se usa el responsable VIVO de su identidad
  -- (423 de los 424 clientes activos lo tienen). Sin ninguno de los dos no hay a quién atribuirla: se dice y ya.
  v_dest := v_cliente.asesor_perfil_id;
  if v_dest is null or not exists (select 1 from crm.equipo e where e.perfil_id = v_dest and e.activo and e.rol_crm in ('vendedor','supervisor')) then
    select r.responsable_id into v_dest
      from crm.inversionista_responsables r
      join crm.inversionistas i on i.id = r.inversionista_id
     where i.perfil_id = p_perfil and r.hasta is null
       and exists (select 1 from crm.equipo e where e.perfil_id = r.responsable_id and e.activo and e.rol_crm in ('vendedor','supervisor'))
     order by r.desde desc
     limit 1;
  end if;
  if v_dest is null then
    return pg_catalog.jsonb_build_object('ok', false, 'sin_ficha', true, 'sin_tarea', true,
      'error', 'el cliente no tiene analista ni responsable activo: nadie a quien atribuir la solicitud');
  end if;

  insert into crm.actividades_cliente (cliente_id, vendedor_id, tipo, detalle, creado_por)
  values (p_perfil, v_dest, 'nota', v_detalle, null)
  returning id into v_act;

  -- La TAREA es lo que hace que alguien la trabaje. El trigger de la tabla resuelve el analista desde la cartera del
  -- cliente y rechaza si no lo tiene o si no está activo en el CRM; eso NO puede tumbar la importación de la fila, así
  -- que se anota como «sin analista» y la nota queda igual en la ficha para que Gerencia lo vea.
  begin
    insert into crm.tareas (perfil_id, tipo, titulo, nota, vence_en, estado, creado_por)
    values (p_perfil, 'llamada', 'Pidió información por la web', v_detalle,
            pg_catalog.now() + interval '1 day', 'pendiente', null)
    returning id into v_tarea;
  exception when others then
    if pg_catalog.left(sqlstate, 2) not in ('22', '23', 'P0') then
      raise;
    end if;
    v_sin_asesor := true;
    v_motivo := sqlstate || ': ' || pg_catalog.left(sqlerrm, 120);
  end;

  return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_act, 'tarea_id', v_tarea,
                                       'repetido', false, 'sin_tarea', v_sin_asesor, 'motivo', v_motivo);
end;
$function$;


revoke all on function private.leads_before_insert() from public, anon, authenticated, service_role;

comment on function private.leads_before_insert() is 'Alta de un lead (BEFORE INSERT): exige un canal concreto (sin nuevos Otro; base_cargada solo con la válvula de la carga de bases, B7 04/10/2026, la reserva vive en private.trg_leads_base_cargada_solo_puerta) y, sin crm.op_privilegiada, impide nacer en estado terminal —salvo el contacto de base cargada que nace dormido (B8, private.bases_carga_nace_dormido)— y enlazar perfil, contrato o conversión. DEFINER, search_path crm, public. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) from public, anon, authenticated, service_role;

grant execute on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) to authenticated;

comment on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) is 'Alta manual atomica con disponibilidad e idempotencia. Canales activos: referido, landing, formulario y oficina. Otro e historicos no admitidos en nuevas altas. Referido conserva restriccion de vendedor a su propio nombre. LANDING/FORMULARIO manuales conservan su politica del divisor. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text) from public, anon, authenticated, service_role;

grant execute on function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text) to authenticated;

comment on function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text) is 'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista), gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto) y potencial (p_potencial: estrella, tibio, frio o sin_marca; con la bandera potencial_lead apagada se rechaza con 55000). Listado y resumen salen de la misma base; resumen.potencial cuenta cada nivel con los demas filtros puestos, antes de aplicar p_potencial; solo viaja con la bandera encendida y para quien tiene ambito de filas (global o con analistas visibles), y cuenta solo las marcas que el actor puede ver por la RLS de crm.leads (una marca que no puede ver cuenta como sin_marca). F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.normalizar_campania_origen(jsonb,text) from public, anon, authenticated, service_role;

comment on function private.normalizar_campania_origen(jsonb,text) is 'F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.repartir_lead_implementacion(uuid,uuid) from public, anon, authenticated, service_role;

comment on function private.repartir_lead_implementacion(uuid,uuid) is 'Implementación privada del reparto. Conserva veto de persona y CAS; Coordinación debe respetar la agenda Lima para Landing/Formulario y el Superadmin activo puede registrar una excepción visible en el reporte. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.guardar_agenda_reparto_diaria(date,uuid,uuid) from public, anon, authenticated, service_role;

grant execute on function crm.guardar_agenda_reparto_diaria(date,uuid,uuid) to authenticated;

comment on function crm.guardar_agenda_reparto_diaria(date,uuid,uuid) is 'Guarda el turno diario Landing/Formulario para Carmen y Jor. Permite el primer registro de hoy aun si hubo reparto y bloquea reescribir un carril previamente guardado con evidencia real. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.leads_por_repartir_implementacion() from public, anon, authenticated, service_role;

comment on function private.leads_por_repartir_implementacion() is 'Cola de leads nuevos sin dueño que el coordinador reparte o descarta. Sin PII de contacto: el comentario del cliente viaja REDACTADO (correo/celular/documento ocultos) y trunco a 400. Incluye clasificacion_auto (marca del código, nunca cierra). Excluye no_contactar=true (Ley 29571). FIFO. Solo coordinador/gerencia activos. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.leads_por_repartir() from public, anon, authenticated, service_role;

grant execute on function crm.leads_por_repartir() to authenticated;

comment on function crm.leads_por_repartir() is 'Frontera C1 endurecida: conserva la proyeccion historica y exige rol CRM efectivo Coordinacion o Gerencia. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.agenda_reparto_diaria(date,integer) from public, anon, authenticated, service_role;

grant execute on function crm.agenda_reparto_diaria(date,integer) to authenticated;

comment on function crm.agenda_reparto_diaria(date,integer) is 'Primera etapa del reparto: plan Landing/Formulario y todas las entregas reales de Coordinación desglosadas por supervisor, con total fuera de turno. Sin PII; solo Coordinación o Gerencia. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.reporte_derivaciones_coordinacion_fn(date,date) from public, anon, authenticated, service_role;

grant execute on function crm.reporte_derivaciones_coordinacion_fn(date,date) to authenticated;

comment on function crm.reporte_derivaciones_coordinacion_fn(date,date) is 'Reporte diario agregado sin PII de leads; incluye nombres e identificadores de colaboradores y el origen histórico. Fechas inclusivas de America/Lima; solo Coordinación o Gerencia activas. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.rescate_descartes_mes(date) from public, anon, authenticated, service_role;

grant execute on function crm.rescate_descartes_mes(date) to authenticated;

comment on function crm.rescate_descartes_mes(date) is 'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead. B6 (03/10/2026): en_gestion_por y en_gestion_hasta marcan el seguimiento activo del analista (intento de la base hace 7 días o menos, o rellamada vigente de ese ciclo); mientras dure, puede_rescatar = false y la pantalla lo pinta en gris. estado no cambia (el bundle viejo valida una lista cerrada). F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric) from public, anon, authenticated, service_role;

comment on function private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric) is 'Núcleo único: desde octubre 2026 el aporte conjunto de referidos tiene límite exacto del porcentaje configurado sobre sus propios cierres válidos por analista/mes. Admisión cronológica, último aporte parcial, exceso cero. Mes completo antes del filtro de rango. Divisor y cartera sin cambios. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.conversion_origen_con_cierre(text) from public, anon, authenticated, service_role;

comment on function private.conversion_origen_con_cierre(text) is 'B11 (05/10/2026): UNA definición de qué orígenes cuentan un cierre en la conversión: landing, formulario, referido y base_cargada (contactos de una base cargada por archivo: pesan 1 y NO entran al divisor, como la regla cerrada del registro manual). Oficina y los demás orígenes no cuentan. NULL con origen NULL (como el `in` al que reemplaza). El divisor no la usa: lo define private.conversion_episodios (solo landing y formulario sin alta manual). Usada por private.conversion_cierres (peso 1 tras la rama del referido), private.registrar_ajuste_si_mes_cerrado, private.conversion_mensual_por_vendedor, crm.metricas_conversiones_equipo_fn, private.metricas_conversiones_implementacion, private.metricas_distribucion_leads_v3_core y la sonda de crm.conversion_mensual_sin_cartera_fn. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.conversion_origen_base_tope(text) from public, anon, authenticated, service_role;

comment on function private.conversion_origen_base_tope(text) is 'Tope de referidos (Miguel, 07/10/2026): UNA definición de qué orígenes de lead forman la BASE del tope, es decir, los leads que el sistema asigna al analista: landing y formulario. Quedan fuera referido, base_cargada (la carga el supervisor) y los orígenes que no cierran en conversión (oficina, otro, web, campania, whatsapp). NULL con origen NULL. Esta función mira solo el ORIGEN: el registro manual (alta_manual) lo excluye private.conversion_episodios al armar la base. Usada por private.conversion_episodios. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone) from public, anon, authenticated, service_role;

comment on function private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone) is 'Filas base del desglose de conversión por origen: una llegada por lead, atribuida al primer analista. No agrega ni publica métricas; EXECUTE solo postgres. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric) from public, anon, authenticated, service_role;

comment on function private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric) is 'Resultados por origen de un mes: llegadas, cierres y conversión por analista y origen, más `aporte` (lo que esos cierres suman al numerador; con el tope de referidos de octubre de 2026 un referido recortado aporta menos que sus cierres). Los cierres salen del núcleo (private.conversion_episodios). F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.ranking_origen_live(date,uuid,jsonb) from public, anon, authenticated, service_role;

comment on function private.ranking_origen_live(date,uuid,jsonb) is 'F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.conversion_divisor_empresa(date,date) from public, anon, authenticated, service_role;

comment on function private.conversion_divisor_empresa(date,date) is 'Núcleo (30/09/2026, v2 con desglose y rango): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Un mes calendario exacto usa la pieza mensual neta (Metas) y, si está sellado, la foto (crm.cierre_mes_vendedor: origenes_ranking y cartera) sin recalcular; cualquier otro rango se calcula en vivo (bruto = neto). Agrupa los episodios de private.conversion_episodios: llegadas por origen (divisor), cierres por origen (formulario, landing, referido con su aporte, oficina sin peso) y cartera (upgrade, renovación con su aporte). numerador_bruto = partes. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API. B11 (05/10/2026): cierres_base_cargada (al final) = cierres de contactos de una base cargada por archivo, que pesan 1 y no están en el divisor; NULL en un mes sellado (la foto no los guarda); cierres_otros ya no los incluye. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.conversion_divisor_empresa_totales(date,date) from public, anon, authenticated, service_role;

comment on function private.conversion_divisor_empresa_totales(date,date) is 'Núcleo (30/09/2026, v2 con desglose y rango): total de la empresa y producción sin analista para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Mes abierto o rango: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos), la misma suma que la puerta mensual oficial; el desglose solo se sirve si todas las filas de la foto lo traen. Nunca recalcula un mes sellado. Sin autorización dentro y sin ejecutores de la API. B11 (05/10/2026): cierres_base_cargada (al final) = suma de las filas en un mes abierto o rango; NULL en un mes sellado. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.conversion_divisor_coordinacion_fn(date,date,date) from public, anon, authenticated, service_role;

grant execute on function crm.conversion_divisor_coordinacion_fn(date,date,date) to authenticated;

comment on function crm.conversion_divisor_coordinacion_fn(date,date,date) is 'Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads. B11 (05/10/2026): cierres.base_cargada = cierres de contactos de una base cargada por archivo (pesan 1, fuera del divisor; null en un mes sellado); otros ya no los incluye. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function crm.importar_lead_fn(jsonb) from public, anon, authenticated, service_role;

grant execute on function crm.importar_lead_fn(jsonb) to service_role;

comment on function crm.importar_lead_fn(jsonb) is 'F2.b [D-4]: puerta SQL del importador (solo service_role). Una fila de la hoja → veredicto {resultado, lead_id, veredicto, reingreso}; el MISMO INSERT del edge bajo el orden total de candados, con el reingreso en la misma transacción. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

revoke all on function private.registrar_solicitud_cliente_fn(uuid,text,jsonb) from public, anon, authenticated, service_role;

comment on function private.registrar_solicitud_cliente_fn(uuid,text,jsonb) is 'F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

do $censo$ declare v_firma text; v_antes text; v_huella text; begin

  if (select huella from private.analitica_leads_citas_exenciones where objeto='crm.agenda_reparto_diaria(date,integer)') is distinct from '09a8ccb1daca70fb7d63ef96c3d0047c' then
    raise exception 'Preflight censo F3: declaración cambió %', 'crm.agenda_reparto_diaria(date,integer)';
  end if;
  select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid='crm.agenda_reparto_diaria(date,integer)'::regprocedure;
  update private.analitica_leads_citas_exenciones set huella=v_huella where objeto='crm.agenda_reparto_diaria(date,integer)';

  if (select huella from private.analitica_leads_citas_exenciones where objeto='crm.guardar_agenda_reparto_diaria(date,uuid,uuid)') is distinct from '4f2a7712595f80dccac1b509bdfd317d' then
    raise exception 'Preflight censo F3: declaración cambió %', 'crm.guardar_agenda_reparto_diaria(date,uuid,uuid)';
  end if;
  select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid='crm.guardar_agenda_reparto_diaria(date,uuid,uuid)'::regprocedure;
  update private.analitica_leads_citas_exenciones set huella=v_huella where objeto='crm.guardar_agenda_reparto_diaria(date,uuid,uuid)';

  if (select huella from private.analitica_leads_citas_exenciones where objeto='private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)') is distinct from 'edcd3841df6c63097cdc64291f75d65b' then
    raise exception 'Preflight censo F3: declaración cambió %', 'private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)';
  end if;
  select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) into v_huella
    from pg_proc p where p.oid='private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)'::regprocedure;
  update private.analitica_leads_citas_exenciones set huella=v_huella where objeto='private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)';

-- El reporte de episodios entra al censo al unir la identidad de origen con crm.leads.
-- Sigue contando episodios de reparto, nunca conversión ni población comercial.
insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon,clase)
select 'crm.reporte_derivaciones_coordinacion_fn(date,date)', 'funcion',
  md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
  'Reporte operativo de episodios de derivación. El join con leads solo proyecta el origen F3; no calcula conversión ni llegadas. Conserva atribución y snapshots históricos.',
  'operativo'
from pg_proc p where p.oid='crm.reporte_derivaciones_coordinacion_fn(date,date)'::regprocedure;
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(), sellado_en=now() where id; end; $censo$;


do $postflight$ begin
  if exists (select 1 from pg_temp._f3_acl_antes a join pg_proc p on p.oid=to_regprocedure(a.firma)
    where p.proacl is distinct from a.proacl) then raise exception 'F3: cambió una ACL'; end if;
  if exists (select 1 from pg_temp._f3_censo_antes a
    join private.analitica_leads_citas_exenciones e on e.objeto=a.objeto
    where (to_jsonb(a)-'huella') is distinct from (to_jsonb(e)-'huella')) then
    raise exception 'F3: se alteró una declaración del censo'; end if;
  if exists (select 1 from private.contadores_crudos_leads_citas() c
    where (not c.declarada or not c.huella_ok) and not exists (
      select 1 from pg_temp._f3_censo_estado_antes a where a.objeto=c.objeto
        and (not a.declarada or not a.huella_ok))) then
    raise exception 'F3: nueva desviación del censo analítico: %', (
      select string_agg(c.objeto, ', ') from private.contadores_crudos_leads_citas() c
      where (not c.declarada or not c.huella_ok) and not exists (
        select 1 from pg_temp._f3_censo_estado_antes a where a.objeto=c.objeto
          and (not a.declarada or not a.huella_ok))); end if;
  -- Exercises both widened private contracts without a user or any writes.
  perform 1 from private.conversion_divisor_empresa_totales(date_trunc('month',now() at time zone 'America/Lima')::date,
    (date_trunc('month',now() at time zone 'America/Lima')+interval '1 month - 1 day')::date);
  perform 1 from crm.periodos_cerrados pc cross join lateral
    private.conversion_divisor_empresa_totales(pc.periodo,(pc.periodo+interval '1 month - 1 day')::date);
end; $postflight$;
notify pgrst, 'reload schema';
commit;
