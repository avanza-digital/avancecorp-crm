-- Sustituto de crm.metricas_altas_analista_fn, que F7 Ola 2b demuele el 14/09.
-- Miguel lo pidio ANTES de borrar el viejo (no perder el reporte de gerencia).
--
-- QUE CAMBIA respecto al viejo (decidido por Miguel el 04/09):
--   Viejo: contaba PERFILES nuevos (rol='cliente') por el ASESOR anotado en la ficha,
--          por mes de creacion del perfil.
--   Nuevo: cuenta CONTRATOS NUEVOS (categoria='nuevo') por el analista que CIERRA,
--          por mes de CIERRE comercial (hora Lima), EXCLUYENDO cierres anulados.
--   => Los numeros NO calcaran al viejo, a proposito: otra unidad (contrato, no ficha),
--      otra fecha (cierre, no creacion) y otra atribucion (el que cierra, no el asesor).
--
-- POR QUE "el que cierra" == la politica ATR para un contrato NUEVO:
--   La atribucion canonica de una conversion es
--     coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id).
--   El resolutor de cadena SOLO sobre-escribe en UPGRADES (camina la cadena y gana el
--   ancestro 'upgrade'); para un contrato 'nuevo' no hay cadena, asi que cae a
--   analista_cierre_id. => "el que cierra" coincide con la politica del sistema para los
--   nuevos; no es una regla nueva ni divergente.
--
-- POR QUE anular NO cuenta (ATR-4, "solo la conversion, siempre"): anular es una SANCION,
--   asi que un contrato cuyo cierre fue anulado NO es un alta. La anulacion vive en un
--   ledger aparte (crm.cierres_avance_anulados / crm.cierres_externos.anulado_en) mapeado
--   por lead; aqui se REUSA el mapeo canonico private.contratos_afectados_por_anulacion,
--   no se reinventa.
--
-- FIDELIDAD: conteo VIVO (se recalcula al preguntar), igual que el viejo. NO usa el
--   sellado de meses de la cuota ni conversion_episodios (en refactor): solo helpers
--   estables. Es un reporte de gestion, no la foto congelada de la cuota.
--
-- Aditiva y sin efecto sobre lo vivo: crea UNA funcion nueva con nombre nuevo. No toca el
--   viejo (que sigue cerrado, en observacion) ni ningun objeto de public.

begin;
set local lock_timeout = '10s';

create or replace function crm.altas_nuevas_por_analista_fn(p_meses integer default 12)
returns table(mes date, analista_id uuid, analista_nombre text, altas bigint)
language sql
stable
security definer
set search_path to ''
as $fn$
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
    select x as contrato_id
    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    union
    select x
    from crm.cierres_externos ce
    cross join lateral private.contratos_afectados_por_anulacion(ce.lead_id) x
    where ce.anulado_en is not null
  ),
  base as (
    select
      (date_trunc('month', c.fecha_cierre_comercial at time zone 'America/Lima'))::date as mes,
      coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
    from public.contratos c
    where c.categoria = 'nuevo'
      and not c.es_demo
      and c.fecha_cierre_comercial is not null
      and not exists (select 1 from anulados an where an.contrato_id = c.id)
      and c.fecha_cierre_comercial >=
        ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
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
$fn$;

alter function crm.altas_nuevas_por_analista_fn(integer) owner to postgres;
revoke all on function crm.altas_nuevas_por_analista_fn(integer) from public;
grant execute on function crm.altas_nuevas_por_analista_fn(integer) to authenticated;

comment on function crm.altas_nuevas_por_analista_fn(integer) is
  'Altas de CONTRATOS NUEVOS (categoria=nuevo) por el analista que cierra '
  '(ATR: coalesce(analista_atribuido_cadena, analista_cierre_id)), por mes de cierre '
  'comercial en Lima, excluyendo cierres anulados. Sustituye a metricas_altas_analista_fn '
  '(F7 Ola 2b). Conteo VIVO, sin sellado de mes. Miguel 04/09.';

-- Postflight: la funcion existe, es SECURITY DEFINER, dueño postgres, y NO la puede
-- ejecutar el mundo (solo authenticated + postgres).
do $post$
declare v_oid regprocedure := 'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure;
begin
  if not (select prosecdef from pg_proc where oid = v_oid) then
    raise exception 'POSTFLIGHT: la funcion deberia ser SECURITY DEFINER';
  end if;
  if pg_get_userbyid((select proowner from pg_proc where oid = v_oid)) <> 'postgres' then
    raise exception 'POSTFLIGHT: dueño inesperado';
  end if;
  if exists (
    select 1
    from aclexplode((select coalesce(proacl, acldefault('f', proowner)) from pg_proc where oid = v_oid)) a
    where a.grantee = 0  -- PUBLIC
  ) then
    raise exception 'POSTFLIGHT: PUBLIC no debe tener EXECUTE';
  end if;
end;
$post$;

commit;
