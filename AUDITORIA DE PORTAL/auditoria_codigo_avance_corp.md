# AUDITORÍA DE CÓDIGO — PORTAL AVANCE CORP
## Resultado y mejoras pendientes
**Fecha:** Junio 2026 | **Alcance:** 78 archivos, ~19,000 líneas | **Auditor:** Claude.ai

---

## CONTEXTO

Se auditó el código completo del Portal Avance Corp (cliente + admin + componentes + service worker + configuración Apache). Se revisó: estructura de archivos, flujo de autenticación, service worker / PWA, seguridad (secretos, CSP, headers), calidad de código y manejo de múltiples contratos.

**Estado general: el código es de calidad profesional.** Los hallazgos son higiene de repositorio y mejoras menores, NO bugs funcionales que bloqueen producción. El objetivo es pasar de "funciona" a "mantenible por un equipo".

---

## LO QUE ESTÁ BIEN (no tocar)

- ✅ Auth robusto: logout con limpieza defensiva de storage, `location.replace()` anti-historial, protección de bfcache (pageshow + persisted)
- ✅ Service worker correcto: patrón `controllerchange` con `hadInitialController` (estándar Workbox), cache versionado, network-first para HTML
- ✅ `resilientFetch` con retry exponencial que respeta `AbortError` (no reintenta cancelaciones de debounce)
- ✅ `customStorage` que alterna localStorage/sessionStorage según "mantener sesión"
- ✅ Seguridad: cero `service_role` expuesto, cero JWT en frontend, cero `console.log` activos en prod, CSP en modo enforcing, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP
- ✅ Estructura organizada: `js/components/`, `js/admin/`, `js/utils/`, `css/`
- ✅ `.htaccess` sólido: fuerza HTTPS, cache control, gzip, bloqueo de archivos sensibles

---

## HALLAZGO 1 — ARCHIVOS DUPLICADOS Y OBSOLETOS EN LA RAÍZ (Prioridad: ALTA)

### Problema
Existen versiones VIEJAS de varios archivos en la raíz del proyecto Y en sus carpetas correctas. Los archivos DIFIEREN en contenido. Los HTML referencian las versiones de las subcarpetas (`/js/...`, `/css/...`), por lo que los archivos en la raíz son huérfanos de una estructura plana anterior.

### Archivos afectados
| Archivo en raíz (OBSOLETO, borrar) | Versión real en uso (conservar) | Estado |
|---|---|---|
| `/auth.js` | `/js/auth.js` | Difieren (~3.7 KB) |
| `/dashboard.js` | `/js/dashboard.js` | Difieren (~5 KB) |
| `/inversion.js` | `/js/inversion.js` | Difieren (~3 KB) |
| `/mobile-menu.js` | `/js/mobile-menu.js` | Difieren (~1.4 KB) |
| `/premium-chart.js` | `/js/components/premium-chart.js` | Difieren |
| `/mobile.css` | `/css/mobile.css` | Difieren |
| `/scroll-lock.js` | `/js/utils/scroll-lock.js` | Idénticos |

### Riesgo
Alguien (humano o IA) edita el archivo equivocado de la raíz, no ve cambios reflejados (porque el HTML carga el de la subcarpeta), y pierde tiempo depurando.

### Acción requerida
1. Confirmar primero que NINGÚN HTML referencia los archivos de la raíz. Verificar con:
   ```bash
   grep -rn 'src="/auth.js"\|src="auth.js"\|src="./auth.js"' *.html
   grep -rn 'src="/dashboard.js"\|src="dashboard.js"' *.html
   # repetir para cada archivo. Los HTML deben usar SIEMPRE /js/... y /css/...
   ```
2. Solo tras confirmar que no hay referencias, borrar los archivos de la raíz:
   - `/auth.js`
   - `/dashboard.js`
   - `/inversion.js`
   - `/mobile-menu.js`
   - `/premium-chart.js`
   - `/mobile.css`
   - `/scroll-lock.js`

### Verificación
- Tras borrar, abrir cada página del portal (login, dashboard, inversión, mercados, novedades, documentos, perfil) y confirmar que cargan sin 404 en consola.
- Confirmar en Network tab que solo se cargan los archivos de `/js/` y `/css/`.

---

## HALLAZGO 2 — `config.json` PÚBLICO Y DESACTUALIZADO (Prioridad: MEDIA)

### Problema A — Exposición pública
`config.json` está desplegado en `public_html` y NO está bloqueado por `.htaccess` (el `FilesMatch` bloquea `package.json`, `composer.json`, etc., pero no `config.json`). El archivo expone:
- Email del superadmin: `AdminCorp@avancecorp.com`
- UUID del superadmin
- URL y anon_key de Supabase (la anon_key es pública por diseño, no es problema, pero el email del admin sí es un dato que facilita ataques dirigidos)

### Problema B — Contenido obsoleto
El archivo está desactualizado:
- Dice `"fase_actual": "FASE 1 - Login y estructura base"` (ya muy superado)
- Lista `dashboard.html` y `js/dashboard.js` como pendientes cuando ya están hechos
- `paleta_colores` contiene la paleta VIEJA verde/oscura (`#1a5c2a`, `#0a0a0a`, `#4CAF50`) en vez de la oficial actual: Navy `#111e3d`, Azul `#2563eb`, fondo blanco (tema claro)

### Acción requerida
Elegir UNA de estas opciones:

**Opción A (recomendada): eliminar del despliegue**
- Borrar `config.json` de `public_html`. Si se necesita como documentación interna, mantenerlo FUERA del directorio público (en el repo local, no en el deploy).

**Opción B: bloquear en .htaccess**
- Agregar `config\.json$` al `FilesMatch` de bloqueo existente:
  ```apache
  <FilesMatch "(^\.|\.md$|\.log$|\.sql$|\.env$|composer\.json$|package\.json$|package-lock\.json$|config\.json$)">
    Require all denied
  </FilesMatch>
  ```
- IMPORTANTE: NO bloquear `manifest.json` (debe seguir accesible para la PWA).

Si se conserva el archivo, además actualizar su contenido obsoleto (fase, pendientes, paleta de colores).

### Verificación
- Si Opción A: confirmar que `https://miavance.com/config.json` devuelve 404.
- Si Opción B: confirmar que `https://miavance.com/config.json` devuelve 403, y que `https://miavance.com/manifest.json` sigue devolviendo 200 (PWA no se rompe).

---

## HALLAZGO 3 — QUERY DUPLICADA EN CARGA DE PÁGINAS ADMIN (Prioridad: BAJA — performance)

### Problema
En `js/auth.js`, la función `verificarAdmin()` llama a `verificarSesion()`, que ya consulta la tabla `perfiles` por `(rol, activo, debe_cambiar_password)`. Inmediatamente después, `verificarAdmin()` vuelve a consultar `perfiles` por `(rol, activo)`. Son dos consultas casi idénticas a la misma tabla en cada carga de página admin.

### Acción requerida
Refactorizar para que `verificarSesion()` retorne el perfil junto con la sesión (o exponer el perfil ya cargado), y que `verificarAdmin()` lo reutilice en vez de hacer una segunda consulta.

Sugerencia de patrón:
```js
// verificarSesion() podría retornar { session, perfil } en vez de solo session
// y verificarAdmin() valida el rol sobre el perfil ya traído, sin segunda query.
```

### Cuidado
- Mantener la lógica defensiva intacta: el chequeo de `activo`, el gate de `debe_cambiar_password`, y las redirecciones.
- No romper los callers existentes de `verificarSesion()` en las páginas del cliente. Si se cambia la firma de retorno, revisar todos los `await verificarSesion()` del proyecto.

### Verificación
- Confirmar en Network tab que al cargar una página admin (ej. `admin/dashboard.html`) solo se hace UNA consulta a `perfiles`, no dos.
- Confirmar que el gate de cliente desactivado y el de primer ingreso siguen funcionando.

---

## HALLAZGO 4 — COMENTARIOS PLACEHOLDER EN `js/supabase.js` (Prioridad: BAJA — limpieza)

### Problema
El archivo `js/supabase.js` ya tiene las credenciales reales, pero conserva comentarios de plantilla confusos:
- `// ⚠️ REEMPLAZAR ESTAS CREDENCIALES CON LAS REALES`
- `// Tu anon key aquí`
- El bloque de instrucciones inicial que dice "Reemplaza SUPABASE_URL con tu Project URL..."

### Acción requerida
Eliminar los comentarios de plantilla / placeholder que ya no aplican. Conservar los comentarios técnicos útiles (los de `customStorage`, `resilientFetch`, y la nota sobre por qué se migró de jsdelivr a esm.sh — esos SÍ aportan valor).

### Verificación
- `view` final sobre `js/supabase.js`: no debe quedar texto que sugiera reemplazar credenciales que ya están puestas.
- Confirmar que el portal sigue conectando a Supabase (login funciona) — el cambio es solo de comentarios, no de código.

---

## HALLAZGO 5 — SELECTOR MULTI-CONTRATO ROMPE EL LAYOUT (Prioridad: MEDIA — visual)

### Problema
En `js/dashboard.js`, `montarSelectorContratos()` agrega un `<select>` al contenedor `.v4-hero-top`, donde ya vive el chip con el número de contrato y el badge "Activo". Cuando el cliente tiene más de un contrato, ambos elementos compiten por el espacio horizontal y el texto se corta (se ve "Contrato AC-202" cortado). La lógica funciona; el layout no.

### Acción requerida
Rediseñar el header de la card principal (hero) para manejar limpiamente el caso multi-contrato:
- Si el cliente tiene UN contrato: mostrar solo el número de contrato como texto estático + badge de estado. Sin dropdown.
- Si el cliente tiene MÁS DE UN contrato: dropdown estilizado donde cada opción muestre `[número] — [capital] [moneda] — [estado]`. El contrato seleccionado recarga todas las métricas (capital, rentabilidad, total, días, barra de progreso, gráfico). El badge de estado debe ir separado del selector, no superpuesto.
- Ancho máximo 100% del contenedor, sin overflow cortado. Probar en mobile (375px).

### Archivos a modificar
- `dashboard.html` (markup del header de la card hero)
- `js/dashboard.js` (función `montarSelectorContratos()` y el render del hero)
- Posiblemente `css/dashboard-v4.css` (estilos del selector — actualmente están inline en el JS, mejor moverlos al CSS)

### Verificación
1. Cliente con 1 contrato: no aparece dropdown, número y badge se ven completos.
2. Cliente con 2+ contratos: dropdown funcional; al cambiar selección se actualizan TODAS las métricas y el gráfico.
3. En 375px de ancho: nada se corta ni se desborda.

### Nota
Hay un screenshot de referencia (`IMG_1008.PNG`) que muestra el problema visual. Adjuntarlo al trabajar este hallazgo.

---

## RESUMEN DE ACCIONES

| # | Hallazgo | Prioridad | Tipo |
|---|---|---|---|
| 1 | Borrar archivos duplicados/obsoletos en raíz | ALTA | Limpieza de repo |
| 2 | Quitar/bloquear `config.json` público + actualizar contenido | MEDIA | Seguridad + doc |
| 3 | Eliminar query duplicada en `verificarAdmin()` | BAJA | Performance |
| 4 | Limpiar comentarios placeholder en `supabase.js` | BAJA | Limpieza |
| 5 | Rediseñar selector multi-contrato | MEDIA | UI/UX |

### Orden de ejecución recomendado
1. **Hallazgo 1** primero (limpieza de raíz — confirmar referencias antes de borrar)
2. **Hallazgo 2** (config.json — decisión simple, alto valor de seguridad)
3. **Hallazgo 5** (selector multi-contrato — requiere diseño, adjuntar screenshot)
4. **Hallazgos 3 y 4** al final (limpieza de bajo riesgo)

### Regla de seguridad para Claude Code
- Todos estos cambios son sobre archivos del frontend. Trabajar en una rama o copia, NO directo sobre los archivos en producción de Hostinger.
- Antes de borrar cualquier archivo (Hallazgo 1), confirmar con grep que no está referenciado.
- Después de cada hallazgo, verificar que el portal sigue cargando sin errores en consola antes de pasar al siguiente.

---

*Auditoría de código realizada: Junio 2026 — Portal Avance Corp, Grupo MasCapital.*
