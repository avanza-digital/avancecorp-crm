-- F4.4 del plan «Hoy del supervisor, sin ruido» — respuesta al BLOQUEANTE B1
-- de la auditoría adversarial de Codex sobre la trazabilidad para gerencia:
--
--   La vista de vigentes filtraba la vigencia ANTES de que el cliente eligiera
--   «el último asiento por alerta». Escenario: secuencia 10 reconoce; la 11
--   pospone hasta las 15:00. A las 15:00 la fila 11 desaparece de la vista
--   (hasta vencido), la 10 sigue dentro de sus 7 días y RESUCITA como último
--   asiento — la alerta queda atenuada por un reconocimiento que la posposición
--   había superado. Afecta a las DOS lecturas de la vista: la campana del
--   supervisor (F4.2) volvía a atenuarse indebidamente y la tarjeta de
--   gerencia (F4.4) listaba un compromiso que ya nadie sostiene.
--
--   Arreglo: la vista elige PRIMERO el último asiento por alerta (distinct on
--   por secuencia, dentro de la ventana de 7 días del candado acotado) y
--   SOLO DESPUÉS evalúa su vigencia. Un posponer vencido, siendo el último,
--   BLOQUEA a los anteriores y simplemente no aparece: nada gobierna esa
--   alerta (suena entera; gerencia no la lista). Efecto colateral bueno: la
--   vista sirve a lo sumo UNA fila por alerta — el «último manda» del front
--   queda como cinturón y los empates son inalcanzables también aquí.
--
-- ⚠️ REGLA de la vista (auditor RLS #2 de F4.2): todo CREATE OR REPLACE
-- DEBE repetir WITH (security_invoker = true) — en PG17 el replace SUSTITUYE
-- las reloptions y sin la cláusula quedaría definer EN SILENCIO, exponiendo
-- el libro completo a cualquier authenticated.
--
-- Sin tocar public.*. Orden de deploy: SERVIDOR primero (este fichero); el
-- front F4.4 que la lee llega después y funciona con ambas formas.

-- ── 0. Guardas de dependencias ───────────────────────────────────────────────
do $$
begin
  if to_regclass('crm.alertas_reconocimientos_vigentes') is null then
    raise exception 'Falta crm.alertas_reconocimientos_vigentes: aplicar primero 20260824034730';
  end if;
end $$;

-- ── 1. El último asiento manda TAMBIÉN vencido ───────────────────────────────
create or replace view crm.alertas_reconocimientos_vigentes
with (security_invoker = true) as
select id, alerta_id, accion, miembros, severidad, hasta, creado_en, secuencia
from (
  select distinct on (alerta_id)
    id, alerta_id, accion, miembros, severidad, hasta, creado_en, secuencia
  from crm.alertas_reconocimientos
  where creado_en > now() - make_interval(days => 7)
  order by alerta_id, secuencia desc
) ultimo
where hasta is null or hasta > now();

comment on view crm.alertas_reconocimientos_vigentes is
  'F4.2/F4.4 «Hoy del supervisor, sin ruido»: el asiento que AÚN gobierna cada alerta — se elige PRIMERO el último por alerta_id (secuencia desc, dentro de la ventana de 7 días del candado acotado de F4.1) y DESPUÉS se evalúa su vigencia (hasta > now() en posposiciones). Así un posponer VENCIDO, siendo el último, bloquea a los asientos anteriores en vez de dejarlos resucitar (bloqueante Codex F4.4 B1): la alerta queda sin gobierno y suena entera. A lo sumo UNA fila por alerta_id. El corte lo hace el reloj de POSTGRES (el front no puede alargar un silencio con un reloj atrasado — Codex F4.2 #2). security_invoker: misma RLS que la tabla (dueño supervisor; gerencia lee todo). La comparación de «reaparece si empeora» sigue en el front: necesita el estado ACTUAL de los grupos, que el servidor no conoce. ⚠️ REGLA (auditor RLS #2): todo CREATE OR REPLACE de esta vista DEBE repetir WITH (security_invoker = true) — en PG17 el replace SUSTITUYE las reloptions y un replace sin WITH la vuelve definer EN SILENCIO, exponiendo el libro completo a cualquier authenticated. Sonda post-cambio: pg_class.reloptions debe contener security_invoker=true.';

-- Los grants existentes de la vista sobreviven al replace (mismo objeto);
-- no se re-otorgan ni se amplían.

-- Vuelta atrás (la forma anterior de 20260824034730):
--   create or replace view crm.alertas_reconocimientos_vigentes
--   with (security_invoker = true) as
--   select id, alerta_id, accion, miembros, severidad, hasta, creado_en, secuencia
--   from crm.alertas_reconocimientos
--   where creado_en > now() - make_interval(days => 7)
--     and (hasta is null or hasta > now());
--   -- (y restaurar el comment de esa migración)
