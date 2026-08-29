-- P-055 Fase 3.1 - El campo «analista que cierra» y la marca de demo.
--
-- TOCA `public`: con permiso explicito de Miguel. Es la decision 2 del plan
-- maestro («se crea y es obligatorio desde ya») y la decision 6 («444444 y
-- 888282 son demos → se excluyen de metricas y ranking»). Esta migracion es
-- SOLO ESTRUCTURA: no rellena nada, no cambia ninguna funcion viva y no cambia
-- lo que ve nadie. El relleno va en 20260829180500 y el uso en 20260829181000.
--
-- POR QUE HACEN FALTA DOS COLUMNAS Y NO UNA:
--
-- 1) `analista_cierre_id` - DE QUIEN ES LA VENTA.
--    Hoy no existe ese dato. Lo que hay son tres cosas que NO sirven:
--      * `creado_por` es QUIEN LA TECLEO. Codex lo refuto como regla universal:
--        16 contratos los registro gerencia, y en 3 casos para asesores
--        distintos. Se conserva intacto -es el registrador y tiene su valor de
--        auditoria- y NO se pisa.
--      * `perfiles.asesor_perfil_id` es el analista DEL CLIENTE. Decision 1 de
--        Miguel: ese vinculo existe «para que el cliente vea a su analista en la
--        app; NO es la guia del ranking».
--      * `crm.leads.contrato_id` esta MUERTO: 0 de 466 contratos tienen lead
--        enlazado. Medido el 2026-08-29.
--    Se acepta NULL a proposito. La decision 18 dice que 12 contratos «se quedan
--    SIN DUENO y fuera del ranking historico», asi que el vacio es un estado
--    legitimo del dato, no un descuido. La obligatoriedad vive en la puerta de
--    entrada (`crear_contrato`, migracion 181000), que es donde puede exigirse
--    sin mentirle al historico.
--
-- 2) `es_demo` - LO QUE NO ES UNA VENTA.
--    Decision 6: 444444 y 888282 son demos de Kirk. Hoy no hay forma de
--    marcarlos, asi que o se excluyen a mano por numero en cada consulta -y se
--    olvida en la siguiente- o contaminan el ranking. La columna existe tambien
--    «para los que vengan», como pide el §5 del plan.
--
-- EL RASTRO YA ESTA: `public.contratos` tiene `trg_audit_contratos` colgado de
-- `public.log_audit_change`, asi que cada cambio de estas dos columnas queda
-- registrado con quien y cuando, sin anadir nada. Verificado en el preflight.
--
-- LO QUE ESTA MIGRACION NO HACE, Y NO ES UN OLVIDO:
--   * no rellena ni un solo contrato (eso es 180500);
--   * no toca `crear_contrato` ni `actualizar_contrato` (eso es 181000);
--   * no crea la reasignacion (eso es 181500);
--   * no excluye los demos de ninguna metrica todavia: la columna nace y nadie
--     la lee. Encenderla es un paso aparte y medible.

begin;

-- ---------------------------------------------------------------- PREFLIGHT --
do $preflight$
begin
  if to_regclass('public.contratos') is null then
    raise exception 'No existe public.contratos: ABORTA';
  end if;

  -- No se pisa nada que ya exista con esos nombres.
  if exists (select 1 from pg_attribute
             where attrelid = 'public.contratos'::regclass
               and attname in ('analista_cierre_id','es_demo')
               and not attisdropped) then
    raise exception 'Ya existe analista_cierre_id o es_demo en public.contratos: ABORTA';
  end if;

  -- El rastro tiene que estar ANTES de crear el campo, o los cambios de
  -- atribucion -que son de pago- no dejarian huella.
  if not exists (
    select 1 from pg_trigger tg
    join pg_proc p on p.oid = tg.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where tg.tgrelid = 'public.contratos'::regclass
      and not tg.tgisinternal
      and n.nspname = 'public' and p.proname = 'log_audit_change'
  ) then
    raise exception 'public.contratos no tiene auditoria colgada: ABORTA (el campo de atribucion no puede nacer sin rastro)';
  end if;

  if to_regclass('public.perfiles') is null then
    raise exception 'No existe public.perfiles: ABORTA';
  end if;
end
$preflight$;

-- ------------------------------------------------------------------ CAMBIO --
set local lock_timeout = '5s';

-- Sin NOT NULL y sin default: anadir una columna nula no reescribe la tabla ni
-- toma candado largo. 466 filas hoy, pero la regla vale igual manana.
alter table public.contratos
  add column analista_cierre_id uuid,
  add column es_demo boolean not null default false;

-- A `crm.equipo`, no a `perfiles` (hallazgo P1-2 de Codex): el candado de la
-- columna es BEFORE UPDATE y las policies de INSERT de contratos estan abiertas
-- a es_admin(), asi que un INSERT directo por la API podia nacer con un CLIENTE
-- como analista. Con la FK al equipo, eso lo rechaza la base aunque todas las
-- demas puertas fallen. Sin ON DELETE: borrar a alguien con ventas atribuidas
-- tiene que reventar, no vaciar la autoria (y la decision 21 ya impide borrar a
-- quien tiene historia de equipo). Mismo precedente: cierres_externos.vendedor_id.
alter table public.contratos
  add constraint contratos_analista_cierre_id_fkey
  foreign key (analista_cierre_id) references crm.equipo(perfil_id);

-- El ranking agrupa por analista y mes: sin este indice, cada tablero se come
-- un recorrido completo de la tabla. Parcial porque los sin dueno no se buscan.
create index if not exists contratos_analista_cierre_idx
  on public.contratos (analista_cierre_id, fecha_cierre_comercial)
  where analista_cierre_id is not null;

-- Y el atajo para saltarse las pruebas, que es lo unico que se preguntara de
-- `es_demo` en las metricas.
create index if not exists contratos_es_demo_idx
  on public.contratos (es_demo)
  where es_demo;

comment on column public.contratos.analista_cierre_id is
  'El analista de quien es la venta (decision 1 y 2 del plan P-055). NO es quien la tecleo -eso es creado_por- ni el analista del cliente -eso es perfiles.asesor_perfil_id, que segun la decision 1 no guia el ranking-. Puede ser NULL: la decision 18 deja 12 contratos historicos sin dueno a proposito. Reasignable, y cada reasignacion queda en audit_log.';

comment on column public.contratos.es_demo is
  'Contrato de prueba, fuera de metricas y ranking (decision 6: 444444 y 888282, de Kirk). Existe tambien para los que vengan.';

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_fk       text;
  v_nulos    integer;
  v_demos    integer;
  v_indices  integer;
begin
  -- Las columnas nacieron con la forma pedida.
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='analista_cierre_id' and atttypid='uuid'::regtype
                   and not attnotnull and not attisdropped) then
    raise exception 'POSTFLIGHT: analista_cierre_id no quedo como uuid nullable';
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='es_demo' and atttypid='bool'::regtype
                   and attnotnull and not attisdropped) then
    raise exception 'POSTFLIGHT: es_demo no quedo como boolean NOT NULL';
  end if;

  select pg_get_constraintdef(oid) into v_fk
  from pg_constraint
  where conrelid='public.contratos'::regclass
    and conname='contratos_analista_cierre_id_fkey';
  if v_fk is null or v_fk !~ 'REFERENCES crm\.equipo\(perfil_id\)' then
    raise exception 'POSTFLIGHT: la clave foranea al equipo no quedo (%)', coalesce(v_fk,'(ninguna)');
  end if;
  -- Sin ON DELETE: borrar un perfil atribuido tiene que reventar, no vaciar.
  if v_fk ~* 'ON DELETE (SET NULL|CASCADE)' then
    raise exception 'POSTFLIGHT: la clave foranea vacia la autoria al borrar un perfil (%)', v_fk;
  end if;

  select count(*) into v_indices from pg_indexes
  where schemaname='public' and tablename='contratos'
    and indexname in ('contratos_analista_cierre_idx','contratos_es_demo_idx');
  if v_indices <> 2 then
    raise exception 'POSTFLIGHT: faltan indices (%)', v_indices;
  end if;

  -- ESTA MIGRACION NO RELLENA NADA. Si algo quedo escrito, es un error.
  select count(*) filter (where analista_cierre_id is not null),
         count(*) filter (where es_demo)
    into v_nulos, v_demos
  from public.contratos;
  if v_nulos <> 0 or v_demos <> 0 then
    raise exception 'POSTFLIGHT: la migracion de ESTRUCTURA escribio datos (% con analista, % demos): ABORTA', v_nulos, v_demos;
  end if;

  raise notice 'POSTFLIGHT OK: campo de atribucion y marca de demo creados, vacios y con rastro';
end
$postflight$;

commit;
