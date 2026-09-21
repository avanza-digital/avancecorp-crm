---
tags: [crm, gestion-diaria, supervisor, plan, typesafe]
estado: etapas 1 y 2 publicadas — TypeSafe técnico probado, piloto humano pendiente
fecha: 2026-09-20
---

# Gestión Diaria F4 — objetivos y piloto TypeSafe

Miguel pidió consolidar los objetivos en texto, sin tablas, y actualizar el documento
principal: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`. Ese documento es la fuente
vigente para retomar. Esta nota registra la decisión; no sustituye el plan ni acredita una
implementación o publicación.

## Objetivos de F4

1. **Mi equipo hoy:** dar al supervisor visibilidad de la actividad y los problemas de cada
   analista, incluidos quienes tienen cero llamadas. Se muestra actividad registrada, no
   presencia en tiempo real. Esta etapa no depende de los cortes ni del pop-up, que se
   incorporan en las etapas 3 y 4.
2. **Detalle del analista:** poder investigar desde la alerta hasta las llamadas por hora,
   el registro del día y la ficha del lead.
3. **Cortes de jornada:** detectar ritmo insuficiente con las reglas acordadas y calculadas
   en Lima. Entre semana, 11:30 mínimo 3; 16:00 base ×2,5 con redondeo hacia arriba, piso 8
   y techo 30. Sábado solo 11:30 dentro de 09:00–13:00; domingo sin avisos de jornada.
4. **Alertas y seguimiento:** pop-up con evidencia, reconocimiento en servidor y posibilidad
   de posponer una hora; coherencia entre dispositivos, campana y lista, sin duplicados.
5. **Configuración gerencial:** ajustar reglas con versiones y vigencia futura. Esta pantalla
   pertenece a F4, no a F5; la alerta de tasa muy baja nace desactivada.
6. **Validación y activación:** probar permisos, cálculos, calendario, estados y regresiones;
   publicar servidor y frontend y activar los cortes con una política futura tras verificar.

Pendientes antes de activar: mínimo del sábado, tratamiento de analistas sin cartera abierta
y límites del aplazamiento (repeticiones y cierre de jornada). No se reabren las decisiones
ya cerradas ni se inventan estos valores.

## Añadido F4.1 — TypeSafe

Miguel aceptó añadir una revisión asistida de posibles contradicciones entre la nota y el
resultado tipificado de una llamada, como entrega posterior e independiente de F4.

La primera etapa evalúa utilidad con aproximadamente 100–200 notas anonimizadas y etiquetadas
por una persona. Se miden aciertos, falsas alarmas, omisiones, cobertura, costo y latencia;
se incluyen ambigüedad, negaciones y referencias temporales. Si la calidad de las notas o la
precisión no permiten una ayuda útil, no se activa.

La segunda etapa, condicionada al piloto, muestra la nota y el resultado al supervisor con
una sugerencia confirmable o descartable. Salidas: compatible, posible contradicción e
información insuficiente. La evaluación es asíncrona, se protege por permisos y se identifica
su versión para evitar resultados obsoletos. No modifica resultados, métricas, cortes ni
leads automáticamente y un fallo del servicio no bloquea el CRM.

Tener la skill no acredita acceso a la API. En la planificación del 20/09 no se enviaron
datos del CRM a TypeSafe ni se ejecutó el piloto. La consulta inicial a Claude sobre esta ampliación no produjo una
revisión válida y no se registra como PASS. El diseño se apoyó en la skill y documentación
oficial de TypeSafe; su utilidad para estas notas todavía debe medirse.

## Continuación

F5 sigue siendo el pulso global y el reporte de hábitos; puede evaluar posteriormente
clasificación de objeciones con TypeSafe. Detectar compromisos en notas exige comprobar las
tareas en servidor y no duplica las reglas obligatorias de F2. Ninguna ampliación de TypeSafe
bloquea F4 o F5. F6 conserva la retirada de Seguimiento tras observar F3–F5 estables.

Actualización documental del 21/09: el resumen inicial del plan principal también presenta
los objetivos y el estado de F0–F6, incluido F4.1, en párrafos y sin tabla. Se conservan las
seis etapas detalladas de F4, las dos de TypeSafe y sus criterios de cierre. Esta edición
no cambia código ni instala o activa funcionalidad.

La revisión documental de Claude del 21/09 pidió aclaraciones: el plan deja explícito que
la base de las 11:30 no cambia después y que los umbrales son valores iniciales configurables.
No se adoptan mínimos ni exclusiones provisionales: las decisiones pendientes bloquean la
activación de los cortes, no la vista del equipo. Las verificaciones de documentación pasan;
no se acredita implementación ni resultado del piloto.

Actualización de implementación inicial del 21/09: F4 etapa 1 cuenta con una candidata validada
localmente y reconciliada con Main. La entrega productiva sigue pendiente; ver
[[Gestion Diaria F4 - vista del equipo validada localmente (2026-09-21)]]. El piloto de
contradicciones de F4.1 no forma parte de esta integración.

Actualización posterior del 21/09: la etapa 1 ya fue publicada, como registra
[[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]]. Miguel retomó
la etapa 2 y se implementó el detalle horario y el recorrido al registro/ficha
en el taller aislado, sin nuevas SQL ni publicación. Ver
[[Gestion Diaria F4 - detalle del analista preparado (2026-09-21)]]. Las etapas
3–6 y el piloto TypeSafe conservan su alcance y sus decisiones pendientes.

Cierre posterior del 21/09: la etapa 2 se publicó desde `baa63aea`, PR #64,
con autorización `$release-crm`, CI y 110 controles HTTP finales PASS. Fuente,
artefacto, recuperación y límites en [[Gestion Diaria F4 - detalle del analista preparado (2026-09-21)]].
La siguiente implementación de F4 es la etapa 3; el recorrido humano productivo
y el piloto humano F4.1 no se presentan como ejecutados.

Arranque TypeSafe posterior del 21/09: Miguel pidió ambas vías, revisión asistida en el
CRM y apoyo técnico al desarrollo. La API respondió con `jev-1.13.0`; se preparó un
ensayo sintético y se probó el toolkit técnico existente. Control aislado: 19/20,
una falsa alerta en «Se gestionó». No se enviaron datos reales ni se activó el CRM.
Miguel indicó que un supervisor validará el piloto y comunicará quién. Estado y
continuación en [[Gestion Diaria F4.1 - TypeSafe tecnico y piloto humano pendiente (2026-09-21)]].

Relacionadas: [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] ·
[[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] ·
[[Gestion Diaria F3 - el dia del analista (2026-09-20)]] · [[Inicio]].
