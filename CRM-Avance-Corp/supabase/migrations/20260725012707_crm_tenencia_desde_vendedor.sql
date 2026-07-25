-- EL RELOJ DEL VENDEDOR — `crm.leads.tenencia_desde` (pedido de Miguel, 2026-07-24)
--
-- PROBLEMA. La cola de acción del vendedor mide la urgencia desde `creado_en`
-- (o desde la última actividad). Con el circuito de leads ya VIVO
--   origen → hoja → conector → cola de Rosa → bandeja del supervisor → vendedor
-- un lead puede pasar DÍAS antes de llegar a un asesor. El día que se lo
-- asignan, su pantalla ya lo pinta en ROJO CRÍTICO — "Entró hace 2 días y nadie
-- lo ha contactado" — culpándolo de una espera que no fue suya. Hoy no se nota
-- (los 65 leads de prod nacieron el mismo día), pero se nota mañana.
--
-- EL DATO YA EXISTE, PERO ESTÁ SELLADO. `crm.lead_asignaciones.asignado_en` del
-- episodio abierto es exactamente el instante en que el supervisor asignó. Esa
-- tabla, sin embargo, es un LIBRO DE AUDITORÍA CERRADO A PROPÓSITO: RLS on con
-- CERO policies y CERO grants. Abrirla al cliente solo para pintar un reloj
-- sería un mal canje — expondría el historial de tenencia completo (quién tuvo
-- qué lead, con qué monto, viniendo de qué supervisor y por qué lo soltó).
--
-- SOLUCIÓN. PROYECTAR el instante a una columna de `crm.leads`, sellada por
-- trigger que ESPEJA la condición del escritor del ledger
-- (`private.trg_leads_asignaciones`) y usa sus mismos instantes: `creado_en` en
-- el alta y `statement_timestamp()` al abrirse un episodio. Compartiendo
-- condición Y statement, la columna es una proyección fiel del episodio
-- abierto, no una segunda fuente de verdad. El ledger sigue siendo la autoridad
-- y sigue cerrado.
--
-- ⚠️ ESPEJAR LA CONDICIÓN COMPLETA, NO SOLO `vendedor_id` (auditoría, hallazgo
-- A1). El ledger abre/cierra episodios por `activo AND etapa operativa AND
-- vendedor_id not null`. Un trigger que solo mirara el cambio de dueño divergiría
-- en 5 caminos reales, y uno de ellos REPRODUCE EL BUG QUE MOTIVA ESTA MIGRACIÓN:
-- un lead descartado hace meses que se reabre y vuelve al MISMO asesor le
-- aparecería con el reloj antiguo → rojo crítico injusto. Por eso la reapertura
-- y la reactivación reinician el reloj, y salir de tenencia operativa lo apaga.
--
-- LOS TRES RELOJES, cada uno respondiendo a su pregunta (ninguno reemplaza a
-- otro; la UI del vendedor muestra los dos primeros JUNTOS a propósito):
--   · creado_en / sla_global_iniciado_en → cuánto lleva esperando EL CLIENTE
--   · tenencia_desde   (este)            → cuánto lleva EN MANOS DE SU ASESOR
--   · última actividad                   → cuánto lleva sin que nadie lo toque
--
-- NO toca `public`. NO toca policies (la columna viaja sobre `leads_select`,
-- que ya decide quién ve la fila). NO añade PII: quien puede leer la fila ya
-- sabe de quién es el lead; solo gana el CUÁNDO.

begin;

-- ── 1. La columna ─────────────────────────────────────────────────────────────

alter table crm.leads
  add column if not exists tenencia_desde timestamptz;

-- El COMMENT vive en la BD y lo lee la próxima auditoría: tiene que decir la
-- verdad sobre QUIÉN defiende la columna. El ACL de `crm.leads` es de TABLA
-- (`relacl` verificado en prod: `authenticated=arw`), así que `authenticated`
-- YA tiene UPDATE sobre toda columna futura y un `revoke update (columna)`
-- sería un no-op silencioso. La inmutabilidad la sostiene el TRIGGER, no el grant.
comment on column crm.leads.tenencia_desde is
  'Instante en que el VENDEDOR ACTUAL recibio este lead; null si no esta en tenencia operativa (sin dueno, inactivo o en etapa terminal). Proyeccion fiel de crm.lead_asignaciones.asignado_en del episodio ABIERTO: el trigger private.trg_leads_tenencia_desde espeja la misma condicion y el mismo statement que el escritor del ledger, asi que no pueden divergir. Se reinicia al cambiar de dueno, al reabrir un descartado y al reactivar; editar, mover de etapa dentro de lo operativo o registrar actividad NO lo tocan. Es el reloj que mide al ASESOR; el reloj del CLIENTE es creado_en/sla_global_iniciado_en. INMUTABLE PARA EL CLIENTE POR EL TRIGGER, no por los grants: el ACL de crm.leads es de TABLA (authenticated=arw), de modo que un revoke por columna seria no-op; el trigger reimpone el valor anterior en todo UPDATE que no abra un episodio.';

-- ── 2. Backfill desde el ledger ───────────────────────────────────────────────
-- ORDEN DELIBERADO: este UPDATE va ANTES de crear el trigger. Si corriera
-- despues, el propio trigger reimpondria `old.tenencia_desde` (null) y borraria
-- el backfill en el mismo statement.
-- Hoy toca 0 filas (ningun lead de prod tiene vendedor todavia), pero cubre el
-- caso real de que se asignen leads entre esta escritura y el merge.
--
-- `trg_leads_before_update` se apaga SOLO durante el backfill (auditoria, M1):
-- ese trigger hace `actualizado_en := now()` y el front ORDENA la cartera por
-- esa columna (`crm-api.ts`), de modo que un backfill sin apagarlo reordenaria
-- de golpe la cartera de todos los asesores por un cambio puramente interno.
-- El ALTER de arriba ya tiene ACCESS EXCLUSIVE sobre la tabla en esta misma
-- transaccion, asi que el disable no anade bloqueo nuevo.
alter table crm.leads disable trigger trg_leads_before_update;

update crm.leads l
set tenencia_desde = la.asignado_en
from crm.lead_asignaciones la
where la.lead_id = l.id
  and la.finalizado_en is null
  and l.vendedor_id is not null
  and l.tenencia_desde is null;

alter table crm.leads enable trigger trg_leads_before_update;

-- ── 3. El sello (trigger) ─────────────────────────────────────────────────────
-- SECURITY DEFINER + search_path fijo: mismo patron que los demas triggers de
-- tenencia de esta tabla. No lee NINGUNA tabla (en particular, no lee el ledger
-- sellado: no abre canal alguno hacia el), asi que el definer solo garantiza
-- que un rol sin privilegios no pueda evadirlo.

create or replace function private.trg_leads_tenencia_desde()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  -- ESPEJO EXACTO de `v_new_debe_tener` / `v_old_debe_tener` en
  -- private.trg_leads_asignaciones: hay episodio abierto solo en tenencia
  -- OPERATIVA. Si estas dos definiciones se separan, la columna deja de ser
  -- una proyeccion del ledger y el COMMENT pasa a mentir.
  v_new_debe boolean;
  v_old_debe boolean;
begin
  v_new_debe := new.activo = true
    and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and new.vendedor_id is not null;

  if tg_op = 'INSERT' then
    -- En el alta el ledger usa `v_evento_en := new.creado_en`; `creado_en` ya
    -- viene sellado por trg_leads_00_guard_tenencia, que corre antes que este.
    new.tenencia_desde := case when v_new_debe then new.creado_en else null end;
    return new;
  end if;

  v_old_debe := old.activo = true
    and old.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and old.vendedor_id is not null;

  if not v_new_debe then
    -- Sale de tenencia operativa (terminal, soft-delete o suelta el dueno): el
    -- ledger CIERRA el episodio y aqui no queda reloj que mostrar.
    new.tenencia_desde := null;
  elsif not v_old_debe then
    -- Entra a tenencia operativa: el ledger ABRE episodio ('reabierto',
    -- 'reactivado', 'asignado'). Es el caso que arregla el bug del descartado
    -- que vuelve al mismo asesor con el reloj antiguo.
    new.tenencia_desde := statement_timestamp();
  elsif new.vendedor_id is distinct from old.vendedor_id then
    -- Transferencia entre asesores: el que recibe estrena reloj; el ledger
    -- cierra un episodio y abre otro en este mismo statement.
    new.tenencia_desde := statement_timestamp();
  elsif new.ciclo_actual is distinct from old.ciclo_actual then
    -- Defensivo: hoy inalcanzable (el guard solo incrementa el ciclo al reabrir
    -- un descartado, y ese camino ya cae en `not v_old_debe`). Se deja para que
    -- un futuro camino de reapertura no herede el reloj en silencio.
    new.tenencia_desde := statement_timestamp();
  else
    -- Ruido: editar, mover de etapa dentro de lo operativo, registrar
    -- actividad. Esta rama es TAMBIEN la que hace la columna infalsificable:
    -- aunque el cliente mande un `tenencia_desde` en el body (puede: el ACL de
    -- crm.leads es de TABLA), el valor entrante se descarta aqui.
    new.tenencia_desde := old.tenencia_desde;
  end if;

  return new;
end;
$function$;

comment on function private.trg_leads_tenencia_desde() is
  'Sella crm.leads.tenencia_desde espejando la condicion de tenencia operativa y los instantes de private.trg_leads_asignaciones (creado_en en INSERT, statement_timestamp() al abrirse un episodio). Reimpone el valor anterior en todo UPDATE que no abra episodio: la columna es de solo lectura para el cliente aunque el ACL de tabla permita escribirla.';

revoke all on function private.trg_leads_tenencia_desde() from public, anon, authenticated, service_role;

-- `zzz`: corre al FINAL de los triggers BEFORE (orden alfabetico). Hoy ninguno
-- reescribe vendedor_id/etapa/activo, pero el escritor del ledger es AFTER y por
-- tanto ve SIEMPRE el valor final; correr al final es lo que garantiza que esta
-- columna decida sobre exactamente los mismos valores aunque manana se anada un
-- trigger BEFORE que si los mueva.
drop trigger if exists trg_leads_zzz_tenencia_desde on crm.leads;
create trigger trg_leads_zzz_tenencia_desde
before insert or update on crm.leads
for each row
execute function private.trg_leads_tenencia_desde();

-- ── 4. Grants ─────────────────────────────────────────────────────────────────
-- El ACL de `crm.leads` es de TABLA (`authenticated=arw`, `service_role=arwd`),
-- asi que este grant es REDUNDANTE hoy: la columna ya seria visible sin el. Se
-- deja explicito por dos razones: (1) es la convencion de toda columna nueva de
-- esta tabla (ver c1b y las migraciones de genero/consentimiento), y (2) si
-- algun dia se cierra el ACL de tabla para pasar a privilegios por columna,
-- esta linea es la que evita que PostgREST empiece a ignorar la columna EN
-- SILENCIO. No se concede UPDATE ni INSERT: el reloj lo sella el servidor.

grant select (tenencia_desde) on crm.leads to authenticated, service_role;

-- ── 5. Indice ─────────────────────────────────────────────────────────────────
-- La cola del vendedor filtra por dueno y ordena por antiguedad de tenencia.
-- Nombre `idx_leads_*` por convencion de la tabla. Nacera como INFO "unused
-- index" en advisors hasta que el front consuma la columna (clase ya aceptada).

create index if not exists idx_leads_tenencia
  on crm.leads (vendedor_id, tenencia_desde desc)
  where activo and vendedor_id is not null;

commit;
