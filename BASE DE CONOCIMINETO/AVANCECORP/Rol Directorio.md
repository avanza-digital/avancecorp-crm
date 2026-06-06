---
tags: [feature, roles, directorio, seguridad, dashboard]
actualizado: 2026-06-05
---

# Rol Directorio (cockpit ejecutivo para los dueños)

**Implementado 2026-06-05.** Quinto rol del portal, pedido por Miguel: un **usuario especial para Kirk y Carlos** (dueños de Avance Corp) que muestre la salud del negocio "de un vistazo" con calidad, que diga *wow*. Es un **mirador de SOLO LECTURA** — no operan nada.

## Qué ve (9 métricas)
AUM (capital gestionado) **por moneda** · clientes activos (+nuevos del mes) · contratos activos (+ticket) · **cobranza al día / morosidad** · intereses pagados a clientes · caja a 90 días · crecimiento de capital 12 meses · **ranking por analista** · top 10 clientes. Con **drill-down** (clic en una métrica → tabla de detalle, solo lectura).

## Lo más importante — seguridad
- El rol `directorio` **NO tiene ninguna policy de RLS** (verificado: 0 policies lo nombran). No puede leer ni escribir tablas del negocio directamente. Su único acceso directo es **su propia fila** de `perfiles` (self-read).
- **Todos los números llegan por RPCs `SECURITY DEFINER`** que validan `es_directorio() OR es_admin()` por dentro: `metricas_directorio()`, `directorio_top_clientes()`, `directorio_morosidad()`, `directorio_ranking_analistas()`. Helper `es_directorio()`. Probado: un `cliente` que las llama recibe `42501 No autorizado`.
- **Única escritura que puede hacer:** cambiar **su propia contraseña** (`supabase.auth.updateUser` — actúa sobre `auth.users`, no sobre data del negocio). La regla "solo lectura" del negocio se mantiene intacta.

## Cómo se crea
El **superadmin**, en `/admin/equipo` → "+ Nuevo miembro del equipo" → tipo **Directorio**. Clave inicial = **DNI** (igual que el resto, ver [[Clave temporal = DNI]]). Aparece con badge **DIRECTORIO**; se puede desactivar ahí mismo. La edge `crear-admin` revalida en el server que solo el superadmin crea directorio.

## Pantalla
`/admin/directorio.html` + `js/admin/directorio.js` (v1) + `css/directorio.css` (v1) — **cockpit oscuro** tipo fintech, responsive (los dueños lo miran del celular). El login enruta el rol vía `auth.js` → `verificarDirectorio()`. No usa `setupAdminShell` (tiene su propio header). Todo nombre de cliente/analista pasa por `escapeHtml` (defensa XSS).

## Definiciones de negocio (confirmadas por Miguel)
- **Intereses pagados** = cuotas `tipo='retorno'` en estado `pagado`.
- **Ranking por analista** = se agrupa por el **asesor del cliente** (`perfiles.asesor_perfil_id`).
- **Crecimiento** = capital captado por mes (por `fecha_inicio` del contrato), mostrado acumulado en la línea.

> ⚠️ El ranking depende de que los clientes tengan asesor. Por eso se arregló el bug de auto-asignación → ver [[Fusión asesor-analista]] (§ bug 2026-06-05). Los clientes creados por admin/superadmin no tienen asesor y no entran al ranking hasta asignarles uno.

## Fuera de alcance (por ahora)
Distribución de cartera (plazo/tasa), export a Excel, tiempo real "en vivo" (carga fresca + botón actualizar). El `var_pct` mensual se capa para no mostrar % absurdos.

## Notas relacionadas
[[Rol Analista]] · [[Fusión asesor-analista]] · [[Arquitectura del portal]] · [[Clave temporal = DNI]] · [[Inicio]]
