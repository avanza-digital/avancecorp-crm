# Seguimiento: textos claros de plazos y Agenda

Estado al 07/09/2026: revisión de textos implementada y verificada localmente, incluidos Gerencia y Supervisor en escritorio y móvil; **esta revisión todavía no está publicada**. El módulo ya publicado conserva su estado documentado en [[Seguimiento - modulo propio y vista por rol 2026-09-07]].

Continúa [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]]. La decisión es explicar cada plazo y quién debe actuar con lenguaje comercial, utilizando las decisiones y fechas que entrega el núcleo. No se introduce otro núcleo, cálculo de fechas en el navegador ni cambio de backend.

## Cada fecha responde una pregunta distinta

| Concepto | Significado que debe conservar la interfaz |
|---|---|
| Límite de seguimiento | Hasta cuándo corresponde registrar otra gestión. Durante una cobertura se muestra como el plazo habitual, junto con el estado de espera. |
| Fecha límite actual de etapa | Hasta cuándo puede continuar la oportunidad en esa etapa según su estado operativo vigente. Esta es la fecha que rige. |
| Límite máximo permitido | El techo que debe respetar cualquier ampliación. Mostrar una fecha máxima posterior no concede automáticamente tiempo adicional ni reemplaza la fecha límite actual. |
| Fecha programada en Agenda | La fecha y hora de la actividad pendiente. Su vencimiento conserva ese instante aunque exista cobertura de seguimiento. |
| Fin de la espera por una actividad | Hasta cuándo esa actividad cubre el seguimiento. No es una nueva fecha de Agenda ni un permiso general para dejar el caso sin atender. |
| Fecha con las ampliaciones aplicadas | El plazo resultante de ampliaciones ya confirmadas por el núcleo. No representa una ampliación solicitada o prometida. |

En la ficha se muestran fechas completas, con año y hora, e indicación explícita de Lima. Una fecha ausente o inválida se presenta como «Sin fecha confirmada».

## Revisión y responsable

Si el núcleo requiere revisión comercial, el aviso aparece antes de los detalles de plazos: «Este caso necesita una decisión». Explica el motivo y señala que el Supervisor o Gerencia debe revisar el caso y definir cómo continuar. Una actividad programada no oculta ni resuelve esta revisión.

Al indicar quién debe retomar el contacto se utiliza «el responsable», sin dar por hecho que toda ficha tiene un analista asignado ni inventar un nombre. Los datos incompletos se explican como información pendiente de revisión, no como un incumplimiento ya demostrado.

## Cobertura, incertidumbre y ampliaciones

La cobertura de una actividad solo afecta el seguimiento por falta de gestión. No suspende las revisiones de etapa, no cambia el vencimiento de Agenda y no autoriza a superar el máximo permitido. La ficha conserva visibles la fecha programada, el fin de la espera y el plazo habitual de seguimiento.

`compromiso.hasta_en` puede ser anterior a `seguimiento.limite_en`. Por eso se mantienen ambas fechas: terminar la cobertura no equivale por sí solo a vencer el plazo habitual. La interfaz no sustituye una por otra ni calcula una fecha combinada; presenta el estado que confirma el núcleo.

`cobertura_activa = null` significa que no se puede confirmar la cobertura; no equivale a `false` ni a una actividad rechazada. Se informa que faltan datos. Del mismo modo, un seguimiento no evaluable se presenta «por confirmar», sin convertirlo en vencido o dentro de plazo.

Las prórrogas automáticas confirmadas se llaman **«Ampliaciones aplicadas»**. Se muestra cuántas se aplicaron, cuántas quedan disponibles y su fecha resultante. El cambio de nombre no altera las reglas automáticas ni añade una solicitud o aprobación manual; una cantidad desconocida permanece «Por confirmar».
