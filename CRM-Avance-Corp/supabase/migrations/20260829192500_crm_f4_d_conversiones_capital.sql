-- P-055 FASE 4.d — El capital del panel de Conversiones sale del nucleo.
--
-- private.metricas_conversiones_implementacion tiene TRES bloques de capital
-- (por lead de la cohorte, totales del rango, y por analista), cada uno con su
-- propia copia de la formula contratos+cooperativas. Los tres pasan a leer de
-- private.capital_episodios via SEIS trasplantes ANCLADOS (el cuerpo no se
-- reescribe: cada expresion compuesta se localiza byte a byte y se reemplaza;
-- si un ancla no aparece EXACTAMENTE una vez, la migracion aborta).
--
-- crm.metricas_vendedores_fn queda FUERA a proposito: su dinero ya es DERIVADO
-- (payloads del cierre y sumas de agregados) — pertenece al dominio del motor
-- del sellado, que se migra despues del 10/09 con produccion y las escritoras.
--
-- El oraculo viaja dentro: payload como GERENCIA (el panel es gerencia/lector
-- por su gate vivo), antes y despues, byte a byte (sin 'generado_en'), en dos
-- ventanas y con y sin filtro de origen.

begin;

set local lock_timeout = '5s';

create temp table zz_f4d_antes (quien text, variante text, huella text) on commit drop;

do $antes$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        h1 text; h2 text; h3 text;
begin
  -- la implementacion LLEVA gate propio (gerencia/lector) y exige hasta<=hoy:
  -- se fotografia con sombrero de gerencia y ventana [1ago..hoy].
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  -- es private (sin EXECUTE para authenticated): se llama como postgres con
  -- las claims puestas — auth.uid() las lee igual y el gate interno pasa.
  select md5((private.metricas_conversiones_implementacion(date '2026-08-01', current_date, null) - 'generado_en')::text) into h1;
  select md5((private.metricas_conversiones_implementacion(date '2026-08-01', current_date, 'referido') - 'generado_en')::text) into h2;
  select md5((private.metricas_conversiones_implementacion(date '2026-07-01', date '2026-07-31', null) - 'generado_en')::text) into h3;
  insert into zz_f4d_antes values ('srv','ago-todos',h1), ('srv','ago-referido',h2), ('srv','jul-todos',h3);
end
$antes$;

-- ---------------------------------------------------------- LOS TRASPLANTES --
do $parche$
declare
  v_src text; v_nuevo text; v_huella text;
  a1 text; r1 text; a2 text; r2 text; a3 text; r3 text;
  a4 text; r4 text; a5 text; r5 text; a6 text; r6 text;
begin
  select p.prosrc, md5(p.prosrc) into v_src, v_huella
  from pg_proc p where p.oid = 'private.metricas_conversiones_implementacion(date,date,text)'::regprocedure;
  if v_huella <> '98df12a365c27dd900b288c1859b047d' then
    raise exception 'conversiones_implementacion cambio (huella %): ABORTA', v_huella;
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='private' and p.proname='capital_episodios') then
    raise exception 'Falta el nucleo (20260829190500): ABORTA';
  end if;

  -- B1: capital VIVO por lead de la cohorte (todo el tiempo, contratos del
  -- perfil + coops del lead). Una sola fuente: el nucleo.
  a1 := $A$      (coalesce((select sum(ct.capital) from (select * from public.contratos where not es_demo) ct
         where ct.cliente_id = l.perfil_id and ct.moneda = 'PEN'), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.lead_id = l.id and ce.anulado_en is null and ce.moneda = 'PEN'), 0)) as capital_lead_pen,$A$;
  r1 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (date '1900-01-01')::timestamp at time zone 'America/Lima',
           (date '9999-01-01')::timestamp at time zone 'America/Lima', true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_pen,$R$;
  a2 := $A$      (coalesce((select sum(ct.capital) from (select * from public.contratos where not es_demo) ct
         where ct.cliente_id = l.perfil_id and ct.moneda = 'USD'), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.lead_id = l.id and ce.anulado_en is null and ce.moneda = 'USD'), 0)) as capital_lead_usd$A$;
  r2 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (date '1900-01-01')::timestamp at time zone 'America/Lima',
           (date '9999-01-01')::timestamp at time zone 'America/Lima', true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%' and k.cliente_id = l.perfil_id)
                or (k.tipo = 'cooperativa'   and k.lead_id   = l.id))), 0)) as capital_lead_usd$R$;

  -- B2: totales del RANGO (contratos con lead + coops del rango).
  a3 := $A$      (coalesce((select sum(c.capital) from (select * from public.contratos where not es_demo) c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta and c.moneda = 'PEN'
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
          where ce.anulado_en is null and ce.moneda = 'PEN'
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_pen,$A$;
  r3 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_pen,$R$;
  a4 := $A$      (coalesce((select sum(c.capital) from (select * from public.contratos where not es_demo) c
        where c.fecha_cierre_comercial >= p_desde and c.fecha_cierre_comercial <= p_hasta and c.moneda = 'USD'
          and exists (select 1 from crm.leads l where l.perfil_id = c.cliente_id)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
          where ce.anulado_en is null and ce.moneda = 'USD'
            and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_usd,$A$;
  r4 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and exists (select 1 from crm.leads l where l.perfil_id = k.cliente_id))
                or k.tipo = 'cooperativa')), 0)) as capital_usd,$R$;

  -- B3: capital por ANALISTA (contratos de los clientes de sus leads + sus coops).
  a5 := $A$      (coalesce((select sum(ct.capital) from (select * from public.contratos where not es_demo) ct
         where ct.moneda = 'PEN'
           and ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta
           and ct.cliente_id in (select l.perfil_id from crm.leads l
                                 where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.vendedor_id = vb.vendedor_id and ce.anulado_en is null and ce.moneda = 'PEN'
           and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_pen,$A$;
  r5 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'PEN'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_pen,$R$;
  a6 := $A$      (coalesce((select sum(ct.capital) from (select * from public.contratos where not es_demo) ct
         where ct.moneda = 'USD'
           and ct.fecha_cierre_comercial >= p_desde and ct.fecha_cierre_comercial <= p_hasta
           and ct.cliente_id in (select l.perfil_id from crm.leads l
                                 where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null)), 0)
       + coalesce((select sum(ce.monto) from crm.cierres_externos ce
         where ce.vendedor_id = vb.vendedor_id and ce.anulado_en is null and ce.moneda = 'USD'
           and (ce.creado_en at time zone 'America/Lima')::date between p_desde and p_hasta), 0)) as capital_usd$A$;
  r6 := $R$      (coalesce((select sum(k.monto) from private.capital_episodios(
           (p_desde::timestamp at time zone 'America/Lima'),
           ((p_hasta + 1)::timestamp at time zone 'America/Lima'), true, '{}'::uuid[]) k
         where k.moneda = 'USD'
           and (   (k.tipo like 'contrato_%'
                    and k.cliente_id in (select l.perfil_id from crm.leads l
                                         where l.vendedor_id = vb.vendedor_id and l.perfil_id is not null))
                or (k.tipo = 'cooperativa' and k.analista_id = vb.vendedor_id))), 0)) as capital_usd$R$;

  -- cada ancla EXACTAMENTE una vez
  if (length(v_src)-length(replace(v_src,a1,'')))/length(a1) <> 1
   or (length(v_src)-length(replace(v_src,a2,'')))/length(a2) <> 1
   or (length(v_src)-length(replace(v_src,a3,'')))/length(a3) <> 1
   or (length(v_src)-length(replace(v_src,a4,'')))/length(a4) <> 1
   or (length(v_src)-length(replace(v_src,a5,'')))/length(a5) <> 1
   or (length(v_src)-length(replace(v_src,a6,'')))/length(a6) <> 1 then
    raise exception 'Un ancla de F4.d no aparece exactamente una vez: ABORTA';
  end if;

  v_nuevo := replace(v_src, a1, r1);
  v_nuevo := replace(v_nuevo, a2, r2);
  v_nuevo := replace(v_nuevo, a3, r3);
  v_nuevo := replace(v_nuevo, a4, r4);
  v_nuevo := replace(v_nuevo, a5, r5);
  v_nuevo := replace(v_nuevo, a6, r6);

  execute format(
    'create or replace function private.metricas_conversiones_implementacion(p_desde date, p_hasta date, p_origen text default null) '
    'returns jsonb language plpgsql stable security definer set search_path to '''' as %L', v_nuevo);
end
$parche$;

-- ------------------------------------------------------------------ ORACULO --
do $despues$
declare v_uid_ger uuid := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
        h1 text; h2 text; h3 text; v_falla text := '';
begin
  execute format('set local request.jwt.claims = %L',
    json_build_object('sub', v_uid_ger, 'role','authenticated')::text);
  -- es private (sin EXECUTE para authenticated): se llama como postgres con
  -- las claims puestas — auth.uid() las lee igual y el gate interno pasa.
  select md5((private.metricas_conversiones_implementacion(date '2026-08-01', current_date, null) - 'generado_en')::text) into h1;
  select md5((private.metricas_conversiones_implementacion(date '2026-08-01', current_date, 'referido') - 'generado_en')::text) into h2;
  select md5((private.metricas_conversiones_implementacion(date '2026-07-01', date '2026-07-31', null) - 'generado_en')::text) into h3;

  if h1 <> (select huella from zz_f4d_antes where variante='ago-todos') then v_falla := v_falla || 'ago-todos '; end if;
  if h2 <> (select huella from zz_f4d_antes where variante='ago-referido') then v_falla := v_falla || 'ago-referido '; end if;
  if h3 <> (select huella from zz_f4d_antes where variante='jul-todos') then v_falla := v_falla || 'jul-todos '; end if;

  if v_falla <> '' then
    raise exception 'ORACULO F4.d: el payload cambio en [%]: NO se publica', v_falla;
  end if;
  raise notice 'ORACULO F4.d OK: Conversiones identico byte a byte (3 variantes)';
end
$despues$;

commit;
