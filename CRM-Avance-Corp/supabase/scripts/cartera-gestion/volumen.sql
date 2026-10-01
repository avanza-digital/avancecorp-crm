-- FRAGMENTO (sin transacción propia): datos sintéticos de VOLUMEN, deterministas (sin random):
-- 28 actores, 5 000 leads, ~31 600 actividades y el libro de recepciones. Cero datos de
-- personas. Lo compone `ensayar.mjs` dentro de una transacción que SIEMPRE se deshace.
--
-- Actores (prefijo f3bb1000…): 1 gerencia · 2 directorio · 3 coordinador ·
-- 11..14 supervisores · 101..120 analistas (5 por supervisor).
-- Los atributos de cada lead salen de divisores distintos de `n` para que no se alineen
-- (etapa, titular, moneda, origen y tenencia varían de forma independiente).
--
-- NUNCA sobre una base con datos: se niega si hay un solo lead, perfil, actividad o miembro de
-- equipo. Solo se siembra en un banco vacío y dentro de una transacción que se deshace.
do $guarda$
begin
  if exists (select 1 from crm.leads) or exists (select 1 from public.perfiles)
     or exists (select 1 from crm.actividades) or exists (select 1 from crm.equipo) then
    raise exception 'VOLUMEN: la base tiene leads, perfiles, actividades o equipo; estos datos sinteticos solo se siembran en un banco vacio';
  end if;
end;
$guarda$;
set local session_replication_role = replica;

create function pg_temp.vactor(n integer) returns uuid language sql immutable as
  $f$ select ('f3bb1000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
create function pg_temp.vlead(n integer) returns uuid language sql immutable as
  $f$ select ('f3bb2000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
grant execute on function pg_temp.vactor(integer), pg_temp.vlead(integer) to authenticated;

insert into public.perfiles (id, nombre_completo, rol, activo)
select pg_temp.vactor(n), 'VOLUMEN ACTOR ' || n, case when n = 2 then 'directorio' else 'comercial' end, true
from unnest(array[1, 2, 3] || array(select generate_series(11, 14)) || array(select generate_series(101, 120))) n;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select pg_temp.vactor(n),
  case when n = 1 then 'gerencia' when n = 2 then 'directorio' when n = 3 then 'coordinador'
    when n between 11 and 14 then 'supervisor' else 'vendedor' end,
  case when n >= 101 then pg_temp.vactor(11 + (n - 101) % 4) end, true
from unnest(array[1, 2, 3] || array(select generate_series(11, 14)) || array(select generate_series(101, 120))) n;

-- Configuración mínima que un banco vacío no trae (la piden el libro de asignaciones y
-- `resumen_cartera_fn`).
insert into crm.sla_politicas (id, version, vigente_desde, zona_horaria, tipo_reloj,
  primera_gestion_minutos, primer_contacto_minutos)
values ('f3bb3000-0000-4000-8000-000000000001', 1, '2020-01-01T00:00:00Z', 'America/Lima', 'corrido', 60, 120);
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
values ('2026-01-01', 0.5, 'sintetico: volumen cartera-gestion');

insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, motivo_descarte,
  monto_estimado, moneda, vendedor_id, asignado_supervisor_id, creado_por, alta_manual,
  creado_en, actualizado_en, convertido_en, tenencia_desde, activo)
select pg_temp.vlead(n), 'VOLUMEN LEAD ' || lpad(n::text, 5, '0'), '+519' || lpad(n::text, 8, '0'),
  case when n % 3 = 0 then (40000000 + n)::text end,
  (array['landing','formulario','referido','oficina','otro','web','campania','whatsapp'])[1 + (n / 3) % 8],
  e.etapa,
  case when e.etapa = 'descartado' then (array['sin_interes','no_responde','sin_fondos'])[1 + n % 3] end,
  100 + (n % 50) * 100, case when (n / 11) % 7 = 0 then 'USD' else 'PEN' end,
  t.vendedor, t.bandeja,
  case when n % 9 = 0 or n % 31 = 0 then pg_temp.vactor(101 + n % 20) end, n % 9 = 0,
  now() - make_interval(days => 2 + n % 120),
  -- Minutos repetidos a propósito: empates de sello que el cursor desempata por id.
  now() - make_interval(mins => n % 3000),
  case when e.etapa = 'convertido' then now() - make_interval(days => n % 90) end,
  -- Tenencia entre 12 horas y 20 días; unos pocos titulares sin ella (hueco de backfill).
  case when t.vendedor is not null and e.etapa not in ('convertido', 'descartado') and n % 499 <> 0
    then now() - make_interval(hours => 12 * (1 + (n / 7) % 40)) end,
  n % 211 <> 0
from generate_series(1, 5000) n
cross join lateral (select case
    when (n / 20) % 20 <= 8 then 'nuevo' when (n / 20) % 20 <= 13 then 'contactado'
    when (n / 20) % 20 <= 15 then 'reunion_agendada' when (n / 20) % 20 = 16 then 'propuesta_enviada'
    when (n / 20) % 20 = 17 then 'convertido' else 'descartado' end as etapa) e
cross join lateral (select
    case when n % 25 <> 0 then pg_temp.vactor(101 + n % 20) end as vendedor,
    case when n % 25 = 0 and n % 50 <> 0 then pg_temp.vactor(11 + n % 4) end as bandeja) t;

-- Actividades: de 0 a 12 por lead, de los nueve tipos, repartidas en los últimos 30 días
-- (unas antes y otras después de la tenencia del titular actual). Una de cada siete llamadas
-- lleva su resultado DESHECHO (`deshecho_en`), muchas más que en producción, para que la regla
-- «lo deshecho no cuenta» decida de verdad la mitad de algunos leads.
insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
select pg_temp.vlead(n), x.tipo,
  case when (n + k * 3) % 7 = 0 and x.tipo in ('llamada_no_contestada', 'llamada_realizada')
    then jsonb_build_object('evento', 'resultado_llamada',
      'resultado', case x.tipo when 'llamada_no_contestada' then 'no_contesto' else 'volver_a_llamar' end,
      'deshecho_en', now(), 'deshecho_por', pg_temp.vactor(101 + (n + k) % 20))
    else '{}'::jsonb end,
  case when (n + k) % 4 <> 0 then pg_temp.vactor(101 + (n + k) % 20) end,
  now() - make_interval(hours => (n * 7 + k * 37) % 720, mins => k)
from generate_series(1, 5000) n
cross join lateral generate_series(1, n % 13) k
cross join lateral (select (array['llamada_no_contestada','whatsapp_enviado','nota','llamada_realizada','whatsapp_recibido',
    'reunion_realizada','cambio_etapa','nota','llamada_no_contestada'])[1 + (n + k * 5) % 9] as tipo) x;
-- Eventos de reasignación: uno de cada seis leads pasó por otro analista; otro de cada seis
-- solo tiene la primera entrega (analista anterior nulo: no cuenta como reasignado).
insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
select pg_temp.vlead(n), 'reasignacion',
  jsonb_build_object('vendedor_anterior', case when n % 6 = 0 then pg_temp.vactor(101 + (n + 7) % 20) end,
    'vendedor_nuevo', pg_temp.vactor(101 + n % 20)),
  null, now() - make_interval(hours => 12 * (1 + (n / 7) % 40))
from generate_series(1, 5000) n
where n % 6 in (0, 3) and n % 25 <> 0;

-- Recepciones: un episodio por lead con titular, en el instante de su tenencia.
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
  asignado_en, sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en,
  primer_contacto_limite_en, moneda, origen, finalizado_en, motivo_cierre, aproximado)
select l.id, 1, 1, l.vendedor_id, 'asignado', s.sello, s.sello,
  'f3bb3000-0000-4000-8000-000000000001', s.sello + interval '1 hour', s.sello + interval '2 hours',
  l.moneda, 'volumen_gestion', s.sello + interval '1 second', 'desactivado', false
from crm.leads l
cross join lateral (select coalesce(l.tenencia_desde, l.creado_en) as sello) s
where l.vendedor_id is not null;

set local session_replication_role = origin;
analyze crm.leads;
analyze crm.actividades;
analyze crm.equipo;
analyze crm.lead_asignaciones;
analyze public.perfiles;

select 'VOLUMEN ' || jsonb_build_object(
  'leads', (select count(*) from crm.leads),
  'leads_nuevo_activos', (select count(*) from crm.leads where activo and etapa = 'nuevo'),
  'actividades', (select count(*) from crm.actividades),
  'actividades_de_contacto', (select count(*) from crm.actividades where tipo in
    ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')),
  'contactos_deshechos', (select count(*) from crm.actividades where metadata ? 'deshecho_en'),
  'recepciones', (select count(*) from crm.lead_asignaciones),
  'actores', (select count(*) from crm.equipo))::text;
