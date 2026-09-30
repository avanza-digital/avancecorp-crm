# Avance — Llamadas desde el celular al CRM

Actualizado: 30/09/2026, 01:05 p. m. (hora de Lima). Generado por `actualizar-avance.mjs` desde `estado.json`; no se edita a mano.

Tablero vivo (el que vale, se actualiza al instante): https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M · Plan completo: `PLAN.md` en esta carpeta.

**Lo último:** 30/09 18:05 UTC: primer intento real en C1 — la URL con número sobrevivió al login (F1.2.2 hecha, F1.2 cerrada), pero la demo buscó antes de cargar sus leads y dijo «ningún lead»: corregido en 3065b84e (espera a que haya leads) y subido; Jhosep reintenta. En el PC los cuatro caminos ya se vieron funcionar.

**Total:** 9 de 102 tareas · 0 de 8 fases hechas.

| Fase | Tareas | Estado | Subfases hechas |
| --- | --- | --- | --- |
| F0 · Piloto y línea base | 1/12 | En curso | 0/4 |
| F1 · Formulario único y coincidencia exacta | 8/12 | En curso | 2/4 |
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
    - ◐ F0.1.3 — C1 completo: PWA instalada, permisos Teléfono y Registro de llamadas confirmados por evidencia, «Aparecer encima», batería sin restricciones y, desde el 30/09, «Abrir vínculos admitidos» + dominio crm.miavance.com en la app (necesario para que la URL la abra). Aviso: no aplica al propio responsable. Pendiente para los próximos celulares. (30/09/2026, 12:21 p. m.)
- **F0.2 · Medir la línea base** — 0/3 · pendiente · Responsable: por asignar
- **F0.3 · Probar los equipos** — 0/3 · en curso · Responsable: Jhosep · C1: prueba de humo superada; noche 1/3 sin caerse; 30/09: la URL abre la PWA con el ajuste de Android (PASS vía 1). Prioridad: salientes. Pendiente: 6 salientes más, casos especiales, bloqueo/batería/reinicio/sin red y dos noches; entrantes solo si ocurren.
    - ◐ F0.3.1 — C1: 4 salientes con número (29/09). Foco del negocio (Jhosep, 30/09): las llamadas que el vendedor HACE; las entrantes se observan si ocurren, sin exigirlas (posible ampliación futura; recorte propuesto a Miguel, #8). Faltan 6 salientes y los casos atendida/no atendida/cancelada. (30/09/2026, 09:53 a. m.)
    - ◐ F0.3.2 — C1: notificación con número y nombre PASS. Apertura de la PWA por URL: PASS el 30/09 con el ajuste de Android «CRM Avance Corp → Abrir vínculos admitidos + dominio crm.miavance.com» («Open Website» abre la app sin barra de direcciones); sin el ajuste abre Chrome (29/09). «Lanzar app» abre la app pero no lleva número; «Send Intent» no hizo falta. Faltan oculto, fijo, internacional, doble SIM y login. (30/09/2026, 12:21 p. m.)
    - ◐ F0.3.3 — C1, noche 1 de 3 (29→30/09): MacroDroid activo por la mañana y la macro encendida; no hubo llamadas nocturnas que verificar. Faltan 2 noches, pantalla bloqueada, batería baja, reinicio y sin red. (30/09/2026, 09:46 a. m.)
- **F0.4 · Cerrar viabilidad** — 1/3 · en curso · Responsable: por asignar · Guía, registro y matriz entregados; falta la evidencia por equipo del piloto y la decisión.
    - ◐ F0.4.1 — REGISTRO.md, macrodroid.md y compatibilidad.md creados; falta la evidencia por equipo.
    - ✓ F0.4.2 — docs/gestion-diaria/piloto-telefonia/ejemplos-sinteticos.md: 23 casos en 6 grupos (exactos, históricos, compartidos y reciclados, contexto contradictorio, internacionales/ocultos/inválidos, completitud), reglas contrastadas con las migraciones 20260709000001 y 20260826182000. (29/09/2026, 05:45 p. m.)

### F1 · Formulario único y coincidencia exacta — 8/12 · en curso
- **F1.1 · Coordinar la intención** — 2/3 · en curso · Responsable: Claude (código) · Jhosep (prueba en C1) · F1.1.1 y F1.1.2 hechas. F1.1.3 probada con tests salvo «otra pestaña», que se comprueba a mano en F1.4.1.
    - ✓ F1.1.1 — lib/intencion-contacto.ts + 11 tests (commit 6a920143): cola por pestaña con actor, lead, canal, número, hora, caducidad (2 h) y formulario abierto; sobrevive a la recarga (sessionStorage); una cabeza a la vez. Nadie lo usa todavía: se integra en F1.1.2. (30/09/2026, 10:21 a. m.)
    - ✓ F1.1.2 — AccionesContacto y el receptor del enlace comparten la cola (6ca9944f, e08288ee); contexto mínimo en sessionStorage; auth.tsx la vacía al salir y al cambiar de identidad. Tests: AccionesContacto 19, receptor 13. (30/09/2026, 11:05 a. m.)
    - ◐ F1.1.3 — Probado con tests: foco y hash en los dos órdenes, recarga (sessionStorage + página), remount y cola (la segunda llamada espera a que se cierre la primera). «Otra pestaña» es por diseño (cola por pestaña) y se comprueba a mano en F1.4.1. (30/09/2026, 11:05 a. m.)
- **F1.2 · Recibir el enlace** — 3/3 · hecha · Responsable: Claude · Cerrada: ruta, propagación en App y receptor en Hoy y Gestión Diaria. · Evidencia: 30/09/2026: commits 69b4bdf2 y e08288ee; router 29 tests, App 10, receptor 15; en C1 la URL con número sobrevivió al login.
    - ✓ F1.2.1 — router.ts (commit 69b4bdf2): #/hoy/llamada/<numero> y #/gestion-diaria/llamada/<numero>; solo se codifica el segmento del número (el + vuelve intacto), acotado a lo que deja un marcador (máx. 40, sin códigos *123#), se suelta al abrir la ficha. 29 tests del router en verde (3 nuevos). (30/09/2026, 10:50 a. m.)
    - ✓ F1.2.2 — App conserva el número al sanear el hash (69b4bdf2) y el receptor espera a que cargue el store (e08288ee). Comprobado en C1 el 30/09: la URL con número sobrevivió al login de la demo (al entrar, el receptor ya tenía el 911 223 344). En la demo, además, espera a que lleguen los leads (3065b84e). (30/09/2026, 01:05 p. m.)
    - ✓ F1.2.3 — components/app/receptor-llamada.tsx montado una vez en App (e08288ee): reutiliza asegurarLead/abrirLead, RegistrarResultado y tareaQueCierra a través de AccionesContacto (la misma encuesta de «Llamar»). 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.3 · Encontrar el lead** — 3/3 · hecha · Responsable: Claude · Cerrada. Pendiente de la prueba real en C1 (F1.4.2) para ver la coincidencia con números de verdad. · Evidencia: 30/09/2026: commits cd4d31b0 y e08288ee; 24 tests de coincidencia (casos sintéticos A, B, C, E, F, D3), 9 de la capa de datos y 13 del receptor, todos en verde.
    - ✓ F1.3.1 — lib/coincidencia-telefono.ts (commit cd4d31b0): E.164 completo de principal y alternativo con las dos formas canónicas de la base (regla del trigger + canonizar_contacto) y el fijo con 0; nunca se recortan 9 dígitos. 24 tests con los casos sintéticos A, B, C, E, F y D3. (30/09/2026, 10:56 a. m.)
    - ✓ F1.3.2 — data/coincidencia-llamada.ts (e08288ee): dígitos nacionales a cartera_pagina_fn con página de 50 (llena → incompleto), leads distintos, error operativo aparte, demo local. 9 tests. (30/09/2026, 11:05 a. m.)
    - ✓ F1.3.3 — Aviso del receptor (e08288ee): único abre la encuesta; ambiguo/incompleto listan candidatos; sin coincidencia e inválido traen búsqueda manual dentro del aviso; error con reintento; reciclado/cliente se avisa. 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.4 · Validar la experiencia** — 0/3 · en curso · Responsable: Claude (checks, guía) · Jhosep (C1) · F1.4.1 verificada en el navegador del PC (4 caminos + limpieza del hash); F1.4.2 en prueba desde C1 con la build servida por HTTPS desde el PC; F1.4.3 con checks y guía hechos (E2E Docker NOT RUN).
    - ◐ F1.4.1 — Verificado en el navegador del PC (demo, 30/09): número de la persona de «Ahora» → formulario en la tarjeta; número de otro lead → su ficha con el diálogo; sin coincidencia → aviso con búsqueda manual que abre la ficha elegida; descartada → aviso «figura en…»; el hash queda limpio en todos. Capturas en .playwright-mcp/f1-*.png (local). Faltan: roles, otra cuenta, formulario en edición, dos pestañas (en el celular). (30/09/2026, 12:51 p. m.)
    - ◐ F1.4.2 — C1 (30/09): la URL abre la PWA con el ajuste de Android (PASS). Build de la rama servida desde el PC (demo :5173/:5174, real :4173/:4174; HTTPS porque el Chrome corporativo fuerza HTTPS). Primer intento en C1: el número sobrevivió al login pero la demo buscó antes de cargar sus leads → corregido (3065b84e), reintento pendiente. Falta el flujo completo en el celular y la alternativa de notificación local. (30/09/2026, 01:05 p. m.)
    - ◐ F1.4.3 — Checks del 30/09: lint, typecheck, suite completa 322 archivos / 4988 tests en verde (cliente-form.test necesitaba más tiempo bajo carga: 15 s por test, decisión de Jhosep, 8f25ad34), cobertura líneas 81,8 % / ramas 75,8 %, build, verify:bundle y dup en verde; rama subida a origin (8f25ad34). A11y del receptor revisada en línea (fb463967). Guía macrodroid.md con la URL nueva y la reversa. Falta: E2E Docker (NOT RUN: sin spec) y cerrar tras la prueba real en C1. (30/09/2026, 11:34 a. m.)

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

- 30/09/2026, 01:05 p. m. · C1: la URL con número sobrevive al login (F1.2.2 hecha, F1.2 cerrada). Hallazgo: en la demo la búsqueda corría antes de cargar los leads; corregido (3065b84e, 15 tests).
- 30/09/2026, 12:51 p. m. · F1.4.1 verificada en el navegador del PC (demo): 4 caminos del receptor y limpieza del hash. F1.4.2: build servida desde el PC por HTTP y HTTPS; C1 fuerza HTTPS (ERR_SSL_PROTOCOL_ERROR con http).
- 30/09/2026, 12:21 p. m. · F0.3.2 en C1: la URL abre la PWA con el ajuste de Android «Abrir vínculos admitidos» + dominio (PASS vía 1). Registrado en REGISTRO.md, compatibilidad.md y la guía. Resuelve cómo le llega el número a la app en F1.
- 30/09/2026, 11:34 a. m. · Push de la rama (8f25ad34): pre-push con la suite completa en verde tras dar más tiempo a cliente-form.test (decisión de Jhosep). Próximo: build de prueba servida desde el PC para C1.
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
