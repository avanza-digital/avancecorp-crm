# Aviso de tratamiento de datos — llamadas desde el celular corporativo (BORRADOR, 10/10/2026)

**Estado: borrador para la revisión de Miguel** (dijo sí al borrador en el #249). Reemplaza el texto del 29/09 de
`REGISTRO.md` §3, que decía que «ningún dato sale del celular» y quedó desactualizado desde la activación del 07/10.
Todo lo que afirma sale del código y de las pruebas en C1 (fuentes al final). **No fija la base legal:** el plan
(§15) deja claro que la firma del analista no resuelve por sí sola el tratamiento de los números ajenos; eso lo decide
Miguel con quien revise el tema. Se entrega y se firma **antes** de instalar nada en C2 y C3.

---

## Texto para el analista

**Qué se instala.** En tu celular corporativo se instala MacroDroid, una app que detecta cuándo termina una llamada
que **tú hiciste** y abre la encuesta de Gestión Diaria del CRM para que registres el resultado al colgar. El CRM se
instala como app con tu cuenta.

**Qué sale del celular.** Al colgar cada llamada **saliente**, el celular manda al servidor del CRM tres datos: el
**número que marcaste**, la **hora** de la llamada y un **código** del celular (su etiqueta, por ejemplo C2, más la hora).
Nada más: no se graba la llamada, no se envía su duración, ni tus contactos, ni tu ubicación. Las llamadas que
**recibes** no se capturan. Cada seis horas el celular manda además una señal de «sigo vivo» con cuántos avisos tiene
pendientes.

**Qué se guarda y qué no.**
- Se guarda la llamada **solo si el número es de un lead que puedes trabajar** (de tu cartera, libre o reutilizable).
  Queda con tu nombre como quien la hizo, el lead, la hora y el estado (pendiente de resultado, registrada o
  descartada con motivo).
- Si el número **no es de ningún lead**, o es de un lead de otro analista, de un cliente o de alguien que pidió no ser
  contactado, la llamada **no se guarda** para nadie. Solo queda, durante 32 días, un registro técnico de que llegó un
  aviso, **sin el número**.
- Por eso una llamada personal hecha desde el celular corporativo no se guarda en el CRM. Aun así, el celular es
  corporativo: conviene no usarlo para llamadas personales.

**Cuánto tiempo.**
- Las llamadas **sin resultado** y las **descartadas** se borran solas a los **30 días**.
- Las llamadas con resultado **registrado** se conservan como parte del historial del lead, igual que cualquier
  gestión que registras hoy en el CRM.
- La bitácora de auditoría del CRM guarda cada cambio con el número reemplazado por `***`.

**Quién lo ve.** La llamada la ve quien tiene el lead en ese momento (tú, y si el lead cambia de dueño, el nuevo), el
supervisor del equipo y gerencia. Gerencia y tu supervisor ven además el **estado** del celular (si dio señal en las
últimas horas, cuántos avisos tiene en cola), **sin la hora exacta** de la señal, para no delatar llamadas personales.
La clave que une tu celular con el CRM solo se ve una vez, al asignarlo; nadie la guarda en claro.

**Lo que te pedimos.** No quitarle a MacroDroid los permisos de Teléfono y Registro de llamadas (sin ellos la llamada se
pierde sin aviso), mantener la app encendida (si es la versión gratis, mirar un anuncio cada 3 días) y avisar a tu
supervisor si algo no se abre o se abre con otro número.

**Cómo retirarte.** Pides a gerencia que cierre el celular en el CRM: la clave deja de valer al instante y el celular
deja de enviar. Lo ya guardado sigue los plazos de arriba.

**Dudas o incidencias:** a soporte, con la etiqueta del celular y la hora, nunca con el número.

---

Nombre del analista: ______________________  Celular (etiqueta): ______  Fecha: ____/____/2026

Firma: ______________________  Entregó (gerencia): ______________________

---

## Para Miguel (no va en el texto del analista)

- Pendiente la base legal del tratamiento de los **números de terceros** (leads): el plan §15 lo deja abierto; DS
  016-2024-JUS citado como referencia, no como conclusión. Si hace falta un texto de la empresa, va aquí.
- Si algún día se activan las **entrantes** (#14), este aviso se rehace: cambia qué se captura.
- Fuentes de cada afirmación: ingesta y decisión 3 (`20261001145242`, `20261005143843` §ingesta y purga), veto por
  número (`20261006162813`), retención (`20261005155914` §purga; política editable por gerencia entre 1 y 365 días),
  bitácora con el número enmascarado (`log_audit_sin_secretos`), visibilidad (`llamada_celular_visible`, decisión 7),
  salud sin horas exactas (`20261006150254`), macro (`macrodroid.md` §3c), pruebas de C1 (`REGISTRO.md` §5i–§5j).
