---
tags: [crm, gerencia, metricas, plan, aprobacion]
requerimiento: REQ-GER-MET-001
fecha: 2026-09-05
estado: publicado-verificacion-visual-autenticada-pendiente
---

# Plan por fases — cuatro datos de Gerencia

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]], [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] e [[Inicio]].

## Aprobación y alcance

El 5 de septiembre de 2026, después de recibir la explicación comercial de N1–N4, Miguel respondió: «ok GO, como lo haras dame el plan por fase, y el objetivo final de esto para decir que ya quedo al 100%».

**El alcance de los cuatro datos está aprobado. No volver a pedir esa aprobación.** En el turno que originó este documento sólo se presentó el plan. Después se implementaron y auditaron localmente N1–N4. La aprobación conceptual no sustituye la confirmación del SQL exacto ni una autorización nueva de publicación. La instrucción anterior de hacer commit de todo al terminar continúa vigente.

Estas fases desarrollan las necesidades del punto 4 y la validación del punto 5 del requerimiento original; no sustituyen sus cinco puntos ni reabren los puntos 1–3 ya publicados.

## Estado de ejecución al 5 de septiembre

- Fases 1–4: completadas localmente. Se ampliaron los dos agregadores existentes, sin cambiar núcleos, fachadas, propietarios ni ACL, y el frontend consume las nuevas proyecciones sin recalcular reglas comerciales.
- Fase 5: versión final `e9cccb2` guardada, sincronizada y empaquetada desde un checkout limpio; cambios concurrentes revisados y CI completo aprobado. Evidencia en [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]].
- Fase 6: SQL `20260905175342` y frontend `build-20260905T180507302Z` publicados y verificados técnicamente. Respuestas reales, núcleos, permisos, advisors, archivos y formulario de acceso comprobados. Sólo queda la comprobación visual autenticada al reconectar el navegador de Gerencia.
- Nombre visible acordado para esta lectura: **«Resultados de los leads del mes»**; no usar «Cosecha del lote» ni añadir «hasta hoy» al título.

## Objetivo final

Que Gerencia pueda conocer, desde los datos canónicos del servidor, cuántos leads recibidos tuvieron cita real, cómo se explica el porcentaje de citas, qué operaciones aportaron conversión y cuándo se consiguieron los cierres. Las pantallas deben conservar población, fechas, atribución y reglas, sin confundir llegadas con asignaciones ni elegibilidad con aporte efectivo.

## Ruta de cierre pendiente — actualización del 5 de septiembre

Miguel pidió un plan por fases para todo lo que falta. Esta ruta desglosa únicamente el cierre de las fases 5–6; no reinicia el desarrollo terminado ni autoriza por sí misma SQL o deploy.

**Orden posterior:** Miguel pidió ejecutar los seis pasos hasta el 100 % operativo. Autoriza el guardado, la sincronización y la publicación del frontend. Después confirmó expresamente el SQL exacto con «si»: aplicado y comprobado. El avance actual se registra en [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]]; las puertas descritas abajo no vuelven a exigir aprobaciones ya recibidas.

1. **Preparar y confirmar el cambio productivo.** Presentar el SQL exacto de Gerencia, su alcance, pruebas y rollback; recibir la confirmación pendiente y la autorización de publicación. Identificar las migraciones ajenas para no aplicarlas. **Cierre:** artefacto exacto confirmado, alcance delimitado y reversión preparada.
2. **Guardar y unificar Main.** Revisar el árbol actual y el trabajo concurrente, preservar los cambios ajenos, hacer el commit final solicitado e integrar el remoto sin sobrescribirlo. Repetir las pruebas pertinentes si cambió lo auditado. Comprobar que Main local y `avancecorp/main` apuntan al mismo commit y construir desde ese contenido exacto. **Cierre:** versión única, verificable y lista para publicar, sin ramas nuevas ni force push.
3. **Actualizar y comprobar el servidor.** Revalidar las definiciones y permisos actuales antes de aplicar únicamente la migración confirmada. Si el estado previo no coincide, detener la aplicación y explicar la diferencia. Leer después las respuestas nuevas y anteriores; verificar núcleos, permisos y acceso de Gerencia intactos, sin datos de prueba productivos. **Cierre:** backend compatible y comprobado; ante un fallo, no avanzar al frontend y usar la reversión acotada cuando corresponda.
4. **Publicar las pantallas.** Desplegar exclusivamente el artefacto del commit Main verificado, conservar la versión anterior recuperable y comprobar versión, archivos, acceso y carga de las pantallas afectadas. **Cierre:** frontend público correcto y acceso operativo; revertir la publicación si falla su comprobación.
5. **Conciliar las métricas reales.** Comparar servidor y pantallas para el mismo período y filtros: leads únicos con cita registrada como realizada; porcentaje de citas con su base y exclusiones; aporte efectivo de las operaciones, incluidas renovaciones y upgrades; cierres por fecha de cierre y analista que los consiguió. Revisar también resultados de los leads del mes, ausencia de asignaciones como captación, estados de error, filtros y animación de Cartera. Verificar tiempos de respuesta, especialmente en rangos históricos. **Cierre:** ninguna diferencia inexplicada dentro del alcance, sin escrituras de prueba en producción.
6. **Registrar y cerrar el requerimiento.** Guardar commit, migración aplicada, versión publicada, comprobaciones y procedimiento de reversión; actualizar el punto 5 del requerimiento sólo tras superar las fases anteriores. **Cierre:** 100 % operativo de este plan de métricas de Gerencia, no una certificación de todo el CRM.

En toda la ruta se conservan núcleos, reglas comerciales, atribución, pesos, permisos y fotografías mensuales selladas. No se crean funciones ni calculadoras independientes ni se reparan automáticamente incidencias ajenas a este requerimiento.

## Fase 1 · Contrato exacto de los cuatro datos

- Identificar la respuesta existente que entregará cada dato y todos sus consumidores de Gerencia; dejar una matriz dato → respuesta/campo → pantalla → prueba.
- N1: leads únicos (`lead_id`, no identidad de persona) entre las llegadas comerciales del rango, con cita clasificada como realizada. Declarar corte de seguimiento; llegada del primer analista, cita real del núcleo de citas, sin inferir asistencia de propuesta/cierre.
- N2: base computable y exclusiones de realización por modalidad, conservando el porcentaje ya calculado en el servidor. No deducir el divisor de un porcentaje redondeado ni usar pactadas brutas como sustituto.
- N3: identidad, atribución y aporte de la operación elegida por el núcleo. Conservar cliente/mes, elección anterior al filtro, renovación con peso de referido y upgrade ×1. Distinguir cero comprobado, ausencia de dato y foto histórica sellada; no reconstruir ni reescribir fotos antiguas.
- N4: cierres comerciales agrupados por fecha real de cierre, con límites semanales y zona America/Lima explícitos. Separar cantidad de cierres del aporte ponderado y de operaciones de Cartera; no reemplazar silenciosamente la serie por semana de llegada.
- Precisar filtros, roles autorizados, nulos y compatibilidad con las respuestas anteriores. Si aparece una imposibilidad técnica real o una ampliación de alcance, explicarla antes de cambiar el acuerdo.

**Salida:** contrato de lectura implementable, trazabilidad completa de consumidores y criterios de prueba, sin reglas comerciales nuevas.

## Fase 2 · Backend y SQL verificable

- Ampliar únicamente respuestas existentes que consumen los núcleos actuales. No crear RPC, núcleos o calculadoras independientes ni ampliar permisos.
- Preparar SQL exacto, comprobaciones del estado previo y reversión acotada. Separar las modificaciones de proyección autorizadas de los núcleos protegidos.
- Probar las respuestas ampliadas en un banco aislado con datos sintéticos; contrastar campos antiguos, tipos, autorización y reglas existentes. Verificar consultas y rendimiento proporcional al cambio.
- Presentar a Miguel el SQL exacto, el resultado de las pruebas y la reversión; esperar confirmación antes de aplicarlo al servidor productivo.

**Salida:** SQL y contrato backend probados; todavía no equivalen a SQL aplicado en producción. La guía de Supabase se utiliza para verificar cambios, revisar acceso y evitar iterar sobre datos productivos; las restricciones del proyecto prevalecen.

## Fase 3 · Frontend conectado

- Conectar los cuatro datos en Conversiones, Citas, Cartera y los demás consumidores identificados en la fase 1, usando componentes y lecturas existentes.
- Mostrar títulos comerciales breves, unidad, período y alcance correctos. Fracciones y aportes vienen del servidor, no de otra fórmula por pantalla.
- Conservar la información de avance inferido como una medida distinta; no renombrarla como asistencia.
- Añadir tratamiento compatible de carga, error y campos nuevos ausentes. Ausencia o lectura no verificable no se convierten en cero.
- Incluir la corrección local ya probada de la animación, preservando valores reales y formato final.

**Salida:** interfaz implementada y verificada localmente contra los contratos ampliados, sin afirmar que ya está publicada.

## Fase 4 · Auditoría integral de las ampliaciones

- Ejecutar pruebas SQL, de contrato, unitarias y de navegador sobre N1–N4; extender la matriz existente de trece escenarios.
- Conciliar cifras entre respuesta y pantalla para la misma población, período, modalidad y ámbito. Explicar las diferencias de preguntas distintas, no forzar igualdad.
- Cubrir reasignaciones, Ana/llegada y otro analista/cierre, manuales/referidos, cancelaciones/reprogramaciones, operaciones repetidas, rangos parciales, cierres tardíos, fotos selladas, PEN/USD, filtros, errores, paginación y porcentajes superiores a 100 %.
- Comparar definición y permisos de núcleos antes/después; comprobar compatibilidad de los consumidores anteriores y que los roles no ganen acceso indebido.
- Repetir las pruebas pertinentes tras cualquier cambio posterior. Las 2.752 pruebas y 121 E2E anteriores son una línea base, no evidencia de campos aún no implementados.

**Salida:** matriz de aceptación con evidencia por cada requisito; sin diferencias inexplicadas ni defectos pendientes dentro de este alcance.

## Fase 5 · Cierre técnico y versión única

- Guardar contratos, resultados de auditoría, cambios y procedimiento de reversión en el repositorio/vault.
- Revisar todo el árbol, preservar trabajo concurrente, verificar que no se incluyan secretos ni artefactos ajenos y hacer el commit final solicitado.
- Integrar cambios remotos sin sobrescribirlos y dejar Main local y `avancecorp/main` sincronizados; sin ramas nuevas ni force push. Revalidar si la integración cambia lo probado.

**Salida:** desarrollo y auditoría terminados, cambios versionados y Main sincronizado. Si aún no se publicaron, informar «terminado técnicamente, pendiente de publicación», no «100 % en producción».

## Fase 6 · Publicación y comprobación productiva — con autorización

- Sólo con SQL exacto confirmado y autorización de publicación: revalidar el estado previo y aplicar únicamente el SQL acordado; no ejecutar migraciones ajenas o una publicación global.
- Comprobar las respuestas nuevas y antiguas del servidor antes de conectar el frontend público.
- Construir y publicar únicamente el artefacto del commit Main local/remoto verificado.
- Verificar acceso a Gerencia, carga de los consumidores afectados y conciliación de las cuatro lecturas con datos reales, sin escrituras de prueba. Mantener preparada la reversión de SQL y frontend.
- Registrar commit, artefacto, versión publicada y evidencia del cierre. La publicación anterior no se repite por inercia.

**Salida:** los cuatro datos funcionan en la versión pública verificada. Esta fase se incluye para definir el cierre operativo completo, pero no se considera autorizada por el GO de alcance.

## Cuándo puede decirse «100 %»

El 100 % corresponde a **este requerimiento de métricas de Gerencia**, no a una garantía universal de que todo el CRM carece de defectos.

- [x] Los cuatro datos aprobados están implementados y visibles localmente en todos sus consumidores acordados, con fuente y corte identificables.
- [x] Las cifras de pantalla concilian localmente con el servidor cuando miden lo mismo; las diferencias de significado están explicadas.
- [x] Núcleos, pesos, atribuciones, deduplicación, fotos selladas y permisos protegidos permanecen intactos; no hay calculadoras independientes.
- [x] Pruebas de backend, frontend y regresión aprobadas; ningún hallazgo local o dato requerido queda oculto como cero, descartado sin acuerdo o pendiente sin declarar.
- [x] Evidencia técnica guardada, versión final `e9cccb2` realizada y Main local/remoto sincronizados antes de construir/publicar; el registro posterior no cambia el código de aplicación publicado.
- [ ] Si se afirma «100 % operativo»: SQL y frontend publicados con autorización, versión comprobada, acceso de Gerencia y cuatro lecturas verificadas en producción.

La siguiente y única comprobación pendiente es visual y autenticada: reconectar Gerencia y contrastar las pantallas con las respuestas reales ya verificadas. **SQL y frontend ya están publicados; no falta otra aprobación ni hay que reaplicar o desplegar por inercia.** No afirmar 100 % operativo hasta dejar evidencia de esa comprobación.
