-- ENSAYO EN PRODUCCIÓN de 20261009200000 (baja de analista → responsable actual). NO APLICA NADA:
-- es la migración entera, al byte, pero en vez de `commit` termina en un `raise` que lleva el resultado y
-- deshace la transacción completa (funciones, ayudantes y temporales). `db query --linked` no muestra avisos:
-- por eso el resultado viaja en el texto del error. Lo corre Miguel con `!`:
--   ! supabase db query --linked --file supabase/scripts/baja-analista-heredero/ensayo-produccion.sql
-- Se espera un ERROR que empieza por «ENSAYO OK (se deshizo todo)». Cualquier otro error = no aplicar.
-- Baja de analista: el capital/operación pasa al responsable ACTUAL activo (Miguel, 09/10/2026).
-- «Todo a Betzabeth»: TODOS los meses de lecturas vivas; los snapshots SELLADOS no se escriben.
-- La cadena de upgrade sigue igual; sin responsable activo distinto, o sin membresía CRM, no cambia el dueño.
-- Medición recibida de producción (09/10; no consultada por este implementador): Pierina 35 contratos
-- (Betzabeth/Vladimir), Noelia 7 (Elizabeth Chiroque), Ivett 3 sin responsable activo (se conservan).
-- Asesor y responsable coinciden 45/45; una renovación de Betzabeth hereda hoy a Pierina por cadena
-- (2026-01-001570 <- 000373); cuatro operaciones de Pierina en agosto; cuatro cierres de Noelia,
-- Qorilazo, septiembre, S/ 88.000. Dos perfiles DEMO inactivos sin contratos reales.
-- Aplicación humana, SOLO tras medir huellas y ensayar en banco:
-- ! supabase db query --linked --file supabase/migrations/20261009200000_crm_baja_analista_heredero.sql
-- Reversa: supabase/scripts/baja-analista-heredero/reversa.sql; no borra historial de migraciones.
-- Cuerpos generados desde vivo/ mediante generar-cuerpos.py; no alterar otras expresiones.
-- Huellas de la primera entrega medidas en banco (09/10/2026, crm 333 / private 685 idénticas).
-- Encargo 2 (cooperativas, exención, rótulo, service_role): huellas medidas en el banco a paridad con producción.
-- NO se llama a private.assert_analitica_leads_citas(): en producción ya falla por tres objetos ajenos
-- sin declarar (crm.gestiones_resumen_fn, private.citas_clientes_core, private.gestion_diaria_cola_hechos).
-- Se verifica y resella exclusivamente la exención de cierres externos, como en 20260915170017.
-- private.contratos_afectados_por_anulacion NO cambia: decide qué contratos produjo un cierre anulado comparando con la
-- FOTO del crédito (acreditado_a); con la regla de baja un alta anulada de un inactivo se contaría al heredero.

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello in share row exclusive mode;

do $mig$
declare
  v_funcion record;
  v_catalogo record;
  v_razon_viva constant text := $razon_viva$Lista las cooperativas del mes para gerencia: listado operativo con su conteo de apoyo, no una calculadora comercial. Tras ATR-4 sus totales excluyen SOLO la demo declarada (misma exclusion por id que el nucleo): los anulados reales SIGUEN siendo dinero (regla 31/08). F4 publicada: período por fecha de imputación, cierres independientes del lead y teléfono vivo restringido a la relación canónica actual. Cálculos y permisos conservados. F8 (20260914213928): el listado devuelve además plazo_meses y tasa_anual pactados por cierre; período, conteos, exclusión de demo y permisos conservados.$razon_viva$;
  v_razon_baja constant text := ' Baja de analista (09/10/2026): ámbito y nombres por el analista efectivo.';
  v_movimiento record;
  v_etapa text := 'PREFLIGHT';
  v_ya_aplicada boolean;
begin
  create temporary table baja_funciones (
    firma text primary key, anterior text, nueva text not null,
    definidor boolean not null, lenguaje text not null, acl text not null
  ) on commit drop;
  insert into pg_temp.baja_funciones values
    ('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', 'c9e58c1da9dd7a5d52991c9e47dc19d5', '2ed07da302e9a1b881a4962724234dd7', true, 'sql', '{postgres=X/postgres}'),
    ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', 'a0f6bab39ae1f046aa4b919ea9ce78ea', '6f85e83b0070f1ccdcc8d752e90fc67e', true, 'plpgsql', '{postgres=X/postgres}'),
    ('private.metricas_cartera_por_vendedor(date)', 'c1a0bab01e474af758f0feff8819414f', '6b7e7a8b868082cd0c81e18ca7c21479', true, 'sql', '{postgres=X/postgres}'),
    ('crm.altas_nuevas_por_analista_fn(integer)', 'ac3136ea697cc25fc7263cb8b23ad8f8', 'b421dfb1f3a317776d9e4e1b9e69dd76', true, 'sql', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('crm.atribucion_contrato_fn(uuid)', '02ad7d7247859fcf9e2c1ece9e2bc22e', '709e2b04159d7d7eb71d312d2dfebc68', true, 'sql', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('private.cartera_f5_fuentes()', 'fa15f7765d0892c790c7a4b6822e756e', 'd53e75a640ab5baed859ed3206e8fbf7', true, 'sql', '{postgres=X/postgres}'),
    ('crm.cierres_externos_fn(date)', 'd44dec0ba4b92ecd1991a7ff204dc57e', '67f5f9c020ea6395da20444911bd303b', true, 'plpgsql', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.analista_dado_de_baja(uuid)', null, '9326734c4500312094d26bf206c6e898', false, 'sql', '{postgres=X/postgres}'),
    ('private.heredero_de_baja(uuid,uuid)', null, 'ee6eae2b1740e49eb3e0721c4fac78a8', false, 'plpgsql', '{postgres=X/postgres}'),
    ('private.analista_efectivo_contrato(uuid,uuid)', null, 'b842caa224a153a145c35b5f614141c0', false, 'plpgsql', '{postgres=X/postgres}'),
    ('private.analista_efectivo_cierre(uuid)', null, '2cf2201f8a01c381a7756293fbdadd46', false, 'plpgsql', '{postgres=X/postgres}');
  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = to_regprocedure('private.analista_atribuido_cadena(uuid)'))
       = '3c9cec305b014ad8c933df25057d3e8b') is not true then
    raise exception '%: cambió o falta analista_atribuido_cadena; no se toca', v_etapa;
  end if;
  -- Exactamente los siete cuerpos nuevos o exactamente los siete vivos. Nunca un estado mixto.
  select bool_and(coalesce((select md5(pg_get_functiondef(p.oid)) from pg_proc p
    where p.oid = to_regprocedure(f.firma)) = f.nueva, false)) into v_ya_aplicada
  from pg_temp.baja_funciones f where f.anterior is not null;
  for v_funcion in select * from pg_temp.baja_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if v_funcion.anterior is null and v_ya_aplicada is not true then
      if to_regprocedure(v_funcion.firma) is not null then
        raise exception 'PREFLIGHT: ya existe % en un estado sin migrar; revisar sin sobrescribir', v_funcion.firma;
      end if;
      continue;
    end if;
    if (v_catalogo.huella = case when v_ya_aplicada then v_funcion.nueva else v_funcion.anterior end) is not true then
      raise exception 'PREFLIGHT: huella inesperada en %: %', v_funcion.firma, v_catalogo.huella;
    end if;
    if (v_catalogo.dueno = 'postgres' and v_catalogo.acl is not null
        and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = v_funcion.lenguaje
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception '%: invariantes inesperadas en % (dueño %, ACL %, definidor %, volatilidad %, lenguaje %, configuración %)',
        v_etapa, v_funcion.firma, v_catalogo.dueno, v_catalogo.acl, v_catalogo.definidor,
        v_catalogo.volatilidad, v_catalogo.lenguaje, v_catalogo.configuracion;
    end if;
  end loop;
  -- También se comprueba al repetir la migración/reversa: ninguna deriva del sello se acepta.
  if ((select e.clase = 'analitica'
      and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
      and e.huella = case when v_ya_aplicada is not true then '06bafcce0f005d95914bd2339d064bed'
                         else md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')) end
      and md5(e.razon) = case when v_ya_aplicada is not true then '80e4fe2d06961a40ed32256a5799a1eb'
                             else md5(v_razon_viva || v_razon_baja) end
    from private.analitica_leads_citas_exenciones e
    join pg_proc p on p.oid = to_regprocedure('crm.cierres_externos_fn(date)')
    where e.objeto = 'crm.cierres_externos_fn(date)')) is not true then
    raise exception 'PREFLIGHT: exención de cierres externos ausente o distinta del estado esperado';
  end if;
  if ((select s.sello = private.huella_exenciones_analitica_lc()
       from private.analitica_lc_sello s where s.id)) is not true then
    raise exception 'PREFLIGHT: sello analítico ausente o desfasado';
  end if;
  if v_ya_aplicada is true then
    raise notice 'crm_baja_analista_heredero: ya aplicada (once huellas e invariantes verificadas)';
    return;
  end if;

  create temporary table baja_antes on commit drop as
    select 'capital'::text as origen, to_jsonb(k) as fila, k.analista_id as analista,
      case when k.cierre_externo_id is not null then persona.responsable_relacion_id
           else cliente.asesor_perfil_id end as responsable,
      k.mes_comercial as mes
    from private.capital_episodios('-infinity','infinity',true,'{}') k
    left join public.contratos contrato on contrato.id = k.contrato_id
    left join public.perfiles cliente on cliente.id = contrato.cliente_id
    left join crm.cierres_externos ce on ce.id = k.cierre_externo_id
    left join crm.leads l on l.id = ce.lead_id
    left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id)
    union all
    select 'cartera', to_jsonb(f), f.analista_origen_id,
      case when f.empresa = 'avance' then cliente.asesor_perfil_id
           else persona.responsable_relacion_id end,
      null::date
    from private.cartera_f5_fuentes() f
    left join public.contratos contrato on f.empresa = 'avance' and contrato.id = f.fuente_id
    left join public.perfiles cliente on cliente.id = contrato.cliente_id
    left join crm.cierres_externos ce on f.empresa <> 'avance' and ce.id = f.fuente_id
    left join crm.leads l on l.id = ce.lead_id
    left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id);
  -- ORÁCULO independiente: NO llama a las tres funciones nuevas para construir el resultado esperado.
  -- La clave lógica es TODA la fila salvo atribución; EXCEPT ALL conserva duplicados.
  create temporary table baja_esperado on commit drop as
    select a.*, case when anterior.activo is false and responsable.activo is true
      and a.responsable is not null and a.responsable <> a.analista
      then a.responsable else a.analista end as esperado
    from pg_temp.baja_antes a
    left join crm.equipo anterior on anterior.perfil_id = a.analista
    left join crm.equipo responsable on responsable.perfil_id = a.responsable;
  create temporary table baja_filas_esperadas on commit drop as
    select a.origen,
      case when a.origen = 'capital' then
        a.fila || jsonb_build_object('analista_id', a.esperado, 'en_roster', exists (
          select 1 from crm.metas_vendedor mv
          where mv.meta_periodo_id = (select mp.id from crm.meta_periodos mp
            where mp.periodo = a.mes order by mp.revision desc limit 1)
            and mv.vendedor_id = a.esperado))
      else a.fila || jsonb_build_object('analista_origen_id', a.esperado) end as fila
    from pg_temp.baja_esperado a;

  -- Cuatro ayudantes, UNA regla. analista_dado_de_baja dice QUIÉN está fuera; heredero_de_baja, QUIÉN hereda.
  -- heredero_de_baja y los dos «efectivos» son PL/pgSQL a propósito (medido 09/10 en producción: con SQL anidado el capital de
  -- setiembre pasaba de 15 a 171 ms porque Postgres 17 re-planifica la función interna en CADA fila). En PL/pgSQL
  -- la cadena se evalúa como expresión simple con su plan en caché, y solo los dados de baja buscan heredero.
  execute $nuevas$
CREATE FUNCTION private.analista_dado_de_baja(p_analista uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  select exists (select 1 from crm.equipo e where e.perfil_id = p_analista and e.activo is false);
$function$
$nuevas$;
  execute $nuevas$
CREATE FUNCTION private.heredero_de_baja(p_analista uuid, p_responsable uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
begin
  -- Hereda solo un responsable distinto y ACTIVO de un analista dado de baja; en cualquier otro caso
  -- (NULL incluido) se conserva el analista: no se inventa dueño.
  if p_responsable is null or p_responsable = p_analista
     or private.analista_dado_de_baja(p_analista) is not true then
    return p_analista;
  end if;
  if exists (select 1 from crm.equipo responsable
             where responsable.perfil_id = p_responsable and responsable.activo is true) then
    return p_responsable;
  end if;
  return p_analista;
end;
$function$
$nuevas$;
  execute $nuevas$
CREATE FUNCTION private.analista_efectivo_contrato(p_contrato_id uuid, p_respaldo uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
  v_analista uuid := coalesce(private.analista_atribuido_cadena(p_contrato_id), p_respaldo);
begin
  if private.analista_dado_de_baja(v_analista) is not true then
    return v_analista;
  end if;
  return private.heredero_de_baja(v_analista,
    (select cliente.asesor_perfil_id
     from public.contratos contrato
     join public.perfiles cliente on cliente.id = contrato.cliente_id
     where contrato.id = p_contrato_id));
end;
$function$
$nuevas$;
  execute $nuevas$
CREATE FUNCTION private.analista_efectivo_cierre(p_cierre_externo_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
  v_analista uuid;
  v_responsable uuid;
begin
  select ce.vendedor_id, persona.responsable_relacion_id
    into v_analista, v_responsable
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id)
  where ce.id = p_cierre_externo_id;
  if private.analista_dado_de_baja(v_analista) is not true then
    return v_analista;
  end if;
  return private.heredero_de_baja(v_analista, v_responsable);
end;
$function$
$nuevas$;
  alter function private.analista_dado_de_baja(uuid) owner to postgres;
  alter function private.heredero_de_baja(uuid,uuid) owner to postgres;
  alter function private.analista_efectivo_contrato(uuid,uuid) owner to postgres;
  alter function private.analista_efectivo_cierre(uuid) owner to postgres;
  revoke execute on function private.analista_dado_de_baja(uuid), private.heredero_de_baja(uuid,uuid),
    private.analista_efectivo_contrato(uuid,uuid), private.analista_efectivo_cierre(uuid)
    from public, anon, authenticated, service_role;

  -- INICIO CUERPOS GENERADOS
  execute $def$
CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$

  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    -- ATR-2: la cadena de upgrade adopta tambien el CAPITAL (contrato 2026-08-30).
    ef.analista_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  cross join lateral private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as ef(analista_id)
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or ef.analista_id = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    ef.analista_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) as ef(analista_id)
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or ef.analista_id = any(p_visibles))

  union all

  select
    'cooperativa',
    -- ATR-4 (Miguel 31/08): la sancion de anular es SOLO de conversion. El
    -- capital de una coop anulada EXISTE y se queda: vuelve a 'stock'. UNICA
    -- excepcion DECLARADA: la fila DEMO de Miguel (qorilazo S/100.000, creada
    -- 19/08 y anulada 20/08 con motivo 'DEMO'; vault «Cierre Qorilazo S 100000
    -- es dato demo») — su lead es REAL y el filtro de demos no la caza, asi
    -- que se excluye por id, sellado por la huella de este cuerpo.
    case when ce.anulado_en is null then 'stock'
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 'nula'
         else 'stock' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ef.analista_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ef.analista_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 0::numeric
         else ce.monto end,
    'nuevo',
    date_trunc('month', coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) at time zone 'America/Lima')::date,
    coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en),
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  cross join lateral private.analista_efectivo_cierre(ce.id) as ef(analista_id)
  where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= p_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < p_fin
    and (p_global or ef.analista_id = any(p_visibles));

$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- Los meses COMPLETOS que toca la ventana: el tope de referidos es por analista y por mes de cierre, y su base son
  -- todos los cierres de leads asignados de ESE analista en ese mes, no solo los de un rango parcial. Como cada analista
  -- tiene su propia base, el ámbito (p_global/p_visibles) se aplica antes de calcular el tope sin cambiar su resultado.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- El índice único del ledger garantiza un cierre por lead. El cierre queda
  -- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
  -- siguen disponibles para consumidores operativos/capital, con aporte CERO.
  select c.*,
    -- El mes de CIERRE: el de la fecha comercial del cierre del lead.
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    -- Un cierre cuenta para la base del tope solo si NO está anulado y es el cierre de un lead que el sistema asigna
    -- (private.conversion_origen_base_tope: landing y formulario) y que no es un registro manual (alta_manual: regla
    -- cerrada, el registro manual queda fuera de la base, como queda fuera del divisor). Los referidos y la base cargada
    -- no entran en la base. Solo la BASE excluye el alta manual: su aporte al numerador sigue entero.
    (not c.anulado and private.conversion_origen_base_tope(c.origen) and not coalesce(lm.alta_manual, false)) as en_base,
    (c.fue_referido and not c.anulado) as es_referido,
    -- Desempate de dos cierres de la MISMA fecha comercial (es un día, sin hora): el que se acreditó antes cuenta antes.
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
  left join crm.leads lm on lm.id = c.lead_id
), con_tope as (
  select m.*,
    -- Un cierre sin analista (analista_id NULL) comparte UNA sola partición con los demás sin analista: un solo tope para todos.
    count(*) filter (where m.en_base) over (partition by m.analista_id, m.mes_cierre) as base_cierres,
    -- Los referidos de cada analista y mes, del más antiguo al más reciente: cuentan los primeros.
    row_number() over (partition by m.analista_id, m.mes_cierre, m.es_referido
                       order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido,
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
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
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
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- TOPE DE REFERIDOS (Miguel, 07/10/2026, desde octubre): por analista y mes de cierre, los referidos cuentan hasta el
-- tope % de sus cierres de leads asignados por el sistema (en_base; sin referidos, base cargada, registros manuales ni
-- operaciones; redondeado hacia arriba); los más recientes pasan a valer 0. Sin cierres asignados la base es 0 y todos sus referidos valen 0.
-- Sin tope vigente para el mes (agosto, septiembre) el aporte queda como siempre.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
         and t.orden_referido > ceil(t.base_cierres * t.tope_pct / 100.0)
       then 0::numeric else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa su propio peso; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
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
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      -- ATR-1: mismo resolutor que el nucleo de conversion (una politica).
      private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) as vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id)
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.altas_nuevas_por_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with gate as (
    -- fail-closed: sin rol CRM ni lector global, el reporte sale VACIO.
    select coalesce(
      (select auth.uid()) is not null
      and (
        private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia')
        or private.es_lector_global()
      ), false) as ok
  ),
  ambito as (
    select
      (coalesce(private.es_lector_global(), false)
       or private.rol_crm((select auth.uid())) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid()))) as ids
  ),
  anulados as (
    -- Contratos cuyo cierre fue anulado, por el mapeo CANONICO (no reinventado).
    -- Rama 2 (cierres_externos = cooperativa): las coop NO viven en public.contratos,
    -- asi que el mapeo devuelve contratos Avance solo si el MISMO lead ligo un 'nuevo'
    -- Avance al mismo acreditado; hoy 0 impacto (unica coop anulada -> 0 'nuevo').
    select x as contrato_id
    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    union
    select x
    from crm.cierres_externos ce
    cross join lateral private.contratos_afectados_por_anulacion(ce.lead_id) x
    where ce.anulado_en is not null and ce.es_cierre_inicial
  ),
  base as (
    -- 🔴 fecha_cierre_comercial ES `date` (el dia comercial de Lima). NUNCA
    --    `at time zone` sobre un date: en un servidor UTC el dia 1 se cae al mes
    --    anterior (footgun del proyecto). Se bucketea y se acota en espacio de FECHA,
    --    igual que private.capital_episodios.
    select
      (date_trunc('month', c.fecha_cierre_comercial))::date as mes,
      private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as analista_id
    from public.contratos c
    where c.categoria = 'nuevo'
      and not c.es_demo
      and c.fecha_cierre_comercial is not null
      and not exists (select 1 from anulados an where an.contrato_id = c.id)
      and c.fecha_cierre_comercial >=
        (date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date
  )
  select
    b.mes,
    b.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    count(*)::bigint as altas
  from gate g
  cross join ambito a
  join base b on g.ok
  left join public.perfiles pf on pf.id = b.analista_id
  where a.es_global or b.analista_id = any(a.ids)
  group by b.mes, b.analista_id, coalesce(pf.nombre_completo, 'Sin analista')
  order by b.mes desc, altas desc;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.atribucion_contrato_fn(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    -- La MISMA regla de visibilidad que ya gobierna los contratos del CRM: se
    -- pregunta a la vista viva en vez de copiar su `where`.
    when not exists (
      select 1 from crm.contratos_cartera v where v.id = p_contrato_id
    ) then null
    else (
      select jsonb_build_object(
        'contrato_id',   c.id,
        'analista_id',   c.analista_cierre_id,
        'analista_nombre', pa.nombre_completo,
        'es_demo',       c.es_demo,
        'registrado_por', pr.nombre_completo,
        -- ATR-3: quien COBRA de verdad (la politica de la cadena de upgrade).
        -- 'cadena' = el contrato pertenece a una cadena de upgrade (el propio
        -- upgrade incluido): toda renovacion suya contara al analista_id de aqui.
        -- 'adoptada' = la cadena difiere del analista que la proceso y sigue siendo la atribucion efectiva.
        'atribucion_efectiva', (
          select jsonb_build_object(
            'cadena',   ef.analista_id is not null,
            'adoptada', ef.analista_id is not null
                        and ef.analista_id <> c.analista_cierre_id
                        and efectivo.analista_id = ef.analista_id,
            'heredada', efectivo.analista_id is distinct from coalesce(ef.analista_id, c.analista_cierre_id),
            'analista_id',     efectivo.analista_id,
            'analista_nombre', pef.nombre_completo
          )
          from (select private.analista_atribuido_cadena(c.id) as analista_id) ef
          cross join lateral (select private.analista_efectivo_contrato(c.id, c.analista_cierre_id) as analista_id) efectivo
          left join public.perfiles pef on pef.id = efectivo.analista_id
        ),
        'reasignaciones', case
          -- El historial con motivos, solo para la autoridad o el propio
          -- analista (A3). Mismo conjunto que la policy de la tabla, con P04.
          when (((select public.es_gestor_cartera())
                 or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
                and not (select private.membresia_crm_revocada()))
               or c.analista_cierre_id = (select auth.uid())
          then coalesce((
            select jsonb_agg(jsonb_build_object(
              'cuando',  r.reasignado_en,
              'de',      pde.nombre_completo,
              'a',       pa2.nombre_completo,
              'motivo',  r.motivo,
              'por',     ppor.nombre_completo
            ) order by r.reasignado_en desc)
            from crm.reasignaciones_analista r
            left join public.perfiles pde  on pde.id  = r.analista_de
            left join public.perfiles pa2  on pa2.id  = r.analista_a
            left join public.perfiles ppor on ppor.id = r.reasignado_por
            where r.contrato_id = c.id
          ), '[]'::jsonb)
          else '[]'::jsonb
        end
      )
      from public.contratos c
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles pr on pr.id = c.creado_por
      where c.id = p_contrato_id
    )
  end;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION crm.cierres_externos_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_global     boolean;
  v_filas      boolean;
  v_alcance    text;
  v_visibles   uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini        timestamptz;
  v_fin        timestamptz;
  v_payload    jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_filas := coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', v_alcance,
    -- Filas para la sección «En cooperativas» de Mi cartera (todo el
    -- histórico del ámbito, más reciente primero). Tope de 200 con total al
    -- lado: sin tope sería la lista sin fin que F2 vino a matar; con tope
    -- mudo, el front sumaría filas truncadas y mentiría en los totales — por
    -- eso los mini-totales NO salen de las filas sino de `totales`.
    'cierres', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'plazo_meses', ce.plazo_meses,
        'tasa_anual', ce.tasa_anual,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_efectivo_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select ce0.*, ef.analista_id as vendedor_efectivo_id
        from crm.cierres_externos ce0
        cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        where v_global or ef.analista_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_efectivo_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles)
    ),
    -- Las filas DEL MES pedido: es la vista de revisión de supervisor y gerencia
    -- («Ver cierres del mes»), donde el número de operación se contrasta. NO se
    -- filtra en el cliente sobre `cierres`, que viene tope 200 por antigüedad y
    -- podría no alcanzar el mes entero.
    'cierres_mes', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or case
          -- F3 conserva la tenencia del lead convertido como historia. El
          -- teléfono vivo de una persona reconocida sigue su relación actual.
          when ce.inversionista_id is not null then exists (
            select 1 from crm.inversionistas ip
            where ip.id=private.inversionista_canonica(ce.inversionista_id)
              and ip.responsable_relacion_id=any(v_visibles))
          else l.vendedor_id=any(v_visibles) end
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'plazo_meses', ce.plazo_meses,
        'tasa_anual', ce.tasa_anual,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_efectivo_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'fecha_comercial', coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
        'fecha_imputacion', coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
        'es_cierre_inicial', ce.es_cierre_inicial,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select ce0.*, ef.analista_id as vendedor_efectivo_id
        from crm.cierres_externos ce0
        cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        where coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) >= v_ini and coalesce((ce0.fecha_imputacion::timestamp at time zone 'America/Lima'),ce0.creado_en) < v_fin
          and (v_global or ef.analista_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      left join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_efectivo_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
        and (v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles))
    ),
    -- Mini-totales de Mi cartera: TODO el histórico del ámbito, por
    -- cooperativa y moneda (PEN/USD jamás sumados). Servidos aquí para que el
    -- front no haga aritmética sobre una lista que puede venir truncada.
    'totales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cooperativa', t.cooperativa,
        'moneda', t.moneda,
        'capital', t.capital,
        'cierres', t.cierres
      ) order by t.cooperativa, t.moneda)
      from (
        select ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        where (v_global or private.analista_efectivo_cierre(ce.id) = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.cooperativa, ce.moneda
      ) t
    ), '[]'::jsonb),
    -- Desglose por empresa del MES pedido, por vendedor × cooperativa ×
    -- moneda, para supervisor y gerencia. La parte «Avance» del desglose la
    -- pone cumplimiento_metas_fn (capital_real ya INCLUYE los externos tras
    -- esta migración): Avance = capital_real − estos agregados, resta de dos
    -- números servidos — no una división en cliente.
    'por_empresa', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', x.vendedor_id,
        'vendedor_nombre', x.nombre,
        'cooperativa', x.cooperativa,
        'moneda', x.moneda,
        'capital', x.capital,
        'cierres', x.cierres
      ) order by x.nombre, x.cooperativa, x.moneda)
      from (
        select ce.vendedor_efectivo_id as vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from (
          select ce0.*, ef.analista_id as vendedor_efectivo_id
          from crm.cierres_externos ce0
          cross join lateral private.analista_efectivo_cierre(ce0.id) as ef(analista_id)
        ) ce
        left join public.perfiles p on p.id = ce.vendedor_efectivo_id
        where coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) >= v_ini and coalesce((ce.fecha_imputacion::timestamp at time zone 'America/Lima'),ce.creado_en) < v_fin
          and (v_global or ce.vendedor_efectivo_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.vendedor_efectivo_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$
$def$;

  execute $def$
CREATE OR REPLACE FUNCTION private.cartera_f5_fuentes()
 RETURNS TABLE(fuente_id uuid, inversionista_id uuid, inversion_id uuid, empresa text, perfil_id uuid, lead_id uuid, numero text, capital numeric, moneda text, estado text, fecha_comercial date, fecha_imputacion date, vence_en date, analista_origen_id uuid, es_inicial boolean, es_demo boolean, identidad_coherente boolean, creado_en timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- La canónica de cada persona y el analista atribuido de cada contrato se calculan UNA vez por
  -- llamada (mapas jsonb) en vez de una CTE recursiva por FILA: medido el 30/09/2026, cada llamada
  -- hacía ~1.900 llamadas a inversionista_canonica() y ~685 a analista_atribuido_cadena() (42 ms);
  -- con los mapas, 11 ms y las mismas 726 filas. Los mapas repiten el criterio EXACTO de esas dos
  -- funciones (que no cambian): paseo hacia la raíz con tope 16 y, sin raíz, el propio id; primer
  -- ancestro «upgrade» por operaciones_cartera con lista de visitados y tope 100.
  with recursive
  paseo as (
    select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i
    union all
    select w.origen, i.id, i.inversionista_canonico_id, w.n+1
    from paseo w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16
  ),
  canon as (
    select origen as id,
      coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon
    from paseo group by origen
  ),
  cadena as (
    select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c
    union all
    select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id
    from cadena cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id
    where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100
  ),
  atrib as (
    select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id
    from cadena cd join public.contratos con on con.id = cd.contrato_id
    where con.categoria = 'upgrade' order by cd.raiz, cd.nivel asc
  ),
  canon_map as (select coalesce(jsonb_object_agg(id::text, canon::text), '{}'::jsonb) as m from canon),
  atrib_map as (select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), '{}'::jsonb) as m from atrib),
  bajas_map as (select coalesce(jsonb_object_agg(e.perfil_id::text, true), '{}'::jsonb) as m
    from crm.equipo e where private.analista_dado_de_baja(e.perfil_id))
  select c.id, ids.personas[1], iv.id, 'avance'::text, c.cliente_id, null::uuid,
    c.numero_contrato, c.capital, c.moneda, c.estado,
    c.fecha_cierre_comercial, c.fecha_cierre_comercial, c.fecha_vencimiento,
    case when (select m from bajas_map) ? coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id)::text
      then private.heredero_de_baja(coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id),
        (select cliente.asesor_perfil_id from public.perfiles cliente where cliente.id = c.cliente_id))
      else coalesce((((select m from atrib_map)->>c.id::text)::uuid),c.analista_cierre_id) end,
    iv.es_primera_conversion,c.es_demo,
    cardinality(ids.personas)=1, c.creado_en
  from public.contratos c
  left join crm.inversiones iv on iv.contrato_id=c.id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (
      select i.id from crm.inversionistas i where i.perfil_id=c.cliente_id
      union select iv.inversionista_id where iv.inversionista_id is not null
    ) x
  ) ids
  union all
  select ce.id, ids.personas[1],iv.id,ce.cooperativa,null::uuid,ce.lead_id,
    ce.referencia_externa,ce.monto,ce.moneda,
    case when ce.anulado_en is not null then 'anulado_comercialmente'
      when ce.vence_en < (statement_timestamp() at time zone 'America/Lima')::date
      then 'vencido' else 'vigente' end,
    coalesce(ce.fecha_comercial,(ce.creado_en at time zone 'America/Lima')::date),
    coalesce(ce.fecha_imputacion,(ce.creado_en at time zone 'America/Lima')::date),
    ce.vence_en,case when (select m from bajas_map) ? ce.vendedor_id::text
      then private.analista_efectivo_cierre(ce.id) else ce.vendedor_id end,ce.es_cierre_inicial,
    ce.id='a112aead-184a-4979-9041-943978fadae4'::uuid,
    cardinality(ids.personas)=1,ce.creado_en
  from crm.cierres_externos ce
  left join crm.inversiones iv on iv.cierre_externo_id=ce.id
  left join crm.leads l on l.id=ce.lead_id
  cross join lateral (
    select array_agg(distinct coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)) as personas
    from (select ce.inversionista_id as id union select iv.inversionista_id
          union select l.inversionista_id) x where x.id is not null
  ) ids;
$function$
$def$;

  -- FIN CUERPOS GENERADOS
  -- Re-declaración acotada: misma normalización que 20260915170017, sin bendecir otros objetos.
  update private.analitica_leads_citas_exenciones e
    set huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')), razon = e.razon || v_razon_baja
    from pg_proc p where p.oid = 'crm.cierres_externos_fn(date)'::regprocedure
      and e.objeto = 'crm.cierres_externos_fn(date)';
  update private.analitica_lc_sello
    set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

  create temporary table baja_despues on commit drop as
    select 'capital'::text as origen, to_jsonb(k) as fila, k.analista_id as analista,
      case when k.cierre_externo_id is not null then persona.responsable_relacion_id
           else cliente.asesor_perfil_id end as responsable,
      k.mes_comercial as mes
    from private.capital_episodios('-infinity','infinity',true,'{}') k
    left join public.contratos contrato on contrato.id = k.contrato_id
    left join public.perfiles cliente on cliente.id = contrato.cliente_id
    left join crm.cierres_externos ce on ce.id = k.cierre_externo_id
    left join crm.leads l on l.id = ce.lead_id
    left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id)
    union all
    select 'cartera', to_jsonb(f), f.analista_origen_id,
      case when f.empresa = 'avance' then cliente.asesor_perfil_id
           else persona.responsable_relacion_id end,
      null::date
    from private.cartera_f5_fuentes() f
    left join public.contratos contrato on f.empresa = 'avance' and contrato.id = f.fuente_id
    left join public.perfiles cliente on cliente.id = contrato.cliente_id
    left join crm.cierres_externos ce on f.empresa <> 'avance' and ce.id = f.fuente_id
    left join crm.leads l on l.id = ce.lead_id
    left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id);
  -- Conservación exacta de TODAS las demás columnas, incluyendo número de filas y multiplicidad.
  if exists (
    (select origen, fila - array['analista_id','en_roster','analista_origen_id'] from pg_temp.baja_antes
     except all
     select origen, fila - array['analista_id','en_roster','analista_origen_id'] from pg_temp.baja_despues)
    union all
    (select origen, fila - array['analista_id','en_roster','analista_origen_id'] from pg_temp.baja_despues
     except all
     select origen, fila - array['analista_id','en_roster','analista_origen_id'] from pg_temp.baja_antes)
  ) then
    raise exception 'ORÁCULO: cambiaron filas, multiplicidad o columnas ajenas a la atribución';
  end if;
  -- Toda fila movida debe corresponder EXACTAMENTE a inactivo -> responsable activo distinto.
  -- También verifica en_roster contra el cuadro de metas del mes y que los no afectados no se muevan.
  if exists (
    (select origen, fila from pg_temp.baja_filas_esperadas
     except all select origen, fila from pg_temp.baja_despues)
    union all
    (select origen, fila from pg_temp.baja_despues
     except all select origen, fila from pg_temp.baja_filas_esperadas)
  ) then
    raise exception 'ORÁCULO: atribución/en_roster no coincide con la regla independiente de baja';
  end if;
  if exists (
    select 1 from pg_temp.baja_despues d
    join crm.equipo anterior on anterior.perfil_id = d.analista and anterior.activo is false
    join crm.equipo responsable on responsable.perfil_id = d.responsable and responsable.activo is true
    where d.responsable is not null and d.responsable <> d.analista
  ) then
    raise exception 'ORÁCULO: queda una fila de un inactivo con responsable activo distinto';
  end if;
  for v_movimiento in
    select origen, analista, esperado, count(*) as filas
    from pg_temp.baja_esperado where analista is distinct from esperado
    group by origen, analista, esperado order by origen, analista, esperado
  loop
    raise notice 'ORÁCULO %: analista % -> responsable %: % filas movidas',
      v_movimiento.origen, v_movimiento.analista, v_movimiento.esperado, v_movimiento.filas;
  end loop;
  raise notice 'ORÁCULO PASS: % filas de capital y % fuentes de cartera; multiplicidad y atribuciones verificadas',
    (select count(*) from pg_temp.baja_despues where origen = 'capital'),
    (select count(*) from pg_temp.baja_despues where origen = 'cartera');

  v_etapa := 'POSTFLIGHT';
  if ((select e.clase = 'analitica' and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
      and md5(e.razon) = md5(v_razon_viva || v_razon_baja)
    from private.analitica_leads_citas_exenciones e
    join pg_proc p on p.oid = to_regprocedure('crm.cierres_externos_fn(date)')
    where e.objeto = 'crm.cierres_externos_fn(date)')) is not true then
    raise exception 'POSTFLIGHT: exención de cierres externos incorrecta';
  end if;
  if ((select s.sello = private.huella_exenciones_analitica_lc()
       from private.analitica_lc_sello s where s.id)) is not true then
    raise exception 'POSTFLIGHT: sello analítico ausente o desfasado';
  end if;

  if ((select md5(pg_get_functiondef(p.oid)) from pg_proc p
       where p.oid = to_regprocedure('private.analista_atribuido_cadena(uuid)'))
       = '3c9cec305b014ad8c933df25057d3e8b') is not true then
    raise exception '%: cambió o falta analista_atribuido_cadena; no se toca', v_etapa;
  end if;
  -- Emitir TODAS las huellas antes de compararlas facilita la medición en banco; nunca omite el rechazo.
  for v_funcion in select * from pg_temp.baja_funciones loop
    raise notice 'HUELLA % = %', v_funcion.firma,
      (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure(v_funcion.firma));
  end loop;
  for v_funcion in select * from pg_temp.baja_funciones loop
    select md5(pg_get_functiondef(p.oid)) as huella, pg_get_userbyid(p.proowner) as dueno,
      p.proacl::text as acl, p.prosecdef as definidor, p.provolatile as volatilidad,
      l.lanname as lenguaje, p.proconfig as configuracion
    into v_catalogo from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = to_regprocedure(v_funcion.firma);
    if (v_catalogo.huella = v_funcion.nueva) is not true then
      raise exception 'POSTFLIGHT: huella inesperada en %: % (esperada %); se deshace todo',
        v_funcion.firma, v_catalogo.huella, v_funcion.nueva;
    end if;
    if (v_catalogo.dueno = 'postgres' and v_catalogo.acl is not null
        and v_catalogo.acl = v_funcion.acl
        and v_catalogo.definidor = v_funcion.definidor
        and v_catalogo.volatilidad = 's' and v_catalogo.lenguaje = v_funcion.lenguaje
        and cardinality(v_catalogo.configuracion) = 1
        and v_catalogo.configuracion[1] in ('search_path=', 'search_path=""')) is not true then
      raise exception '%: invariantes inesperadas en % (dueño %, ACL %, definidor %, volatilidad %, lenguaje %, configuración %)',
        v_etapa, v_funcion.firma, v_catalogo.dueno, v_catalogo.acl, v_catalogo.definidor,
        v_catalogo.volatilidad, v_catalogo.lenguaje, v_catalogo.configuracion;
    end if;
  end loop;
  raise notice 'crm_baja_analista_heredero: aplicada';
end $mig$;

comment on function private.capital_episodios(timestamptz,timestamptz,boolean,uuid[]) is 'Capital por contrato, desglose y cooperativa. BAJA DE ANALISTA (09/10/2026): el analista sale de private.analista_efectivo_contrato / private.analista_efectivo_cierre (cadena de upgrade + regla de baja hacia el responsable actual activo), en todos los meses vivos; los snapshots sellados no se tocan.';
comment on function private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric) is 'Núcleo único de la conversión: llegadas (divisor), cierres de leads y operaciones de cartera (numerador). Desde 2026-10 aplica el TOPE DE REFERIDOS (private.tope_referidos_conversion) por analista y mes de cierre; su base son los cierres de leads asignados por el sistema (private.conversion_origen_base_tope), calculada sobre el mes completo de cada analista y recortada después al rango pedido. BAJA DE ANALISTA (09/10/2026): la pierna de operaciones usa private.analista_efectivo_contrato; las piernas de leads (ledger) no cambian.';
comment on function private.metricas_cartera_por_vendedor(date) is 'Conversión de cartera derivada exclusivamente de private.conversion_episodios (operación deduplicada por cliente/mes); economía completa de renovaciones por asesor. El adicional solo vive en las columnas de dinero. BAJA DE ANALISTA (09/10/2026): el asesor sale de private.analista_efectivo_contrato.';
comment on function crm.altas_nuevas_por_analista_fn(integer) is 'Altas de CONTRATOS NUEVOS (categoria=nuevo) por el analista que cierra (ATR: coalesce(analista_atribuido_cadena, analista_cierre_id)), por mes de cierre comercial (espacio de fecha, sin tz), excluyendo cierres anulados. Sustituye a metricas_altas_analista_fn (F7 Ola 2b). Conteo VIVO, sin sellado de mes. Miguel 04/09. BAJA DE ANALISTA (09/10/2026): el analista sale de private.analista_efectivo_contrato (regla de baja hacia el responsable actual activo).';
comment on function crm.atribucion_contrato_fn(uuid) is 'De quien es la venta (F3.6) + a quien COBRA de verdad (ATR-3: atribucion_efectiva {cadena, adoptada, analista_id, analista_nombre} — la politica de la cadena de upgrade). NULL si quien pregunta no ve el contrato (gate: la vista crm.contratos_cartera). BAJA DE ANALISTA (09/10/2026): analista_id/analista_nombre son el efectivo (private.analista_efectivo_contrato); clave nueva heredada = la regla de baja actuó; cadena conserva su significado; adoptada solo es true cuando la cadena difiere del analista de cierre y sigue siendo el efectivo.';
comment on function private.cartera_f5_fuentes() is 'Cartera F5: una fila por fuente (contrato Avance o cierre externo) con su persona canónica y su analista atribuido. Canónica y atribución se calculan una vez por llamada (mapas jsonb) con el mismo criterio que inversionista_canonica y analista_atribuido_cadena (30/09/2026). SECURITY DEFINER: solo la llaman funciones de private/crm. BAJA DE ANALISTA (09/10/2026): analista_origen_id pasa por private.heredero_de_baja (contratos) y private.analista_efectivo_cierre (cierres externos).';
comment on function private.analista_dado_de_baja(uuid) is 'Regla de baja, parte 1 (09/10/2026): un analista está dado de baja si su membresía CRM existe y está inactiva (crm.equipo.activo = false). Única definición: la usan heredero_de_baja, los dos efectivos y el mapa de cartera_f5_fuentes.';
comment on function private.heredero_de_baja(uuid,uuid) is 'Regla única de baja: solo una membresía CRM explícitamente inactiva hereda al responsable distinto y explícitamente activo; NULL, sin membresía o sin heredero activo conserva el analista.';
comment on function private.analista_efectivo_contrato(uuid,uuid) is 'Analista de contrato: cadena de upgrade o respaldo, seguido de la regla de baja usando asesor_perfil_id del cliente actual del contrato.';
comment on function private.analista_efectivo_cierre(uuid) is 'Analista de cierre externo: regla de baja sobre vendedor_id usando responsable_relacion_id de coalesce(cierre.inversionista_id, lead.inversionista_id).';

comment on function crm.cierres_externos_fn(date) is 'Cierres en cooperativas: filas históricas y del mes (tope 200), conteos, totales y desglose por empresa. BAJA DE ANALISTA (09/10/2026): ámbito, vendedor_id y vendedor_nombre por el analista efectivo; teléfono vivo y exclusión de demo conservados.';
do $ensayo$
declare
  v_t0 timestamptz;
  v_ms_cartera numeric;
  v_ms_capital numeric;
  v_resumen text;
  v_001570 text;
  v_noelia text;
begin
  if to_regclass('pg_temp.baja_esperado') is null then
    raise exception 'ENSAYO: la migración ya estaba aplicada (no hay oráculo que mostrar)';
  end if;
  v_t0 := clock_timestamp();
  perform count(*) from private.cartera_f5_fuentes();
  v_ms_cartera := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(*) from private.capital_episodios('2026-10-01 00:00-05', '2026-11-01 00:00-05', true, '{}');
  v_ms_capital := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  select string_agg(format('%s: %s → %s = %s filas', r.origen, coalesce(pa.nombre_completo, r.analista::text),
           coalesce(pe.nombre_completo, r.esperado::text), r.filas), ' | ' order by r.origen, pa.nombre_completo, pe.nombre_completo)
    into v_resumen
  from (select origen, analista, esperado, count(*) as filas from pg_temp.baja_esperado
        where analista is distinct from esperado group by 1, 2, 3) r
  left join public.perfiles pa on pa.id = r.analista
  left join public.perfiles pe on pe.id = r.esperado;
  select string_agg(distinct coalesce(p.nombre_completo, '?'), ', ') into v_001570
  from private.capital_episodios('-infinity', 'infinity', true, '{}') k
  join public.contratos c on c.id = k.contrato_id and c.numero_contrato = '2026-01-001570'
  left join public.perfiles p on p.id = k.analista_id;
  select string_agg(format('%s %s', k.monto, coalesce(p.nombre_completo, '?')), ', ' order by k.fecha) into v_noelia
  from private.capital_episodios('2026-09-01 00:00-05', '2026-10-01 00:00-05', true, '{}') k
  join crm.cierres_externos ce on ce.id = k.cierre_externo_id
  join public.perfiles pv on pv.id = ce.vendedor_id and pv.nombre_completo = 'NOELIA SALAZAR RUIZ'
  left join public.perfiles p on p.id = k.analista_id;
  raise exception 'ENSAYO OK (se deshizo todo). Movidas: %. || 2026-01-001570 cuenta a: %. || Cooperativas de Noelia en setiembre: %. || Tiempo: cartera_f5_fuentes % ms, capital de octubre % ms.',
    coalesce(v_resumen, 'ninguna'), coalesce(v_001570, '?'), coalesce(v_noelia, 'ninguna'), v_ms_cartera, v_ms_capital;
end $ensayo$;
