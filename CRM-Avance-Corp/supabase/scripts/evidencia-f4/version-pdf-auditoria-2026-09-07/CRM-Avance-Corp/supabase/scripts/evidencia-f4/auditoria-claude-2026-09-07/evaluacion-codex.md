# F4 — evaluación de la auditoría de Claude

Codex conserva la responsabilidad de implementación. Claude actuó como revisor
secundario, en modo Plan, sin herramientas, escrituras ni delegación. Su
[informe íntegro](informe-claude.md), [procedencia](ejecucion.json) y
[seis archivos exactos de entrada](manifest-entrada.json) quedan conservados.
El informe dice «cinco artefactos», pero enumera y recibió seis.

**G4 permanece abierto.** La opinión estática de Claude no certifica el banco
ni constituye aprobación de F4. La corrección SQL posterior fue comprobada por
Codex; no se atribuye a Claude una revisión de esa versión que no recibió.

## Resultado de la verificación

| Hallazgo | Evaluación y disposición |
|---|---|
| H1 · Ausencia del objeto en el adaptador Deno | **Cerrado para el caso ensayado.** `index.ts` ya normalizaba los códigos numéricos y textuales. El ensayo se amplió para recuperar a través del entrypoint Deno real dos jobs con intento 2 y cero objetos previos: fallo de render y fallo de subida. Ambos generan, descargan y sellan el mismo job sin duplicar la inversión. |
| H2 · Versión de plantilla incompatible retiene la reserva | **Pendiente de compatibilidad del proceso PDF.** La respuesta 409 sin liberar la reserva es anterior a esta corrección. La afirmación de que añade una descarga en cada repetición es incorrecta: la validación de versión retorna antes del nuevo acceso a Storage. No se marca automáticamente una versión desconocida como corrupción: podría ser una versión válida de un despliegue posterior. Falta ensayar y fijar su recuperación sin cambiar el documento. |
| H3 · Subida tardía después de comprobar ausencia | **Riesgo residual abierto.** Los 30 segundos observados eran el timeout HTTP del oráculo, no una garantía de muerte del worker. No se acepta el supuesto de exclusión por `lease > timeout`. La reserva SQL, el token y `upsert:false` protegen el sello y la no sobrescritura; falta ensayar la subida tardía y su terminación acotada. |
| H4 · Petición Storage que no termina | **Pendiente técnico aceptado.** La consulta previa resuelve el reintento observado con objeto existente; no demuestra que toda E/S tenga un límite. El bloqueo observado al repetir la subida de un PDF grande no permite generalizar que todos los 4xx se cuelguen. Se debe diagnosticar/acotar el transporte y cubrir esa carrera antes de dar por completo el bloque de recuperación. |
| H5 · Datos y error nulos | **Comportamiento conservador correcto.** Solo 404 o `NoSuchKey` prueban ausencia; una respuesta ambigua no autoriza subir ni sobrescribir. |
| H6 · Huella antes del tamaño máximo | **Mejora defensiva pendiente, preexistente.** El bucket y el handler tienen límite de 10 MiB; una alteración privilegiada del objeto no equivale a un acceso público. Revisar el consumo de memoria junto con la E/S, sin presentar esta observación como vulnerabilidad demostrada. |
| H7 · Tiempos de recuperación | **Medido en el banco.** La recuperación Deno tardó 40–434 ms por petición en los casos observados; las recuperaciones con render tardaron 234–434 ms. La espera de reserva fue de 120 segundos reales y se informa aparte. No se extrapola a producción. |
| S1 · Relectura de inversión confirmada bloqueada por veto posterior | **Reproducido y corregido localmente.** Antes, confirmar, preparar otra vez y recuperar el acceso de una inversión confirmada devolvían P0429. Ahora se separa autorización vigente de las condiciones para nuevas escrituras. Avance y cooperativa devuelven la misma fuente/inversión; solicitud, PDF, historia y saga quedan intactos. Se conservaron los rechazos para solicitudes nuevas, pendientes y equipo ajeno. La baja del responsable y los cambios de rol siguen en la matriz de permisos dinámicos. |
| S2 · Contratos vinculados no se borran, incluidos demos | **No se acepta rehabilitar el borrado físico.** Conservar el historial y excluir la eliminación física de demos/históricos son requisitos expresos del plan. La anulación y la exclusión económica de demos sí necesitan completar sus ensayos. El vínculo neutral no acredita por sí solo contaminación de Capital: el núcleo conserva el filtro de demos. |
| S3 · Identidad obligatoria para contratos | **Cobertura de puertas pendiente; no es toda una restricción nueva.** La versión original de `public.crear_contrato` ya llama a `asegurar_identidad_perfil` con F3 encendida. El plan registra esa consecuencia desde el 06/09. Queda comprobar todas las rutas heredadas y renovar el recenso antes de un encendido real de F4. |
| S4 · Relectura del origen tras bloquear solicitud | **Defensa incorporada.** `confirmar_inversion_fn` ahora contrasta el origen leído con la fila bloqueada y rechaza cambios con 40001, igual que acceso y revisión. Ninguna puerta actual autorizada cambiaba ese origen. No se congela indiscriminadamente el payload: su corrección trazable es un requisito pendiente. |
| S5 · Sustitución privilegiada de comprobantes | **Límite de confianza, no vía de usuario demostrada.** Las políticas frenan al usuario y la FK frena el borrado; service-role conserva capacidad privilegiada. Guardar tamaño/mimetype no probaría integridad de bytes. El inventario debe revisar todas las rutas con esa credencial y, si procede, incorporar huella verificada desde el servidor. |
| S6 · Errores de negocio y candados en la política de subida | **Serialización intencionada con seguimiento pendiente de UI.** La política vuelve a validar persona, ámbito, veto y solicitud antes de aceptar el objeto; devolver P0429/40001 no autoriza escritura. La autorización precede a los datos de negocio. F5 debe tratar esos rechazos como recarga/revisión, sin relajar RLS. |
| S7 · Unicidad no visible al revisor | **Refutado.** Existen los tres índices únicos: perfil no fusionado, contrato e inversión por cierre. Se capturó su DDL. No se agrega `LIMIT 1` para ocultar una posible incoherencia. |
| S8 · UUID de condición inválido | **Pendiente de validación de entradas.** Adelantar la validación a preparar y dar error de negocio forma parte del bloque de términos/datos; el rechazo actual en confirmar no crea una inversión parcial. |
| S9 · Referencia externa vacía | **Pendiente de validación de correcciones.** La restricción de base impide dejar una inversión F4 sin referencia. Falta un error claro antes del UPDATE y cubrir esa corrección. |
| S10 · Misma clave tras fusión con otro payload | **Contrato intencionado; falta caso específico de cliente.** La clave conserva el payload y la identidad de origen. Reenviar otra identidad con la misma clave debe producir conflicto, aunque ambas resuelvan a la misma canónica. F5 debe reenviar la intención original, no reconstruirla con IDs nuevos. |
| S11 · `es_primera_conversion` en Avance | **Sin defecto económico demostrado.** El censo de funciones vivas encuentra la columna solo en `backfill_multiempresa_ejecutar` e `inversion_vincular_fuente`, ambos escritores. No hay lector financiero de esa columna en el banco ni consumidor de aplicación localizado, aparte de tipos. Capital y conversión siguen sus fuentes canónicas. Esto no sustituye todo el inventario externo. |
| S12 · FK al período sellado | **Protección coherente con el plan.** Un ajuste no debe quedar sin su período original ni justificar reescribir el sello. El paquete de reversa debe conservar esta condición. |

## Evidencia reproducible

- [PDF Deno, 12 grupos y 10 contratos](../pdf-real-f70aa474-7243-4a6e-b545-6853780a6055.json):
  incorpora ausencia real, objetos existentes y tiempos de recuperación.
- [Defecto S1 antes de corregir](../reintento-confirmado-defecto-b2f2ffb9-6c0d-467a-a611-6486d9072033.json)
  y [resultado después](../reintento-confirmado-1fe9b479-35d4-4aa7-84b6-dea34e6d7ab6.json).
- [Nueve oráculos de regresión](../regresion-reintento-2026-09-08T02-12-09.228Z.json):
  cooperativas, Portal, veto, responsable, documento, fusión, carreras de identidad,
  concurrencia y estructura. Todos terminaron satisfactoriamente.
- [Comprobaciones de los índices, consumidores y contenido PDF](../auditoria-comprobaciones-2026-09-08T02-17-23.584Z.json).
- [Estructura de la candidata posterior](../estructura-2026-09-08T02-12-09.151Z.json):
  34 funciones, 17 nuevas y cuatro tablas cerradas al acceso directo.

## Documento contractual y trazabilidad

Miguel indicó conservar el contenido del PDF y pedirle aprobación antes de
cualquier incorporación relativa a cotitulares. **No se cambió la plantilla,
el renderer, la firma, el fondo ni las fuentes.** El cotitular sigue en la tabla
contractual y en el snapshot; la plantilla v7 no lo imprime. Cualquier propuesta
debe mostrar texto y ubicación exactos antes de editar el documento.

El verificador estructural anterior escribía sobre un nombre fijo y sustituyó
la captura asociada al checkpoint de las 19:58. Esa captura original no se
conserva. El checkpoint identifica expresamente la verificación posterior,
mantiene la huella original y explica la sustitución; no se presenta como la
misma captura. El verificador ahora crea archivos únicos con creación exclusiva.
La candidata SQL histórica sí queda archivada byte por byte en `entrada/`.
