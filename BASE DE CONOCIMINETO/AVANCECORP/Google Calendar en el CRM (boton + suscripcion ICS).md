---
tags: [crm, agenda, google-calendar, ics, 2026-07-18]
actualizado: 2026-07-18
---

# Google Calendar en el CRM — botón + suscripción ICS

Decisión de Miguel (2026-07-18): conectar la agenda del CRM con Google Calendar
"de manera muy sencilla". Se descartó el OAuth completo (aprobación de Google +
mucho desarrollo — sigue en Fase H del [[Agenda comercial del CRM (plan v2)]]) y
se construyeron las **dos variantes baratas, complementarias**:

## 1. Botón "Añadir a Google Calendar" (por tarea)

- En la pantalla **Agenda**, cada fila tiene un botón (ícono calendario+) que abre
  la plantilla pública `calendar.google.com/calendar/render?action=TEMPLATE` con
  título, fecha/hora, duración (default 30 min) y la nota como descripción.
- Sin conexión de cuenta, sin permisos, instantáneo. Si la fecha es ilegible el
  botón no se pinta (jamás un enlace roto).
- Código: `enlaceGoogleCalendar()` en `app/src/lib/agenda-derivada.ts` (+ tests).

## 2. Suscripción del calendario (conectar una vez)

- Tarjeta **"Mi calendario de Google"** en Configuración (solo roles que escriben;
  en demo solo se anuncia): genera un **enlace secreto personal**, se copia y se
  pega en Google Calendar → *Otros calendarios → + → Desde una URL*. Las tareas
  pendientes aparecen solas; Google refresca **cada algunas horas** (es espejo de
  lectura, NO sincronización bidireccional).
- **Renovar enlace** rota el token: el enlace anterior muere al instante (así se
  revoca un enlace filtrado). Sin DELETE: dejar de compartir = rotar.
- Piezas:
  - Tabla `crm.agenda_ics` (token uuid por miembro de `crm.equipo`). RLS: cada
    quien SU fila — el token es privado incluso para su supervisor. Migración
    `20260718120243_crm_agenda_ics_suscripcion` ✅ producción (ver `MIGRACIONES.md`).
  - Edge `crm-agenda-ics` (**verify_jwt=false**: Google no manda JWT; el token ES
    el control de acceso). Sirve ICS (RFC 5545, escapes correctos, UTC +
    X-WR-TIMEZONE Lima) con las tareas `pendiente+activo` del dueño (ventana: 30
    días atrás en adelante, techo 500). Token desconocido → 404. Solo lectura.
  - Frontend: `lib/agenda-ics.ts` (URL del feed + pasos), API en `data/crm-api.ts`
    (`obtenerTokenIcs`/`crearTokenIcs`/`rotarTokenIcs`), tarjeta
    `components/app/calendario-google.tsx` (+ tests de los 4 estados).

## Verificación (2026-07-18)

- Oráculo transaccional `test-agenda-ics.sql` → `AGENDA_ICS_TX_OK` en el branch.
- Smoke E2E en branch: feed 200 con VEVENT correcto; 404 con token malo.
- Advisors security+performance: sin hallazgos nuevos. Merge verificado en prod.
- ⚠️ Gate RLS de sesiones reales **omitido con OK explícito de Miguel** (tabla
  aislada). **Deuda**: añadir `agenda_ics` a `fixtures.mjs`/`seed-demo.mjs`/
  `test-rls.mjs` en la próxima pasada del gate.

## Estado final

- **Desplegado a crm.miavance.com el 2026-07-18** (salió en el deploy posterior de
  la sesión de formularios de clientes; verificado contra el sitio vivo: chunks
  `config-*` y `agenda-*` con la tarjeta y el botón, `crm-api-*` con `agenda_ics`).
- Costo: cero adicional (el branch temporal ya fue borrado; Google no cobra).

Relacionadas: [[Agenda comercial del CRM (plan v2)]] · [[CRM conexión a datos reales]] ·
[[Deploy a Hostinger]]
