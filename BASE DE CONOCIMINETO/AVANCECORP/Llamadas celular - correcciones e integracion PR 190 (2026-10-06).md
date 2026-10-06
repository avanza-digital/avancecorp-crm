# Llamadas celular — correcciones e integración del PR 190

Miguel encargó a Codex corregir el informe y devolver el trabajo a Jhosep. Se integra su rama `crm/llamadas-190-integrar-jhosep-20261006` (`93374fb4`) y `main` (`afae7b59`); las dos migraciones que preparó pasan a ser la décima y la undécima. La correctiva `20261006162813` queda duodécima.

Decisiones conservadas: no guardar contactos vetados/clientes ni números tomados por otro ámbito; el antiguo dueño no ve ni toca una llamada ajena sobre un reutilizable. La fuente real y el guardado v5 del analista quedan conectados. No implica publicación ni activación de C1.

Verificado: reducido415/415, app6245, Docker17/17, llamadas197/197 en esquema completo. La matriz global mantiene ocho fallos previos ajenos a llamadas. Detalles y límites: `CRM-Avance-Corp/docs/plans/llamadas-celular/CIERRE-CORRECCIONES-20261006.md`.

Relacionadas: [[Llamadas desde el celular - analisis del PR 190 (2026-10-06)]], [[Inicio]].
