# Llamadas desde el celular al CRM — carpeta del plan para Miguel

Esta carpeta es la copia **versionada** del plan aprobado y de su avance. Llega por git a los dos talleres; la copia de trabajo de `GESTION DIARIA/AUTOMATIZACION DE LLAMADAS/` sigue existiendo, pero git la ignora y no viaja.

## Objetivo de negocio (Jhosep, 30/09/2026)

> **Objetivo:** que los vendedores registren cada llamada sin esfuerzo.
>
> Al colgar, el celular los lleva directo a la encuesta de Gestión Diaria (la misma de «Llamar»). Según lo que marquen, se cierra la tarea pendiente o se abre la siguiente.
>
> **Alcance:** solo el CRM de Avance Corp, con MacroDroid en celulares Android corporativos. El analista elige siempre el resultado.

Consecuencia para el piloto: la gestión que se mide es la que el vendedor **hace** (llamadas salientes). El CRM no tiene métricas de llamadas recibidas, así que las entrantes no son el foco ahora (quedan como posible ampliación futura); en el plan aprobado siguen apareciendo (F0.3.1 «diez entrantes», F2 «entrante perdida → devolución») y su recorte es una propuesta para Miguel (`PROPUESTAS-DE-AJUSTE.md`, #8).

## Qué hay aquí

| Archivo | Qué es | Quién lo escribe |
| --- | --- | --- |
| `PLAN.md` | La Versión 3 aprobada (29/09/2026): 8 fases, 33 subfases, 102 tareas con casilla. Los textos no se tocan; solo cambian las casillas, las líneas «Estado · Avance · Responsable», «Seguimiento de F<n>», «Evidencia / fecha de validación» y la tabla de 5.1, con las reglas de su propia sección 5.1 | Claude, con `actualizar-avance.mjs` |
| `AVANCE.md` | Resumen de un minuto: total, tabla por fase, detalle por subfase, «Lo último» y últimos cambios | Se genera; no se edita a mano |
| `estado.json` | El estado en datos (tareas hechas, en curso o bloqueadas, subfases, fases, novedad, cambios). Es el espejo del tablero vivo | Claude, en cada avance real |
| `actualizar-avance.mjs` | Regenera `PLAN.md` y `AVANCE.md` desde `estado.json` (`node actualizar-avance.mjs`) | — |
| `PROPUESTAS-DE-AJUSTE.md` | Ajustes que Claude propone al plan, con evidencia. **No cambian el plan** hasta que Miguel los apruebe | Claude |
| `F2-PLAN-CORTO.md` | Borrador del contrato y del diseño de F2 (tablas, núcleo, RLS, verificación, orden de PRs) apoyado en el catálogo real. Sin SQL hasta el OK de Miguel; incluye las 7 decisiones que él debe fijar | Claude |
| `F3-PLAN-CORTO.md` | Plan corto de F3 (Edge Function de ingesta, puerta de servicio, límite, salud, macro durable): las 5 decisiones (1–4 tomadas por Jhosep como provisionales el 01/10), las 6 pruebas que Jhosep debe hacer en C1 antes de escribir la macro y el estado de F3-a (la base, construida en banco local) | Claude |
| `F5-F7-ANALISIS.md` | Análisis adelantado de F5, F6 y F7 (03/10): qué cambió desde que se aprobó el plan, qué se reutiliza, el diseño descrito sin código y las decisiones que necesitaría Miguel. Borrador: no pide revisión hasta que toque F5 | Claude |
| `SEGUIMIENTO.md` | **Seguimiento conciliado** de las 102 tareas (07/10, pedido por Miguel): estado, evidencia, siguiente paso, responsable y dependencia de cada una; hitos de instalación; ampliaciones y decisiones pendientes | Claude |
| `COORDINACION.md` | Reglas de trabajo con Miguel, mapa de los PR, turno, orden y bitácora | Claude (Jhosep) |
| `F4B-PLAN-CORTO.md`, `F4C-F4D-PLAN-CORTO.md`, `F4E-PLAN-CORTO.md` | Planes cortos de la pestaña del analista, la tarjeta «Celulares» con la activación de C1, y la vista de supervisor y gerencia | Claude |
| `HANDOFF-<fecha>.md` | Cierre de cada sesión: qué se hizo, cómo probarlo, qué falta y el prompt para retomar | Claude |

La guía del día para activar C1 vive con los materiales del piloto: `docs/gestion-diaria/piloto-telefonia/ACTIVAR-C1.md`.

## Dónde verlo en vivo

- **Tablero (el que vale):** https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M — una columna por fase, una tarjeta por subfase, una casilla por tarea. Se actualiza al instante cuando Claude escribe un avance. Es privado: Jhosep lo comparte desde el menú «Compartir» de la página.
- **Plan completo en documento:** https://claude.ai/artifact/TkNzWXtg3RPuFPvrnZcaEX — el mismo texto de `PLAN.md`, para leer y comentar.
- Esta carpeta se actualiza con cada commit; el tablero, en el momento. Si difieren, manda el tablero.

## Cómo se lee el avance

- Casilla marcada = tarea terminada **y verificada**, con evidencia y fecha en la línea «Evidencia» de su subfase.
- `EN CURSO` o `BLOQUEADA: motivo` junto a una tarea = empezada o detenida; la casilla sigue vacía.
- `NO APLICA: motivo` = tarea condicional que no corresponde; no cuenta en el denominador.
- Una subfase se cierra cuando todas sus tareas aplicables están verificadas. Una fase, cuando además cumple su «Aceptación» y los checks comunes de la sección 14.
- Solo Claude marca casillas, y solo con evidencia ejecutada (test corrido, prueba en celular, commit). Nadie las marca por suposición.

## Estado hoy

**Al 07/10/2026, 21:45 UTC.** Detalle tarea por tarea en `SEGUIMIENTO.md` (31 de 102 cerradas con evidencia).

- **F1 (la encuesta al colgar) está en producción** desde la noche del 01/10 (PR #165) y se comprobó con C1 el 02/10.
- **Las doce migraciones de llamadas, la Edge y F4-b están en `main`** (PR #190, fusionado el 06/10) y probadas, pero
  **sin instalar**: producción tiene 0 de 12, sin Edge y con el modo SLA activo (comprobado por Miguel el 07/10). La
  pantalla va detrás del interruptor `LLAMADAS_CELULAR_APROBADAS` (apagado).
- **F4-c (la tarjeta «Celulares») está en `main`:** Miguel la aprobó y fusionó el #215 el 07/10 (`5f42e908`).
- **Las decisiones #16, #17 y #18 están aprobadas** (07/10, `DECISIONES-PENDIENTES.md`): Pro para el piloto, F0 con
  salientes y F4-e en F4 con el diccionario A1–A7.
- **Lo siguiente es de Miguel, y su agente ya lo está haciendo:** ensayar con SLA activo, aplicar las doce desde LF con
  sus registradores, desplegar la Edge y abrir el interruptor en un release. Después se activa C1 con `ACTIVAR-C1.md`
  («instalar no es activar»).
- F0 (piloto, sin código) sigue en curso con un solo celular, C1 (Samsung A16).

Para retomar: el `HANDOFF-*.md` más reciente.
