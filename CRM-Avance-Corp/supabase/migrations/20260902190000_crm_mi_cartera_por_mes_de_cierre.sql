-- Mi cartera, por MES DE CIERRE - la fecha comercial llega al front.
--
-- QUE, en una linea: `crm.contratos_cartera` gana UNA columna de lectura,
-- `fecha_cierre_comercial`, para que la pantalla del analista pueda partir su
-- cartera por el mes en que VENDIO en vez del mes en que TECLEO.
--
-- POR QUE. Hoy «Mi cartera» agrupa por `creado_en` (decision del 2026-08-14,
-- tomada cuando la cuota tambien medía por `creado_en`). El P-055 movio la cuota
-- a `fecha_cierre_comercial` y la pantalla se quedo atras: el 02/09/2026, nueve
-- cierres de agosto -S/ 517.500 + US$ 37.000 de MERLYS, FIORELLA y KELLY,
-- registrados el 01/09- aparecen bajo «Septiembre 2026» mientras su cuota los
-- cuenta en agosto. El dinero esta bien; el rotulo miente.
--
-- POR QUE ASI Y NO AMPLIANDO LA FUNCION VIVA. La migracion 20260829182500
-- descarto ampliar esta vista, y tenia razon en el fondo: `contratos_cartera_fn`
-- es SECURITY DEFINER con `returns table(...)`, y anadirle una columna exige
-- DROP + CREATE -`create or replace` no puede cambiar el tipo de retorno-. Una
-- funcion viva NO se reteclea. Pero su premisa concreta ya no se sostiene y se
-- comprobo contra produccion el 02/09:
--   * `cronograma_contrato_fn` y `titulares_contrato_fn` llaman a la FUNCION,
--     no a la vista (`strpos(prosrc,'contratos_cartera_fn') > 0`).
--   * solo `atribucion_contrato_fn` nombra la vista, y desde el cuerpo: sin
--     dependencia registrada (`pg_depend` sobre la vista devuelve vacio).
--   * `create or replace view` SI admite ANADIR una columna al final, y conserva
--     OID, grants y `security_invoker`.
-- Asi que no se toca nada vivo: se ENVUELVE. La funcion nueva pregunta a la
-- vieja -que es donde vive la regla de quien ve que contrato- y le pega la
-- fecha. Copiar ese `where` lo haria divergir; preguntarlo, no puede.
--
-- LO QUE NO HACE: no toca la cuota, ni los rankings, ni `capital_episodios`, ni
-- la posibilidad de retro-datar un cierre (hay clientes antiguos sin registrar y
-- Miguel la quiere abierta). Es una columna de LECTURA.

begin;

-- ── Preflight: sobre que estamos construyendo ────────────────────────────────
do $$
declare
  v_cols text;
  v_esperadas constant text :=
    'id,numero_contrato,cliente_id,cliente_nombre,asesor_perfil_id,capital,'
    || 'moneda,tasa_anual,modalidad,tipo_interes,categoria,estado,fecha_inicio,'
    || 'fecha_vencimiento,notas_internas,creado_por,creado_en,'
    || 'producto_condicion_id,producto_id,producto_codigo,producto_version_id,'
    || 'producto_version,producto_nombre,producto_version_estado';
begin
  if to_regclass('crm.contratos_cartera') is null then
    raise exception 'No existe la vista crm.contratos_cartera: ABORTA';
  end if;
  if to_regprocedure('crm.contratos_cartera_fn()') is null then
    raise exception 'No existe crm.contratos_cartera_fn(): ABORTA';
  end if;

  -- La envoltura proyecta las 24 columnas POR NOMBRE. Si la funcion viva ya no
  -- tiene esa forma, la vista saldria distinta y el front descartaria filas en
  -- silencio: mejor abortar aqui.
  select string_agg(a.argname, ',' order by a.ord)
    into v_cols
  from pg_proc p
  cross join lateral unnest(p.proargnames, p.proargmodes)
       with ordinality as a(argname, argmode, ord)
  where p.oid = 'crm.contratos_cartera_fn()'::regprocedure
    and a.argmode = 't';

  if v_cols is distinct from v_esperadas then
    raise exception
      'crm.contratos_cartera_fn() ya no devuelve las 24 columnas esperadas: %',
      v_cols;
  end if;

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'contratos_cartera'
      and c.reloptions @> array['security_invoker=true']
  ) then
    raise exception
      'crm.contratos_cartera dejo de ser security_invoker: ABORTA';
  end if;
end;
$$;

-- ── La envoltura ─────────────────────────────────────────────────────────────
create or replace function crm.contratos_cartera_v2_fn()
returns table(
  id uuid, numero_contrato text, cliente_id uuid, cliente_nombre text,
  asesor_perfil_id uuid, capital numeric, moneda text, tasa_anual numeric,
  modalidad text, tipo_interes text, categoria text, estado text,
  fecha_inicio date, fecha_vencimiento date, notas_internas text,
  creado_por uuid, creado_en timestamptz, producto_condicion_id uuid,
  producto_id uuid, producto_codigo text, producto_version_id uuid,
  producto_version integer, producto_nombre text, producto_version_estado text,
  fecha_cierre_comercial date
)
language sql
stable
security definer
set search_path = ''
as $$
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
$$;

comment on function crm.contratos_cartera_v2_fn() is
  'crm.contratos_cartera_fn() + fecha_cierre_comercial (mes en que se VENDIO, '
  'el mismo con el que se mide la cuota). Envuelve la funcion viva en vez de '
  'reteclearla: el permiso lo sigue poniendo ella.';

-- PUBLIC no basta con revocarselo a anon: si PUBLIC lo tiene, no se cerro nada.
revoke all on function crm.contratos_cartera_v2_fn() from public;
grant execute on function crm.contratos_cartera_v2_fn() to authenticated;
grant execute on function crm.contratos_cartera_v2_fn() to service_role;

-- ── La vista: MISMAS 24 columnas, en el MISMO orden, + la nueva al final ─────
create or replace view crm.contratos_cartera as
select
  id, numero_contrato, cliente_id, cliente_nombre, asesor_perfil_id,
  capital, moneda, tasa_anual, modalidad, tipo_interes, categoria, estado,
  fecha_inicio, fecha_vencimiento, notas_internas, creado_por, creado_en,
  producto_condicion_id, producto_id, producto_codigo, producto_version_id,
  producto_version, producto_nombre, producto_version_estado,
  fecha_cierre_comercial
from crm.contratos_cartera_v2_fn();

alter view crm.contratos_cartera set (security_invoker = true);

-- ── Postflight: que quedo, no que quisimos ──────────────────────────────────
do $$
declare
  v_n int;
  v_ultima text;
  v_sp text;
begin
  select count(*), max(column_name) filter (where ordinal_position = 25)
    into v_n, v_ultima
  from information_schema.columns
  where table_schema = 'crm' and table_name = 'contratos_cartera';

  if v_n <> 25 or v_ultima is distinct from 'fecha_cierre_comercial' then
    raise exception
      'La vista quedo con % columnas y la 25a es %', v_n, v_ultima;
  end if;

  -- Las 24 de siempre siguen donde estaban: si alguna se movio, el front
  -- (que las pide por nombre) no lo notaria, pero cualquier `select *` si.
  if exists (
    select 1
    from information_schema.columns nueva
    join pg_proc p on p.oid = 'crm.contratos_cartera_fn()'::regprocedure
    cross join lateral unnest(p.proargnames, p.proargmodes)
         with ordinality as vieja(argname, argmode, ord)
    where nueva.table_schema = 'crm'
      and nueva.table_name = 'contratos_cartera'
      and vieja.argmode = 't'
      and nueva.ordinal_position = vieja.ord
      and nueva.column_name is distinct from vieja.argname
  ) then
    raise exception 'Las 24 columnas originales cambiaron de sitio: ABORTA';
  end if;

  if not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'crm' and table_name = 'contratos_cartera'
      and grantee = 'authenticated' and privilege_type = 'SELECT'
  ) then
    raise exception 'authenticated perdio el SELECT sobre la vista: ABORTA';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'contratos_cartera'
      and c.reloptions @> array['security_invoker=true']
  ) then
    raise exception 'La vista perdio security_invoker: ABORTA';
  end if;

  -- PUBLIC no puede ejecutar la envoltura. `has_function_privilege` MIENTE
  -- cuando el permiso viene por PUBLIC: se mira el ACL crudo (grantee = 0).
  if exists (
    select 1
    from pg_proc p,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'crm.contratos_cartera_v2_fn()'::regprocedure
      and a.grantee = 0
  ) then
    raise exception 'PUBLIC puede ejecutar contratos_cartera_v2_fn: ABORTA';
  end if;

  -- El search_path vacio se GUARDA con comillas: comprobarlo sin ellas aborta.
  select array_to_string(p.proconfig, ',') into v_sp
  from pg_proc p where p.oid = 'crm.contratos_cartera_v2_fn()'::regprocedure;
  if v_sp is distinct from 'search_path=""' then
    raise exception 'search_path de la envoltura es %, no vacio', v_sp;
  end if;
end;
$$;

commit;
