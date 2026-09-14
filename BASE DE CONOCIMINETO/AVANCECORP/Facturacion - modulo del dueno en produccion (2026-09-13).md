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
- **Vista «Todo S/» por defecto** y tramo **mes / semana / día**.
- **Marcar días sueltos** pulsando su cabecera (con pista animada).
- **Tablet**: menú plegado, abre en Semana, filtros plegables, blancos de 24 px.
- Servidor: `crm.facturacion_diaria_fn` (migración `20260910…`, registro 273).
- Los 9 fallos de la auditoría de Codex, corregidos.

## Lección repetida (11/09 y 13/09): otra sesión puede publicar tu trabajo

Dos veces seguidas la publicación de Facturación la hizo OTRA sesión al desplegar lo suyo,
porque el tronco es uno. Antes de dar algo por «pendiente de publicar»:

1. `curl https://crm.miavance.com/version.json` → `buildId`.
2. Buscar ese `buildId` en `CRM-Avance-Corp/releases/*.manifest.json` → commit vivo.
3. `git merge-base --is-ancestor <tu-commit> <commit-vivo>` → si SÍ, ya está en prod.

Y el bloqueo inverso también es real: el empaquetado lee del DISCO, así que archivos sin
commitear de otra sesión dentro de `app/` impiden publicar (pasó el 11/09 con 21 y el 13/09
con 39). El árbol compartido obliga a commitear pronto.

## A vigilar

Si a Miguel le molestan los ceros en la vista de dólares (analistas sin venta en USD), la
salida es un interruptor «ocultar filas en cero», no volver al roster parcial.

Relacionado: [[Inicio]] · [[F6 - cierre y ajustes publicados (2026-09-11)]] ·
[[G6 - conciliacion real preparada (2026-09-11)]]
