# Funciones sueltas y conexiones pendientes del servidor CRM

Revisión del 6 de septiembre de 2026 (Lima). Proyecto **PortalAvanceCorp** (`dctqcbznekcyxhjujuci`). Análisis de solo lectura; no se cambió el servidor.

**[Ver conexiones pendientes en Figma](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=32-395)** · **[Ver candidatas a retiro y falsas alarmas](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=34-395)**

## Resultado para negocio

Encontramos acciones del servidor que no tienen una conexión de pantalla localizada y puertas anteriores que fueron superadas por caminos vigentes. Esto identifica trabajo pendiente y mantenimiento innecesario posible; **no demuestra una interrupción actual del servicio ni justifica borrar funciones automáticamente**.

| Prioridad de revisión | Caso | Evidencia actual | Para qué serviría resolverlo |
|---|---|---|---|
| Primero, funcional | No contactar | `crm.marcar_no_contactar` y `crm.levantar_no_contactar` existen; no aparecen en los consumidores revisados. El CRM lee `no_contactar`. | Que el equipo marque la restricción desde la ficha; que Gerencia la levante con motivo. Al marcar se cancelan las tareas que corresponden. |
| Después, funcional | Mes comercial | `crm.contratos_por_periodo_comercial_fn` y `crm.corregir_fecha_cierre_comercial` existen y no tienen pantalla consumidora localizada. | Consultar ventas por su mes comercial y corregir la atribución mensual con auditoría, respetando meses sellados. |
| Producto pendiente | Agenda | `crm.resumen_tareas_fn` sigue sin consumidor localizado. La memoria documenta que se difirió. | Obtener pendientes, vencidas y señales de seguimiento del servidor. No se concluye que los contadores actuales estén mal. |
| Diseño | Capital | `private.capital_autorizada` no tiene entrada localizada. Los reportes sí llaman `private.capital_episodios` aplicando sus propios controles. | Decidir si se utiliza la puerta común para reducir mantenimiento o se retira. Antes de conectarla hay que respetar la medida, los filtros y los permisos de cada reporte. |
| Limpieza posible | Diez puertas anteriores | Cinco grupos sin consumidor localizado: pagos, PDF, alta de equipo, contratos por producto del esquema crm y consulta antigua por DNI. | Reducir caminos paralelos, nombres confusos y mantenimiento. Verificación externa y observación de uso antes de un retiro. |

**Precisión sobre No contactar:** no se localizó una acción de la pantalla que marque o levante la restricción; no se afirma que exista hoy un botón que esté fallando. El trigger `trg_leads_000_no_contactar_puerta` está habilitado. Con `resolver_en_puertas=false` conserva el comportamiento anterior; al activar la identidad rechaza cambios directos de la marca salvo la operación privilegiada de sus puertas. Es un pendiente para operar estas acciones desde el CRM; este análisis no redefine por sí solo el plan de activación.

## Las diez puertas para revisar

| Función | Camino vigente / motivo de revisión |
|---|---|
| `public.pagos_admin_metricas_globales` | La pantalla publicada de Pagos llama `public.admin_pagos_metricas`. |
| `public.pagos_admin_resumen_contratos` | La pantalla publicada de Pagos llama `public.admin_pagos_resumen`. |
| `crm.contrato_pdf_archivo_fn` | El flujo vigente utiliza la Edge `crm-contrato-pdf-v2` y puertas actuales de estado/archivo. Sus auxiliares internos siguen conectados. |
| `crm.contrato_pdf_snapshot_v2` | Puerta anterior sin consumidor localizado; ejecución de usuario revocada. No confundir con `private.contrato_pdf_snapshot_v2_base`, que sí tiene conexiones. |
| `crm.registrar_candidato_usuario_fn` | La Edge desplegada `crm-usuarios` llama `crm.registrar_vendedor_usuario_fn`. |
| `crm.crear_contrato_producto` | Sin consumidor localizado y sin EXECUTE de authenticated; CRM entra por la puerta con PDF. |
| `crm.crear_contrato_con_cuenta_producto` | Igual: puerta anterior del CRM con permiso de usuario revocado. |
| `crm.actualizar_contrato_producto` | Igual; no extender la conclusión a la función homónima del esquema public. |
| `crm.actualizar_contrato_con_cuenta_producto` | Igual; la actualización actual usa `crm.actualizar_contrato_con_cuenta_pdf_v3`. |
| `crm.existe_cliente_por_dni` | Consulta antigua sin consumidor localizado. La creación de leads utiliza `crm.verificar_disponibilidad_lead`; aclarar posibles consumidores externos. |

No se ha verificado una ventana reciente de tráfico de estas diez funciones. “Camino anterior” significa que no se localizó su entrada en las fuentes revisadas y, donde se indica, se encontró una alternativa usada; no significa una equivalencia exacta de firmas o permisos.

## Falsas alarmas que se descartaron

- **Distribución:** v3 utiliza los motores internos v2 y base. La puerta `crm.metricas_distribucion_leads_fn` v1 tiene EXECUTE para `crm_metricas_bridge`; su consumidor externo no fue identificado. No se propone retirarla.
- **Herramientas de operación:** `private.assert_auditoria` y `private.veredicto_f7` tienen scripts de comprobación; `private.backfill_multiempresa_ejecutar` y su auxiliar preparan identidad; `public.marcar_contrato_demo` tiene uso manual documentado. No necesitan estar conectadas a una pantalla.
- **Identidad unificada:** corrección de documentos, fusiones, reasignación de responsable y rescates de conversión son piezas previstas. Las tres banderas siguen apagadas. Algunas acciones esperan interfaz y otras se operan manualmente.
- **Solicitudes de tasa:** pedir, resolver y responder al tope esperan la etapa R3. Política v1 en `observacion`; el observador de contratos ya alcanza el núcleo por otra ruta. No declarar muerto el núcleo porque la puerta de pantalla no se consume.
- **Diagnóstico push:** Edge `diagnostico-push` retirada a propósito, con respuesta 410; diferente de `enviar-push`.

## Método y límites

1. Catálogo vivo: 476 firmas de funciones SQL de crm/private/public, sus cuerpos, lenguaje, permisos y comentarios.
2. Dependencias registradas de triggers, políticas y otros objetos; nombres invocados en cuerpos SQL/PLpgSQL, incluidos nombres de función pasados en rutas dinámicas cuando son visibles.
3. Código de las 16 Edge Functions desplegadas, incluyendo los archivos auxiliares devueltos.
4. Nueve tareas programadas: nombres de las funciones que llaman. Se excluyeron del informe comandos completos y secretos.
5. Código local de CRM y Portal, excluyendo tipos generados y pruebas del censo de consumidores de pantalla; scripts y notas se examinaron para detectar usos técnicos, planes y operaciones manuales.
6. Archivos JavaScript publicados accesibles desde el CRM y sus referencias de módulos: 48 archivos descargados correctamente. También se comprobaron `miavance.com/js/admin/pagos.js` y `contratos.js`. La búsqueda encontró además el texto “Node.js” dentro de una dependencia; se excluyó como falso enlace, no como módulo faltante.
7. El análisis estático inicial dejó **44 firmas sin camino desde los consumidores automáticos o de pantalla localizados**. La tabla siguiente clasifica esas firmas: incluye auxiliares, herramientas manuales y fases preparadas; no son 44 errores ni 44 funciones muertas.

La búsqueda textual es conservadora: una coincidencia puede ser una referencia o una llamada dinámica, y las sobrecargas con el mismo nombre requieren revisión de firma. PostgreSQL no registra todas las llamadas internas de PL/pgSQL en pg_depend. Este informe combina fuentes, pero no sustituye una medición de ejecución.

`track_functions=none`, con cero funciones en `pg_stat_user_functions`: **no hay un contador habilitado que permita probar desuso por esa vía**. No se activó ni reinició instrumentación. No se leyó el Apps Script instalado en Google; se revisó únicamente su copia local, que apunta a `crm-importar-leads`. Tampoco se inspeccionaron clientes SQL externos del rol `crm_metricas_bridge`. Las pantallas locales pueden contener cambios posteriores al último despliegue; el informe conserva ambas evidencias.

## Clasificación de las 44 firmas

| Función | Clasificación |
|---|---|
| `crm.abandonar_conversion_gerencia_fn` | Preparada · Identidad unificada apagada |
| `crm.actualizar_contrato_con_cuenta_producto` | Revisión de retiro · Camino anterior |
| `crm.actualizar_contrato_producto` | Revisión de retiro · Camino anterior |
| `crm.contrato_pdf_archivo_fn` | Revisión de retiro · Camino anterior |
| `crm.contrato_pdf_snapshot_v2` | Revisión de retiro · Camino anterior |
| `crm.contratos_por_periodo_comercial_fn` | Pantalla pendiente · Período comercial |
| `crm.corregir_documento_inversionista_fn` | Preparada · Identidad unificada apagada |
| `crm.corregir_fecha_cierre_comercial` | Pantalla pendiente · Período comercial |
| `crm.crear_contrato_con_cuenta_producto` | Revisión de retiro · Camino anterior |
| `crm.crear_contrato_producto` | Revisión de retiro · Camino anterior |
| `crm.enlazar_lead_inversionista_fn` | Preparada · Identidad unificada apagada |
| `crm.existe_cliente_por_dni` | Revisión de retiro · Camino anterior |
| `crm.fusion_previsualizar_fn` | Preparada · Identidad unificada apagada |
| `crm.fusionar_inversionistas_fn` | Preparada · Identidad unificada apagada |
| `crm.levantar_no_contactar` | Pantalla pendiente · No contactar |
| `crm.marcar_no_contactar` | Pantalla pendiente · No contactar |
| `crm.metricas_distribucion_leads_fn` | Uso externo por aclarar · No retirar |
| `crm.publicar_politica_rentabilidad_fn` | Preparada · Solicitudes de tasa |
| `crm.reasignar_responsable_relacion_fn` | Preparada · Identidad unificada apagada |
| `crm.registrar_candidato_usuario_fn` | Revisión de retiro · Camino anterior |
| `crm.resolver_solicitud_tasa_fn` | Preparada · Solicitudes de tasa |
| `crm.resolver_tasa_fn` | Preparada · Solicitudes de tasa |
| `crm.responder_tope_tasa_fn` | Preparada · Solicitudes de tasa |
| `crm.resumen_tareas_fn` | Pantalla pendiente · Agenda |
| `crm.retomar_conversion_gerencia_fn` | Preparada · Identidad unificada apagada |
| `crm.solicitar_tasa_fn` | Preparada · Solicitudes de tasa |
| `private.assert_auditoria` | Uso técnico/manual documentado |
| `private.backfill_multiempresa_ejecutar` | Uso técnico/manual documentado |
| `private.bloquear_leads_nowait` | Pantalla pendiente · No contactar |
| `private.cancelar_tareas_pendientes_lead` | Pantalla pendiente · No contactar |
| `private.capital_autorizada` | Revisión de diseño · Capital |
| `private.documento_es_de_identidad` | Preparada · Identidad unificada apagada |
| `private.f2_mapear` | Uso técnico/manual documentado |
| `private.fusion_bloqueos` | Preparada · Identidad unificada apagada |
| `private.fusion_estado_jsonb` | Preparada · Identidad unificada apagada |
| `private.huella_solicitud_tasa` | Preparada · Solicitudes de tasa |
| `private.leads_de_persona_veto` | Pantalla pendiente · No contactar |
| `private.motivo_sin_documento` | Preparada · Identidad unificada apagada |
| `private.puede_operar_tasa_cliente` | Preparada · Solicitudes de tasa |
| `private.vencer_solicitudes_tasa` | Preparada · Solicitudes de tasa |
| `private.veredicto_f7` | Uso técnico/manual documentado |
| `public.marcar_contrato_demo` | Uso técnico/manual documentado |
| `public.pagos_admin_metricas_globales` | Revisión de retiro · Camino anterior |
| `public.pagos_admin_resumen_contratos` | Revisión de retiro · Camino anterior |

## Evidencia conservada

- [Cuerpos y dependencias del servidor](./evidencia-funciones-conexiones.json)
- [Clasificación y relaciones localizadas](./clasificacion-funciones-sin-entrada.json)
- [Referencias en código local](./referencias-frontend-funciones.json)
- [Referencias y huellas de archivos publicados](./referencias-frontend-publicado.json)
- [Verificación visual del diagrama](./verificacion/conexiones-0.png)

La memoria anterior de saneamiento P-053 ayudó a localizar candidatos, pero no se copió como estado vigente: por ejemplo, `resumen_cartera_clientes_fn` ya aparece en el CRM publicado y se excluyó de los huérfanos.

## Siguiente trabajo propuesto

Para aprovechar funciones disponibles: conectar acciones de No contactar y del período comercial con sus permisos, validaciones y mensajes; decidir la integración del resumen de Agenda. Son cambios de producto, fuera del alcance de esta revisión y del diagrama.

Para simplificar el servidor: aclarar integraciones externas, medir uso durante una ventana representativa y preparar retiros reversibles por grupo. La puerta común de capital necesita una decisión de diseño y comparación de resultados antes de cualquier cambio.
