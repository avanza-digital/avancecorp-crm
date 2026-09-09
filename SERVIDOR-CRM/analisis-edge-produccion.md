# Edge Functions del servidor CRM Avance Corp

Lectura de producción realizada el 6 de septiembre de 2026, hora de Lima (7 de septiembre UTC). Proyecto Supabase `dctqcbznekcyxhjujuci`. Fuente principal: contenido desplegado obtenido con `supabase_get_edge_function`; versiones contrastadas con `inventario-produccion.json`. No se ejecutaron las funciones, no se consultaron clientes y no se modificó el servidor. Las fuentes descargadas permanecieron en memoria; este informe no contiene credenciales ni datos personales.

## Cómo leer esta parte del servidor

Una **Edge Function** es un encargado que recibe una solicitud, verifica permisos, pide trabajo a la base de datos y, cuando corresponde, llama a correo, notificaciones o archivos. Una **RPC** es una operación con nombre dentro de PostgreSQL: concentra reglas comerciales. Una **bifurcación** es una decisión que lleva por caminos distintos; no es automáticamente un defecto.

**La conversión del lead crea o enlaza al cliente. El contrato se registra por otra operación.** Las funciones de avisos comunican pagos o vencimientos; no transfieren dinero.

## Estado que cambia el dibujo

La inspección de las 16 funciones encontró estado de despliegue `ACTIVE`. Sin embargo, `diagnostico-push` solo responde HTTP 410 (`gone`): está desplegada pero retirada funcionalmente.

El análisis SQL del equipo confirmó `resolver_en_puertas=false`, `inversiones_escritura=false` y `ficha_360_neutral=false`. En particular, **la nueva identidad unificada está preparada en las funciones de alta/conversión, pero su camino está apagado**. En el diagrama, la ruta vigente debe ir con línea continua; la alternativa preparada, con línea discontinua y la etiqueta «apagada hoy».

## Inventario explicado para negocio

| Función exacta | Versión | Para qué sirve comercialmente | Conexiones principales |
|---|---:|---|---|
| `crm-importar-leads` | 19 | Recibe prospectos por lotes, revisa datos y devuelve el resultado de cada fila. | `crm.destinos_importacion_por_correo_fn`, `crm.importar_lead_fn` |
| `crm-convertir-lead` | 14 | Convierte un prospecto trabajado en cliente del portal, conservando su responsable comercial. | `crm.mi_acceso_fn`, `crm.leads`, `crm.reservar_conversion_lead`, `crm.convertir_lead_con_domicilio`, Auth, `public.perfiles`, Resend |
| `crear-cliente` | 33 | Da de alta a un cliente directamente desde una operación autorizada del Portal o del CRM. | `crm.mi_acceso_fn`, `crm.bandera_activa`, Auth, `public.perfiles`, Resend |
| `importar-clientes` | 15 | Carga clientes en lote con sus datos bancarios; permite previsualización. | Auth, `public.perfiles`, `crm.bandera_activa`; `crm.alta_cliente_identidad_fn` en rama apagada |
| `eliminar-cliente` | 8 | Elimina un cliente permitido por sus controles de negocio; exige que no tenga contratos en el camino vigente. | `public.contratos`, `public.novedades`, `public.perfiles`, Auth; `crm.eliminar_cliente_fn` en rama apagada |
| `crm-contrato-pdf-v2` | 12 | Prepara el PDF del contrato, comprueba el archivo y permite descargarlo; también coordina la eliminación del contrato y sus archivos. | RPC de PDF/eliminación en `crm`, Storage `contratos-generados` y `documentos` |
| `ciclo-contratos` | 6 | Marca vencimientos y avisa para que cliente y asesor coordinen renovación o retiro. | `public.marcar_contratos_vencidos`, `public.contratos`, perfiles, equipo, novedades, push, Resend |
| `notificar-pagos` | 9 | Confirma pagos registrados y recuerda pagos programados para dentro de tres días. | `public.cronograma_pagos`, contratos/perfiles, novedades, push, Resend |
| `enviar-comunicado` | 15 | Envía un comunicado a un destinatario o al conjunto previsto por su consulta. | Perfiles/contratos, Resend y llamada interna a `enviar-push` |
| `enviar-push` | 7 | Envía alertas a los dispositivos suscritos de un cliente o de todos los destinatarios seleccionados. | `public.suscripciones_push`, proveedor push del navegador |
| `diagnostico-push` | 7 | Antigua herramienta de diagnóstico, hoy retirada. | Ninguna: devuelve HTTP 410 |
| `crm-tipo-cambio` | 8 | Obtiene una referencia USD→PEN para poder comparar capitales en una misma moneda. | API pública del BCRP; no usa base de datos |
| `crm-agenda-ics` | 7 | Muestra tareas del miembro del CRM en un calendario por suscripción. | `crm.agenda_ics_feed_fn`; produce un archivo/calendario ICS |
| `crm-usuarios` | 7 | Da de alta vendedores del CRM con autorización comercial y reintentos controlados. | `crm.buscar_candidato_por_correo_fn`, Auth, `crm.registrar_vendedor_usuario_fn` |
| `crear-admin` | 18 | Crea cuentas administrativas del Portal según el nivel del administrador. | Auth, `public.perfiles` |
| `resetear-password` | 7 | Permite al administrador restablecer la contraseña de una cuenta autorizada. | Auth, `public.perfiles` |

## Bifurcación 1 — Entrada de prospectos

Recorrido vigente: conector de la hoja → `crm-importar-leads` → revisión de filas → resolución de vendedor → `crm.importar_lead_fn` → resultado por fila.

El origen Google Sheets/Apps Script está documentado en el vault. Esta revisión confirmó el receptor desplegado, no inspeccionó ni ejecutó el Apps Script vivo.

- **Datos correctos / datos incorrectos:** nombre, teléfonos, capital, moneda, canal y demás campos se revisan. Una fila mala no detiene todo el lote.
- **Vendedor encontrado / no encontrado:** si el correo corresponde a un destino válido se asigna; si no existe, entra «por repartir». Si falla técnicamente la resolución de destinos, el lote falla de forma temporal: no lo interpreta como ausencia de vendedor.
- **Importado / duplicado / ya cliente / rechazado / error temporal:** son resultados distintos para que el equipo sepa si trabajar, corregir o reintentar. `ya_cliente` depende de la decisión de identidad en SQL; no debe dibujarse como camino necesariamente activo con la bandera apagada.
- La Edge elimina repetidos dentro del mismo lote, pero la decisión contra la base ya se delega a `crm.importar_lead_fn`.
- Un teléfono alternativo válido puede rescatar una fila; se prioriza un móvil como teléfono principal. La columna de consentimiento puede registrar el sello de aceptación, pero `NO` o vacío no bloquean por sí solos la importación.

Evidencia: `crm-importar-leads/index.ts`, líneas 433–536; schema CRM configurado en línea 225.

## Bifurcación 2 — Convertir prospecto en cliente

Antes de cualquier alta se verifica sesión, `crm.mi_acceso_fn` (`puede_contratar`) y acceso al lead dentro del ámbito del usuario. El lead debe conservar responsabilidad comercial previa; no se atribuye automáticamente al usuario que aprieta el botón.

**Camino vigente, identidad apagada:**

1. `crm.reservar_conversion_lead` reserva la conversión de ese prospecto.
2. Si el documento ya corresponde a un perfil de cliente activo, reutiliza ese cliente.
3. Si no existe, `crm.marcar_efectos_conversion` sella la reserva y crea Auth + `public.perfiles`. Si falla el perfil, intenta deshacer la nueva cuenta Auth.
4. `crm.convertir_lead_con_domicilio` enlaza el cliente y cierra el prospecto; el domicilio se completa dentro de la operación autorizada.
5. El correo de bienvenida sale después del cierre y solo cuando se creó una cuenta nueva. Si el correo falla, no deshace una conversión ya realizada.

**Camino preparado, apagado:** reserva por persona/documento, `crm.saga_conversion_fn`, recuperación de intentos previos y cierre con la identidad reservada. La secuencia distingue `crear_auth`, `crear_perfil`, `enlazar`, `listo` y persona ya existente. «Saga» significa aquí recordar hasta qué paso llegó el alta para retomarla sin duplicar a la persona.

La bandera también cambia la respuesta ante un reintento de un lead ya convertido: en el camino preparado puede devolver el resultado previo sin crear ni enviar otra bienvenida; en el camino vigente el lead cerrado se rechaza.

La conversión a cooperativa es otra puerta SQL, `crm.convertir_lead_externo`, mencionada por la protección de reservas de esta Edge. Debe representarse como un ramal comercial distinto hacia cierre externo; su cuerpo SQL corresponde al análisis principal, no fue invocado aquí.

Evidencia: `functions/crm-convertir-lead/index.ts`, líneas 94–157, 212–365, 367–505 y 513–550.

## Bifurcación 3 — Alta directa o en lote

`crear-cliente` admite dos autoridades: los roles históricos autorizados del Portal y la capacidad CRM de `crm.mi_acceso_fn`. Una revocación CRM explícita impide el uso del camino de compatibilidad. El analista histórico o vendedor CRM se autoasigna como asesor; Supervisión, Gerencia y administradores crean sin apropiarse de la cartera.

Con identidad apagada, `crear-cliente` y `importar-clientes` crean Auth + perfil. Con identidad encendida, ambas usan `crm.alta_cliente_identidad_fn` para reclamar a la persona y seguir su avance. `importar-clientes` conserva previsualización `dry_run` y resultados separados por fila.

`eliminar-cliente` también conserva dos caminos. Hoy comprueba ausencia de contratos, elimina novedades dirigidas y perfil, y después elimina Auth. El camino preparado concentra la operación de negocio en `crm.eliminar_cliente_fn` antes de Auth. Esto permite localizar varias puertas que afectan a la misma identidad.

Evidencia: `crear-cliente/autorizacion.mjs`; `functions/crear-cliente/index.ts`, líneas 176–369; `functions/importar-clientes/index.ts`, líneas 141–331; `eliminar-cliente/index.ts`, líneas 88–158.

## Bifurcación 4 — Contrato y PDF tienen estados separados

La Edge `crm-contrato-pdf-v2` recibe solo la acción y el identificador del contrato. No permite que el navegador invente un PDF libre: obtiene la información autorizada del servidor.

| Acción | Recorrido | Explicación comercial |
|---|---|---|
| `status` | `crm.contrato_pdf_estado_fn` → comprobar archivo si está sellado → URL temporal | Consultar si el documento está listo. |
| `ensure` | `crm.contrato_pdf_reservar` → `crm.contrato_pdf_reclamar` → renderizar → subir → descargar y verificar → `crm.contrato_pdf_marcar_subido` → `crm.contrato_pdf_finalizar` | Crear o recuperar el documento del contrato sin pisar a otro intento. |
| `delete` | `crm.contrato_eliminacion_preparar` → eliminar objetos permitidos de ambos buckets → `crm.contrato_eliminacion_finalizar` | Coordinar la eliminación autorizada del contrato y sus archivos; no es simplemente ocultar un PDF. |

Estados: `sin_reserva`, `pendiente`, `procesando`, `subido_verificado`, `sellado`, `error_reintentable`, `integridad_bloqueada`. El bloque listo entrega una URL firmada válida por **300 segundos**. Un fallo recuperable usa `crm.contrato_pdf_marcar_error`; una divergencia del contenido bloquea la integridad.

**Punto clave para negocio:** un contrato registrado puede tener el PDF pendiente. Reintentar obtener el PDF no debería interpretarse como registrar otro contrato. El mapa debe separar «contrato existe» de «documento listo».

Evidencia: `crm-contrato-pdf-v2/handler.ts`, líneas 643–645, 674–741, 827, 842–1100. Buckets privados contrastados en análisis SQL: `contratos-generados` y `documentos`.

## Bifurcación 5 — Avisos y vencimientos

`notificar-pagos` distingue:

- `pagado`: busca las cuotas indicadas que ya están pagadas y aún no tienen sello de aviso.
- `recordatorio`: busca cuotas pendientes con fecha programada exactamente hoy + 3 días, en hora de Lima.

Ambas rutas agrupan por cliente activo y generan tres salidas: novedad en portal, push del dispositivo y correo por Resend. **No se registra ni ejecuta el pago dentro de esta Edge.**

`ciclo-contratos` ejecuta el evento `diario`: primero llama `public.marcar_contratos_vencidos`; después busca dos ventanas separadas de contratos activos por vencer: hoy a +7 días y +8 a +30 días. Avisa al cliente por novedad/push/correo, y al asesor elegible por push/correo. Los asesores deben tener perfil activo y membresía CRM activa de vendedor o supervisor.

Las dos funciones admiten secreto de cron validado por `public.verificar_cron_secret` o usuario administrativo autorizado. `verify_jwt=false` no significa ausencia de control: estas rutas validan credenciales dentro de su cuerpo. También admiten `dry_run`, pero no fue ejecutado en esta revisión.

**Lugar para marcar en ámbar:** ambas sellan el aviso antes de enviar los canales, con el fin de evitar avisos dobles por corridas simultáneas. El sello significa que la corrida tomó el aviso; no acredita entrega de correo/push. Sus fallos de envío se contabilizan o registran, pero no se vio una cola por canal con confirmación de entrega en estos cuerpos. Además, el recordatorio de pagos usa un día exacto; los avisos de vencimiento usan ventanas que pueden recuperar días intermedios sin ejecución.

Evidencia: `notificar-pagos/index.ts`, líneas 154–211 y 260–319; `ciclo-contratos/index.ts`, líneas 187–287 y 398–424. El análisis principal confirmó 9 trabajos cron activos en el servidor; no todos llaman a Edge Functions.

## Integraciones y dependencias

| Conexión | Para qué se usa | Qué quedó verificado |
|---|---|---|
| Supabase Auth | Acceso y creación/gestión de identidades de Portal y CRM. | Llamadas desplegadas en altas, usuarios, borrado y contraseñas. |
| Resend, `api.resend.com` | Correos de bienvenida, comunicados, pagos y próximos vencimientos. | Host literal y llamadas en código desplegado; no se probó entrega. |
| Push web | Alertas de navegador/dispositivo. | Usa suscripciones activas guardadas y desactiva las expiradas ante 404/410; los hosts finales dependen de cada suscripción y no se leyeron datos personales. |
| BCRP, `estadisticas.bcrp.gob.pe` | Referencia USD→PEN para capital/ranking. | `crm-tipo-cambio` consulta compra `PD04639PD` y venta `PD04640PD`, hasta la fecha de corte; promedia hasta 7 últimas fechas publicadas y cachea por corte durante 1 hora. Sin acceso a BD. |
| Calendarios compatibles con ICS | Consultar tareas del CRM desde Google Calendar, Apple Calendar u Outlook. | `crm-agenda-ics` genera un espejo de lectura por token privado a través de `crm.agenda_ics_feed_fn`; no hay escritura de vuelta al CRM en esta Edge. |
| Google Sheets / Apps Script | Captura/importación de prospectos. | Ruta documentada en vault y receptor `crm-importar-leads` vivo; script externo no auditado en esta lectura. |
| Storage de Supabase | Archivos contractuales. | PDF usa `contratos-generados`; eliminación puede incluir `documentos`; ambos privados según catálogo SQL. |

`esm.sh`, JSR y módulos empaquetados son proveedores de dependencias del código, no sistemas comerciales que reciban automáticamente los datos de clientes. Los dominios `miavance.com` y `crm.miavance.com` aparecen como portales/orígenes permitidos y enlaces, no como bases de datos adicionales.

## Lugares recomendados para resaltar en el diagrama

1. **Identidad vigente / preparada:** cuatro puertas Edge mantienen alternativas alrededor de la misma bandera. Evitar presentar la identidad unificada como ya activa.
2. **Portal / CRM:** `crear-cliente` une autoridades de ambos; `crm-convertir-lead` exige capacidad CRM. Varias herramientas históricas (`crear-admin`, `resetear-password`, comunicados/push) siguen validando roles Portal directamente. Es una diferencia de responsabilidades observable; no se concluye aquí que sean permisos incorrectos.
3. **Correo/push repetidos en distintos encargados:** comunicados delega push a `enviar-push`, pero pagos y vencimientos implementan envíos propios. Es un lugar concreto para revisar mantenimiento duplicado.
4. **Cliente / contrato / PDF:** son resultados distintos y deben tener cajas distintas. Crear un cliente no equivale a registrar una inversión; PDF pendiente no equivale a contrato inexistente.
5. **Aviso tomado / aviso entregado:** los sellos contra duplicados no son comprobantes de entrega al destinatario.
6. **Desplegado / utilizado:** `ACTIVE` no prueba tráfico ni uso exitoso. `diagnostico-push` demuestra por qué es necesaria la distinción.

## Límites de esta evidencia

Se leyó código desplegado de todas las funciones y configuración de inventario, no ejecuciones ni contenido de clientes. No se invocaron altas, eliminaciones, correos, cron ni simulaciones `dry_run`. No se confirmó el tráfico de cada puerta ni la entrega final de los proveedores. Las reglas internas de los RPC son responsabilidad del análisis SQL complementario. El catálogo permite dibujar conexiones; los comentarios históricos de código y las notas se contrastaron con las instrucciones ejecutables cuando diferían.
