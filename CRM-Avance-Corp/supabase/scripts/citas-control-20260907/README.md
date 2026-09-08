# Verificación del control de Citas — 7 de septiembre de 2026

**Estado: aplicada y verificada en producción el 7 de septiembre de 2026, a las 21:03:47 de Lima.** El usuario confirmó continuar tras recibir el SQL concreto y su verificación. Los siete controles pasan.

## Hallazgo e impacto

La publicación `20260907194622_crm_citas_gerencia_bases_y_alcance.sql` actualizó el agregador de Citas, pero dejó la huella de su versión anterior en el registro de excepciones. El cuerpo productivo coincide con el SQL publicado. Antes de este ajuste había exactamente un contador declarado cuya huella no coincidía: `private.metricas_reuniones_implementacion(date,date)`. Tras aplicarlo, los 29 contadores pasan el control; la lista conserva sus 30 excepciones y el tope sigue en 30.

El control `private.assert_analitica_leads_citas()` fallaba por esa referencia y ahora está aprobado. Su vigía sigue activo; captura fallos y los registra en `private.vigia_alertas`. Este control no se ejecuta como parte de la consulta de métricas de Citas. No se ejecutó el vigía manualmente ni se modificó su histórico de alertas.

Las lecturas con el rol de Gerencia para agosto y para el 1–7 de septiembre responden correctamente: modalidades y orígenes suman lo mismo que el total general; los responsables visibles no lo superan. Esto comprueba respuesta y conciliación de esos cortes, no la exactitud exhaustiva de cada registro o fórmula comercial.

La razón de la excepción sigue siendo válida: el agregador consume los núcleos existentes para estados de citas y cierres; también conserva el uso del núcleo de capital para stock. La ampliación publicada agrega campos y desgloses de esas bases. No hace falta un núcleo nuevo ni cambiar reglas comerciales para resolver este hallazgo.

## Corrección aplicada

Se aplicó [20260908020020_crm_citas_repara_huella_control.sql](../../migrations/20260908020020_crm_citas_repara_huella_control.sql), copia idéntica de [correccion-propuesta.sql](correccion-propuesta.sql), desde el commit `c9c31b469c462de8c66bd6339f49280dc3333ffe`. Main local y `avancecorp/main` coincidían antes de aplicar. SHA-256: `ee5ea57693342b95172011254fb3ceb8f62ae14f3f07e1f4102d224b1f94e455`. En una transacción:

1. Comprueba las ocho definiciones esperadas, el sello previo y que solo exista el fallo revisado.
2. Cambia únicamente la huella de la excepción de Citas y recalcula el sello del registro con su fecha de sellado.
3. Exige que permanezcan idénticos la razón, fecha de declaración, otras excepciones y el tope.
4. Ejecuta los siete controles existentes antes de confirmar; cualquier fallo revierte la operación.

No hay cambios de funciones, permisos, clientes, tareas, actividades ni frontend. El script rechaza una segunda aplicación o un estado que haya cambiado; en ese caso corresponde revisar de nuevo, no saltarse sus condiciones.

La huella usada por el registro es el MD5 del cuerpo normalizado con la expresión del censo. Es distinta del MD5 de la definición SQL completa. El cambio de definición mostrado abajo ocurrió en la publicación anterior de Citas; esta corrección conservó el cuerpo `cec7ee9e…` y actualizó únicamente su referencia:

| Huella | Antes | Después revisado |
| --- | --- | --- |
| Registro normalizado | `48702e1a8028340b3a26137027182c98` | `4b28cc419c1b0d84fdbe43afdd5a0909` |
| Definición completa | `6e8935eae3cf1a4c049a93cb20e1f3bd` | `cec7ee9ec1c31ddd8fa17f1d42e88fc1` |

## Pruebas y límites

[resultado-local.json](resultado-local.json) registra la huella SHA-256 del SQL ensayado y los resultados. El banco PostgreSQL 17.10 aislado reproduce el rechazo inicial con las seis definiciones productivas capturadas. La corrección pasa los siete controles y el cierre de reconstrucción. Se verificaron rechazo por sello alterado, rechazo de reaplicación, reversión ante error y conservación de datos, cuerpos y permisos. El ensayo existente de diez alteraciones detectó todas y las revirtió.

El banco es una copia del esquema de integración: tiene 30 contadores frente a los 29 de producción. Ambos respetan el tope 30. Se ajustó solo en la copia el nombre de base de nueve jobs para satisfacer la auditoría de su configuración. No se activó un scheduler, acceso TCP ni conexión a producción. La comparación de datos usa fixtures locales. Las otras dos definiciones verificadas (capital y peso de referido) ya coincidían entre el banco y producción.

[verificar-local.py](verificar-local.py) admite únicamente el banco preparado `citas_control_20260907`, en el socket `/private/tmp/sla-integracion-vtihsz8b`, puerto `55485`, sin TCP y con la marca `LOCAL-SLA-BANK`. No prepara otro banco ni debe apuntarse a producción. El proceso local se detiene al cerrar esta revisión.

[evidencia-produccion.json](evidencia-produccion.json) conserva el diagnóstico anterior a la aplicación. [produccion-antes.json](produccion-antes.json) registra las condiciones previas inmediatas; [produccion-despues.json](produccion-despues.json), la aplicación, comparación y verificaciones posteriores. Los comentarios y estados de la propuesta y del ensayo original se conservan como evidencia histórica del SQL exacto aprobado.

## Cierre de producción

La revisión independiente de Claude y la evaluación de sus observaciones por Codex están en [revision-claude.md](revision-claude.md). La versión final incorpora las comprobaciones de capital y peso de referido. Se descartó el supuesto de columnas anulables: todas tienen `NOT NULL`. El censo productivo tardó 256,703 ms en la medición; se conserva el límite de 30 segundos con reversión ante timeout.

Los siete controles y el cierre de reconstrucción pasan en producción. La comparación confirma una sola huella actualizada, 29 excepciones restantes idénticas, el mismo tope y ocho cuerpos con sus permisos y propietarios sin cambios. El sello actual es `96e3eeda6722eed61315efa724e70e24` y coincide con el cálculo del registro.

El servicio asignó inicialmente la versión `20260908020347`; se alineó únicamente ese identificador con `20260908020020`, conservando el nombre y el SQL registrados. Su MD5 coincide con el artefacto del commit. La operación administrativa ejecutada está en [registro-version-aplicado.sql](registro-version-aplicado.sql).

Las lecturas posteriores de Gerencia (21:08:27 de Lima) vuelven a conciliar agosto y el 1–7 de septiembre. Advisors conserva sus 210 avisos previos, sin nuevos, sin resueltos y sin errores; la comparación ignora únicamente la hora de observación. El frontend mantiene su publicación existente. Este hallazgo queda cerrado.
