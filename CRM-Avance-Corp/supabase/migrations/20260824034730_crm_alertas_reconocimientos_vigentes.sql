-- F4.2 del plan «Hoy del supervisor, sin ruido» — respuesta a los hallazgos
-- de la auditoría adversarial de Codex sobre el front de reconocimientos:
--
--   1. crm.alertas_reconocimientos_vigentes — VISTA (security_invoker) sobre
--      el libro que corta la VIGENCIA con el reloj de POSTGRES: solo asientos
--      de ≤7 días (el candado acotado de F4.1) y, si son posposición, con su
--      `hasta` aún futuro. El bloqueante Codex F4.2 #2: si el front filtra
--      la vigencia con el reloj del DISPOSITIVO, un portátil atrasado alarga
--      un silencio más allá del tope — exactamente la clase de fallo de
--      [[prueba-de-fechas-en-tu-propia-zona]]. El front ahora lee SOLO esta
--      vista; su comparación local queda como cinturón (cliente adelantado ⇒
--      caduca antes ⇒ suena de más, la dirección segura).
--   2. UNIQUE (secuencia) en el libro — Codex F4.2 #6: «el último asiento
--      manda» se lee por `secuencia`; la identity ya la hace monotónica por
--      la vía normal, pero sin UNIQUE una restauración/doble carga podría
--      sembrar empates y el ganador sería arbitrario. El front además trata
--      un empate como libro corrupto (fail-loud), esto lo hace inalcanzable.
--
-- Sin tocar public.*. Orden de deploy: SERVIDOR primero (este fichero); el
-- front que lee la vista llega después en el mismo release.

-- ── 0. Guardas de dependencias ───────────────────────────────────────────────
do $$
begin
  if to_regclass('crm.alertas_reconocimientos') is null then
    raise exception 'Falta crm.alertas_reconocimientos: aplicar primero 20260823204930';
  end if;
end $$;

-- ── 1. Orden total del libro, sellado también ante corrupción ────────────────
alter table crm.alertas_reconocimientos
  add constraint alertas_reconocimientos_secuencia_unica unique (secuencia);

comment on constraint alertas_reconocimientos_secuencia_unica
  on crm.alertas_reconocimientos is
  'F4.2: «el último asiento manda» se resuelve por secuencia; la identity ya es monotónica y este UNIQUE cierra la vía anómala (restauración, doble carga) que sembraría empates con ganador arbitrario.';

-- ── 2. La vista de vigentes: el reloj de Postgres corta, no el del cliente ───
-- security_invoker: la vista NO amplía nada — corre con los permisos y la RLS
-- del que consulta (dueño supervisor, o gerencia que lee todo), igual que la
-- tabla base. Es un recorte temporal, no una puerta.
create view crm.alertas_reconocimientos_vigentes
with (security_invoker = true) as
select id, alerta_id, accion, miembros, severidad, hasta, creado_en, secuencia
from crm.alertas_reconocimientos
where creado_en > now() - make_interval(days => 7)
  and (hasta is null or hasta > now());

comment on view crm.alertas_reconocimientos_vigentes is
  'F4.2 «Hoy del supervisor, sin ruido»: los asientos del libro que AÚN pueden gobernar una alerta — vigencia ≤7 días desde creado_en (el candado acotado de F4.1) y, en posposiciones, hasta > now(). El corte lo hace el reloj de POSTGRES: el front lee SOLO esta vista para que un dispositivo con el reloj atrasado no pueda alargar un silencio (Codex F4.2 #2). security_invoker: misma RLS que la tabla (dueño supervisor; gerencia lee todo). La comparación de «reaparece si empeora» sigue en el front: necesita el estado ACTUAL de los grupos, que el servidor no conoce. ⚠️ REGLA (auditor RLS #2): todo CREATE OR REPLACE de esta vista DEBE repetir WITH (security_invoker = true) — en PG17 el replace SUSTITUYE las reloptions y un replace sin WITH la vuelve definer EN SILENCIO, exponiendo el libro completo a cualquier authenticated. Sonda post-cambio: pg_class.reloptions debe contener security_invoker=true.';

revoke all on crm.alertas_reconocimientos_vigentes from public, anon;
grant select on crm.alertas_reconocimientos_vigentes to authenticated;

-- Vuelta atrás:
--   drop view crm.alertas_reconocimientos_vigentes;
--   alter table crm.alertas_reconocimientos
--     drop constraint alertas_reconocimientos_secuencia_unica;
