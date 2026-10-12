# Llamadas desde el celular — PR 215 aprobado y activación pendiente

> Nota histórica anterior a la instalación. Estado vigente: [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]].

07/10/2026. Relacionado: [[Telefonia CRM - plan por fases y Jev asistido (2026-09-29)]], [[Llamadas desde el celular - analisis del PR 190 (2026-10-06)]], [[Inicio]].

El usuario informó que Jhosep decía tener todo listo. Codex verificó la entrega y **aprobó técnicamente el PR #215** sobre `d7dfd5b459914ccd2ff46c1633cde25a5f725e70`. [Revisión publicada](https://github.com/avanza-digital/avancecorp-crm/pull/215#pullrequestreview-5448406485).

El P2 anterior está resuelto: el diálogo distingue alta de rotación; al rotar conserva `cola_llamadas` y `errores_llamadas`. Gerencia mantiene el permiso exclusivo de la pantalla. La tarjeta y sus cinco RPC quedan apagadas en sesión real con `LLAMADAS_CELULAR_APROBADAS = false`. El PR no contiene migraciones.

Verificación local del HEAD exacto: `npm run check` PASS (398 archivos, 6366/6366 pruebas, lint/tipos/build/bundle y demás controles); Docker E2E de `config-celulares.spec.ts` y `config-demo.spec.ts`, 4/4 PASS. Revisión Claude focalizada PASS, evaluada por Codex; `git merge-tree` sin conflictos con Main `ba702c61`. No hubo cambios de código ni nuevos commits. El PR seguía abierto y en borrador al aprobarlo: **esta sesión no lo fusionó**.

Producción comprobada otra vez en solo lectura: 0 migraciones `crm_llamadas_celular%`, tablas de asignaciones/eventos/salud ausentes, sin Edge `crm-llamadas-ingesta`; SLA `activo`, revisión 1. No se aplicaron migraciones, no hubo release ni altas productivas.

Jhosep entregó seguimiento, guía de activación y decisiones en `crm/llamadas-f4d-activacion-20261007` (HEAD consultado `a430d770`), sin modificar el #215. El plan está en **31/102 tareas cerradas**; F1 aceptada, F0/F3 físicos incompletos y F4–F7 sin aceptación final. Nuevas pruebas reportadas de C1 contra el receptor: 429, fijo, pantalla bloqueada y ráfaga; no equivalen a probar la Edge real.

Próximo orden: integrar #215; ensayo local con SLA activo y las doce desde LF; aplicación por el flujo autorizado, Edge y release; luego activación física C1 y restantes equipos. Permanecen decisiones de Miguel: #18 Pro, #16 aceptar F0 con salientes y dejar entrantes a su fase, #17/A1–A7 y ubicación de F4-e. Jhosep reporta Pro a S/19 visto en C1 y vencimiento gratuito aproximado 09/10 15:50 Lima; verificar vigencia antes de actuar. La aprobación del PR no aprueba esas decisiones ni declara completo el plan.
