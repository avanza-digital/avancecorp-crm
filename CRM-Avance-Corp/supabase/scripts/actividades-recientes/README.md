# Actividad reciente — instalación y registro de `20260920014500`

Fase 3 del plan «sin topes» (19/09/2026, noche). El arranque del CRM deja de descargar el
registro entero de actividades (`crm.actividades_del_ambito_fn`, recortado a 1 000 filas por
PostgREST); la bitácora de Hoy · Directorio pide `crm.actividades_recientes_fn(8)`. Acta en
`supabase/migrations/MIGRACIONES.md` (entrada 20260920014500); ensayo en `verificacion.json`.

## Orden de publicación (obligatorio: el SQL va ANTES que el front)

1. Instalar la migración en producción por la vía autorizada (Miguel con `!`, desde
   `CRM-Avance-Corp/`):

   ```
   npx supabase db query --linked --file supabase/migrations/20260920014500_crm_actividades_recientes.sql
   ```

   El preflight exige la Fase 1 instalada (`private.nombre_de_autor`), sella la huella de
   `actividades_select` medida el 19/09 y comprueba los grants por columna de `crm.leads` y la RLS
   activa; el postflight corre el gate propio y los cuatro gates del mundo SLA.

2. Medir en producción los md5 de `pg_get_functiondef` de la puerta y del núcleo, anotarlos en
   `verificacion.json` y generar el registrador:

   ```
   node supabase/scripts/actividades-recientes/generar-registrador.mjs
   ```

3. Registrar la migración CON su cuerpo (fail-closed):

   ```
   npx supabase db query --linked --file supabase/scripts/registrar-20260920014500.sql
   ```

4. Sonda anónima (`Content-Profile: crm`): `{"p_limite":8}` → `42501`; `{"p_nope":1}` → `PGRST202`.

5. Fusionar la PR, construir el front en un worktree LIMPIO (`npm ci` en `app/` y en la raíz),
   `release:crm`, preflight y deploy desde el terminal de Miguel. Devolver `main` el mismo día.

## Después: OBSERVAR y DERRIBAR la RPC vieja

`crm.actividades_del_ambito_fn` sigue viva. Con el front nuevo publicado, ninguna pantalla la
llama. Tras una semana sin llamadas en los logs de PostgREST (`query_logs`, ruta
`/rest/v1/rpc/actividades_del_ambito_fn`), una migración aparte la deprecia (`revoke execute`
de `authenticated` + `comment on`), nunca un `drop` inmediato.

## Reversa

`drop function crm.actividades_recientes_fn(integer); drop function
private.actividades_recientes_core(integer); drop function private.assert_actividades_recientes();
drop function private.assert_actividades_recientes_mutantes(); drop function
private.assert_actividades_recientes_base();` y retirar primero el front. Nada de datos que
deshacer: la migración solo lee.
