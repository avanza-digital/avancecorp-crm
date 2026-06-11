---
tags: [auditoria, movil, responsive, historial]
actualizado: 2026-06-07
---

# Auditoría móvil 2026-06-07

Auditoría a fondo de la **versión móvil** del portal (todas las páginas y roles), con 4 agentes paralelos + verificación manual contra el código. Disparada por los cambios recientes (rol [[Rol Directorio]] y fusión asesor→analista, ver [[Fusión asesor-analista]]).

## Veredicto
La base móvil es **sólida y madura** (`css/mobile.css` con 9 pasos + `mobile-menu.js` + scroll-lock iOS-safe + `no-zoom.js`). **Sin bloqueantes críticos.** Logout en móvil funciona en TODOS los roles (drawer para cliente/admin; dropdown del avatar para analista; menú de cuenta propio para directorio). Login móvil sólido.

## Bugs funcionales encontrados y CORREGIDOS
- **pagos** — tras registrar/anular un pago en una fila de contrato expandida, el cronograma quedaba colgado en *"Cargando cronograma…"* (`EXPANDIDO` no se reseteaba y el cache se borraba). Fix: `renderTabla` recarga el cronograma del contrato expandido. (`pagos.js` v25→26)
- **documentos admin** — "Descargar" hacía `window.open()` **después** del `await` → Safari iOS bloqueaba el popup. Fix: pre-abrir pestaña en el gesto + fallback `<a>` (patrón espejo de `documentos.js` cliente). (admin `documentos.js` v15→16)
- **analista** — la vista previa del contrato no refrescaba al cambiar de moneda (faltaba listener en `k_moneda`); DNI sin longitud mínima (ahora 8–12, espejo de clientes); n° de cuenta ahora valida solo-dígitos; countdown 30s→15s + pausa en segundo plano. (`analista.js` v6→7)
- **directorio** — tooltips de los charts eran **solo hover** (inservibles en touch): añadido scrub táctil al chart de Evolución (su tip ya muestra "Captado" por mes, cubriendo ambos). CSV ahora usa **Web Share** en iOS (antes el `download` de blob no guardaba). Modales con scroll-lock; `#pwdModal` cierra tocando fuera; `recargar()` ya no queda en "Actualizando…" si falla un RPC; sin autofocus en móvil. (`directorio.js` v3→4)

## Touch targets subidos a 44px y otros
- `mobile.css` (v8→9, PASO 10): "Descargar" de docs del dashboard, "Descargar/Eliminar" de docs admin (`#tablaHistorial`), `.combo-item`, `.upload-remove`/`.lightbox-close`, alto del chart de mercados (lo pisaba `[id*="chart"]`), detalle de bandeja con wrap, **rótulos en las tarjetas de documentos** del cliente.
- Inline: ojito de privacidad del dashboard 44px; login "Olvidé mi contraseña" 44px + pill de país ya no finge ser interactivo; reset "Volver" / ojito 44px.
- `mobile-menu.js` (v9→10): el avatar `.v4-user-pill` (antes inerte) lleva a "Mi perfil"; **coordina los 3 overlays inferiores** (FAB instalar + banner PWA + prompt push) para que no se solapen (solo uno a la vez, prioridad push > banner > FAB) — se hizo aquí para evitar la cascada de cache-busting entre install-fab/install-prompt/push.

## Pendiente (no aplicado)
- Ninguno bloqueante. Deuda menor: `mobile.css` PASO 8 tiene reglas muertas (`#tradingview_chart_wrap` ya no existe); selector `.main-header-inner > .user-menu` quedó obsoleto por el wrapper `.user-menu-wrap`; `pagos` no usa la RPC paginada (escala futura).

> **Desplegado a Hostinger el 2026-06-07** (subida manual de Miguel). El patrón de [[project_auth_deploy_bump_v]] (bumpear `?v` en importadores) se aplicó a cada módulo editado, así que los clientes reciben los assets nuevos sin caché vieja.

## Notas relacionadas
[[Auditorías del portal]] · [[Arquitectura del portal]] · [[Rol Directorio]] · [[Rol Analista]] · [[Inicio]]
