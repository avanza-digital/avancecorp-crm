# Avance — Llamadas desde el celular al CRM

Actualizado: 30/09/2026, 11:18 a. m. (hora de Lima). Generado por `actualizar-avance.mjs` desde `estado.json`; no se edita a mano.

Tablero vivo (el que vale, se actualiza al instante): https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M · Plan completo: `PLAN.md` en esta carpeta.

**Lo último:** 30/09 16:18 UTC: F1 con todo el código hecho y verificado en unidad (8 commits en feat/llamadas-f0): lint, typecheck, 4988 tests, cobertura 81,8 %, build y bundle en verde; un archivo ajeno (cliente-form) falla por timeout solo bajo carga. Falta la prueba real en C1 (F1.4.1/F1.4.2): hace falta una build de la rama alcanzable desde el celular sin tocar producción.

**Total:** 8 de 102 tareas · 0 de 8 fases hechas.

| Fase | Tareas | Estado | Subfases hechas |
| --- | --- | --- | --- |
| F0 · Piloto y línea base | 1/12 | En curso | 0/4 |
| F1 · Formulario único y coincidencia exacta | 7/12 | En curso | 1/4 |
| F2 · Núcleo confiable y contrato de datos | 0/13 | Pendiente | 0/4 |
| F3 · Captura, puertas y sincronización durable | 0/13 | Pendiente | 0/4 |
| F4 · Bandeja y registro conciliado en celular y PC | 0/13 | Pendiente | 0/4 |
| F5 · Jev para identificación asistida | 0/15 | Pendiente | 0/5 |
| F6 · Gerencia y calidad de evidencia | 0/12 | Pendiente | 0/4 |
| F7 · Despliegue gradual y operación | 0/12 | Pendiente | 0/4 |

## Detalle por subfase

### F0 · Piloto y línea base — 1/12 · en curso
- **F0.1 · Preparar el piloto** — 0/3 · en curso · Responsable: Jhosep · C1 (Samsung A16, Android 16) registrado y con PWA + MacroDroid; falta la macro, la prueba de humo y 1–2 celulares más.
    - ◐ F0.1.1 — C1 registrado: Samsung Galaxy A16 (SM-A165M), Android 16, Chrome predeterminado, MacroDroid 5.67 (Play Store, sep. 2026), batería «No restringido», «Aparecer encima» activado. Faltan 1–2 celulares más. (30/09/2026, 09:46 a. m.)
    - ◐ F0.1.2 — Jhosep asume analista piloto (C1), soporte y registro de incidencias mientras haya un solo celular. (29/09/2026, 06:16 p. m.)
    - ◐ F0.1.3 — C1 completo: PWA instalada, permisos Teléfono y Registro de llamadas confirmados por evidencia (el número llega al trigger), «Aparecer encima» y batería sin restricciones. Aviso: no aplica al propio responsable. Pendiente para los próximos celulares. (29/09/2026, 07:06 p. m.)
- **F0.2 · Medir la línea base** — 0/3 · pendiente · Responsable: por asignar
- **F0.3 · Probar los equipos** — 0/3 · en curso · Responsable: Jhosep · C1: prueba de humo superada; noche 1/3 sin caerse. Prioridad: salientes (lo que el vendedor hace). Pendiente: 6 salientes más, casos especiales, bloqueo/batería/reinicio/sin red y dos noches; entrantes solo si ocurren.
    - ◐ F0.3.1 — C1: 4 salientes con número (29/09). Foco del negocio (Jhosep, 30/09): las llamadas que el vendedor HACE; las entrantes se observan si ocurren, sin exigirlas (posible ampliación futura; recorte propuesto a Miguel, #8). Faltan 6 salientes y los casos atendida/no atendida/cancelada. (30/09/2026, 09:53 a. m.)
    - ◐ F0.3.2 — C1: notificación con número y nombre PASS. Apertura de la PWA: «Open Website» abre Chrome (FAIL); «Lanzar app → Avance CRM» abre la app instalada (PASS, vía 3); «Send Intent» sin probar (chrome://webapks bloqueado en el equipo). Faltan oculto, fijo, internacional, doble SIM y login. (29/09/2026, 07:22 p. m.)
    - ◐ F0.3.3 — C1, noche 1 de 3 (29→30/09): MacroDroid activo por la mañana y la macro encendida; no hubo llamadas nocturnas que verificar. Faltan 2 noches, pantalla bloqueada, batería baja, reinicio y sin red. (30/09/2026, 09:46 a. m.)
- **F0.4 · Cerrar viabilidad** — 1/3 · en curso · Responsable: por asignar · Guía, registro y matriz entregados; falta la evidencia por equipo del piloto y la decisión.
    - ◐ F0.4.1 — REGISTRO.md, macrodroid.md y compatibilidad.md creados; falta la evidencia por equipo.
    - ✓ F0.4.2 — docs/gestion-diaria/piloto-telefonia/ejemplos-sinteticos.md: 23 casos en 6 grupos (exactos, históricos, compartidos y reciclados, contexto contradictorio, internacionales/ocultos/inválidos, completitud), reglas contrastadas con las migraciones 20260709000001 y 20260826182000. (29/09/2026, 05:45 p. m.)

### F1 · Formulario único y coincidencia exacta — 7/12 · en curso
- **F1.1 · Coordinar la intención** — 2/3 · en curso · Responsable: Claude (código) · Jhosep (prueba en C1) · F1.1.1 y F1.1.2 hechas. F1.1.3 probada con tests salvo «otra pestaña», que se comprueba a mano en F1.4.1.
    - ✓ F1.1.1 — lib/intencion-contacto.ts + 11 tests (commit 6a920143): cola por pestaña con actor, lead, canal, número, hora, caducidad (2 h) y formulario abierto; sobrevive a la recarga (sessionStorage); una cabeza a la vez. Nadie lo usa todavía: se integra en F1.1.2. (30/09/2026, 10:21 a. m.)
    - ✓ F1.1.2 — AccionesContacto y el receptor del enlace comparten la cola (6ca9944f, e08288ee); contexto mínimo en sessionStorage; auth.tsx la vacía al salir y al cambiar de identidad. Tests: AccionesContacto 19, receptor 13. (30/09/2026, 11:05 a. m.)
    - ◐ F1.1.3 — Probado con tests: foco y hash en los dos órdenes, recarga (sessionStorage + página), remount y cola (la segunda llamada espera a que se cierre la primera). «Otra pestaña» es por diseño (cola por pestaña) y se comprueba a mano en F1.4.1. (30/09/2026, 11:05 a. m.)
- **F1.2 · Recibir el enlace** — 2/3 · en curso · Responsable: Claude · F1.2.1 y F1.2.3 hechas. F1.2.2 con código y tests; se cierra con la prueba del login en C1 (F1.4.2).
    - ✓ F1.2.1 — router.ts (commit 69b4bdf2): #/hoy/llamada/<numero> y #/gestion-diaria/llamada/<numero>; solo se codifica el segmento del número (el + vuelve intacto), acotado a lo que deja un marcador (máx. 40, sin códigos *123#), se suelta al abrir la ficha. 29 tests del router en verde (3 nuevos). (30/09/2026, 10:50 a. m.)
    - ◐ F1.2.2 — App conserva el número en el saneado del hash (69b4bdf2) y el receptor espera a que el store cargue tras el login (e08288ee, test). Falta comprobar en C1 que el enlace sobrevive a iniciar sesión (F1.4.2). (30/09/2026, 11:05 a. m.)
    - ✓ F1.2.3 — components/app/receptor-llamada.tsx montado una vez en App (e08288ee): reutiliza asegurarLead/abrirLead, RegistrarResultado y tareaQueCierra a través de AccionesContacto (la misma encuesta de «Llamar»). 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.3 · Encontrar el lead** — 3/3 · hecha · Responsable: Claude · Cerrada. Pendiente de la prueba real en C1 (F1.4.2) para ver la coincidencia con números de verdad. · Evidencia: 30/09/2026: commits cd4d31b0 y e08288ee; 24 tests de coincidencia (casos sintéticos A, B, C, E, F, D3), 9 de la capa de datos y 13 del receptor, todos en verde.
    - ✓ F1.3.1 — lib/coincidencia-telefono.ts (commit cd4d31b0): E.164 completo de principal y alternativo con las dos formas canónicas de la base (regla del trigger + canonizar_contacto) y el fijo con 0; nunca se recortan 9 dígitos. 24 tests con los casos sintéticos A, B, C, E, F y D3. (30/09/2026, 10:56 a. m.)
    - ✓ F1.3.2 — data/coincidencia-llamada.ts (e08288ee): dígitos nacionales a cartera_pagina_fn con página de 50 (llena → incompleto), leads distintos, error operativo aparte, demo local. 9 tests. (30/09/2026, 11:05 a. m.)
    - ✓ F1.3.3 — Aviso del receptor (e08288ee): único abre la encuesta; ambiguo/incompleto listan candidatos; sin coincidencia e inválido traen búsqueda manual dentro del aviso; error con reintento; reciclado/cliente se avisa. 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.4 · Validar la experiencia** — 0/3 · en curso · Responsable: Claude (checks, guía) · Jhosep (C1) · F1.4.3 casi completa (checks y guía hechos; E2E Docker NOT RUN). F1.4.1 y F1.4.2 esperan una build alcanzable desde C1: no hay .env en este clon y producción no se toca.
    - ◐ F1.4.2 — Jhosep en C1: macro con la URL https://crm.miavance.com/#/gestion-diaria/llamada/{call_number} (Abrir enlaces compatibles o Send Intent). Antes hay que publicar la build de la rama en un entorno alcanzable desde el celular. (30/09/2026, 11:05 a. m.)
    - ◐ F1.4.3 — Checks corridos el 30/09 (fb463967): lint y typecheck en verde; suite 4988 tests, todos en verde salvo cliente-form.test.tsx (y una vez lead-drawer-convertir) que fallan por timeout SOLO bajo la carga de la suite completa en esta máquina y pasan solos (28/28, 33/33), sin tocar nada de F1; cobertura líneas 81,8 % / ramas 75,8 % (umbral 30/26); release-config, push-tasa, build, verify:bundle y dup en verde. Revisión a11y en línea: blancos táctiles 44 px, role=status, label del buscador. Guía macrodroid.md con la URL nueva y la reversa. Falta: E2E Docker (NOT RUN: sin spec pertinente todavía) y cerrar con la prueba real. (30/09/2026, 11:18 a. m.)

### F2 · Núcleo confiable y contrato de datos — 0/13 · pendiente
- **F2.1 · Cerrar el contrato** — 0/3 · pendiente · Responsable: por asignar
- **F2.2 · Diseñar datos e identidad** — 0/4 · pendiente · Responsable: por asignar
- **F2.3 · Aplicar ámbito y permisos** — 0/3 · pendiente · Responsable: por asignar
- **F2.4 · Verificar el núcleo** — 0/3 · pendiente · Responsable: por asignar

### F3 · Captura, puertas y sincronización durable — 0/13 · pendiente
- **F3.1 · Publicar el contrato de puertas** — 0/3 · pendiente · Responsable: por asignar
- **F3.2 · Proteger la ingesta** — 0/3 · pendiente · Responsable: por asignar
- **F3.3 · Persistir y enviar** — 0/4 · pendiente · Responsable: por asignar
- **F3.4 · Probar recuperación** — 0/3 · pendiente · Responsable: por asignar

### F4 · Bandeja y registro conciliado en celular y PC — 0/13 · pendiente
- **F4.1 · Construir la bandeja** — 0/3 · pendiente · Responsable: por asignar
- **F4.2 · Registrar y enlazar** — 0/4 · pendiente · Responsable: por asignar
- **F4.3 · Resolver casos operativos** — 0/3 · pendiente · Responsable: por asignar
- **F4.4 · Validar el circuito** — 0/3 · pendiente · Responsable: por asignar

### F5 · Jev para identificación asistida — 0/15 · pendiente
- **F5.1 · Banco y baseline** — 0/3 · pendiente · Responsable: por asignar
- **F5.2 · Evaluación fuera de línea** — 0/3 · pendiente · Responsable: por asignar
- **F5.3 · Modo sombra** — 0/3 · pendiente · Responsable: por asignar
- **F5.4 · Asistencia opt-in** — 0/3 · pendiente · Responsable: por asignar
- **F5.5 · Decidir activación** — 0/3 · pendiente · Responsable: por asignar

### F6 · Gerencia y calidad de evidencia — 0/12 · pendiente
- **F6.1 · Definir métricas** — 0/3 · pendiente · Responsable: por asignar
- **F6.2 · Medir salud y tiempo** — 0/3 · pendiente · Responsable: por asignar
- **F6.3 · Construir reporte e histórico** — 0/3 · pendiente · Responsable: por asignar
- **F6.4 · Reconciliar y aceptar** — 0/3 · pendiente · Responsable: por asignar

### F7 · Despliegue gradual y operación — 0/12 · pendiente
- **F7.1 · Aceptar el piloto** — 0/3 · pendiente · Responsable: por asignar
- **F7.2 · Preparar soporte y reversa** — 0/3 · pendiente · Responsable: por asignar
- **F7.3 · Publicar por cohortes** — 0/3 · pendiente · Responsable: por asignar
- **F7.4 · Cerrar y mantener** — 0/3 · pendiente · Responsable: por asignar

## Últimos cambios

- 30/09/2026, 11:18 a. m. · F1.4.3: gate del app corrido (lint, typecheck, cobertura 81,8 %, build, bundle, dup en verde; flaky ajeno documentado); a11y del receptor revisada (fb463967). Pendiente: prueba real en C1.
- 30/09/2026, 11:05 a. m. · F1.1.2, F1.2.3, F1.3.2 y F1.3.3 hechas (e08288ee): receptor del enlace + capa de datos; F1.3 cerrada. F1.4 en curso (checks, guía, prueba en C1).
- 30/09/2026, 10:56 a. m. · F1.3.1 hecha (cd4d31b0): coincidencia exacta, 24 tests con los casos sintéticos. F1.3.2 y F1.3.3 en curso junto con el receptor F1.2.3.
- 30/09/2026, 10:50 a. m. · F1.2.1 hecha y F1.2.2 con código (69b4bdf2): ruta por número y su propagación en App. F1.2.3 y F1.3.1 en curso.
- 30/09/2026, 10:41 a. m. · F1.1.2 integrada en AccionesContacto y auth.tsx (6ca9944f, 18 tests); queda abierta hasta el receptor. F1.2 en curso: ruta por número (F1.2.1).
- 30/09/2026, 10:21 a. m. · F1.1.1 hecha: coordinador de la intención de contacto con 11 tests (6a920143); antes, 12 tests de caracterización de AccionesContacto (9b638279). F1.1.2 en curso.
- 30/09/2026, 10:07 a. m. · F1 en curso (F1.1 · F1.1.1): plan corto presentado a Jhosep con archivos, reutilización y verificación; el aterrizaje será Gestión Diaria y la ruta por número servirá también en Hoy. Empieza por tests de caracterización de AccionesContacto.
- 30/09/2026, 09:53 a. m. · Objetivo de negocio escrito en README.md (Jhosep, 30/09): registrar cada llamada sin esfuerzo, foco en salientes; entrantes como ampliación futura. Propuesta #8 para Miguel: acotar F0.3.1 y F2 a salientes.
- 30/09/2026, 09:46 a. m. · F0: MacroDroid 5.67 anotado en REGISTRO y compatibilidad; noche 1/3 superada en C1 (F0.3.3 en curso).
- 29/09/2026, 07:27 p. m. · Cierre de sesión 29/09: corrección de dirección (las 4 llamadas fueron salientes; entrantes NOT RUN). Handoff escrito en docs/plans/llamadas-celular/HANDOFF-2026-09-29.md para retomar mañana.
- 29/09/2026, 07:22 p. m. · F0.3.2: la PWA se abre como app con «Lanzar app → Avance CRM» (PASS vía 3); la notificación con número estaba en la barra (PASS). Guía actualizada con la vía 3 y cómo obtener el paquete para F1.
- 29/09/2026, 07:06 p. m. · F0.3 en curso: prueba de humo en C1. Número capturado en 3/3 llamadas (PASS preliminar); «Open Website» abre Chrome y no la PWA (FAIL vía 1); notificación ejecutada pero no vista (por confirmar). Registrado en REGISTRO.md y compatibilidad.md; guía actualizada con la URL de Gestión Diaria y la vía Send Intent.
- 29/09/2026, 06:16 p. m. · F0.1: C1 (Samsung Galaxy A16, Android 16, Chrome) registrado en REGISTRO.md y compatibilidad.md; PWA y MacroDroid instalados; Jhosep como analista piloto y soporte. Sigue la macro y la prueba de humo.
- 29/09/2026, 05:45 p. m. · F0.4.2 hecha: ejemplos sintéticos de teléfonos (23 casos) verificados contra las reglas de canonización de la base. F0.1.3 y F0.4.1 en curso; el resto de F0 espera celulares y personas.
- 29/09/2026, 05:42 p. m. · F0 en curso: carpeta versionada docs/plans/llamadas-celular/ (PLAN.md aprobado, AVANCE.md, estado.json) y materiales del piloto en docs/gestion-diaria/piloto-telefonia/ (guía MacroDroid, REGISTRO, compatibilidad, ejemplos sintéticos).
