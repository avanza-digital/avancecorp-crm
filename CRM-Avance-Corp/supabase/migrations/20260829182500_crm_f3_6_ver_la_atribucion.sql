-- P-055 Fase 3.6 - Poder VER de quien es una venta (y su historial).
--
-- QUE, en una linea: una consulta nueva que devuelve el analista de un contrato,
-- si es de prueba, y las reasignaciones que ha tenido. Sin ella, la pantalla no
-- puede mostrar la atribucion ni ofrecer el boton de reasignar.
--
-- POR QUE UNA CONSULTA APARTE Y NO AMPLIAR LA VISTA. El camino "natural" seria
-- anadir las columnas a `crm.contratos_cartera`, que es de donde el CRM lee los
-- contratos. NO SE HACE, y la razon es concreta:
--   * esa vista es `security_invoker=true` -corre como quien llama-, asi que no
--     puede leer `public.contratos` por su cuenta: la RLS se lo impediria. Lee a
--     traves de `crm.contratos_cartera_fn()`, que SI es SECURITY DEFINER.
--   * para que la funcion devuelva columnas nuevas hay que DROP + CREATE -no se
--     puede `create or replace` cambiando el tipo de retorno-, y la vista
--     depende de ella.
--   * y de esa vista dependen ADEMAS `crm.cronograma_contrato_fn` y
--     `crm.titulares_contrato_fn`, las dos `language sql`, o sea con dependencia
--     registrada: habria que tumbarlas y rehacerlas tambien.
--   Total: cuatro objetos vivos del CRM caidos y rehechos en produccion para
--   anadir dos columnas de lectura. No compensa. Esta consulta es aditiva: si
--   algo falla, no se cae nada que hoy funcione.
--
-- EL PERMISO NO SE VUELVE A ESCRIBIR: en vez de copiar el `where` de
-- `contratos_cartera_fn` -que es donde vive la regla de quien ve que contrato-,
-- se PREGUNTA a la vista viva. Copiado, divergiria; preguntado, no puede.
--
-- LAS REASIGNACIONES: con nombre y motivo, pero NO para todo el que ve el
-- contrato (hallazgo A3 del auditor RLS): el gate de la vista es el asesor DEL
-- CLIENTE, y la premisa de esta fase es que ese asesor puede NO ser el analista
-- de la venta. Sin este recorte, el comercial A leeria el motivo que gerencia
-- escribio sobre el comercial B — informacion de desempeno de un par. El
-- historial se devuelve solo a la autoridad que ya puede leer la tabla del
-- rastro (gestor de cartera o gerencia, con P04) o AL PROPIO analista de la
-- venta; para el resto, lista vacia. El nombre del analista y la marca de demo
-- si quedan al ambito de la vista: son la explicacion de la ficha, no un
-- expediente.
--
-- ⚠️ INVARIANTE DE LA QUE DEPENDE ESTA FUNCION (hallazgo N4): la delegacion es
-- correcta MIENTRAS `crm.contratos_cartera` siga siendo una vista invoker
-- apoyada en `crm.contratos_cartera_fn()` (DEFINER con `where` por auth.uid()).
-- Si un dia esa vista pasa a leer `public.contratos` con RLS, ESTA funcion
-- -duena postgres, que salta RLS- pasaria a devolver TODO en silencio.

begin;

do $preflight$
begin
  if to_regclass('crm.contratos_cartera') is null then
    raise exception 'No existe la vista crm.contratos_cartera: ABORTA';
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname in ('analista_cierre_id','es_demo') and not attisdropped
                 group by attrelid having count(*) = 2) then
    raise exception 'Falta la migracion 20260829180000: ABORTA';
  end if;
  if to_regclass('crm.reasignaciones_analista') is null then
    raise exception 'Falta la migracion 20260829181500 (el rastro): ABORTA';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='crm' and p.proname='atribucion_contrato_fn') then
    raise exception 'Ya existe crm.atribucion_contrato_fn: ABORTA';
  end if;
end
$preflight$;

set local lock_timeout = '5s';

create function crm.atribucion_contrato_fn(p_contrato_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $fn$
  select case
    -- La MISMA regla de visibilidad que ya gobierna los contratos del CRM: se
    -- pregunta a la vista viva en vez de copiar su `where`.
    when not exists (
      select 1 from crm.contratos_cartera v where v.id = p_contrato_id
    ) then null
    else (
      select jsonb_build_object(
        'contrato_id',   c.id,
        'analista_id',   c.analista_cierre_id,
        'analista_nombre', pa.nombre_completo,
        'es_demo',       c.es_demo,
        'registrado_por', pr.nombre_completo,
        'reasignaciones', case
          -- El historial con motivos, solo para la autoridad o el propio
          -- analista (A3). Mismo conjunto que la policy de la tabla, con P04.
          when (((select public.es_gestor_cartera())
                 or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
                and not (select private.membresia_crm_revocada()))
               or c.analista_cierre_id = (select auth.uid())
          then coalesce((
            select jsonb_agg(jsonb_build_object(
              'cuando',  r.reasignado_en,
              'de',      pde.nombre_completo,
              'a',       pa2.nombre_completo,
              'motivo',  r.motivo,
              'por',     ppor.nombre_completo
            ) order by r.reasignado_en desc)
            from crm.reasignaciones_analista r
            left join public.perfiles pde  on pde.id  = r.analista_de
            left join public.perfiles pa2  on pa2.id  = r.analista_a
            left join public.perfiles ppor on ppor.id = r.reasignado_por
            where r.contrato_id = c.id
          ), '[]'::jsonb)
          else '[]'::jsonb
        end
      )
      from public.contratos c
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles pr on pr.id = c.creado_por
      where c.id = p_contrato_id
    )
  end;
$fn$;

revoke execute on function crm.atribucion_contrato_fn(uuid) from public, anon;
grant  execute on function crm.atribucion_contrato_fn(uuid) to authenticated, service_role;

comment on function crm.atribucion_contrato_fn(uuid) is
  'De quien es una venta, si es de prueba, y su historial de reasignaciones (P-055 Fase 3). Devuelve NULL si quien pregunta no puede ver ese contrato: la regla la pone crm.contratos_cartera, no esta funcion.';

do $postflight$
declare v_abierta text; v_cfg text[]; v_secdef boolean;
begin
  select p.prosecdef, p.proconfig into v_secdef, v_cfg
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='crm' and p.proname='atribucion_contrato_fn';

  if v_secdef is null then raise exception 'POSTFLIGHT: no se creo la funcion'; end if;
  if not v_secdef then raise exception 'POSTFLIGHT: no quedo SECURITY DEFINER'; end if;
  -- ⚠️ `search_path=""` se guarda CON comillas.
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: sin search_path vacio (%)', v_cfg; end if;

  -- A3: el recorte del historial tiene que estar en el cuerpo vivo.
  if (select strpos(p.prosrc, 'membresia_crm_revocada') = 0
             or strpos(p.prosrc, 'analista_cierre_id = (select auth.uid())') = 0
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='crm' and p.proname='atribucion_contrato_fn') then
    raise exception 'POSTFLIGHT: el historial quedo sin el recorte de autoridad (A3)';
  end if;

  select string_agg(distinct coalesce(pr.rolname,'PUBLIC'), ', ') into v_abierta
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join lateral aclexplode(p.proacl) a
  left join pg_roles pr on pr.oid=a.grantee
  where n.nspname='crm' and p.proname='atribucion_contrato_fn'
    and a.privilege_type='EXECUTE' and (a.grantee = 0 or pr.rolname='anon');
  if v_abierta is not null then
    raise exception 'POSTFLIGHT: quedo abierta a %', v_abierta; end if;

  -- La vista y sus dos dependientes siguen INTACTAS: no se toco ninguna.
  if to_regclass('crm.contratos_cartera') is null
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='crm' and p.proname in ('cronograma_contrato_fn','titulares_contrato_fn')
                    group by n.nspname having count(*) = 2) then
    raise exception 'POSTFLIGHT: se toco algo de la vista o sus dependientes';
  end if;

  raise notice 'POSTFLIGHT OK: la atribucion se puede consultar sin haber tocado nada vivo';
end
$postflight$;

commit;
