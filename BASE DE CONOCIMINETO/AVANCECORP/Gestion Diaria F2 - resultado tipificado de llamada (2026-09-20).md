---
tags: [crm, gestion-diaria, servidor, front]
fecha: 2026-09-20
estado: ensayada-en-banco, pendiente-de-instalar
---

# Gestión Diaria F2 — el resultado tipificado de la llamada (2026-09-20)

Fase 2 del plan de [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]]. A partir de aquí **toda llamada del CRM** (acciones de contacto de colas/Hoy/ficha, cierre de una tarea de llamada desde la agenda, composer del drawer) se cierra con **uno de siete resultados** y sus efectos ocurren en la misma operación: tarea siguiente, descarte con submotivo hacia el [[Centro de rescate]], «No insistir». Con **Deshacer** de 24 h para quien la registró.

## Las decisiones de Miguel (19/09) que gobiernan
- Siete resultados: no contestó · contestó, volver a llamar · contestó, agendó **cita** · contestó, no le interesa · número errado · no es la persona · pide otro producto.
- «No le interesa» y «pide otro producto» **descartan** con submotivo obligatorio. Submotivos → motivo REAL del catálogo: sin fondos ahora → `sin_fondos`; ya invirtió con otro → `competencia`; desconfianza / no le interesa invertir / otro → `sin_interes`; préstamo / crédito / otro producto → `pide_credito`. El lead cae en el Centro de rescate (el supervisor lo reabre con «Reabrir»).
- Número errado / no es la persona: **el analista decide** — llamar al 2.º número hoy (la tarea lleva el número en el título), descartar por `datos_invalidos`, reintentar a 7 días o solo registrar. Esas llamadas cuentan como intento pero **no** entran en la tasa de contacto.
- «No contestó»: el motor propone WhatsApp mañana (omitible); al **6.º intento** sin respuesta el panel ofrece «marcar perdido: no responde» (el servidor exige ≥ 2 intentos sin respuesta, sin contar números errados).
- Casilla «Pidió que no lo vuelvan a llamar» (Ley 29571) → `crm.marcar_no_contactar`. **No se deshace** desde el analista (levantarlo es de Gerencia).

## Reglas escritas tras las revisiones (Codex ×2, tres refutadores, auditor RLS)
- **Quién registra:** vendedor, supervisor y gerencia (los mismos que el escritor sellado). El **supervisor** puede registrar «volver a llamar» / «agendó cita» **sin agendar**: la agenda es del analista; al **dueño** del lead se le exige la tarea.
- **Deshacer es una reapertura:** compone sobre `crm.reabrir_lead_fn` → ciclo nuevo, SLA y tenencia reiniciados, el descarte queda en el ledger de episodios. Devuelve el lead a la etapa que tenía al descartarse, salvo «cita agendada» → «contactado» (la cita la canceló el sistema y no vuelve). Si otro lead vivo ya tiene ese teléfono, el deshacer falla con texto humano y no sella nada.
- **Replay honesto:** un reintento con la misma operación devuelve lo guardado sin escribir (aunque la fecha propuesta ya haya pasado); un reintento con otro resultado, submotivo, descarte o «No insistir» se rechaza (23505).
- **Anti-falsificación:** las claves del resultado en `crm.actividades.metadata` solo las escribe el núcleo bajo un GUC; un INSERT del cliente con `resultado` muere con 42501. El resultado escrito no se reescribe (append-only).
- **Candados en el orden de la casa** (documento → persona → lead → recibo/tarea) cuando la operación toca a la persona.
- **Deuda declarada para F3:** el registro de F1 no muestra `deshecho_en` (un resultado deshecho se ve como vigente hasta F3, que debe filtrarlo) y el Centro de rescate no marca los descartes deshechos.

## Dónde vive
- Migración `20260920005000_crm_gestion_diaria_resultado_llamada.sql` (puertas `crm.registrar_llamada_v3`, `crm.deshacer_resultado_llamada`; núcleo `private.llamada_registrar`; gate paraguas `private.assert_gestion_diaria` = F1 + F2; 14 mutantes). Acta en `MIGRACIONES.md`. Ensayo: `supabase/scripts/gestion-diaria-resultado/`.
- Front: `lib/resultado-llamada.ts` (catálogo, espejo del servidor), `components/gestion-diaria/registrar-resultado.tsx` (panel del mockup 5, atajos 1–7), `store.registrarLlamada` / `store.deshacerResultadoLlamada`, cubo `llamada` en `data/sla-operacion-comandos.ts`.
- **Orden de instalación:** F1 (`20260919211958`) → F2 → front (`/release-crm`).

Relacionadas: [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Terminología comercial del CRM]] · [[Acceso y roles del CRM]] · [[Inicio]]
