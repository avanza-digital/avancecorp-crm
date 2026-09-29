# Llamadas desde el celular al CRM — carpeta del plan para Miguel

Esta carpeta es la copia **versionada** del plan aprobado y de su avance. Llega por git a los dos talleres; la copia de trabajo de `GESTION DIARIA/AUTOMATIZACION DE LLAMADAS/` sigue existiendo, pero git la ignora y no viaja.

## Qué hay aquí

| Archivo | Qué es | Quién lo escribe |
| --- | --- | --- |
| `PLAN.md` | La Versión 3 aprobada (29/09/2026): 8 fases, 33 subfases, 102 tareas con casilla. Los textos no se tocan; solo cambian las casillas, las líneas «Estado · Avance · Responsable», «Seguimiento de F<n>», «Evidencia / fecha de validación» y la tabla de 5.1, con las reglas de su propia sección 5.1 | Claude, con `actualizar-avance.mjs` |
| `AVANCE.md` | Resumen de un minuto: total, tabla por fase, detalle por subfase, «Lo último» y últimos cambios | Se genera; no se edita a mano |
| `estado.json` | El estado en datos (tareas hechas, en curso o bloqueadas, subfases, fases, novedad, cambios). Es el espejo del tablero vivo | Claude, en cada avance real |
| `actualizar-avance.mjs` | Regenera `PLAN.md` y `AVANCE.md` desde `estado.json` (`node actualizar-avance.mjs`) | — |
| `PROPUESTAS-DE-AJUSTE.md` | Ajustes que Claude propone al plan, con evidencia. **No cambian el plan** hasta que Miguel los apruebe | Claude |

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

Ninguna fase publicada. F0 (piloto, sin código) arrancó el 29/09/2026 con la parte que no necesita celulares: guía, plantillas y ejemplos sintéticos en `docs/gestion-diaria/piloto-telefonia/`. Lo que falta de F0 depende de personas y equipos: elegir 2–3 celulares, asignar analistas y soporte, firmar el consentimiento y medir cinco días.
