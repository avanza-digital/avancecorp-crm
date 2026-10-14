# Plan de mecanismos de responsabilidad y atribución

Estado: implementado y probado en banco aislado el 13/10/2026. Resultado y límites en [VERIFICACION.md](VERIFICACION.md). Autorizados el núcleo privado, el adaptador compatible en `public` y el bloqueo del cambio directo de asesor. Atención completa permitida a Gerencia y administradores del portal. Producción fuera de alcance.
Fecha: 13 de octubre de 2026.

El caso 001595 requiere corregir al vendedor del contrato. Cambiar la atención del cliente tiene otro efecto. Las dos acciones se presentarán por separado y compartirán las reglas del servidor utilizadas por Facturación. [Diagnóstico y evidencia](AUDITORIA.md).

## Resultado para el usuario

| Acción | Qué confirma el usuario | Qué garantiza el servidor |
| --- | --- | --- |
| Cambiar quién atiende al cliente | Responsable anterior y nuevo; cliente afectado; tareas y leads operativos que pasan; efectos económicos excepcionales por baja | Alinea las referencias de atención que correspondan en una transacción. Conserva el vendedor histórico. Muestra y verifica la herencia efectiva cuando aplique |
| Corregir el dueño de una venta | Contrato, fecha, moneda, importe, vendedor anterior y nuevo, motivo y contratos vinculados afectados | Cambia la atribución autorizada con historial, conserva el capital y comprueba el resultado de la atribución efectiva |

La pantalla no deduce la intención a partir del motivo libre. Escribir «venta de Jorge» no sustituye seleccionar la acción de corregir una venta.

## Arquitectura de cuatro capas

1. **Pantalla:** consume únicamente las puertas a través del módulo de datos. Presenta la vista previa que devuelve el servidor y confirma una acción concreta.
2. **Puertas:** funciones expuestas en `crm`, delgadas y versionadas cuando cambie el contrato. Validan entrada, autorizan y delegan.
3. **Núcleo:** funciones en `private` para resolver impacto, cambiar atención y corregir atribución. Concentración de las reglas, candados y postcondiciones.
4. **Tablas:** se reutilizan perfiles, personas, tramos de responsables, contratos e historiales existentes. No se propone crear una tabla de negocio nueva ni exponer `private`.

El código nuevo no debe llamar desde el núcleo a una puerta. La lógica actual de `crm.reasignar_responsable_relacion_fn` pasará a un núcleo privado y conservará una puerta compatible. La lógica de `public.reasignar_analista_contrato` también debe tener un núcleo privado único, conservando su firma actual como adaptador para consumidores existentes.

## Contrato de la operación

### Vista previa de solo lectura

- Resuelve actor, permisos, identidad canónica, responsables, estado del contrato y equipo.
- Calcula por separado vendedor registrado y analista efectivo de facturación.
- Enumera la operación y cualquier descendiente de una cadena que resultaría afectado.
- Separa PEN y USD; muestra la distribución anterior y prevista sin mezclar monedas.
- Devuelve una versión del estado relevante. No escribe, no simula con UPDATE y no bloquea filas durante la interacción humana.
- La versión incluye vendedor almacenado, analista efectivo de cada contrato/desglose, identidad canónica y estado, tramo vigente, asesor del perfil, membresías activas de origen/destino, jerarquía y conjunto de descendientes. Se vuelve a resolver bajo candados al confirmar.
- No entrega identidades ni contratos fuera del ámbito autorizado.

### Confirmación atómica

- Vuelve a autorizar dentro del núcleo y bajo los candados necesarios.
- Revalida la versión y el conjunto afectado; no confía en importes, rol o alcance enviados por la pantalla.
- Reutiliza el orden de candados de identidad, jerarquía, tareas y contratos del proyecto. Conflictos concurrentes exigen relectura y una nueva confirmación.
- Guarda el cambio y su historial en la misma transacción. Una validación fallida revierte ambos.
- Una repetición no debe generar un segundo movimiento ni un segundo historial. Se devuelve un resultado inequívoco o un conflicto que obliga a releer; no se promete una idempotencia que no esté respaldada por datos.
- Verifica las postcondiciones con el núcleo de atribución y facturación antes de devolver éxito. La pantalla refresca las lecturas afectadas con ese resultado, sin hacer dos escrituras independientes.

## Límites de cada núcleo

### Atención del cliente

Alinear el responsable canónico, el tramo vigente y el asesor de perfil donde exista cartera operativa, junto con los leads abiertos y tareas aplicables. Preservar las excepciones vigentes para responsables de Gerencia, identidades fusionadas/inactivas, bandeja y operaciones confirmadas. No convertir una diferencia legítima en una transferencia de ventas.

El retorno actual `sin_cambios` compara solo el tramo: debe comprobar también las referencias que el núcleo garantiza. Si están desalineadas, debe conciliar con rastro o rechazar claramente; no devolver éxito dejando una inconsistencia sin informar.

Cerrar la vía del portal que escribe directamente el asesor para esta operación. El portal utilizará una puerta autorizada con la misma política de permisos que su vía anterior. No ampliar los permisos del CRM por reutilizarla. Para perfiles sin persona unificada, resolver un camino explícito sin crear inversiones o identidades por accidente.

### Atribución de la venta

Conservar la autoría de registro y usar el historial de reasignaciones existente. La corrección de 001595 es independiente de la atención: una operación de PEN 150.000 pasa de Fiorella a Jorge; las demás operaciones de Fiorella y el capital total por moneda se conservan.

En renovaciones/upgrades, corregir el campo del contrato puede no modificar el analista efectivo o puede afectar descendientes. El núcleo debe exponer ese alcance y rechazar una confirmación que no corresponda al efecto mostrado. No reasignar automáticamente todos los contratos de un cliente.

Los desgloses de `crm.operaciones_cartera` requieren prueba independiente: `capital_episodios` usa `o.vendedor_id` como respaldo, mientras el stock contractual usa `c.analista_cierre_id`. No se cambiará la autoría histórica de la operación para ocultar esa diferencia. Si la atribución de un desglose no acompaña la corrección según el contrato comercial aprobado, la candidata debe rechazar el éxito y resolver esa regla antes de habilitar dicho caso. 001595 no tiene desgloses y el censo de octubre no encontró divergencias efectivas por esta vía; es un riesgo de regresión a probar, no una segunda causa del caso.

La corrección de vendedor de cooperativas queda fuera de la primera entrega: no usa la puerta contractual. Su atención y herencia sí deben verificarse. La interfaz no ofrecerá una corrección contractual sobre una cooperativa.

Respetar las reglas de baja y snapshots sellados. Una modificación del historial de conversión de leads no forma parte automática de esta acción; cualquier efecto adicional debe ser explícito y probado.

### Prevención en el alta

La solicitud de 001595 se creó por `cartera`: el servidor tomó al responsable Fiorella como vendedor, aunque Jorge registró la operación. El alta debe mostrar el vendedor que resolverá el servidor y exigir una confirmación clara del importe y atribución antes de crear la inversión. No se presume que registrador y vendedor deban coincidir. La regla de venta cruzada que fija vendedor = registrador conserva su contrato y sus controles.

## Compatibilidad y autorización de public

Objeto actual que necesariamente interviene: `public.reasignar_analista_contrato(uuid,uuid,text)`.

Se propone conservar su firma y política de permisos y sustituir su cuerpo por delegación al núcleo privado único, evitando mantener dos implementaciones. La compatibilidad conserva firma, respuesta de éxito, autorización, historial y rechazo por membresía revocada. Los conflictos nuevos de concurrencia salen como `PT409` (HTTP 409) y el legado rechaza cadenas con alcance ampliado no confirmado; se comprobarán todos los consumidores.

Los controles del camino legado no pueden permitir saltarse las garantías de integridad del núcleo. Cualquier requisito nuevo incompatible con su firma debe resolverse con despliegue coordinado o puerta versionada; no inventar un valor de confirmación para aparentar que el usuario vio una vista previa.

El cierre completo de la vía directa del portal requiere además un control de servidor sobre el cambio de `public.perfiles.asesor_perfil_id`; cambiar solo el JavaScript dejaría la vía antigua disponible. Se propone un candado que permita las operaciones de núcleo autorizadas y rechace el UPDATE directo. **Control autorizado expresamente por Miguel el 13/10/2026.** Antes de escribirlo se inventariarán altas, bajas, fusiones, reasignaciones y cualquier escritor actual para conservar sus caminos legítimos y el orden de candados. No se aplicará un bloqueo general sin adaptar y probar esos consumidores.

Decisión aprobada: Gerencia y administradores activos del portal pueden trasladar la atención completa. Una membresía CRM revocada invalida también el permiso del portal. La puerta legado de Gerencia conserva su gate anterior.

El permiso específico sobre `public`, el adaptador y el candado fue concedido junto con la implementación y las pruebas en banco aislado. No incluye producción.

## Implementación y verificación

1. Guardar cuerpos, firmas, permisos, dependencias y huellas vigentes; inventariar envoltorios y consumidores publicados. Baseline de consultas y advisors.
2. Crear el banco aislado en Docker, con esquema a paridad y datos sintéticos. No usar producción como banco.
3. Nueva migración para los núcleos y puertas; migración de hardening según las reglas del repo; ambas con reversa, comentarios y ledger. Nunca editar migraciones históricas.
4. Adaptar CRM y la operación de asignación del portal a las puertas. No reestructurar otros módulos ni modificar sus operaciones por esta tarea.
5. Ejecutar pruebas SQL/HTTP con RLS real y casos permitidos/denegados. Verificar aislamiento, ACL mínima, `search_path`, reversa y reinstalación. Justificar cada SECURITY DEFINER; núcleo invoker siempre que el diseño lo permita.
6. Regenerar tipos desde el banco candidato, validar payloads y ejecutar los gates frontend y de scripts pertinentes; E2E local en Docker.
7. Revisión independiente con evidencia y auditoría RLS; resolver hallazgos con pruebas. Repetir los checks afectados, comparar advisors y entregar el artefacto listo.
8. Publicación como etapa separada bajo las reglas de rama/commit/release del proyecto. No aplicar una migración directamente a producción.

### Pruebas que deben impedir la regresión

| Caso | Resultado exigido |
| --- | --- |
| Cambiar solo atención con vendedor activo | Responsables operativos coherentes; atribución contractual y facturación histórica conservadas |
| Corregir 001595 sintético | Fiorella − PEN 150.000, Jorge + PEN 150.000; capital global igual; las otras cuatro operaciones intactas |
| Motivo «venta de Jorge» en la acción de atención | No se interpreta como orden de reasignar contratos |
| Perfil y persona desalineados, tramo ya igual al destino | Conciliación o rechazo explícito; no éxito incompleto |
| Monto, dueño, jerarquía o cadena cambian después de previsualizar | Confirmación antigua rechazada sin escrituras |
| Supervisor registra alta para una cartera de otro analista | Se confirma el vendedor resuelto; no se usa automáticamente al registrador |
| Renovación sin ancestro upgrade y con desgloses | Atribución de stock, renovado y adicional coherente con la decisión; sin modificar autoría para forzarla |
| Dos correcciones simultáneas y reintentos | Resultado coherente y sin historial duplicado |
| Fallo al escribir historial o verificar resultado | Rollback completo |
| Upgrade con renovaciones | Alcance mostrado igual al ejecutado; se conservan reglas de adopción |
| Analista dado de baja | Herencia efectiva mostrada, comprobada y sin atribuir éxito al nombre equivocado |
| Mes sellado | Snapshot conservado; comportamiento vivo explicado y probado |
| Roles, usuario revocado, sin sesión y llamadas al núcleo | Solo vías y ámbitos autorizados |
| CRM y portal | Mismo resultado de negocio y políticas de acceso conservadas |
| Cifra y detalle tras corregir | Coinciden por día, tipo, moneda, analista y supervisor |

Una consulta de conciliación debe distinguir diferencias legítimas entre atención y venta de incumplimientos de una operación confirmada. Nunca mover ventas automáticamente porque sus dos nombres no coincidan.

## Estado de las puertas de aprobación

- Aprobado: dos acciones separadas y efecto visible antes de guardar.
- Requisito ratificado: reglas de backend del proyecto.
- Aprobado expresamente: plan técnico, modificación compatible de la función de `public`, candado de escritura directa y atención completa por Gerencia y administradores del portal.
- No ejecutado: corrección puntual, migraciones ni release en producción. Las dos migraciones candidatas se probaron únicamente en el banco aislado.
