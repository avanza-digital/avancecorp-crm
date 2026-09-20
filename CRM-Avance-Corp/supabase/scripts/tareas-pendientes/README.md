# Tareas por cursor — instalación y registro de `20260919235100`

Fase 2 del plan «sin topes» (19/09/2026). La agenda deja de leer `crm.tareas` directo (PostgREST
recortaba a 1 000 filas: gerencia tenía 1 156 pendientes y perdía 156) y pide
`crm.tareas_pendientes_fn` por cursor `(vence_en, id)` en lotes de 500 hasta que no hay más. Acta
completa en `supabase/migrations/MIGRACIONES.md` (entrada 20260919235100); ensayo en el banco
resumido en `verificacion.json`.

## Orden de publicación (obligatorio: el SQL va ANTES que el front)

1. Instalar `supabase/migrations/20260919235100_crm_tareas_pendientes_keyset.sql` en producción por
   la vía autorizada (Miguel con `!`, desde `CRM-Avance-Corp/`):

   ```
   npx supabase db query --linked --file supabase/migrations/20260919235100_crm_tareas_pendientes_keyset.sql
   ```

   El preflight sella la huella de `tareas_select` medida el 19/09 y comprueba los grants por columna
   de `crm.leads`; si alguien los tocó desde entonces, se niega y hay que re-auditar. El postflight
   corre el gate propio, valida el índice y los cuatro gates del mundo SLA.

2. Medir en producción los md5 de `pg_get_functiondef` de la puerta y del núcleo (incluyen los
   comentarios internos: una copia del banco sin ellos no vale), anotarlos en `verificacion.json`
   y generar el registrador:

   ```
   node supabase/scripts/tareas-pendientes/generar-registrador.mjs
   ```

3. Registrar la migración CON su cuerpo (fail-closed: se niega si el SQL no está tal cual):

   ```
   npx supabase db query --linked --file supabase/scripts/registrar-20260919235100.sql
   ```

4. Sonda anónima, sin credenciales de persona: un POST a `/rest/v1/rpc/tareas_pendientes_fn` con
   `{"p_limite":10}` y la clave anon debe responder `42501` (`permission denied`); con
   `{"p_nope":1}` → `PGRST202`.

5. Fusionar la PR, construir el front en un worktree LIMPIO con `npm ci` propio, `release:crm`,
   preflight y deploy. Devolver `main` el mismo día y regenerar el mapa de capas (Foco 2 pierde el
   salto de lectura directa de `crm.tareas`).

## Reversa

`drop function crm.tareas_pendientes_fn(integer,timestamptz,uuid); drop function
private.tareas_pendientes_core(integer,timestamptz,uuid); drop function
private.assert_tareas_pendientes(); drop function private.assert_tareas_pendientes_mutantes();
drop function private.assert_tareas_pendientes_base(); drop index crm.tareas_pendientes_keyset_idx;`
y retirar primero el front (que la llama): vuelve a la lectura directa con su recorte. Nada de
datos que deshacer: la migración solo lee.
