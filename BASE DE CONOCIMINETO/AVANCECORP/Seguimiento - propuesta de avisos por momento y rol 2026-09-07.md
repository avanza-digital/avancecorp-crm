# Seguimiento: propuesta de avisos por momento y rol

Estado: **PROPUESTA APROBADA, IMPLEMENTADA Y PUBLICADA EL 07/09/2026**. Miguel confirmó «ok vamos con tu planteamiento» y después «ok publica» al recibir el SQL concreto. Ver [[Seguimiento - avisos accionables implementados 2026-09-07]] para el resultado y la evidencia productiva.

Este documento conserva la propuesta inicial y su diagnóstico. Las reglas finales de primera gestión, próxima actividad y revisión comercial, junto con el cierre vigente de producción, están en [[Plan de avisos por accion y rol - 2026-09-07]]. El pendiente posterior de Citas también quedó resuelto: [[Control de Citas pendiente - huella de excepcion 2026-09-07]].

Miguel informó el 07/09/2026 que analistas y supervisores no entienden el recuadro «Seguimiento y plazos». Durante la revisión planteó retirar la explicación permanente y avisar en el momento apropiado de la cadencia. Esta dirección reemplaza la exploración inicial de tres recuadros alternativos; primero se debe resolver qué avisar, a quién y cuándo.

Relacionadas: [[Seguimiento - textos claros de plazos y Agenda 2026-09-07]], [[Seguimiento - modulo propio y vista por rol 2026-09-07]], [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] y [[Hoy Analista - seguimiento solo en su modulo 2026-09-07]].

## Evidencia y alcance

Revisión acotada a la captura proporcionada por Miguel y al código vigente. No es una prueba de comprensión con usuarios ni una auditoría completa de accesibilidad o de todas las pantallas.

![Recuadro actual proporcionado por Miguel](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-contextuales-20260907/01-recuadro-actual.png)

1. **Leer el estado — confuso.** «En espera» domina aunque la actividad del 5 de septiembre a las 13:00 sigue pendiente en la captura tomada el 7 de septiembre a las 10:37. La cobertura hasta el día 7 a las 13:00 no cambia el vencimiento de Agenda. La imagen no demuestra que la persona no haya realizado la actividad; demuestra que sigue pendiente de resolución en el sistema.
2. **Identificar la fecha útil — sobrecargado.** Cinco fechas, explicación extensa y dos límites de etapa con importancia visual parecida. La fecha máxima puede interpretarse como una ampliación ya concedida.
3. **Actuar — incompleto.** El recuadro no ofrece una acción directa para resolver la actividad. La persona debe traducir el estado y encontrar otra parte de la ficha o Agenda.

La captura conserva agrupaciones y encabezados reconocibles. La carga de lectura y el recorrido en dos columnas son riesgos visibles de comprensión; teclado, lector de pantalla, contraste computado y comportamiento a distintos tamaños requieren comprobación al implementar.

## Alternativas consideradas

| Alternativa | Evaluación |
| --- | --- |
| Acortar y recolorear el recuadro permanente | Reduce texto, pero sigue exigiendo interpretar fechas que no requieren acción en ese momento. |
| Retirarlo y emitir una notificación pasajera | Limpia la ficha, pero el pendiente puede perderse si el usuario no ve el aviso. |
| Avisos según estado y rol, con pendiente persistente y detalle opcional | Recomendada: aviso concreto cuando corresponde actuar; permanece en los pendientes existentes hasta resolverse. |

## Comportamiento propuesto

- **Todo dentro de plazo:** no mostrar una alerta SLA. Conservar la próxima actividad en Agenda y permitir consultar los plazos bajo demanda.
- **Llega la hora de una actividad:** mostrar al responsable la actividad y su acción disponible en Agenda. Es un vencimiento de Agenda, no el final de la cobertura de seguimiento.
- **Actividad vencida sin resolución:** pedir revisar la actividad o registrar su resultado real; no marcarla cumplida automáticamente ni asumir que nunca se realizó.
- **Seguimiento requerido por el núcleo:** pedir retomar el contacto y registrar la gestión. No disparar el aviso por una fecha base pasada si el núcleo confirma cobertura activa.
- **Revisión comercial requerida:** mostrar al supervisor o Gerencia el motivo y la acción de revisar y definir el siguiente paso. Conservar también las actividades que correspondan al analista: una acción no debe ocultar otra independiente.
- **Datos o lectura incompletos:** informar que no se pudo confirmar el estado; no presentar silencio como garantía de estar al día.

Un aviso representa un pendiente, con identidad estable y destino directo. La misma causa no genera avisos repetidos en cada refresco. Leer o reconocer no equivale a resolver. Se retira al confirmarse que su condición dejó de existir; una condición independiente o un nuevo episodio puede generar otro aviso. Los agrupamientos del supervisor y sus reconocimientos existentes deben conservar trazabilidad.

Los avisos persistentes viven en la campana/bandeja existente y en el contexto de la ficha mientras corresponda; Seguimiento conserva su lista paginada. No se devuelve el bloque retirado a Hoy del Analista.

## Hallazgo técnico previo, resuelto en la publicación

El siguiente diagnóstico corresponde a la versión anterior. La publicación conecta la campana, ficha y cola con los avisos autorizados del núcleo operativo.

La ficha usa `EstadoSlaV2` mediante `useEstadosSlaV2` y el módulo consume `cola_accion_v2_fn`. La campana sigue en `AlertasCRMProvider` → `useEstadoSlaOperativo` → `useEstadoSlaLeads` → `estado_sla_leads_fn`, más `derivarAlertasVendedor`/`derivarAlertasSupervisor`, `colaDe` y tareas del store. Por tanto, ocultar el recuadro y confiar sin cambios en la campana no asegura cobertura de seguimiento y revisiones según el núcleo operativo nuevo.

No se necesita otro núcleo de negocio. Se debe ampliar la proyección de avisos del núcleo vigente y adaptar sus consumidores: estado, destinatario autorizado, causa, instante de inicio, acción/destino, identificadores de tarea y episodio, y condición de resolución. Los cálculos comerciales deben permanecer en el servidor; la interfaz presenta sus resultados. No se deben formar totales de campana usando únicamente la primera página de Seguimiento ni el lote local de leads.

La ficha actual recibe tarea, fecha y cobertura, pero no un estado explícito de vencimiento de tarea ni todas las señales de la cola. La lectura de ficha debe recibir las señales necesarias del mismo núcleo, sin inventar un segundo cálculo temporal en el navegador.

Hoy las lecturas V2 se refrescan aproximadamente cada 60 segundos y el reloj del CRM también al recuperar foco/visibilidad. Eso no acredita avisos con el CRM cerrado ni una entrega exacta al segundo. Si se requiere entrega fuera del CRM, deberá diseñarse la ejecución programada y el transporte de notificaciones en backend; esa ampliación no está decidida ni implementada.

## Base de investigación

- [Nielsen Norman Group: Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/): priorizar las opciones de uso frecuente y mantener accesible el detalle secundario.
- [Nielsen Norman Group: Visibility of System Status](https://www.nngroup.com/articles/visibility-system-status/): el estado mostrado debe permitir comprender qué ocurre y actuar.
- [GitLab Pajamas: Choosing a messaging pattern](https://design.gitlab.com/patterns/choosing-a-messaging-pattern/): mostrar mensajes relevantes para quien puede actuar, usar avisos para condiciones dinámicas y evitar explicaciones permanentes con apariencia de alerta.

La recomendación para este CRM es una inferencia de esa investigación, la captura y la implementación revisada. Antes de publicarla se debe comprobar con analistas y supervisores que identifican la acción y su responsable sin interpretar las reglas internas.
