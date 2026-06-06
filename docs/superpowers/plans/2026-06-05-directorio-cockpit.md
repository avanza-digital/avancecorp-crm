# Rol Directorio — Cockpit ejecutivo · Plan de Implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crear un rol `directorio` de solo lectura para los dueños (Kirk y Carlos) con un panel ejecutivo ("cockpit oscuro") que muestra 9 métricas del negocio con drill-down, y que pueden cambiar su propia contraseña.

**Architecture:** Se replica el patrón del rol `analista` ya existente. El rol vive en `perfiles.rol`; el acceso a datos de negocio es **exclusivamente vía RPCs `SECURITY DEFINER`** que validan `es_directorio() OR es_admin()` (el directorio NO tiene SELECT directo a las tablas). Frontend en JS vanilla (ES Modules) + Supabase, gráficos SVG custom, deploy manual a Hostinger.

**Tech Stack:** Supabase (Postgres + Auth + Edge Functions Deno/TS), JavaScript vanilla ES Modules, HTML/CSS sin build step.

---

## Notas de método (leer antes de empezar)

1. **No hay framework de tests.** El portal nunca tuvo tests automatizados; el patrón establecido (igual que se validó el rol analista) es **verificación manual contra la BD real** + revisión visual con capturas. Por eso, en este plan el "test" de cada tarea son **pruebas concretas ejecutables**: queries/INSERT de prueba vía Supabase MCP (`execute_sql`) que deben pasar o fallar como se indica, y checks en el navegador. No se inventa un harness de tests (sería YAGNI y rompería el patrón del repo).

2. **Regla de Miguel — mostrar SQL primero.** Toda tarea de BD muestra el SQL **verbatim** y se aplica vía Supabase MCP (`apply_migration`) **solo tras OK de Miguel**. El SQL ya está escrito completo en cada tarea; no improvisar.

3. **Deploy manual.** Tras editar archivos del portal, hay que copiar a la carpeta espejo de Hostinger y subir el `?v=N` del módulo editado (ver Tarea 11). Las edge functions se despliegan vía MCP `deploy_edge_function`.

4. **3 definiciones de negocio a CONFIRMAR con Miguel al revisar el SQL** (están marcadas `⚠️ CONFIRMAR` en las tareas 2 y 3). Si Miguel las cambia, se ajusta el SQL de esa tarea antes de aplicar:
   - **Intereses pagados a clientes** = suma de `monto_pagado` de cuotas con `tipo='retorno'` y `estado='pagado'`.
   - **Ranking por analista** = se agrupan los contratos por el asesor del cliente (`perfiles.asesor_perfil_id`), no por quién tecleó el contrato.
   - **Crecimiento de capital** = capital captado por mes (suma de `capital` por mes de `fecha_inicio`), mostrado acumulado en la línea.

---

## File Structure

**Crear:**
- `public_html/admin/directorio.html` — pantalla cockpit (shell sin nav, patrón analista).
- `public_html/js/admin/directorio.js` — carga de métricas (RPC), render de KPIs/gráficos, drill-down, cambiar contraseña.
- `public_html/css/directorio.css` — estilos del cockpit oscuro.

**Modificar:**
- `public_html/js/auth.js` — `verificarDirectorio()` + ramas de enrutado en `login()` y `redirigirSiAutenticado()`.
- `_supabase_functions/functions/crear-admin/index.ts` — aceptar `rol='directorio'` (solo superadmin) + clave temporal = DNI si no se envía password.
- `public_html/admin/equipo.html` — opción "Directorio" en el selector de tipo.
- `public_html/js/admin/equipo.js` — payload con `directorio`, badge, password opcional.
- `public_html/CLAUDE.md` — documentar el rol nuevo (fuente de verdad técnica).
- `BASE DE CONOCIMINETO/AVANCECORP/Rol Directorio.md` — nota del vault (crear) + enlazar desde `Inicio.md`.

**BD (vía MCP, sin archivo en repo salvo respaldo):** constraint `perfiles_rol_check`, función `es_directorio()`, RPCs `metricas_directorio()`, `directorio_top_clientes()`, `directorio_morosidad()`, `directorio_ranking_analistas()`.

---

## Task 1: BD — Rol `directorio` (constraint + helper `es_directorio()`)

**Objetivo:** Que la BD acepte el valor `'directorio'` en `perfiles.rol` y exista el helper de rol, SIN darle ningún permiso de lectura/escritura sobre tablas de negocio.

**Files:**
- Aplicar vía Supabase MCP `apply_migration` (name: `directorio_rol_y_helper`).
- Respaldo: guardar el SQL en `AUDITORIA DE PORTAL/directorio_2026-06-05.sql` (append).

- [ ] **Step 1: Inspeccionar el CHECK actual de `perfiles.rol`**

Vía MCP `execute_sql`:
```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.perfiles'::regclass AND contype = 'c';
```
Expected: aparece un CHECK tipo `perfiles_rol_check` con `rol = ANY (ARRAY['cliente','analista','admin','superadmin'])`. **Anota el nombre exacto** (puede no llamarse `perfiles_rol_check`). Usa ese nombre real en el Step 2.

- [ ] **Step 2: Mostrar a Miguel el SQL y, con OK, aplicar la migración**

```sql
-- 1) Ampliar el CHECK del rol para incluir 'directorio'
ALTER TABLE public.perfiles DROP CONSTRAINT perfiles_rol_check;  -- usar el nombre real del Step 1
ALTER TABLE public.perfiles ADD CONSTRAINT perfiles_rol_check
  CHECK (rol = ANY (ARRAY['cliente','analista','admin','superadmin','directorio']));

-- 2) Helper de rol, espejo de es_analista()
CREATE OR REPLACE FUNCTION public.es_directorio()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid() AND rol = 'directorio' AND activo = true
  );
$$;

REVOKE EXECUTE ON FUNCTION public.es_directorio() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.es_directorio() TO authenticated;
```
Aplicar con MCP `apply_migration`, name `directorio_rol_y_helper`.

- [ ] **Step 3: Verificar que la constraint y el helper existen**

```sql
SELECT pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='public.perfiles'::regclass AND contype='c';
SELECT proname FROM pg_proc WHERE proname='es_directorio';
```
Expected: el CHECK ahora incluye `directorio`; `es_directorio` aparece.

- [ ] **Step 4: Commit del respaldo SQL**

```bash
git add "AUDITORIA DE PORTAL/directorio_2026-06-05.sql"
git commit -m "BD: rol directorio (constraint + helper es_directorio)"
```

---

## Task 2: BD — RPC `metricas_directorio()` (KPIs de cabecera)

**Objetivo:** Una sola función que devuelve, en `jsonb`, todos los números de la fila de KPIs + la serie de crecimiento. Validada por rol. El directorio la llama; no toca tablas.

**Files:** MCP `apply_migration` (name `directorio_rpc_metricas`). Respaldo en el mismo `.sql`.

⚠️ **CONFIRMAR con Miguel** antes de aplicar: definiciones de "intereses pagados" y "crecimiento" (ver Notas de método #4).

- [ ] **Step 1: Confirmar nombres de columnas reales**

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('contratos','cronograma_pagos','perfiles')
ORDER BY table_name, ordinal_position;
```
Expected (según exploración): `contratos(capital, moneda, tasa_anual, estado, fecha_inicio, cliente_id, ...)`, `cronograma_pagos(monto_programado, monto_pagado, estado, tipo, fecha_programada, fecha_pago_real, contrato_id, ...)`, `perfiles(rol, activo, asesor_perfil_id, creado_en, ...)`. **Si algún nombre difiere, ajustar el SQL del Step 2.**

- [ ] **Step 2: Mostrar el SQL a Miguel y, con OK, aplicar**

```sql
CREATE OR REPLACE FUNCTION public.metricas_directorio()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v jsonb;
  hoy date := (now() AT TIME ZONE 'America/Lima')::date;
  inicio_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Lima'))::date;
BEGIN
  -- Guard de rol: solo directorio o admin/superadmin
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  WITH activos AS (
    SELECT * FROM contratos WHERE estado = 'activo'
  ),
  aum AS (
    SELECT moneda,
           COALESCE(SUM(capital),0) AS total,
           COALESCE(SUM(capital) FILTER (WHERE fecha_inicio >= inicio_mes),0) AS captado_mes
    FROM activos GROUP BY moneda
  ),
  cuotas AS (
    SELECT cp.*, c.moneda
    FROM cronograma_pagos cp JOIN contratos c ON c.id = cp.contrato_id
    WHERE c.estado = 'activo'
  ),
  vencidas AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado' AND fecha_programada < hoy
  ),
  pendientes AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado'
  )
  SELECT jsonb_build_object(
    'generado_en', now(),
    'aum', (
      SELECT jsonb_object_agg(moneda, jsonb_build_object(
        'total', total,
        'captado_mes', captado_mes,
        'var_pct', CASE WHEN (total - captado_mes) > 0
                        THEN round((captado_mes / (total - captado_mes) * 100)::numeric, 1)
                        ELSE 0 END
      )) FROM aum
    ),
    'clientes', jsonb_build_object(
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos),
      'nuevos_mes', (SELECT COUNT(*) FROM perfiles WHERE rol='cliente' AND creado_en >= inicio_mes)
    ),
    'contratos', jsonb_build_object(
      'activos', (SELECT COUNT(*) FROM activos),
      'ticket_promedio', (
        SELECT COALESCE(jsonb_object_agg(moneda, prom),'{}'::jsonb) FROM (
          SELECT moneda, round(AVG(capital)::numeric,2) AS prom FROM activos GROUP BY moneda
        ) t
      )
    ),
    'cobranza', jsonb_build_object(
      'pct_al_dia', (
        SELECT CASE WHEN COUNT(*)=0 THEN 100
               ELSE round((COUNT(*) FILTER (WHERE estado='pagado' OR fecha_programada >= hoy)::numeric
                           / COUNT(*) * 100), 1) END
        FROM cuotas WHERE fecha_programada <= hoy
      ),
      'cuotas_vencidas', (SELECT COUNT(*) FROM vencidas),
      'monto_vencido', (
        SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
          SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto FROM vencidas GROUP BY moneda
        ) t
      )
    ),
    'intereses_pagados', (  -- ⚠️ retornos pagados
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT c.moneda, COALESCE(SUM(cp.monto_pagado),0) AS monto
        FROM cronograma_pagos cp JOIN contratos c ON c.id=cp.contrato_id
        WHERE cp.tipo='retorno' AND cp.estado='pagado'
        GROUP BY c.moneda
      ) t
    ),
    'caja_90d', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto
        FROM pendientes WHERE fecha_programada BETWEEN hoy AND (hoy + 90)
        GROUP BY moneda
      ) t
    ),
    'crecimiento', (  -- ⚠️ capital captado por mes, últimos 12 meses
      SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'mes', to_char(m, 'YYYY-MM'),
          'PEN', COALESCE((SELECT SUM(capital) FROM contratos
                           WHERE moneda='PEN' AND date_trunc('month',fecha_inicio)=m),0),
          'USD', COALESCE((SELECT SUM(capital) FROM contratos
                           WHERE moneda='USD' AND date_trunc('month',fecha_inicio)=m),0)
        ) AS row
        FROM generate_series(date_trunc('month', hoy) - interval '11 months',
                             date_trunc('month', hoy), interval '1 month') m
      ) s
    )
  ) INTO v;

  RETURN v;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.metricas_directorio() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.metricas_directorio() TO authenticated;
```
Aplicar con MCP `apply_migration`, name `directorio_rpc_metricas`.

- [ ] **Step 3: Probar que devuelve datos (como admin) y que el guard funciona**

Como tu usuario (admin/superadmin), vía MCP `execute_sql`:
```sql
SELECT public.metricas_directorio();
```
Expected: un JSON con `aum`, `clientes`, `contratos`, `cobranza`, `intereses_pagados`, `caja_90d`, `crecimiento` (12 entradas). Los números deben verse razonables contra la realidad.

- [ ] **Step 4: Commit del respaldo SQL**

```bash
git add "AUDITORIA DE PORTAL/directorio_2026-06-05.sql"
git commit -m "BD: RPC metricas_directorio (KPIs de cabecera)"
```

---

## Task 3: BD — RPCs de detalle (drill-down)

**Objetivo:** 3 funciones de solo lectura para los detalles: top clientes, morosidad, ranking de analistas. Mismo guard de rol.

**Files:** MCP `apply_migration` (name `directorio_rpc_detalle`). Respaldo en el `.sql`.

⚠️ **CONFIRMAR**: ranking por `asesor_perfil_id` (ver Notas #4).

- [ ] **Step 1: Mostrar el SQL a Miguel y, con OK, aplicar**

```sql
-- Top 10 clientes por capital activo
CREATE OR REPLACE FUNCTION public.directorio_top_clientes()
RETURNS TABLE(cliente_id uuid, nombre text, capital_pen numeric, capital_usd numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.id, p.nombre_completo,
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0),
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='USD'),0)
  FROM contratos c JOIN perfiles p ON p.id = c.cliente_id
  WHERE c.estado='activo'
  GROUP BY p.id, p.nombre_completo
  ORDER BY COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0) DESC
  LIMIT 10;
END; $$;

-- Cuotas vencidas (morosidad) con su cliente
CREATE OR REPLACE FUNCTION public.directorio_morosidad()
RETURNS TABLE(cliente text, numero_contrato text, numero_cuota int,
              fecha_programada date, monto numeric, moneda text, dias_vencida int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE hoy date := (now() AT TIME ZONE 'America/Lima')::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT p.nombre_completo, c.numero_contrato, cp.numero_cuota,
         cp.fecha_programada, cp.monto_programado, c.moneda,
         (hoy - cp.fecha_programada)::int
  FROM cronograma_pagos cp
  JOIN contratos c ON c.id = cp.contrato_id
  JOIN perfiles p ON p.id = c.cliente_id
  WHERE c.estado='activo' AND cp.estado <> 'pagado' AND cp.fecha_programada < hoy
  ORDER BY cp.fecha_programada ASC;
END; $$;

-- Ranking por analista (asesor del cliente)
CREATE OR REPLACE FUNCTION public.directorio_ranking_analistas()
RETURNS TABLE(analista_id uuid, nombre text, capital_pen numeric,
              capital_usd numeric, n_clientes bigint, n_contratos bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0),
         COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='USD'),0),
         COUNT(DISTINCT c.cliente_id), COUNT(c.id)
  FROM contratos c
  JOIN perfiles cli ON cli.id = c.cliente_id
  JOIN perfiles a ON a.id = cli.asesor_perfil_id
  WHERE c.estado='activo'
  GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(c.capital) FILTER (WHERE c.moneda='PEN'),0) DESC;
END; $$;

REVOKE EXECUTE ON FUNCTION public.directorio_top_clientes()       FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.directorio_morosidad()          FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.directorio_ranking_analistas()  FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.directorio_top_clientes()       TO authenticated;
GRANT  EXECUTE ON FUNCTION public.directorio_morosidad()          TO authenticated;
GRANT  EXECUTE ON FUNCTION public.directorio_ranking_analistas()  TO authenticated;
```
Aplicar con MCP `apply_migration`, name `directorio_rpc_detalle`.

- [ ] **Step 2: Probar las 3 RPC**

```sql
SELECT * FROM public.directorio_top_clientes();
SELECT * FROM public.directorio_morosidad();
SELECT * FROM public.directorio_ranking_analistas();
```
Expected: filas coherentes (top clientes ordenado desc; morosidad = cuotas vencidas reales; ranking por analista). Si no hay morosidad, 0 filas (no error).

- [ ] **Step 3: Commit del respaldo SQL**

```bash
git add "AUDITORIA DE PORTAL/directorio_2026-06-05.sql"
git commit -m "BD: RPCs de detalle del directorio (top clientes, morosidad, ranking)"
```

---

## Task 4: Edge `crear-admin` — aceptar rol `directorio` + clave temporal = DNI

**Objetivo:** Que el superadmin pueda crear un usuario `directorio` desde la UI; si no se envía password, usar el DNI como clave temporal (igual que `crear-cliente`).

**Files:**
- Modify: `_supabase_functions/functions/crear-admin/index.ts`

- [ ] **Step 1: Leer el archivo y ubicar las líneas a tocar**

Leer `_supabase_functions/functions/crear-admin/index.ts`. Localizar: validación del llamante (`["admin","superadmin"].includes`), lectura de `rol` del body, cálculo de `rolFinal`, validación de campos obligatorios (`if (!email || !password || ...)`), y el `createUser({ password })`.

- [ ] **Step 2: Permitir que sólo el superadmin cree `directorio`**

Modificar el bloque de cálculo de `rolFinal`. Localizar:
```typescript
  const esSuperadmin = perfilCaller.rol === "superadmin";
  if (!esSuperadmin && rol === "admin") {
    return json(cors, { error: "Un administrador solo puede crear analistas" }, 403);
  }
  const rolFinal = esSuperadmin
    ? (rol === "analista" ? "analista" : "admin")
    : "analista";
```
Reemplazar por:
```typescript
  const esSuperadmin = perfilCaller.rol === "superadmin";
  if (!esSuperadmin && (rol === "admin" || rol === "directorio")) {
    return json(cors, { error: "Solo el superadmin puede crear administradores o directorio" }, 403);
  }
  const rolFinal = esSuperadmin
    ? (rol === "analista" ? "analista"
       : rol === "directorio" ? "directorio"
       : "admin")
    : "analista";
```

- [ ] **Step 3: Clave temporal = DNI cuando no se envía password**

Localizar la validación de obligatorios (algo como):
```typescript
  if (!email || !password || !nombre_completo || !dni) {
```
Cambiar para que `password` ya NO sea obligatorio, pero el DNI sí:
```typescript
  if (!email || !nombre_completo || !dni) {
```
Y justo antes del `createUser`, calcular la clave final (espejo de `crear-cliente`):
```typescript
  // Clave temporal = DNI (8 dígitos, ceros a la izquierda) si no se envió password.
  const dniLimpio = String(dni).replace(/\D/g, "");
  let passwordFinal: string;
  if (password) {
    if (String(password).length < 8) {
      return json(cors, { error: "La contraseña debe tener al menos 8 caracteres" }, 400);
    }
    passwordFinal = String(password);
  } else {
    passwordFinal = dniLimpio.padStart(8, "0");
  }
```
Y en el `createUser`, usar `passwordFinal`:
```typescript
  const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
    email: emailNorm,
    password: passwordFinal,   // antes: password
    email_confirm: true,
    user_metadata: { nombre: nombre_completo },
  });
```

- [ ] **Step 4: Desplegar la edge vía MCP**

Usar MCP `deploy_edge_function` con el contenido actualizado de `crear-admin`. Expected: deploy OK.

- [ ] **Step 5: Verificar el guard (sin crear data real todavía)**

Probar que un admin normal NO puede crear directorio: desde una sesión admin (o simulando), invocar `crear-admin` con `rol:'directorio'` → Expected: 403 "Solo el superadmin...". (La creación real de Kirk/Carlos se hace en la Tarea 10.)

- [ ] **Step 6: Commit**

```bash
git add _supabase_functions/functions/crear-admin/index.ts
git commit -m "Edge crear-admin: acepta rol directorio (solo superadmin) + clave temporal DNI"
```

---

## Task 5: `auth.js` — enrutado del rol `directorio`

**Objetivo:** Que el login y la verificación de sesión manden al `directorio` a su pantalla y bloqueen el resto.

**Files:**
- Modify: `public_html/js/auth.js`

- [ ] **Step 1: Agregar `verificarDirectorio()` (clon de `verificarAnalista`)**

Justo debajo de la función `verificarAnalista()` (termina ~L282), añadir:
```javascript
export async function verificarDirectorio() {
  protegerBfcache(verificarDirectorio)
  const session = await verificarSesion()
  if (!session) return

  try {
    const { data: perfil, error } = await supabase
      .from('perfiles')
      .select('rol, activo')
      .eq('id', session.user.id)
      .single()

    if (error || !perfil) {
      window.location.replace('/index.html')
      return
    }

    if (!perfil.activo) {
      try { await supabase.auth.signOut({ scope: 'global' }) } catch {}
      window.location.replace('/index.html')
      return
    }

    if (perfil.rol !== 'directorio') {
      if (perfil.rol === 'admin' || perfil.rol === 'superadmin') {
        window.location.replace('/admin/dashboard.html')
      } else if (perfil.rol === 'analista') {
        window.location.replace('/admin/analista.html')
      } else {
        window.location.replace('/dashboard.html')
      }
      return
    }

    return perfil
  } catch (error) {
    console.error('Error al verificar rol de directorio:', error)
    window.location.replace('/index.html')
  }
}
```

- [ ] **Step 2: Rama en `login()`**

En `login()`, localizar:
```javascript
    } else if (perfil.rol === 'analista') {
      // El analista tiene su propio espacio acotado (alta de clientes + contratos).
      window.location.replace('/admin/analista.html')
    } else if (perfil.rol === 'admin' || perfil.rol === 'superadmin') {
```
Insertar **antes** de la rama `admin`:
```javascript
    } else if (perfil.rol === 'directorio') {
      window.location.replace('/admin/directorio.html')
```

- [ ] **Step 3: Rama en `redirigirSiAutenticado()`**

Localizar la rama `analista` dentro de `redirigirSiAutenticado()`:
```javascript
        } else if (perfil.rol === 'analista') {
          window.__dismissSplash?.()
          window.location.replace('/admin/analista.html')
        } else if (perfil.rol === 'admin' || perfil.rol === 'superadmin') {
```
Insertar **antes** de la rama `admin`:
```javascript
        } else if (perfil.rol === 'directorio') {
          window.__dismissSplash?.()
          window.location.replace('/admin/directorio.html')
```

- [ ] **Step 4: Verificación visual (después de tener la página, Tarea 7)**

Por ahora solo revisar que el archivo no tenga errores de sintaxis:
Run: `node --check public_html/js/auth.js`
Expected: sin salida (OK).

- [ ] **Step 5: Commit**

```bash
git add public_html/js/auth.js
git commit -m "auth.js: enrutar rol directorio a /admin/directorio.html"
```

---

## Task 6: UI de equipo — opción "Directorio"

**Objetivo:** Que en `/admin/equipo` el superadmin pueda elegir tipo "Directorio" y se vea su badge.

**Files:**
- Modify: `public_html/admin/equipo.html`
- Modify: `public_html/js/admin/equipo.js`

- [ ] **Step 1: Agregar la opción al selector (solo tiene sentido para superadmin)**

En `equipo.html`, localizar el `<select id="a_rol">` con las opciones admin/analista. Añadir, después de la opción `analista`:
```html
    <option value="directorio">Directorio — panel ejecutivo de solo lectura (dueños)</option>
```
Y actualizar el texto de ayuda debajo para mencionar: "El **directorio** solo ve los números del negocio; no crea ni edita nada."

- [ ] **Step 2: Incluir `directorio` en el payload de `crearAdmin()`**

En `equipo.js`, localizar:
```javascript
    rol:             !ES_SUPERADMIN ? 'analista'
                       : (document.getElementById('a_rol')?.value === 'analista' ? 'analista' : 'admin')
```
Reemplazar por (respeta los 3 tipos que puede crear el superadmin):
```javascript
    rol:             !ES_SUPERADMIN ? 'analista'
                       : (document.getElementById('a_rol')?.value || 'admin')
```
> Nota: la edge revalida en el servidor que solo el superadmin cree `directorio`/`admin`, así que confiar en el `value` del select es seguro (el server manda).

- [ ] **Step 3: Password opcional cuando el tipo es `directorio`**

Localizar la validación de password en `crearAdmin()` (antes de invocar la edge). Hacer que, si el tipo es `directorio` (o `analista`) y el campo password está vacío, se envíe sin password (la edge pondrá DNI). Si tu validación actual exige password siempre, envolverla:
```javascript
  const tipoSel = document.getElementById('a_rol')?.value
  const permiteClaveTemporal = (tipoSel === 'directorio' || tipoSel === 'analista')
  if (!payload.password && !permiteClaveTemporal) {
    // ...mostrar error "ingresa una contraseña"...
    return
  }
  if (!payload.password) delete payload.password  // la edge usará el DNI
```

- [ ] **Step 4: Badge del rol en la tabla "Equipo del sistema"**

En `equipo.js`, localizar el render del badge:
```javascript
  const badgeRol = a.rol === 'superadmin'
    ? `<span class="badge badge-new" ...>SUPER</span>`
    : a.rol === 'analista'
      ? `<span class="badge badge-renovado" ...>ANALISTA</span>`
      : ''
```
Reemplazar la cadena por una que también contemple `directorio`:
```javascript
  const badgeRol = a.rol === 'superadmin'
    ? `<span class="badge badge-new" style="margin-left:6px; font-size:9.5px; letter-spacing:0.04em;">SUPER</span>`
    : a.rol === 'directorio'
      ? `<span class="badge badge-info" style="margin-left:6px; font-size:9.5px; letter-spacing:0.04em;">DIRECTORIO</span>`
      : a.rol === 'analista'
        ? `<span class="badge badge-renovado" style="margin-left:6px; font-size:9.5px; letter-spacing:0.04em;">ANALISTA</span>`
        : ''
```
> Si no existe la clase `badge-info` en `css/admin.css`, usar una existente (p. ej. `badge-renovado`) o agregar `.badge-info{background:#1d4ed8;color:#fff}` en `css/admin.css` y subir su `?v=`.

- [ ] **Step 5: Subir versiones y check de sintaxis**

En `equipo.html`, subir el `?v=N` de `equipo.js` (y de `admin.css` si se tocó). Luego:
Run: `node --check public_html/js/admin/equipo.js`
Expected: OK.

- [ ] **Step 6: Commit**

```bash
git add public_html/admin/equipo.html public_html/js/admin/equipo.js public_html/css/admin.css
git commit -m "Equipo: alta de usuario tipo Directorio (badge + clave temporal)"
```

---

## Task 7: Pantalla `/admin/directorio.html` (shell + contenedores cockpit)

**Objetivo:** El HTML de la pantalla, siguiendo el `<head>` del patrón `analista.html` (CSS/JS versionados, guard inline, sin nav), con los contenedores que llenará el JS y el menú de cuenta con "Cambiar contraseña".

**Files:**
- Create: `public_html/admin/directorio.html`

- [ ] **Step 1: Crear el archivo**

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <script src="/js/no-zoom.js?v=4" defer></script>
  <meta name="format-detection" content="telephone=no, email=no, address=no">
  <script>
  (function(){try{var has=function(s){for(var i=0;i<s.length;i++){var k=s.key(i);if(k&&(k.indexOf("sb-")===0||k.indexOf("supabase.")===0))return true;}return false;};if(!has(localStorage)&&!has(sessionStorage))location.replace("/index.html");}catch(e){}})();
  </script>
  <meta name="apple-mobile-web-app-capable" content="yes">
  <title>Directorio · Portal AvanceCorp</title>
  <meta name="description" content="Panel ejecutivo — Avance Corp.">
  <meta name="robots" content="noindex, nofollow">
  <link rel="icon" type="image/png" sizes="32x32" href="/img/favicon-32.png?v=1">
  <link rel="apple-touch-icon" sizes="180x180" href="/img/apple-touch-icon.png?v=1">
  <link rel="manifest" href="/manifest.json?v=5">
  <meta name="theme-color" content="#070b11">
  <meta name="apple-mobile-web-app-title" content="AvanceCorp">
  <link rel="preconnect" href="https://dctqcbznekcyxhjujuci.supabase.co">
  <link rel="preconnect" href="https://esm.sh" crossorigin>
  <link rel="stylesheet" href="/css/main.css?v=13">
  <link rel="stylesheet" href="/css/admin.css?v=17">
  <link rel="stylesheet" href="/css/directorio.css?v=1">
</head>
<body class="dir-body">
  <a class="skip-link" href="#main">Saltar al contenido</a>
  <div class="dir-app">
    <!-- Barra superior -->
    <header class="dir-topbar">
      <div class="dir-brand">Avance Corp · <span>Directorio</span></div>
      <div class="dir-top-right">
        <span class="dir-fresh" id="dirFresh">Cargando…</span>
        <button class="dir-btn" id="btnRefrescar" type="button" aria-label="Actualizar">↻</button>
        <div class="dir-account">
          <button class="dir-avatar" id="btnCuenta" type="button"><span id="dirIniciales">··</span></button>
          <div class="dir-menu hidden" id="menuCuenta">
            <div class="dir-menu-name" id="dirNombre">—</div>
            <button class="dir-menu-item" id="btnCambiarPwd" type="button">Cambiar contraseña</button>
            <button class="dir-menu-item danger" id="btnSalir" type="button">Cerrar sesión</button>
          </div>
        </div>
      </div>
    </header>

    <main id="main" class="dir-main">
      <!-- Fila de KPIs -->
      <section class="dir-kpis" id="kpis" aria-label="Indicadores">
        <div class="dir-kpi skeleton" data-kpi="aum-pen"  data-drill="">      <div class="k-l">AUM Soles</div><div class="k-v" id="kAumPen">—</div><div class="k-u" id="kAumPenVar"></div></div>
        <div class="dir-kpi skeleton" data-kpi="aum-usd"  data-drill="">      <div class="k-l">AUM Dólares</div><div class="k-v" id="kAumUsd">—</div><div class="k-u" id="kAumUsdVar"></div></div>
        <div class="dir-kpi skeleton" data-kpi="clientes" data-drill="topclientes"><div class="k-l">Clientes activos</div><div class="k-v" id="kClientes">—</div><div class="k-u" id="kClientesNuevos"></div></div>
        <div class="dir-kpi skeleton" data-kpi="contratos" data-drill="">     <div class="k-l">Contratos activos</div><div class="k-v" id="kContratos">—</div><div class="k-u" id="kTicket"></div></div>
        <div class="dir-kpi skeleton" data-kpi="cobranza" data-drill="morosidad"><div class="k-l">Cobranza al día</div><div class="k-v" id="kCobranza">—</div><div class="k-u" id="kVencidas"></div></div>
        <div class="dir-kpi skeleton" data-kpi="caja"     data-drill="">      <div class="k-l">Caja · 90 días</div><div class="k-v" id="kCaja">—</div><div class="k-u">a pagar a clientes</div></div>
      </section>

      <div class="dir-mid">
        <!-- Gráfico hero + intereses -->
        <section class="dir-panel">
          <div class="dir-panel-h"><span>Crecimiento de capital · 12 meses</span><span id="crecTotal"></span></div>
          <div id="chartCrecimiento" class="dir-chart"></div>
          <div class="dir-panel-h" style="margin-top:14px"><span>Intereses pagados a clientes</span><span id="interesesTotal"></span></div>
          <div id="chartIntereses" class="dir-bars"></div>
        </section>

        <!-- Ranking + Top clientes -->
        <section class="dir-panel">
          <div class="dir-panel-h"><span>Ranking por analista</span><button class="dir-link" data-drill="ranking">ver todo →</button></div>
          <div id="rankingAnalistas" class="dir-rank"></div>
          <div class="dir-panel-h" style="margin-top:14px"><span>Top clientes por capital</span><button class="dir-link" data-drill="topclientes">ver 10 →</button></div>
          <div id="topClientes" class="dir-rank"></div>
        </section>
      </div>
    </main>
  </div>

  <!-- Modal de drill-down (lo llena el JS) -->
  <div class="dir-modal hidden" id="dirModal">
    <div class="dir-modal-card">
      <div class="dir-modal-h"><span id="modalTitulo">Detalle</span><button class="dir-modal-x" id="modalCerrar">✕</button></div>
      <div class="dir-modal-body" id="modalBody"></div>
    </div>
  </div>

  <!-- Modal cambiar contraseña -->
  <div class="dir-modal hidden" id="pwdModal">
    <div class="dir-modal-card">
      <div class="dir-modal-h"><span>Cambiar contraseña</span><button class="dir-modal-x" id="pwdCerrar">✕</button></div>
      <form class="dir-modal-body" id="pwdForm">
        <input class="dir-input" type="password" id="pwdNueva" placeholder="Nueva contraseña" autocomplete="new-password">
        <input class="dir-input" type="password" id="pwdConfirma" placeholder="Confirmar contraseña" autocomplete="new-password">
        <p class="dir-err hidden" id="pwdError"></p>
        <p class="dir-ok hidden" id="pwdOk"></p>
        <button class="dir-btn-primary" type="submit" id="pwdGuardar">Guardar</button>
      </form>
    </div>
  </div>

  <script type="module" src="/js/admin/directorio.js?v=1"></script>
</body>
</html>
```

- [ ] **Step 2: Verificar que abre (redirige sin sesión)**

Abrir `http://localhost/admin/directorio.html` sin sesión → Expected: el guard inline redirige a `/index.html`.

- [ ] **Step 3: Commit**

```bash
git add public_html/admin/directorio.html
git commit -m "Pantalla directorio.html (shell cockpit + modales)"
```

---

## Task 8: `js/admin/directorio.js` — lógica del cockpit

**Objetivo:** Cargar métricas vía RPC, pintar KPIs, gráfico de crecimiento (SVG), barras de intereses, ranking y top clientes, drill-down y cambiar contraseña.

**Files:**
- Create: `public_html/js/admin/directorio.js`

- [ ] **Step 1: Crear el archivo completo**

```javascript
import { supabase } from '../supabase.js'
import { verificarDirectorio, logout } from '../auth.js'
import { setupAdminShell, formatearMoneda, setText, iniciales } from './_helpers.js'

let DATA = null

/* ---------- helpers de formato ---------- */
const money = (n, m) => formatearMoneda(Number(n || 0), m)
const pct = (n) => `${Number(n || 0).toFixed(1)}%`

/* ---------- carga de métricas ---------- */
async function cargarMetricas () {
  const { data, error } = await supabase.rpc('metricas_directorio')
  if (error) throw error
  return data
}

/* ---------- render KPIs ---------- */
function pintarKpis (d) {
  const aumPen = d.aum?.PEN || { total: 0, var_pct: 0 }
  const aumUsd = d.aum?.USD || { total: 0, var_pct: 0 }
  setText('kAumPen', money(aumPen.total, 'PEN'))
  setText('kAumPenVar', `▲ ${pct(aumPen.var_pct)} mes`)
  setText('kAumUsd', money(aumUsd.total, 'USD'))
  setText('kAumUsdVar', `▲ ${pct(aumUsd.var_pct)} mes`)

  setText('kClientes', d.clientes?.activos ?? 0)
  setText('kClientesNuevos', `▲ ${d.clientes?.nuevos_mes ?? 0} nuevos`)

  setText('kContratos', d.contratos?.activos ?? 0)
  const tk = d.contratos?.ticket_promedio?.PEN
  setText('kTicket', tk ? `tkt ${money(tk, 'PEN')}` : '')

  setText('kCobranza', pct(d.cobranza?.pct_al_dia))
  const venc = d.cobranza?.cuotas_vencidas ?? 0
  setText('kVencidas', venc ? `${venc} vencidas` : 'sin vencidas')

  const cajaPen = d.caja_90d?.PEN || 0
  setText('kCaja', money(cajaPen, 'PEN'))

  document.querySelectorAll('.dir-kpi.skeleton').forEach(el => el.classList.remove('skeleton'))
}

/* ---------- gráfico de crecimiento (línea SVG, acumulado) ---------- */
function pintarCrecimiento (serie) {
  const cont = document.getElementById('chartCrecimiento')
  if (!serie?.length) { cont.innerHTML = '<p class="dir-empty">Sin datos</p>'; return }
  let acc = 0
  const pts = serie.map(s => { acc += Number(s.PEN || 0); return acc })
  const max = Math.max(...pts, 1)
  const W = 520, H = 140
  const coords = pts.map((v, i) => {
    const x = (i / (pts.length - 1)) * W
    const y = H - (v / max) * (H - 12) - 6
    return [x, y]
  })
  const line = coords.map((c, i) => `${i ? 'L' : 'M'}${c[0].toFixed(1)},${c[1].toFixed(1)}`).join(' ')
  const area = `${line} L${W},${H} L0,${H} Z`
  cont.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" class="dir-svg">
      <defs><linearGradient id="gC" x1="0" x2="0" y1="0" y2="1">
        <stop offset="0" stop-color="#3b82f6" stop-opacity=".5"/>
        <stop offset="1" stop-color="#3b82f6" stop-opacity="0"/></linearGradient></defs>
      <path d="${area}" fill="url(#gC)"/>
      <path d="${line}" fill="none" stroke="#60a5fa" stroke-width="2.5"/>
    </svg>`
  setText('crecTotal', `+ ${money(acc, 'PEN')}`)
}

/* ---------- barras de intereses pagados ---------- */
function pintarIntereses (d) {
  const totalPen = d.intereses_pagados?.PEN || 0
  setText('interesesTotal', money(totalPen, 'PEN'))
  // Barra simple proporcional a la serie de crecimiento (visual); el número real es el total.
  const cont = document.getElementById('chartIntereses')
  const serie = d.crecimiento || []
  const max = Math.max(...serie.map(s => Number(s.PEN || 0)), 1)
  cont.innerHTML = serie.map(s => {
    const h = Math.round((Number(s.PEN || 0) / max) * 100)
    return `<span style="height:${Math.max(h, 4)}%" title="${s.mes}"></span>`
  }).join('')
}

/* ---------- ranking + top clientes (resumen, top 3) ---------- */
async function pintarListas () {
  const [{ data: rank }, { data: top }] = await Promise.all([
    supabase.rpc('directorio_ranking_analistas'),
    supabase.rpc('directorio_top_clientes')
  ])
  const rk = document.getElementById('rankingAnalistas')
  rk.innerHTML = (rank || []).slice(0, 3).map(r => `
    <div class="dir-li"><span class="dir-nm"><span class="dir-av">${iniciales(r.nombre)}</span>${r.nombre}</span>
    <span class="dir-amt">${money(r.capital_pen, 'PEN')}</span></div>`).join('') || '<p class="dir-empty">Sin datos</p>'

  const tc = document.getElementById('topClientes')
  tc.innerHTML = (top || []).slice(0, 3).map((c, i) => `
    <div class="dir-li"><span class="dir-nm"><span class="dir-av ok">${i + 1}</span>${c.nombre}</span>
    <span class="dir-amt">${money(c.capital_pen, 'PEN')}</span></div>`).join('') || '<p class="dir-empty">Sin datos</p>'
}

/* ---------- drill-down ---------- */
async function abrirDrill (tipo) {
  const modal = document.getElementById('dirModal')
  const body = document.getElementById('modalBody')
  const titulo = document.getElementById('modalTitulo')
  body.innerHTML = '<p class="dir-empty">Cargando…</p>'
  modal.classList.remove('hidden')

  try {
    if (tipo === 'topclientes') {
      titulo.textContent = 'Top clientes por capital'
      const { data } = await supabase.rpc('directorio_top_clientes')
      body.innerHTML = tabla(data, ['nombre', 'capital_pen', 'capital_usd'],
        ['Cliente', 'Capital S/', 'Capital US$'], ['', 'PEN', 'USD'])
    } else if (tipo === 'morosidad') {
      titulo.textContent = 'Cuotas vencidas (morosidad)'
      const { data } = await supabase.rpc('directorio_morosidad')
      body.innerHTML = tabla(data,
        ['cliente', 'numero_contrato', 'numero_cuota', 'fecha_programada', 'monto', 'dias_vencida'],
        ['Cliente', 'Contrato', 'Cuota', 'Vencía', 'Monto', 'Días'],
        ['', '', '', '', 'mon', ''])
    } else if (tipo === 'ranking') {
      titulo.textContent = 'Ranking por analista'
      const { data } = await supabase.rpc('directorio_ranking_analistas')
      body.innerHTML = tabla(data,
        ['nombre', 'capital_pen', 'capital_usd', 'n_clientes', 'n_contratos'],
        ['Analista', 'Capital S/', 'Capital US$', 'Clientes', 'Contratos'],
        ['', 'PEN', 'USD', '', ''])
    }
  } catch (e) {
    body.innerHTML = `<p class="dir-err">No se pudo cargar: ${e.message}</p>`
  }
}

function tabla (filas, cols, headers, fmt) {
  if (!filas?.length) return '<p class="dir-empty">Sin registros</p>'
  const th = headers.map(h => `<th>${h}</th>`).join('')
  const rows = filas.map(f => '<tr>' + cols.map((c, i) => {
    let v = f[c]
    if (fmt[i] === 'PEN') v = money(v, 'PEN')
    else if (fmt[i] === 'USD') v = money(v, 'USD')
    else if (fmt[i] === 'mon') v = money(v, f.moneda || 'PEN')
    return `<td>${v ?? ''}</td>`
  }).join('') + '</tr>').join('')
  return `<table class="dir-table"><thead><tr>${th}</tr></thead><tbody>${rows}</tbody></table>`
}

/* ---------- cambiar contraseña ---------- */
function validarPwd (pwd) {
  if (pwd.length < 8) return 'La contraseña debe tener al menos 8 caracteres.'
  if (!/[a-z]/.test(pwd)) return 'Incluye al menos una letra minúscula.'
  if (!/[A-Z]/.test(pwd)) return 'Incluye al menos una letra mayúscula.'
  if (!/[0-9]/.test(pwd)) return 'Incluye al menos un número.'
  return null
}

async function guardarPwd (e) {
  e.preventDefault()
  const err = document.getElementById('pwdError')
  const ok = document.getElementById('pwdOk')
  err.classList.add('hidden'); ok.classList.add('hidden')
  const p1 = document.getElementById('pwdNueva').value
  const p2 = document.getElementById('pwdConfirma').value
  const e1 = validarPwd(p1)
  if (e1) { err.textContent = e1; err.classList.remove('hidden'); return }
  if (p1 !== p2) { err.textContent = 'Las contraseñas no coinciden.'; err.classList.remove('hidden'); return }
  const btn = document.getElementById('pwdGuardar'); btn.disabled = true
  const { error } = await supabase.auth.updateUser({ password: p1 })
  btn.disabled = false
  if (error) { err.textContent = error.message || 'No se pudo actualizar.'; err.classList.remove('hidden'); return }
  ok.textContent = 'Contraseña actualizada ✅'; ok.classList.remove('hidden')
  document.getElementById('pwdForm').reset()
}

/* ---------- frescura ---------- */
function pintarFresh (d) {
  const t = d?.generado_en ? new Date(d.generado_en) : new Date()
  setText('dirFresh', 'Actualizado ' + t.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' }))
}

/* ---------- recarga total ---------- */
async function recargar () {
  DATA = await cargarMetricas()
  pintarKpis(DATA)
  pintarCrecimiento(DATA.crecimiento)
  pintarIntereses(DATA)
  pintarFresh(DATA)
  await pintarListas()
}

/* ---------- eventos ---------- */
function bind () {
  document.getElementById('btnRefrescar').addEventListener('click', () => recargar().catch(console.error))
  document.getElementById('btnSalir').addEventListener('click', logout)
  document.getElementById('btnCuenta').addEventListener('click', () =>
    document.getElementById('menuCuenta').classList.toggle('hidden'))
  document.getElementById('btnCambiarPwd').addEventListener('click', () => {
    document.getElementById('menuCuenta').classList.add('hidden')
    document.getElementById('pwdModal').classList.remove('hidden')
  })
  document.getElementById('pwdCerrar').addEventListener('click', () =>
    document.getElementById('pwdModal').classList.add('hidden'))
  document.getElementById('pwdForm').addEventListener('submit', guardarPwd)
  document.getElementById('modalCerrar').addEventListener('click', () =>
    document.getElementById('dirModal').classList.add('hidden'))
  // drill-down: cualquier elemento con data-drill no vacío
  document.body.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-drill]')
    if (el && el.getAttribute('data-drill')) abrirDrill(el.getAttribute('data-drill'))
  })
}

/* ---------- arranque ---------- */
;(async () => {
  const perfil = await verificarDirectorio()
  if (!perfil) return
  await setupAdminShell({ welcomeFirstName: false })
  setText('dirNombre', perfil.nombre_completo || 'Directorio')
  setText('dirIniciales', iniciales(perfil.nombre_completo || 'D'))
  bind()
  try { await recargar() } catch (e) {
    console.error(e)
    setText('dirFresh', 'Error al cargar')
  }
})()
```
> Nota: `setupAdminShell()` puede pelear con el header propio del cockpit (está pensado para el shell admin con avatar `#userAvatar`, etc.). Si rompe el layout, llamarlo es opcional aquí — el cockpit ya trae su propia barra. En ese caso, sustituir su uso por leer el perfil directamente. Validar visualmente en el Step 2 y ajustar.

- [ ] **Step 2: Check de sintaxis**

Run: `node --check public_html/js/admin/directorio.js`
Expected: OK.

- [ ] **Step 3: Commit**

```bash
git add public_html/js/admin/directorio.js
git commit -m "directorio.js: carga de métricas, gráficos, drill-down y cambio de clave"
```

---

## Task 9: `css/directorio.css` — estilo cockpit oscuro

**Objetivo:** Los estilos del panel oscuro, responsive. (Tomar como referencia el mockup `.superpowers/brainstorm/<sesión>/content/cockpit-full.html`.)

**Files:**
- Create: `public_html/css/directorio.css`

- [ ] **Step 1: Crear el archivo**

```css
.dir-body{background:radial-gradient(130% 130% at 0% 0%,#0d1b2a,#070b11);color:#e8eef6;min-height:100vh;margin:0}
.dir-app{max-width:1200px;margin:0 auto;padding:16px}
.dir-topbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}
.dir-brand{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:#cfe0f5}
.dir-brand span{color:#60a5fa}
.dir-top-right{display:flex;align-items:center;gap:10px}
.dir-fresh{font-size:11px;color:#8aa0b8}
.dir-btn{background:#101d2e;border:1px solid #1c3047;color:#cfe0f5;border-radius:8px;width:32px;height:32px;cursor:pointer}
.dir-account{position:relative}
.dir-avatar{width:32px;height:32px;border-radius:50%;background:#1d4ed8;color:#fff;border:0;font-size:11px;font-weight:700;cursor:pointer}
.dir-menu{position:absolute;right:0;top:38px;background:#0f1722;border:1px solid #1e2c3d;border-radius:10px;padding:8px;min-width:180px;z-index:20}
.dir-menu-name{font-size:12px;color:#8aa0b8;padding:6px 8px;border-bottom:1px solid #1e2c3d;margin-bottom:4px}
.dir-menu-item{display:block;width:100%;text-align:left;background:none;border:0;color:#dbe6f3;padding:8px;border-radius:6px;cursor:pointer;font-size:13px}
.dir-menu-item:hover{background:#162338}
.dir-menu-item.danger{color:#f87171}

.dir-kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:10px;margin-bottom:14px}
.dir-kpi{background:#101d2e;border:1px solid #1c3047;border-radius:12px;padding:11px 12px;cursor:default;transition:.15s}
.dir-kpi[data-drill]:not([data-drill=""]){cursor:pointer}
.dir-kpi[data-drill]:not([data-drill=""]):hover{border-color:#3b82f6;transform:translateY(-2px)}
.dir-kpi .k-l{font-size:9px;color:#6f8aa8;text-transform:uppercase;letter-spacing:.04em}
.dir-kpi .k-v{font-size:18px;color:#eaf2fb;font-weight:700;margin-top:5px;line-height:1.05}
.dir-kpi .k-u{font-size:9px;color:#22c55e;margin-top:4px}

.dir-mid{display:grid;grid-template-columns:1.6fr 1fr;gap:12px}
.dir-panel{background:#0c1826;border:1px solid #1c3047;border-radius:12px;padding:13px}
.dir-panel-h{display:flex;justify-content:space-between;align-items:center;font-size:10px;color:#6f8aa8;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px}
.dir-panel-h span:last-child{color:#dbe6f3}
.dir-link{background:none;border:0;color:#60a5fa;cursor:pointer;font-size:10px}
.dir-chart .dir-svg{width:100%;height:140px;display:block}
.dir-bars{display:flex;align-items:flex-end;gap:5px;height:50px;margin-top:6px}
.dir-bars span{flex:1;background:linear-gradient(#3b82f6,#1d4ed8);border-radius:3px 3px 0 0;opacity:.85}
.dir-rank{display:flex;flex-direction:column;gap:8px}
.dir-li{display:flex;align-items:center;justify-content:space-between;font-size:12px;color:#dbe6f3}
.dir-nm{display:flex;align-items:center;gap:7px}
.dir-av{width:20px;height:20px;border-radius:50%;background:#1d4ed8;color:#fff;font-size:9px;display:flex;align-items:center;justify-content:center;font-weight:700}
.dir-av.ok{background:#0f9d58}
.dir-amt{color:#9fb4cc;font-weight:600}
.dir-empty{color:#6f8aa8;font-size:12px;text-align:center;padding:10px}

.dir-modal{position:fixed;inset:0;background:rgba(3,7,12,.7);display:flex;align-items:center;justify-content:center;z-index:50;padding:16px}
.dir-modal.hidden,.hidden{display:none}
.dir-modal-card{background:#0f1722;border:1px solid #1e2c3d;border-radius:14px;width:min(640px,100%);max-height:85vh;overflow:auto}
.dir-modal-h{display:flex;justify-content:space-between;align-items:center;padding:14px 16px;border-bottom:1px solid #1e2c3d;font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:#cfe0f5}
.dir-modal-x{background:none;border:0;color:#8aa0b8;font-size:16px;cursor:pointer}
.dir-modal-body{padding:14px 16px}
.dir-table{width:100%;border-collapse:collapse;font-size:12px}
.dir-table th{text-align:left;color:#6f8aa8;text-transform:uppercase;font-size:9px;padding:6px 8px;border-bottom:1px solid #1e2c3d}
.dir-table td{padding:7px 8px;border-bottom:1px solid #131f30;color:#dbe6f3}
.dir-input{width:100%;background:#0c1826;border:1px solid #1c3047;border-radius:8px;padding:10px;color:#eaf2fb;margin-bottom:10px}
.dir-btn-primary{background:#1d4ed8;border:0;color:#fff;border-radius:8px;padding:10px 16px;cursor:pointer;font-weight:600}
.dir-err{color:#f87171;font-size:12px}
.dir-ok{color:#22c55e;font-size:12px}

@media(max-width:820px){
  .dir-kpis{grid-template-columns:repeat(2,1fr)}
  .dir-mid{grid-template-columns:1fr}
}
```

- [ ] **Step 2: Commit**

```bash
git add public_html/css/directorio.css
git commit -m "css/directorio.css: estilo cockpit oscuro responsive"
```

---

## Task 10: Verificación integral contra la BD real (patrón rol analista)

**Objetivo:** Probar de punta a punta con un usuario `directorio` de prueba, exactamente como se validó el rol analista. Crear y **eliminar** el usuario de prueba al final.

**Files:** ninguno (pruebas).

- [ ] **Step 1: Crear un directorio de prueba**

Desde tu sesión superadmin, en `/admin/equipo` → "+ Nuevo miembro del equipo" → tipo **Directorio**, con un DNI de prueba y sin escribir contraseña. Expected: se crea; aparece con badge **DIRECTORIO**.

- [ ] **Step 2: Login del directorio de prueba (clave = DNI)**

Cerrar sesión, entrar con el correo del directorio de prueba y password = su DNI (8 dígitos). Expected: cae directo en `/admin/directorio.html` con los números cargados. Capturar pantalla para Miguel.

- [ ] **Step 3: Probar que NO puede escribir nada (lo crítico)**

Con el `user id` del directorio de prueba, vía MCP `execute_sql` impersonando el rol (o probando las policies), confirmar que falla cualquier escritura. Como verificación directa, revisar que NO existe ninguna policy de INSERT/UPDATE/DELETE que nombre a directorio:
```sql
SELECT polname, cmd, qual, with_check
FROM pg_policies WHERE schemaname='public'
  AND (qual ILIKE '%directorio%' OR with_check ILIKE '%directorio%');
```
Expected: **0 filas** (el rol no aparece en ninguna policy → no puede escribir ni leer tablas directamente). El único acceso es vía las RPC y el self-read de `perfiles`.

- [ ] **Step 4: Probar el guard de las RPC con un rol NO autorizado**

Con un usuario `cliente` de prueba (o el JWT de un cliente), invocar `metricas_directorio()`. Expected: error "No autorizado" (42501). Repetir con `directorio_morosidad()`.

- [ ] **Step 5: Probar drill-down y cambio de contraseña**

En el navegador como el directorio de prueba: clic en "Cobranza" → abre morosidad; clic en "Clientes"/"ver 10" → top clientes; "ver todo" → ranking. Luego menú de cuenta → "Cambiar contraseña" → poner una clave válida (mín 8, may/min/número) → Expected: "actualizada ✅". Cerrar sesión y volver a entrar con la **nueva** clave. Expected: entra.

- [ ] **Step 6: Re-confirmar que sigue sin poder escribir tras cambiar clave**

Repetir el query del Step 3 → Expected: sigue en 0 filas (cambiar su propia clave no le dio permisos de negocio).

- [ ] **Step 7: Correr advisors de seguridad**

MCP `get_advisors` (type security). Expected: sin hallazgos nuevos atribuibles a las funciones/rol directorio.

- [ ] **Step 8: Eliminar el directorio de prueba**

Desde `/admin/equipo`, desactivar y/o eliminar el usuario de prueba (o vía edge `eliminar-cliente`/MCP). Expected: queda limpio.

---

## Task 11: Deploy, documentación y grafo

**Objetivo:** Dejar todo desplegado y documentado.

**Files:**
- Modify: `public_html/CLAUDE.md`
- Create: `BASE DE CONOCIMINETO/AVANCECORP/Rol Directorio.md`
- Modify: `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md` (enlazar la nota nueva)

- [ ] **Step 1: Deploy manual a Hostinger**

Copiar a la carpeta espejo de Hostinger los archivos nuevos/editados: `admin/directorio.html`, `js/admin/directorio.js`, `css/directorio.css`, `js/auth.js`, `admin/equipo.html`, `js/admin/equipo.js` (y `css/admin.css` si se tocó). Verificar que los `?v=N` editados quedaron subidos. Las edge ya se desplegaron en la Tarea 4.

- [ ] **Step 2: Documentar en `public_html/CLAUDE.md`**

Agregar el rol `directorio` a la lista de roles (§ esquema), las RPCs nuevas (`metricas_directorio`, `directorio_top_clientes`, `directorio_morosidad`, `directorio_ranking_analistas`), el helper `es_directorio()`, la pantalla `/admin/directorio.html`, y la nota de que crear `directorio` exige `es_superadmin()`.

- [ ] **Step 3: Nota del vault**

Crear `BASE DE CONOCIMINETO/AVANCECORP/Rol Directorio.md` (con frontmatter de tags, igual que `Rol Analista.md`): qué es, qué ve, que es solo lectura vía RPC, cómo se crea, las 3 definiciones de negocio confirmadas, cómo se verificó. Enlazar `[[Rol Analista]]`, `[[Arquitectura del portal]]`, `[[Clave temporal = DNI]]`. Añadir el enlace `[[Rol Directorio]]` en la lista de features de `Inicio.md`.

- [ ] **Step 4: Actualizar el grafo**

Run: `graphify update .`
Expected: el grafo reindexa los archivos nuevos sin error.

- [ ] **Step 5: Commit final**

```bash
git add public_html/CLAUDE.md "BASE DE CONOCIMINETO/AVANCECORP/Rol Directorio.md" "BASE DE CONOCIMINETO/AVANCECORP/Inicio.md"
git commit -m "Docs: rol Directorio en CLAUDE.md + nota de vault"
```

---

## Self-Review (cobertura vs spec)

- ✅ Rol `directorio` solo lectura → Tareas 1, 10 (verificado que no aparece en policies).
- ✅ Cada dueño su login + clave temporal = DNI → Tareas 4, 6, 10.
- ✅ Lo crea el superadmin desde equipo → Tareas 4, 6.
- ✅ 9 métricas (AUM×moneda, clientes, contratos, cobranza/morosidad, intereses, caja, crecimiento, ranking, top clientes) → Tareas 2, 3, 8.
- ✅ Estilo cockpit oscuro responsive → Tareas 7, 9.
- ✅ Drill-down solo lectura → Tareas 3, 8.
- ✅ Cambiar contraseña propia → Tareas 7, 8, 10.
- ✅ Enrutado de login → Tarea 5.
- ✅ Frescura (carga + botón actualizar + hora) → Tareas 7, 8.
- ✅ Monedas separadas siempre → Tareas 2, 3, 8.
- ✅ Verificación patrón analista + advisors → Tarea 10.
- ✅ Fuera de alcance (distribución cartera, export Excel) → no hay tareas (correcto).
- ⚠️ 3 definiciones de negocio a confirmar con Miguel en el SQL → marcadas en Tareas 2 y 3.
```
