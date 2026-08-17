# Especificación funcional: verificación, espera y toma de un lead libre

## 1. Resumen ejecutivo

Cuando un vendedor contacta a una persona y esta le informa que ya habló con otro asesor, el vendedor debe poder buscarla en el CRM y comprobar si ya existe un seguimiento activo.

Si el lead está en seguimiento activo, el vendedor que realizó la búsqueda solo podrá consultar información mínima del seguimiento. No podrá transferirlo, reabrirlo, editarlo, duplicarlo ni registrar actividades sobre él.

El vendedor podrá crear un recordatorio personal para volver a revisar el lead cuando venza el periodo de protección. Si al llegar esa fecha el lead realmente está libre, podrá tomar el mismo lead e iniciar un nuevo seguimiento, conservando su identidad e historial.

---

## 2. Problema comercial

Actualmente puede ocurrir el siguiente escenario:

1. Un vendedor llama a un posible cliente.
2. El cliente informa que ya habló con otro vendedor de la empresa.
3. El vendedor necesita confirmar si existe un seguimiento activo en el CRM.
4. Si no existe un flujo claro de consulta y espera, pueden presentarse problemas como:
   - duplicación de leads;
   - dos vendedores contactando al mismo cliente;
   - interferencia en el seguimiento de otro vendedor;
   - transferencias o reaperturas sin autorización;
   - actividades internas que renuevan artificialmente la vigencia del lead;
   - pérdida de oportunidades porque el segundo vendedor olvida revisar el lead cuando queda libre.

El CRM debe proteger el seguimiento activo y, al mismo tiempo, permitir que una oportunidad abandonada pueda recuperarse cuando termine su periodo de protección.

---

## 3. Objetivo

Crear un flujo comercial que permita:

- comprobar si un contacto ya tiene seguimiento activo;
- impedir cualquier intervención de otro vendedor mientras el seguimiento esté protegido;
- permitir que el vendedor interesado programe un recordatorio privado;
- volver a verificar la disponibilidad en la fecha correspondiente;
- tomar el mismo lead cuando esté libre;
- iniciar una nueva tenencia sin crear un duplicado;
- conservar toda la trazabilidad del lead.

---

## 4. Solución acordada

La solución se divide en tres momentos:

1. **Verificación de seguimiento activo.**
2. **Espera mediante recordatorio personal.**
3. **Toma del lead cuando esté realmente libre.**

El recordatorio no concede propiedad ni prioridad sobre el lead. La disponibilidad siempre debe validarse nuevamente en el servidor antes de permitir que el vendedor lo tome.

---

## 5. Flujo comercial detallado

### 5.1 Verificar si el contacto ya existe

El vendedor contará con una opción como:

> **Verificar lead por contacto**

Podrá buscar por los identificadores admitidos por la política actual del CRM, por ejemplo:

- teléfono;
- DNI;
- correo, cuando corresponda.

La búsqueda no debe modificar el lead ni registrar una actividad comercial sobre él.

### 5.2 Resultado: lead con seguimiento activo

Si el lead tiene seguimiento activo, el CRM mostrará una tarjeta informativa de solo lectura con la información mínima necesaria:

- indicador: **“Seguimiento activo”**;
- nombre del asesor que actualmente lo tiene, si la política de visibilidad lo permite;
- fecha del último contacto válido registrado;
- fecha estimada a partir de la cual podrá revisarse nuevamente;
- mensaje: **“Este lead todavía está protegido por un seguimiento activo.”**

#### Acciones prohibidas

Mientras el lead esté protegido, el vendedor que consulta no podrá:

- tomarlo;
- transferirlo;
- reasignarlo;
- reabrirlo;
- editarlo;
- registrar una actividad;
- registrar un duplicado;
- iniciar tareas de seguimiento;
- modificar la fecha de disponibilidad.

### 5.3 Única acción permitida: recordatorio personal

La única acción disponible será:

> **Recordarme revisar este lead**

Esta acción creará un recordatorio privado en la agenda o bandeja personal del vendedor.

El recordatorio deberá contener:

- referencia segura al lead;
- fecha sugerida de revisión;
- texto como: **“Verificar si este lead ya está libre.”**

#### Reglas del recordatorio

El recordatorio:

- no reserva el lead;
- no cambia el propietario;
- no se registra como actividad del lead;
- no renueva el periodo de protección;
- no modifica la fecha de último contacto;
- no es visible como gestión comercial para el asesor que posee el lead;
- puede eliminarse o reprogramarse sin afectar al lead.

Es importante que el recordatorio viva separado de las actividades comerciales, para que no altere el cálculo de inactividad.

### 5.4 Llegada de la fecha de revisión

En la fecha programada, el CRM notificará al vendedor con un mensaje como:

> **Este lead debe revisarse. Verifica si ya está libre.**

El recordatorio mostrará la acción:

> **Verificar disponibilidad**

Al pulsarla, el CRM consultará nuevamente el estado real del lead.

### 5.5 El lead continúa activo

Si el asesor actual realizó una nueva gestión o el lead todavía está dentro del periodo protegido:

- seguirá bloqueado;
- no se mostrará la acción para tomarlo;
- el CRM actualizará la fecha estimada de próxima revisión;
- el vendedor podrá reprogramar su recordatorio personal.

El vendedor no obtiene ningún derecho sobre el lead por haber creado el recordatorio.

### 5.6 El lead ya está libre

Si la verificación confirma que el lead está libre, se mostrará la acción:

> **Tomar lead e iniciar seguimiento**

Al confirmarla, el CRM deberá realizar una operación única y atómica que:

1. asigne el lead existente al vendedor;
2. inicie una nueva tenencia o periodo de seguimiento;
3. conserve el mismo `lead_id`;
4. conserve todo el historial previo;
5. registre quién tenía el lead anteriormente;
6. registre quién lo tomó y en qué fecha;
7. registre que fue recuperado después de quedar libre;
8. permita programar la primera llamada, tarea o siguiente actividad.

No se debe crear un lead nuevo.

### 5.7 Concurrencia

Si dos vendedores intentan tomar el mismo lead al mismo tiempo:

- solo uno podrá obtenerlo;
- gana la primera operación confirmada por el servidor;
- el segundo recibirá un mensaje como:

> **Este lead acaba de ser tomado por otro vendedor y ya volvió a estar en seguimiento.**

La validación debe hacerse al momento de tomar el lead, no únicamente cuando se abrió la pantalla.

---

## 6. Regla de disponibilidad

La disponibilidad se calculará utilizando la política vigente del CRM, actualmente basada en el periodo de inactividad definido para el negocio.

Para este flujo:

- la fecha debe calcularla el sistema;
- el vendedor no debe calcularla ni modificarla manualmente;
- el periodo debe partir de la última actividad comercial válida;
- los recordatorios personales no deben considerarse actividad válida;
- si existe una gestión nueva, la fecha estimada se recalcula;
- no se recomienda hardcodear el número de días en la interfaz: debe venir de la regla central del CRM.

Ejemplo comercial:

- El CRM muestra que el último contacto fue registrado el día 10.
- El seguimiento permanece protegido hasta la fecha calculada por la política.
- El vendedor programa una revisión para el día posterior a la liberación.
- En esa fecha, el CRM verifica nuevamente el estado.
- Solo si está libre aparece **“Tomar lead e iniciar seguimiento”**.

---

## 7. Estados funcionales sugeridos

| Estado | Significado | Acciones del vendedor interesado |
|---|---|---|
| `seguimiento_activo` | Otro asesor lo está trabajando | Consultar información y crear recordatorio personal |
| `pendiente_revision` | Existe recordatorio personal | Esperar o reprogramar recordatorio |
| `libre` | Ya puede ser tomado | Tomar lead e iniciar seguimiento |
| `tomado` | El vendedor lo tomó correctamente | Gestionar seguimiento normal |
| `tomado_por_otro` | Otro vendedor lo tomó primero | Sin intervención; mostrar aviso |

`pendiente_revision` debe ser un estado del recordatorio del vendedor, no un cambio en el estado comercial del lead.

---

## 8. Información visible y privacidad comercial

El vendedor que consulta un lead ajeno solo debe ver la información necesaria para tomar una decisión:

- que existe seguimiento activo;
- quién lo tiene, si está permitido por rol;
- fecha del último contacto;
- fecha estimada de liberación;
- posibilidad de crear recordatorio personal.

No deberá poder ver información sensible o innecesaria del seguimiento, como notas privadas, detalles completos de conversación, documentos o datos comerciales que no correspondan a su ámbito.

---

## 9. Trazabilidad requerida

Cuando el lead quede libre y sea tomado, se recomienda registrar un evento como:

> **Lead tomado después de liberación por inactividad**

Datos mínimos del evento:

- `lead_id`;
- propietario anterior;
- nueva persona responsable;
- fecha del último contacto válido;
- fecha en que quedó libre;
- fecha y hora en que fue tomado;
- motivo: `liberacion_por_inactividad`;
- usuario que ejecutó la acción.

La creación y eliminación de recordatorios personales puede auditarse separadamente, pero nunca debe modificar el timeline comercial ni la fecha de última actividad del lead.

---

## 10. Criterios de aceptación

### Caso 1: lead activo

**Dado** un lead con seguimiento activo,  
**cuando** otro vendedor lo busca,  
**entonces** ve únicamente información de estado, último contacto y fecha estimada de revisión.

No puede editarlo, transferirlo, reabrirlo, duplicarlo ni registrar actividades.

### Caso 2: creación del recordatorio

**Dado** un lead activo,  
**cuando** el vendedor pulsa “Recordarme revisar este lead”,  
**entonces** se crea un recordatorio personal.

El lead conserva propietario, estado y fecha de última actividad sin modificaciones.

### Caso 3: todavía no está libre

**Dado** que llega la fecha del recordatorio,  
**cuando** el CRM vuelve a verificar y el lead continúa activo,  
**entonces** permanece bloqueado y se ofrece reprogramar la revisión.

### Caso 4: lead libre

**Dado** que llega la fecha del recordatorio,  
**cuando** el CRM confirma que el lead está libre,  
**entonces** se habilita “Tomar lead e iniciar seguimiento”.

Al confirmar, se reutiliza el mismo lead, se inicia una nueva tenencia y se registra la trazabilidad.

### Caso 5: dos vendedores intentan tomarlo

**Dado** un lead libre,  
**cuando** dos vendedores intentan tomarlo simultáneamente,  
**entonces** solo uno obtiene la asignación y el otro recibe un aviso de que ya fue tomado.

### Caso 6: el recordatorio no modifica la inactividad

**Dado** un recordatorio personal asociado al lead,  
**cuando** se calcula la fecha de liberación,  
**entonces** el recordatorio no cuenta como actividad comercial ni reinicia el periodo de protección.

---

## 11. Fuera de alcance

Este flujo no permitirá:

- transferir leads activos desde esta pantalla;
- reabrir leads protegidos;
- forzar una reasignación;
- crear duplicados;
- reservar anticipadamente un lead;
- otorgar prioridad por haber creado un recordatorio;
- editar el historial del asesor actual.

Cualquier excepción gerencial o administrativa deberá pertenecer a otro flujo con permisos y auditoría propios.

---

## 12. Resultado esperado

Con esta solución:

- se protege el trabajo del asesor que mantiene un seguimiento activo;
- se evita duplicar o contactar simultáneamente al mismo cliente;
- el vendedor interesado no pierde la oportunidad de revisar el lead más adelante;
- los recordatorios no manipulan el cálculo de inactividad;
- cuando el lead queda libre, puede ser recuperado de forma ordenada;
- se mantiene el mismo lead, su historial y toda la trazabilidad comercial.
