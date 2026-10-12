# Llamadas desde el celular — revisión detallada del PR #235

Relacionado: [[Inicio]], [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]], [[Llamadas desde el celular - reparto con Jhosep y analisis H-P5 H-P10 (2026-10-09)]].

PR: https://github.com/avanza-digital/avancecorp-crm/pull/235
Cabeza revisada y reconfirmada: `7c28e2963afa22615bf3cc57e7e1f184e55c733a`; base `f3efe078`. Solo seis documentos, 73 adiciones y 46 eliminaciones. No se fusionó ni publicó durante esta revisión; tampoco se enviaron comentarios nuevos al PR.

## Dictamen

CHANGES_REQUESTED: un P2 operativo en SOPORTE.md:71. Ante el error de guardado «Solo una tarea de llamada pendiente…», recomienda primero cerrar el CRM. Los campos aún no guardados viven solo en useState y se pierden al desmontar/recargar (H-P5 ya reproducido). Debe proteger/guardar el borrador y comprobar confirmación ANTES de reiniciar o actualizar. Además ese error también aparece con versión actual si la tarea dejó de estar pendiente: completada y cancelada reproducidas con el store. Ver store.tsx:3180–3185. No diagnosticar automáticamente una versión vieja.

P3 de consistencia: estado.json:99 sigue afirmando como causa que la segunda encuesta recarga la app. El análisis y el acuse 6087325109 establecen que la pérdida del borrador está confirmada pero la causa física del salto de A a B sigue sin demostrarse. Redacción preexistente; al consolidar, conviene ajustarla y regenerar AVANCE.md.

## Validación

45/102 tareas y 2/8 fases correctos; F4 8/13 y F4.4 3/3. Solo F4.4.1 pasa a hecha; F4.2.4 pasa a bloqueada y sigue sin marcar. 102 IDs únicos, sin desconocidos ni hecha+bloqueada. Totales SEGUIMIENTO 45/4/14/39. Historial previo preservado.

PASS JSON, consistencia y git diff --check. Regenerar PLAN.md/AVANCE.md en copia aislada deja ambos idénticos byte por byte. PASS 8/8 tests (6 existentes + 2 sondas de diagnóstico de tareas completada/cancelada), 1,79 s. Sondas retiradas de la copia limpia tras conservarlas fuera; checkout compartido intacto. No se repitieron C1, E2E ni build por ser documental. CI al último chequeo: preflight y cambios PASS, app-check en curso, Preview omitido; rama detrás de main, cabeza sin cambios.

## Siguiente recomendado

Corregir SOPORTE y luego fusionar el PR documental cuando cumpla sus gates; no requiere publicación. Programar F4.2.4 ahora en un PR separado con Jhosep como escritor: frontend + módulo de datos, selección/confirmación explícita del resultado existente, sin crear otra gestión. La RPC instalada existe y el frontend no la llama. El enlace manual tiene sus validaciones; la regla temporal rechaza resultados anteriores a llamada menos 10 minutos, no es una ventana simétrica. Revisar si las lecturas actuales bastan para candidatos antes de prometer solo pantalla.

Se leyó el acuse de Jhosep del #232, comentario 6087325109: acepta H-P10 primero; H-P5 espera prueba focalizada. **No desactivar prueba leeds ni PRUEBA C1 B** hasta su aviso. Jev sigue OFF.

Informe completo y evidencia local: /private/tmp/avancecorp-pr235-review-20261009/REVISION.md .
