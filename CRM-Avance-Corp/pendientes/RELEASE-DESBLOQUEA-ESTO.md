# El release del 23/09/2026: construido y verificado, esperando el `deploy`

**Todo está hecho menos subir el ZIP.** El artefacto existe, pasa los tres
controles y contiene todo lo que hay vivo. Lo único que falta es ejecutarlo con
el token de Hostinger, que solo tiene Miguel.

## 1. Publicar

El script lee el token de la variable de entorno `HOSTINGER_API_TOKEN`. Se
exporta desde el gestor de credenciales (nunca en la línea del comando) y luego:

```bash
node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs \
  deploy crm.miavance.com \
  ../avancecorp-release-20260923/CRM-Avance-Corp/releases/crm-20260923T020404Z-e65ef3f11b17.zip
```

El script **arranca su propio servidor MCP con `npx`** — no hace falta que el
MCP de la sesión esté conectado (el 23/09 los tres de Hostinger daban
`CONNECT_TIMEOUT`) — y **vuelve a pasar el preflight por su cuenta** antes de
subir nada.

### Lo que ya está verificado sobre ese ZIP

| | |
|---|---|
| `npm run check` | OK · 279 ficheros, 4170 tests |
| Manifiesto | OK · `ARTEFACTO_OK … 13ddd91a622d…` |
| Preflight | OK · `live=build-20260922T221442353Z/7d65fcdb484f candidate=e65ef3f11b17` |

🔴 **Por qué hubo que construirlo en un worktree aparte:** `main` local había
DIVERGIDO de `avancecorp/main` y **no contenía lo que estaba vivo**. Publicar
desde ahí habría borrado 55 ficheros y ~2.275 líneas (Gestión Diaria F4 / PR #73
y el acceso Avance / PR #74). El worktree está en
`../avancecorp-release-20260923`, commit `e65ef3f1`, y contiene lo vivo,
`avancecorp/main` entero y el trabajo del 22–23/09.

## 2. Smoke, justo después

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://crm.miavance.com/
curl -s https://crm.miavance.com/version.json     # buildId nuevo
```
Y comprobar que el `index-<hash>.js` que referencia el HTML vivo responde 200.

## 3. Aplicar las tres migraciones con pestillo, EN ESTE ORDEN

Primero confirmar que el front ya está vivo:

```bash
git merge-base --is-ancestor c2c9274b <commit del manifiesto publicado> \
  && echo LISTO || echo "TODAVIA NO"
```

| # | Migración | Qué hace |
|---|---|---|
| 1 | `20260922233545_crm_puerta5_declara_su_fuente.sql` | la #5 declara |
| 2 | `20260923002033_crm_puerta5_delega_en_la_mensual.sql` | la #5 delega (su preflight exige la anterior por md5) |
| 3 | `20260923012825_crm_puertas7y8_declaran_con_pestillo.sql` | la #8 declara, y la #7 lo hereda |

Las tres exigen, en la MISMA sesión de SQL:
`set local crm.ola1_front_publicado = 'si';`
**Nunca editar la migración commiteada:** se copia a un temporal y se le
antepone el `set local`. Después de cada una:
`supabase migration repair --status applied <versión> --linked`.

## 4. Comprobar que la unificación se sostiene

```bash
supabase db query --linked --file supabase/scripts/conversion/ensayo-cierre-unificacion.sql
```

Sella agosto de verdad, anula un cierre suyo y compara las cinco puertas, todo
con `rollback`. Tiene que decir que los cinco caminos restan lo mismo.

## 5. Devolver el merge a `main`, el mismo día

```bash
git merge --ff-only e65ef3f1    # o el commit final del worktree
git push avancecorp main
```

🔴 **Bloqueo conocido:** el merge toca `docs/gestion-diaria/GESTION-DIARIA.md`,
que está modificado sin commitear en la carpeta compartida. Git rechazará el
fast-forward mientras siga así. La sesión `avancecorp-desktop-bb` confirmó el
23/09 que **ese cambio no es suyo** —ya venía modificado cuando arrancó—, así
que hay que preguntar a la sesión `-2e` o a Miguel de quién es antes de tocarlo.

Y cuando ya no haga falta: `git worktree remove ../avancecorp-release-20260923`.

## 6. Rotar el token de Hostinger

Lleva pendiente desde que se pegó en claro. Después de este deploy, ya.
