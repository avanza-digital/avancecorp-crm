---
tags: [crm, gestion-diaria, llamadas, clientes, postventa, pendiente, objetivo]
fecha: 2026-10-01
estado: OBJETIVO PENDIENTE (decisión de Jhosep, 01/10/2026) · propuesta #13 para Miguel
---

# Llamadas desde el celular — clientes como objetivo pendiente (2026-10-01)

## Lo que decidió Jhosep
«Esto va para pendientes, porque primero tenemos que hacer que el módulo Gestión Diaria haga la gestión de
clientes. Pero sí es un objetivo pendiente hacer llamadas con clientes también, y gestionar las tareas de los
clientes, no solo de los leads: de los dos en general.» (01/10/2026)

Lo pidió al saber que un cliente puede necesitar una tarea para volver a llamarlo por un servicio nuevo.

## Por qué no entra en el plan de llamadas actual
- El plan aprobado por Miguel (Versión 3) cubre solo leads.
- La ingesta del celular busca el número solo entre los teléfonos de los leads. Una llamada a un cliente queda
  «por revisar» si conserva su teléfono de lead, y se ignora si el teléfono solo está en su ficha de cliente.
- La encuesta de «Llamar» no registra resultado en un lead cerrado (convertido o descartado): el núcleo v4
  responde «El lead esta cerrado».

## Ampliación del 02/10: también las llamadas que hacen ellos (entrantes)
Jhosep (02/10/2026): si un lead **o un cliente** llama al analista por iniciativa propia, debe contar.
Es lo que ya decía el plan aprobado («entrantes atendidas; perdidas como devolución») y retira su recorte
a «solo salientes» (propuesta #8). Quedó como propuestas **#14** y **#15** para Miguel:
- Entrante atendida de un lead o cliente → al colgar se abre su registro (encuesta del lead; postventa del cliente).
- Entrante perdida → tarea nueva «devolver la llamada».
- Número que no es lead ni cliente → nada: ni encuesta ni aviso.
- Métricas aparte (#15): llamadas recibidas, atendidas frente a perdidas, devolución de perdidas y
  resultado tras una entrante. Nunca se suman a «llamadas hechas» ni al cumplimiento del analista.
- Orden: primero se cierra la macro de salientes (F3-c); las entrantes van justo después. Ver
  [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]].

## Lo que ya existe y sirve de base
- **Agenda de postventa:** tareas colgadas del cliente (`crm.tareas.inversionista_id`) y gestiones por
  persona, detrás de la bandera `postventa_neutral`. Ver [[F6 - implementación de postventa (2026-09-10)]].
- **Cola del día con clientes, en producción desde el 29/09:** Gestión Diaria trae también las tareas de
  clientes, con la tarjeta «Cliente de tu cartera», «Llamar» y «Registrar resultado». Ver
  [[Cola del dia con clientes - plan (2026-09-28)]]. Comprobado el 01/10 en la versión publicada
  (`build-20261001T211328361Z`): el texto de la tarjeta y la llamada a `cola_accion_v3_fn` están dentro.
- **Venta cruzada:** el servicio nuevo de un cliente se registra desde su ficha, sin crear un lead nuevo. Ver
  también [[Gestión comercial de clientes - renovaciones y upgrades]].
- Al convertirse un lead, el sistema cancela sus tareas de lead; el seguimiento sigue en la postventa.

## Lo que faltaría para el objetivo
1. Completar la gestión de clientes en Gestión Diaria (lo que Jhosep pone primero).
2. Que la ingesta del celular reconozca también el teléfono del cliente y deje la llamada pendiente del cliente.
3. Que al colgar se abra el registro del cliente (su tarea de postventa) en vez de la encuesta de leads.
4. Que la llamada quede enlazada con la gestión registrada, y que las cifras separen leads y clientes.

## Dónde está escrito
- Propuesta #13 en `CRM-Avance-Corp/docs/plans/llamadas-celular/PROPUESTAS-DE-AJUSTE.md` (rama `feat/llamadas-f2`).
- Plan de llamadas: [[Llamadas desde el celular - F1 receptor por URL y ajuste Android (2026-09-30)]].
