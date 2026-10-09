# Encargo a Codex (IMPLEMENTADOR) — Facturación fase 2: ningún cambio de equipo se pierde

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Escribes SOLO dentro de este worktree
(`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-jerarquia-20261009`). Sin commit,
sin push, sin red, sin Docker, sin producción y sin invocar a otros agentes. Todo en español. Al terminar: informe breve
(archivos, decisiones, dudas abiertas). Nivel 3: base de datos. No edites migraciones ya commiteadas.

## El problema

Facturación pone cada venta bajo el «supervisor de ENTONCES». Lo reconstruye con los eventos `jerarquia_actualizada` de
`crm.usuario_eventos` (`crm.facturacion_diaria_fn`, CTE `eventos`/`tramos`). Pero solo dos funciones escriben ese
evento, y lo hacen a mano:
- `crm.actualizar_jerarquia_usuario_fn` (pantalla de Gerencia);
- `crm.registrar_vendedor_usuario_fn` (alta).

Las demás vías cambian `crm.equipo.supervisor_id` **sin dejar rastro**:
- `crm.fijar_membresia_activa_fn`, baja con reemplazo: `update crm.equipo set supervisor_id = p_reemplazo_id where supervisor_id = p_perfil_id and activo is true`;
- migraciones sin sesión (ya pasó el 28/08 con `$normalizar_directorio$`);
- `crm.purgar_membresia_crm`: la FK `on delete set null` vacía al supervisor de los subordinados;
- escrituras directas de `service_role`.

Cuando pasa, una venta pasada puede saltar al equipo nuevo.

## Decisión de Miguel (09/10)

Un cambio que no hace una persona se anota con el autor **«sistema»**. Es un UUID fijo y documentado: `actor_id` es
`uuid not null` y **no tiene clave foránea** (comprobado en producción). No se crea ningún perfil ni se toca `public`.

## Diseño (impleméntalo así; si ves un fallo, dilo en el informe en vez de cambiar el diseño)

1. **Una sola pieza escribe el evento:** un trigger en `crm.equipo`.
   - `AFTER INSERT ... FOR EACH ROW WHEN (new.supervisor_id IS NOT NULL)`.
   - `AFTER UPDATE OF supervisor_id ... FOR EACH ROW WHEN (old.supervisor_id IS DISTINCT FROM new.supervisor_id)`.
   - Sin cambio real, no hay evento.
   - Función `private.trg_equipo_evento_jerarquia()`: `SECURITY DEFINER`, dueño `postgres`, `set search_path to ''` y
     nombres calificados. Inserta DIRECTO en `crm.usuario_eventos`, no vía `private.registrar_evento_usuario`, que exige
     `auth.uid()`.
   - Recuerda que `tgtype` no ve el `WHEN`: las comprobaciones de catálogo que escribas deben mirar `pg_get_triggerdef`.
2. **Autor:** `coalesce(auth.uid(), private.actor_sistema_eventos())`. Se crea `private.actor_sistema_eventos()`
   (`immutable`, devuelve un UUID constante elegido por ti, con `COMMENT ON` que diga qué es). Así:
   - cuando Gerencia da de baja con reemplazo, el autor es esa persona;
   - en migraciones, `service_role` o cascadas, es «sistema».
3. **Idempotencia** (`UNIQUE (actor_id, accion, idempotencia)`)
   - Las 2 RPC que hoy escriben el evento **dejan de escribirlo**. Antes de su `UPDATE`/`INSERT` de `crm.equipo`, le
     pasan al trigger su `p_idempotencia` y el `perfil_id` objetivo por dos GUC transaccionales
     (`set_config('crm.evento_jerarquia_idempotencia', …, true)` y `…_objetivo`).
   - El trigger usa esa idempotencia **solo** si `new.perfil_id` coincide con el objetivo, y la consume (pone los GUC a
     `''`) para que ninguna otra fila la reutilice. Sin GUC: `gen_random_uuid()`.
   - INSERT sin `on conflict`. Un choque = error = el cambio de equipo tampoco se hace (fail closed).
   - Las comprobaciones de repetición de las 2 RPC (hoy buscan el evento por actor + acción + idempotencia; la del alta
     cuenta todos los eventos del actor con esa idempotencia) tienen que seguir funcionando igual: compruébalo y ajústalas
     si hace falta.
4. **Detalle del evento:** las mismas claves que hoy (`supervisor_anterior`, `supervisor_nuevo`) más `via`:
   `'rpc'` cuando viene de una de las 2 RPC y `'automatica'` en otro caso. Máximo 4096 bytes.
5. **Nada más cambia.**
   - `crm.facturacion_diaria_fn` no se toca.
   - Un tramo con supervisor NULL sigue cayendo al supervisor de hoy, como ahora.
   - `crm.fijar_membresia_activa_fn` no se toca: su `UPDATE` ya dispara el trigger.
6. **Garantía acotada, declarada en la cabecera:** quien desactive triggers o use `session_replication_role = replica`
   queda fuera.

## Cuerpos vivos de producción

En `supabase/scripts/jerarquia-evento/vivo/` (md5 de `pg_get_functiondef` en el nombre del informe; verifícalos):
- `crm.actualizar_jerarquia_usuario_fn` (`79c43d9888cf0d54b92eb26e8b46c3af`);
- `crm.registrar_vendedor_usuario_fn` (`c3b73f85fdd791534d6edcc5015b14ff`);
- `crm.fijar_membresia_activa_fn` (`9be9925a221e64119b21e0f6a299ceb9`, solo lectura);
- `private.registrar_evento_usuario` (`8c423da784e0ff61e7eb91c896d851f2`, solo lectura);
- `crm.facturacion_diaria_fn` (`4b11e1da336f2f296c81f064ce30e35b`, solo lectura).

Las 2 RPC reescritas se generan a máquina desde `vivo/` con un `generar-cuerpos.py` que cambie solo lo necesario, con
conteos exactos (patrón: `supabase/scripts/baja-analista-heredero/generar-cuerpos.py`).

## Entregables

1. **`supabase/migrations/20261009223000_crm_jerarquia_evento_en_toda_via.sql`.** Patrón:
   `supabase/migrations/20261009200000_crm_baja_analista_heredero.sql` (léela entera).
   - `begin … commit` con `DO` idempotente y fail-closed.
   - PREFLIGHT de huellas vivas (las 5) y de que no existan ya la función ni el trigger nuevos.
   - Se crea `actor_sistema_eventos`, la función del trigger y los 2 triggers; se reescriben las 2 RPC.
   - POSTFLIGHT: huellas nuevas como `'PENDIENTE_MEDIR_EN_BANCO'` (Claude las mide); dueño, ACL, `prosecdef`,
     `search_path` y `pg_get_triggerdef` de los 2 triggers; `COMMENT ON` de todo.
2. **`supabase/scripts/jerarquia-evento/reversa.sql`.** Restaura las 2 RPC exactas, borra los triggers y las 2 funciones
   nuevas. Idempotente.
3. **`supabase/scripts/jerarquia-evento/ensayo-sintetico.sql`.** Banco Docker vacío. Guarda: aborta si
   `public.contratos` tiene filas. Todo termina en ROLLBACK. Siembra con el patrón de
   `supabase/scripts/baja-analista-heredero/ensayo-sintetico.sql`: `auth.users(id, email)`, `public.perfiles`,
   `crm.equipo`. Casos PASS/FAIL:
   - (a) la RPC de jerarquía: 1 evento, autor = quien llama, idempotencia = la suya; repetirla con la misma idempotencia
     no duplica y responde igual;
   - (b) el alta con supervisor: 1 evento de jerarquía, y su repetición funciona;
   - (c) la baja con reemplazo de un supervisor con 2 subordinados activos: 2 eventos, autor = Gerencia, `via` automática;
   - (d) `UPDATE` directo sin sesión: 1 evento, autor «sistema»;
   - (e) `UPDATE` al mismo supervisor: 0 eventos;
   - (f) INSERT sin supervisor: 0 eventos;
   - (g) borrado del supervisor con la cascada `set null` (usa la vía de `crm.purgar_membresia_crm` si es posible; si no,
     un DELETE con su válvula `crm.purgando_membresia`): eventos con `supervisor_nuevo` NULL;
   - (h) dos cambios de la misma fila en una transacción: 2 eventos;
   - (i) si el insert del evento falla (fuérzalo, p. ej. un detalle de más de 4096 bytes, en un sub-bloque), el cambio de
     equipo tampoco queda;
   - (j) Facturación: una venta antes y otra después de una baja con reemplazo quedan con su supervisor de entonces
     (`crm.facturacion_diaria_fn` con claims de Gerencia; las ventas sembradas como en el ensayo de baja de analista).
   - Y un caso que demuestre que, SIN la migración, (c) no deja evento (comentario de cómo correrlo).
4. Actualiza `supabase/scripts/test-usuarios-jerarquia.sql` si sus conteos de eventos (4 y 3) cambian, explicando por qué.
   Lo esperado es que no cambien.
5. `supabase/scripts/jerarquia-evento/LEEME.md` y una entrada nueva al final de `supabase/migrations/MIGRACIONES.md`
   (estado: «en banco, sin aplicar»).
