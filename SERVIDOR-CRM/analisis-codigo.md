# Mapa del código para SERVIDOR CRM

Fecha de revisión local: 2026-09-06 (Lima). Análisis de solo lectura; no se modificaron aplicación ni servidor. Los nombres y líneas se comprobaron en el código local. El estado **productivo actual** debe contrastarse con el catálogo vivo de Supabase; una migración local o una nota histórica no prueban por sí solas que una rama esté activa hoy.

**Contraste vivo recibido del análisis principal:** las tres banderas `resolver_en_puertas`, `inversiones_escritura` y `ficha_360_neutral` están **apagadas**. Por tanto, las ramas de identidad/saga descritas abajo son capacidad local preparada y no el recorrido encendido. La política de rentabilidad está en **observación, versión 1**. `private.sla_operacion_leads` no aparece en el inventario vivo. Evidencia del catálogo: `SERVIDOR-CRM/inventario-produccion.json` (captura 2026-09-07 00:39 UTC, 06/09 en Lima).

**Ampliación verificada directamente contra Supabase:** [verificacion-distribucion-nucleos.md](./verificacion-distribucion-nucleos.md). Las puertas v1/v2 de Distribución están cerradas, pero sus motores internos siguen siendo utilizados por v3. Las pantallas Conversiones y Reuniones combinan las tres calculadoras. `capital_autorizada` existe, pero no es una ventana universal en el código vivo: algunos consumidores resuelven su ámbito y llaman al núcleo directamente.

## Lectura comercial del sistema

El CRM tiene tres formas de pedir trabajo a Supabase. La pantalla puede consultar una tabla protegida, pedir una operación comercial ya preparada (RPC), o llamar a un servicio auxiliar (Edge Function) para tareas como crear acceso de cliente, importar prospectos o fabricar un PDF. Las tres terminan en la misma base; no son tres servidores independientes.

La base separa `crm` (trabajo comercial), `public` (clientes/contratos compartidos con el Portal) y `private` (reglas internas y calculadoras). `private` no es otra base: es un área interna a la que la pantalla no entra directamente. Auth confirma quién está conectado; membresías/capacidades y permisos por fila deciden qué puede ver y hacer.

## Entradas verificadas en el frontend

Todas las líneas de esta tabla pertenecen a `CRM-Avance-Corp/app/src/data/crm-api.ts`.

| Necesidad del negocio | Función de pantalla → entrada del servidor | Línea |
|---|---|---:|
| Ver prospectos | `listarLeads` → lectura `crm.leads` | 465, 473 |
| Cartera paginada | `listarCarteraPagina` → `crm.cartera_pagina_fn` | 637, 663 |
| Ver equipo permitido | `listarEquipo` → `crm.equipo_visible_fn` | 747 |
| Repartir a supervisión | `repartirLead` → `crm.repartir_lead` | 1170 |
| Derivar al equipo | `derivarLeadsEquipo` → `crm.derivar_leads_equipo_fn` | 4384, 4400 |
| Descartar y recuperar | `crm.descartar_lead`, `deshacer_descarte`, `rescatar_descartes` | 1184, 1197, 1305 |
| Registrar prospecto | `insertarLead` → `crm.crear_lead_si_disponible` | 1783 |
| Editar prospecto | `actualizarLead` → UPDATE directo de `crm.leads`; `editarLeadFn` → `crm.editar_lead_fn` | 1819, 1851 |
| Registrar contacto | `insertarActividad` → INSERT directo de `crm.actividades` | 1858 |
| Agenda | `listarTareasDelAmbito`, `insertarTarea`, `actualizarTarea` → `crm.tareas` | 1928, 1968, 1973 |
| Cerrar/reprogramar cita | `cerrarReunion`, `reprogramarReunion` → RPC comercial | 2085, 2137 |
| Convertir en cliente Avance | `convertirLead` → Edge `crm-convertir-lead` | 2211 |
| Nuevo contrato | `crearContrato` → `crm.crear_contrato_con_cuenta_pdf_v2` | 2432, 2465 |
| Corregir contrato | `actualizarContrato` → `crm.actualizar_contrato_con_cuenta_pdf_v3` | 3375, 3398 |
| Nuevo cliente sin partir de lead | `crearClientePortal` → Edge `crear-cliente` | 2885, 2899 |
| Ficha comercial y detalle | `crm.cliente_ficha_fn`, `crm.cliente_detalle_fn` | 2684, 2791 |
| Cronograma / titulares | `crm.cronograma_contrato_fn`, `crm.titulares_contrato_fn` | 3292, 3328 |
| Cierre en cooperativa | `convertirLeadExterno` → `crm.convertir_lead_externo` | 4582, 4613 |
| Corregir/anular cierres | `crm.corregir_cierre_externo`, `anular_cierre_externo`, `anular_cierre_avance` | 4700, 4763, 4834 |
| Capital, pagos, vencimientos | `crm.metricas_capital_mes_fn`, `metricas_pagos_mes_fn`, `metricas_vencimientos_fn` | 3559, 3829, 3858 |
| Gerencia comercial | `crm.metricas_distribucion_leads_v3_fn`, `metricas_conversiones_fn`, `metricas_reuniones_fn` | 3950, 4026, 4164 |
| Resultado oficial mensual | `crm.conversion_mensual_fn` | 4087 |
| Trabajo pendiente / resumen de cartera | `crm.cola_accion_fn`, `crm.resumen_cartera_fn` | 4217, 4194 |

Autorización al iniciar: `CRM-Avance-Corp/app/src/lib/auth.tsx:60` llama `crm.mi_acceso_fn`. La migración `20260903215149_crm_capacidad_conversion_unica.sql:195` publica `puede_contratar` desde `private.puede_gestionar_contratos_crm()`. La Edge de conversión consulta la misma RPC con la sesión del actor (`_supabase_functions/functions/crm-convertir-lead/index.ts:94`).

## Recorrido comercial recomendado para el diagrama

1. **Llegan interesados**: landing/formulario/hoja/importación, o registro manual.
2. **Identificar y evitar duplicación**: reconocer persona, disponibilidad, vetos de contacto, y decidir si es nuevo prospecto o reingreso de alguien conocido.
3. **Distribuir trabajo**: cola por repartir → supervisor → analista. La historia de asignaciones conserva quién recibió y quién cerró; mover un prospecto no crea otra llegada.
4. **Gestionar relación**: prospecto (`crm.leads`) + contactos (`crm.actividades`) + compromisos/citas (`crm.tareas`). Citas son tareas de tipo `reunion`; no hay una tabla separada llamada citas.
5. **Resultado comercial**: continuar seguimiento / descartar y eventualmente rescatar / convertir. La conversión se bifurca por destino: Avance crea/enlaza perfil y acceso al Portal; cooperativa registra un cierre externo.
6. **Administrar inversión**: contratos Avance (`public.contratos`), cuotas/cronogramas y cuentas; renovaciones/upgrades dejan su operación en `crm.operaciones_cartera`. El cierre de cooperativa vive en `crm.cierres_externos`.
7. **Medir**: las fuentes alimentan calculadoras internas de conversión, capital y citas; los RPC de Gerencia adaptan sus resultados a cada pantalla.
8. **Conservar historia**: auditoría, asignaciones, atribución y fotografías de meses cerrados explican qué pasó y evitan reescribir el pasado comercial.

## Calculadoras compartidas: qué significa cada una

### Conversión / llegada única

`private.conversion_episodios`, definición local revisada en `CRM-Avance-Corp/supabase/migrations/20260904210831_crm_conversion_llegadas_unicas.sql:37`.

- Una llegada por `crm.leads.id`, con fecha de alta original en Lima. La primera atribución se busca en todo `crm.lead_asignaciones` antes de filtrar el equipo visible (líneas 53–76).
- La llegada queda en quien primero la recibió; el cierre, en quien lo consiguió. Son hechos distintos, aunque pertenezcan al mismo prospecto.
- Base del índice: altas automáticas de Landing/Formulario. Referidos y altas manuales tienen conteo, pero no aportan al divisor (líneas 62–63).
- Cierres salen del historial de asignaciones, con peso de referido según período (líneas 80–102).
- Renovación y upgrade elegibles salen de `crm.operaciones_cartera`; se toma la primera elegible por cliente/mes antes del recorte temporal. Renovación pesa como referido; upgrade aporta 1 (líneas 106–128).
- Consumidores locales de esa misma migración: `private.conversion_mensual_por_vendedor` (136), `private.metricas_conversiones_implementacion` (234), `crm.metricas_conversiones_equipo_fn` (776), `private.metricas_distribucion_leads_v3_core` (1065), `crm.conversion_mensual_sin_cartera_fn` (1325), `crm.cerrar_periodo` (1873).

### Capital

`private.capital_episodios`, base en `20260829190500_crm_f4_0_nucleo_capital.sql:51` y atribución por cadena en `20260830233000_crm_atr_2_capital_por_cadena_de_upgrade.sql:131`.

Pregunta comercial: **qué dinero entró y a quién corresponde esa producción**. Une contratos Avance, desglose de renovación/adicional y cierres externos; usa `private.analista_atribuido_cadena` para la atribución cuando corresponde (líneas 147, 178). La ventana autorizada es `private.capital_autorizada`.

Hay dos vistas legítimas: capital que entró en el período y capital vigente hoy. El pipeline estimado es otra pregunta y no debe sumarse al capital firmado. Las monedas se conservan separadas en el núcleo; cualquier total convertido debe identificar su tipo de cambio y propósito.

### Citas

`private.citas_episodios` en `20260830120000_crm_f6_a_nucleo_de_citas_y_censo.sql:67` lee `crm.tareas` de tipo `reunion`, activas y por vencimiento (líneas 111–116). Produce banderas: realizada, no-show, cancelada por asesor, cancelada por sistema, reprogramada, pendiente de cierre y programada a futuro. Sirve para distinguir **cuántas citas ocurrieron** de **cuántos prospectos llegaron a tener una cita**.

### SLA y pendientes

El vault vigente identifica `private.metricas_sla_global_core` (primera gestión/cohortes) y `crm.estado_sla_leads_fn` (snapshots). La ampliación `private.sla_operacion_leads` + `private.sla_operacion_autorizada` está **solo diseñada**, no implementada/productiva según la nota `Nucleo operativo SLA - arquitectura y consumidores 2026-09-06.md`. Representarla punteada como propuesta, nunca como servidor activo.

## Bifurcaciones que conviene marcar y explicar

| Punto | Significado comercial | Clasificación |
|---|---|---|
| Avance / cooperativa | El destino de la inversión cambia qué documentos/acceso/registro se crean. Convergen en métricas de capital y conversión con reglas explícitas. | Bifurcación de negocio deliberada |
| Primera llegada / cierre / renovación | Captación, logro del asesor y nueva operación de cliente existente son hechos distintos. Una reasignación no aumenta captación. | Bifurcación de significado deliberada |
| Conversión del lote / índice mensual | «De los que llegaron, cuántos cerraron» y el índice que admite arrastre/renovaciones no responden lo mismo. | Etiquetar para evitar comparación falsa |
| Mes vivo / mes sellado | Hoy se calcula fresco; un período cerrado usa fotografía y ajustes posteriores. | Historia comercial deliberada |
| Portal / CRM | Dos aplicaciones comparten perfiles/contratos; el CRM tiene además su membresía y radio de equipo. No basta con un único rótulo «admin». | Frontera de autoridad que debe estar visible |
| RPC / tabla directa / Edge | Varias puertas técnicas para operaciones diferentes. Una tabla directa sigue teniendo RLS y triggers. | No implica error por sí mismo |
| `resolver_en_puertas` encendida / apagada | Código de compatibilidad antiguo y flujo de identidad/saga. El valor vivo decide qué rama se usa. | APAGADA según lectura viva; identidad/saga inactiva |
| Demo / sesión real | Datos de ejemplo calculan localmente; sesión real consulta RPC y muestra error si falla, sin sustituirlo por números demo. | Fuera del servidor productivo |
| Inventario pendiente / métrica analítica | Contar tareas o leads para trabajar no equivale a medir conversión. | Mantener preguntas separadas |

## Edges y diferencias respecto a notas históricas

- **Importación actual local**: `CRM-Avance-Corp/supabase/functions/crm-importar-leads/index.ts:448` resuelve destinos con `destinos_importacion_por_correo_fn`; línea 487 llama **`importar_lead_fn`**, por fila. El censo del vault del 03/09 todavía menciona `crear_lead_si_disponible`; no copiar ese detalle histórico al diagrama sin contrastarlo con la Edge desplegada.
- **Conversión actual local**: `_supabase_functions/functions/crm-convertir-lead/index.ts:132` consulta `resolver_en_puertas`. La rama de identidad en línea 367 reserva por persona, reanuda con `saga_conversion_fn` (413), registra efectos (422), crea Auth si corresponde (427) y cierra transaccionalmente la conversión (492). Hay rama legacy en el mismo archivo: coexistir en código no prueba uso de ambas.
- **Alta sin lead**: `_supabase_functions/functions/crear-cliente/index.ts:180` consulta la misma bandera; `alta_cliente_identidad_fn` en línea 247 ordena los pasos de identidad/Auth/enlace.
- **PDF**: `CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/handler.ts:844` consulta estado, renderiza y guarda archivo, luego registra resultado; acceso firmado de 300 segundos en línea 827. Es auxiliar del contrato: fallo del PDF no debería dibujarse como inexistencia del contrato.
- **Colaboradores**: `CRM-Avance-Corp/supabase/functions/crm-usuarios/handler.ts:241` busca candidato y línea 287 registra vendedor por RPC.

## Identidad multiempresa: capa relacional, no segunda caja de dinero

En `20260903160000_crm_f1_identidad_empresas_inversiones.sql` están `crm.empresas` (77), `crm.inversionistas` (127), `crm.inversionista_identificadores` (174), `crm.inversionista_leads` (217), `crm.inversionista_responsables` (237), `crm.inversiones` (279), `crm.inversion_titulares` (314) y banderas (349).

La definición de `crm.inversiones` (302) dice expresamente: registro de relación persona–empresa–fuente económica; una fuente es contrato Avance **o** cierre externo. No copia montos ni moneda: los lee de su fuente a través del núcleo de capital. Dibujarla como «índice de inversiones de la persona», no como calculadora paralela.

Las tablas existen, pero el análisis principal confirmó que las tres banderas de activación están apagadas. El bloque debe quedar visualmente separado como **estructura preparada / activación pendiente**, sin flechas sólidas que impliquen uso de la nueva escritura.

## Límites de la evidencia local

Se usó CodeGraph antes de localizar código, pero devolvió varios símbolos/ubicaciones de un índice antiguo y no resolvió bien SQL; se complementó con búsquedas puntuales y lectura de las secciones relevantes. Las líneas anteriores son las observadas en disco, no los encabezados antiguos del índice.

Las notas históricas de autoridad del 29/08 describen defectos que notas posteriores declaran reparados. No presentar esos incidentes como fallos actuales. Tampoco se puede inferir que todas las migraciones del repositorio están aplicadas; Supabase vivo decide vigencia, exposición, dependencias reales y banderas.

No se midieron frecuencias de uso por ruta: una dependencia en código prueba que puede llamarse, no cuánto tráfico recibe. No se hizo auditoría de seguridad integral ni se consultaron datos personales de clientes.
