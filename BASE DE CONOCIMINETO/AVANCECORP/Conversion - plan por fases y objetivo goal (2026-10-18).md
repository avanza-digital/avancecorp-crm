---
tags: [crm, leads, conversion, plan, figma]
actualizado: 2026-10-18
estado: plan-revisado-sin-implementar
---

# Recorrido de leads: plan por fases y objetivo para goal

Continuación de [[Conversion - recorrido obligatorio por hechos (propuesta 2026-10-12)]] y [[Etapas del CRM - mapa de funcionamiento (2026-10-12)]].

El usuario pidió analizar el plan, detallarlo por etapas en el mismo archivo de Figma y entregar el objetivo para goal. Después pidió indicar si hacen falta flujos n8n y priorizar robustez y escalabilidad. **Esta tarea actualiza el plan; no autoriza ni ejecuta la implementación, la creación de un Goal o la publicación.**

- [Plan vigente en el mismo FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=17-117).
- [Objetivo para goal](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=35-233).
- [Decisiones y límites](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=35-225).
- [Decisión sobre n8n](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=35-229).
- [Propuesta corregida del analista](https://www.figma.com/design/clrnxxPbacujdC3S5tMWkn?node-id=13-16).

El plan vigente tiene **ocho fases**. Sustituye el plan anterior de cinco fases en la sección 17:117. El duplicado histórico de cinco fases del archivo de pantallas (9:596) no se ha actualizado en esta tarea; usar el FigJam enlazado como referencia vigente. El flujo 11:117 y el archivo oculto 3:29 se conservaron.

## Evaluación

La base del plan es correcta. El recorrido se apoya en hechos reales y reutiliza el cierre actual del CRM. Para ejecutarlo con confianza faltaba concretar evidencias, controles por fase, tratamiento de antiguos y entrega hasta el ZIP.

Gestionado → Contactado → Cita agendada → Entrevista realizada → Convertido.
Mover una tarjeta no acredita hechos. La inversión se completa dentro de la conversión; no se exige antes de abrirla.

No se considera validada una evidencia por el nombre de la etapa, el origen referido/importado ni el rol del usuario. Una llamada contestada puede acreditar gestión y contacto en el mismo guardado. Las cinco etapas previas y la inversión no se deben convertir en un bloqueo circular para abrir la conversión.

## Evidencia de la revisión

Fuente de implementación contrastada: Main `6ace3d441bd874a1e06613ee5718b1023e08c39d`, igual a `avancecorp/main` al inicio de la revisión, desde la copia limpia ya existente. Se preservó el checkout original con cambios ajenos. CodeGraph se consultó primero; no devolvió los símbolos relevantes y se complementó con lecturas acotadas:

- `app/src/components/gestion-diaria/registrar-resultado.tsx:239`: confirma persistencia antes de cerrar y llamar a `onGuardado`.
- `app/src/components/app/cerrar-tarea.tsx:325`: capital y entrevista dependen del resultado de la cita; conserva «Saltar esta vez».
- `app/src/lib/store.tsx:674`: `ejecutarCierreTarea` usa `cerrar_reunion_v3` para cita de lead y `cerrar_tarea_v2` para otras tareas; no dividir el cierre atómico.
- `app/src/data/inversion-solicitud-api.ts`: preparación, contexto de reanudación, confirmación y acceso externo; operaciones de cliente actual tienen rutas distintas.
- `app/src/components/app/inversion-nueva.tsx:475`: reconsulta la solicitud antes del acceso y preserva su recuperación.

No se auditó de nuevo el SQL vivo ni se hizo un censo de datos en esta tarea; ambas comprobaciones forman parte del plan, no son resultados obtenidos. El Plugin API confirmó el texto visible actual del plan anterior: algunos nombres de capa eran antiguos, pero sus `characters` sí contenían la propuesta corregida.

## Regla de avance

En cada fase: implementar → comprobar → revisión de Codex → corregir → repetir las comprobaciones afectadas. No avanzar con fallos obligatorios ni hallazgos aceptados pendientes. Registrar PASS / FAIL / NOT RUN con evidencia.

Claude: revisión de arquitectura y, con nueva evidencia, revisión del cambio crítico de datos/conversión. Máximo habitual: 2 consultas sustantivas; sin revisiones repetidas para conseguir un PASS.

Cada fase exige pruebas pertinentes; la fase 6 integra la verificación completa, no posterga todas las pruebas hasta el final. Un check obligatorio NOT RUN impide declarar superado su gate. Registrar motivo y resultado de cada hallazgo aceptado o rechazado.

## Ocho fases

### 1. Definir qué acredita cada etapa

**Alcance:** 01 · CONTRATO Y ALCANCE

- Mapear cierres, RPC, triggers, acceso externo y reanudación; contrastar el código con el SQL vigente.
- Precisar evidencia y ciclo: reabrir inicia otro; reasignar conserva el mismo, incluso sin tareas SLA.
- Definir primera conversión por persona/empresa, vigencia y orden de hechos, permisos de oficina y presupuestos de rendimiento.

**Entrega:** Matriz de aceptación + contratos resueltos + fuentes SQL verificadas + arquitectura revisada por Claude.

**Gate:** No iniciar el evaluador sin resolver ciclo y alcance de primera conversión. Incluir cliente de otra empresa, cliente anterior e importado. Antiguos: la política pendiente frena su activación, no el trabajo independiente.

### 2. Evaluar hechos del ciclo vigente

**Alcance:** 02 · DATOS Y REGLA COMÚN

- Un único evaluador de hechos vigentes, compartido por lectura y conversión, con permisos y referencias.
- Modos del servidor desde el inicio: apagado, observación y exigencia por grupo; por defecto, observar sin bloquear.
- Censo de antiguos y consultas por lote; ciclos e índices según la evidencia de fase 1.

**Entrega:** Evaluador + lectura autorizada por lote + censo sin inventar evidencias.

**Gate:** SQL/RLS y rendimiento medidos. Grupo de activación decidido en servidor, configuración simple y auditada. Probar los tres modos; observar registra lo que faltaría sin impedir la operación.

### 3. Registrar una vez, acreditar bien

**Alcance:** 03 · CIERRE ACTUAL Y OFICINA

- Reutilizar cierres de llamadas/citas y el motor de siguiente acción; conservar su transacción.
- Oficina: contacto, cita inmediata y asistencia real; registrar origen, actor y hora del servidor, con permisos y sin fechas inventadas.
- Reintentos sin duplicados; «No contestó», «No asistió» y «Saltar esta vez» conservan su sentido.

**Entrega:** Cierres integrados + atención en oficina sin repetir formularios ni crear duplicados.

**Gate:** Avanzar de lead solo tras guardar; un fallo al refrescar la guía no invalida el guardado. Probar duplicados, límites de permisos y cierre + próxima tarea en integración y E2E local.

### 4. Mostrar qué falta y cómo resolverlo

**Alcance:** 04 · GUÍA DEL ANALISTA

- Mostrar progreso y próxima acción en ficha, Mi día y tablero con las acciones existentes.
- Cita futura: ver o reprogramar. Lectura fallida o RPC ausente: estado desconocido y reintento, sin bloquear guardar ni avanzar.
- Refrescar al guardar, deshacer, reabrir o reasignar; conservar datos, foco y accesibilidad.

**Entrega:** Guía clara y coherente en las pantallas actuales, sin otro motor de tareas.

**Gate:** Mismo historial, mismo estado entre vistas. Probar móvil, teclado y las dos combinaciones de versiones frontend/backend. La conversión mantiene la decisión del servidor.

### 5. Comprobar en el servidor

**Alcance:** 05 · CONVERSIÓN PROTEGIDA

- Validar inicio, reanudación, acceso externo y confirmación con el evaluador y el modo ya existentes.
- Comprobar hechos e inversión atómicamente; preservar permisos, borradores e idempotencia.
- Guardar referencias de la evidencia al confirmar; una anulación posterior no revierte automáticamente contratos ni clientes.

**Entrega:** Primera conversión protegida + recuperación segura ante cambios o respuestas perdidas.

**Gate:** Probar cancelación/deshacer frente a confirmación, doble envío, cliente actual y rutas directas. Respetar reglas de anulación y recuperar solicitudes con acceso creado. Claude revisa; Codex corrige y vuelve a comprobar.

### 6. Probar antes de exigir el recorrido

**Alcance:** 06 · VALIDACIÓN Y ACTIVACIÓN

- Ejecutar gates del proyecto, SQL/RLS aislado y E2E local en Docker con la matriz de fases 1–5.
- Ensayar observación → guía → exigencia usando los modos ya probados.
- Decidir antiguos con el censo y probar reversión mediante configuración, sin borrar hechos ni deshacer migraciones.

**Entrega:** Matriz de pruebas + plan de activación y reversión probado en entorno aislado.

**Gate:** Sin fallos obligatorios ni excepciones silenciosas. Antiguos: decisión comercial y regularización antes de exigirles el recorrido. Revertir solo la regla nueva, conservando permisos, hechos e historial.

### 7. Cerrar la revisión del cambio

**Alcance:** 07 · PR Y PREPARACIÓN DE RELEASE

- Abrir PR, revisar CodeRabbit cuando esté disponible y resolver hallazgos con evidencia.
- Integrar el PR aprobado y cambios remotos; verificar Main local = avancecorp/main.
- Documentar orden y compatibilidad de migraciones, Edge Functions y frontend, sin aplicarlos a producción.

**Entrega:** Commit revisado + checks + instrucciones de despliegue, activación y reversión.

**Gate:** Correcciones verificadas y commit identificado. El ZIP de frontend no sustituye los requisitos de backend: declarar qué debe estar aplicado antes de publicarlo.

### 8. Entregar un artefacto verificable

**Alcance:** 08 · ZIP Y ENTREGA

- Construir y empaquetar con los scripts actuales desde el commit verificado.
- Revisar contenido, versión y prueba de humo; calcular SHA-256.
- Entregar ZIP, commit, resultados, dependencias de backend y este plan actualizado.

**Entrega:** ZIP trazable + checksum + informe de pruebas + manifiesto de publicación.

**Gate:** El artefacto corresponde al commit validado y explicita los requisitos pendientes de producción. Esta meta termina en la entrega del ZIP; publicar y activar son acciones separadas.

## Contratos pendientes y activación

DEFINICIONES QUE DEBE CERRAR LA FASE 1
• Fuente del ciclo: reapertura inicia uno; reasignación no lo cambia. Validar con SQL, también sin tareas SLA.
• Alcance de primera conversión: persona/empresa, cliente anterior, otra empresa o importado.
• Orden y vigencia de hechos, y quién puede registrar la visita de oficina.
Estos contratos condicionan el desarrollo correspondiente. La política de antiguos y el grupo de activación condicionan la exigencia en producción.

RECOMENDACIÓN PARA LEADS ANTIGUOS
Medir antes de bloquear. Clasificar hechos completos, incompletos y ambiguos; regularizar con evidencias reales y decisión comercial registrada. No dar por cumplido un hecho porque la tarjeta esté en una etapa avanzada.

La fuente actual `tarea_sla_contexto.ciclo_n` es candidata, no una decisión demostrada. Confirmar con SQL que existe para todos los orígenes, cambia al reabrir y no se reinicia al reasignar. Si no satisface el contrato, evaluar los eventos de descarte/reapertura ya existentes antes de proponer otra estructura.

La matriz de fase 1 debe cerrar también si el contacto precede a la cita y si hay caducidad de evidencias dentro de un ciclo; no confundir plazos SLA con invalidez comercial. No añadir excepciones de origen o de empresa desde el cliente.

Los modos apagado/observación/exigencia y la selección de grupo se resuelven en servidor y nacen en fase 2, antes del guard de fase 5. La configuración debe ser mínima y auditada, no un motor nuevo de reglas. Ensayar que cambiar el modo revierte únicamente el requisito nuevo; no debilita permisos ni controles financieros actuales.

Al confirmar, conservar un registro mínimo de referencias de evidencias/ciclo utilizado. Las anulaciones posteriores siguen los permisos y reglas actuales: si se permiten, quedan auditadas sin desconvertir al cliente ni revertir automáticamente un contrato. No introducir una autorización general nueva para anular.

Oficina registra un hecho real con origen, actor y hora del servidor. Mantener las restricciones de acceso a leads; no fabricar llamadas anteriores o fechas retroactivas. No se incorporó seguimiento del dispositivo ni otro reporte comercial, porque no son necesarios para este alcance.

## Arquitectura y n8n

No hace falta n8n para este recorrido.
El backend del CRM y las transacciones de PostgreSQL controlan evidencias, permisos y conversión. La robustez viene de reintentos seguros, bloqueos coherentes, consultas por lote, índices medidos y trazabilidad de errores.

n8n quedaría como opción futura para avisos o integraciones después de guardar, sin decidir etapas ni bloquear la operación del analista. No se añade al alcance actual.

Complementar escalabilidad con paginación, una lectura por lote, índices justificados con planes de consulta, invalidación de caché y un único evaluador compartido por resumen y confirmación. Evitar una consulta por tarjeta, otro registro paralelo de hechos y nuevas colas/microservicios sin necesidad medida.

## Revisión independiente

Se consultó Claude mediante `scripts/claude-review`, como SECONDARY_REVIEWER sin herramientas ni modificaciones. Dictamen inicial: **CHANGES_REQUESTED**, confianza MEDIUM, referido al plan (sin afirmar bugs comprobados del producto).

Codex incorporó:
1. Modos y grupo del servidor desde fase 2, antes del guard.
2. Contratos de ciclo y primera conversión por persona/empresa como gate de fase 1.
3. Anulaciones posteriores a confirmación y registro de la evidencia utilizada.
4. Límites del caso oficina y permisos.
5. Compatibilidad frontend/backend y ausencia del RPC sin romper guardados.
6. Dependencias de cada decisión y fusión de PR sujeta a aprobación.

Se acotó la recomendación de permitir deshacer: conservar reglas actuales, no habilitar anulaciones por defecto. No se añadieron dispositivo ni reporte de oficina como requisitos nuevos. No se repitió el review para obtener un PASS; Codex evaluó y corrigió el plan.

## Objetivo para goal

Implementar el recorrido de primera conversión de leads por hechos verificables del ciclo comercial vigente, siguiendo las ocho fases de este plan y reutilizando los cierres y el motor de siguiente acción actuales. Incluir evaluación central y modos de observación/exigencia en servidor, guía del analista y atención en oficina, preservando permisos, borradores, operaciones de clientes actuales y seguridad ante reintentos y concurrencia.

Codex debe implementar y revisar cada fase, ejecutar las pruebas pertinentes, corregir los hallazgos aceptados y volver a verificar antes de avanzar. Incorporar a Claude en arquitectura y revisión del cambio crítico conforme al protocolo del proyecto; registrar PASS, FAIL o NOT RUN con evidencia.

Completar SQL/RLS en entorno aislado, E2E local en Docker, revisión del PR, integración en Main y comprobación de Main local = avancecorp/main. Construir desde ese commit y entregar ZIP, SHA-256, informe de pruebas y requisitos de backend, activación y reversión. Terminar con el artefacto entregado; no publicar ni activar bloqueos de producción sin la instrucción correspondiente y la política de antiguos definida. No requiere n8n.

El objetivo se entrega como texto; **no se ha creado ni iniciado un Goal**.

## Verificación de esta entrega

- PASS: actualización del mismo contenedor FigJam 17:117; 8 tarjetas y 7 conexiones.
- PASS: estructura sin desbordamiento de hijos; textos editables y objetivo incluido.
- PASS: inspección de captura completa, fase 1 y objetivo; texto legible, sin cortes ni solapamientos. Contenedor vertical conservado en el mismo archivo.
- NOT RUN: tests de producto, SQL/RLS y E2E; no se modificó el producto ni se implementó el recorrido.
- Publicación / activación: no realizadas.
