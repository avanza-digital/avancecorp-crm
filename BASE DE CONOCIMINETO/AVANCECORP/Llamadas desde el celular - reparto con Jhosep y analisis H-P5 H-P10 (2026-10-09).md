# Llamadas desde el celular — reparto con Jhosep y análisis H-P5/H-P10

Fecha: 09/10/2026, 13:52 Lima.

Relacionado: [[Inicio]], [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]], [[Llamadas desde el celular - Figma actualizado al PR 232 (2026-10-09)]], [[Llamadas desde el celular - H-WA aceptado y ayuda coordinada (2026-10-09)]].

## Reparto confirmado

Miguel pidió preguntar a la sesión de Jhosep en qué ayudar y hacerlo. Se coordinó por el #232 (sesión remota de Jhosep):
- Pregunta: https://github.com/avanza-digital/avancecorp-crm/pull/232#issuecomment-6087013958
- Respuesta: https://github.com/avanza-digital/avancecorp-crm/pull/232#issuecomment-6087059089
- Entrega: https://github.com/avanza-digital/avancecorp-crm/pull/232#issuecomment-6087235959

Jhosep: pruebas F4.4.1 (dos pestañas), F4.2.4 (enlace manual desde PC), luego contrato/oráculos F4-e. Único escritor de docs/plans/llamadas-celular/ y REGISTRO.md. Su cierre documental H-WA estaba en crm/llamadas-docs-cierre-hwa-20261009, commit 4173c2f2 desde f3efe078, pendiente PR al coordinar.

Codex/Miguel: analizar y proponer H-P5/H-P10 con evidencia; implementación futura en PR propio según el acuerdo. Se entregó ese análisis, no una corrección aplicada.

## Hallazgos confirmados y límites

Base inmutable analizada: f3efe078da807768516bd5f24fb120dbd030a375, en /private/tmp/avancecorp-pr190-correcciones-20261006. Es main tras #233; el build frontend de llamadas sigue build-20261009T181538004Z (#232).

H-P10: la API distingue es_propia, pero textos colectivos y lineaPendiente atribuyen todas las llamadas a la persona que mira. Se recomienda textos neutrales e indicador por fila propia/otro analista, manteniendo permisos y métricas. «Hoy» significa resueltas hoy en Lima. Dar al antiguo responsable acceso al detalle de un lead fuera de su ámbito sería otro cambio de negocio; no es necesario para corregir el texto. La atribución financiera de #233 tiene otro contrato.

H-P5: los campos del formulario viven solo en useState; unmount/remount pierde resultado, nota y título. La cola en sessionStorage sí conserva A delante de B de distinto lead después de una nueva carga. Por tanto la causa física de B apareciendo primero en C1 sigue sin demostrarse: distinguir recarga, limpieza al desmontar y cambio de contexto/pestaña. Nueva llamada al mismo lead tras recargar reemplaza intención/evento: un futuro borrador solo por lead_id sería inseguro.

Propuesta H-P5: borrador versionado por cuenta/lead/identidad de llamada, recuperación explícita en misma pestaña, caducidad 2h alineada con coordinador, revalidación de acceso/tarea/fechas. No reutilizar datos entre eventos ni autoenviar. Guardados inciertos deben conservar el recibo idempotente existente de sla-operacion-comandos y sus parámetros; no generar una operación nueva. No pasar a localStorage compartido sin diseñar la coordinación entre pestañas. Antes de declarar arreglado el salto en C1 hace falta una repetición P5 focalizada con contexto de navegación, sin PII. No repetir P1–P15.

## Evidencia y estado

PASS 95/95 tests (6 archivos, 9,01 s): 91 existentes + 4 sondas temporales de diagnóstico. Las sondas afirman el comportamiento fallido actual, no prueban una corrección. Copias y entrega en /private/tmp/avancecorp-hp5-hp10-20261009/. Sondas retiradas de la copia de trabajo tras conservarlas; checkout limpio y git diff --check PASS.

Revisión secundaria intentada mediante scripts/claude-review: respuesta sin VERDICT válido, no cuenta como PASS. Sin cambios al wrapper. C1 físico y E2E/build de una implementación: NOT RUN en este análisis; no se modificó producto ni producción.

FigJam actualizado con responsables, enlace a la entrega y estado «propuesta entregada, sin implementación»: https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY . Avance permanece 44/102 tareas, 2/8 fases; H-WA y F4-d aceptados. Jev OFF. Checkout compartido preservado.
