-- REEXPRESIÓN DE SEPTIEMBRE 2026 — paso 1: reabrir el mes.
-- Pedido por Miguel el 14/10/2026: los analistas se demoraron en cargar sus ventas
-- de septiembre y el sello automático del 11/10 (09:20 Lima) las rechaza.
-- Mismo camino que agosto (scripts/reexpresion-agosto-2026/01-reabrir.sql), más:
--   · las acreditaciones de conversión de septiembre se respaldan y sus marcas de
--     sello se liberan (el próximo sello las vuelve a fijar);
--   · las ventas en cooperativa de septiembre registradas DESPUÉS del sello (el
--     sistema las imputó al mes de registro y dejó un rastro en
--     crm.inversion_ajustes_mes_cerrado) vuelven a septiembre: su imputación pasa
--     a su fecha comercial y el rastro se retira. Diagnóstico del 14/10
--     (00-diagnostico.sql): 1 caso, Qorilazo S/ 20 000, fecha comercial 15/09,
--     registrado el 13/10.
--
-- Qué hace, en una transacción: respalda todo lo que toca en
-- private.respaldo_cierre_septiembre_2026, retira sello y foto, devuelve esas
-- ventas a septiembre, libera las marcas de sello, PAUSA el ciclo diario (si no,
-- lo volvería a sellar mañana a las 09:20: su ventana ya pasó) y guarda una huella
-- de los datos del mes TAL COMO QUEDAN, para que 03 sepa si algo cambió después.
-- Cierre: 02-resellar.sql (o la configuración de plazo de Gerencia, cuando exista).
-- Reversa: 03-restaurar.sql, solo mientras nada haya cambiado en septiembre.
--
-- Ensayo sin escribir: ver LEEME.md (01 → 02 → deshacer 02 → 03, todo con ROLLBACK).
-- Ejecución real:
--   npx supabase db query --linked --file supabase/scripts/reexpresion-septiembre-2026/01-reabrir.sql
begin;
set local lock_timeout = '10s';
-- to_jsonb(timestamptz) depende de TimeZone; 01 y 03 comparan ese texto (huella
-- y filas restauradas): ambos fijan UTC (revisión Codex r2).
set local timezone = 'UTC';

-- Mismos candados que usan el sello, el trigger de altas de contratos, el
-- escritor de acreditaciones, las deudas y las inversiones tardías (global y
-- mensual, en ese orden). Todos toman el mensual ANTES de mirar el sello.
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);
select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'), (date '2026-09-01' - date '2000-01-01')::integer);

create temp table _antes on commit drop as
select
  (select count(*) from crm.cierre_mes_vendedor where periodo = date '2026-09-01') as foto,
  (select count(*) from crm.conversion_acreditaciones
    where periodo_comercial = date '2026-09-01') as acreditaciones,
  (select count(*) from crm.conversion_acreditaciones
    where periodo_comercial = date '2026-09-01' and sellado_en is not null) as acreditaciones_selladas,
  (select count(*) from crm.conversion_acreditaciones
    where periodo_comercial = date '2026-09-01' and incluida_en_sello) as acreditaciones_incluidas,
  (select count(*) from crm.inversion_ajustes_mes_cerrado
    where periodo_origen = date '2026-09-01') as rastros_tardios;

-- Ventas en cooperativa de septiembre que vuelven a septiembre: las que tienen
-- rastro de registro tardío con origen septiembre. Con su analista efectivo (el
-- mismo que usa private.capital_episodios) y si tiene meta publicada en septiembre:
-- sin ella, la venta dejaría de sumar a su cuota (en octubre sí sumaba).
create temp table _tardias on commit drop as
select ia.inversion_id, ce.id as cierre_externo_id, ce.cooperativa, ce.monto, ce.moneda,
       ce.fecha_comercial, ce.fecha_imputacion as imputacion_anterior,
       ia.fecha_imputacion as imputacion_del_rastro, ce.anulado_en, ce.vendedor_id,
       ef.analista_id as analista_efectivo,
       exists (
         select 1 from crm.metas_vendedor mv
         where mv.meta_periodo_id = (select mp.id from crm.meta_periodos mp
                                     where mp.periodo = date '2026-09-01'
                                     order by mp.revision desc limit 1)
           and mv.vendedor_id = ef.analista_id
       ) as con_meta_en_septiembre
from crm.inversion_ajustes_mes_cerrado ia
join crm.inversiones i on i.id = ia.inversion_id
left join crm.cierres_externos ce on ce.id = i.cierre_externo_id
left join lateral (
  select x.analista_id from private.analista_efectivo_cierre(ce.id) as x(analista_id)
  where ce.id is not null
) ef on true
where ia.periodo_origen = date '2026-09-01';

do $pre$
begin
  if (select auth.uid()) is not null then
    raise exception 'PREFLIGHT: se ejecuta sin sesión (rol de servicio por db query)';
  end if;
  -- Una sola vez: una segunda reapertura va por la configuración de Gerencia.
  if to_regclass('private.respaldo_cierre_septiembre_2026') is not null then
    raise exception 'PREFLIGHT: septiembre ya se reabrió una vez con este script (existe el respaldo); revisar';
  end if;
  -- Septiembre tiene que ser el ÚLTIMO mes sellado: reabrir uno con un mes
  -- posterior sellado rompería el orden del ciclo y los arrastres.
  if not exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01')
     or exists (select 1 from crm.periodos_cerrados where periodo > date '2026-09-01') then
    raise exception 'PREFLIGHT: septiembre no está sellado o hay un mes posterior sellado';
  end if;
  if (select foto from _antes) = 0 then
    raise exception 'PREFLIGHT: septiembre está sellado pero su foto está vacía; revisar';
  end if;
  -- Deudas NACIDAS de septiembre (anular una venta de septiembre después del
  -- sello): con el mes abierto la anulación se recalcula en vivo y la deuda se
  -- descontaría dos veces. El diagnóstico del 14/10 dio 0.
  if exists (select 1 from crm.ajustes_mes_cerrado where periodo_origen = date '2026-09-01') then
    raise exception 'PREFLIGHT: hay deudas nacidas de septiembre sellado; no reabrir sin plan';
  end if;
  -- Deudas de agosto ABSORBIDAS por la foto de septiembre: al borrar la foto se
  -- perdería el descuento (ya quedó saldado) — el fallo de dinero del 15/08.
  if exists (select 1 from crm.cierre_mes_vendedor
             where periodo = date '2026-09-01'
               and (ajuste_numerador <> 0 or ajuste_pen <> 0 or ajuste_usd <> 0)) then
    raise exception 'PREFLIGHT: la foto de septiembre absorbió deudas de agosto; no reabrir sin plan';
  end if;
  -- Registros tardíos: solo se sabe devolver a septiembre ventas en cooperativa
  -- con fecha comercial en septiembre, imputadas a un mes ABIERTO y coherentes con
  -- su rastro. Uno de contrato u otra forma: no se adivina.
  if exists (select 1 from _tardias t
             where t.cierre_externo_id is null
                or t.fecha_comercial is null
                or t.fecha_comercial not between date '2026-09-01' and date '2026-09-30'
                or t.imputacion_anterior is distinct from t.imputacion_del_rastro
                or t.imputacion_anterior < date '2026-10-01'
                or exists (select 1 from crm.periodos_cerrados pc
                           where pc.periodo = date_trunc('month', t.imputacion_anterior)::date)) then
    raise exception 'PREFLIGHT: hay un registro tardío de septiembre que no es una venta en cooperativa coherente; revisar';
  end if;
  -- Devolverla a un mes donde su analista no tiene meta la dejaría sin atribuir.
  if exists (select 1 from _tardias t
             where t.analista_efectivo is null or not t.con_meta_en_septiembre) then
    raise exception 'PREFLIGHT: el analista de una venta registrada tarde no tiene meta en septiembre; al devolverla dejaría de sumar a su cuota. Revisar con Gerencia';
  end if;
  -- Y ninguna venta en cooperativa de septiembre imputada fuera SIN rastro.
  if exists (select 1 from crm.cierres_externos ce
             where ce.fecha_comercial between date '2026-09-01' and date '2026-09-30'
               and ce.fecha_imputacion >= date '2026-10-01'
               and not exists (select 1 from _tardias t where t.cierre_externo_id = ce.id)) then
    raise exception 'PREFLIGHT: hay ventas en cooperativa de septiembre imputadas a otro mes sin rastro; revisar';
  end if;
  if not exists (select 1 from cron.job where jobid = 3 and jobname = 'crm-cierre-mes-diario' and active) then
    raise exception 'PREFLIGHT: el ciclo diario no es el job 3 activo; revisar';
  end if;
end $pre$;

-- 1. Copia íntegra de lo que se va a retirar o cambiar (estado ANTES).
create table private.respaldo_cierre_septiembre_2026 as
  select 'periodos_cerrados'::text as tabla, to_jsonb(pc) as fila, now() as guardado_en
    from crm.periodos_cerrados pc where pc.periodo = date '2026-09-01'
  union all
  select 'cierre_mes_vendedor', to_jsonb(f), now()
    from crm.cierre_mes_vendedor f where f.periodo = date '2026-09-01'
  union all
  select 'conversion_acreditaciones', to_jsonb(ca), now()
    from crm.conversion_acreditaciones ca where ca.periodo_comercial = date '2026-09-01'
  union all
  select 'inversion_ajustes_mes_cerrado', to_jsonb(ia), now()
    from crm.inversion_ajustes_mes_cerrado ia where ia.periodo_origen = date '2026-09-01'
  union all
  select 'cierres_externos', to_jsonb(ce), now()
    from crm.cierres_externos ce where ce.id in (select cierre_externo_id from _tardias);
alter table private.respaldo_cierre_septiembre_2026 enable row level security;
revoke all on private.respaldo_cierre_septiembre_2026 from public, anon, authenticated, service_role;
comment on table private.respaldo_cierre_septiembre_2026 is
  'Sello, foto, acreditaciones, rastros de registro tardío y cierres en cooperativa de septiembre 2026 tal como estaban antes de reabrirlo el 14/10/2026 para cargar ventas atrasadas, más la huella del mes reabierto. Se restaura con scripts/reexpresion-septiembre-2026/03-restaurar.sql.';

-- 2. Los candados «no se edita ni se borra» se levantan SOLO aquí, dentro de la
--    transacción, y se vuelven a encender en seguida. La auditoría sigue activa
--    para sello, foto, cierres en cooperativa y acreditaciones; el rastro tardío
--    solo audita altas (trg_audit_inversion_ajustes es AFTER INSERT): su borrado
--    queda únicamente en este respaldo.
--    Orden: el rastro tardío apunta (FK) al sello; se retira antes que el sello.
alter table crm.inversion_ajustes_mes_cerrado disable trigger trg_inversion_ajustes_inmutables;
delete from crm.inversion_ajustes_mes_cerrado where periodo_origen = date '2026-09-01';
alter table crm.inversion_ajustes_mes_cerrado enable trigger trg_inversion_ajustes_inmutables;

alter table crm.cierre_mes_vendedor disable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   disable trigger trg_periodos_cerrados_00_append_only;
delete from crm.cierre_mes_vendedor where periodo = date '2026-09-01';
delete from crm.periodos_cerrados   where periodo = date '2026-09-01';
alter table crm.cierre_mes_vendedor enable trigger trg_cierre_mes_vendedor_00_append_only;
alter table crm.periodos_cerrados   enable trigger trg_periodos_cerrados_00_append_only;

-- 3. Las ventas en cooperativa registradas tarde vuelven a septiembre: imputación
--    = fecha comercial, que es lo que el sistema pone cuando se registra a tiempo.
alter table crm.cierres_externos disable trigger trg_cierres_externos_00_inmutables;
alter table crm.cierres_externos disable trigger trg_cierres_f4_inmutables;
update crm.cierres_externos ce set fecha_imputacion = ce.fecha_comercial
 where ce.id in (select cierre_externo_id from _tardias);
alter table crm.cierres_externos enable trigger trg_cierres_externos_00_inmutables;
alter table crm.cierres_externos enable trigger trg_cierres_f4_inmutables;

-- 4. Las acreditaciones vuelven a «sin sellar»: el próximo sello las fija de
--    nuevo (el trigger del sello solo toca las que tienen sellado_en nulo).
--    `ajuste_anulacion_en_sello` solo existe si ya se aplicó 20261012220959.
do $liberar$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'crm' and table_name = 'conversion_acreditaciones'
               and column_name = 'ajuste_anulacion_en_sello') then
    execute $q$
      update crm.conversion_acreditaciones
         set sellado_en = null, incluida_en_sello = null, ajuste_anulacion_en_sello = null,
             actualizado_en = clock_timestamp()
       where periodo_comercial = date '2026-09-01' and sellado_en is not null
    $q$;
  else
    update crm.conversion_acreditaciones
       set sellado_en = null, incluida_en_sello = null, actualizado_en = clock_timestamp()
     where periodo_comercial = date '2026-09-01' and sellado_en is not null;
  end if;
end $liberar$;

-- 5. Nadie vuelve a sellar septiembre hasta que los analistas terminen de cargar.
select cron.alter_job(job_id := 3, active := false);

-- 6. HUELLA del mes tal como queda reabierto: contratos, acreditaciones (sin sus
--    marcas de sello), operaciones de cartera, inversiones, TODAS las anulaciones
--    Avance y los cierres en cooperativa anulados o de septiembre. 03-restaurar.sql
--    la recalcula con el MISMO texto: si algo cambió, restaurar la foto vieja
--    perdería capital o deuda y se niega.
insert into private.respaldo_cierre_septiembre_2026 (tabla, fila, guardado_en)
select 'huella', jsonb_build_object('md5',
  -- [HUELLA-SEPTIEMBRE] inicio (copia exacta en 03-restaurar.sql)
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
  )))
  -- [HUELLA-SEPTIEMBRE] fin
), now();

do $post$
begin
  if exists (select 1 from crm.periodos_cerrados where periodo = date '2026-09-01')
     or exists (select 1 from crm.cierre_mes_vendedor where periodo = date '2026-09-01') then
    raise exception 'POSTFLIGHT: septiembre sigue sellado';
  end if;
  if exists (select 1 from crm.conversion_acreditaciones
             where periodo_comercial = date '2026-09-01' and sellado_en is not null) then
    raise exception 'POSTFLIGHT: quedan acreditaciones de septiembre marcadas como selladas';
  end if;
  if exists (select 1 from crm.inversion_ajustes_mes_cerrado where periodo_origen = date '2026-09-01')
     or exists (select 1 from crm.cierres_externos ce
                where ce.id in (select cierre_externo_id from _tardias)
                  and ce.fecha_imputacion is distinct from ce.fecha_comercial) then
    raise exception 'POSTFLIGHT: una venta registrada tarde no volvió a septiembre';
  end if;
  if (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'periodos_cerrados') <> 1
     or (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'huella') <> 1
     or (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'cierre_mes_vendedor')
          <> (select foto from _antes)
     or (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'conversion_acreditaciones')
          <> (select acreditaciones from _antes)
     or (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'inversion_ajustes_mes_cerrado')
          <> (select rastros_tardios from _antes)
     or (select count(*) from private.respaldo_cierre_septiembre_2026 where tabla = 'cierres_externos')
          <> (select count(*) from _tardias) then
    raise exception 'POSTFLIGHT: el respaldo no coincide con lo retirado o cambiado';
  end if;
  if (select active from cron.job where jobid = 3) then
    raise exception 'POSTFLIGHT: el ciclo diario sigue activo';
  end if;
  if exists (
    select 1 from pg_trigger
    where tgname in ('trg_cierre_mes_vendedor_00_append_only', 'trg_periodos_cerrados_00_append_only',
                     'trg_inversion_ajustes_inmutables', 'trg_cierres_externos_00_inmutables',
                     'trg_cierres_f4_inmutables')
      and tgenabled = 'D'
  ) then
    raise exception 'POSTFLIGHT: un candado quedó apagado';
  end if;
end $post$;

-- Resumen (db query solo muestra la última sentencia con filas).
select jsonb_build_object(
  'resultado', 'SEPTIEMBRE 2026 REABIERTO: ya se pueden cargar contratos con fecha de septiembre. Ciclo diario en pausa.',
  'foto_retirada', a.foto,
  'acreditaciones_respaldadas', a.acreditaciones,
  'acreditaciones_liberadas', a.acreditaciones_selladas,
  'acreditaciones_que_estaban_incluidas', a.acreditaciones_incluidas,
  'ventas_devueltas_a_septiembre', (select coalesce(jsonb_agg(jsonb_build_object(
      'cooperativa', t.cooperativa, 'monto', t.monto, 'moneda', t.moneda,
      'fecha_comercial', t.fecha_comercial, 'imputada_antes_a', t.imputacion_anterior,
      'analista', p.nombre_completo, 'con_meta_en_septiembre', t.con_meta_en_septiembre,
      'anulada', t.anulado_en is not null)), '[]'::jsonb)
    from _tardias t left join public.perfiles p on p.id = t.analista_efectivo),
  'meses_sellados', (select jsonb_agg(periodo order by periodo) from crm.periodos_cerrados),
  'ciclo_activo', (select active from cron.job where jobid = 3)
) as reapertura
from _antes a;
commit;
