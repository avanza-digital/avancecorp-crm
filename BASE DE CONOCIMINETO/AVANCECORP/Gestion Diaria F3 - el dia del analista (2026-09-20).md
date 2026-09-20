---
tags: [crm, gestion-diaria, servidor, front]
fecha: 2026-09-20
estado: ensayada-en-banco, pendiente-de-instalar
---

# Gestión Diaria F3 — el día del analista (2026-09-20)

Fase 3 del plan de [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]], después de [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]]. El analista abre Gestión Diaria y lo primero que ve es **a quién llamar ahora**: su cola completa del día, agrupada y ordenada, con el panel del resultado en cada fila. Debajo, su marcador, sus compromisos y los descartes de hoy con «Deshacer».

## La pregunta que responde

*¿A quién llamo ahora?* Una sola pantalla, cuatro grupos **en el orden que manda** (decisión #2 de Miguel):

1. **Sin primer intento** — el lead nuevo va primero: el SLA corre desde la asignación.
2. **Vencidas** — lo ya comprometido que se pasó de fecha.
3. **Hoy** — lo que el propio analista acordó para hoy.
4. **Sin conversación** — leads abiertos que llevan más días de los que permite la perilla sin una conversación real.

El cuarto grupo **estrena `crm.politica_abandono.dias_abandono`** (7 días): se mide `greatest(última conversación real, tenencia_desde)` ante el **dueño actual**, y los intentos (llamada no contestada, WhatsApp enviado) **no** reinician el reloj — decisión de Miguel del 16/08. Los tres primeros salen de `crm.cola_accion_v2_fn`, la misma cola del mundo SLA, que no se toca.

## Qué mide el marcador

- **Llamada** = `llamada_realizada` + `llamada_no_contestada`. **Contacto** = `llamada_realizada`. **Llamada útil** = la que no acabó en «número errado» ni «no es la persona» (el histórico sin resultado cuenta como útil). **Tasa de contacto** = contactos / útiles.
- El **%** aparece SIEMPRE con su conteo al lado («60 % · 5 llamadas»), y el chip Bien / Atención / Bajo solo desde **5 llamadas útiles** (decisión #7). Umbrales en un solo sitio, `private.gestion_diaria_umbrales()`: Bien ≥ 45 %, Atención ≥ 25 %.
- **Llamadas por hora** (08–20 Lima, decisión #8), que F4 y F5 reutilizarán para el equipo y el pulso.
- **Cita agendada** = tarea de cita creada en el día por el analista, la misma definición que `metricas_agenda_fn`.

## Lo que se decidió aquí (y por qué)

- **El nivel se juzga con la tasa SIN redondear** (Codex, 20/09): 13 de 29 es 44,83 %, o sea «atención», aunque redondee a 45. El % que se muestra sí va redondeado.
- **Quién puede mirar el día de quién:** un analista, solo el suyo. Supervisor, gerencia y lector global, el de un miembro **activo** de su roster visible que **lleve leads**. `crm.equipo_visible_fn` incluye a los dados de baja y, para el lector global, a coordinación y directorio: por eso se exige `activo` y `rol_crm`. Denegación con 42501 explícito, nunca un día vacío que parezca «no llamó».
- **«Deshacer» solo lo ofrece quien registró:** el servidor exige ser el autor, así que un supervisor que mira el día de otro recibe `puede_deshacer: false` y no un botón que fallaría.
- **El deshacer sale del toast y vive en la pantalla:** antes solo duraba 15 segundos; ahora «Descartados hoy» lo ofrece las 24 horas que el servidor admite.
- **Se paga la deuda de F2:** el registro crudo de F1 ya muestra `deshecho_en`, así que un resultado deshecho deja de verse como vigente.
- **«Hoy» no cambia.** Son dos presentaciones distintas y se dice en pantalla: Hoy = «las 3 cosas de ahora»; Gestión Diaria = la cola completa. Una prueba compartida las mantiene coherentes en el primer ítem: el lead sin primer intento manda en las dos.

## Dónde vive

- Migración `20260920041500_crm_gestion_diaria_analista.sql`: puerta `crm.gestion_diaria_analista_fn(p_dia, p_analista_id)` (INVOKER) y núcleos `private.gestion_diaria_llamadas` (la definición única de llamada/contacto/tasa, para F4 y F5), `gestion_diaria_analista_core` y `gestion_diaria_umbrales`. Gate `assert_gestion_diaria_analista` dentro del paraguas, 24 mutantes. Acta en `MIGRACIONES.md`; ensayo en `supabase/scripts/gestion-diaria-analista/`.
- Front: `screens/gestion-diaria/analista.tsx`, `lib/gestion-diaria-analista.ts` (contrato, `ordenarColaDiaria` y el espejo demo), `useDiaAnalista`, y `RegistrarResultado` con `onGuardado` para saltar a la fila siguiente al guardar.
- **Orden de instalación:** F2 (`20260920005000`) → F3 → front (`/release-crm`).

Relacionadas: [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] · [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Terminología comercial del CRM]] · [[Acceso y roles del CRM]] · [[Inicio]]
