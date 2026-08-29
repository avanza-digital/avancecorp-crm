---
tags: [crm, cartera, postventa, ficha-360, ux, plan]
actualizado: 2026-08-29
estado: referencia-ux-candidata-integrada-no-desplegada
fase: F4.1
---

# Ficha comercial 360 de clientes — plan

> [!note] Estado posterior — 2026-08-29
> La rama R2 se conserva únicamente como referencia UX/comercial. La candidata
> integrada actual usa `crm.cliente_detalle_fn(uuid)` para el detalle seguro y
> permanece **sin desplegar**; `crm.cliente_ficha_fn` es el nombre propuesto por
> este plan para una frontera futura, no una RPC vigente. Véase
> [[Auditoría backend Gestión de cartera 2026-08-28]].
> En la candidata actual, `creado_por` solo completa el ámbito cuando
> `asesor_perfil_id` es nulo y el creador pertenece al árbol autorizado; jamás
> prevalece sobre una asignación vigente.

Decisión aprobada por Miguel el **2026-08-25** e implementada en una rama
aislada: desde **Mi cartera**, el vendedor puede abrir a un cliente en una ficha
con la misma claridad y facilidad de uso que la ficha de Leads, adaptada a la
relación después de la primera venta. Continúa [[Gestión comercial de clientes - renovaciones y upgrades]]
y parte del cierre documentado en [[Cierre Mi cartera operativa 2026-08-25]].

La implementación y sus pruebas técnicas están terminadas. Solo faltan publicar
la preview aislada y recibir la aceptación comercial; producción no cambia sin
una autorización posterior.

## Objetivo de producto

Dar al vendedor una sola vista para entender **quién es el cliente, qué tiene,
qué ocurrió y qué debe hacer después**, sin obligarlo a alternar entre el
detalle de solo lectura, el diálogo de gestión y las filas de contratos.

No se convierte al cliente nuevamente en lead. La experiencia se siente
familiar, pero cada ficha responde a un momento comercial distinto:

| Ficha de lead | Ficha de cliente |
|---|---|
| Etapa, capital en juego, descarte y conversión | Estado de cartera, capital vigente, renovación y aumento de inversión |
| Actividades de captación | Historial comercial postventa |
| Próxima acción vinculada al lead | Próxima acción vinculada al cliente |
| Datos necesarios para cerrar la venta | Identidad y contacto mínimo, inversiones y continuidad comercial |

## Vista acordada

La ficha se abre como panel lateral, igual que Leads, y contiene:

1. **Cabecera:** avatar, nombre, estado activo/inactivo, asesor responsable y
   capital vigente separado por PEN/USD.
2. **Contacto rápido:** llamar, WhatsApp y correo con los mismos patrones
   accesibles de la ficha de Leads.
3. **Próxima acción:** tareas pendientes, cierre/anulación y alta de llamada,
   WhatsApp, reunión u otra tarea.
4. **Contratos:** vigentes, por vencer, vencidos y renovados; acceso a detalle,
   cronograma y acciones permitidas de renovación, aumento de inversión o nueva
   inversión.
5. **Datos del cliente:** identidad y contacto estrictamente necesarios;
   corrección únicamente cuando el servidor la autoriza. La ficha no muestra
   domicilio ni incorpora información bancaria en este bloque.
6. **Historial comercial:** llamadas, WhatsApp, reuniones, notas, renovaciones,
   aumentos de inversión y reasignaciones en orden temporal.
7. **Acciones comerciales:** registrar seguimiento, renovar, aumentar la
   inversión y registrar una nueva inversión, siempre condicionadas por rol,
   responsabilidad actual y estado.

Las cuentas donde Avance Corp deposita intereses y devuelve capital se consultan
por separado y solo para los roles habilitados. No forman parte de la identidad
del cliente, no se amplía su exposición y Directorio no puede verlas.

## Alcance por rol

| Rol | Qué puede hacer en la ficha |
|---|---|
| **Vendedor** | Consulta y gestiona únicamente los clientes que tiene asignados actualmente. |
| **Supervisor** | Usa la misma ficha para los clientes de su equipo. Si un asesor está inactivo, conserva la consulta, pero las acciones quedan bloqueadas hasta reasignar al cliente. |
| **Gerencia** | Consulta la cartera completa y conserva las acciones que ya le corresponden. |
| **Directorio** | Consulta global sin cuentas bancarias y sin botones para modificar o registrar operaciones. |

Haber creado al cliente en el pasado no concede acceso permanente: el campo
técnico `creado_por` sirve como registro histórico, no como permiso de lectura.
El historial sigue siempre la asignación actual del cliente, aunque una gestión
anterior haya sido registrada por otro vendedor.

## Protección durante la consulta

- Los permisos y datos visibles se vuelven a comprobar cada **60 segundos**
  mientras la pantalla está abierta.
- Al cerrar la ficha, cerrar una corrección o perder acceso, los datos consultados
  se retiran de la memoria temporal de la aplicación.
- La información personal básica usa una consulta propia y mínima
  (`cliente_ficha_fn`). La ficha no reutiliza `useClienteDetalle`, porque esa
  consulta fue creada para corregir datos y maneja más información de la necesaria
  para una consulta comercial.
- Las cuentas se solicitan mediante consultas independientes y solo cuando el rol
  está autorizado.
- El capital vigente en soles y el capital vigente en dólares se muestra por
  separado. Nunca se suman monedas diferentes en un solo total.

## Subplan de implementación

### 1. ✅ Completado — proteger lo que ya funcionaba

Se documentaron y probaron los recorridos existentes de Leads, Mi cartera,
seguimiento, contratos y corrección. También se verificaron teclado, foco,
lectura asistida, cierres y tamaños de pantalla.

### 2. ✅ Completado — construir una experiencia común

Se crearon piezas visuales compartidas para que las fichas de lead y cliente se
sientan parte del mismo CRM, sin mezclar sus reglas ni sus historiales.

### 3. ✅ Completado — entregar una fotografía comercial segura

La ficha usa su propia consulta mínima de identidad y contacto. Contratos,
historial, tareas y cuentas autorizadas llegan por consultas separadas. El resumen
calcula próximos vencimientos y capital vigente por moneda, sin sumar PEN y USD.

### 4. ✅ Completado — ficha lateral navegable

La consulta de cliente pasó a una ficha lateral con contacto rápido, resumen de
cartera, inversiones, historial y estados claros de carga o reintento. Funciona
en escritorio y móvil sin desborde y devuelve el foco al punto exacto desde el
que se abrió.

### 5. ✅ Completado — seguimiento dentro de la ficha

El vendedor puede ver la próxima acción, registrar seguimiento y continuar hacia
Hoy o Agenda. Los resultados se muestran solo después de que la operación fue
confirmada, evitando mensajes de éxito que todavía no estén guardados.

### 6. ✅ Completado — continuidad hacia la siguiente venta

Cada inversión muestra estado, capital, moneda y vencimiento. Desde la ficha se
conectan los recorridos existentes para renovar, aumentar la inversión, registrar
una nueva inversión, consultar el detalle y revisar el cronograma.

### 7. ✅ Completado — permisos alineados con la cartera actual

Se aplicó la misma regla desde la lista hasta el historial: cada vendedor ve su
cartera actual, el supervisor ve su equipo, Gerencia ve toda la empresa y
Directorio tiene consulta global sin cuentas ni acciones. Los clientes de asesores
inactivos siguen visibles al supervisor, pero deben reasignarse antes de operar.

### 8. ✅ Completado — pruebas técnicas y comerciales

Quedaron cubiertos los roles, reintentos, foco, móvil, contratos, capital por
moneda, historial según asignación actual, retiro de datos al perder acceso y
actualización periódica de permisos. Los controles automáticos de tipos, calidad,
compilación y seguridad respaldan la entrega.

### 9. 🟡 Pendiente — preview y aceptación

- Publicar la preview aislada sin cambiar producción.
- Probar la consulta con vendedor, supervisor, Gerencia y Directorio.
- Validar con Miguel la comprensión visual y los recorridos comerciales usando
  datos controlados.
- Resolver hallazgos y repetir los controles necesarios.
- Preparar una publicación controlada solo si existe autorización explícita.

**Salida pendiente:** preview aceptada y paquete listo para una publicación
posterior.

## Integración en el plan principal

Esta iniciativa se incorpora como **F4.1**, dentro de Postventa y dirección:

`Mi cartera operativa → Ficha comercial 360 → cadencias y exportaciones → cierre de release`

La implementación de F4.1 está terminada y el siguiente paso es la preview aislada.
La aceptación de esa preview sí es necesaria antes de considerar cerrada la
experiencia de seguimiento y nueva venta desde la cartera.

## Fuera de alcance

- convertir un cliente en lead o devolverlo al pipeline;
- fusionar `crm.actividades` con `crm.actividades_cliente`;
- inventar un segundo historial o duplicar renovaciones/aumentos de inversión;
- ampliar permisos bancarios o de contratos;
- sumar PEN y USD;
- publicar en producción sin visto bueno explícito.

## Definición de terminado

- El vendedor abre cualquier cliente visible desde Mi cartera en una ficha lateral
  coherente con Leads.
- Puede comprender estado, capital, contratos, historial y próxima acción sin
  cambiar de pantalla.
- Puede ejecutar únicamente las acciones autorizadas y cada mensaje de éxito
  significa que la operación quedó guardada.
- Supervisor, Gerencia y Directorio reciben la variante correcta por cartera y rol.
- Directorio no ve cuentas bancarias ni acciones.
- Clientes de asesores inactivos, errores parciales, móvil, accesibilidad y cambios
  simultáneos tienen pruebas.
- Como cierre pendiente: preview autenticada aprobada y evidencia registrada antes
  de cualquier cambio en producción.

## Indicadores comerciales para evaluar la mejora

- porcentaje de clientes activos con próxima acción;
- tiempo desde abrir la ficha hasta agendar una gestión;
- renovaciones y aumentos de inversión originados desde la ficha;
- clientes por vencer sin seguimiento;
- fallos de persistencia y reintentos;
- uso de la ficha por vendedor después del piloto.

## Relacionado

- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Mi cartera por meses]]
- [[Agenda comercial del CRM (plan v2)]]
- [[Acceso y roles del CRM]]
- [[Categorización de inversiones - Nuevo Renovación Upgrade]]
- [[Cierre Mi cartera operativa 2026-08-25]]
