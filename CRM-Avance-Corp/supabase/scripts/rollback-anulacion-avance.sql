-- ---------------------------------------------------------------------------
-- VUELTA ATRAS de la anulacion de cierres de AVANCE
-- ---------------------------------------------------------------------------
-- NO es una migracion y por eso NO vive en migrations/: con un timestamp
-- posterior se aplicaria sola en cualquier replay y desharia el arreglo.
-- Se ejecuta A MANO y solo si algo se rompe en produccion.
--
-- Deja las cosas como estaban justo antes: la cuota vuelve al cuerpo post-B
-- (md5(prosrc) = 0210e0daa1ee83896ec30d2948bb490f) y la pregunta de anulacion
-- vuelve a mirar SOLO cooperativas.
--
-- ⚠️ NO borra `crm.cierres_avance_anulados` ni `crm.anular_cierre_avance`: si
-- gerencia ya anulo algo, ese registro es la razon escrita que se le dio a una
-- persona. Tras revertir, esas anulaciones dejan de descontar (que es el punto
-- de revertir) pero la fila sigue ahi para saber que pasó.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

create or replace function private.cierre_externo_anulado(p_lead_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and ce.anulado_en is not null
  )
$$;

comment on function private.cierre_externo_anulado(uuid) is
  'TRUE si el lead tiene un cierre en cooperativa anulado por gerencia. Definicion UNICA de «anulado» para los dos numeradores de conversion (private.conversion_mensual_por_vendedor y la CTE conversiones de crm.cumplimiento_metas_fn): escrita dos veces, divergen.';

revoke all on function private.cierre_externo_anulado(uuid)
  from public, anon, authenticated, service_role;

create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
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

  with contratos_base as materialized (
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
    where c.creado_en>=v_ini and c.creado_en<v_fin
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
  ), contratos_confirmados as materialized (
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
      on meta_lead.meta_periodo_id=v_periodo_id
     and meta_lead.vendedor_id=base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=v_periodo_id
     and meta_autor.vendedor_id=base.creado_por
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
      on mv.meta_periodo_id=v_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=v_ini and ce.creado_en<v_fin
      -- Un cierre anulado por gerencia (fraude o error) deja de pagar. La fila
      -- sigue ahi porque es el ancla de legalidad del lead convertido, pero no
      -- es dinero. Su gemelo en la conversion vive en
      -- private.conversion_mensual_por_vendedor.
      and ce.anulado_en is null
  ), reales as (
    select vendedor_id,categoria,moneda,
      count(*)::integer as contratos_real,
      coalesce(sum(capital),0) as capital_real
    from (
      select vendedor_id,categoria,moneda,capital
      from contratos_confirmados
      where vendedor_id is not null
      union all
      select vendedor_id,categoria,moneda,capital
      from externos_confirmados
    ) confirmados
    group by vendedor_id,categoria,moneda
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
    --
    -- COSTE, anotado a proposito: al plegarse el predicado de ambito a `true`,
    -- cada llamada recorre el ledger del mes de TODA la empresa, tambien la de
    -- un vendedor suelto. Hoy es irrelevante (la base tiene 1-2 filas) pero
    -- renuncia a la indexabilidad que peleo la migracion A: revisar cuando
    -- entre la base fria (C2 del plan de escalabilidad).
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
$function$;

commit;
