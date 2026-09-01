-- ROLLBACK de ATR-4 (20260901180000) — restaura los 8 cuerpos PRE-ATR-4 AL BYTE.
-- ⚠️ La fila 20260901180000 del registro NO se borra aqui: retirarla A MANO.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Anti-pisado: solo se revierte LO QUE ATR-4 dejo.
do $$
declare v_fn constant text[][] := array[
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '38c99b1bd6e8ae0bc8bb0f93d5487ce8'],
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', '6d5ccff20d28d767ebd6efdf851806ac'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'fdf2a8723406446f7c2597aaaad9e106'],
    array['private.contratos_afectados_por_anulacion(uuid)',                   'f65428e6aa50b7a68a2082dea52a6cb8'],
    array['crm.metricas_vencimientos_fn(integer)',                             '4e7751a6c644a9c120ae155035e70561'],
    array['public.directorio_ranking_analistas()',                             '2f41fe29d1c5fa991fa7855336edefa2'],
    array['public.metricas_directorio()',                                      '048fb9e9c3f6163c768028f23e82ec91'],
    array['crm.cierres_externos_fn(date)',                                     'd78d4b5152ed0cc3f55a9c4fea66f15f']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback ATR-4: % NO tiene el cuerpo de ATR-4 (huella %) — investigar antes de revertir', v_fila[1], v_h;
    end if;
  end loop;
end $$;

-- CANDADO DE MUNDO: este rollback restaura la semantica PRE-ATR-4 (que quita
-- capital al anular). Solo es seguro con CERO anulaciones reales: si ya nacio
-- una con la regla nueva, revertir seria reescribirle el dinero — en ese caso
-- se corrige HACIA DELANTE con una migracion, no con este guion.
do $rb_mundo$
declare v_n int;
begin
  select count(*) into v_n from crm.cierres_avance_anulados;
  if v_n <> 0 then
    raise exception 'rollback ATR-4: hay % anulaciones de Avance — este rollback solo vale con 0; corregir hacia delante', v_n;
  end if;
  select count(*) into v_n from crm.ajustes_mes_cerrado;
  if v_n <> 0 then
    raise exception 'rollback ATR-4: hay % deudas registradas — corregir hacia delante', v_n;
  end if;
  select count(*) into v_n from crm.cierres_externos where anulado_en is not null
    and id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid;
  if v_n <> 0 then
    raise exception 'rollback ATR-4: hay % coop(s) anulada(s) REAL(es) — corregir hacia delante', v_n;
  end if;
end $rb_mundo$;

CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $rb_capital$
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
    coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id),
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
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
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
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
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$rb_capital$;

CREATE OR REPLACE FUNCTION private.produccion_mes_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo_id uuid)
 RETURNS TABLE(vendedor_id uuid, categoria text, moneda text, contratos_real integer, capital_real numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $rb_produccion$
  with anulados as materialized (
    -- Los cierres anulados y, sobre todo, A QUIEN se le habia acreditado cada
    -- uno. Conjunto diminuto por definicion, asi que conduce el `exists` de
    -- abajo en vez de recorrer leads por cada contrato.
    --
    -- `acreditado_a` cae al ANALISTA DEL LEDGER cuando el lead ya no declara
    -- vendedor. Es deliberado: `crm.leads.vendedor_id` es MUTABLE (gerencia
    -- puede devolver un lead a la cola global) y usarlo solo dejaria la
    -- anulacion inerte justo cuando mas falta hace. El ledger es inmutable y es
    -- ademas la MISMA fuente de la que sale el numerador de la conversion, asi
    -- que las dos mitades castigan a la misma persona por construccion.
    select
      l.id,
      coalesce(
        (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
        private.vendedor_acreditado_del_cierre(l.id)
      ) as acreditado_a
    from crm.leads l
    where l.id in (
      select ca.lead_id from crm.cierres_avance_anulados ca
      union all
      select ce.lead_id from crm.cierres_externos ce where ce.anulado_en is not null
    )
  ), contratos_base as materialized (
    -- public.contratos es la confirmación canónica. El lateral resume todos los
    -- enlaces explícitos sin duplicar el contrato y detecta los legacy ambiguos
    -- que apuntan a vendedores distintos: esos quedan sin atribuir.
    select
      c.id,
      c.categoria,
      c.moneda,
      c.capital,
      c.creado_por,
      c.analista_cierre_id,
      coalesce(enlaces.tiene_vendedor_explicito,false)
        as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos,0) as vendedores_distintos,
      enlaces.vendedor_unico
    from (select k.contrato_id as id, k.categoria, k.moneda,
                 k.monto as capital, k.registrado_por as creado_por,
                 k.analista_id as analista_cierre_id,
                 (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
          from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
          where k.tipo like 'contrato_%' and k.medida = 'stock') c
    left join lateral (
      select
        count(*) filter(where lead.vendedor_id is not null)>0
          as tiene_vendedor_explicito,
        count(distinct lead.vendedor_id)
          filter(where lead.vendedor_id is not null)::integer
          as vendedores_distintos,
        case
          when count(distinct lead.vendedor_id)
            filter(where lead.vendedor_id is not null)=1
          then min(lead.vendedor_id::text)
            filter(where lead.vendedor_id is not null)::uuid
        end as vendedor_unico
      from crm.leads lead
      where lead.contrato_id=c.id
    ) enlaces on true
    where c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
      and c.fecha_cierre_comercial < (p_fin at time zone 'America/Lima')::date
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
  ), atribuidos as materialized (
    -- La atribución explícita es autoritativa: si existe pero no pertenece al
    -- snapshot del mes, no cae silenciosamente al autor. El autor inmutable se
    -- usa solo cuando el contrato no tiene vendedor explícito. metas_vendedor
    -- impide que supervisores u otros actores se apropien de la producción.
    select
      base.id,
      case
        -- P-055 F3.5b: si la venta tiene analista, es SUYA — validada contra el
        -- cuadro de metas del mes, igual que todo lo demas. Fuera del cuadro,
        -- sin atribucion: NUNCA cae a otro actor.
        when base.analista_cierre_id is not null then meta_analista.vendedor_id
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,
      base.categoria,
      base.moneda,
      base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id=p_periodo_id
     and meta_lead.vendedor_id=base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=p_periodo_id
     and meta_autor.vendedor_id=base.creado_por
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id=p_periodo_id
     and meta_analista.vendedor_id=base.analista_cierre_id
  ), neutralizados as materialized (
    -- Los pares (contrato, vendedor) que dejan de acreditar. La REGLA vive en
    -- `private.contratos_afectados_por_anulacion` y NO se reescribe aqui: la
    -- misma funcion la usa la RPC para decir `afecta_cuota`, y escrita dos veces
    -- las dos divergen — es la leccion que ya costo dos rondas esta semana.
    select ca as contrato_id, an.acreditado_a as vendedor_id
    from anulados an
    cross join lateral private.contratos_afectados_por_anulacion(an.id) ca
  ), contratos_confirmados as materialized (
    -- 2026-08-13 · SOLO SE LE PUEDE QUITAR EL MERITO A QUIEN LO TIENE.
    --
    -- La anulacion se aplica DESPUES de atribuir, y solo cuando el vendedor
    -- atribuido ES la persona a la que se le habia acreditado el cierre
    -- anulado. Las dos claves no son la misma: la exclusion se decide por
    -- CLIENTE (el unico enlace que el flujo real crea) pero el merito se paga
    -- por AUTOR del contrato. Comparar solo por cliente castigaba a quien no
    -- habia hecho nada: si ese cliente RENUEVA meses despues con otro vendedor,
    -- anular el cierre viejo le borraba a ese otro su venta legitima, en un mes
    -- ya cerrado y sin dejar rastro. Con flujos normales, sin nada raro.
    --
    -- Neutralizar aqui (y no excluir el contrato en `contratos_base`) conserva
    -- ademas la garantia original: `reales` filtra `vendedor_id is not null`,
    -- asi que el contrato desaparece en vez de CAER AL AUTOR — que era el
    -- «regalo» que se midio y se descarto al disenar esto.
    select
      a.id,
      case
        when a.vendedor_id is not null and exists (
          select 1 from neutralizados n
          where n.contrato_id = a.id
            and n.vendedor_id = a.vendedor_id
        ) then null
        else a.vendedor_id
      end as vendedor_id,
      a.categoria,
      a.moneda,
      a.capital
    from atribuidos a
  ), externos_confirmados as materialized (
    -- Cierres en cooperativas (Qorilazo/Prodelco): suman a la cuota del mes
    -- como categoría 'nuevo', en SU moneda (PEN/USD jamás se suman), atribuidos
    -- al vendedor_id FOTO del cierre y validados contra el snapshot de metas
    -- del mes — el MISMO contrato que un contrato Avance: fuera del snapshot ⇒
    -- sin atribución, nunca cae a otro actor (el JOIN hace ambas cosas).
    -- Ventana por creado_en: la fecha del cierre es automática y no se
    -- retro-data, así que el mes del cierre es el mes real.
    select
      mv.vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
    from (select k.cierre_externo_id as id, k.analista_id as vendedor_id,
                 k.moneda, k.monto, k.anulado,
                 k.fecha as creado_en
          from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
          where k.tipo = 'cooperativa') ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin
      -- Un cierre anulado por gerencia (fraude o error) deja de pagar. La fila
      -- sigue ahi porque es el ancla de legalidad del lead convertido, pero no
      -- es dinero. Su gemelo en la conversion vive en
      -- private.conversion_mensual_por_vendedor.
      and not ce.anulado
  )
  select confirmados.vendedor_id, confirmados.categoria, confirmados.moneda,
    count(*)::integer as contratos_real,
    coalesce(sum(confirmados.capital),0) as capital_real
  from (
    select cc.vendedor_id, cc.categoria, cc.moneda, cc.capital
    from contratos_confirmados cc
    where cc.vendedor_id is not null
    union all
    select ec.vendedor_id, ec.categoria, ec.moneda, ec.capital
    from externos_confirmados ec
  ) confirmados
  group by confirmados.vendedor_id, confirmados.categoria, confirmados.moneda
$rb_produccion$;

CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $rb_registrar$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_meta_id     uuid;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  -- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;

  -- La ventana del mes sellado y su cuadro de metas: los dos los necesita la
  -- rama de cooperativas para reproducir la regla del mes abierto.
  v_ini := v_periodo::timestamp at time zone 'America/Lima';
  v_fin := (v_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  select mp.id into v_meta_id
  from crm.meta_periodos mp
  where mp.periodo = v_periodo
  order by mp.revision desc
  limit 1;

  -- Y lo que valia en capital: todo lo que deja de acreditar, con la MISMA
  -- regla que la cuota. PEN y USD por separado -una deuda en soles no se paga
  -- con produccion en dolares- y ademas desglosado por categoria, que es la
  -- casilla exacta de la que habra que descontarlo.
  --
  -- Los totales y el desglose salen de UNA sola consulta a proposito: antes
  -- eran dos y nada garantizaba que cuadraran, mientras `saldar_ajustes`
  -- descuenta casilla a casilla leyendo el desglose.
  with piezas as (
    -- (a) Los contratos Avance que dejan de acreditar. SIN los de prueba
    --     (hallazgo A2): un contrato demo nunca sumo capital -la migracion
    --     20260829182000 lo saca de produccion_mes_por_vendedor-, asi que
    --     anularlo no puede generar deuda. Sin este filtro renaceria la misma
    --     asimetria mes abierto/mes sellado que esta migracion vino a matar.
    select k.categoria::text as categoria, k.moneda::text as moneda, k.monto as capital
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz,
                                   true, '{}'::uuid[]) k
      on k.contrato_id = x and k.tipo like 'contrato_%' and k.medida = 'stock'

    union all

    -- (b) 2026-08-29 · Los cierres en COOPERATIVA del mismo lead que ya estan
    --     anulados. No tienen fila en `public.contratos`, asi que sin esta rama
    --     la sancion se quedaba a medias: el mes abierto si le quitaba el
    --     capital al analista y el mes sellado no.
    --     Regla copiada de `private.produccion_mes_por_vendedor`, bloque
    --     `externos_confirmados`, condicion por condicion.
    select 'nuevo'::text, ce.moneda::text, ce.monto
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and ce.anulado_en is not null
      and ce.vendedor_id = v_acreditado
      and ce.creado_en >= v_ini
      and ce.creado_en <  v_fin
      and exists (
        select 1 from crm.metas_vendedor mv
        where mv.meta_periodo_id = v_meta_id
          and mv.vendedor_id = ce.vendedor_id
      )
  ), agrupado as (
    select p.categoria, p.moneda,
           sum(p.capital)  as capital,
           count(*)::int   as contratos
    from piezas p
    group by p.categoria, p.moneda
  )
  select
    coalesce(sum(a.capital) filter (where a.moneda = 'PEN'), 0),
    coalesce(sum(a.capital) filter (where a.moneda = 'USD'), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'categoria',  a.categoria,
      'moneda',     a.moneda,
      'capital',    a.capital,
      'contratos',  a.contratos)), '[]'::jsonb)
  into v_pen, v_usd, v_detalle
  from agrupado a;

  -- Un cierre que no valia nada no genera deuda.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;
$rb_registrar$;

CREATE OR REPLACE FUNCTION private.contratos_afectados_por_anulacion(p_lead_id uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $rb_afectados$
  select c.id
  from crm.leads l
  cross join lateral (
    -- La FOTO manda. El calculo vivo solo sirve de respaldo: para cierres en
    -- cooperativa (que no pasan por esta tabla) y para responder ANTES de anular.
    select coalesce(
      (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
      private.vendedor_acreditado_del_cierre(l.id)
    ) as acreditado_a
  ) q
  join public.contratos c
    on (
      -- (a) enlace directo, cuando alguien lo rellena (legado o manual)
      c.id = l.contrato_id
      -- (b) el enlace del flujo REAL: el lead apunta al CLIENTE.
      or (l.perfil_id is not null
          and l.perfil_id = c.cliente_id
          and l.convertido_en is not null
          -- SUELO: un contrato ANTERIOR a la conversion no lo produjo este
          -- cierre. `crm.convertir_lead` admite un cliente que YA existia, asi
          -- que su cartera previa es de otra historia comercial y no se toca.
          and c.creado_en >= l.convertido_en
          -- TECHO: y deja de reclamar en cuanto ese mismo cliente vuelve a
          -- cerrarse. Sin esto un cierre anulado se quedaba con TODO el futuro
          -- del cliente para siempre — incluida la venta legitima que ese mismo
          -- vendedor le hiciera un ano despues.
          and not exists (
            select 1
            from crm.leads l_post
            where l_post.perfil_id = l.perfil_id
              and l_post.id <> l.id
              and l_post.convertido_en is not null
              -- Orden TOTAL, no parcial: `now()` es constante dentro de una
              -- transaccion, asi que dos conversiones del mismo cliente pueden
              -- empatar al microsegundo. Con `>` a secas ninguna cerraria el
              -- techo de la otra y AMBAS reclamarian los mismos contratos.
              and (l_post.convertido_en, l_post.id) > (l.convertido_en, l.id)
              and l_post.convertido_en <= c.creado_en
          ))
    )
   -- Y solo se le quita a quien lo tiene: el contrato debe estar acreditado a la
   -- misma persona a la que se le acredito el cierre anulado.
   and c.creado_por = q.acreditado_a
   -- Lo que la cuota NO mira, esto tampoco puede prometerlo: sin estos dos
   -- filtros, un contrato en otra moneda o de categoria no contable entraba en
   -- `contratos_afectados` y ponia `afecta_cuota` en true sin que bajara un sol.
   and c.categoria in ('nuevo','renovacion','upgrade')
   and c.moneda in ('PEN','USD')
   -- Y la MISMA regla de ambiguedad que aplica la cuota: un contrato enlazado a
   -- leads de vendedores DISTINTOS ya queda sin atribuir alli, asi que anular no
   -- movera un sol. Sin esto, `afecta_cuota` decia true y no bajaba nada.
   and not exists (
     select 1
     from crm.leads le
     where le.contrato_id = c.id
       and le.vendedor_id is not null
     having count(distinct le.vendedor_id) > 1
   )
  where l.id = p_lead_id
$rb_afectados$;

CREATE OR REPLACE FUNCTION crm.metricas_vencimientos_fn(p_dias integer DEFAULT 90)
 RETURNS TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $rb_venc$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', e.fecha_vencimiento))::date as mes,
    e.moneda,
    count(*)::bigint as contratos_por_vencer,
    sum(e.monto)     as capital_por_vencer
  from private.capital_episodios(
         '-infinity'::timestamptz,
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         or (e.tipo = 'cooperativa' and e.estado = 'vigente'))
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      -- ATR-3 (decision de Miguel 31/08): la lente ENSEÑA por quien se lleva la
      -- produccion (el analista del episodio; con ATR-2 sera el de la cadena),
      -- no por el archivador del dueño. Sin analista -> no cuenta a nadie
      -- (invariante F3.5b); gerencia/lector global lo ve todo igual.
      or (e.tipo like 'contrato_%' and e.analista_id = any (a.ids))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$rb_venc$;

CREATE OR REPLACE FUNCTION public.directorio_ranking_analistas()
 RETURNS TABLE(analista_id uuid, nombre text, capital_pen numeric, capital_usd numeric, n_clientes bigint, n_contratos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $rb_rank$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  -- DECISION A (30/08): los contratos acreditan al asesor del cliente (como
  -- siempre en esta pantalla); las cooperativas acreditan a SU analista.
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0),
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='USD'),0),
         COUNT(DISTINCT e.cliente_id) FILTER (WHERE e.cliente_id IS NOT NULL),
         COUNT(e.contrato_id)
  FROM private.capital_episodios(
         '-infinity'::timestamptz, 'infinity'::timestamptz,
         true, '{}'::uuid[]) e
  LEFT JOIN perfiles cli ON cli.id = e.cliente_id
  JOIN perfiles a ON a.rol = 'analista'
    AND a.id = CASE WHEN e.tipo = 'cooperativa' THEN e.analista_id
                    ELSE cli.asesor_perfil_id END
  WHERE e.medida = 'stock'
    AND ((e.tipo LIKE 'contrato_%' AND e.estado='activo')
         OR (e.tipo = 'cooperativa' AND e.estado='vigente'))
  GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0) DESC;
END;
$rb_rank$;

CREATE OR REPLACE FUNCTION public.metricas_directorio()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $rb_mdir$
DECLARE
  v jsonb;
  hoy date := (now() AT TIME ZONE 'America/Lima')::date;
  inicio_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Lima'))::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  WITH episodios AS (
    -- DECISION A (30/08): el Directorio ve el negocio COMPLETO — contratos
    -- Avance y cierres en cooperativas vigentes, de una sola calculadora.
    SELECT * FROM private.capital_episodios(
      '-infinity'::timestamptz, 'infinity'::timestamptz,
      true, '{}'::uuid[])
    WHERE medida = 'stock'
      AND (tipo LIKE 'contrato_%' OR tipo = 'cooperativa')
  ),
  activos AS (
    SELECT contrato_id AS id, cliente_id, moneda, monto AS capital,
           (fecha AT TIME ZONE 'America/Lima')::date AS fecha_cierre_comercial
    FROM episodios
    WHERE estado IN ('activo','vigente')
  ),
  aum AS (
    SELECT moneda,
           COALESCE(SUM(capital),0) AS total,
           COALESCE(SUM(capital) FILTER (WHERE fecha_cierre_comercial >= inicio_mes),0) AS captado_mes
    FROM activos GROUP BY moneda
  ),
  cuotas AS (
    SELECT cp.*, c.moneda
    FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id
    WHERE c.estado IN ('activo','vencido')
      AND cp.estado <> 'trasladado'
  ),
  vencidas AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado' AND fecha_programada < hoy
  ),
  pendientes AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado'
  )
  SELECT jsonb_build_object(
    'generado_en', now(),
    'aum', (
      SELECT COALESCE(jsonb_object_agg(moneda, jsonb_build_object(
        'total', total,
        'captado_mes', captado_mes,
        'var_pct', CASE WHEN (total - captado_mes) > 0
                        THEN round((captado_mes / (total - captado_mes) * 100)::numeric, 1)
                        ELSE 0 END
      )), '{}'::jsonb) FROM aum
    ),
    'clientes', jsonb_build_object(
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos WHERE cliente_id IS NOT NULL),
      'nuevos_mes', (SELECT COUNT(*) FROM perfiles WHERE rol='cliente' AND creado_en >= inicio_mes)
    ),
    'contratos', jsonb_build_object(
      'activos', (SELECT COUNT(*) FROM activos),
      'ticket_promedio', (
        SELECT COALESCE(jsonb_object_agg(moneda, prom),'{}'::jsonb) FROM (
          SELECT moneda, round(AVG(capital)::numeric,2) AS prom FROM activos GROUP BY moneda
        ) t
      )
    ),
    'cobranza', jsonb_build_object(
      'pct_al_dia', (
        SELECT CASE WHEN COUNT(*)=0 THEN 100
               ELSE round((COUNT(*) FILTER (WHERE estado='pagado' OR fecha_programada >= hoy)::numeric
                           / COUNT(*) * 100), 1) END
        FROM cuotas WHERE fecha_programada <= hoy
      ),
      'cuotas_vencidas', (SELECT COUNT(*) FROM vencidas),
      'monto_vencido', (
        SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
          SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto FROM vencidas GROUP BY moneda
        ) t
      )
    ),
    'intereses_pagados', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT c.moneda, COALESCE(SUM(cp.monto_pagado),0) AS monto
        FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id=cp.contrato_id
        WHERE cp.tipo IN ('retorno','devolucion') AND cp.estado='pagado'
        GROUP BY c.moneda
      ) t
    ),
    'caja_90d', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto
        FROM pendientes WHERE fecha_programada BETWEEN hoy AND (hoy + 90)
        GROUP BY moneda
      ) t
    ),
    'crecimiento', (
      SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'mes', to_char(m, 'YYYY-MM'),
          'PEN', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='PEN' AND e.mes_comercial = m::date),0),
          'USD', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='USD' AND e.mes_comercial = m::date),0)
        ) AS row
        FROM generate_series(date_trunc('month', hoy) - interval '11 months',
                             date_trunc('month', hoy), interval '1 month') m
      ) s
    )
  ) INTO v;

  RETURN v;
END;
$rb_mdir$;

CREATE OR REPLACE FUNCTION crm.cierres_externos_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $rb_cef$
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
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where v_global or ce0.vendedor_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or ce.vendedor_id = any(v_visibles)
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
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where ce0.creado_en >= v_ini and ce0.creado_en < v_fin
          and (v_global or ce0.vendedor_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where ce.creado_en >= v_ini and ce.creado_en < v_fin
        and (v_global or ce.vendedor_id = any(v_visibles))
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
        where (v_global or ce.vendedor_id = any(v_visibles))
          and ce.anulado_en is null   -- los anulados no son dinero
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
        select ce.vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        left join public.perfiles p on p.id = ce.vendedor_id
        where ce.creado_en >= v_ini and ce.creado_en < v_fin
          and (v_global or ce.vendedor_id = any(v_visibles))
          and ce.anulado_en is null   -- los anulados no son dinero
        group by ce.vendedor_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$rb_cef$;

-- Re-sellos de vuelta con las razones VIVAS EXACTAS (leidas de produccion el
-- 01/09 — la v1 de este guion inventaba 2 de 3 y la refutacion lo cazo).

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure),
       razon = $razon_rb$Consumidor del nucleo de CAPITAL (F4): su join a crm.leads es para atribuir episodios, no para contar leads como metrica.$razon_rb$
 where objeto = 'private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)';
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure),
       razon = 'El numerador del ajuste sale del EPISODIO del nucleo (F6.c). La rama de coops anuladas queda cruda POR SEMANTICA DE LA F4: el nucleo de capital solo carga capital que existe y la deuda necesita el monto ORIGINAL de la coop anulada; la deriva de esa regla copiada la vigila este mismo trinquete (produccion_mes_por_vendedor tambien esta sellada).'
 where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)';
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p where p.oid = 'private.contratos_afectados_por_anulacion(uuid)'::regprocedure),
       razon = $razon_rb2$Operativa de la anulacion: localiza contratos/leads afectados para retroceder etapa; no responde preguntas de metricas.$razon_rb2$
 where objeto = 'private.contratos_afectados_por_anulacion(uuid)';
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'crm.cierres_externos_fn(date)'::regprocedure),
       razon = $razon_rb3$Lista las cooperativas del mes para gerencia: es un listado operativo con su conteo de apoyo, no una calculadora de conversion; el capital de coops ya vive en capital_episodios.$razon_rb3$
 where objeto = 'crm.cierres_externos_fn(date)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

update private.analista_vigencia_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(p.prosrc,
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'public.directorio_ranking_analistas()'::regprocedure),
       razon = $razon_v$No es una puerta de analista: usa rol = analista para SELECCIONAR a quien se rankea, y el acceso esta gateado por es_directorio() o es_admin().$razon_v$
 where objeto = 'public.directorio_ranking_analistas()';

-- Verificacion: los 8 volvieron AL BYTE y los guardianes quedan verdes.
do $$
declare v_fn constant text[][] := array[
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '90f1d8c2342becb94cc3d3e023227078'],
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['private.contratos_afectados_por_anulacion(uuid)',                   '2df41b523f953048184070d66d37cda4'],
    array['crm.metricas_vencimientos_fn(integer)',                             '54a9bf11bb4e0bbf0fc4d7c12bed7fcb'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['public.metricas_directorio()',                                      '1802e44a4f8b304df19b1e15cd3934a6'],
    array['crm.cierres_externos_fn(date)',                                     '31af3945063d671e3d181332df60750b']
  ];
  v_fila text[]; v_h text; v_verd text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback ATR-4: % no volvio al byte (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's') then
    raise exception 'rollback ATR-4: atributos del nucleo no volvieron';
  end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback ATR-4: analitica en rojo: %', v_verd; end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback ATR-4: vigencia en rojo: %', v_verd; end if;
end $$;

select 'ROLLBACK-ATR4-OK: los 8 cuerpos pre-ATR-4 restaurados al byte' as resultado;
commit;
