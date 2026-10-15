-- REEXPRESIÓN DE SEPTIEMBRE 2026 — reversa: deshacer 01-reabrir.sql tal cual.
-- Vuelve a poner el sello y la foto del 11/10, devuelve a las acreditaciones sus
-- marcas de sello originales, devuelve las ventas en cooperativa registradas tarde
-- a su mes de registro (con su rastro) y reactiva el ciclo diario.
--
-- SOLO vale mientras septiembre siga abierto y NADA haya cambiado en sus datos
-- desde la reapertura (misma huella que guardó 01). Si ya se volvió a sellar, o
-- si se cargó, corrigió, anuló o retiró algo, restaurar la foto vieja perdería
-- capital o deuda (revisión Codex 14/10, P1 ×2): se niega y la salida es volver
-- a sellar con 02-resellar.sql o con la configuración de plazo de Gerencia.
-- Se ejecuta con: npx supabase db query --linked --file <este archivo>
begin;
set local lock_timeout = '10s';
-- to_jsonb(timestamptz) depende de TimeZone; 01 y 03 comparan ese texto (huella
-- y filas restauradas): ambos fijan UTC (revisión Codex r2).
set local timezone = 'UTC';
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-09-01' - date '2000-01-01')::integer);

create temp table _ahora on commit drop as
select
  -- [HUELLA-SEPTIEMBRE] inicio (copia exacta de 01-reabrir.sql)
  (select md5(concat_ws('#',
    (select string_agg(to_jsonb(c)::text, '|' order by c.id) from public.contratos c
      where c.fecha_cierre_comercial >= date '2026-09-01' and c.fecha_cierre_comercial < date '2026-10-01'),
    (select string_agg((to_jsonb(ca) - 'sellado_en' - 'incluida_en_sello' - 'ajuste_anulacion_en_sello'
                        - 'actualizado_en')::text, '|' order by ca.id)
      from crm.conversion_acreditaciones ca where ca.periodo_comercial = date '2026-09-01'),
    (select string_agg(to_jsonb(o)::text, '|' order by o.id) from crm.operaciones_cartera o
      where o.periodo = date '2026-09-01'),
    (select string_agg(to_jsonb(i)::text, '|' order by i.id) from crm.inversiones i
      where i.fecha_comercial >= date '2026-09-01' and i.fecha_comercial < date '2026-10-01'),
    (select string_agg(to_jsonb(a)::text, '|' order by a.id) from crm.cierres_avance_anulados a),
    (select string_agg(to_jsonb(ce)::text, '|' order by ce.id) from crm.cierres_externos ce
      where ce.anulado_en is not null
         or coalesce(ce.fecha_comercial, (ce.creado_en at time zone 'America/Lima')::date)
              between date '2026-09-01' and date '2026-09-30')
  ))) as huella;
  -- [HUELLA-SEPTIEMBRE] fin

do $pre$
declare v_sellos integer; v_fotos integer; v_huella text;
begin
  if to_regclass('private.respaldo_cierre_septiembre_2026') is null then
    raise exception 'PREFLIGHT: no existe el respaldo de septiembre; no se puede restaurar';
  end if;
  execute $q$select count(*) filter (where tabla = 'periodos_cerrados'),
                    count(*) filter (where tabla = 'cierre_mes_vendedor'),
                    max(fila->>'md5') filter (where tabla = 'huella')
               from private.respaldo_cierre_septiembre_2026$q$
    into v_sellos, v_fotos, v_huella;
  if v_sellos <> 1 or v_fotos = 0 or v_huella is null then
    raise exception 'PREFLIGHT: el respaldo de septiembre está incompleto; no se puede restaurar';
  end if;
  if exists (select 1 from crm.periodos_cerrados where periodo >= date '2026-09-01') then
    raise exception 'PREFLIGHT: septiembre (o un mes posterior) ya se volvió a sellar; la reversa ya no aplica';
  end if;
  if exists (select 1 from crm.ajustes_mes_cerrado where periodo_origen = date '2026-09-01')
     or exists (select 1 from crm.inversion_ajustes_mes_cerrado where periodo_origen = date '2026-09-01') then
    raise exception 'PREFLIGHT: hay ajustes de septiembre; revisar antes de restaurar';
  end if;
  if v_huella is distinct from (select huella from _ahora) then
    raise exception 'PREFLIGHT: los datos de septiembre cambiaron desde la reapertura (contratos, conversiones, anulaciones, cartera o inversiones); restaurar perdería capital o deuda. Volver a sellar con 02-resellar.sql';
  end if;
end $pre$;

-- Los BEFORE INSERT del ranking recalculan columnas con datos de hoy: se apagan
-- para que la foto restaurada sea la del respaldo, byte a byte. Los candados
-- append-only no hacen falta: septiembre está abierto y solo se inserta.
alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_10_ranking_origen;
alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_11_ranking_cartera;

-- El trigger del sello marca las acreditaciones que estén en nulo; justo después
-- se les devuelven las marcas exactas del respaldo.
insert into crm.periodos_cerrados
  select (jsonb_populate_record(null::crm.periodos_cerrados, r.fila)).*
  from private.respaldo_cierre_septiembre_2026 r where r.tabla = 'periodos_cerrados';
insert into crm.cierre_mes_vendedor
  select (jsonb_populate_record(null::crm.cierre_mes_vendedor, r.fila)).*
  from private.respaldo_cierre_septiembre_2026 r where r.tabla = 'cierre_mes_vendedor';

alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_10_ranking_origen;
alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_11_ranking_cartera;

-- Las ventas registradas tarde vuelven a donde estaban: su rastro (apunta al
-- sello, por eso va después de él) y su imputación al mes de registro.
insert into crm.inversion_ajustes_mes_cerrado
  select (jsonb_populate_record(null::crm.inversion_ajustes_mes_cerrado, r.fila)).*
  from private.respaldo_cierre_septiembre_2026 r where r.tabla = 'inversion_ajustes_mes_cerrado';

alter table crm.cierres_externos disable trigger trg_cierres_externos_00_inmutables;
alter table crm.cierres_externos disable trigger trg_cierres_f4_inmutables;
update crm.cierres_externos ce set fecha_imputacion = (r.fila->>'fecha_imputacion')::date
  from private.respaldo_cierre_septiembre_2026 r
 where r.tabla = 'cierres_externos' and ce.id = (r.fila->>'id')::uuid;
alter table crm.cierres_externos enable trigger trg_cierres_externos_00_inmutables;
alter table crm.cierres_externos enable trigger trg_cierres_f4_inmutables;

do $marcas$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'crm' and table_name = 'conversion_acreditaciones'
               and column_name = 'ajuste_anulacion_en_sello') then
    execute $q$
      update crm.conversion_acreditaciones ca
         set sellado_en = (r.fila->>'sellado_en')::timestamptz,
             incluida_en_sello = (r.fila->>'incluida_en_sello')::boolean,
             ajuste_anulacion_en_sello = (r.fila->>'ajuste_anulacion_en_sello')::numeric,
             actualizado_en = clock_timestamp()
        from private.respaldo_cierre_septiembre_2026 r
       where r.tabla = 'conversion_acreditaciones' and ca.id = (r.fila->>'id')::uuid
    $q$;
  else
    update crm.conversion_acreditaciones ca
       set sellado_en = (r.fila->>'sellado_en')::timestamptz,
           incluida_en_sello = (r.fila->>'incluida_en_sello')::boolean,
           actualizado_en = clock_timestamp()
      from private.respaldo_cierre_septiembre_2026 r
     where r.tabla = 'conversion_acreditaciones' and ca.id = (r.fila->>'id')::uuid;
  end if;
end $marcas$;

select cron.alter_job(job_id := 3, active := true);

do $post$
declare v_difiere boolean;
begin
  -- Igualdad fila a fila contra el respaldo, en las dos direcciones.
  if exists (
    select 1 from private.respaldo_cierre_septiembre_2026 r
    where r.tabla = 'cierre_mes_vendedor'
      and not exists (select 1 from crm.cierre_mes_vendedor f where to_jsonb(f) = r.fila)
  ) or exists (
    select 1 from crm.cierre_mes_vendedor f
    where f.periodo = date '2026-09-01'
      and not exists (select 1 from private.respaldo_cierre_septiembre_2026 r
                      where r.tabla = 'cierre_mes_vendedor' and r.fila = to_jsonb(f))
  ) or exists (
    select 1 from private.respaldo_cierre_septiembre_2026 r
    where r.tabla = 'periodos_cerrados'
      and not exists (select 1 from crm.periodos_cerrados pc where to_jsonb(pc) = r.fila)
  ) or exists (
    select 1 from private.respaldo_cierre_septiembre_2026 r
    where r.tabla = 'inversion_ajustes_mes_cerrado'
      and not exists (select 1 from crm.inversion_ajustes_mes_cerrado ia where to_jsonb(ia) = r.fila)
  ) or exists (
    select 1 from crm.inversion_ajustes_mes_cerrado ia
    where ia.periodo_origen = date '2026-09-01'
      and not exists (select 1 from private.respaldo_cierre_septiembre_2026 r
                      where r.tabla = 'inversion_ajustes_mes_cerrado' and r.fila = to_jsonb(ia))
  ) or exists (
    select 1 from private.respaldo_cierre_septiembre_2026 r
    where r.tabla = 'cierres_externos'
      and not exists (select 1 from crm.cierres_externos ce where to_jsonb(ce) = r.fila)
  ) then
    raise exception 'POSTFLIGHT: alguna fila restaurada no es idéntica al respaldo';
  end if;
  -- Cada acreditación respaldada existe y tiene sus marcas originales (LEFT JOIN:
  -- una que faltara también falla), y no hay ninguna fuera del respaldo.
  if exists (
    select 1 from private.respaldo_cierre_septiembre_2026 r
    left join crm.conversion_acreditaciones ca on ca.id = (r.fila->>'id')::uuid
    where r.tabla = 'conversion_acreditaciones'
      and (ca.id is null
        or ca.sellado_en is distinct from (r.fila->>'sellado_en')::timestamptz
        or ca.incluida_en_sello is distinct from (r.fila->>'incluida_en_sello')::boolean)
  ) or exists (
    select 1 from crm.conversion_acreditaciones ca
    where ca.periodo_comercial = date '2026-09-01'
      and not exists (select 1 from private.respaldo_cierre_septiembre_2026 r
                      where r.tabla = 'conversion_acreditaciones' and (r.fila->>'id')::uuid = ca.id)
  ) then
    raise exception 'POSTFLIGHT: las acreditaciones no quedaron como en el respaldo';
  end if;
  -- La tercera marca solo existe con 20261012220959: consulta dinámica (una
  -- referencia estática a una columna ausente falla al planificar).
  if exists (select 1 from information_schema.columns
             where table_schema = 'crm' and table_name = 'conversion_acreditaciones'
               and column_name = 'ajuste_anulacion_en_sello') then
    execute $q$
      select exists (
        select 1 from private.respaldo_cierre_septiembre_2026 r
        join crm.conversion_acreditaciones ca on ca.id = (r.fila->>'id')::uuid
        where r.tabla = 'conversion_acreditaciones'
          and ca.ajuste_anulacion_en_sello
                is distinct from (r.fila->>'ajuste_anulacion_en_sello')::numeric)
    $q$ into v_difiere;
    if v_difiere then
      raise exception 'POSTFLIGHT: alguna acreditación no recuperó ajuste_anulacion_en_sello';
    end if;
  end if;
  if not (select active from cron.job where jobid = 3) then
    raise exception 'POSTFLIGHT: el ciclo diario no quedó activo';
  end if;
  if exists (
    select 1 from pg_trigger
    where tgname in ('trg_cierre_mes_vendedor_00_append_only', 'trg_periodos_cerrados_00_append_only',
                     'trg_cierre_mes_vendedor_10_ranking_origen', 'trg_cierre_mes_vendedor_11_ranking_cartera',
                     'trg_inversion_ajustes_inmutables', 'trg_cierres_externos_00_inmutables',
                     'trg_cierres_f4_inmutables')
      and tgenabled = 'D'
  ) then
    raise exception 'POSTFLIGHT: un trigger quedó apagado';
  end if;
end $post$;

select 'SEPTIEMBRE 2026 RESTAURADO tal como estaba el 11/10. Ciclo diario reactivado.' as resultado;
commit;
