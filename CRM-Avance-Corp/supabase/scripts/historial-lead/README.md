# Historial por lead — instalación y registro de `20260919185718`

Fase 1 del plan «sin topes» (19/09/2026). La ficha del lead deja de filtrar en el navegador la
lista global del ámbito (que PostgREST corta a 1 000 filas) y pide `crm.actividades_de_lead_fn`
por lead, por cursor, sin ventana ni tope. Acta completa en `supabase/migrations/MIGRACIONES.md`
(entrada 20260919185718); ensayo en el banco resumido en `verificacion.json`.

## Orden de publicación (obligatorio: el SQL va ANTES que el front)

1. Instalar `supabase/migrations/20260919185718_crm_actividades_de_lead.sql` en producción por
   la vía autorizada (Miguel con `!`, desde `CRM-Avance-Corp/`):

   ```
   npx supabase db query --linked --file supabase/migrations/20260919185718_crm_actividades_de_lead.sql
   ```

   El preflight sella las huellas de `actividades_select` y `leads_select` medidas el 19/09; si
   alguien las tocó desde entonces, se niega y hay que re-auditar. El postflight corre el gate
   propio y los cuatro del mundo SLA.

2. Registrar la migración CON su cuerpo (fail-closed: se niega si el SQL no está tal cual):

   ```
   npx supabase db query --linked --file supabase/scripts/registrar-20260919185718.sql
   ```

   El registrador lo genera `generar-registrador.mjs` leyendo la migración del archivo y los md5
   de `verificacion.json`; no se edita a mano.

3. Sonda anónima, sin credenciales de persona: un POST a `/rest/v1/rpc/actividades_de_lead_fn`
   con `{"p_lead_id":"00000000-0000-4000-8000-000000000000"}` y la clave anon debe responder
   `42501` (`permission denied`); con `{"p_nope":1}` → `PGRST202`.

4. Fusionar la PR #28 con **merge commit** (no squash) y ANTES de construir; luego `release:crm`,
   preflight y deploy del front. Devolver `main` el mismo día y regenerar el mapa de capas.

## Reversa

`drop function crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid); drop function
private.actividades_de_lead_core(uuid,integer,timestamptz,uuid); drop function
private.nombre_de_autor(uuid); drop function private.assert_actividades_de_lead(); drop function
private.assert_actividades_de_lead_mutantes(); drop function
private.assert_actividades_de_lead_base();` y retirar primero el front (que la llama). Nada de
datos que deshacer: la migración solo lee.
