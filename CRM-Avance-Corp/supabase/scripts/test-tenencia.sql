-- Oraculo transaccional autocontenido de `crm.leads.tenencia_desde` (el reloj
-- del vendedor). Exito = token TENENCIA_TX_OK; todo queda en rollback.
--
-- La invariante central: `tenencia_desde` mide desde que el lead ENTRO A LAS
-- MANOS DE SU ASESOR, no desde que entro al CRM. Un lead que paso 3 dias en la
-- cola de Rosa y hoy le cae a un vendedor NO puede nacer en rojo.
--
-- Cubre: alta con y sin dueno, la ASIGNACION (el caso de Miguel), la igualdad
-- exacta con el ledger crm.lead_asignaciones en cada camino, la inmunidad al
-- ruido, la transferencia entre vendedores, el parqueo, el CIERRE (terminal
-- apaga el reloj) y la REAPERTURA (el descartado que vuelve al mismo asesor
-- estrena reloj — hallazgo A1 de la auditoria), la infalsificabilidad REAL
-- desde una sesion authenticated, el orden de disparo del trigger y el estado
-- honesto de los grants.
--
-- NOTA de alcance (auditoria, B3): V02/V03 no pueden distinguir `new.creado_en`
-- de `statement_timestamp()` porque trg_leads_00_guard_tenencia fija
-- `creado_en := statement_timestamp()` en ese mismo statement; ambas
-- implementaciones pasarian. Lo que si prueban es la igualdad con el ledger.
--
-- ⚠️ Solo contra un BRANCH de Supabase, nunca contra produccion: apaga
-- temporalmente un trigger de crm.leads para fabricar la edad de una fixture.

begin;

set local lock_timeout = '5s';

-- Claims de management del ejecutor (MCP/dashboard) → auth.uid() debe ser null
-- para sembrar como sistema; bajo psql es no-op.
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('2a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ten-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('2a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ten-v1@test.invalid', now(), '{}', '{}', now(), now()),
  ('2a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ten-v2@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('2a000000-0000-4000-8000-000000000001', 'Tenencia Supervisor', 'ten-sup@test.invalid', 'comercial', true),
  ('2a000000-0000-4000-8000-000000000002', 'Tenencia Vendedor Uno', 'ten-v1@test.invalid', 'comercial', true),
  ('2a000000-0000-4000-8000-000000000003', 'Tenencia Vendedor Dos', 'ten-v2@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('2a000000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('2a000000-0000-4000-8000-000000000002', 'vendedor', '2a000000-0000-4000-8000-000000000001', true),
  ('2a000000-0000-4000-8000-000000000003', 'vendedor', '2a000000-0000-4000-8000-000000000001', true);

-- L1 nace SIN dueno (cola global, como todo lead que entra por el conector).
-- L2 nace CON dueno (alta manual de un vendedor desde su propia pantalla).
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por
)
values
  ('2b000000-0000-4000-8000-000000000001', 'TENENCIA SQL DE LA COLA', '999444001', 'nuevo', 'landing', 5000, 'PEN',
   null, null, true, false, '2a000000-0000-4000-8000-000000000001'),
  ('2b000000-0000-4000-8000-000000000002', 'TENENCIA SQL ALTA PROPIA', '999444002', 'nuevo', 'otro', 1000, 'PEN',
   '2a000000-0000-4000-8000-000000000002', null, true, false, '2a000000-0000-4000-8000-000000000002');

-- ── V1: el alta ───────────────────────────────────────────────────────────────
do $test$
declare
  v record;
begin
  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v.tenencia_desde is not null then
    raise exception 'V01 un lead sin dueno no debe tener reloj de tenencia (%)', v.tenencia_desde;
  end if;

  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000002';
  if v.tenencia_desde is distinct from v.creado_en then
    raise exception 'V02 en el alta con dueno el reloj debe ser creado_en (% vs %)', v.tenencia_desde, v.creado_en;
  end if;
  -- Espejo del ledger: el episodio de 'ingreso' comparte el instante.
  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '2b000000-0000-4000-8000-000000000002'
      and finalizado_en is null
      and asignado_en = v.tenencia_desde
  ) then
    raise exception 'V03 el reloj del alta no coincide con asignado_en del ledger';
  end if;
end;
$test$;

-- ── V2: orden de disparo (auditoria, B1) ─────────────────────────────────────
-- El nombre `zzz` es lo que garantiza que el trigger decida sobre los MISMOS
-- valores finales que ve el escritor del ledger (que es AFTER).
do $test$
declare
  v_ultimo text;
begin
  select tgname into v_ultimo
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm' and c.relname = 'leads'
    and not t.tgisinternal
    and (t.tgtype & 2) > 0        -- BEFORE
    and (t.tgtype & 1) > 0        -- ROW
    and t.tgenabled <> 'D'
  order by t.tgname desc limit 1;

  if v_ultimo is distinct from 'trg_leads_zzz_tenencia_desde' then
    raise exception 'V04 el sello de tenencia ya no es el ultimo trigger BEFORE (lo es %)', v_ultimo;
  end if;
end;
$test$;

-- ── Fixture: L1 envejece 3 dias en la cola ───────────────────────────────────
-- `creado_en` es inmutable en UPDATE (leads_before_update lo restaura desde
-- OLD) → se apaga ESE trigger, dentro de la tx, SOLO para fabricar la edad.
-- Es exactamente el escenario que motivo la migracion: el lead lleva dias
-- esperando en la cola de Rosa cuando por fin le cae a un asesor.
alter table crm.leads disable trigger trg_leads_before_update;
update crm.leads
   set creado_en = statement_timestamp() - interval '3 days'
 where id = '2b000000-0000-4000-8000-000000000001';
alter table crm.leads enable trigger trg_leads_before_update;

-- Rosa lo parkea en la bandeja del supervisor (sigue SIN dueno).
update crm.leads
   set asignado_supervisor_id = '2a000000-0000-4000-8000-000000000001'
 where id = '2b000000-0000-4000-8000-000000000001';

do $test$
declare
  v record;
begin
  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v.tenencia_desde is not null then
    raise exception 'V05 parkear en una bandeja no da tenencia: es del supervisor, no de un asesor';
  end if;
  if v.creado_en > transaction_timestamp() - interval '2 days' then
    raise exception 'V06 la fixture no envejecio: creado_en = %', v.creado_en;
  end if;
end;
$test$;

-- ── V3: LA ASIGNACION — el caso que motivo todo ──────────────────────────────
do $test$
declare
  v record;
  v_sla_antes timestamptz;
  v_ledger timestamptz;
begin
  -- El SLA del CLIENTE se captura ANTES para probar INVARIANCIA (auditoria C1:
  -- comparar contra el reloj de pared solo media la edad de la fixture).
  select sla_global_iniciado_en into v_sla_antes
    from crm.leads where id = '2b000000-0000-4000-8000-000000000001';

  -- El supervisor baja el lead de su bandeja a un vendedor.
  update crm.leads
     set vendedor_id = '2a000000-0000-4000-8000-000000000002',
         asignado_supervisor_id = null
   where id = '2b000000-0000-4000-8000-000000000001';

  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';

  if v.tenencia_desde is null then
    raise exception 'V07 tras asignar, el lead debe tener reloj de tenencia';
  end if;
  -- EL NUCLEO: el reloj NO es creado_en. El lead nacio hace 3 dias; su asesor
  -- lo tiene hace segundos y su cola no puede pintarlo en rojo critico.
  if v.tenencia_desde <= v.creado_en + interval '2 days' then
    raise exception 'V08 el reloj arranco con el lead (%), no con la asignacion (%)', v.creado_en, v.tenencia_desde;
  end if;
  if v.tenencia_desde < transaction_timestamp() then
    raise exception 'V09 el reloj de la asignacion deberia ser de ahora, no del pasado (%)', v.tenencia_desde;
  end if;
  -- El reloj del CLIENTE sigue INTACTO: la migracion no borra la verdad del
  -- negocio, solo deja de usarla para juzgar al asesor.
  if v.sla_global_iniciado_en is distinct from v_sla_antes then
    raise exception 'V10 la asignacion movio el SLA global del cliente (% → %)', v_sla_antes, v.sla_global_iniciado_en;
  end if;

  -- Igualdad EXACTA con el ledger: ambos triggers corren en el mismo statement.
  select asignado_en into v_ledger from crm.lead_asignaciones
   where lead_id = '2b000000-0000-4000-8000-000000000001' and finalizado_en is null;
  if v_ledger is distinct from v.tenencia_desde then
    raise exception 'V11 columna y ledger divergen (% vs %)', v.tenencia_desde, v_ledger;
  end if;
end;
$test$;

-- ── V4: el ruido NO reinicia el reloj ────────────────────────────────────────
do $test$
declare
  v_antes timestamptz;
  v_despues timestamptz;
begin
  select tenencia_desde into v_antes from crm.leads where id = '2b000000-0000-4000-8000-000000000001';

  update crm.leads set nota = 'el cliente pidio que lo llamen por la tarde'
   where id = '2b000000-0000-4000-8000-000000000001';
  select tenencia_desde into v_despues from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v_despues is distinct from v_antes then
    raise exception 'V12 editar la nota reinicio el reloj (% → %)', v_antes, v_despues;
  end if;

  update crm.leads set etapa = 'contactado' where id = '2b000000-0000-4000-8000-000000000001';
  select tenencia_desde into v_despues from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v_despues is distinct from v_antes then
    raise exception 'V13 mover de etapa dentro de lo operativo reinicio el reloj (% → %)', v_antes, v_despues;
  end if;

  update crm.leads set monto_estimado = 20000 where id = '2b000000-0000-4000-8000-000000000001';
  select tenencia_desde into v_despues from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v_despues is distinct from v_antes then
    raise exception 'V14 editar el monto reinicio el reloj (% → %)', v_antes, v_despues;
  end if;
end;
$test$;

-- ── V5: la transferencia reinicia el reloj del que recibe ────────────────────
--
-- ⚠️ POR QUE ESTE BLOQUE NO ASEVERA "el reloj AVANZO". `statement_timestamp()`
-- no avanza dentro de un mismo statement, y este oraculo se ejecuta tanto bajo
-- psql (un statement por comando) como en BATCH via MCP (todo el archivo como
-- una simple-query, donde TODOS los comandos comparten el instante). Es la
-- misma trampa que ya documenta test-descartados.sql. En modo batch, "heredar
-- el reloj del anterior" y "re-sellarlo" producen literalmente el MISMO valor,
-- asi que una comparacion `>` seria un FALSO ROJO bajo MCP y un `>=` seria un
-- FALSO VERDE bajo psql.
--
-- Lo que SI es demostrable en ambos modos —y es la contrata real de la
-- migracion— es que la columna sigue al EPISODIO ABIERTO: tras transferir hay
-- una fila NUEVA en el ledger, la vieja quedo cerrada, y la columna apunta a la
-- nueva. Si el trigger heredara (rama `else`), seguiria apuntando al instante
-- del episodio CERRADO.
-- El avance estricto del reloj se asevera donde si se puede: en el gate JS
-- (`testTenencia` en test-rls.mjs), donde cada llamada PostgREST es su propio
-- statement y el reloj avanza de verdad.
do $test$
declare
  v_antes timestamptz;
  v_episodio_viejo uuid;
  v record;
  v_ledger record;
begin
  select tenencia_desde into v_antes from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  select id into v_episodio_viejo from crm.lead_asignaciones
   where lead_id = '2b000000-0000-4000-8000-000000000001' and finalizado_en is null;

  update crm.leads set vendedor_id = '2a000000-0000-4000-8000-000000000003'
   where id = '2b000000-0000-4000-8000-000000000001';

  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v.tenencia_desde < v_antes then
    raise exception 'V15 el reloj retrocedio al transferir (% → %)', v_antes, v.tenencia_desde;
  end if;

  select * into v_ledger from crm.lead_asignaciones
   where lead_id = '2b000000-0000-4000-8000-000000000001' and finalizado_en is null;

  -- El episodio abierto es OTRO: el ledger roto de dueno.
  if v_ledger.id = v_episodio_viejo then
    raise exception 'V16 el ledger no abrio un episodio nuevo al transferir';
  end if;
  if v_ledger.analista_id <> '2a000000-0000-4000-8000-000000000003' then
    raise exception 'V17 el episodio abierto no es del vendedor que recibe (%)', v_ledger.analista_id;
  end if;
  -- …y la columna apunta al episodio NUEVO, no al que quedo cerrado.
  if v_ledger.asignado_en is distinct from v.tenencia_desde then
    raise exception 'V18 tras transferir, columna y ledger divergen (% vs %)', v.tenencia_desde, v_ledger.asignado_en;
  end if;
  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '2b000000-0000-4000-8000-000000000001'
      and finalizado_en is not null
      and analista_id = '2a000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'V19 el episodio del vendedor anterior no se cerro';
  end if;
end;
$test$;

-- ── V6: el CIERRE apaga el reloj (auditoria A1, camino c) ────────────────────
-- Salir de tenencia operativa cierra el episodio en el ledger; la columna,
-- como proyeccion del episodio ABIERTO, tiene que quedarse en null.
do $test$
declare
  v timestamptz;
begin
  update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes'
   where id = '2b000000-0000-4000-8000-000000000001';

  select tenencia_desde into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v is not null then
    raise exception 'V20 un lead cerrado no tiene episodio abierto: el reloj debe apagarse (%)', v;
  end if;
  if exists (select 1 from crm.lead_asignaciones
             where lead_id = '2b000000-0000-4000-8000-000000000001' and finalizado_en is null) then
    raise exception 'V21 el ledger dejo un episodio abierto tras el cierre';
  end if;
end;
$test$;

-- ── V7: la REAPERTURA estrena reloj (auditoria A1, camino a) ─────────────────
-- ESTE es el bug que la primera version del trigger dejaba vivo: un descartado
-- que vuelve al MISMO asesor no puede reaparecer con el reloj de hace meses.
do $test$
declare
  v record;
  v_ledger timestamptz;
begin
  update crm.leads set etapa = 'nuevo', motivo_descarte = null
   where id = '2b000000-0000-4000-8000-000000000001';

  select * into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v.tenencia_desde is null then
    raise exception 'V22 tras reabrir, el asesor vuelve a tener el lead: debe haber reloj';
  end if;
  -- Aqui SI vale la comparacion absoluta en ambos modos: el reloj estaba en
  -- NULL tras el cierre, asi que cualquier valor tuvo que sellarse ahora. Es la
  -- prueba de que el descartado que vuelve al mismo asesor NO hereda el reloj
  -- viejo (hallazgo A1 de la auditoria).
  if v.tenencia_desde < transaction_timestamp() then
    raise exception 'V23 la reapertura heredo un reloj viejo (%)', v.tenencia_desde;
  end if;

  select asignado_en into v_ledger from crm.lead_asignaciones
   where lead_id = '2b000000-0000-4000-8000-000000000001' and finalizado_en is null;
  if v_ledger is distinct from v.tenencia_desde then
    raise exception 'V24 tras reabrir, columna y ledger divergen (% vs %)', v.tenencia_desde, v_ledger;
  end if;
end;
$test$;

-- ── V8: soltar el lead apaga el reloj ────────────────────────────────────────
update crm.leads
   set vendedor_id = null,
       asignado_supervisor_id = '2a000000-0000-4000-8000-000000000001'
 where id = '2b000000-0000-4000-8000-000000000001';

do $test$
declare
  v timestamptz;
begin
  select tenencia_desde into v from crm.leads where id = '2b000000-0000-4000-8000-000000000001';
  if v is not null then
    raise exception 'V25 un lead devuelto a la bandeja no debe conservar reloj de asesor (%)', v;
  end if;
end;
$test$;

-- ── V9: INFALSIFICABLE desde una sesion authenticated real ───────────────────
-- Sustituye a la asercion de grants por columna, que seria un FALSO VERDE: el
-- ACL de crm.leads es de TABLA (`authenticated=arw`, verificado en prod), asi
-- que `authenticated` SI puede mandar la columna en un PATCH y un
-- `revoke update (columna)` seria un no-op silencioso. Lo que de verdad
-- defiende el dato es el trigger — y eso es lo que se prueba aqui.
select set_config('request.jwt.claim.sub', '2a000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
declare
  v_antes timestamptz;
  v_despues timestamptz;
begin
  select tenencia_desde into v_antes from crm.leads where id = '2b000000-0000-4000-8000-000000000002';
  if v_antes is null then
    raise exception 'V26 el vendedor no puede leer el reloj de su propio lead (RLS o grant)';
  end if;

  update crm.leads set tenencia_desde = transaction_timestamp() - interval '90 days'
   where id = '2b000000-0000-4000-8000-000000000002';

  select tenencia_desde into v_despues from crm.leads where id = '2b000000-0000-4000-8000-000000000002';
  if v_despues is distinct from v_antes then
    raise exception 'V27 un vendedor pudo falsificar su propio reloj (% → %)', v_antes, v_despues;
  end if;
end;
$test$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ── V10: el estado HONESTO de los grants ─────────────────────────────────────
-- No se asevera "authenticated no puede escribir la columna" (seria falso):
-- se asevera que PUEDE LEERLA y se deja constancia de que la escritura la
-- bloquea el trigger, no el ACL.
do $test$
begin
  if not has_column_privilege('authenticated', 'crm.leads', 'tenencia_desde', 'SELECT') then
    raise exception 'V28 authenticated no puede LEER tenencia_desde: PostgREST la ignorara en silencio';
  end if;
  if not has_column_privilege('service_role', 'crm.leads', 'tenencia_desde', 'SELECT') then
    raise exception 'V29 service_role no puede leer tenencia_desde: las edge functions la perderian';
  end if;
  if has_column_privilege('anon', 'crm.leads', 'tenencia_desde', 'SELECT') then
    raise exception 'V30 anon no debe ver tenencia_desde';
  end if;
end;
$test$;

select 'TENENCIA_TX_OK' as resultado;

rollback;
