---
tags: [crm, ux, avatares, agenda, deploy, produccion, 2026-07-17]
actualizado: 2026-07-17
---

# Pasada de UX del CRM (vendedor) — 2026-07-17

Sesión de mejoras de experiencia del CRM del vendedor. **Todo commiteado (5 commits en `main` LOCAL) y DESPLEGADO+verificado en producción `crm.miavance.com`** (build vivo `index-DEAQNq7u.js` / `index-BG1kKAKm.css`; HTML sirve el hash nuevo, assets 200, ZIP 404 en ambos dominios, asset viejo 404). Mismo método de [[Deploy a Hostinger]].

## Qué se hizo
- **Avatares de silueta por género** (diseño Claude Design "Avatares Silueta v2", importado por MCP DesignSync): 3 peinados por género elegidos por hash del nombre; tinte violeta (F) / azul (M). Campo `genero` + `fecha_nacimiento` agregado al tipo `Lead`. **Sin dato de género → iniciales** (distinguibles), no una silueta neutra idéntica.
- **Agenda "Hoy" = protagonista**: dónde estar / qué vence hoy manda el día del vendedor → capital en juego por cita + urgencia; la meta bajó a franja compacta (marcador). Regla: [[Layout del CRM con lógica comercial]] (si no existe, ver memoria del proyecto).
- **Menú lateral colapsable + hover-peek animado** (asoma el menú al pasar el mouse, se cierra solo).
- **Hover-card de preview del lead** (Radix `@radix-ui/react-hover-card`) en Cartera y la cola: etapa + capital + contacto sin abrir la ficha.
- **Timeline del lead colapsable** (agrupa rachas de cambio de etapa, evita scroll infinito).
- **Botón "Llamar"**: como el `tel:` no marca desde la laptop, ahora **copia el número y abre el registro del resultado**.
- **Meta del mes**: el capital en **USD ahora cuenta a la meta convertido a soles** al tipo de cambio promedio de la semana (es conversión, no rompe la regla PEN≠USD).

## ⚠️ Push bloqueado — decisión de repos pendiente
El remoto `origin` (`avanza-platform`/`main`) es **otro proyecto** ("Academia Phoenix") y no contiene el CRM; las historias divergieron. **No se puede push/pull sin destruir uno de los dos.** Los 5 commits están **solo en local**. El deploy no depende de git (build local → Hostinger). Miguel decide la estructura de repos/ramas.

## Falta para que funcione en REAL (mañana)
1. ~~Migración BD~~ → **CERRADA DE PUNTA A PUNTA 2026-07-18**: `genero` + `fecha_nacimiento` en `crm.leads` EN PROD (`20260718000001`, branch→merge, gate omitido con OK de Miguel — ver `MIGRACIONES.md`) **+ frontend DESPLEGADO** (build vivo `index-hYSw4tAX.js`: formulario de alta con género/fecha + validación 18 años + frontera). Falta solo la prueba visual de Miguel. ⚠️ Solo leads: `perfiles` diferido (el cliente convertido y el Equipo siguen en iniciales).
2. ~~Tipo de cambio real~~ → **HECHO 2026-07-18**: edge `crm-tipo-cambio` (API pública oficial del **BCRP**, series SBS compra `PD04639PD` + venta `PD04640PD`, punto medio, **promedio 7 días hábiles**, cache 1 h en la edge, sin BD ni cron — la edge es proxy de solo lectura). `useTipoCambio` real la consume con Valibot en la frontera; si BCRP/edge fallan → null y la meta degrada a solo-PEN (nunca inventa TC). Verificado en prod: S/ 3.3965 (08–16 Jul), 401 sin sesión. Build vivo `index-BcuvIYj2.js`.
3. ~~Agenda real~~ → **EN PROD 2026-07-18** (Fases A+B2 del plan v2): tabla `crm.tareas` + RPC `cerrar_tarea` en BD (gate 207/207) y frontend desplegado (build `index-DJSuuUeh.js`): HOY héroe con tareas reales (vencidas primero), sección "Próxima acción" en el drawer con quick-add, pantalla Agenda derivada. Ver [[Agenda comercial del CRM (plan v2)]]. Falta el motor (completar-y-agendar-siguiente) — Fase B.

## Notas
- La otra sesión de IA en paralelo commiteó su "distribución de leads para gerencia" y desplegó su build aislado antes; dejó `lead-nuevo.tsx` (a11y) e `inteligencia.ts` (comentario) sin commitear — no se tocaron.
- Claude Design trae también avatares **ilustrados a color "solo ficha"** — no implementados; opción futura para el header del drawer.

## Relacionadas
[[CRM conexión a datos reales]] · [[Deploy a Hostinger]] · [[Acceso y roles del CRM]] · [[Refactor de tablas y datos del CRM]]
