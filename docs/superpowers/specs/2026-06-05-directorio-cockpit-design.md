# Directorio — Cockpit ejecutivo para los dueños (Kirk & Carlos)

- **Fecha:** 2026-06-05
- **Autor:** Miguel (idea) + Claude (diseño)
- **Estado:** Aprobado (brainstorming) — pendiente de plan de implementación
- **Proyecto:** Portal Avance Corp (`miavance.com`)

## 1. Resumen

Un **rol nuevo, de solo lectura, llamado `directorio`**, pensado para que los dueños de Avance Corp (Kirk y Carlos) entren al portal y vean la salud del negocio en una **única pantalla ejecutiva ("cockpit")** de estilo oscuro tipo fintech. No operan nada: no crean, no editan, no borran. Es un mirador de alto nivel con drill-down de solo lectura para entender el detalle detrás de cada número.

Objetivo: que los dueños tengan **información de calidad de un vistazo** y digan "wow", sin riesgo de tocar data real por accidente.

## 2. Decisiones tomadas en el brainstorming

| Decisión | Elección |
|---|---|
| Modelo de acceso | **A** — rol nuevo `directorio`, **solo lectura** (no superadmin, no pestaña embebida) |
| Login | **Cada dueño su propio usuario** (auditable), no uno compartido |
| Clave inicial | **Temporal = DNI**, igual que el resto del portal (ver [[Clave temporal = DNI]]) |
| Cambio de clave | El dueño **puede cambiar su propia contraseña** desde su pantalla (única acción de escritura que tiene, y es sobre su cuenta de Auth, no sobre data del negocio) |
| Quién los crea | El **superadmin**, desde `/admin/clientes` → "+ Nuevo miembro del equipo" → tipo **Directorio** |
| Estilo visual | **A — Cockpit oscuro** (fintech / Bloomberg, denso, "en vivo") |
| Alcance | **B** — tablero **+ drill-down** de solo lectura en las métricas |
| Frescura | Carga fresca por visita + botón actualizar + hora del último corte. **Realtime streaming = mejora futura**, no en el arranque. |
| Monedas | **Soles y dólares SIEMPRE separados** (nunca sumados) |
| Dispositivo | Responsive (los dueños lo mirarán desde el celular) |

## 3. Métricas incluidas (9)

1. **Capital gestionado (AUM)** — separado por moneda (Soles / Dólares), con variación mensual.
2. **Clientes activos** — total + nuevos del mes.
3. **Contratos activos** — total + ticket promedio.
4. **Cobranza al día / morosidad** — % al día y nº de cuotas vencidas.
5. **Intereses pagados a clientes** — rentabilidad entregada (acumulado).
6. **Próximos pagos (caja)** — monto a pagar a clientes en los próximos 90 días.
7. **Crecimiento de capital** — tendencia de capital captado, últimos 12 meses (gráfico hero).
8. **Ranking por analista** — quién capta más capital / clientes.
9. **Top clientes por capital** — top 10, concentración de la inversión.

**Fuera de alcance (explícito):** *Distribución de cartera (plazo/tasa)* — no se incluye. Exportar a Excel — no por ahora.

## 4. Arquitectura

Stack existente del portal (sin cambios de fondo): frontend HTML+CSS+**JS vanilla (ES Modules)**, backend **Supabase** (Postgres + Auth + Edge Functions), gráficos **SVG vanilla custom**, deploy manual a Hostinger. Ver [[Arquitectura del portal]] y `public_html/CLAUDE.md` (fuente de verdad técnica).

### 4.1 Rol y base de datos
- Nuevo valor de rol **`directorio`** en `perfiles.rol` (junto a `cliente | analista | admin | superadmin`).
- Helper SQL **`es_directorio()`** (espejo de `es_admin()` / `es_analista()`).
- **Acceso a datos SOLO vía RPC (lo más estricto):** el rol `directorio` **no recibe ninguna policy nueva** sobre las tablas de negocio. NO puede `SELECT` `contratos`/`cronograma_pagos` directamente (la RLS los niega), ni mucho menos escribir. Su único acceso directo es la lectura de **su propia fila** en `perfiles` (policy de self-read que ya existe para todos). Todas las métricas llegan por **RPCs `SECURITY DEFINER`** que corren con privilegios elevados pero validan `es_directorio() OR es_admin()` antes de devolver nada. Resultado: el dueño nunca toca data cruda; solo ve los números ya calculados.
- **Única excepción de escritura**: el dueño puede **cambiar su propia contraseña** vía **Supabase Auth** (`auth.updateUser({ password })`), que actúa sobre su cuenta de Auth (`auth.users`), **no** sobre las tablas de negocio del `schema public`. No requiere ninguna policy de escritura ni edge function; el propio usuario autenticado actualiza su clave. La regla "solo lectura" se refiere a la **data del negocio** y se mantiene intacta.
- Escalada de roles: crear/asignar el rol `directorio` exige `es_superadmin()`, consistente con la regla "escalada de roles cerrada" del portal. Un admin no puede crear directorios; solo el superadmin.

### 4.2 Cálculo en el servidor (no en el navegador)
- Las cifras agregadas se calculan en **RPCs `SECURITY DEFINER`** que validan `es_directorio() OR es_admin()` antes de responder:
  - `metricas_directorio()` → devuelve el bloque de KPIs de cabecera (AUM por moneda, clientes, contratos, cobranza, intereses, caja 90d, serie de crecimiento 12m).
  - RPCs de detalle para los drill-down (solo lectura), p. ej. `directorio_top_clientes()`, `directorio_morosidad()`, `directorio_ranking_analistas()`.
- Razón: centralizar la lógica de negocio (sumas por moneda, definición de "morosidad", ventana de caja) en un solo lugar y **no exponer data cruda innecesaria** al frontend del dueño.

### 4.3 Creación del usuario directorio
- Reutiliza la edge **`crear-admin`** (ya crea `admin` **o** `analista`, solo superadmin) extendiéndola para crear también rol **`directorio`**. Clave temporal = DNI (reutiliza el mismo patrón de `crear-cliente`). Ver [[Clave temporal = DNI]].
- En `/admin/clientes`, el botón "+ Nuevo miembro del equipo" suma la opción **Directorio**. En la tabla "Equipo del sistema" aparece con badge **DIRECTORIO** y se puede **desactivar** ahí mismo (corta el acceso al instante), igual que el analista.

### 4.4 Enrutamiento de login
- `auth.js` gana un **`verificarDirectorio()`** (espejo de `verificarAnalista()`); el login manda el rol `directorio` a `/admin/directorio.html` y le impide navegar al resto del panel admin.

## 5. La pantalla (`/admin/directorio.html` + `js/admin/directorio.js`)

Estilo **cockpit oscuro**. Layout (de arriba a abajo):
- **Barra superior**: marca "Avance Corp · Directorio", nombre del dueño logueado, indicador de frescura ("Actualizado hace X"), botón actualizar, y un menú de cuenta con **"Cambiar contraseña"** + cerrar sesión.
- **Cambiar contraseña**: formulario simple (clave nueva + confirmar) que llama a `auth.updateUser({ password })` de Supabase. Mismas reglas de fuerza de clave que usa el resto del portal. Útil sobre todo para que el dueño deje de usar la clave temporal = DNI.
- **Fila de KPIs**: AUM Soles · AUM Dólares · Clientes activos · Contratos activos · Cobranza/morosidad · Caja 90 días.
- **Gráfico hero**: Crecimiento de capital 12 meses (SVG vanilla, como el resto del portal).
- **Barra**: Intereses pagados a clientes (acumulado).
- **Panel derecho**: Ranking por analista + Top 10 clientes.
- **Responsive**: se reordena en una columna en celular.

Referencia visual: mockup guardado en `.superpowers/brainstorm/<sesión>/content/cockpit-full.html`.

### 5.1 Drill-down (solo lectura)
Clic en una métrica abre su detalle, sin permitir ninguna acción de escritura:
- **Top clientes** → lista de los 10 con su capital.
- **Cobranza / morosidad** → qué cuotas están vencidas, de qué cliente, cuánto.
- **Ranking analistas** → desglose por analista (capital y nº de clientes/contratos).

## 6. Componentes a tocar / crear

| Componente | Cambio |
|---|---|
| Migración SQL | Nuevo rol `directorio`, `es_directorio()`, policies `*_directorio_select_*` (solo lectura), RPCs `metricas_directorio()` + RPCs de detalle. |
| Edge `crear-admin` | Aceptar tipo `directorio` (solo superadmin). |
| `js/auth.js` | `verificarDirectorio()` + enrutar el rol a su pantalla. |
| `admin/directorio.html` | Nueva pantalla cockpit. |
| `js/admin/directorio.js` | Carga de métricas (RPC), render de KPIs/gráficos, drill-down, **cambiar contraseña** (`auth.updateUser`). |
| `admin/clientes` (UI + js) | Opción "Directorio" en "+ Nuevo miembro del equipo" + badge + desactivar. |

## 7. Errores y casos borde
- **Sin permiso**: si un usuario no-`directorio`/no-admin invoca las RPCs, devuelven error de autorización (validación en la propia función, no solo en el frontend).
- **Cero data**: monedas, gráficos y rankings deben renderizar limpio con 0 contratos / 0 clientes (estado vacío, no error).
- **Dos monedas**: nunca sumar soles + dólares; si una moneda no tiene data, mostrar su tarjeta en cero, no ocultarla.
- **Desactivado**: un directorio desactivado pierde acceso al instante (mismo mecanismo que analista).
- **Fechas**: respetar el manejo de fechas del portal para no repetir el [[Bug de fechas UTC]] en los cortes mensuales / ventana de 90 días.

## 8. Verificación (contra la BD real, patrón rol analista)
Con un usuario `directorio` de prueba (crear y **eliminar** después):
1. Ve los números y cuadran con la data real.
2. **No puede escribir nada**: probar que `INSERT/UPDATE/DELETE` directos y cualquier RPC de mutación fallan para el rol.
3. Los drill-down abren y muestran detalle correcto, solo lectura.
4. Un usuario que **no** es directorio (cliente/analista) **no** puede entrar a la pantalla ni invocar las RPCs.
5. Crear el directorio desde la UI funciona (clave = DNI) y desactivarlo corta el acceso.
6. El directorio **sí** puede cambiar su propia contraseña y luego loguear con la nueva; tras hacerlo, sigue **sin** poder escribir data de negocio (revalidar punto 2).
7. Correr los **security advisors** de Supabase: sin hallazgos nuevos.

## 9. Notas relacionadas (vault)
[[Rol Analista]] · [[Fusión asesor-analista]] · [[Clave temporal = DNI]] · [[Arquitectura del portal]] · [[Bug de fechas UTC]] · [[Auditorías del portal]]
