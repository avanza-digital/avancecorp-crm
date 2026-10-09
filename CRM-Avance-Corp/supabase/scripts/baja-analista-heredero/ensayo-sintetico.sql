-- SOLO banco local de Docker, como postgres y con la migración aplicada. Nunca producción.
-- Se siembra historia con analistas dados de baja, conservando los triggers encendidos.
-- Contratos legacy propios (producto_condicion_id omitido) y fecha comercial inferida por el servidor.
-- La operación se inserta antes de disparar los triggers diferidos. READ COMMITTED es obligatorio
-- para trg_operacion_cartera_fija_categoria (20261009120000). TODO termina en ROLLBACK.
begin isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '180s';

do $guardia$
begin
  -- El banco es Postgres pelado con el ESQUEMA de producción y sin datos (montar-banco.sh): no trae
  -- app.settings.jwt_secret. La guarda es que no haya ni un contrato: producción tiene cientos.
  if exists (select 1 from public.contratos) then
    raise exception 'ENSAYO: la base tiene contratos; solo se permite el banco LOCAL vacío de Docker';
  end if;
  if (current_user = 'postgres') is not true then
    raise exception 'ENSAYO: ejecutar como postgres en el banco';
  end if;
  if to_regprocedure('private.heredero_de_baja(uuid,uuid)') is null
     or to_regprocedure('private.analista_dado_de_baja(uuid)') is null
     or to_regprocedure('private.analista_efectivo_contrato(uuid,uuid)') is null
     or to_regprocedure('private.analista_efectivo_cierre(uuid)') is null then
    raise exception 'ENSAYO: falta aplicar la migración en banco';
  end if;
  if (current_setting('session_replication_role') = 'origin') is not true then
    raise exception 'ENSAYO: los triggers deben estar encendidos';
  end if;
end $guardia$;

create temporary table baja_casos (
  numero integer generated always as identity,
  caso text not null, correcto boolean not null
) on commit drop;
create function pg_temp.baja_comprobar(p_caso text, p_correcto boolean) returns void
language plpgsql as $prueba$
begin
  insert into pg_temp.baja_casos(caso, correcto) values (p_caso, p_correcto is true);
  raise notice '%: %', case when p_correcto is true then 'PASS' else 'FAIL' end, p_caso;
end $prueba$;

do $ensayo$
declare
  v_a uuid := gen_random_uuid();
  v_p uuid := gen_random_uuid();
  v_h uuid := gen_random_uuid();
  v_i uuid := gen_random_uuid();
  v_empresa uuid := gen_random_uuid();
  v_supervisor uuid := gen_random_uuid();
  v_supervisor_2 uuid := gen_random_uuid();
  v_gerencia uuid := gen_random_uuid();
  v_cliente_p uuid := gen_random_uuid();
  v_cliente_i uuid := gen_random_uuid();
  v_cliente_a uuid := gen_random_uuid();
  v_nuevo uuid := gen_random_uuid();
  v_upgrade uuid := gen_random_uuid();
  v_renovacion uuid := gen_random_uuid();
  v_contrato_i uuid := gen_random_uuid();
  v_contrato_a uuid := gen_random_uuid();
  v_upgrade_a uuid := gen_random_uuid();
  v_renovacion_a uuid := gen_random_uuid();
  v_contrato_empresa uuid := gen_random_uuid();
  v_historico uuid := gen_random_uuid();
  v_persona uuid := gen_random_uuid();
  v_persona_sin_responsable uuid := gen_random_uuid();
  -- crm.leads admite UN lead por persona (leads_inversionista_uidx): cada lead de cooperativa lleva la suya.
  v_persona_lead_b uuid := gen_random_uuid();
  v_persona_lead_c uuid := gen_random_uuid();
  v_persona_lead_i uuid := gen_random_uuid();
  v_cierre uuid := gen_random_uuid();
  v_cierre_respaldo uuid := gen_random_uuid();
  v_cierre_precedencia uuid := gen_random_uuid();
  v_cierre_i uuid := gen_random_uuid();
  v_operacion uuid := gen_random_uuid();
  v_meta uuid := gen_random_uuid();
  v_mes date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes_anterior date;
  v_anterior_meta uuid;
  v_revision integer;
  v_fila record;
  v_ficha jsonb;
  v_altas jsonb;
  v_cierres jsonb;
  v_correcto boolean;
  v_rol_real text;
  v_metricas record;
  v_lead uuid;
  v_documento text;
  v_sellos_antes jsonb;
  v_sellos_despues jsonb;
begin
  if exists (select 1 from crm.periodos_cerrados where periodo = v_mes) then
    raise exception 'ENSAYO: el mes actual está sellado; preparar el banco sin alterar sus sellos';
  end if;
  select max(mes) into v_mes_anterior
  from (select (v_mes - make_interval(months => n))::date as mes from generate_series(1,59) n) meses
  where not exists (select 1 from crm.periodos_cerrados s where s.periodo = meses.mes);
  if v_mes_anterior is null then
    raise exception 'ENSAYO: se necesita otro mes abierto en los últimos 60 meses';
  end if;
  select coalesce(jsonb_agg(to_jsonb(s) order by to_jsonb(s)::text), '[]'::jsonb)
    into v_sellos_antes from crm.cierre_mes_vendedor s;

  -- Se crean TODOS los actores y clientes; no se reciclan identidades del banco.
  -- Mismo patrón auth -> perfiles -> supervisor -> equipo que siembra-banco.sql.
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('crm.op_privilegiada', 'on', true);
  for v_fila in select * from (values
    (v_supervisor, 'SUPERVISOR S1', 'comercial'), (v_supervisor_2, 'SUPERVISOR S2', 'comercial'),
    (v_gerencia, 'GERENCIA', 'admin'),
    (v_a, 'A ACTIVO', 'comercial'), (v_p, 'P INACTIVO', 'comercial'),
    (v_h, 'H HEREDERO', 'comercial'), (v_i, 'I SIN HEREDERO', 'comercial'),
    (v_empresa, 'EMPRESA SIN MEMBRESIA', 'admin'),
    (v_cliente_p, 'CLIENTE P', 'cliente'), (v_cliente_i, 'CLIENTE I', 'cliente'),
    (v_cliente_a, 'CLIENTE A', 'cliente')
  ) personas(id, nombre, rol) loop
    -- Solo (id, email): sirve igual en el Postgres pelado del banco y en el stack completo.
    insert into auth.users(id, email) values (v_fila.id, v_fila.id::text || '@baja-ensayo.test');
    insert into public.perfiles(id, nombre_completo, correo, rol, activo, tipo_documento,
      debe_cambiar_password, titular_distinto, titular_distinto_usd)
    values (v_fila.id, 'ENSAYO BAJA ' || v_fila.nombre, v_fila.id::text || '@baja-ensayo.test',
      v_fila.rol, true, 'DNI', false, false, false);
  end loop;
  insert into crm.equipo(perfil_id, rol_crm, activo) values
    (v_supervisor, 'supervisor', true), (v_supervisor_2, 'supervisor', true),
    (v_gerencia, 'gerencia', true);
  insert into crm.equipo(perfil_id, rol_crm, supervisor_id, activo) values
    (v_a, 'vendedor', v_supervisor, true), (v_h, 'vendedor', v_supervisor, true),
    (v_p, 'vendedor', v_supervisor_2, true), (v_i, 'vendedor', v_supervisor_2, true);
  -- P e I están activos durante el alta histórica: trg_leads_guard_tenencia rechaza
  -- INSERT de leads a inactivos. Se desactivan después de sembrar sus cierres.
  update public.perfiles set asesor_perfil_id = v_h where id in (v_cliente_p, v_cliente_a);
  -- I tiene cliente sin responsable. A tiene responsable H y aun así sigue contando a A.
  insert into crm.inversionistas(id, perfil_id, responsable_relacion_id, creado_por) values
    (v_persona, v_cliente_p, v_h, v_gerencia),
    (v_persona_sin_responsable, v_cliente_i, null, v_gerencia),
    (v_persona_lead_b, null, v_h, v_gerencia),
    (v_persona_lead_c, null, v_h, v_gerencia),
    (v_persona_lead_i, null, null, v_gerencia);

  -- No se manda fecha_cierre_comercial; el BEFORE la infiere de fecha_inicio.
  -- analista_cierre_id tiene FK a crm.equipo: una cuenta SIN membresía no puede ser analista de un contrato;
  -- ese caso se prueba en la regla pura (heredero_de_baja) y no con un contrato.
  -- Cada contrato genera su snapshot de producto legacy, sin clonar el de otro contrato.
  for v_fila in select * from (values
    (v_nuevo, v_cliente_p, v_p, 'nuevo', v_mes),
    (v_upgrade, v_cliente_p, v_p, 'upgrade', v_mes),
    (v_renovacion, v_cliente_p, v_h, 'renovacion', v_mes),
    (v_contrato_i, v_cliente_i, v_i, 'nuevo', v_mes),
    (v_contrato_a, v_cliente_a, v_a, 'nuevo', v_mes),
    (v_upgrade_a, v_cliente_a, v_a, 'upgrade', v_mes),
    (v_renovacion_a, v_cliente_a, v_h, 'renovacion', v_mes),
    (v_historico, v_cliente_p, v_p, 'nuevo', v_mes_anterior)
  ) contratos(id, cliente, analista, categoria, fecha) loop
    insert into public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
      modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria,
      creado_por, analista_cierre_id, es_demo)
    values (v_fila.id, 'BAJA-' || v_fila.id::text, v_fila.cliente, 1000, 'PEN', 15,
      'mensual', 'simple', v_fila.fecha, (v_fila.fecha + interval '12 months')::date,
      'activo', v_fila.categoria, v_h, v_fila.analista, false);
  end loop;
  -- Las cuatro operaciones satisfacen también el cinturón diferido de los contratos.
  insert into crm.operaciones_cartera(cliente_id, vendedor_id, tipo, contrato_nuevo_id,
    fecha_operacion, periodo, moneda, elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_cliente_p, v_p, 'upgrade', v_upgrade, v_mes, v_mes, 'PEN', false, true, 'flujo_cartera', v_h),
         (v_cliente_a, v_a, 'upgrade', v_upgrade_a, v_mes, v_mes, 'PEN', false, true, 'flujo_cartera', v_h);
  insert into crm.operaciones_cartera(id, cliente_id, vendedor_id, tipo, contrato_origen_id,
    contrato_nuevo_id, fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
    elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_operacion, v_cliente_p, v_p, 'renovacion', v_upgrade, v_renovacion,
      v_mes, v_mes, 'PEN', 800, 200, true, true, 'flujo_cartera', v_h),
    (gen_random_uuid(), v_cliente_a, v_h, 'renovacion', v_upgrade_a, v_renovacion_a,
      v_mes, v_mes, 'PEN', 800, 200, true, true, 'flujo_cartera', v_h);

  -- Cuatro cooperativas: persona directa, respaldo por lead, precedencia de persona directa
  -- SIN responsable frente al lead CON responsable, e inactivo I sin heredero.
  for v_fila in select * from (values
    (v_cierre, v_p, v_persona, v_persona, v_h),
    (v_cierre_respaldo, v_p, null::uuid, v_persona_lead_b, v_h),
    (v_cierre_precedencia, v_p, v_persona_sin_responsable, v_persona_lead_c, v_p),
    (v_cierre_i, v_i, v_persona_sin_responsable, v_persona_lead_i, v_i)
  ) cierres(id, analista, persona_directa, persona_lead, esperado) loop
    v_lead := gen_random_uuid();
    v_documento := (80000000 + floor(random() * 9999999)::integer)::text;
    insert into crm.leads(id, nombre_completo, telefono, origen, etapa, vendedor_id,
      convertido_en, inversionista_id, creado_por, monto_estimado)
    values (v_lead, 'ENSAYO BAJA COOPERATIVA', '+519' || v_documento, 'oficina', 'convertido',
      v_fila.analista, v_mes::timestamp at time zone 'America/Lima', v_fila.persona_lead, v_h, 22000);
    insert into crm.cierres_externos(id, lead_id, cooperativa, monto, moneda, documento_tipo,
      documento, nombre_completo, numero_transaccion, vendedor_id, creado_por, inversionista_id,
      fecha_comercial, fecha_imputacion, es_cierre_inicial, vence_en)
    values (v_fila.id, v_lead, 'qorilazo', 22000, 'PEN', 'DNI', v_documento,
      'ENSAYO BAJA COOPERATIVA', 'BAJA-' || v_fila.id::text, v_fila.analista, v_h,
      v_fila.persona_directa, v_mes, v_mes, true, (v_mes + interval '12 months')::date);
  end loop;
  -- Estado histórico posterior a la baja, sobre filas exclusivamente de este ensayo.
  -- Los clientes ya apuntan a H o carecen de responsable; no se ensaya aquí la puerta de offboarding.
  update crm.equipo set activo = false where perfil_id in (v_p, v_i);

  -- Roster deliberadamente asimétrico: H entra, P no. Una revisión efímera del mes.
  select id, revision into v_anterior_meta, v_revision from crm.meta_periodos
    where periodo = v_mes order by revision desc limit 1;
  insert into crm.meta_periodos(id, periodo, revision, revision_anterior_id, publicada_por)
    values (v_meta, v_mes, coalesce(v_revision, 0) + 1, v_anterior_meta, v_gerencia);
  insert into crm.metas_vendedor(meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
    values (v_meta, v_h, v_supervisor, 50);
  -- Disparar ahora los candados diferidos: no ocultar fallos de siembra con el ROLLBACK.
  set constraints all immediate;
  set constraints all deferred;

  perform pg_temp.baja_comprobar('Regla: P -> H', private.heredero_de_baja(v_p, v_h) = v_h);
  perform pg_temp.baja_comprobar('Regla: I sin responsable', private.heredero_de_baja(v_i, null) = v_i);
  perform pg_temp.baja_comprobar('Regla: responsable inactivo', private.heredero_de_baja(v_p, v_i) = v_p);
  perform pg_temp.baja_comprobar('Regla: responsable sin membresía', private.heredero_de_baja(v_p, v_empresa) = v_p);
  perform pg_temp.baja_comprobar('Regla: responsable igual', private.heredero_de_baja(v_p, v_p) = v_p);
  perform pg_temp.baja_comprobar('Regla: A activo', private.heredero_de_baja(v_a, v_h) = v_a);
  perform pg_temp.baja_comprobar('Regla: cuenta de empresa', private.heredero_de_baja(v_empresa, v_h) = v_empresa);
  perform pg_temp.baja_comprobar('NULL: analista', private.heredero_de_baja(null, v_h) is null);
  perform pg_temp.baja_comprobar('NULL: ambos', private.heredero_de_baja(null, null) is null);
  perform pg_temp.baja_comprobar('NULL: contrato y respaldo', private.analista_efectivo_contrato(null, null) is null);
  perform pg_temp.baja_comprobar('NULL: contrato conserva respaldo', private.analista_efectivo_contrato(null, v_p) = v_p);
  perform pg_temp.baja_comprobar('Contrato ausente conserva respaldo', private.analista_efectivo_contrato(gen_random_uuid(), v_p) = v_p);
  perform pg_temp.baja_comprobar('NULL: cierre', private.analista_efectivo_cierre(null) is null);
  perform pg_temp.baja_comprobar('Cierre ausente', private.analista_efectivo_cierre(gen_random_uuid()) is null);
  perform pg_temp.baja_comprobar('Respaldo NULL conserva cadena', private.analista_efectivo_contrato(v_renovacion, null) = v_h);
  perform pg_temp.baja_comprobar('Cadena inactiva permanece P antes de heredar',
    private.analista_atribuido_cadena(v_renovacion) = v_p);
  perform pg_temp.baja_comprobar('Cadena activa permanece A',
    private.analista_efectivo_contrato(v_renovacion_a, v_h) = v_a);

  for v_fila in select * from (values
    (v_nuevo, v_h), (v_upgrade, v_h), (v_renovacion, v_h),
    (v_contrato_i, v_i), (v_contrato_a, v_a), (v_upgrade_a, v_a),
    (v_renovacion_a, v_a), (v_historico, v_h)
  ) esperado(contrato, analista) loop
    perform pg_temp.baja_comprobar('Capital contrato ' || v_fila.contrato,
      (select count(*) = 1 and bool_and(k.analista_id = v_fila.analista)
       from private.capital_episodios('-infinity','infinity',true,'{}') k
       where k.contrato_id = v_fila.contrato and k.tipo like 'contrato_%'));
    perform pg_temp.baja_comprobar('Cartera contrato ' || v_fila.contrato,
      (select count(*) = 1 and bool_and(f.analista_origen_id = v_fila.analista)
       from private.cartera_f5_fuentes() f where f.fuente_id = v_fila.contrato));
  end loop;
  perform pg_temp.baja_comprobar('Capital desglose P -> H: dos partes, 800 + 200 y roster H',
    (select count(*) = 2 and bool_and(k.analista_id = v_h and k.en_roster)
      and sum(k.monto) = 1000
     from private.capital_episodios('-infinity','infinity',true,'{}') k
     where k.contrato_id = v_renovacion and k.tipo like 'desglose_%'));
  perform pg_temp.baja_comprobar('Capital contrato P -> H: roster H',
    (select count(*) = 1 and bool_and(k.en_roster)
     from private.capital_episodios('-infinity','infinity',true,'{}') k
     where k.contrato_id = v_nuevo and k.tipo = 'contrato_nuevo'));
  for v_fila in select * from (values
    (v_cierre, v_h), (v_cierre_respaldo, v_h), (v_cierre_precedencia, v_p), (v_cierre_i, v_i)
  ) esperado(cierre, analista) loop
    perform pg_temp.baja_comprobar('Cierre: directo/respaldo/precedencia/I ' || v_fila.cierre,
      private.analista_efectivo_cierre(v_fila.cierre) = v_fila.analista);
    perform pg_temp.baja_comprobar('Capital cooperativa ' || v_fila.cierre,
      (select count(*) = 1 and bool_and(k.analista_id = v_fila.analista
          and k.en_roster = (v_fila.analista = v_h) and k.monto = 22000)
       from private.capital_episodios('-infinity','infinity',true,'{}') k where k.cierre_externo_id = v_fila.cierre));
    perform pg_temp.baja_comprobar('Cartera cooperativa ' || v_fila.cierre,
      (select count(*) = 1 and bool_and(f.analista_origen_id = v_fila.analista)
       from private.cartera_f5_fuentes() f where f.fuente_id = v_fila.cierre));
  end loop;
  perform pg_temp.baja_comprobar('Visibilidad H: contrato, dos desgloses y cooperativa',
    (select count(*) = 4 from private.capital_episodios('-infinity','infinity',false,array[v_h]) k
     where k.contrato_id = v_renovacion or k.cierre_externo_id = v_cierre));
  perform pg_temp.baja_comprobar('Visibilidad P: pierde contrato, desgloses y cooperativa heredados',
    not exists (select 1 from private.capital_episodios('-infinity','infinity',false,array[v_p]) k
     where k.contrato_id = v_renovacion or k.cierre_externo_id = v_cierre));
  perform pg_temp.baja_comprobar('Conversión operación P -> H',
    (select count(*) = 1 and bool_and(e.analista_id = v_h)
     from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
       (v_mes + interval '1 month')::timestamp at time zone 'America/Lima', v_mes, true, '{}', 1) e
     where e.operacion_id = v_operacion));
  perform pg_temp.baja_comprobar('Conversión operación visible a H',
    (select count(*) = 1 from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
       (v_mes + interval '1 month')::timestamp at time zone 'America/Lima', v_mes, false, array[v_h], 1) e
     where e.operacion_id = v_operacion));
  perform pg_temp.baja_comprobar('Conversión operación deja de ser visible a P',
    not exists (select 1 from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
       (v_mes + interval '1 month')::timestamp at time zone 'America/Lima', v_mes, false, array[v_p], 1) e
     where e.operacion_id = v_operacion));
  select * into v_metricas from private.metricas_cartera_por_vendedor(v_mes) where vendedor_id = v_h;
  perform pg_temp.baja_comprobar('Métricas H: conteos y dinero heredados',
    v_metricas.conversiones_renovacion = 1 and v_metricas.operaciones_renovacion = 1
    and v_metricas.operaciones_upgrade = 1
    and v_metricas.capital_renovado_pen = 800 and v_metricas.capital_adicional_pen = 200);
  perform pg_temp.baja_comprobar('Métricas P: ya no tiene operaciones',
    not exists (select 1 from private.metricas_cartera_por_vendedor(v_mes) where vendedor_id = v_p));
  select * into v_metricas from private.metricas_cartera_por_vendedor(v_mes) where vendedor_id = v_a;
  perform pg_temp.baja_comprobar('Métricas A: cadena activa conserva operaciones',
    v_metricas.conversiones_renovacion = 1 and v_metricas.operaciones_renovacion = 1
    and v_metricas.operaciones_upgrade = 1 and v_metricas.capital_renovado_pen = 800);

  -- Las puertas se ejecutan como authenticated con identidad CRM real.
  -- Solo postgres registra los resultados en las temporales; no se les abren permisos.
  perform set_config('crm.op_privilegiada', 'off', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',v_gerencia,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_gerencia::text, true);
  for v_fila in select * from (values
    (v_nuevo, v_h, false, false, true),
    (v_upgrade, v_h, true, false, true),
    (v_renovacion, v_h, true, false, true),
    (v_contrato_i, v_i, false, false, false),
    (v_contrato_a, v_a, false, false, false),
    (v_renovacion_a, v_a, true, true, false)
  ) esperado(contrato, analista, cadena, adoptada, heredada) loop
    perform set_config('role', 'authenticated', true);
    v_ficha := crm.atribucion_contrato_fn(v_fila.contrato)->'atribucion_efectiva';
    perform set_config('role', 'postgres', true);
    perform pg_temp.baja_comprobar('Ficha: efectivo, cadena, adoptada y heredada ' || v_fila.contrato,
      (v_ficha->>'analista_id')::uuid = v_fila.analista
      and v_ficha->>'analista_nombre' = (select nombre_completo from public.perfiles where id = v_fila.analista)
      and (v_ficha->>'cadena')::boolean = v_fila.cadena
      and (v_ficha->>'adoptada')::boolean = v_fila.adoptada
      and (v_ficha->>'heredada')::boolean = v_fila.heredada);
  end loop;
  for v_fila in select * from (values (v_h), (v_i), (v_a)) analistas(id) loop
    perform set_config('role', 'authenticated', true);
    select altas = 1 into v_correcto from crm.altas_nuevas_por_analista_fn(60)
      where mes = v_mes and analista_id = v_fila.id;
    perform set_config('role', 'postgres', true);
    perform pg_temp.baja_comprobar('Altas nuevas del mes para ' || v_fila.id, v_correcto);
  end loop;
  perform set_config('role', 'authenticated', true);
  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_altas
    from crm.altas_nuevas_por_analista_fn(60) a;
  perform set_config('role', 'postgres', true);
  perform pg_temp.baja_comprobar('Altas nuevas: histórico P -> H', exists (
    select 1 from jsonb_array_elements(v_altas) a
    where (a->>'mes')::date = v_mes_anterior and (a->>'analista_id')::uuid = v_h and (a->>'altas')::bigint = 1));
  perform pg_temp.baja_comprobar('Altas nuevas: P desaparece', not exists (
    select 1 from jsonb_array_elements(v_altas) a where (a->>'analista_id')::uuid = v_p));

  -- Ámbitos reales: S1 tiene A/H; S2 conserva P/I en su subárbol, aunque estén dados de baja.
  for v_fila in select * from (values
    (v_h, 'H', true), (v_supervisor, 'S1', true),
    (v_supervisor_2, 'S2', false), (v_a, 'A', false)
  ) actores(id, nombre, ve_heredadas) loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub',v_fila.id,'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_fila.id::text, true);
    perform set_config('role', 'authenticated', true);
    v_rol_real := current_user;
    select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_altas
      from crm.altas_nuevas_por_analista_fn(60) a;
    perform set_config('role', 'postgres', true);
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': consulta ejecutada como authenticated',
      v_rol_real = 'authenticated' and current_user = 'postgres');
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': altas heredadas del mes e históricas según ámbito',
      case when v_fila.ve_heredadas then
        (select count(*) = 2 and bool_and((a->>'altas')::bigint = 1)
         from jsonb_array_elements(v_altas) a
         where (a->>'analista_id')::uuid = v_h and (a->>'mes')::date in (v_mes, v_mes_anterior))
      else not exists (select 1 from jsonb_array_elements(v_altas) a where (a->>'analista_id')::uuid = v_h) end);
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': ninguna alta sigue bajo P',
      not exists (select 1 from jsonb_array_elements(v_altas) a where (a->>'analista_id')::uuid = v_p));
    if v_fila.id = v_supervisor_2 then
      perform pg_temp.baja_comprobar('Rol S2: conserva el alta de I sin heredero',
        (select count(*) = 1 and bool_and((a->>'altas')::bigint = 1)
         from jsonb_array_elements(v_altas) a where (a->>'analista_id')::uuid = v_i and (a->>'mes')::date = v_mes));
    elsif v_fila.id = v_a then
      perform pg_temp.baja_comprobar('Rol A: conserva su propia alta',
        (select count(*) = 1 and bool_and((a->>'altas')::bigint = 1)
         from jsonb_array_elements(v_altas) a where (a->>'analista_id')::uuid = v_a and (a->>'mes')::date = v_mes));
    end if;
  end loop;

  for v_fila in select * from (values (v_h, 'H'), (v_a, 'A')) actores(id, nombre) loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub',v_fila.id,'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_fila.id::text, true);
    perform set_config('role', 'authenticated', true);
    v_ficha := crm.atribucion_contrato_fn(v_nuevo);
    perform set_config('role', 'postgres', true);
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': ficha heredada solo para el asesor H',
      case when v_fila.id = v_h then
        (v_ficha->'atribucion_efectiva'->>'heredada')::boolean is true
        and (v_ficha->'atribucion_efectiva'->>'analista_id')::uuid = v_h
        and v_ficha->'atribucion_efectiva'->>'analista_nombre' = 'ENSAYO BAJA H HEREDERO'
      else v_ficha is null end);
  end loop;

  -- El periodo es el primer día del mes actual de Lima (nunca futuro).
  for v_fila in select * from (values
    (v_h, 'H', 2, 44000), (v_supervisor_2, 'S2', 2, 44000), (v_gerencia, 'GERENCIA', 4, 88000)
  ) actores(id, nombre, cierres, capital) loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub',v_fila.id,'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_fila.id::text, true);
    perform set_config('role', 'authenticated', true);
    v_cierres := crm.cierres_externos_fn(v_mes);
    perform set_config('role', 'postgres', true);
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': conteos de cooperativas según ámbito',
      (v_cierres->>'cierres_total')::integer = v_fila.cierres
      and (v_cierres->>'cierres_mes_total')::integer = v_fila.cierres
      and jsonb_array_length(v_cierres->'cierres') = v_fila.cierres
      and jsonb_array_length(v_cierres->'cierres_mes') = v_fila.cierres);
    perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': totales de cooperativas según ámbito',
      (select count(*) = 1 and bool_and((t->>'capital')::numeric = v_fila.capital
         and (t->>'cierres')::integer = v_fila.cierres and t->>'moneda' = 'PEN' and t->>'cooperativa' = 'qorilazo')
       from jsonb_array_elements(v_cierres->'totales') t));
    if v_fila.id = v_supervisor_2 then
      perform pg_temp.baja_comprobar('Rol S2: no ve cooperativas heredadas en ninguna lista',
        not exists (select 1 from jsonb_array_elements((v_cierres->'cierres') || (v_cierres->'cierres_mes')) c
          where (c->>'cierre_id')::uuid in (v_cierre, v_cierre_respaldo)));
      perform pg_temp.baja_comprobar('Rol S2: conserva el cierre de precedencia bajo P',
        (select count(*) = 1 and bool_and((c->>'vendedor_id')::uuid = v_p
          and c->>'vendedor_nombre' = 'ENSAYO BAJA P INACTIVO')
         from jsonb_array_elements(v_cierres->'cierres_mes') c where (c->>'cierre_id')::uuid = v_cierre_precedencia));
      perform pg_temp.baja_comprobar('Rol S2: por empresa conserva P/I y excluye H',
        (select count(*) = 2 and bool_and((c->>'vendedor_id')::uuid in (v_p, v_i)
          and (c->>'capital')::numeric = 22000 and (c->>'cierres')::integer = 1)
         from jsonb_array_elements(v_cierres->'por_empresa') c));
    else
      perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': cierre heredado bajo H en ambas listas',
        (select count(*) = 2 and bool_and((c->>'vendedor_id')::uuid = v_h
          and c->>'vendedor_nombre' = 'ENSAYO BAJA H HEREDERO')
         from jsonb_array_elements((v_cierres->'cierres') || (v_cierres->'cierres_mes')) c
         where (c->>'cierre_id')::uuid = v_cierre));
      perform pg_temp.baja_comprobar('Rol ' || v_fila.nombre || ': por empresa suma 44000 y dos heredadas bajo H',
        (select count(*) = 1 and bool_and(c->>'vendedor_nombre' = 'ENSAYO BAJA H HEREDERO'
          and c->>'cooperativa' = 'qorilazo' and c->>'moneda' = 'PEN'
          and (c->>'capital')::numeric = 44000 and (c->>'cierres')::integer = 2)
         from jsonb_array_elements(v_cierres->'por_empresa') c where (c->>'vendedor_id')::uuid = v_h));
    end if;
  end loop;

  -- Permisos efectivos, además del ACL exacto: PUBLIC no es un rol consultable
  -- con has_function_privilege. Los superusuarios omiten ACL por definición de Postgres.
  for v_fila in select * from (values
    ('crm.altas_nuevas_por_analista_fn(integer)'), ('crm.atribucion_contrato_fn(uuid)'),
    ('crm.cierres_externos_fn(date)')
  ) puertas(firma) loop
    perform pg_temp.baja_comprobar('Permisos: anon sin EXECUTE en ' || v_fila.firma,
      has_function_privilege('anon', v_fila.firma, 'EXECUTE') is false);
  end loop;
  for v_fila in select * from (values
    ('private.analista_dado_de_baja(uuid)'), ('private.heredero_de_baja(uuid,uuid)'),
    ('private.analista_efectivo_contrato(uuid,uuid)'), ('private.analista_efectivo_cierre(uuid)')
  ) ayudantes(firma) loop
    perform pg_temp.baja_comprobar('Permisos: solo postgres tiene EXECUTE en ' || v_fila.firma,
      has_function_privilege('postgres', v_fila.firma, 'EXECUTE') is true
      and not exists (select 1 from pg_roles r where r.rolname <> 'postgres' and not r.rolsuper
        and has_function_privilege(r.oid, v_fila.firma::regprocedure, 'EXECUTE'))
      and (select p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
           from pg_proc p where p.oid = v_fila.firma::regprocedure));
  end loop;
  select coalesce(jsonb_agg(to_jsonb(s) order by to_jsonb(s)::text), '[]'::jsonb)
    into v_sellos_despues from crm.cierre_mes_vendedor s;
  perform pg_temp.baja_comprobar('Snapshots sellados sin cambios', v_sellos_antes = v_sellos_despues);
  perform pg_temp.baja_comprobar('Triggers encendidos al terminar', current_setting('session_replication_role') = 'origin');
end $ensayo$;

select numero, caso, case when correcto then 'PASS' else 'FAIL' end as resultado
from pg_temp.baja_casos order by numero;
do $resultado$
begin
  if exists (select 1 from pg_temp.baja_casos where correcto is not true) then
    raise exception 'ENSAYO BAJA FAIL: % casos fallaron; todo se deshace',
      (select count(*) from pg_temp.baja_casos where correcto is not true);
  end if;
  raise notice 'ENSAYO BAJA PASS: % casos; se deshace toda la siembra', (select count(*) from pg_temp.baja_casos);
end $resultado$;
rollback;
