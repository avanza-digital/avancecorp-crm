# Verificación del control de Citas — 7 de septiembre de 2026

**Estado: corrección preparada y probada localmente; NO aplicada en producción.** La petición vigente es verificar el hallazgo y recomendar qué hacer.

## Hallazgo e impacto

La publicación `20260907194622_crm_citas_gerencia_bases_y_alcance.sql` actualizó el agregador de Citas, pero dejó la huella de su versión anterior en el registro de excepciones. El cuerpo productivo coincide con el SQL publicado. A las 20:47:48 de Lima hay exactamente un contador declarado cuya huella no coincide: `private.metricas_reuniones_implementacion(date,date)`. El censo contiene 29 contadores, la lista 30 excepciones y el tope sigue en 30.

El control `private.assert_analitica_leads_citas()` falla por esa referencia. Su vigía captura los fallos y los registra en `private.vigia_alertas`. Este control no se ejecuta como parte de la consulta de métricas de Citas; el defecto afecta la verificación interna y el vigía.

Las lecturas con el rol de Gerencia para agosto y para el 1–7 de septiembre responden correctamente: modalidades y orígenes suman lo mismo que el total general; los responsables visibles no lo superan. Esto comprueba respuesta y conciliación de esos cortes, no la exactitud exhaustiva de cada registro o fórmula comercial.

La razón de la excepción sigue siendo válida: el agregador consume los núcleos existentes para estados de citas y cierres; también conserva el uso del núcleo de capital para stock. La ampliación publicada agrega campos y desgloses de esas bases. No hace falta un núcleo nuevo ni cambiar reglas comerciales para resolver este hallazgo.

## Corrección propuesta

El archivo revisable es [correccion-propuesta.sql](correccion-propuesta.sql). En una transacción:

1. Comprueba las ocho definiciones esperadas, el sello previo y que solo exista el fallo revisado.
2. Cambia únicamente la huella de la excepción de Citas y recalcula el sello del registro con su fecha de sellado.
3. Exige que permanezcan idénticos la razón, fecha de declaración, otras excepciones y el tope.
4. Ejecuta los siete controles existentes antes de confirmar; cualquier fallo revierte la operación.

No hay cambios de funciones, permisos, clientes, tareas, actividades ni frontend. El script rechaza una segunda aplicación o un estado que haya cambiado; en ese caso corresponde revisar de nuevo, no saltarse sus condiciones.

La huella usada por el registro es el MD5 del cuerpo normalizado con la expresión del censo. Es distinta del MD5 de la definición SQL completa:

| Huella | Antes | Después revisado |
| --- | --- | --- |
| Registro normalizado | `48702e1a8028340b3a26137027182c98` | `4b28cc419c1b0d84fdbe43afdd5a0909` |
| Definición completa | `6e8935eae3cf1a4c049a93cb20e1f3bd` | `cec7ee9ec1c31ddd8fa17f1d42e88fc1` |

## Pruebas y límites

[resultado-local.json](resultado-local.json) registra la huella SHA-256 del SQL ensayado y los resultados. El banco PostgreSQL 17.10 aislado reproduce el rechazo inicial con las seis definiciones productivas capturadas. La corrección pasa los siete controles y el cierre de reconstrucción. Se verificaron rechazo por sello alterado, rechazo de reaplicación, reversión ante error y conservación de datos, cuerpos y permisos. El ensayo existente de diez alteraciones detectó todas y las revirtió.

El banco es una copia del esquema de integración: tiene 30 contadores frente a los 29 de producción. Ambos respetan el tope 30. Se ajustó solo en la copia el nombre de base de nueve jobs para satisfacer la auditoría de su configuración. No se activó un scheduler, acceso TCP ni conexión a producción. La comparación de datos usa fixtures locales. Las otras dos definiciones verificadas (capital y peso de referido) ya coincidían entre el banco y producción.

[verificar-local.py](verificar-local.py) admite únicamente el banco preparado `citas_control_20260907`, en el socket `/private/tmp/sla-integracion-vtihsz8b`, puerto `55485`, sin TCP y con la marca `LOCAL-SLA-BANK`. No prepara otro banco ni debe apuntarse a producción. El proceso local se detiene al cerrar esta revisión.

[evidencia-produccion.json](evidencia-produccion.json) conserva la última consulta de solo lectura, las huellas, la excepción, el sello, el tope y la conciliación de los dos cortes. La propuesta todavía no se ha ejecutado contra producción.

## Paso recomendado

La revisión independiente de Claude y la evaluación de sus observaciones por Codex están en [revision-claude.md](revision-claude.md). La versión final incorpora las comprobaciones de capital y peso de referido. Se descartó el supuesto de columnas anulables: todas tienen `NOT NULL`. El censo productivo tardó 256,703 ms en la medición; se conserva el límite de 30 segundos con reversión ante timeout.

Presentar el SQL concreto para confirmación, conforme a `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md`. Tras la confirmación, registrar una migración con la convención del proyecto, revalidar las condiciones previas y aplicar esa corrección transaccional. Guardar el resultado de los controles y la comparación de metadatos antes/después. Este ajuste no necesita una publicación nueva del frontend.
