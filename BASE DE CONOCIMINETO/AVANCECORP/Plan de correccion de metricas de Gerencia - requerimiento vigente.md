---
tags: [crm, gerencia, requerimiento, plan, metricas]
identificador: REQ-GER-MET-001
fecha_acuerdo: 2026-09-04
estado: publicado-verificacion-visual-autenticada-pendiente
---

# Plan de corrección de métricas de Gerencia — requerimiento vigente

Relacionado con [[Inicio]], [[Auditoria de metricas de Gerencia - hallazgos y plan 2026-09-04]], [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]] y [[Main unico - sincronizacion y publicacion 2026-09-04]].

## Acuerdo y continuidad

Miguel aceptó la recomendación de trabajo y pidió guardar los **cinco puntos** del plan para poder continuar sin depender del chat. En esta solicitud pidió únicamente el objetivo del primer punto y la persistencia del requerimiento; **no se inició implementación ni publicación**.

Este documento es el seguimiento vigente de los cinco puntos. El informe enlazado conserva la evidencia, los hallazgos G01–G15 y las necesidades N1–N4. Sus etapas técnicas 0–5 se agrupan aquí en los cinco puntos comunicados a Miguel; la publicación permanece como una puerta posterior, no como un sexto requerimiento autorizado.

Avance posterior: se ejecutó exclusivamente el punto 1 como inventario documental de significados y fuentes. Completado y verificado el 4 de septiembre de 2026, 21:21 America/Lima, sin implementar correcciones ni publicar. Entregable: [[Inventario de indicadores de Gerencia - Contrato de lectura]]; comprobaciones: [[Inventario de indicadores de Gerencia - Evidencia y verificacion]].

Avance siguiente: el objetivo posterior autorizó la implementación local del punto 2. Completado y verificado el 4 de septiembre de 2026, 22:05 America/Lima, sin publicación. Entregable, alcance, pruebas y límites: [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]].

Punto 3: Miguel autorizó continuar con «ok hazlo» y confirmó el SQL exacto con «sí», condicionado a probarlo aisladamente. Aplicado y verificado el 4 de septiembre, 22:50 America/Lima: se excluyeron de la lectura dos contratos de prueba (PEN 100.000 y USD 100.000), sin borrar datos; los 517 contratos reales concilian con el resumen. **Completado a las 23:23 Lima: frontend implementado y verificado localmente, sin deploy.** 2.741 pruebas y 120 E2E aprobadas (26 omisiones previas). Alcance, pruebas y reversión en [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]].

**Publicación posterior concluida:** Miguel pidió guardar todo y publicar el frontend. Commit de implementación `50f33a59b92b2263296863c857e4ef3e39619450`, Main local/remoto sincronizados antes de construir y publicar; build `build-20260905T043211512Z` verificado en producción el 4 de septiembre, 23:49 Lima. Ejecución, pruebas, acceso con sesión de Gerencia y reversión en [[Publicacion frontend metricas Gerencia 2026-09-04]]. No se aplicó SQL adicional ni se cerraron los puntos 4–5.

## Objetivo general

Que Gerencia vea métricas confiables, comprensibles y coherentes con el servidor, sin confundir captación con asignaciones, avance inferido con asistencia ni datos de prueba con capital real.

## Los cinco puntos acordados

### 1. Definir qué significa cada indicador

- [x] Completado: inventario de definiciones y fuentes, verificado y enlazado arriba.
- **Objetivo:** definir y documentar qué mide cada indicador de Gerencia y de qué dato del servidor proviene, para evitar confundir llegadas, asignaciones, citas, cierres y capital, sin cambiar los núcleos.
- Entregable: inventario por pantalla e indicador con pregunta comercial, fuente y campo, unidad, fecha, ámbito, atribución, exclusiones y estado de disponibilidad/verificación.
- Criterio de cierre: cada indicador tiene una definición inequívoca y una fuente identificada; las diferencias legítimas y los datos faltantes quedan explícitos. No se cambian reglas para forzar coincidencias.

### 2. Corregir pantallas y conexiones existentes

- [x] Completado y verificado; publicado posteriormente con autorización expresa en el release `crm-20260905T043212Z-50f33a59b92b`. Evidencia de implementación en la nota del punto 2 y de publicación en la nota de despliegue enlazadas arriba.
- Objetivo: presentar el dato correcto bajo el nombre y período correctos, reutilizando las salidas y componentes existentes.
- Alcance: retirar asignaciones presentadas como captación; distinguir base automática y llegadas; no afirmar asistencia a partir de etapas inferidas; corregir fechas de Rendimiento, estados de citas, alcance de filtros y tratamiento de errores/verificación.
- Criterio de cierre: los números conservan el significado del servidor; error, ausencia de verificación y cero real no se confunden. No hay nuevas calculadoras independientes.

### 3. Corregir la lectura de Cartera

- [x] Completado: SQL confirmado por Miguel, probado aisladamente y aplicado como `20260905034917`; lectura productiva conciliada y núcleos/permisos intactos. Conexión frontend y completitud implementadas, verificadas y publicadas posteriormente en `crm-20260905T043212Z-50f33a59b92b`. Ver las notas del punto 3 y de publicación enlazadas arriba.
- Objetivo: que los indicadores reales de Cartera se apoyen en las lecturas existentes del servidor y no incluyan contratos de prueba ni dependan de listas incompletas.
- Alcance: conciliar los resúmenes existentes campo por campo antes de conectarlos; corregir la exclusión de pruebas en la fachada existente del listado; respetar saldo vigente, producción mensual, monedas y atribución.
- Criterio de cierre: exclusiones y alcance concilian entre indicadores y listado; ningún dato de prueba aporta al indicador real. No se borran contratos ni perfiles, ni se modifica el núcleo de capital.

### 4. Justificar los datos que falten

- [x] Justificación, alcance comercial y ampliación compatible local de N1–N4 completados.
- Avance 5 de septiembre: fuentes reales y propuestas N1–N4 justificadas en [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]]. Miguel respondió «ok GO». Las ampliaciones quedaron implementadas exclusivamente en dos respuestas existentes y documentadas en [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]]. **No falta otra aprobación conceptual.** El SQL exacto aún requiere confirmación antes de producción.
- Objetivo: explicar y acordar cada necesidad adicional antes de ampliarla, sin duplicar reglas de negocio.
- Entregable por necesidad: pregunta comercial, dato existente insuficiente, motivo técnico, alternativa sin ampliación, impacto y aprobación requerida.
- Casos ya identificados: leads únicos del lote con cita real; divisor ajustado de citas por modalidad; aporte efectivo de cada operación; cierres por semana real de cierre.
- Criterio de cierre: cada caso queda resuelto con una lectura existente, descartado o aprobado expresamente como ampliación compatible de una respuesta existente. No se crean núcleos, RPC ni funciones independientes.

### 5. Probar y conciliar

- [ ] SQL y frontend publicados; auditoría, CI, conciliación real del servidor/esquemas, versión pública, archivos y formulario de acceso comprobados. Falta únicamente revisar las pantallas con una sesión real de Gerencia: el navegador integrado quedó desconectado. Evidencia en [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]].
- Avance 5 de septiembre: N1–N4 y la regresión visual de `AnimatedValue` quedaron verificadas. `npm run check` aprobó 194 archivos y 2.819 pruebas; el recorrido E2E aprobó 121 y omitió 26 por configuración, sin fallos; los bancos SQL N1–N4/ACL/rollback y la revisión independiente quedaron en GO técnico. Catálogo, núcleos, fachadas, propietarios y permisos protegidos permanecen intactos. Evidencia en [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] y [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]]. Aún sin SQL productivo, commit final ni nuevo deploy.
- Objetivo: demostrar que las pantallas coinciden con el servidor cuando miden lo mismo y explican las diferencias cuando miden cosas distintas.
- Alcance: reasignaciones, llegada a Ana/cierre de Luis, manuales/referidos, citas y cancelaciones, operaciones repetidas, capital de prueba, PEN/USD, filtros, rangos parciales, meses sellados, errores, respuestas parciales y metas superiores al 100 %.
- Observación resuelta y publicada: el importe negativo transitorio de Cartera provenía del reloj de animación y no del servidor. La corrección conserva el valor final y los negativos reales, y viajó en `build-20260905T180507302Z`; su recorrido E2E aprobó.
- Criterio de cierre: pruebas de contrato e interfaz aprobadas, discrepancias justificadas y núcleos/permisos intactos. No usar producción para semillas, mutantes ni pruebas de escritura.

## Restricciones obligatorias

1. No editar ni modificar ningún núcleo; mantener la semántica del servidor.
2. No crear funciones, RPC o calculadoras independientes ni reconstruir fórmulas de negocio por pantalla.
3. Conservar origen y fecha de llegada, atribución al primer analista, cierre a quien lo consigue, pesos vigentes, deduplicación y fotografías mensuales selladas.
4. Si falta algo, explicar técnicamente y comercialmente por qué antes de proponerlo. Ampliar una respuesta existente tampoco queda aprobado de forma automática.
5. Mostrar el SQL exacto y esperar confirmación antes de cambios de base de datos. No aplicar migraciones ajenas o pendientes mediante una publicación global.
6. No publicar hasta tener autorización. Al publicar: Main local sincronizado con `avancecorp/main`, artefacto del mismo commit verificado, sin ramas de release ni force push, verificación y reversión preparadas.
7. Preservar cambios concurrentes del usuario; revisar el estado actual del repositorio antes de continuar. Las huellas y cifras del informe son evidencia de su fecha, no una garantía de que el estado externo siga igual.

## Punto de reanudación

**Orden posterior vigente (5 de septiembre):** Miguel pidió ejecutar los seis pasos del cierre hasta publicar y verificar estas mejoras. Guardado, sincronización y publicación de frontend autorizados. Después confirmó el SQL exacto con «si»; ya se aplicó y comprobó. Seguir [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]] para el estado actual; no volver a pedir ninguna de esas autorizaciones.

**Avance de ejecución:** SQL de Gerencia aplicado como `20260905175342` con el mismo contenido aprobado, núcleos y permisos intactos y cifras reales verificadas. Candidato inicial `5ada0c5` guardado, sincronizado, probado y empaquetado; se prepara la versión final con los cambios concurrentes del frontend ya revisados. Los párrafos históricos siguientes no invalidan este estado actual.

**Último punto terminado:** 4, ampliaciones N1–N4 justificadas, aprobadas e implementadas localmente. El punto 5 está cerrado en local y conserva abierta su comprobación productiva. Los puntos 1–3 ya estaban publicados.

**Siguiente acción única:** reconectar el navegador con una sesión real de Gerencia y verificar las pantallas contra los períodos/filtros conciliados. SQL aplicado `20260905175342` y frontend público `build-20260905T180507302Z`, desde Main sincronizado `e9cccb2`, ya están comprobados técnicamente. No repetir commit de implementación, SQL ni deploy por retomar el chat. Sólo después de la comprobación autenticada completar el punto 5 y el objetivo al 100 % operativo.

El punto 4 está completo; el punto 5 sólo conserva pendientes las puertas productivas. No inferir autorización de SQL adicional, funciones nuevas, commit ni deploy. Línea base histórica al comenzar el punto 2: HEAD `ecbb7b97ad79124e34f1a924227d27dd8585c737`, árbol de aplicación `ed23ef494093755055f1b236a37d9830fe3220f9`, inicialmente limpio. Los commits concurrentes y las correcciones publicadas desde `50f33a5` se deben preservar. Verificar nuevamente el estado y el remoto antes de cualquier publicación futura.

Al retomar: leer este requerimiento, la ejecución de los puntos 2 y 3, el inventario y el informe enlazado; verificar el estado actual y actualizar aquí el avance de cada punto. No repetir los puntos 1–3 salvo cambios posteriores que exijan actualizarlos. No marcar los demás completos por tener sus objetivos descritos.
