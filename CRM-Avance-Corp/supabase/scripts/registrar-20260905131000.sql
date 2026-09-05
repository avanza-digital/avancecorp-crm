-- Registra 20260905131000 (crm_altas_nuevas_por_analista_v2) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/generar-registrador-altas.mjs leyendo la migracion
-- del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO aplicar la
-- migracion con `db query --linked --file`, DESPUES este registrador (el pin 1
-- se niega a registrar lo que no paso).
do $reg_altas$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_altas$-- Sustituto de crm.metricas_altas_analista_fn, que F7 Ola 2b demuele el 14/09.
-- Miguel lo pidio ANTES de borrar el viejo (no perder el reporte de gerencia).
--
-- v2: la v1 (20260905130000) se RETIRO sin aplicar. auditor-rls (04/09) la cazo con
--     un NO-GO: usaba `at time zone 'America/Lima'` sobre `fecha_cierre_comercial`,
--     que es un `date` -> en un servidor UTC el dia 1 se cae al mes anterior (footgun
--     documentado del proyecto). La seguridad estaba limpia; solo el conteo. v2 bucketea
--     y acota en espacio de FECHA, como private.capital_episodios.
--
-- QUE CAMBIA respecto al viejo (decidido por Miguel el 04/09):
--   Viejo: contaba PERFILES nuevos (rol='cliente') por el ASESOR de la ficha, por mes
--          de creacion.
--   Nuevo: cuenta CONTRATOS NUEVOS (categoria='nuevo') por el analista que CIERRA, por
--          mes de CIERRE comercial, EXCLUYENDO cierres anulados.
--   => Los numeros NO calcaran al viejo, a proposito: otra unidad, otra fecha, otra
--      atribucion.
--
-- POR QUE "el que cierra" == la politica ATR para un contrato NUEVO:
--   La atribucion canonica es coalesce(private.analista_atribuido_cadena(c.id),
--   c.analista_cierre_id); el resolutor de cadena SOLO sobre-escribe en UPGRADES, asi
--   que para un 'nuevo' cae a analista_cierre_id. No es una regla nueva ni divergente.
--
-- POR QUE anular NO cuenta (ATR-4, "solo la conversion, siempre"): anular es SANCION.
--   La anulacion vive en un ledger aparte (crm.cierres_avance_anulados /
--   crm.cierres_externos.anulado_en) mapeado por lead; aqui se REUSA el mapeo canonico
--   private.contratos_afectados_por_anulacion, no se reinventa.
--
-- FIDELIDAD: conteo VIVO (se recalcula al preguntar), igual que el viejo. NO usa el
--   sellado de meses de la cuota ni conversion_episodios (en refactor): solo helpers
--   estables. Es un reporte de gestion, no la foto congelada de la cuota.
--
-- Aditiva y sin efecto sobre lo vivo: crea UNA funcion nueva con nombre nuevo. No toca el
--   viejo (que sigue cerrado, en observacion) ni ALTERA ningun objeto de public (solo lo LEE).

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
    where ce.anulado_en is not null
  ),
  base as (
    -- 🔴 fecha_cierre_comercial ES `date` (el dia comercial de Lima). NUNCA
    --    `at time zone` sobre un date: en un servidor UTC el dia 1 se cae al mes
    --    anterior (footgun del proyecto). Se bucketea y se acota en espacio de FECHA,
    --    igual que private.capital_episodios.
    select
      (date_trunc('month', c.fecha_cierre_comercial))::date as mes,
      coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
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
$fn$;

alter function crm.altas_nuevas_por_analista_fn(integer) owner to postgres;
revoke all on function crm.altas_nuevas_por_analista_fn(integer) from public;
grant execute on function crm.altas_nuevas_por_analista_fn(integer) to authenticated;

comment on function crm.altas_nuevas_por_analista_fn(integer) is
  'Altas de CONTRATOS NUEVOS (categoria=nuevo) por el analista que cierra '
  '(ATR: coalesce(analista_atribuido_cadena, analista_cierre_id)), por mes de cierre '
  'comercial (espacio de fecha, sin tz), excluyendo cierres anulados. Sustituye a '
  'metricas_altas_analista_fn (F7 Ola 2b). Conteo VIVO, sin sellado de mes. Miguel 04/09.';

-- Postflight: seguridad + una GUARDA anti-regresion del footgun de fecha.
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
  -- Anti-footgun: el bucket en espacio de fecha DEBE caer en el mes calendario del
  -- cierre. Un `at time zone` sobre el date (la regresion de la v1) lo violaria.
  if exists (
    select 1 from public.contratos c
    where c.categoria = 'nuevo' and c.fecha_cierre_comercial is not null
      and (date_trunc('month', c.fecha_cierre_comercial))::date
          <> make_date(
               extract(year  from c.fecha_cierre_comercial)::int,
               extract(month from c.fecha_cierre_comercial)::int, 1)
  ) then
    raise exception 'POSTFLIGHT: el bucket mensual no cae en el mes del cierre (¿tz sobre un date?)';
  end if;
end;
$post$;

commit;
$mig_altas$;

  -- 1) PIN: lo que la migracion hizo ES verdad — la funcion existe. Si no,
  --    no se registra lo que no paso.
  if to_regprocedure('crm.altas_nuevas_por_analista_fn(integer)') is null then
    raise exception 'registrar altas: crm.altas_nuevas_por_analista_fn(integer) NO existe — aplicar la migracion antes de registrar';
  end if;

  -- 2) La version no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260905131000' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar altas: la version 20260905131000 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260905131000', 'crm_altas_nuevas_por_analista_v2', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transaccion entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260905131000' and name = 'crm_altas_nuevas_por_analista_v2'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar altas: la relectura no encontro la fila exacta';
  end if;
end $reg_altas$;
