-- P-055 Fase 3.4 - Reasignar el analista de una venta, dejando rastro.
--
-- TOCA `public` (una funcion nueva y un trigger sobre `public.contratos`): con
-- permiso explicito de Miguel. La tabla del rastro vive en `crm`.
--
-- QUE, en una linea: se crea la unica puerta por la que la atribucion de una
-- venta puede cambiar, y se cierra cualquier otra.
--
-- DE DONDE SALE: decision 2 del plan («debe poder reasignarse despues») y §5
-- («campo nuevo, inmutable, reasignable CON RASTRO»). «Inmutable» y
-- «reasignable» no se contradicen: quiere decir que no se mueve solo ni por un
-- UPDATE cualquiera — se mueve por una puerta, con un motivo y con nombre.
--
-- CUATRO PIEZAS (la cuarta la exigio el auditor RLS — hallazgo A1: se habia
-- protegido con puerta y motivo el campo que mueve una etiqueta y dejado
-- abierto `es_demo`, que APAGA la venta entera en 7 metricas y en el sello):
--
-- 1) `crm.reasignaciones_analista` - el rastro. Hace falta una tabla propia
--    porque el MOTIVO no tiene donde vivir: `public.contratos` no tiene esa
--    columna y `crm.actividades` cuelga de un LEAD, y un contrato no es de
--    ningun lead (es la misma razon por la que el cierre de mes tampoco escribe
--    ahi). Es append-only: una reasignacion no se edita ni se borra.
--
-- 2) `public.reasignar_analista_contrato(...)` - la puerta. Exige motivo, como
--    lo exige `crm.anular_cierre_externo`, y por la misma razon escrita alli:
--    esto le mueve el merito -y manana el pago- de una persona a otra, y esa
--    persona merece una razon escrita y no un registro mudo.
--
-- 3) `trg_contratos_analista_solo_por_la_puerta` - el candado. Sin el, la
--    puerta seria decorativa: la politica `contratos_admin_actualiza` deja a
--    cualquier admin del portal hacer un UPDATE directo por la API y mover la
--    atribucion sin motivo y sin rastro. El candado usa la valvula por
--    transaccion que ya usa este proyecto (`current_setting(..., true) = 'on'`,
--    igual que `crm.op_privilegiada` en los cierres externos), con nombre
--    PROPIO para que ninguna otra operacion privilegiada la abra por accidente.
--
-- 4) `trg_contratos_demo_solo_por_la_puerta` + `public.marcar_contrato_demo`.
--    El mismo par candado+puerta, con SU PROPIA valvula (no se comparte la de
--    reasignar: una operacion privilegiada no debe abrir la otra por accidente)
--    y trigger APARTE del de analista — la leccion registrada del proyecto es
--    que ampliar el `UPDATE OF` de un trigger existente via DROP+CREATE borra
--    clausulas en silencio. Marcar/desmarcar es SOLO de gerencia, exige motivo,
--    y el motivo queda en `public.audit_log` como fila propia (tabla
--    'contratos', operacion 'demo_marca'): el cambio de la columna ya lo audita
--    `trg_audit_contratos`, pero la RAZON no tenia donde vivir.
--
-- QUIEN PUEDE REASIGNAR, y por que ese conjunto: el mismo que ya puede corregir
-- cualquier contrato en `public.actualizar_contrato` -gestor de cartera o
-- gerencia del CRM, con la comprobacion P04 de membresia revocada-. Miguel no
-- dijo quien reasigna, asi que NO SE INVENTA UN CONJUNTO NUEVO: se reutiliza el
-- que el sistema ya trata como autoridad administrativa. Si quiere acotarlo solo
-- a gerencia, es una linea.
--
-- LO QUE NO HACE: no toca `creado_por` -el registrador es otra cosa y se
-- conserva-, no toca ninguna metrica, y no permite reasignar un contrato marcado
-- como demo (no es una venta: no tiene a quien atribuirse).

begin;

-- ---------------------------------------------------------------- PREFLIGHT --
do $preflight$
begin
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='analista_cierre_id' and not attisdropped) then
    raise exception 'Falta la migracion 20260829180000 (el campo): ABORTA';
  end if;
  if to_regclass('crm.reasignaciones_analista') is not null then
    raise exception 'Ya existe crm.reasignaciones_analista: ABORTA';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='reasignar_analista_contrato') then
    raise exception 'Ya existe public.reasignar_analista_contrato: ABORTA';
  end if;
  -- El candado tiene sentido porque HAY una puerta trasera abierta hoy.
  if not exists (select 1 from pg_policy
                 where polrelid='public.contratos'::regclass and polcmd = 'w') then
    raise warning 'No hay politica de UPDATE sobre contratos; el candado se instala igual';
  end if;
end
$preflight$;

set local lock_timeout = '5s';

-- ---------------------------------------------------------- 1) EL RASTRO --
create table crm.reasignaciones_analista (
  id            uuid primary key default gen_random_uuid(),
  contrato_id   uuid not null references public.contratos(id) on delete restrict,
  -- A crm.equipo, no a perfiles: a nivel de BD un cliente no cabe en el rastro
  -- (mismo precedente que cierres_externos.vendedor_id). `reasignado_por` si va
  -- a perfiles: quien reasigna puede ser un admin del portal que no es del
  -- equipo comercial.
  analista_de   uuid references crm.equipo(perfil_id),
  analista_a    uuid not null references crm.equipo(perfil_id),
  motivo        text not null,
  reasignado_por uuid not null references public.perfiles(id),
  reasignado_en timestamptz not null default now(),
  constraint reasignaciones_motivo_no_vacio
    check (btrim(motivo) <> '' and length(motivo) <= 300),
  constraint reasignaciones_cambia_de_verdad
    check (analista_de is distinct from analista_a)
);

create index reasignaciones_analista_contrato_idx
  on crm.reasignaciones_analista (contrato_id, reasignado_en desc);

comment on table crm.reasignaciones_analista is
  'Rastro de cada cambio de atribucion de una venta (P-055 Fase 3). Append-only: quien la tenia, quien la tiene, por que y quien lo hizo.';

alter table crm.reasignaciones_analista enable row level security;

-- Lectura: la misma autoridad administrativa que puede reasignar. Nadie
-- escribe por la API: la unica escritura es la RPC, que es SECURITY DEFINER.
create policy reasignaciones_lee_autoridad
  on crm.reasignaciones_analista for select to authenticated
  using (
    ((select public.es_gestor_cartera())
     or coalesce(private.rol_crm((select auth.uid())) = 'gerencia', false))
    -- P04: una membresia CRM revocada manda tambien sobre la LECTURA del
    -- rastro, igual que en la RPC (hallazgo M6; patron de operaciones_cartera).
    and not (select private.membresia_crm_revocada())
  );

-- `public` incluido: la leccion de la casa es que revocar a `anon` no basta.
-- Y NADA para `service_role` (hallazgo M5): la RPC es SECURITY DEFINER y corre
-- como postgres, asi que ese rol no necesita tocar la tabla — y como salta la
-- RLS, cualquier portador de la llave podria FABRICAR filas de rastro sin el
-- UPDATE correspondiente. Mismo criterio que crm.operaciones_cartera.
revoke all on crm.reasignaciones_analista from public, anon, authenticated, service_role;
grant select on crm.reasignaciones_analista to authenticated;

-- Append-only de verdad, no por convencion.
create or replace function private.trg_reasignaciones_append_only()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  raise exception using
    errcode = 'P0409',
    message = 'El rastro de reasignaciones no se edita ni se borra';
end;
$$;

create trigger trg_reasignaciones_00_append_only
  before update or delete on crm.reasignaciones_analista
  for each row execute function private.trg_reasignaciones_append_only();

-- La regla de la casa: toda tabla de crm.* audita via private.log_audit_crm
-- (hallazgo M4; el id es uuid, asi que no muerde la trampa de usuario_eventos).
-- UPDATE y DELETE nunca llegaran (el append-only los revienta antes), pero se
-- declaran igual: si un dia alguien baja ese candado, el rastro no se queda ciego.
create trigger trg_audit_reasignaciones_analista
  after insert or update or delete on crm.reasignaciones_analista
  for each row execute function private.log_audit_crm();

-- ------------------------------------------------------------ 3) EL CANDADO --
-- (va antes que la puerta: si la puerta se creara primero y algo fallara
--  despues, quedaria una puerta sin candado)
create or replace function private.trg_contratos_analista_solo_por_la_puerta()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  v_por_la_puerta boolean :=
    coalesce(current_setting('crm.reasignando_analista', true) = 'on', false);
begin
  if new.analista_cierre_id is distinct from old.analista_cierre_id
     and not v_por_la_puerta then
    raise exception using
      errcode = 'P0409',
      message = 'La atribucion de una venta solo se cambia con public.reasignar_analista_contrato',
      hint    = 'Hace falta un motivo escrito: mover el merito de una persona a otra no se hace en silencio.';
  end if;
  return new;
end;
$$;

create trigger trg_contratos_analista_solo_por_la_puerta
  before update of analista_cierre_id on public.contratos
  for each row execute function private.trg_contratos_analista_solo_por_la_puerta();

-- El candado de `es_demo` (hallazgo A1). Trigger APARTE a proposito.
create or replace function private.trg_contratos_demo_solo_por_la_puerta()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  v_por_la_puerta boolean :=
    coalesce(current_setting('crm.marcando_demo', true) = 'on', false);
begin
  if new.es_demo is distinct from old.es_demo and not v_por_la_puerta then
    raise exception using
      errcode = 'P0409',
      message = 'La marca de prueba solo se cambia con public.marcar_contrato_demo',
      hint    = 'Marcar un contrato como prueba lo saca de todas las metricas y del sello mensual: eso exige motivo escrito y autoridad de gerencia.';
  end if;
  return new;
end;
$$;

create trigger trg_contratos_demo_solo_por_la_puerta
  before update of es_demo on public.contratos
  for each row execute function private.trg_contratos_demo_solo_por_la_puerta();

-- Y el INSERT (P1-2 de Codex): sin esto, un INSERT directo por la API con
-- es_demo=true nace marcado sin motivo ni puerta. `crear_contrato` nunca lo
-- manda, asi que el camino legitimo no lo nota.
create or replace function private.trg_contratos_demo_no_nace_marcado()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.es_demo
     and not coalesce(current_setting('crm.marcando_demo', true) = 'on', false) then
    raise exception using
      errcode = 'P0409',
      message = 'Un contrato no nace marcado como prueba: se marca despues con public.marcar_contrato_demo';
  end if;
  return new;
end;
$$;

create trigger trg_contratos_demo_no_nace_marcado
  before insert on public.contratos
  for each row execute function private.trg_contratos_demo_no_nace_marcado();

-- ------------------------------------------------------------- 2) LA PUERTA --
create or replace function public.reasignar_analista_contrato(
  p_contrato_id uuid,
  p_analista_id uuid,
  p_motivo      text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $fn$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_motivo text := btrim(p_motivo);
  v_row    public.contratos%rowtype;
  v_id     uuid;
begin
  -- El mismo conjunto que ya puede corregir cualquier contrato.
  if v_uid is null
     or not ((select public.es_gestor_cartera())
             or coalesce(v_rol = 'gerencia', false)) then
    raise insufficient_privilege using
      message = 'No autorizado para reasignar la venta';
  end if;
  -- P04: una membresia CRM revocada manda sobre el poder de portal.
  if (select private.membresia_crm_revocada()) then
    raise insufficient_privilege using
      message = 'Tu membresia CRM fue revocada; no puedes reasignar ventas';
  end if;

  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo de la reasignacion' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres' using errcode = '22023';
  end if;

  select * into v_row from public.contratos where id = p_contrato_id for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if v_row.es_demo then
    raise exception 'Un contrato de prueba no se atribuye a nadie' using errcode = '22023';
  end if;

  if p_analista_id is null then
    raise exception 'Elige el analista al que pasa la venta' using errcode = '22023';
  end if;
  -- Igual que en el alta: del equipo comercial, sin exigir que siga ACTIVO
  -- (decision 15: la venta de quien ya no esta cuenta igual). Los roles
  -- OFF-ROSTER (coordinador reparte la cola, directorio solo lee) no son filas
  -- del organigrama comercial por diseno documentado del sistema: una venta no
  -- puede ser suya (P1-2 de Codex).
  if not exists (select 1 from crm.equipo e
                 where e.perfil_id = p_analista_id
                   and e.rol_crm in ('vendedor','supervisor','gerencia')) then
    raise exception 'El analista tiene que ser del equipo comercial' using errcode = '22023';
  end if;
  if v_row.analista_cierre_id is not distinct from p_analista_id then
    raise exception 'Esa venta ya esta atribuida a esa persona' using errcode = 'P0409';
  end if;

  insert into crm.reasignaciones_analista (
    contrato_id, analista_de, analista_a, motivo, reasignado_por
  ) values (
    p_contrato_id, v_row.analista_cierre_id, p_analista_id, v_motivo, v_uid
  ) returning id into v_id;

  -- La valvula, solo para esta sentencia y solo en esta transaccion.
  perform set_config('crm.reasignando_analista', 'on', true);
  update public.contratos
     set analista_cierre_id = p_analista_id
   where id = p_contrato_id;
  perform set_config('crm.reasignando_analista', 'off', true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'de', v_row.analista_cierre_id,
    'a', p_analista_id,
    'reasignacion_id', v_id);
end;
$fn$;

revoke execute on function public.reasignar_analista_contrato(uuid, uuid, text) from public, anon;
grant execute on function public.reasignar_analista_contrato(uuid, uuid, text)
  to authenticated, service_role;

-- ------------------------------------------- 4b) LA PUERTA DE LA MARCA DEMO --
-- El catalogo de operaciones del registro admite una nueva: `demo_marca`.
-- `audit_log.operacion` tiene un CHECK con INSERT/UPDATE/DELETE; la fila del
-- motivo no es ninguna de las tres -no describe un DML, describe un ACTO
-- administrativo- y colarla como 'UPDATE' duplicaria la fila del trigger y
-- mentiria. Se amplia el catalogo, que es para lo que esta esa columna. La
-- bandeja de actividad de gerencia la mostrara tal cual, que es deseable.
do $check$
declare v_def text;
begin
  -- P2-2 (Codex): el DROP depende del nombre y la forma del CHECK vivo. Se
  -- valida ANTES: si el catalogo difiere de lo esperado, ABORTA en vez de
  -- tirar un constraint que no es el que se cree.
  select pg_get_constraintdef(oid) into v_def
  from pg_constraint
  where conrelid = 'public.audit_log'::regclass
    and conname = 'audit_log_operacion_check' and contype = 'c';
  if v_def is null then
    raise exception 'No existe audit_log_operacion_check como CHECK: ABORTA (revisar el catalogo)';
  end if;
  if v_def !~ 'INSERT' or v_def !~ 'UPDATE' or v_def !~ 'DELETE' then
    raise exception 'audit_log_operacion_check no tiene la forma esperada (%): ABORTA', v_def;
  end if;
  if v_def ~ 'demo_marca' then
    raise exception 'audit_log_operacion_check ya admite demo_marca: ABORTA (¿re-run?)';
  end if;
end $check$;

alter table public.audit_log drop constraint audit_log_operacion_check;
alter table public.audit_log add constraint audit_log_operacion_check
  check (operacion = any (array['INSERT','UPDATE','DELETE','demo_marca']));


create or replace function public.marcar_contrato_demo(
  p_contrato_id uuid,
  p_es_demo     boolean,
  p_motivo      text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $fn$
declare
  v_uid    uuid := (select auth.uid());
  v_rol    text := private.rol_crm((select auth.uid()));
  v_motivo text := btrim(p_motivo);
  v_row    public.contratos%rowtype;
begin
  -- SOLO gerencia: esto borra (o resucita) la produccion de un analista en
  -- todas las metricas y en el sello. Mas estrecho que reasignar, a proposito.
  if v_uid is null or coalesce(v_rol, '') <> 'gerencia' then
    raise insufficient_privilege using
      message = 'Solo gerencia marca un contrato como prueba';
  end if;
  if (select private.membresia_crm_revocada()) then
    raise insufficient_privilege using
      message = 'Tu membresia CRM fue revocada; no puedes marcar contratos';
  end if;

  if p_es_demo is null then
    raise exception 'Di si el contrato es de prueba o deja de serlo' using errcode = '22023';
  end if;
  if v_motivo is null or v_motivo = '' then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;
  if length(v_motivo) > 300 then
    raise exception 'El motivo admite como maximo 300 caracteres' using errcode = '22023';
  end if;

  select * into v_row from public.contratos where id = p_contrato_id for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  if v_row.es_demo = p_es_demo then
    raise exception 'El contrato ya esta asi' using errcode = 'P0409';
  end if;

  -- P1-3 (Codex): marcar o desmarcar cambia lo que SUMAN las metricas vivas.
  -- Si el mes comercial de este contrato ya esta SELLADO, hacerlo partiria la
  -- historia en dos verdades (la foto sellada contra las pantallas vivas) y,
  -- concurrente con el sellado, seria una carrera. Mismo cerrojo y misma regla
  -- que la correccion de la fecha comercial (20260824170630): el mes sellado
  -- no se reescribe.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (date_trunc('month', v_row.fecha_cierre_comercial)::date - date '2000-01-01')::integer
  );
  if exists (select 1 from crm.periodos_cerrados pc
             where pc.periodo = date_trunc('month', v_row.fecha_cierre_comercial)::date) then
    raise exception using
      errcode = 'P0409',
      message = format('El mes %s ya esta sellado: la marca de prueba no se cambia sobre un mes cerrado',
                       to_char(v_row.fecha_cierre_comercial, 'YYYY-MM')),
      hint    = 'Lo sellado no se reescribe. Si el contrato no debio contar, se corrige en el mes vivo con gerencia.';
  end if;

  perform set_config('crm.marcando_demo', 'on', true);
  update public.contratos set es_demo = p_es_demo where id = p_contrato_id;
  perform set_config('crm.marcando_demo', 'off', true);

  -- La RAZON, en el mismo registro donde vive el cambio. `trg_audit_contratos`
  -- ya dejo la fila del UPDATE con antes/despues; esta fila hermana lleva el
  -- motivo y se distingue por su operacion propia.
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values ('contratos', 'demo_marca', p_contrato_id::text, v_uid,
          jsonb_build_object('es_demo', v_row.es_demo),
          jsonb_build_object('es_demo', p_es_demo, 'motivo', v_motivo));

  return jsonb_build_object('ok', true, 'contrato_id', p_contrato_id, 'es_demo', p_es_demo);
end;
$fn$;

revoke execute on function public.marcar_contrato_demo(uuid, boolean, text) from public, anon;
grant execute on function public.marcar_contrato_demo(uuid, boolean, text)
  to authenticated, service_role;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_abiertas text;
begin
  if to_regclass('crm.reasignaciones_analista') is null then
    raise exception 'POSTFLIGHT: no se creo la tabla del rastro'; end if;
  if not (select relrowsecurity from pg_class where oid='crm.reasignaciones_analista'::regclass) then
    raise exception 'POSTFLIGHT: el rastro se quedo sin seguridad por filas'; end if;
  if not exists (select 1 from pg_trigger where tgrelid='crm.reasignaciones_analista'::regclass
                 and tgname='trg_reasignaciones_00_append_only') then
    raise exception 'POSTFLIGHT: el rastro no quedo append-only'; end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.contratos'::regclass
                 and tgname='trg_contratos_analista_solo_por_la_puerta') then
    raise exception 'POSTFLIGHT: no quedo el candado sobre la atribucion'; end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.contratos'::regclass
                 and tgname='trg_contratos_demo_solo_por_la_puerta') then
    raise exception 'POSTFLIGHT: no quedo el candado sobre la marca de demo'; end if;
  if (select pg_get_triggerdef(oid) from pg_trigger
      where tgrelid='public.contratos'::regclass
        and tgname='trg_contratos_demo_solo_por_la_puerta') !~ 'UPDATE OF es_demo' then
    raise exception 'POSTFLIGHT: el candado de demo no quedo acotado a su columna'; end if;
  if not exists (select 1 from pg_trigger where tgrelid='crm.reasignaciones_analista'::regclass
                 and tgname='trg_audit_reasignaciones_analista') then
    raise exception 'POSTFLIGHT: el rastro quedo sin auditoria de la casa'; end if;

  -- El candado tiene que mirar SOLO esa columna: si vigilara toda la fila,
  -- frenaria correcciones legitimas de otros campos.
  if (select pg_get_triggerdef(oid) from pg_trigger
      where tgrelid='public.contratos'::regclass
        and tgname='trg_contratos_analista_solo_por_la_puerta')
     !~ 'UPDATE OF analista_cierre_id' then
    raise exception 'POSTFLIGHT: el candado no quedo acotado a la columna de atribucion';
  end if;

  -- La puerta no queda abierta a los visitantes sin cuenta.
  select string_agg(distinct coalesce(pr.rolname,'PUBLIC'), ', ')
    into v_abiertas
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join lateral aclexplode(p.proacl) a
  left join pg_roles pr on pr.oid = a.grantee
  where n.nspname='public' and p.proname in ('reasignar_analista_contrato','marcar_contrato_demo')
    and a.privilege_type='EXECUTE' and (a.grantee = 0 or pr.rolname = 'anon');
  if v_abiertas is not null then
    raise exception 'POSTFLIGHT: una puerta quedo abierta a % ', v_abiertas;
  end if;

  -- El catalogo de operaciones del registro: ampliado con demo_marca y cerrado.
  if (select pg_get_constraintdef(oid) from pg_constraint
      where conrelid='public.audit_log'::regclass
        and conname='audit_log_operacion_check') !~ 'demo_marca' then
    raise exception 'POSTFLIGHT: el catalogo de operaciones no admite demo_marca';
  end if;

  -- M5: service_role NO recupera permisos sobre el rastro por ningun camino.
  if exists (
    select 1 from pg_class c
    cross join lateral aclexplode(c.relacl) a
    join pg_roles pr on pr.oid = a.grantee
    where c.oid = 'crm.reasignaciones_analista'::regclass
      and pr.rolname = 'service_role'
  ) then
    raise exception 'POSTFLIGHT: service_role quedo con permisos sobre el rastro';
  end if;

  raise notice 'POSTFLIGHT OK: la atribucion solo se mueve por la puerta, con motivo y con rastro';
end
$postflight$;

commit;
