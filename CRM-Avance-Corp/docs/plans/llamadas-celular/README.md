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
| `HANDOFF-<fecha>.md` | Cierre de cada sesión: qué se hizo, cómo probarlo, qué falta y el prompt para retomar | Claude |

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

Ninguna fase publicada en producción. F0 (piloto, sin código) arrancó el 29/09/2026 y sigue en curso con C1 (Samsung A16); lo que falta depende de personas y equipos: más celulares, analistas y soporte, consentimiento y cinco días de medición. F1 (solo pantalla, sin tablas ni puertas nuevas) se construyó y probó el 30/09/2026 en la rama `feat/llamadas-f0` (tests, E2E en Docker, prueba real en C1) y Miguel la aprobó y fusionó a `main` ese mismo día (PR #148); **publicarla es el siguiente paso de Miguel** (release con preflight) y hasta entonces la macro del celular sigue con la URL sin número. F2 arrancó como análisis (`F2-PLAN-CORTO.md`): sin SQL hasta que Miguel fije sus 7 decisiones.
