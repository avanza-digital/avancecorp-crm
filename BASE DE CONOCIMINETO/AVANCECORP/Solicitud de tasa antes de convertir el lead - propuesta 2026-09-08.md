---
tags: [crm, leads, rentabilidad, propuesta]
fecha: 2026-09-08
estado: publicado-propuesta-historica
---

# Solicitud de tasa antes de convertir el lead

**Estado posterior — 09/09:** implementación, SQL y publicación autorizados y completados. Estado vigente en [[Solicitud de tasa en el lead - publicada 2026-09-09]]. La rama de pruebas fue eliminada. Lo que sigue conserva la propuesta y aceptación originales; las referencias a trabajos pendientes pertenecen a ese momento histórico.

Relacionado: [[Inicio]], [[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]], [[Correccion solicitud de tasa - motivo y bloqueo de contrato 2026-09-08]], [[Historial de decisiones de tasa de Gerencia]], [[Capacidad única de conversión de leads (2026-09-03)]].

## Necesidad expresada por Miguel

El analista debe solicitar la aprobación de tasa antes de convertir el lead a cliente. Miguel propone mostrar el mismo recuadro de solicitud en la ficha del lead y pide una recomendación sobre el flujo. Esta conversación plantea el cambio; no autoriza todavía una implementación ni una migración concreta.

## Evidencia local

- `app/src/components/app/lead-drawer.tsx`, `confirmarReal`: llama a `convertirLead` con identidad y cuentas bancarias; confirma el cierre del lead y después abre `ContratoNuevo`. El formulario del contrato puede omitirse.
- `app/src/components/app/tasa-politica.tsx`: el recuadro exige `clienteId`; la consulta y la solicitud dependen del cliente existente.
- `app/src/data/crm-api.ts`, `IntencionContrato` y `solicitarTasa`: la solicitud lleva `cliente_id`, sin referencia previa a un lead.
- `mismaIntencion` compara capital, moneda, fechas exactas de inicio/vencimiento, modalidad, tipo de interés y condición de producto. Una autorización no equivale a una tasa libre para cualquier operación.

La navegación comenzó con CodeGraph y se complementó con lectura puntual de los símbolos nuevos que el índice no localizó. No se comprobó el despliegue vivo en esta conversación.

## Propuesta de flujo

1. Mostrar una sección compacta «Condiciones de inversión» en la ficha del lead, conservando el recuadro horizontal existente para solicitar la excepción durante la negociación.
2. Obtener la tasa base de la política central. La tasa base sin petición pendiente permite el flujo normal; una excepción enviada y pendiente impide convertir en Avance incluso a la base. El seguimiento comercial del lead continúa disponible.
3. Solicitar sobre condiciones concretas: capital, moneda, fechas/plazo, modalidad y tipo de interés, tasa solicitada y motivo. Conservar categoría, producto y contrato origen cuando correspondan.
4. Reutilizar la bandeja de Gerencia y la respuesta al analista, indicando si la solicitud pertenece a un lead o a un cliente. La aprobación por sí sola no convierte al lead.
5. Al convertir, validar nuevamente en el servidor el estado, la vigencia, las condiciones y la autoridad antes del alta y sus efectos. Asociar la misma solicitud al cliente resuelto y al contrato, conservando su historial. Consumirla una sola vez cuando se cree correctamente el contrato.
6. Si cambian las condiciones contractuales, la aprobación anterior no autoriza la nueva propuesta. Conservar el historial y tramitar una nueva aprobación. Un rechazo o declinación permite elegir la base; una contraoferta requiere aceptación para usar una tasa superior.

No basta trasladar el componente: el servidor debe admitir una propuesta previa al cliente y enlazarla de forma segura al resolver su identidad, incluido el caso de un cliente ya existente. El diseño concreto de datos y la migración quedan pendientes.

Las solicitudes desde la ficha de clientes siguen siendo necesarias para nuevas operaciones, renovaciones, upgrades y correcciones. Deben compartir el mismo núcleo. La propuesta no redefine las tasas ni los cierres de cooperativas externas, las reglas de conversión o la arquitectura multiempresa.

## Restricciones a resolver en el diseño técnico

- Fechas: mostrar la fecha de inicio prevista y precargar los mismos datos al contratar. La política vigente compara fechas exactas; sustituirlas por una ventana flexible o permitir tolerancias sería una nueva decisión de negocio de Miguel. No se asume autorizada. Que la fecha sea desconocida en todos los leads o que la mayoría de aprobaciones deba repetirse es una hipótesis, no evidencia observada.
- Identidad: antes de enviar y al convertir, comprobar la identidad disponible y las solicitudes del mismo cliente/operación. Resolver expresamente la colisión con una petición ya existente y evitar dos autorizaciones utilizables para la misma propuesta. No crear el cliente ni enviar su bienvenida solo para comprobarlo.
- Permisos: conservar la autoridad real de solicitudes y sus ámbitos, además de la capacidad de conversión. No permitir autoaprobación. No imponer un límite global de una solicitud por analista que le impida negociar con distintos prospectos.
- Descarte o cambio de destino: definir el tratamiento auditable de la solicitud y conservar su caducidad. No añadir cancelación de solicitudes enviadas ni retirar el bloqueo vigente de forma implícita.

Una revisión independiente mediante `scripts/claude-review` devolvió **CHANGES_REQUESTED**, confianza media, sobre el diseño. Se incorporaron las restricciones de identidad, fechas y ciclo de vida; no se aceptaron como hechos sus hipótesis sobre frecuencia de cambios de fecha, permisos del servidor o bloqueo indefinido. Tampoco se cambió la huella vigente ni se limitó automáticamente toda solicitud del lead a categoría `nuevo`. No hubo implementación evaluada ni una segunda revisión. El primer intento del wrapper no completó la ejecución restringida; el reintento permitido entregó el único dictamen.

## Verificación y alcance

Investigación y propuesta comercial basadas en código y memoria local. Sin cambios en código de producto, base de datos o publicación. PASS: enlaces del vault y rutas del código referenciado comprobados; sin errores de espacios en la nota. NOT RUN: pruebas de runtime y build, porque el cambio es documental; deberán ejecutarse con la implementación. La revisión de diseño no certifica seguridad ni comportamiento del servidor.

## Vista local solicitada después

Miguel pidió «muéstrame local cómo se vería tal cual». Se preparó una copia independiente del frontend en `/private/tmp/avancecorp-lead-tasa-preview-20260908`, disponible mientras corre Vite en `http://127.0.0.1:5198/`. La ficha de ejemplo se abre automáticamente y conserva los componentes, estilos, tamaño y fondo del CRM. El recuadro horizontal se ubica después de las etapas, dentro de «Condiciones de inversión». Las etapas se ajustan a dos líneas en móvil para evitar desborde.

El selector «Vista local» simula tasa base, borrador, pendiente, aprobación, contraoferta, aceptación, rechazo y cambio de condiciones. El envío bloquea la conversión y el estado se conserva al cerrar/reabrir durante la misma visita. El paso de conversión muestra un resumen con la tasa elegida. Recargar restablece el ejemplo. Son datos y decisiones simuladas: no se conectó el backend, enviaron solicitudes, crearon cuentas ni publicaron cambios.

Archivos de la vista: `src/prototypes/lead-tasa/` en la copia; integración en sus copias de `lead-drawer.tsx` y `main.tsx`. `README.md` contiene el comando para volver a iniciar el servidor. El código de producto del working tree original no recibió esta implementación visual.

PASS: lint de archivos modificados sin avisos, TypeScript, compilación Vite y diez comprobaciones interactivas de estados, aceptación, traslado de tasa, relectura al reabrir, validación y Enter. En móvil (390 px), envío/aceptación y geometría horizontal sin desborde; escritorio a 1440 px. Capturas de escritorio, móvil y aprobación inspeccionadas en `.playwright-mcp/lead-tasa-preview-*.png`. Consola tras recarga final sin errores. La compilación conserva avisos por tamaño de chunks/importación mixta de la aplicación copiada. El navegador integrado no estuvo disponible; la revisión visual se realizó con el navegador de pruebas.

NOT RUN: suite integral del producto, integración de servidor y pruebas con datos reales; el alcance es una muestra local interactiva. Nivel 1 de presentación, sin otra revisión secundaria. La implementación financiera y su SQL siguen pendientes.

## Preferencia visual confirmada

Después de ver la muestra local, Miguel respondió «me gusta mucho». Se conserva esta vista como el diseño elegido: recuadro horizontal dentro de «Condiciones de inversión» en la ficha del lead, con estados y bloqueo de conversión visibles. No volver a pedirle que elija una propuesta visual para este mismo alcance.

Esta aceptación corresponde a la presentación local. El diseño concreto del servidor, la resolución de las restricciones anteriores, la implementación real y la publicación siguen pendientes; no se interpreta el comentario como aprobación de una migración SQL aún no preparada.
