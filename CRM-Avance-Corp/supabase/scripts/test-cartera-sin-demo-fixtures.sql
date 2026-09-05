-- Sólo fixtures locales: el runner verifica socket privado y cluster vacío.
create schema auth;
create schema private;
create schema crm;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

-- Dobles de contexto: ejercitan cada OR de la fachada sin cambiar auth real.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('cartera.actor',true),'')::uuid
$$;
create function private.rol_crm(uuid) returns text language sql stable as $$
  select case when $1 is not null then nullif(current_setting('cartera.rol',true),'') end
$$;
create function private.es_lector_global() returns boolean language sql stable as $$
  select auth.uid() is not null and current_setting('cartera.global',true)='true'
$$;
create function private.vendedor_ids_visibles(uuid) returns setof uuid language sql stable as $$
  select unnest(coalesce(nullif(current_setting('cartera.visibles',true),'')::uuid[],'{}'::uuid[]))
  where $1 is not null
$$;

create table public.perfiles(
  id uuid primary key, nombre_completo text, asesor_perfil_id uuid,
  creado_por uuid, activo boolean not null default true
);
create table crm.productos_inversion(id uuid primary key,codigo text);
create table crm.producto_versiones(
  id uuid primary key,producto_id uuid,numero_version integer,nombre text,estado text
);
create table crm.producto_condiciones(id uuid primary key,version_id uuid);
create table public.contratos(
  id uuid primary key,numero_contrato text,cliente_id uuid,capital numeric,
  moneda text,tasa_anual numeric,modalidad text,tipo_interes text,categoria text,
  estado text,fecha_inicio date,fecha_vencimiento date,notas_internas text,
  creado_por uuid,creado_en timestamptz,producto_condicion_id uuid,
  fecha_cierre_comercial date,es_demo boolean not null
);
create table public.cronograma_pagos(
  id uuid,contrato_id uuid,numero_cuota integer,fecha_programada date,
  monto_programado numeric,estado text,tipo text,fecha_pago_real date,monto_pagado numeric
);
create table public.contrato_titulares(
  id uuid,contrato_id uuid,orden smallint,nombre_completo text,tipo_documento text,documento text
);
insert into public.perfiles
select md5('cliente-'||n)::uuid,'FIXTURE '||n,
  case when n=3 then null else md5('analista-'||(case when n=1 then 1 else 2 end))::uuid end,
  md5('analista-1')::uuid,n<>4
from generate_series(1,4) n;
insert into crm.productos_inversion values(md5('producto')::uuid,'FIXTURE');
insert into crm.producto_versiones values(md5('version')::uuid,md5('producto')::uuid,1,'FIXTURE','publicada');
insert into crm.producto_condiciones values(md5('condicion')::uuid,md5('version')::uuid);
insert into public.contratos
select md5('contrato-'||n)::uuid,'LOCAL-'||n,md5('cliente-'||(((n-1)%4)+1))::uuid,
  n*1000,case when n%2=0 then 'USD' else 'PEN' end,10,'mensual','simple',
  case when n%3=0 then 'renovacion' when n%3=1 then 'nuevo' else 'upgrade' end,
  case when n%4=0 then 'vencido' else 'activo' end,
  '2026-08-01','2026-09-15','fixture',md5('analista-1')::uuid,'2026-09-01T10:00:00-05',
  md5('condicion')::uuid,'2026-09-01',n>4
from generate_series(1,8) n;
insert into public.cronograma_pagos
select md5('cuota-'||id)::uuid,id,1,'2026-09-15',100,'pendiente','cuota',null,null from public.contratos;
insert into public.contrato_titulares
select md5('titular-'||id)::uuid,id,1,'FIXTURE','DNI','00000000' from public.contratos;

CREATE OR REPLACE FUNCTION crm.contratos_cartera_fn()
 RETURNS TABLE(id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text, asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric, modalidad text, tipo_interes text, categoria text, estado text, fecha_inicio date, fecha_vencimiento date, notas_internas text, creado_por uuid, creado_en timestamp with time zone, producto_condicion_id uuid, producto_id uuid, producto_codigo text, producto_version_id uuid, producto_version integer, producto_nombre text, producto_version_estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id, c.numero_contrato, c.cliente_id, cli.nombre_completo,
    cli.asesor_perfil_id, c.capital, c.moneda, c.tasa_anual, c.modalidad,
    c.tipo_interes, c.categoria, c.estado, c.fecha_inicio,
    c.fecha_vencimiento, c.notas_internas, c.creado_por, c.creado_en,
    c.producto_condicion_id, p.id, p.codigo, v.id, v.numero_version,
    v.nombre, v.estado
  from public.contratos c
  join public.perfiles cli on cli.id = c.cliente_id
  join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
  join crm.producto_versiones v on v.id = pc.version_id
  join crm.productos_inversion p on p.id = v.producto_id
  where (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) = 'gerencia'
    or cli.asesor_perfil_id in (
      select private.vendedor_ids_visibles((select auth.uid()))
    )
    or (
      cli.asesor_perfil_id is null
      and cli.creado_por in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
    )
  );
$function$;
revoke all on function crm.contratos_cartera_fn() from public;
grant execute on function crm.contratos_cartera_fn() to authenticated,service_role;

CREATE OR REPLACE FUNCTION crm.contratos_cartera_v2_fn()
 RETURNS TABLE(id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text, asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric, modalidad text, tipo_interes text, categoria text, estado text, fecha_inicio date, fecha_vencimiento date, notas_internas text, creado_por uuid, creado_en timestamp with time zone, producto_condicion_id uuid, producto_id uuid, producto_codigo text, producto_version_id uuid, producto_version integer, producto_nombre text, producto_version_estado text, fecha_cierre_comercial date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- El gate NO se reescribe: lo pone `contratos_cartera_fn`, y este join solo
  -- puede recortar sus filas, nunca anadir una. `public.contratos.id` es la PK,
  -- asi que el join es 1:1 y no duplica.
  select
    f.id, f.numero_contrato, f.cliente_id, f.cliente_nombre,
    f.asesor_perfil_id, f.capital, f.moneda, f.tasa_anual,
    f.modalidad, f.tipo_interes, f.categoria, f.estado,
    f.fecha_inicio, f.fecha_vencimiento, f.notas_internas,
    f.creado_por, f.creado_en, f.producto_condicion_id,
    f.producto_id, f.producto_codigo, f.producto_version_id,
    f.producto_version, f.producto_nombre, f.producto_version_estado,
    c.fecha_cierre_comercial
  from crm.contratos_cartera_fn() f
  join public.contratos c on c.id = f.id;
$function$;

CREATE OR REPLACE FUNCTION crm.cronograma_contrato_fn(p_contrato_id uuid)
 RETURNS TABLE(id uuid, numero_cuota integer, fecha_programada date, monto_programado numeric, estado text, tipo text, fecha_pago_real date, monto_pagado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  select cp.id, cp.numero_cuota, cp.fecha_programada, cp.monto_programado,
         cp.estado, cp.tipo, cp.fecha_pago_real, cp.monto_pagado
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id
    and exists (select 1 from crm.contratos_cartera_fn() cc where cc.id = p_contrato_id)
  order by cp.numero_cuota;
$function$;

CREATE OR REPLACE FUNCTION crm.titulares_contrato_fn(p_contrato_id uuid)
 RETURNS TABLE(id uuid, orden smallint, nombre_completo text, tipo_documento text, documento text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  select t.id, t.orden, t.nombre_completo, t.tipo_documento, t.documento
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id
    and exists (select 1 from crm.contratos_cartera_fn() cc where cc.id = p_contrato_id)
  order by t.orden;
$function$;
revoke all on function crm.contratos_cartera_v2_fn() from public;
revoke all on function crm.cronograma_contrato_fn(uuid) from public;
revoke all on function crm.titulares_contrato_fn(uuid) from public;
grant execute on function crm.contratos_cartera_v2_fn() to authenticated,service_role;
grant execute on function crm.cronograma_contrato_fn(uuid) to authenticated,service_role;
grant execute on function crm.titulares_contrato_fn(uuid) to authenticated,service_role;
grant usage on schema crm to authenticated,service_role,anon;
create view crm.contratos_cartera with(security_invoker=true) as select * from crm.contratos_cartera_v2_fn();
grant select on crm.contratos_cartera to authenticated,service_role;

create table public.contextos(
  nombre text,actor uuid,rol text,global boolean,visibles uuid[]
);
insert into public.contextos values
  ('gerencia',md5('gerente')::uuid,'gerencia',false,'{}'),
  ('directorio',md5('directorio')::uuid,null,true,'{}'),
  ('analista_1_y_creador_sin_asesor',md5('analista-1')::uuid,'vendedor',false,array[md5('analista-1')::uuid]),
  ('analista_2',md5('analista-2')::uuid,'vendedor',false,array[md5('analista-2')::uuid]),
  ('supervisor',md5('supervisor')::uuid,'supervisor',false,array[md5('analista-1')::uuid,md5('analista-2')::uuid]),
  ('ajeno',md5('ajeno')::uuid,'vendedor',false,'{}'),
  ('sin_actor',null,null,false,'{}');
create table public.oraculo(nombre text,original jsonb,real jsonb,real_v2 jsonb);
create table public.datos_antes as select md5(string_agg(to_jsonb(c)::text,',' order by c.id)) huella from public.contratos c;
do $$
declare ctx record;
begin
 for ctx in select * from public.contextos loop
  perform set_config('cartera.actor',coalesce(ctx.actor::text,''),true);
  perform set_config('cartera.rol',coalesce(ctx.rol,''),true);
  perform set_config('cartera.global',ctx.global::text,true);
  perform set_config('cartera.visibles',ctx.visibles::text,true);
  insert into public.oraculo
  select ctx.nombre,
    (select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from crm.contratos_cartera_fn() f),
    (select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from crm.contratos_cartera_fn() f join public.contratos c on c.id=f.id where not c.es_demo),
    (select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from crm.contratos_cartera_v2_fn() f join public.contratos c on c.id=f.id where not c.es_demo);
 end loop;
end;
$$;

