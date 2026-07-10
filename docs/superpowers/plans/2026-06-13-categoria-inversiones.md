# Categoría de inversiones (Nuevo / Renovación / Upgrade) — Plan de implementación

> **Para ejecución:** este plan toca BD (3 RPCs + 1 columna), frontend admin, frontend analista, CSS y deploy. Sigue el patrón del portal (CLAUDE.md): `?v=N` por módulo + bump del Service Worker + deploy de todo `public_html/` vía Hostinger MCP. Cada cambio de BD se le muestra a Miguel ANTES de aplicar.

**Goal:** Etiquetar cada contrato de inversión con una categoría (Nuevo/Renovación/Upgrade), asignada **manualmente** por el admin o el analista al crear/editar el contrato, visible como badge en la tabla y la ficha, y filtrable.

**Architecture:** Columna `categoria` en `contratos` (nullable + CHECK). La escritura pasa por las RPCs `SECURITY DEFINER` que ya existen — `crear_contrato` (admin+analista, obligatoria al crear), `actualizar_contrato` (corrección del analista), `actualizar_numero_contrato` (edición del admin). El frontend añade un `<select>` a los dos formularios de contrato (admin `n_categoria`, analista `k_categoria`), un badge en tabla/detalle y un filtro server-side.

**Tech Stack:** Supabase (Postgres + RLS + RPC), JavaScript vanilla ES Modules, CSS con tokens, Service Worker cache-busting.

---

## Decisiones de diseño (cerradas con Miguel)

- **Vive en el contrato** (no en el cliente) → conserva historial + reportes por periodo.
- **Asignación MANUAL** por admin y analista (hay casos fuera de regla).
- **Obligatoria al crear** (validada en frontend Y en la RPC `crear_contrato`).
- **Editable** después: admin vía `actualizar_numero_contrato`; analista vía `actualizar_contrato` (dentro de su ventana de 5 h).
- **Valores en BD:** `nuevo` · `renovacion` · `upgrade` (ascii/minúscula, como `estado`). Etiqueta visible con tilde vía mapa JS (`Renovación`).
- **33 contratos existentes:** quedan `categoria = NULL` ("—" en la tabla). Se clasifican a mano al editarlos. Sin backfill automático (no se puede deducir retroactivamente).
- **Colores de badge:** nuevo = verde · renovación = azul · upgrade = dorado.
- **Solo admin/analista** lo ven. El portal del cliente NO cambia.

---

## FASE 1 — Base de datos (mostrar SQL a Miguel antes de aplicar)

Se aplica vía Supabase MCP (`apply_migration`), proyecto `dctqcbznekcyxhjujuci`. Cada migración con su nombre snake_case.

### Tarea 1.1 — Columna `categoria`

- [ ] **Migración `contratos_categoria_columna`:**

```sql
ALTER TABLE public.contratos
  ADD COLUMN categoria text
  CHECK (categoria IS NULL OR categoria IN ('nuevo','renovacion','upgrade'));

COMMENT ON COLUMN public.contratos.categoria IS
  'Tipo de operación de inversión: nuevo | renovacion | upgrade. NULL = contrato antiguo sin clasificar.';
```

- [ ] **Verificar:** `select column_name, data_type, is_nullable from information_schema.columns where table_name='contratos' and column_name='categoria';` → 1 fila, nullable=YES.

### Tarea 1.2 — `crear_contrato`: aceptar e insertar `categoria` (obligatoria)

Reemplazar la función completa (es `CREATE OR REPLACE`). Cambios vs. la actual: (a) declarar `v_categoria`; (b) validar que sea uno de los 3 valores; (c) agregar `categoria` al INSERT.

- [ ] **Migración `crear_contrato_con_categoria`:** misma función actual + estos 3 cambios:
  - En el bloque `DECLARE`, añadir: `v_categoria text := p_contrato->>'categoria';`
  - Tras la validación de tasa (antes de generar el N°), añadir:
    ```sql
    -- Categoría obligatoria y válida (manual; el front la exige, el server la reespeja)
    IF v_categoria IS NULL OR v_categoria NOT IN ('nuevo','renovacion','upgrade') THEN
      RAISE EXCEPTION 'Selecciona la categoría del contrato (Nuevo, Renovación o Upgrade)';
    END IF;
    ```
  - En el `INSERT INTO public.contratos (...)`, añadir `categoria` a la lista de columnas (tras `notas_internas`) y `v_categoria` a la lista de `VALUES` (en la misma posición, antes de `'activo', v_uid`).

- [ ] **Verificar:** crear un contrato de prueba por RPC sin `categoria` → debe fallar con el mensaje en español; con `categoria:'nuevo'` → inserta y la fila queda con `categoria='nuevo'`. (Hacer en transacción revertida o limpiar la fila de prueba.)

### Tarea 1.3 — `actualizar_contrato`: permitir editar `categoria` (analista)

Reemplazar la función completa. Cambios: validar categoría si viene, y añadirla al `UPDATE`.

- [ ] **Migración `actualizar_contrato_con_categoria`:** misma función actual + :
  - Tras la validación de tasa, añadir:
    ```sql
    IF (p_contrato->>'categoria') IS NOT NULL
       AND (p_contrato->>'categoria') NOT IN ('nuevo','renovacion','upgrade') THEN
      RAISE EXCEPTION 'Categoría inválida';
    END IF;
    ```
  - En el `UPDATE public.contratos SET ...`, añadir una línea (tras `notas_internas = ...`):
    ```sql
    categoria = COALESCE(NULLIF(p_contrato->>'categoria',''), categoria),
    ```
    (COALESCE → si no viene, conserva la actual; nunca la borra.)

- [ ] **Verificar:** llamar `actualizar_contrato` con `categoria:'upgrade'` sobre un contrato del analista → la fila cambia a `upgrade`.

### Tarea 1.4 — `actualizar_numero_contrato`: permitir editar `categoria` (admin)

El admin edita por esta RPC (no regenera cronograma → funciona con cuotas pagadas). Añadir un parámetro `p_categoria`.

- [ ] **Migración `actualizar_numero_contrato_con_categoria`:**
  - Firma nueva: `actualizar_numero_contrato(p_id uuid, p_numero text, p_notas text DEFAULT NULL, p_categoria text DEFAULT NULL)`.
  - Tras el check de `es_admin()`, validar:
    ```sql
    IF p_categoria IS NOT NULL AND p_categoria NOT IN ('nuevo','renovacion','upgrade') THEN
      RAISE EXCEPTION 'Categoría inválida';
    END IF;
    ```
  - En el `UPDATE`, añadir:
    ```sql
    categoria = COALESCE(NULLIF(btrim(p_categoria),''), categoria),
    ```
  - **Nota:** Postgres permite añadir un parámetro con DEFAULT sin romper a los llamadores viejos, pero como cambia la firma conviene `DROP FUNCTION public.actualizar_numero_contrato(uuid,text,text);` antes del `CREATE OR REPLACE`, o crear la nueva firma y revocar/eliminar la vieja. Mantener `GRANT EXECUTE ... TO authenticated` y `REVOKE ... FROM anon, public` (igual que hoy).

- [ ] **Verificar:** `actualizar_numero_contrato(p_id, '000123', 'nota', 'renovacion')` como admin → la fila queda con `categoria='renovacion'` y cronograma intacto.

### Tarea 1.5 — Advisors

- [ ] Correr `get_advisors(type:'security')` → confirmar **cero hallazgos nuevos** (solo los WARN preexistentes de `SECURITY DEFINER`/`pg_trgm`/`pg_net`).

---

## FASE 2 — Frontend admin (`public_html/admin/contratos.html` + `public_html/js/admin/contratos.js`)

### Tarea 2.1 — Mapa de etiquetas (helper local)

- [ ] En `contratos.js`, cerca de las constantes del tope (tras `PREFIJO_CONTRATO`), añadir:
```javascript
// Categoría de inversión: valor en BD → etiqueta visible (con tilde)
const CATEGORIA_LABEL = { nuevo: 'Nuevo', renovacion: 'Renovación', upgrade: 'Upgrade' }
```

### Tarea 2.2 — `<select>` de categoría en el modal (crear/editar)

- [ ] En `contratos.html`, dentro de `#formNuevo`, **después** del `form-grid-2` de Modalidad/Tipo de interés (línea ~247) y **antes** del bloque de fechas (~249), insertar:
```html
<div class="input-group">
  <label class="input-label" for="n_categoria">Categoría de la inversión *</label>
  <select class="input" id="n_categoria" required>
    <option value="" disabled selected>Selecciona…</option>
    <option value="nuevo">Nuevo (primera inversión)</option>
    <option value="renovacion">Renovación (reinvierte)</option>
    <option value="upgrade">Upgrade (aumenta capital)</option>
  </select>
</div>
```

### Tarea 2.3 — Leer la categoría en `obtenerDatosForm()`

- [ ] En `contratos.js`, en el objeto que retorna `obtenerDatosForm()` (línea ~953), añadir tras `notas_internas`:
```javascript
    categoria: document.getElementById('n_categoria').value || null,
```

### Tarea 2.4 — Enviar `categoria` al crear

- [ ] En `crearContrato()`, en el objeto `p_contrato` (línea ~1109), añadir tras `notas_internas: d.notas_internas`:
```javascript
      categoria: d.categoria,
```
- [ ] Añadir validación de frontend (antes de armar el cronograma, junto a las demás validaciones ~1032):
```javascript
  if (!d.categoria) {
    errEl.textContent = 'Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).'
    errEl.classList.remove('hidden')
    return
  }
```

### Tarea 2.5 — Precargar y dejar editable la categoría en `abrirModalEditar()`

- [ ] En `abrirModalEditar()` (tras la línea `...n_notas...value = c.notas_internas`, ~779), añadir:
```javascript
  document.getElementById('n_categoria').value = c.categoria || ''
```
- [ ] **Confirmar que `setCamposContractualesBloqueados(true)` NO bloquea `n_categoria`** (la categoría SÍ debe poder editarse). Revisar la lista de IDs que esa función deshabilita; `n_categoria` no debe estar. Si la función bloquea por un selector amplio, exceptuar `n_categoria`. Actualizar también el texto del banner de edición para mencionar que la categoría sí se puede corregir.

### Tarea 2.6 — Enviar `categoria` al editar (admin → `actualizar_numero_contrato`)

- [ ] En `guardarEdicionContrato()` (~1135), en la llamada `supabase.rpc('actualizar_numero_contrato', {...})`, añadir el argumento:
```javascript
    p_categoria: document.getElementById('n_categoria').value || null,
```
- [ ] Validar antes de llamar a la RPC: si `n_categoria` está vacío, mostrar el mismo error de "Selecciona la categoría…" y `return`.

### Tarea 2.7 — Traer `categoria` en la query de la lista

- [ ] En `cargarContratos()`, en el `.select('...')` (línea ~63-66), añadir `categoria` a la lista de columnas de `contratos` (junto a `estado`).

### Tarea 2.8 — Columna + badge en la tabla

- [ ] En `contratos.html`, en el `<thead>` (línea ~162), añadir `<th>Categoría</th>` entre `<th>Estado</th>` y `<th>Acciones</th>`.
- [ ] En `contratos.html`, en las filas de "Cargando…"/vacío, subir el `colspan` de **9 → 10** (línea ~167; y el del estado vacío en `renderTabla`).
- [ ] En `contratos.js`, en `renderTabla()`, tras la línea del badge de estado, añadir:
```javascript
    const catBadge = c.categoria
      ? `<span class="badge badge-${c.categoria}">${CATEGORIA_LABEL[c.categoria]}</span>`
      : '<span class="text-muted">—</span>'
```
- [ ] En el template de la fila, añadir `<td>${catBadge}</td>` entre la celda de estado (`<td>${badge}</td>`) y la de acciones.
- [ ] Subir a **10** cualquier `colspan="9"` del cuerpo (estado vacío de `renderTabla`).

### Tarea 2.9 — Categoría en la ficha de detalle

- [ ] En `mostrarDetalle()` (~622), tras el `<div class="field">` del Estado, añadir:
```javascript
      <div class="field"><span class="field-label">Categoría</span>${contrato.categoria ? `<span class="badge badge-${contrato.categoria}">${CATEGORIA_LABEL[contrato.categoria]}</span>` : '<span class="text-muted">—</span>'}</div>
```

### Tarea 2.10 — Filtro por categoría

- [ ] En `contratos.html`, en `.filter-bar` (tras `#filterMoneda`, ~148), añadir:
```html
<select class="input" id="filterCategoria">
  <option value="">Todas las categorías</option>
  <option value="nuevo">Nuevo</option>
  <option value="renovacion">Renovación</option>
  <option value="upgrade">Upgrade</option>
  <option value="__sin">Sin categoría</option>
</select>
```
- [ ] En `contratos.js`, declarar el estado: `let FILTRO_CATEGORIA = ''` (junto a `FILTRO_MONEDA`, ~26).
- [ ] En `cargarContratos()`, tras `if (FILTRO_MONEDA) q = q.eq('moneda', FILTRO_MONEDA)`, añadir:
```javascript
  if (FILTRO_CATEGORIA === '__sin') q = q.is('categoria', null)
  else if (FILTRO_CATEGORIA) q = q.eq('categoria', FILTRO_CATEGORIA)
```
- [ ] En los listeners (~1407), añadir:
```javascript
  document.getElementById('filterCategoria')?.addEventListener('change', (e) => {
    FILTRO_CATEGORIA = e.target.value
    PAGINA_ACTUAL = 0
    recargarSoloContratos()
  })
```

---

## FASE 3 — Frontend analista (`public_html/admin/analista.html` + `public_html/js/admin/analista.js`)

### Tarea 3.1 — Mapa de etiquetas

- [ ] En `analista.js`, junto a `PREFIJO_CONTRATO` (~634), añadir el mismo `CATEGORIA_LABEL`.

### Tarea 3.2 — `<select>` de categoría en el modal de contrato del analista

- [ ] En `analista.html`, dentro del modal de contrato, después del `form-grid-2` de Tipo de interés/Modalidad (~380), insertar:
```html
<div class="input-group">
  <label class="input-label" for="k_categoria">Categoría de la inversión *</label>
  <select class="input" id="k_categoria" required>
    <option value="" disabled selected>Selecciona…</option>
    <option value="nuevo">Nuevo (primera inversión)</option>
    <option value="renovacion">Renovación (reinvierte)</option>
    <option value="upgrade">Upgrade (aumenta capital)</option>
  </select>
</div>
```

### Tarea 3.3 — Leer categoría en `datosContratoForm()`

- [ ] En `analista.js`, en el objeto de `datosContratoForm()` (~649), añadir tras `notas_internas`:
```javascript
    categoria: document.getElementById('k_categoria').value || null,
```

### Tarea 3.4 — Validación + precarga

- [ ] En `guardarContrato()` (~744), añadir a las validaciones:
```javascript
  if (!d.categoria) {
    errEl.textContent = 'Selecciona la categoría de la inversión (Nuevo, Renovación o Upgrade).'
    errEl.classList.remove('hidden'); return
  }
```
- [ ] En la precarga de "Corregir contrato" (~715, tras `k_notas`), añadir:
```javascript
  document.getElementById('k_categoria').value = k.categoria || ''
```
- [ ] El submit del analista ya pasa `p_contrato: d` tal cual a `crear_contrato` y `actualizar_contrato`, así que `categoria` viaja automáticamente. **No** hay que tocar las llamadas RPC.

### Tarea 3.5 — Traer `categoria` en el SELECT del analista

- [ ] En `analista.js`, en el `.select('id, numero_contrato, ... estado, notas_internas, creado_en')` (~240), añadir `categoria`. (Si el analista lista/muestra contratos con badge, replicar el badge igual que el admin; si solo los corrige, basta con traer la columna para precargar.)

---

## FASE 4 — CSS de los badges (`public_html/css/admin.css`)

Las clases base `.badge` viven en `main.css` (cargado por todas las páginas admin). Las variantes de **categoría** son admin-only → van en `admin.css` para no bumpear `main.css` en las 16 páginas cliente.

- [ ] Al final de `admin.css`, añadir:
```css
/* Badges de categoría de inversión (admin) */
.badge-nuevo      { background: var(--green-bg); color: var(--green); }
.badge-renovacion { background: var(--info-bg);  color: var(--info); }
.badge-upgrade    { background: var(--gold-pale); color: var(--gold); border: 1px solid #f0c060aa; }
```
- [ ] Confirmar que `admin/contratos.html` y `admin/analista.html` cargan `admin.css` (ambos lo cargan en `?v=17`, verificado).

---

## FASE 5 — Versionado y deploy

### Tarea 5.1 — Bump de versiones (`?v=N`)

- [ ] `admin/contratos.html`: `contratos.js?v=27` → `?v=28`.
- [ ] `admin/analista.html`: `analista.js?v=12` → `?v=13`.
- [ ] `admin.css?v=17` → `?v=18` en **todos** los HTML de `/admin/` que lo cargan. Usar el patrón del proyecto:
  ```bash
  grep -rl "admin.css?v=17" public_html/admin | xargs sed -i '' 's/admin.css?v=17/admin.css?v=18/g'
  ```
  (verificar después que no queda ningún `admin.css?v=17`).
- [ ] `service-worker.js`: `CACHE_VERSION = 'avance-v89'` → `'avance-v90'`.
- [ ] Actualizar la tabla de versiones del CLAUDE.md (§13) y agregar entrada al changelog (§ÚLTIMA ACTUALIZACIÓN).

### Tarea 5.2 — Deploy

- [ ] **BD:** ya aplicada en FASE 1 (producción).
- [ ] **Frontend:** desplegar `public_html/` a miavance.com vía Hostinger MCP (`hosting_deployStaticWebsite`, ZIP sin los 5 archivos locales: `CLAUDE.md`, `.git/`, `.claude/`, `.gitignore`, `.DS_Store`).

---

## FASE 6 — Verificación

- [ ] `node --check public_html/js/admin/contratos.js` y `node --check public_html/js/admin/analista.js` → sin errores.
- [ ] **SQL:** crear un contrato de prueba (como admin) con `categoria='nuevo'` → fila OK; intentar crear sin categoría → error en español. Limpiar la prueba.
- [ ] **Navegador (Miguel, en incógnito):**
  - Admin → Contratos → "+ Nuevo contrato": el select de categoría aparece y es obligatorio; crear uno → la tabla muestra el badge de color.
  - Editar un contrato → cambiar la categoría → se guarda (cronograma intacto).
  - Filtrar por "Renovación" y por "Sin categoría".
  - Abrir "Ver detalle" → la ficha muestra el badge de categoría.
  - Como **analista**: crear un contrato → exige categoría; corregir uno dentro de la ventana → la categoría cambia.
- [ ] **Auditoría adversarial** (1 subagente): IDs HTML↔JS consistentes (`n_categoria`/`k_categoria`), las 3 RPCs validan el valor, el badge usa `escapeHtml`/valor controlado (los valores son de un set fijo, no input libre → seguro), `colspan` correcto, sin referencias colgantes.

---

## Resumen de archivos tocados

| Capa | Archivos |
|---|---|
| BD (MCP) | columna `contratos.categoria` + RPCs `crear_contrato`, `actualizar_contrato`, `actualizar_numero_contrato` |
| Admin | `admin/contratos.html`, `js/admin/contratos.js` |
| Analista | `admin/analista.html`, `js/admin/analista.js` |
| CSS | `css/admin.css` (+ bump `?v` en HTML admin) |
| Infra | `service-worker.js`, `CLAUDE.md` (§13 + changelog) |
