# Seguimiento: textos claros de plazos y Agenda

Estado al 07/09/2026: **PUBLICADO Y VERIFICADO** en `crm.miavance.com`. Incluye pruebas de Gerencia y Supervisor en escritorio y móvil, y comprobación de los textos en una ficha real de Gerencia. Continúa el módulo documentado en [[Seguimiento - modulo propio y vista por rol 2026-09-07]].

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

## Publicación y comprobaciones

Commit fuente `fc4e1a8f6b4d183d2c541a076b6ff51827727073`, sincronizado con Main y `avancecorp/main` antes de publicar. Build `build-20260907T133816534Z`, release `crm-20260907T133846Z-fc4e1a8f6b4d`. ZIP de 1.923.230 bytes, SHA-256 `da3c312f57443bb2241b5c0e7f419589448bb1a28849998d310a887206bbbbed`. Conserva el release anterior del filtro de conversión (`543a5af`) en su ascendencia; no modifica la base de datos.

Pasaron 2.945 pruebas en 202 archivos, tipos y lint de los archivos afectados, compilación y verificación del paquete. Las dos pruebas E2E de Gerencia/Supervisor pasaron con inspección de capturas de la ficha en móvil y escritorio. La prueba de incertidumbre comprueba que `null` no se presenta como rechazo de espera ni como cero ampliaciones restantes; la de cobertura mantiene separadas una fecha habitual posterior y una espera que termina antes.

La [verificación HTTP](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/modulo-seguimiento-20260907/textos-plazos-produccion-http.json) confirma los 78 archivos sin fallos: 65 hashes exactos, 12 imágenes transformadas por Hostinger y `.htaccess` con 403. Build estable y ZIP inaccesible con 404 en CRM y portal.

En una ficha real se verificó el caso planteado: seguimiento vencido desde el plazo del 6 de setiembre a las 11:03 p. m.; fecha límite de etapa del 1 de setiembre a las 10:00 a. m.; máximo del 2 de setiembre a las 11:21 a. m.; actividad programada para el 31 de agosto a las 10:00 a. m. El núcleo confirmó que la espera de esa actividad terminó el 1 de setiembre a las 10:00 a. m., mostrado ahora expresamente. Se comprobó el aviso «Este caso necesita una decisión» y la instrucción para Supervisor o Gerencia. Se cerró la ficha sin guardar gestiones y se restauraron los filtros. Cero errores de consola. La comprobación real fue de Gerencia; Supervisor se comprobó mediante E2E con datos sintéticos.

Los commits documentales posteriores registran esta evidencia sin cambiar el artefacto servido.
