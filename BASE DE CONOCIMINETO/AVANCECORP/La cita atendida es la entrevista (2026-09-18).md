# La cita atendida es la entrevista (2026-09-18)

> **✅ EN PRODUCCIÓN el 18/09/2026.** SQL registro 305 (~16:10 Lima) y front
> `crm-20260918T211444Z-3745bb9770c2` (~16:15). Servidor primero, front después.

**Pedido de Miguel:** «cuando el analista diga que una cita vino a la cita, esto se convierta
automáticamente en una entrevista».

## El hueco: dos sistemas contaban la misma cosa de forma distinta

La regla de negocio ya estaba escrita desde el 13/09 en
[[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]]:

> Cita: generada en el CRM. **Entrevista: asistencia a una cita.** Si una persona asiste dos
> veces, suma dos entrevistas.

Y **Gerencia ya la aplicaba sola**: `private.citas_episodios` cuenta como entrevista toda tarea de
tipo reunión con `estado='completada'`. Ahí no faltaba nada.

Lo que no se había enterado era **el pipeline del lead**. Al cerrar una cita como «Se realizó», el
servidor escribe la actividad `reunion_realizada`, y el único avance automático que eso dispara
sube de `nuevo` a `contactado`. Si el lead ya estaba contactado —lo normal cuando la cita se agendó
por el flujo natural— **no se movía nada**. El analista tenía que ir al kanban y arrastrar la
tarjeta a mano.

Resultado: el número de entrevistas de Gerencia y la etapa del lead decían cosas distintas sobre la
misma persona, y la diferencia dependía de que alguien se acordara de arrastrar.

## El detalle que lo hace fácil: la etapa ya existía

«Entrevista realizada» **ya es una etapa del pipeline**. Su clave en la base es
`propuesta_enviada` (el nombre viejo, de cuando la etapa significaba otra cosa) y el front la
rotula así desde hace tiempo en `app/src/lib/tipos.ts`. No hubo que crear ninguna etapa: hubo que
conectar el hecho con ella.

⚠️ **No renombrar esa clave.** Trece funciones del servidor la comparan por texto y el CHECK de
`crm.leads` la enumera. El rótulo vive en el front; la clave, quieta.

## Lo que se decidió

1. **Asistió = entrevista, siempre.** No depende del resultado comercial: aunque quede «No
   interesado», la entrevista ocurrió. Así la etapa y el contador de Gerencia dicen lo mismo.
2. **El capital se pregunta en ese mismo momento.** Nadie llegaba a «Entrevista realizada» sin
   declarar el capital propuesto (regla del 25/07: de esa cifra viven el capital en proceso y las
   metas del mes, y el estimado del primer contacto es una corazonada). Si la etapa subiera sola
   sin preguntar, el avance automático fabricaría entrevistas con capital en blanco — el mismo bug
   que el diálogo de capital vino a cerrar, ahora invisible. Ver [[Layout del CRM = lógica comercial]].
3. **Un solo acto, una sola transacción.** O la cita queda cerrada Y la entrevista registrada, o no
   pasa ninguna de las dos.
4. **Segunda entrevista de la misma persona:** la etapa ya no sube, pero el capital recién
   propuesto **sí** se asienta. Son dos reglas distintas en una sola sentencia.
5. **Excepción «No interesado»:** ahí no se pide capital y el del lead no se toca. La entrevista se
   registra igual (ocurrió). Salió de la auditoría: exigir una cifra obligatoria a quien dijo que no
   obliga al analista a **inventarla**, y esa invención entra al capital en proceso y a las metas
   del mes por la misma puerta que las cifras reales. Una regla obligatoria que la gente solo puede
   cumplir inventando datos no protege el dato: lo corrompe.

## Cómo quedó, por capas

| Capa | Pieza |
|---|---|
| Tabla | `crm.leads` — sus CHECK siguen siendo el último candado |
| Núcleo | `private.entrevista_registrar(lead, actor, capital, moneda)` — autoridad, subir etapa, asentar capital |
| Puerta | `crm.cerrar_reunion_v3(...)` — valida el input y delega; la única expuesta, solo a `authenticated` |
| Pantalla | el diálogo de cerrar la cita: resultado comercial + capital, y a guardar |

**No se tocó `crm.cerrar_reunion`.** Su cuerpo está **sellado por md5** dentro de
`private.assert_sla_comandos`, porque de él depende el orden de bloqueos lead→tarea de todos los
comandos SLA. Cambiarlo obligaba a re-sellar y re-auditar ese orden para conseguir un efecto que se
logra **componiendo por encima**: la puerta v3 delega el cierre entero en `cerrar_reunion_v2`
(recibo idempotente incluido) y después llama al núcleo. Es la lección general: *cuando un writer
está sellado, se compone sobre él, no se abre*.

## Verificación

Ensayo **contra producción sin escribir nada** (receta de [[Probar en producción sin escribir nada]]):
la migración real —preflight y gates incluidos— más un oráculo, todo dentro de una transacción que
termina en `rollback`. **VERDE, 0 fallos**, contra la forma real del esquema y con actores vivos.
**6 mutantes, los 6 muertos.** Detalle y comandos en `supabase/scripts/entrevista-al-asistir/`.

### Tres trampas que enseñó el propio oráculo

1. **Un rechazo que no rechaza se escapa hacia adelante.** El primer mutante cerró la cita que las
   pruebas siguientes daban por abierta: el fallo salió como error crudo tres pasos después y el
   informe se perdió. Ahora cada rechazo comprueba que la cita sigue `pendiente`, y toda llamada que
   se espera exitosa va envuelta — un imprevisto es un FALLO, no un abort.
2. **Un caso condicional puede dar verde sin haber probado nada.** La prueba de ámbito estaba
   envuelta en «si existe un vendedor de otro equipo…» y su rama de aviso no sumaba fallos: sin ese
   actor, el único caso de denegación se saltaba en silencio. Los actores ahora son **obligatorios**
   y su ausencia aborta el ensayo.
3. **Lo que el recibo no guarda, el recibo no protege.** El recibo idempotente del CRM guarda el
   payload del cierre, no el capital. Repetir la misma operación con otra cifra la escribía mientras
   devolvía la respuesta vieja. La puerta detecta ahora el replay y no escribe nada.

## 🔴 Hallazgo aparte: cuatro gates del servidor están en ROJO en producción

Al preparar esto se midieron los ocho controles de producción. Cuatro llevan en rojo **desde antes,
por trabajos ajenos a este cambio**:

- `assert_auditoria` — 8 tablas sin rastro de auditoría completo (`crm.cartera_lecturas`,
  `crm.contratos_eliminados_auditoria`, `crm.inversion_ajustes_mes_cerrado`,
  `crm.inversion_backfill_lotes`, `crm.inversion_cotitular_origenes`, `crm.inversion_eventos`,
  `crm.inversion_solicitud_correcciones`, `crm.inversion_solicitud_revisiones`).
- `assert_analitica_leads_citas` — `crm.contrato_eliminar_auditado` sin declarar (ya anotado el 16/09).
- `assert_analista_vigencia` — puertas exentas cuyo cuerpo cambió desde que se declararon.
- `assert_f7_piezas_cerradas` — `crm.crear_contrato_con_cuenta` cambió estando sellada.

Los cuatro del mundo SLA están verdes. Un gate en rojo no avisa de nada nuevo: se vuelve ruido, y
el día que detecte algo real nadie lo mirará. **Esto merece una sesión propia.**

Relacionado: [[Cierre de mes]] · [[Fundamentos UX del CRM]] · [[Auditoria de Citas de Gerencia - frontend y contrato backend 2026-09-07]]
