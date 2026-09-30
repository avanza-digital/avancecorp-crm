# Avance — Llamadas desde el celular al CRM

Actualizado: 30/09/2026, 04:46 p. m. (hora de Lima). Generado por `actualizar-avance.mjs` desde `estado.json`; no se edita a mano.

Tablero vivo (el que vale, se actualiza al instante): https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M · Plan completo: `PLAN.md` en esta carpeta.

**Lo último:** 30/09 21:46 UTC: Miguel aprobó y fusionó el PR #148 a main (6ace8487, 21:41 UTC): F1 ya está en main, pero NO en producción: el sitio vive build-20260930T213751470Z (Coordinación, construida a las 21:37 desde la rama de rescate sobre el vivo 57e7b3b4), sin F1. La macro sigue con la URL sin número hasta el release. Antes de publicar F1, main tiene que contener lo vivo (hoy no contiene 57e7b3b4 ni la rama de rescate) o el preflight rechazará la build. F2 sigue como análisis: plan corto afinado con los tres mapas, a la espera de las 7 decisiones de Miguel.

**Total:** 13 de 102 tareas · 1 de 8 fases hechas.

| Fase | Tareas | Estado | Subfases hechas |
| --- | --- | --- | --- |
| F0 · Piloto y línea base | 1/12 | En curso | 0/4 |
| F1 · Formulario único y coincidencia exacta | 12/12 | Hecha | 4/4 |
| F2 · Núcleo confiable y contrato de datos | 0/13 | En curso | 0/4 |
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

### F1 · Formulario único y coincidencia exacta — 12/12 · hecha · 30/09/2026, rama feat/llamadas-f0 (9b638279…5d9f21c3): coordinador, ruta, coincidencia exacta y receptor con 4998 tests en verde, E2E Docker 285 passed, prueba física en C1 y aceptación de §7 cumplida (ambos órdenes una sola vez, edición no se pierde, fijo/internacional, incompleto nunca autoselecciona, RLS, tarea propia). Sin tablas ni puertas nuevas. 30/09 21:41 UTC: PR #148 aprobado y fusionado a main por Miguel (6ace8487). Sigue SIN publicar: producción vive build-20260930T213751470Z (rama de rescate de Coordinación, sin F1); el release con preflight es el siguiente paso de Miguel.
- **F1.1 · Coordinar la intención** — 3/3 · hecha · Responsable: Claude (código) · Jhosep (prueba en C1) · Cerrada. · Evidencia: 30/09/2026: commits 6a920143, 6ca9944f, e08288ee, 5d9f21c3; tests del coordinador (13) y de AccionesContacto (20); recarga, remount, ambos órdenes, cola y dos pestañas vistos en el navegador.
    - ✓ F1.1.1 — lib/intencion-contacto.ts + 11 tests (commit 6a920143): cola por pestaña con actor, lead, canal, número, hora, caducidad (2 h) y formulario abierto; sobrevive a la recarga (sessionStorage); una cabeza a la vez. Nadie lo usa todavía: se integra en F1.1.2. (30/09/2026, 10:21 a. m.)
    - ✓ F1.1.2 — AccionesContacto y el receptor del enlace comparten la cola (6ca9944f, e08288ee); contexto mínimo en sessionStorage; auth.tsx la vacía al salir y al cambiar de identidad. Tests: AccionesContacto 19, receptor 13. (30/09/2026, 11:05 a. m.)
    - ✓ F1.1.3 — Probado con tests (coordinador 13, AccionesContacto 20, receptor 18, Mi día 81) y en el navegador contra la demo (30/09): foco y hash en los dos órdenes, recarga (la intención sobrevive y se vuelve a ofrecer), remount, otra pestaña (cola por pestaña: la segunda pestaña no se entera) y cola (TERESA abierta → llega JUAN → espera → al cerrar se abre solo). Dos hallazgos corregidos por el camino: la carrera de 0 ms con la tarjeta «Ahora» y la intención delegada que moría al desmontarse las acciones (5d9f21c3). (30/09/2026, 03:20 p. m.)
- **F1.2 · Recibir el enlace** — 3/3 · hecha · Responsable: Claude · Cerrada: ruta, propagación en App y receptor en Hoy y Gestión Diaria. · Evidencia: 30/09/2026: commits 69b4bdf2 y e08288ee; router 29 tests, App 10, receptor 15; en C1 la URL con número sobrevivió al login.
    - ✓ F1.2.1 — router.ts (commit 69b4bdf2): #/hoy/llamada/<numero> y #/gestion-diaria/llamada/<numero>; solo se codifica el segmento del número (el + vuelve intacto), acotado a lo que deja un marcador (máx. 40, sin códigos *123#), se suelta al abrir la ficha. 29 tests del router en verde (3 nuevos). (30/09/2026, 10:50 a. m.)
    - ✓ F1.2.2 — App conserva el número al sanear el hash (69b4bdf2) y el receptor espera a que cargue el store (e08288ee). Comprobado en C1 el 30/09: la URL con número sobrevivió al login de la demo (al entrar, el receptor ya tenía el 911 223 344). En la demo, además, espera a que lleguen los leads (3065b84e). (30/09/2026, 01:05 p. m.)
    - ✓ F1.2.3 — components/app/receptor-llamada.tsx montado una vez en App (e08288ee): reutiliza asegurarLead/abrirLead, RegistrarResultado y tareaQueCierra a través de AccionesContacto (la misma encuesta de «Llamar»). 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.3 · Encontrar el lead** — 3/3 · hecha · Responsable: Claude · Cerrada. Pendiente de la prueba real en C1 (F1.4.2) para ver la coincidencia con números de verdad. · Evidencia: 30/09/2026: commits cd4d31b0 y e08288ee; 24 tests de coincidencia (casos sintéticos A, B, C, E, F, D3), 9 de la capa de datos y 13 del receptor, todos en verde.
    - ✓ F1.3.1 — lib/coincidencia-telefono.ts (commit cd4d31b0): E.164 completo de principal y alternativo con las dos formas canónicas de la base (regla del trigger + canonizar_contacto) y el fijo con 0; nunca se recortan 9 dígitos. 24 tests con los casos sintéticos A, B, C, E, F y D3. (30/09/2026, 10:56 a. m.)
    - ✓ F1.3.2 — data/coincidencia-llamada.ts (e08288ee): dígitos nacionales a cartera_pagina_fn con página de 50 (llena → incompleto), leads distintos, error operativo aparte, demo local. 9 tests. (30/09/2026, 11:05 a. m.)
    - ✓ F1.3.3 — Aviso del receptor (e08288ee): único abre la encuesta; ambiguo/incompleto listan candidatos; sin coincidencia e inválido traen búsqueda manual dentro del aviso; error con reintento; reciclado/cliente se avisa. 13 tests. (30/09/2026, 11:05 a. m.)
- **F1.4 · Validar la experiencia** — 3/3 · hecha · Responsable: Claude (checks, guía) · Jhosep (C1) · Cerrada. · Evidencia: 30/09/2026: navegador del PC contra la demo (4 caminos, roles, otra cuenta, cola, dos pestañas); C1 con la build de la rama (macro real, login, build real sin guardar); gate del app en verde; E2E Docker 285 passed / 1 flaky ajeno / 0 failed.
    - ✓ F1.4.1 — Verificado en el navegador del PC contra la demo (30/09): analista («Ahora» y ficha), supervisor con lead de su equipo (ficha + diálogo, sin casilla de tarea ajena), otra cuenta (al cerrar sesión la cola queda vacía), formulario en edición (la segunda llamada espera), dos pestañas (independientes) y limpieza del hash en todos los casos. Tarea propia: regla de tareaQueCierra cubierta por tests. En C1: flujo completo con demo y build real. (30/09/2026, 03:20 p. m.)
    - ✓ F1.4.2 — Retorno real en Android validado en C1 el 30/09 con la build de la rama servida desde el PC: (1) macro de MacroDroid con {call_number} → Chrome → CRM demo → aviso con el número marcado; (2) URL con número → login → encuesta de la persona de «Ahora»; (3) build real con la cuenta de Jhosep → encuesta de un lead propio (ficha + diálogo), cerrada sin registrar; (4) con el ajuste de Android la URL abre la app instalada. La alternativa de notificación local NO APLICA: la URL sí abre la PWA (plan §6, «Dos decisiones separadas»). Hallazgo corregido por el camino: la demo buscaba antes de cargar (3065b84e). Registro en REGISTRO.md §5b. (30/09/2026, 02:25 p. m.)
    - ✓ F1.4.3 — PASS: lint, typecheck, suite completa (4998 tests), cobertura líneas 81,8 % / ramas 75,8 %, build, verify:bundle y dup; a11y del receptor revisada en línea; E2E en Docker (imagen playwright v1.61.1, 2 workers): 285 passed, 26 skipped, 1 flaky ajeno (gestion-diaria-pulso, foco de Gerencia; pasó al reintentar), 0 failed, 12,5 min. Guía macrodroid.md con la URL y la reversa. Nota: scripts/e2e-docker.sh no arranca en Windows (rutas de Git Bash al Node de Windows); se corrió el mismo docker run a mano. Revisión Codex: no (LEVEL 2, 0–1 permitido). (30/09/2026, 03:37 p. m.)

### F2 · Núcleo confiable y contrato de datos — 0/13 · en curso
- **F2.1 · Cerrar el contrato** — 0/3 · en curso · Responsable: Claude (borrador) · Miguel (decide) · Borrador del contrato en F2-PLAN-CORTO.md: 7 decisiones para Miguel (elegibilidad, entrantes, descarte motivado, Deshacer, hora y atribución, retención, lead reasignado). La #4 ya casa con lo que Deshacer hace hoy (no borra ni desenlaza; 24 h, solo el autor). Sin SQL hasta su OK.
- **F2.2 · Diseñar datos e identidad** — 0/4 · en curso · Responsable: Claude (borrador) · Miguel (aprueba) · Diseño de datos afinado con los tres mapas de solo lectura (30/09): tablas llamadas_celular_* (asignaciones con credencial en hash, eventos con origen + hash inmutables, enlace 1:1, política de retención); el enlace va por el actividad_id que devuelve v4, «autor compatible» = ámbito sobre el lead, efectos deshechos derivados de deshecho_en; F2 aditiva (no toca actividades ni funciones selladas); RLS sin policies con puertas DEFINER; auditoría con log_audit_sin_secretos; purga con cron; molde 20260927012948; reversa que conserva los hechos. Espera el OK de Miguel.
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

- 30/09/2026, 04:46 p. m. · Miguel aprobó y fusionó el PR #148 a main (6ace8487, 21:41 UTC): F1 en main, sin publicar (producción vive la build de Coordinación de las 21:37, sin F1). Su merge de main a la rama quedó integrado (b4f49494). Aviso: main no contiene aún lo vivo (57e7b3b4 / rama de rescate); hay que fusionarlo antes del release de F1 o el preflight rechaza.
- 30/09/2026, 04:41 p. m. · F2-PLAN-CORTO.md afinado con los tres mapas de solo lectura: enlace por actividad_id de v4, autor por ámbito, Deshacer sin desenlazar, F2 aditiva, credencial con hash, idempotencia P0409, RLS sin policies, auditoría sin teléfonos, purga, molde de migración, reversa y contrato de ingesta para F3. Sigue sin SQL hasta el OK de Miguel.
- 30/09/2026, 04:21 p. m. · F2 en curso como análisis: F2-PLAN-CORTO.md (contrato con 7 decisiones para Miguel, diseño de datos, núcleo, RLS, verificación, orden de PRs). F2.1 y F2.2 en curso. Sin código ni SQL.
- 30/09/2026, 04:08 p. m. · Publicación de F1 preparada para Miguel: PR #148 a main (https://github.com/avanza-digital/avancecorp-crm/pull/148) con IMPLEMENTED/REVIEW/VERIFICATION/RISKS y los pasos manuales del release. main fusionado en la rama (d326c6b9). Nada publicado.
- 30/09/2026, 03:37 p. m. · F1.4.3 hecha y F1 cerrada: E2E Docker 285 passed / 26 skipped / 1 flaky ajeno / 0 failed (12,5 min). F1 completa en la rama; sin publicar.
- 30/09/2026, 03:20 p. m. · F1.1.3 y F1.4.1 hechas (navegador contra la demo + tests); F1.1 cerrada. Correcciones: 600 ms para que «Ahora» tome la intención, la cola se atiende sola, la intención delegada es de «Mi día», sin duplicados sobre un lead abierto (5d9f21c3). Vitest a 15 s por test (39172c6e).
- 30/09/2026, 02:25 p. m. · F1.4.2 hecha: prueba real en C1 con la build de la rama (macro real, login, build real con lead propio sin guardar). Macro devuelta a producción. Observación de Jhosep: para un lead que no es el de «Ahora» se abre la ficha con el diálogo (por diseño; posible ajuste para Miguel).
- 30/09/2026, 01:58 p. m. · C1: la macro real (Abrir sitio web con {call_number}) abrió Chrome en la demo y el receptor mostró el aviso con el número marcado. El número viaja de MacroDroid al CRM. REGISTRO.md §5b.
- 30/09/2026, 01:13 p. m. · C1: tras la corrección, la URL con número abrió la encuesta de TERESA en «Ahora» en el celular (demo). Registrado en REGISTRO.md §5b.
- 30/09/2026, 01:05 p. m. · C1: la URL con número sobrevive al login (F1.2.2 hecha, F1.2 cerrada). Hallazgo: en la demo la búsqueda corría antes de cargar los leads; corregido (3065b84e, 15 tests).
- 30/09/2026, 12:51 p. m. · F1.4.1 verificada en el navegador del PC (demo): 4 caminos del receptor y limpieza del hash. F1.4.2: build servida desde el PC por HTTP y HTTPS; C1 fuerza HTTPS (ERR_SSL_PROTOCOL_ERROR con http).
- 30/09/2026, 12:21 p. m. · F0.3.2 en C1: la URL abre la PWA con el ajuste de Android «Abrir vínculos admitidos» + dominio (PASS vía 1). Registrado en REGISTRO.md, compatibilidad.md y la guía. Resuelve cómo le llega el número a la app en F1.
- 30/09/2026, 11:34 a. m. · Push de la rama (8f25ad34): pre-push con la suite completa en verde tras dar más tiempo a cliente-form.test (decisión de Jhosep). Próximo: build de prueba servida desde el PC para C1.
- 30/09/2026, 11:18 a. m. · F1.4.3: gate del app corrido (lint, typecheck, cobertura 81,8 %, build, bundle, dup en verde; flaky ajeno documentado); a11y del receptor revisada (fb463967). Pendiente: prueba real en C1.
- 30/09/2026, 11:05 a. m. · F1.1.2, F1.2.3, F1.3.2 y F1.3.3 hechas (e08288ee): receptor del enlace + capa de datos; F1.3 cerrada. F1.4 en curso (checks, guía, prueba en C1).
