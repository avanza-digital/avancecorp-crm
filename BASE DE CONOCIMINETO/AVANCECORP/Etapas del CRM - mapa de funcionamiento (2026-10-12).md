---
tags: [crm, pipeline, etapas, reglas, mapa]
actualizado: 2026-10-12
estado: investigado-sin-cambios-de-reglas
---

# Etapas del CRM — mapa de funcionamiento

Miguel pidió ubicar el funcionamiento antes de definir nuevas reglas. Esta nota documenta el comportamiento encontrado, anterior a la propuesta de recorrido obligatorio descrita en el seguimiento.

**Seguimiento de la misma sesión:** Miguel pidió impedir la conversión hasta completar todas las etapas y confirmó que deben acreditarse con hechos, no movimientos de tarjeta. La propuesta y los casos pendientes están en [[Conversion - recorrido obligatorio por hechos (propuesta 2026-10-12)]]. El funcionamiento descrito abajo es el anterior a esa futura regla.

Se revisó el código local de `main` (`68bf2324`, con cambios previos de otras tareas) y se consultaron **solo catálogos, definiciones de funciones y configuración** de producción, proyecto `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`). No se crearon ni modificaron leads, actividades, tareas, políticas o funciones. La comparación no certifica que todo el frontend local sea idéntico al publicado.

## Recorrido y significado de las etapas

| Nombre visible | Valor guardado | Funcionamiento actual |
|---|---|---|
| Nuevo | `nuevo` | Etapa inicial habitual. El alta manual desde una columna también puede crear directamente en otra etapa activa. |
| Gestionado | Sigue siendo `nuevo` | Columna calculada: titular asignado, inicio de tenencia conocido y al menos una gestión vigente desde esa asignación. No admite movimiento manual hacia ella. |
| Contactado | `contactado` | Avance automático desde `nuevo` al registrar llamada contestada, WhatsApp recibido o reunión realizada. También admite movimiento manual y reactivación desde la base. |
| Cita agendada | `reunion_agendada` | Avance automático al crear una cita futura que cumpla las condiciones descritas abajo; también admite movimiento manual. |
| Entrevista realizada | `propuesta_enviada` | Avance automático al cerrar una cita como realizada mediante el flujo de entrevista. El movimiento manual pregunta capital y moneda. El nombre interno es histórico. |
| Convertido | `convertido` | Cierre mediante el flujo de inversión, con inversión confirmada. No es destino del arrastre. |
| Descartado | `descartado` | Cierre con motivo obligatorio. Tiene reapertura, rescate y gestión de base con reglas propias. |

Catálogo: `CRM-Avance-Corp/app/src/lib/tipos.ts:9`. Columnas: `app/src/lib/pipeline-columnas.ts:66`. Presentación compartida: `app/src/lib/use-etapa-visible.ts`.

## Movimiento manual

Hay tres entradas: arrastrar una tarjeta, menú «Mover a» del Pipeline y botones de etapas de la ficha. Todas terminan en `store.cambiarEtapa` → `actualizarLead` → UPDATE de `crm.leads`.

- **No existe una secuencia obligatoria entre las cuatro etapas activas.** Se puede avanzar, saltar etapas o retroceder. La selección manual de Cita agendada no crea por sí sola una cita; la de Entrevista realizada no registra por sí sola asistencia.
- Se valida permiso de escritura y ámbito del lead. El servidor aplica permisos por fila, restricciones y disparadores.
- El store impide mover terminales y exige usar los flujos de convertir/descartar para cerrar. El servidor impide reabrir convertidos y restringe la reapertura de descartados a su operación específica.
- Al entrar manualmente a Entrevista realizada, el diálogo confirma capital positivo y moneda; ambos se guardan junto con la etapa. El capital es opcional en la firma general de `cambiarEtapa`: la exigencia del diálogo no constituye una regla universal del servidor para todo cambio manual.
- Gestionado no es destino. Mover de Gestionado a Nuevo tampoco cambia nada: ambos guardan `nuevo`. Devolver un lead de una etapa posterior a `nuevo` puede mostrarlo como Gestionado si conserva una gestión vigente.
- «Nuevo lead» desde una columna real hereda esa etapa. Una futura regla de secuencia debe considerar también el alta, no solo los movimientos de leads existentes.

Puntos: `app/src/screens/pipeline.tsx:542`, `app/src/components/app/lead-drawer.tsx:360`, `app/src/components/app/capital-propuesta.tsx:25`, `app/src/lib/store.tsx:2670`, `app/src/data/crm-api.ts:2687`, `app/src/components/app/lead-nuevo.tsx:718`.

## Automatismos de avance

### Contacto

`private.trg_actividades_avance_etapa` actúa al insertar actividades. Solo mueve leads activos que siguen en `nuevo`, y solo con `llamada_realizada`, `whatsapp_recibido` o `reunion_realizada`. Una llamada no contestada o WhatsApp enviado pueden mostrar Gestionado, pero no producen este avance a Contactado. Una nota no cuenta como gestión de contacto.

### Cita

`private.trg_tareas_avance_etapa` actúa al **crear** una tarea: tipo reunión, activa, pendiente, fecha futura y sin `reagendada_de`. El lead debe estar en `nuevo` o `contactado`, tener analista o bandeja y estar en el ámbito autorizado. Exige alguna de las cinco actividades de contacto: contestada, no contestada, WhatsApp enviado, recibido o reunión realizada.

Ese requisito de actividad consulta el historial sin recortarlo a la tenencia actual y sin filtrar resultados deshechos. Es diferente de la regla de Gestionado. Reagendar automáticamente tras una inasistencia no equivale a un nuevo avance. Crear la cita desde Entrevista realizada tampoco retrocede la etapa.

### Entrevista

`crm.cerrar_reunion_v3` compone el cierre de la cita y `private.entrevista_registrar` en una transacción. Cerrar como realizada avanza desde cualquiera de las tres etapas previas a `propuesta_enviada`.

Se exige capital y moneda cuando hubo propuesta; el resultado `no_interesado` registra la asistencia sin pedir capital. Una segunda entrevista conserva la etapa y puede actualizar el capital. Una cita cancelada o con inasistencia no registra entrevista. Registrar una actividad aislada `reunion_realizada` pasa por el automatismo de Contactado; el avance a Entrevista realizada corresponde al cierre mediante v3.

Espejo del navegador/demo: `app/src/lib/avance-automatico.ts:56`, `:85`, `:128`. El servidor es la autoridad; cualquier cambio debe actualizar también este espejo y los mensajes del store.

## Llamadas y Gestión diaria

Las llamadas ordinarias del frontend usan `crm.registrar_llamada_v4`. Con un evento de celular identificado usan v5, que delega en el mismo núcleo v4 y añade el enlace con la llamada. V3 se conserva por compatibilidad.

- «No contestó», «Número errado» y «No es la persona» registran actividad de intento sin respuesta.
- «Volver a llamar», «Agendó cita», «No le interesa» y «Pide otro producto» registran llamada contestada y pueden activar Contactado.
- El siguiente paso, si corresponde, crea la tarea dentro de la misma operación y puede activar el avance a Cita agendada.
- **No le interesa y Pide otro producto ya no descartan por sí solos.** Descartar es una decisión separada desde el 21/09. La nota de F2 del 20/09 contiene la regla anterior.
- «No contactar» es una restricción adicional, no una etapa. Impide nuevas gestiones/reapertura según el flujo; no debe equipararse automáticamente con Descartado.

Puntos: `app/src/lib/resultado-llamada.ts`, `app/src/lib/store.tsx:3254`, `app/src/data/sla-operacion-comandos.ts`, funciones `private.llamada_registrar_v4` y `crm.registrar_llamada_v5`.

## Retrocesos, reapertura y caminos especiales

| Acción | Efecto actual |
|---|---|
| Movimiento manual entre etapas activas | Puede retroceder; no hay restricción general de orden. |
| Cancelar la última cita pendiente | Si el lead está exactamente en Cita agendada, tiene dueño y no hubo reunión realizada en el ciclo actual: vuelve a Contactado si hay alguna gestión de los cinco tipos en ese ciclo, o a Nuevo si no hay ninguna. Un intento sin respuesta también cuenta en esta regla. |
| Cancelar y reagendar en la misma operación | Si queda otra cita pendiente, no baja por la cancelación. |
| Registrar inasistencia | No baja automáticamente por ese hecho. |
| Devolver a la cola global sin responsable | Cancela tareas pendientes y puede retirar Cita agendada con una regla de retroceso equivalente. |
| Descartar o convertir | Cancela tareas pendientes del lead. |
| Reabrir desde la ficha | `crm.reabrir_lead_fn`: Descartado → Nuevo, conserva responsable, abre nuevo ciclo. Comprueba ámbito, No contactar y conflictos de identidad/persona. |
| Reactivar desde Base para gestión | Reabre a Nuevo y avanza a Contactado en la misma operación, conservando dueño. Si falta capital lo pide antes. «Agendó cita» desde la base activa también esta reactivación; debe distinguirse del registro de una tarea de cita. |
| Rescate/reparto y toma de descartado reutilizable | Tienen entradas propias (`crm.rescatar_descartes`, `crm.tomar_lead_libre`), con reapertura a Nuevo y controles de asignación/identidad. No confundirlas con Reactivar de la base. |
| Deshacer resultado de llamada | Solo autor y dentro de 24 horas, con controles de ámbito. Cancela la tarea siguiente pendiente; si revierte el descarte correspondiente, reabre un ciclo y restaura la etapa al descartar, excepto Cita agendada → Contactado. No es una reversión general de todos los avances. Un resultado con No insistir no se deshace por esta vía. |
| Reasignar un lead que estaba Gestionado | La nueva tenencia excluye gestiones anteriores y, si sigue guardado como `nuevo`, se muestra Nuevo hasta una gestión vigente. No implica que toda reasignación reinicie cualquier etapa activa. |
| Anular una conversión | No reabre el lead convertido; sigue el flujo específico de anulación de inversión/cierre. |

Núcleos: `private.retroceso_por_anular_reunion`, `private.trg_leads_sync_tareas`, `crm.reabrir_lead_fn`, `private.base_gestion_reactivar_capital_core`, `crm.deshacer_resultado_llamada`.

## Permisos y efectos asociados

Analista: su ámbito. Supervisor: el ámbito autorizado de su equipo. Gerencia: ámbito global. Directorio: lectura. Coordinación tiene operaciones de reparto/descarte propias, sin el Pipeline comercial ni capacidad general de gestionar la cartera. Cada operación revalida su permiso; tener acceso a una ficha no concede todas sus acciones.

Al cambiar etapa se registra una actividad `cambio_etapa` con origen, destino, autor y marca automática. El servidor cierra el episodio de plazo anterior y abre el correspondiente a la nueva etapa. La reapertura abre además un nuevo ciclo. Los filtros, contadores, avisos de plazo y capital en proceso consumen estas etapas; el cierre confirmado alimenta los núcleos de conversión e inversiones.

El reporte de Citas/Entrevistas usa hechos de citas y asistencia. Mover manualmente una tarjeta a Entrevista realizada no produce el cierre de una cita. «Depósito» es el nombre comercial del resultado de conversión en ese reporte; no es otra etapa guardada del lead.

### Plazos configurados al consultar producción

Política vigente **v6**, reloj corrido, zona `America/Lima`. Son límites base: el núcleo también controla prórrogas/compromisos; no significan avance automático al vencer.

| Concepto | Plazo base |
|---|---|
| Primera gestión | 2 horas |
| Primer contacto | 24 horas |
| Nuevo, incluido Gestionado | 24 horas |
| Contactado | 8 días |
| Cita agendada | 15 días |
| Entrevista realizada | 20 días |

La configuración está en `app/src/screens/config-sla.tsx` y las políticas en `crm.sla_politicas` / `crm.sla_politica_etapas`. Los episodios existentes conservan su política. Los comentarios históricos que citan 72/120 horas no describen los plazos vigentes consultados.

## Mapa del servidor para la futura implementación

Rutas bajo `CRM-Avance-Corp/supabase/migrations/`:

| Tema | Archivo de referencia |
|---|---|
| Avance por actividad/cita y actividad del cambio | `20260725060657_crm_avance_automatico_etapa.sql` |
| Versión posterior del avance por contacto y núcleo SLA | `20260907024903_crm_sla_nucleo_operativo_escritura.sql` |
| Cancelación con retroceso | `20260726151751_crm_anular_autoria_y_retroceso_reunion.sql` |
| Límites de terminales/ciclos/asignación | `20260803164348_crm_offboarding_gate_activos.sql` |
| Reencolar y cancelar tareas | `20260809024942_crm_reencolar_cancela_tareas.sql` |
| Reapertura por operación específica | `20260906150000_crm_f2b_d15_reabrir_lead_por_puerta.sql` y ampliaciones posteriores; consultar cuerpo vivo antes de editar |
| Cierre de entrevista con capital | `20260918213000_crm_entrevista_al_asistir.sql` |
| Convertir mediante inversión | `20260919161807_crm_conversion_inversion_unificada.sql` y ampliaciones posteriores |
| Resultado y descarte separados | `20260921153654_crm_resultado_llamada_seguimiento.sql` |
| Partición Nuevo/Gestionado en Pipeline | `20261001154153_crm_cartera_filtro_gestion.sql` |
| Lectura compartida de gestión vigente | `20261003225551_crm_gestion_vigente_lectura.sql` |
| Reactivación de base y capital faltante | `20261004223253_crm_bases_cargadas_seguimiento.sql` |

No editar migraciones ya versionadas: cualquier cambio futuro lleva migración nueva. La tabla es un mapa de referencias, no una afirmación de que cada definición inicial sea la última; hay funciones modificadas posteriormente. Para esta investigación se consultaron sus cuerpos vivos.

## Verificación de esta investigación

- **PASS:** 222 pruebas existentes en cinco archivos: `lib/avance-automatico.test.ts`, `lib/pipeline-columnas.test.ts`, `lib/use-etapa-visible.test.ts`, `screens/pipeline.test.tsx`, `screens/pipeline-gestionado.test.tsx`.
- **PASS:** lectura de disparadores habilitados, políticas de UPDATE, privilegios de etapa, restricciones, funciones de avance/reapertura/reactivación/deshacer y configuración de plazos en producción.
- **PASS:** los cuerpos de `crm.cerrar_reunion_v3` y `private.entrevista_registrar` coinciden entre producción y la migración local: MD5 `353d2293ae00a96e92acbbe7c9c219a2` y `63022f53cf33b689870505e6188c8827`.
- **NOT RUN:** E2E en Docker, matriz RLS y ensayos SQL con escrituras. Esta tarea solo localizó/documentó reglas; no cambió el producto ni probó transiciones sobre leads reales.
- Navegación inicial con CodeGraph; su salida no cubría varias funciones actuales. Se complementó con búsquedas puntuales, código y catálogos vivos.

Antes de implementar hay que definir con Miguel condiciones de cada transición, saltos/retrocesos, quién puede hacerlos, excepciones de base y reapertura, y efecto sobre plazos. Después se aplican conjuntamente servidor, espejo frontend, interfaces y pruebas pertinentes.

Relacionadas: [[Pipeline - columna Gestionado (2026-10-01)]] · [[Gestionado - ficha y vistas coherentes (2026-10-03)]] · [[Gestion Diaria - resultado separado del descarte (2026-09-21)]] · [[Base para gestion del analista - F0 y decisiones (2026-10-01)]] · [[Citas Gerencia - etapa Deposito 2026-09-15]] · [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]] · [[Inicio]].
