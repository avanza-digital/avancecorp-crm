# Llamadas desde el celular - F1 receptor por URL y ajuste Android (2026-09-30)

Estado: F1 del plan «Llamadas desde el celular al CRM» (Versión 3 aprobada por Miguel)
terminada en la rama `feat/llamadas-f0` y aprobada y fusionada a `main` por Miguel (PR #148,
30/09 21:41 UTC), pero **NO activa en producción**: al publicar la corrección de documentos,
Miguel decidió «Solo documentos; mantener F1 pendiente» y el PR #151 retiró temporalmente su
activación (el receptor no se monta; módulos, rutas y pruebas siguen en `main`). Reactivarla
requiere su autorización. 🔑 Lección (01/10): para dar por viva una función no basta encontrar
parte de su código en el bundle publicado; hay que comprobar su punto de entrada en el commit
construido y leer la descripción del PR de publicación. F0 (piloto con el celular C1) sigue
midiendo.

Objetivo de negocio (Jhosep, 30/09): que los vendedores registren cada llamada sin
esfuerzo. Al colgar, MacroDroid abre `https://crm.miavance.com/#/gestion-diaria/llamada/{call_number}`;
el CRM encuentra al lead por el número y abre **la misma encuesta de «Llamar»**. Según el
resultado se cierra la tarea o se abre la siguiente; el analista elige siempre el resultado.
Alcance: solo salientes (las entrantes son ampliación futura, propuesta #8).

Cómo funciona F1 (solo pantalla, sin tablas ni puertas nuevas): una **cola de intenciones
de contacto por pestaña** (`lib/intencion-contacto.ts`, sessionStorage) que `AccionesContacto`
y el receptor del enlace comparten; el receptor (`components/app/receptor-llamada.tsx`,
montado una vez en `App`) lee el número, lo quita del hash, espera al store y busca
candidatos con los dígitos nacionales por `crm.cartera_pagina_fn` (INVOKER, RLS); compara
exacto con las **dos formas canónicas** de la base (trigger `private.normalizar_telefono`
y `canonizar_contacto`, más el fijo con 0). Un solo lead vivo → la tarjeta «Ahora» de Mi día
toma la intención (600 ms de margen) o se abre la ficha con el diálogo; varios → candidatos;
ninguno → aviso con buscador dentro (en el celular no hay barra). Con una encuesta abierta la
siguiente llamada espera en la cola y se atiende sola al cerrar. Nunca se autoselecciona.

🔑 Lo no obvio del celular (Samsung A16, Android 16, MacroDroid 5.67 de Play):
- `{call_number}` llega en salientes; no hay duración ni dirección en el trigger «Call Ended».
- La URL solo abre la **app instalada** si en Android se activa «CRM Avance Corp → Definir
  como predeterminada → Abrir vínculos admitidos» **y** el dominio `crm.miavance.com` en
  «Direcciones web admitidas». Sin eso abre Chrome. No hizo falta `packageName` ni Send Intent.
- El Chrome corporativo fuerza HTTPS (`ERR_SSL_PROTOCOL_ERROR` contra un servidor http de
  pruebas): o se apaga «Usar siempre conexiones seguras», o se sirve con certificado propio.
- «Parámetros de codificación de URL» de la acción «Abrir sitio web» debe ir desmarcado:
  codificaría el `#` y la app no recibiría la ruta.

Decisiones tomadas (Jhosep): F1 arrancó antes de cerrar F0; aterrizaje en Gestión Diaria con
la ruta válida también en Hoy (propuesta #9 para Miguel); `vitest.config.ts` con 15 s por
test porque la suite completa tumbaba por carga un archivo distinto cada vez en el taller
Windows; F1 queda en rama hasta el OK de Miguel. Observación para Miguel: un lead que no es
el de «Ahora» abre la ficha con el diálogo (por diseño; posible ajuste: abrir en la tarjeta).

Verificación: unit 5093 con `main` fusionado; cobertura 81,8 %; build, bundle y dup PASS;
E2E Docker 285 passed, 26 skipped, 1 flaky ajeno, 0 failed (`scripts/e2e-docker.sh` no arranca
en Windows: se corrió el `docker run` a mano); Playwright contra la demo (login → «Ahora»,
cola, dos pestañas, otra cuenta, supervisor, hash limpio); prueba real en C1 con la build de la
rama servida desde el PC (macro real → Chrome → CRM → aviso con el número; build real con un
lead propio, sin guardar). Registro sin números: `docs/gestion-diaria/piloto-telefonia/REGISTRO.md`.

Siguiente: Miguel decide publicar F1 (`npm run release:crm` → preflight → `/release-crm`;
antes, `main` debe contener lo vivo, hoy la rama de rescate de Coordinación, o el preflight
rechaza) y revisa `PROPUESTAS-DE-AJUSTE.md` #1–#9; al publicar, la macro pasa a la URL con
`{call_number}`. F2 (núcleo de eventos de llamada en la base) tiene su plan corto
en `docs/plans/llamadas-celular/F2-PLAN-CORTO.md`, pendiente de sus 7 decisiones.

Evidencia: `CRM-Avance-Corp/docs/plans/llamadas-celular/` (PLAN aprobado con casillas,
AVANCE, HANDOFF-2026-09-30) y tablero vivo https://claude.ai/artifact/Q3GmV9m6Cy2GPQGKAbNy8M.

Relacionadas: [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]],
[[Gestion Diaria - vuelta persistente verificada localmente (2026-09-30)]],
[[Auditoria ACID, CAP e idempotencia del CRM (2026-09-24)]], [[Inicio]].
