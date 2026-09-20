---
tags: [crm, leads, cartera, inversiones, conversion, plan]
fecha: 2026-09-18
estado: propuesto-pendiente-de-ejecucion
---

# Plan de unificación de conversión de leads y nueva inversión

## Objetivo solicitado por Miguel

El botón **Convertir a cliente** debe utilizar el mismo registro de inversiones que **Nueva inversión** en Cartera: formulario, validaciones, revisión y guardado compartidos. Cartera es la referencia de comportamiento. Desde Leads se precargan los datos disponibles y se completa la primera conversión al confirmar la inversión.

Miguel pidió primero identificar el problema y después elaborar este plan. Esta nota no autoriza implementación, SQL productivo ni publicación.

## Diagnóstico confirmado en el código local

- Cartera monta `InversionNueva`, que prepara una solicitud, permite revisarla y la confirma mediante `confirmar_inversion_revisada_fn`.
- Leads monta `DialogConvertir`. Avance crea o enlaza el acceso y convierte al lead antes del contrato; después permite omitir ese contrato. Cooperativas usan directamente `convertir_lead_externo`.
- En cooperativas, Leads fija el inicio en hoy, permite omitir la referencia y no solicita un comprobante adjunto. Cartera permite elegir fecha comercial, exige referencia y comprobante y ofrece revisión antes de confirmar.
- `private.inversion_persona_contexto` rechaza un lead canónico que todavía no está convertido. También se utiliza en lectores y operaciones de cartera; quitar ese control globalmente no resuelve la integración.
- La preparación actual requiere `inversionista_id` y no admite un contexto de lead inicial. La ficha de Cartera y su capacidad de nueva inversión también dependen del contexto actual.

El resultado propuesto cambia expresamente el momento del cierre Avance: **preparar la persona o su acceso no convierte comercialmente al lead; la confirmación de la inversión completa esa conversión**. Se alinea así con el pedido de usar el proceso de Cartera.

## 1. Definir el contrato compartido

Tomar el flujo de Cartera como fuente de verdad y documentar sus campos, reglas y estados para Avance, Qorilazo y Prodelco. Comparar campo por campo con Leads para trasladar identidad, domicilio, aprobaciones de tasa y datos necesarios para el pago.

Definir dos contextos de entrada al mismo proceso: primera inversión desde un lead y operación sobre un inversionista existente. El servidor debe conservar el contexto y el vínculo con el lead durante toda la solicitud, incluidos los reintentos. Las condiciones financieras se validan con las mismas reglas por empresa.

Precisar la atribución: conservar al analista del lead para su conversión y verificar la compatibilidad con el responsable de la persona. Un conflicto de identidad, cartera o responsable sigue la resolución autorizada existente; la unificación no debe reasignar silenciosamente al cliente ni la venta.

Antes de implementar, contrastar en solo lectura el catálogo, capacidades y configuración productivos con las fuentes locales. El diagnóstico previo no verificó la base productiva.

**Salida:** matriz de campos y capacidades por origen, empresa y rol; estados de solicitud; reglas de fechas, atribución y recuperación; lista concreta de funciones y consumidores afectados.

## 2. Preparar la primera inversión dentro del núcleo compartido

Extender la preparación de solicitudes para reconocer una entrada desde Leads. Resolver o crear la identidad mediante el mecanismo canónico y su documento verificado, reutilizando personas existentes y respetando los límites sobre leads canónicos, fusiones y reservas.

Persistir el origen, el lead y el modo de operación como parte inmutable de la solicitud y de su protección contra reintentos distintos. La clave de recuperación debe existir desde el lead, aunque todavía no haya una identidad creada. La lectura y recuperación de esa solicitud debe funcionar sin depender de una ficha que exija conversión previa.

Autorizar la entrada por el lead y comprobar también el vínculo y los permisos sobre la identidad. Mantener los controles de miembro activo, ámbito comercial, No contactar, cambio de responsable y revocación. El guard de las operaciones posteriores seguirá protegiendo a sus otros consumidores.

Los adaptadores de entrada, si son necesarios, deben desembocar en validadores y escritores compartidos. No mantener dos implementaciones de las condiciones económicas.

**Salida:** solicitud recuperable para un lead abierto, sin reconocer todavía venta, inversión confirmada ni conversión.

## 3. Confirmar inversión y conversión comercial juntas

La confirmación compartida debe distinguir primera conversión de inversión posterior. Para una primera inversión, guardar su fuente económica, enlazarla con la persona y completar el cierre del lead dentro de una misma transacción de base de datos. No ejecutar el cierre anterior y después registrar una segunda inversión.

Reutilizar los marcadores existentes `cierres_externos.es_cierre_inicial` e `inversiones.es_primera_conversion`. Mantener la atribución, auditoría, episodio comercial y lectores canónicos de capital y conversión; una confirmación inicial produce una inversión y una conversión, sin duplicación.

Validar de nuevo las condiciones y autorizaciones de tasa al confirmar. Separar fecha comercial, fecha efectiva de registro y tratamiento de períodos cerrados según las reglas existentes de Cartera. Una fecha elegida no debe sustituir indiscriminadamente el sello de conversión.

La creación de acceso Avance y la subida del comprobante quedan fuera de la transacción SQL: usar los mecanismos recuperables existentes. Si se interrumpe el flujo tras preparar un acceso, conservar una solicitud que pueda retomarse sin crear otra cuenta. Documentar y comprobar cómo se presenta ese acceso preparado en el Portal y en los lectores; su existencia no debe contar como venta o inversión.

Conservar el comportamiento de bienvenida Avance después de la confirmación, con control de duplicados. El controlador actual de acceso de Cartera no envía correos, por lo que esta integración requiere tratarlo explícitamente. Cooperativas conservan identidad neutral y comprobante propio. Un fallo posterior de correo o PDF no se presenta como una inversión que nunca se guardó.

**Salida:** cierre coherente y recuperable, aun ante doble clic, pérdida de respuesta o reintentos.

## 4. Conectar los dos botones al mismo formulario

Adaptar `InversionNueva` para recibir ambos contextos y convertir la entrada de Leads en un adaptador pequeño. Reutilizar sus pasos por empresa, los formularios contractuales y el resumen de revisión.

Desde Leads, precargar identidad, contacto, moneda y condiciones válidas; solicitar lo que falte y conservar las tasas aprobadas. En Avance, seleccionar o registrar la cuenta de pago como parte del mismo proceso contractual de Cartera y exigir su validez antes de confirmar. En cooperativas, compartir fecha comercial, plazo, rentabilidad, referencia y comprobante.

Cancelar o cerrar un borrador conserva el lead abierto. Al confirmar, mostrar la inversión guardada y actualizar Leads, Pipeline, Cartera, ficha, contratos y métricas afectadas mediante sus lectores existentes. Mantener los datos y el foco ante errores; impedir cierres accidentales durante el envío.

Retirar las escrituras duplicadas del diálogo anterior cuando la equivalencia esté probada. Contemplar solicitudes antiguas en curso y clientes ya convertidos sin contrato. La transición debe permitir continuarlos sin recrear identidades, convertir dos veces ni reescribir el historial automáticamente.

**Salida:** ambos botones utilizan el mismo proceso de registro; el contexto de Leads añade el cierre inicial correspondiente.

## 5. Verificar el flujo completo y sus efectos

Probar la paridad de campos, validaciones y resultado económico entre ambos orígenes, junto con la diferencia legítima entre primera conversión y operación posterior.

Casos obligatorios:

- Avance, Qorilazo y Prodelco con las monedas admitidas por cada empresa.
- Persona nueva, existente, fusionada, documento duplicado y responsable incompatible.
- Tasas aprobadas, pendientes, vencidas o modificadas; cuenta de pago y datos legales.
- Cancelación antes y después de preparar acceso, cierre y reapertura, fallo de adjunto, corte de red y respuesta perdida.
- Doble envío y confirmaciones concurrentes, incluido un navegador que todavía use el proceso anterior; comprobar el orden de bloqueos.
- Reasignación, revocación y permisos de analista, supervisor, Gerencia y Directorio.
- Fecha comercial anterior y período cerrado; una sola inversión y un solo cierre inicial en capital, conversión, metas y demás lectores pertinentes.
- Regresiones de nuevas inversiones de clientes existentes, renovaciones, aumentos y reinversiones.
- Recorrido en escritorio y móvil, mensajes de estado y retorno al registro correcto.

Aplicar `.ai/VERIFICATION.md`: validaciones estáticas, pruebas de dominio, build y recorridos E2E; para servidor, pruebas SQL/HTTP y matriz RLS en entorno aislado. La revisión secundaria del cambio concreto complementa esas comprobaciones.

**Salida:** evidencia PASS/FAIL/NOT RUN, prueba visual y revisión del cambio implementado. Las pruebas de la versión anterior no validan esta futura integración.

## 6. Preparar e instalar la transición

Crear migraciones nuevas y actualizar el registro de migraciones, sin editar las ya versionadas. Preparar compatibilidad de solicitudes existentes, despliegue por etapas y reversa que conserve datos. Instalar primero las capacidades de servidor compatibles y después la interfaz; comprobar qué sucede con sesiones y versiones anteriores.

Presentar el SQL exacto antes de la autorización productiva que exigen las reglas del proyecto. La publicación posterior requiere su autorización de release y un artefacto construido desde Main verificado contra `avancecorp/main`. Comprobar la versión publicada y cerrar los recursos temporales propios.

**Salida:** publicación trazable con recuperación preparada y comprobación posterior.

## Criterio de aceptación

Un usuario puede iniciar desde Convertir a cliente o Nueva inversión, registrar las mismas condiciones por empresa y recorrer la misma revisión y confirmación. Desde un lead abierto, cancelar no lo convierte; confirmar registra una inversión vinculada y cierra una sola conversión para el analista correspondiente. Reintentar recupera esa misma operación. Cartera y las métricas reflejan el resultado confirmado.

## Evidencia y revisión del plan

- **PASS, línea base del diagnóstico:** tres archivos y 92 pruebas locales de conversión, solicitudes y Cartera. APIs simuladas; acreditan el comportamiento previo, no este plan implementado.
- **NOT RUN:** nueva implementación, pruebas de integración con base real, recorrido autenticado productivo y publicación; no forman parte de la elaboración del plan.
- Claude emitió **CHANGES_REQUESTED**, confianza media, sobre el borrador del plan. Se incorporaron el contexto inmutable de la solicitud, la atribución, la recuperación de acceso y los casos de convivencia/concurrencia. No se atribuye un PASS al reviewer.
- La observación de que Cartera carece de domicilio no está acreditada: `AltaAvance` lo captura y valida (`inversion-nueva.tsx:268-278`). Se conserva el inventario de campos como comprobación necesaria.
- `es_primera_conversion` ya existe (`20260903160000_crm_f1_identidad_empresas_inversiones.sql:292`); se reutiliza, no se propone una columna duplicada.
- El cambio de momento de conversión queda explícito en este plan y corresponde al pedido de usar el registro de inversión como referencia. No se solicitó otra confirmación para volver a plantear el objetivo que Miguel ya indicó.

Fuentes principales: `app/src/components/app/lead-drawer.tsx`, `inversion-nueva.tsx`, `contrato-nuevo.tsx`; `app/src/data/inversion-solicitud-api.ts`; las funciones `preparar_inversion_fn`, `confirmar_inversion_revisada_fn`, `inversion_persona_contexto` y las puertas de conversión; `_supabase_functions/functions/crm-convertir-lead/` y `crm-inversion-portal/`.

Relacionadas: [[Cartera multiempresa - publicacion (2026-09-16)]], [[Cartera multiempresa - plan de gestion integral (2026-09-16)]], [[Capacidad única de conversión de leads (2026-09-03)]], [[Gestión comercial de clientes - renovaciones y upgrades]], [[Cuentas bancarias por contrato]].
