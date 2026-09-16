# Facturación: el módulo del dueño, completo en producción (2026-09-13)

**Estado:** 🟢 COMPLETO y VIVO en `crm.miavance.com` desde el 13/09/2026 a las 18:06 Lima
(`build-20260913T230629516Z`, commit `9bd86c3`, chunk `facturacion-C3-5eJPN.js`, 30 984 B,
SHA-256 igual al manifiesto). Publicado por la sesión de Control de Citas, que arrastró los
cinco commits de Facturación (`49f940f` → `5ec81cc`) al desplegar su propio trabajo.

## Qué resuelve (idioma de negocio)

Miguel ve **cuánto se vendió cada día, por supervisor y por analista**, sin pedir informes.
Pantalla «Facturación» del CRM, en pesos y dólares por separado, con el total del día en
soles al tipo de cambio del motor (`lib/tipo-cambio.ts`, promedio 7 días hábiles SBS/BCRP).

## Lo que trae la versión viva

- **Roster completo**: todo analista activo aparece, aunque su mes esté en cero
  (sembrado con `crm.equipo_visible_fn`). La tabla NO cambia de filas al cambiar de moneda.
- **Selector de tipo de capital**: Capital nuevo · Renovaciones · Upgrades · Cooperativa · Todos.
- **Vista «Todo S/» por defecto** y tramo **mes / semana / día**. **Desde el 14/09 (`build-20260914T150911131Z`, commit `c22e2ed`, publicado por Miguel ~10:25 Lima) abre en «Todos los tipos» y en Mes, también en tablet** (Miguel: «por default el módulo abra en la vista de MES, y con el filtro todos los tipos para ver todo el capital»). Motivo: la renovación de US$ 10 000 de Rosa Aguirre del 10/09 «no salía» porque la pantalla abría en Capital nuevo.
- **Marcar días sueltos** pulsando su cabecera (con pista animada).
- **Tablet**: menú plegado, filtros plegables, blancos de 24 px. (Del 11 al 14/09 abría en Semana; desde el 14/09 abre en Mes como el escritorio.)
- Servidor: `crm.facturacion_diaria_fn` (migración `20260910…`, registro 273).
- Los 9 fallos de la auditoría de Codex, corregidos.

## Publicar con el árbol compartido sucio (14/09): worktree limpio

El 14/09 otra sesión (Codex, Citas) tenía 13 archivos de `app/` sin commitear. El empaquetado
lee del disco y `release:crm` exige árbol limpio, así que el release se construyó en un
worktree temporal (`git worktree add --detach <carpeta> <commit>`), con symlinks de
`CRM-Avance-Corp/node_modules` y `app/node_modules` (no el de la raíz) y las dos variables
`VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` exportadas en el shell (son públicas: van en el
chunk `crm-api-*.js` de todo navegador). `npm run release:crm -- --output <raíz>/CRM-Avance-Corp/releases`
deja el ZIP donde el preflight lo busca. Luego el worktree se borra.

## Lección repetida (11/09 y 13/09): otra sesión puede publicar tu trabajo

Dos veces seguidas la publicación de Facturación la hizo OTRA sesión al desplegar lo suyo,
porque el tronco es uno. Antes de dar algo por «pendiente de publicar»:

1. `curl https://crm.miavance.com/version.json` → `buildId`.
2. Buscar ese `buildId` en `CRM-Avance-Corp/releases/*.manifest.json` → commit vivo.
3. `git merge-base --is-ancestor <tu-commit> <commit-vivo>` → si SÍ, ya está en prod.

Y el bloqueo inverso también es real: el empaquetado lee del DISCO, así que archivos sin
commitear de otra sesión dentro de `app/` impiden publicar (pasó el 11/09 con 21 y el 13/09
con 39). El árbol compartido obliga a commitear pronto.

## 16/09/2026: el supervisor también la tiene, y ve SU equipo

Miguel: «quiero que el módulo de facturación lo tengan los supervisores, para ver el avance de
sus equipos». Migración `20260916205617_crm_facturacion_diaria_supervisor` + front en el mismo
commit (capacidad `verFacturacion`, Gerencia y Supervisión). **SQL instalada y registrada en
producción el 16/09 ~16:30 Lima** con el `!` de Miguel; el front sale con `/release-crm`.

**Qué ve el supervisor (regla de negocio, no de pantalla).** Las filas cuyo *supervisor de
entonces* es él (o alguien de su subárbol) más sus ventas propias. Es la misma regla con la que
la función ya acredita cada venta a Gerencia («el supervisor es el de entonces, no el de hoy»,
Miguel 10/09), aplicada como recorte:

- un analista que **se fue** de su equipo a mitad de mes: lo que vendió bajo él sigue en su
  pantalla; lo de después, no;
- un analista que **llegó** a mitad de mes: solo lo vendido desde que llegó; lo anterior es del
  otro supervisor y **el nombre del otro supervisor no le llega** (criterio M-1: nadie fuera de
  Gerencia lee a qué equipo pertenecía alguien de otro equipo);
- vendedor, coordinador y ajenos siguen recibiendo VACÍO.

No se usó el organigrama de hoy (`analista_id = any(visibles)`, lo que hace
`metricas_capital_mes_fn`) porque rompía las dos cosas: enseñaba al supervisor filas rotuladas
con OTRO equipo y le quitaba al otro las ventas que la regla de Miguel le acredita.

**La pantalla no cambió.** Recibe del servidor solo lo suyo y el roster (`equipo_visible_fn`) ya
le trae solo su subárbol. Sus ventas propias entran como una fila más, bajo «Sin supervisor»,
igual que las ve Gerencia hoy (producción fuera del ranking).

**Cómo se probó.** `test-facturacion.sql` casos 10–12 (con un cambio de equipo real sembrado y
deshecho) y el bloque de facturación de `test-rls.mjs` (`sup1`/`sup2` reciben exactamente las
filas de Gerencia bajo su predicado). El postflight de la migración ensaya lo mismo con los
datos reales de producción dentro de la transacción antes de hacer commit.

Relacionado: [[Lead propio del supervisor - 2026-09-16]] · [[Hoy del supervisor - reparto compacto]].

## A vigilar

Si a Miguel le molestan los ceros en la vista de dólares (analistas sin venta en USD), la
salida es un interruptor «ocultar filas en cero», no volver al roster parcial.

Relacionado: [[Inicio]] · [[F6 - cierre y ajustes publicados (2026-09-11)]] ·
[[G6 - conciliacion real preparada (2026-09-11)]]
