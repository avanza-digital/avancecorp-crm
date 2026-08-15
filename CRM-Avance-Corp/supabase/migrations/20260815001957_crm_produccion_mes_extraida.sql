-- ---------------------------------------------------------------------------
-- La produccion del mes (capital y contratos) deja de vivir dentro de la
-- funcion que la publica
-- ---------------------------------------------------------------------------
-- QUE HACE. Extrae de `crm.cumplimiento_metas_fn` el bloque que decide QUE
-- CAPITAL Y CUANTOS CONTRATOS le acreditan a cada vendedor en un mes, y lo pone
-- en `private.produccion_mes_por_vendedor`. `cumplimiento_metas_fn` pasa a
-- CONSUMIRLA. Ni una regla cambia: es un movimiento, no una reescritura.
--
-- POR QUE. Miguel decidio (2026-08-14) que el mes se CIERRE: llegado el dia 10
-- el CRM le saca una foto al mes —conversion, cumplimiento de meta y capital por
-- asesor— y a partir de ahi enseña la foto en vez de recalcular. Para sacar esa
-- foto hay que poder PEDIR esos numeros, y hoy no se puede: viven dentro de una
-- funcion que ademas recorta por `auth.uid()`, asi que un proceso de cierre que
-- la llamara recibiria «No autorizado» o, peor, el recorte de quien la invoque.
--
-- La alternativa era reimplementar la regla dentro del cierre. Es exactamente la
-- deuda que este esquema ya pago dos veces: la conversion llego a tener DOS
-- formulas (la del titular y la de la barra de metas) y costo una migracion
-- entera unificarlas; y `contratos_afectados_por_anulacion` nacio de que la
-- misma regla estaba escrita en la cuota y en la RPC, y divergieron. La regla se
-- escribe UNA vez.
--
-- Es el gemelo exacto de `private.conversion_mensual_por_vendedor`, que ya es el
-- nucleo unico de la conversion desde la migracion 20260813212332: mismo patron,
-- misma razon.
--
-- QUE NO HACE. No toca `public`. No cambia ninguna policy ni ningun grant. No
-- cambia el payload de `crm.cumplimiento_metas_fn` — el postflight lo comprueba
-- comparando el resultado ANTES y DESPUES sobre el mismo periodo.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight — de donde se extrae
-- ---------------------------------------------------------------------------
do $preflight$
begin
  -- El cuerpo del que se extrae. Si `cumplimiento_metas_fn` cambio desde que se
  -- escribio esta migracion, el bloque que se mueve podria no ser el mismo y el
  -- movimiento dejaria de ser inocuo. Obliga a mirar antes de aplicar.
  if (select md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cumplimiento_metas_fn')
     is distinct from '114e570780fc2c68baa0a455b910c4b9' then
    raise exception 'crm.cumplimiento_metas_fn cambio: revisar el bloque que esta migracion extrae antes de aplicar.';
  end if;

  -- Las tres piezas que el bloque extraido invoca por nombre. Si alguna
  -- desapareciera, la funcion nueva las reimplementaria en silencio.
  if to_regprocedure('private.contratos_afectados_por_anulacion(uuid)') is null then
    raise exception 'Falta private.contratos_afectados_por_anulacion: la regla de que contratos dejan de acreditar.';
  end if;
  if to_regprocedure('private.vendedor_acreditado_del_cierre(uuid)') is null then
    raise exception 'Falta private.vendedor_acreditado_del_cierre.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La produccion del mes, por vendedor
-- ---------------------------------------------------------------------------
-- Devuelve, por (vendedor, categoria, moneda), cuantos contratos le acreditan y
-- cuanto capital. Es EL MISMO cuerpo que hasta hoy vivia en la CTE `reales` de
-- `crm.cumplimiento_metas_fn`, con sus comentarios intactos: lo que sigue es un
-- traslado literal.
--
-- ⚠️ NO RECORTA POR AMBITO, a proposito. Devuelve la empresa entera y el recorte
-- lo hace quien llama: `cumplimiento_metas_fn` con su CTE `visibles`, y el
-- cierre de mes con nada, porque una foto de lo que se pago tiene que ser
-- completa. Recortar aqui obligaria a pasar el ambito y abriria la puerta a que
-- los dos consumidores recortaran distinto.
--
-- SECURITY DEFINER porque lee `public.contratos` y `crm.metas_vendedor`, que sus
-- llamadores no alcanzan por RLS; y porque sus dos consumidores ya son DEFINER y
-- estan a su vez cerrados por un gate explicito. No la puede invocar nadie mas:
-- vive en `private`, cuyo USAGE no tiene ni `authenticated` ni `anon`.
create or replace function private.produccion_mes_por_vendedor(
  p_ini timestamptz,
  p_fin timestamptz,
  p_periodo_id uuid
)
returns table (
  vendedor_id uuid,
  categoria text,
  moneda text,
  contratos_real integer,
  capital_real numeric
)
language sql
stable
security definer
set search_path = ''
as $$
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
      coalesce(enlaces.tiene_vendedor_explicito,false)
        as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos,0) as vendedores_distintos,
      enlaces.vendedor_unico
    from public.contratos c
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
    where c.creado_en>=p_ini and c.creado_en<p_fin
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
    from crm.cierres_externos ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin
      -- Un cierre anulado por gerencia (fraude o error) deja de pagar. La fila
      -- sigue ahi porque es el ancla de legalidad del lead convertido, pero no
      -- es dinero. Su gemelo en la conversion vive en
      -- private.conversion_mensual_por_vendedor.
      and ce.anulado_en is null
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
$$;

comment on function private.produccion_mes_por_vendedor(timestamptz, timestamptz, uuid) is
  'Capital y contratos que le acreditan a cada vendedor en un mes, por categoria y moneda. '
  'Nucleo UNICO: lo consumen crm.cumplimiento_metas_fn (que lo recorta por ambito) y el '
  'cierre de mes (que no lo recorta, porque una foto de lo pagado es completa). '
  'Extraida de cumplimiento_metas_fn el 2026-08-15 sin cambiar ninguna regla.';

revoke all on function private.produccion_mes_por_vendedor(timestamptz, timestamptz, uuid) from public;

-- ---------------------------------------------------------------------------
-- 2. `cumplimiento_metas_fn` pasa a consumirla
-- ---------------------------------------------------------------------------
-- El unico cambio del cuerpo: las seis CTE que calculaban la produccion
-- desaparecen y `reales` se convierte en una llamada. Todo lo demas —el gate,
-- la validacion del periodo, las conversiones, `visibles` y el JSON— queda
-- literalmente igual.
create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_factor numeric;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);
  v_factor:=private.peso_referido_conversion(p_periodo);

  with reales as (
    -- La produccion del mes. Vivia aqui dentro en seis CTE y ahora es una
    -- llamada: la MISMA regla, en un solo sitio, para que el cierre de mes
    -- pueda sellar exactamente lo que esta pantalla publica.
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), conversiones as (
    -- MIGRACION B: la conversion de las METAS deja de tener formula propia y
    -- CONSUME la misma funcion que pinta la pantalla. Antes esta CTE calculaba
    -- convertidos/RESUELTOS sin ponderar, asi que el mismo asesor tenia dos
    -- porcentajes distintos a 300 px de distancia: el titular ponderado y la
    -- barra de su propia meta. Reimplementar una regla de negocio dos veces es
    -- la deuda; esto la borra.
    --
    -- El filtro de cierres ANULADOS ya no se escribe aqui: viaja dentro de
    -- private.conversion_mensual_por_vendedor, que es ahora la unica definicion.
    --
    -- p_global => true A PROPOSITO, y la razon NO es la que parece. Recortar
    -- aqui ademas de en `visibles` daria EL MISMO conjunto de filas (medido:
    -- p_global=true/p_visibles={} y p_global=false/p_visibles={A} devuelven
    -- filas identicas para A), asi que no se hace por no perder a nadie.
    --
    -- Se hace porque para el LECTOR GLOBAL `private.vendedor_ids_visibles`
    -- devuelve VACIO (su rol_crm es NULL y la funcion retorna sin filas): un
    -- p_visibles construido con ella le dejaria todos los numeros en blanco.
    -- `crm.conversion_mensual_fn` resuelve lo mismo con su propio v_global.
    --
    -- Es seguro porque este nucleo no tiene ni un agregado transversal: todas
    -- sus CTE agrupan por analista_id y devuelve como mucho UNA fila por
    -- analista, asi que el valor de un vendedor no depende de quien mas este en
    -- el conjunto. El total de empresa se calcula en `conversion_mensual_fn`,
    -- no aqui — por eso ALLI el recorte tiene que ir antes y aqui no. Quien
    -- manda es la CTE `visibles` (metas_vendedor ∩ vendedor_ids_visibles), que
    -- es la tabla conductora del join.
    select cm.analista_id as vendedor_id,
      (cm.cierres_no_referidos+cm.cierres_referidos)::integer as convertidos,
      cm.divisor::integer as resueltos,
      cm.numerador,
      cm.cierres_no_referidos,
      cm.cierres_referidos,
      cm.conversion_pct as conversion_real
    from private.conversion_mensual_por_vendedor(
      v_ini,v_fin,true,'{}'::uuid[],v_factor) cm
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_recibidos_ponderado'
    ),
    'ponderacion_referido',v_factor,
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'numerador',coalesce(cv.numerador,0),
      'cierres_no_referidos',coalesce(cv.cierres_no_referidos,0),
      'cierres_referidos',coalesce(cv.cierres_referidos,0),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Postflight — el movimiento no cambio ningun numero
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_n integer;
begin
  -- La funcion nueva existe, es DEFINER y tiene el search_path fijado.
  select count(*) into v_n
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'produccion_mes_por_vendedor'
    and p.prosecdef
    and array_to_string(p.proconfig, ',') like '%search_path=%';
  if v_n <> 1 then
    raise exception 'private.produccion_mes_por_vendedor no quedo creada como DEFINER con search_path fijo (n=%)', v_n;
  end if;

  -- Y `cumplimiento_metas_fn` la INVOCA: si el reemplazo hubiera dejado el
  -- cuerpo viejo, esto lo caza. `strpos` y NO `like`: en LIKE el guion bajo es
  -- comodin de un caracter y casaria con cualquier cosa parecida (trampa que ya
  -- freno un despliegue correcto el 2026-08-14).
  if (select strpos(p.prosrc, 'produccion_mes_por_vendedor')
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cumplimiento_metas_fn') = 0 then
    raise exception 'crm.cumplimiento_metas_fn no consume la funcion extraida: quedo el cuerpo viejo.';
  end if;

  -- Y ya no lleva dentro el bloque que se movio.
  if (select strpos(p.prosrc, 'contratos_base')
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cumplimiento_metas_fn') > 0 then
    raise exception 'crm.cumplimiento_metas_fn conserva el calculo extraido: habria DOS definiciones de la produccion.';
  end if;
end;
$postflight$;

commit;

-- ---------------------------------------------------------------------------
-- VUELTA ATRAS
-- ---------------------------------------------------------------------------
-- `supabase/scripts/rollback-produccion-mes-extraida.sql` restaura el cuerpo
-- anterior de `crm.cumplimiento_metas_fn` (el del md5 anclado arriba) y borra
-- `private.produccion_mes_por_vendedor`. Es seguro mientras nadie mas la
-- consuma: en cuanto entre el cierre de mes, dejara de serlo.
