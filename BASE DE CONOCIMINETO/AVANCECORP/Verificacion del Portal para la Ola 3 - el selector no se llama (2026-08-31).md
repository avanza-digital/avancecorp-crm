# Verificación del Portal para la Ola 3 — el selector NO se llama (2026-08-31)

Prerrequisito 3.0 de la **Ola 3** de la [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica|Fase 7]]: responder en binario, contra el paquete **VIVO** de miavance.com (no el repo — hubo deploys fuera de git), si alguna pantalla del portal llama al selector de productos del catálogo.

## Veredicto: **NO LLAMA** ✅

El portal vivo **nunca invoca** `public.productos_inversion_seleccion_fn`. El único archivo del sitio que contiene la llamada es **código muerto**: nada lo carga.

## La evidencia, anclada al paquete vivo

**Enumeración cerrada por el árbol REAL del hosting** (API de Hostinger, no suposición): 14 archivos en la raíz, 11 páginas en `admin/`, 47 JS en total — nombres idénticos al repo, sin páginas fantasma. Los **21 HTML y 47 JS vivos se descargaron y se buscaron todos**.

- **Único archivo con la llamada:** `js/admin/productos-contrato-ui.js` (línea 141), sha256 `780b955652f6fa832015f925965b7978aa445b520d63f3294dd73008aefceb4c` — **idéntico al byte** con el repo.
- **Nadie lo carga:** 0 etiquetas `<script>` en los 21 HTML vivos, 0 imports estáticos, 0 `import()` dinámicos en los otros 46 JS. El único import de `productos-contrato-core.js` es el propio `-ui.js`, y el core no hace ningún `rpc(...)`.
- **La pantalla de contratos** (`js/admin/contratos.js?v=40`, sha256 `ed618cfc…` == repo) solo **lee la columna** `producto_condicion_id` en sus SELECT; jamás llama al selector. `analista.js?v=25` (`3f81713b…` == repo) igual.
- Versiones vivas de los scripts admin al momento de la foto: analista v25 · bandeja v6 · clientes v43 · conciliacion v7 · contratos v40 · dashboard v21 · directorio v8 · documentos v20 · equipo v7 · novedades v24 · pagos v36.

## Qué corrige esta medición

La nota de la F5.d decía «el portal usa `public.productos_inversion_seleccion_fn(uuid)`» — eso era verdad **del código en el árbol**, no del sitio: el módulo que la llama existe pero es inalcanzable. **Consecuencia para la Ola 3: la puerta pública del selector SÍ puede entrar a la demolición** (revoke → observar → drop, con el método de la F7 y el OK de Miguel por pieza), sin release previo del portal.

## Refutación adversarial de Codex (misma tarde): EL VEREDICTO SE SOSTIENE

Codex atacó el veredicto por 6+ ángulos y no lo tumbó: sin RPC de nombre dinámico (`rg` de `.rpc(` no-literal: 0), el service worker (`avance-v112`) no precachea ni mencionó jamás el módulo, sin scripts inline que llamen `rpc`, los 2 únicos `import()` dinámicos cargan `/js/supabase.js`, sin eval/new Function/workers/iframes, y — el fuerte — **`git log -S` sobre todo el historial: ningún HTML publicado cargó jamás el módulo**, así que la hipótesis «CDN sirviendo un HTML viejo que sí lo cargaba» no tiene base histórica. Único cabo declarado (P2): los objetos reales en el borde de la CDN no son inspeccionables sin red desde su sandbox — sin sustento para sospechar, pero dicho.

## Lo que queda de la verificación

- ⏳ **Humo del panel Directorio** (AUM, ranking por cartera, top clientes) con un usuario real del Directorio — lo tiene que abrir Miguel logueado; yo no tengo esa sesión. Es la otra mitad del criterio 3.0.
- La foto vale al 2026-08-31 ~16:30 UTC; si el portal se re-despliega antes de la Ola 3, re-anclar (bastan los sha256 de arriba).

Relacionado: [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]] · la sección Ola R/F7 de `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`.
