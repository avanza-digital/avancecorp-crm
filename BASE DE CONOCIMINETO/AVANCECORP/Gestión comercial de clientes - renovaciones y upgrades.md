---
tags: [crm, cartera, postventa, renovacion, upgrade, conversion]
actualizado: 2026-08-25
estado: gestion-implementada-ficha-360-pendiente-preview-y-aceptacion
---

# Gestión comercial de clientes — renovaciones y aumentos de inversión

Decisión cerrada con Miguel el **2026-08-24**: **Mi cartera** deja de ser una
lista de consulta y pasa a ser el lugar desde el que el vendedor continúa la
relación comercial con sus clientes.

## Acciones disponibles

Desde cada cliente se puede:

- agendar llamada, WhatsApp, reunión u otra tarea;
- registrar un aumento de inversión;
- registrar una nueva inversión;
- abrir detalle, corregir dentro de las autorizaciones existentes y consultar
  el historial comercial;
- renovar desde el contrato que llegó a su fecha fin.

Las gestiones de cliente viven en la misma agenda operativa que las de leads y
aparecen en **Hoy** y **Agenda**. Su resultado se guarda en un historial de
postventa propio. No modifica la etapa, el tiempo máximo de respuesta ni el
historial de captación de Leads.

Las reuniones conservan además su clasificación estructurada (resultado
comercial o motivo de cancelación), sin reducirla a una etiqueta genérica.

## Ficha comercial 360

F4.1 reúne esta continuidad comercial en una ficha lateral comparable con la de
Leads. Su implementación y sus pruebas técnicas están terminadas; solo faltan la
preview aislada y la aceptación comercial antes de considerar una publicación.

La ficha responde a una regla sencilla por rol:

- el vendedor ve y gestiona únicamente a los clientes que tiene asignados;
- el supervisor usa la misma ficha para los clientes de su equipo;
- Gerencia consulta la cartera completa con sus permisos actuales;
- Directorio consulta toda la cartera, pero no ve cuentas bancarias ni tiene
  acciones para modificar datos o registrar operaciones.

El registro de quién creó originalmente al cliente no concede acceso. El historial
acompaña al cliente y se muestra al vendedor que lo tiene asignado hoy, aunque una
gestión anterior haya sido realizada por otra persona. Si el asesor anterior está
inactivo, el supervisor conserva la consulta, pero las acciones quedan bloqueadas
hasta reasignar al cliente.

La información personal de la ficha se limita a identidad y contacto necesarios;
no incluye domicilio ni datos bancarios. Las cuentas donde se depositan intereses y
se devuelve capital se consultan por separado y solo para los roles habilitados.

Mientras la ficha permanece visible, permisos y datos se vuelven a comprobar cada
60 segundos. Al cerrarla, terminar una corrección o perder acceso, la aplicación
retira los datos temporales de esa consulta.

El capital vigente en soles y el capital vigente en dólares siempre se muestra por
separado. Las acciones se nombran de forma uniforme para el equipo: **nueva
inversión**, **renovación** y **aumento de inversión**.

### Beneficio comercial

- El vendedor comprende la relación completa antes de llamar o escribir.
- El siguiente seguimiento se agenda con menos pasos y mejor contexto.
- Las renovaciones por vencer y los aumentos de inversión son más visibles.
- El supervisor acompaña a su equipo desde la misma información que usa el
  vendedor.
- Gerencia y Directorio obtienen una lectura consistente sin ampliar el acceso a
  datos sensibles.

## Renovación

Una renovación:

1. solo se habilita cuando el contrato llega a su fecha fin;
2. crea **otro contrato**;
3. enlaza y cierra el anterior dentro de la misma transacción;
4. traslada sus cuotas pendientes;
5. registra el puente económico:
   **capital anterior → capital renovado + capital adicional = contrato nuevo**.

El **capital adicional** es dinero nuevo y se conserva separado porque se paga
de otra manera. No crea una conversión adicional. El desglose se muestra en la
misma cartera para vendedor, supervisor y Gerencia, siempre separado por PEN/USD.

## Conversión

- Renovación: suma **1 conversión** y **0 al divisor**.
- Aumento de inversión: suma 1 conversión solo si ocurre en un mes posterior al
  mes del primer contrato del cliente.
- Un cliente suma como máximo **una conversión por mes**, aunque renueve dos
  inversiones o combine renovación + aumento de inversión.
- La conversión se acredita al vendedor responsable de la cartera en el instante
  de la operación.
- El divisor conserva como única fuente los leads no referidos recibidos; ni el
  capital renovado ni el adicional lo alteran.

## Histórico de agosto de 2026

Se reconstruyeron 48 operaciones: 9 renovaciones y 39 aumentos de inversión,
correspondientes a 29 clientes elegibles. Los nueve desgloses históricos de
renovación no podían deducirse con certeza: se muestran como **desglose
pendiente** y no se inventa capital adicional.

## Implementación y prueba

- Renovaciones y aumentos de inversión: cambios de base de datos
  `20260824231133` y `20260824233619`.
- Seguimiento de reuniones `20260825005519`: prueba completa en un entorno seguro;
  los datos de prueba se deshacen al terminar y su publicación sigue pendiente de
  autorización.
- `crm.operaciones_cartera` conserva un registro inalterable de cada operación.
- `crm.actividades_cliente` conserva el historial de seguimiento después de la
  venta.
- `GESTION_CLIENTES_RENOVACIONES_OK` confirma automáticamente que una operación se
  guarda completa o no se guarda.
- La tarea de cliente conserva su vínculo con el cliente y viaja al nuevo vendedor
  cuando la cartera se reasigna.
- Al cerrar una reunión se conserva el resultado comercial o el motivo por el que
  no se realizó. Si no puede guardarse la siguiente acción, tampoco se deja un
  cierre incompleto.
- F4.1 usa el cambio aislado
  `20260825214823_crm_ficha_comercial_cliente_scope.sql` y la comprobación
  `FICHA_CLIENTE_SCOPE_TX_OK` para verificar que cada rol vea únicamente la cartera
  que le corresponde.

## Relacionado

- [[Ficha comercial 360 de clientes - plan]]
- [[Mi cartera por meses]]
- [[Categorización de inversiones - Nuevo Renovación Upgrade]]
- [[Conversion mensual - definicion cerrada]]
- [[Periodo comercial de contratos]]
- [[Agenda comercial del CRM (plan v2)]]
- [[Ciclo de vida de contratos]]
