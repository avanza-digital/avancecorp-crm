# Encargo a Codex (SECONDARY_REVIEWER) — Propuesta #21: cierre en lote de llamadas pendientes del mismo lead

ROLE: SECONDARY_REVIEWER.
- NO editas, NO implementas, NO commiteas y NO invocas a otro agente. Solo revisas y devuelves hallazgos con evidencia
  (archivo, línea, fragmento) sobre el ANÁLISIS de abajo. Nada de código: la propuesta todavía no se construye.
- No ves la base ni la red: todo lo que debes juzgar va transcrito aquí.
- Riesgo LEVEL 2 (solo pantalla sobre una puerta existente, si se aprueba como está). Ronda r1. En español.
- Formato de respuesta: `VEREDICTO: DE ACUERDO | CON REPAROS | EN CONTRA` y una lista numerada de hallazgos con
  prioridad (P0 invalida la propuesta, P1 cambia una decisión, P2 conviene, P3 nota), cada uno con la evidencia y qué
  habría que cambiar. Sin hallazgo sin evidencia.

## La idea (Jhosep, 12/10/2026)

Cuando un analista llama varias veces al mismo lead y ninguna se conecta (p. ej. 5 llamadas en el día a quien nunca
contesta), hoy llena la encuesta 5 veces con «No contestó». MacroDroid y el CRM ya guardaron cada llamada con su hora.
Propuesta: en «Pendientes» de la pestaña «Llamadas del celular», cerrar varias pendientes del mismo lead de una vez,
eligiendo el resultado una sola vez.

Lo que NO cambia: cada llamada sigue siendo una gestión propia (5 llamadas = 5 gestiones), relación llamada–gestión
uno a uno con el mismo enlace y la misma vía que hoy (`pestana`), el analista elige el resultado (el sistema no decide),
`PLAN.md` no se toca (entra como propuesta #21 en `PROPUESTAS-DE-AJUSTE.md`).

Reglas propuestas: (1) mismo lead y mismo analista; (2) solo resultados sin conversación; (3) solo si el estado técnico
de la llamada NO es `conectada` ni `desconocido` (no usar `duracion_seg`: «cero no prueba nada»); (4) la tarea de
seguimiento se crea UNA vez para el grupo; (5) atomicidad e idempotencia definidas.

## Análisis del PRIMARY (Claude), verificado contra el código el 12/10/2026

**A. Viable solo en pantalla, con la v5 una vez por llamada.** `crm.registrar_llamada_v5` es el núcleo sellado de la v4
más, en la misma transacción, el enlace exacto con la llamada de `p_evento_origen_id` (vía `al_colgar` o `pestana`). La
pestaña ya la llama así, una llamada por vez (`app/src/screens/gestion-diaria/analista.tsx:169-173`). La bandeja ya
devuelve por fila `evento_origen_id`, `ocurrio_en`, `estado_tecnico` y `duracion_seg`. Sin puerta nueva ni migración.

```sql
-- 20261005155914_crm_llamadas_celular_enlace_exacto.sql, cola de crm.registrar_llamada_v5
  v_resp := private.llamada_registrar_v4(
    v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
    nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
    p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
  if p_evento_origen_id is null then
    return v_resp || pg_catalog.jsonb_build_object('enlace', null);
  end if;
  return v_resp || pg_catalog.jsonb_build_object('enlace', private.llamada_celular_enlazar_exacto(
    v_uid, p_lead_id, (v_resp ->> 'actividad_id')::uuid, p_evento_origen_id, p_via, pg_catalog.clock_timestamp()));
```
COMMENT de la v5: «Un enlace imposible no impide guardar el resultado: devuelve enlace.estado = no_enlazado con su
motivo». COMMENT de `llamada_celular_enlazar_exacto`: «llamada ya llegada, del mismo analista, identificada con ese lead
→ enlace … Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado}».

```sql
-- 20261006150154_crm_llamadas_celular_bandeja_con_origen.sql, fila de la bandeja (líneas 57-59)
'evento_id', p.id, 'evento_origen_id', p.evento_origen_id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
```

**B. La hora de cada gestión será la de la confirmación, no la de su llamada.** La v4 no recibe fecha (firma:
`p_actor, p_operacion_id, p_lead_id, p_resultado, p_submotivo, p_detalle, p_siguiente, p_tarea_id, p_descartar,
p_no_insista`, 20260921153654:23) y es núcleo sellado (F4.2.2: «sin alterar núcleo sellado»). La hora real de la llamada
vive en el evento (`ocurrio_en`) y el enlace 1:1 la une a su gestión. El pulso de Gestión Diaria cuenta «llamadas por
hora» por la hora de la gestión:

```sql
-- 20260924201358_crm_gestion_diaria_pulso_habitos.sql:14-22
  select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
    coalesce(a.metadata->>'resultado','sin_resultado'),
    coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
    extract(hour from a.creado_en at time zone 'America/Lima')::integer
  from crm.actividades a where … and a.tipo in ('llamada_realizada','llamada_no_contestada')
```
F4-e (decimotercera, en este mismo PR) cuenta `llamadas_hoy` por la hora de la llamada y `resultados_hoy` por la fecha
de la actividad: ahí el lote sale bien por diseño. Recomendación del PRIMARY: NO retrofechar gestiones (afectaría
reglas que ordenan por `creado_en`: «No responde exige 2 intentos posteriores a la última conversación», tareas
vencidas, metas). Si se quiere el pulso por hora real, es un cambio de F6 sobre los eventos enlazados.

**C. Tarea siguiente una sola vez: ya lo permite la v4.** Opcional en `no_contesto`; obligatoria solo en
`volver_a_llamar` y `agendo_reunion` cuando el actor es el dueño; una sola tarea de llamada pendiente por lead.

```sql
-- 20260921153654:94-96 y 189-196
  -- Tarea siguiente: obligatoria en volver_a_llamar (llamada) y agendo_reunion
  -- (reunion); opcional en no_contesto (llamada/whatsapp) y en numero errado /
  -- no es la persona (llamada al 2.º número o reintento); prohibida al descartar.
    if p_siguiente is null and v_vendedor = p_actor then
      if p_resultado = 'volver_a_llamar' then
        raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
      elsif p_resultado = 'agendo_reunion' then
        raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
      end if;
    end if;
```
En el lote: `p_siguiente` solo en la última llamada; las demás sin tarea. Además «No responde» (descartar) exige al
menos 2 intentos sin respuesta posteriores a la última conversación, esta llamada incluida (20260921153654:283-299):
un lote de 5 «No contestó» deja listo ese descarte en la última.

**D. Catálogo.** Resultados: `no_contesto, volver_a_llamar, agendo_reunion, no_interesado, numero_errado,
no_es_la_persona, pide_otro_producto` (CHECK `actividades_resultado_llamada_forma`). «Buzón» no existe. «Sin
conversación» para el lote = solo `no_contesto` (número errado y no es la persona son hechos distintos, uno por llamada).

**E. Serialización obligatoria (idempotencia de la app).** La app guarda UNA intención por actor + lead + cubo
«llamada» y rechaza un segundo guardado distinto mientras el anterior no confirme:

```ts
// app/src/data/sla-operacion-comandos.ts:41-44 y 179-183
function clave(actor: string, sujeto: string, comando: Comando): string {
  const cubo = comando === 'registrar_actividad_v2' ? 'actividad' : esLlamada(comando) ? 'llamada' : 'tarea'
  return `${PREFIJO}${actor}:${cubo}:${sujeto}`
}
  if (intencion && intencion.huella !== firma) {
    throw new CrmApiError('Hay un guardado pendiente de confirmar. Reintenta con los mismos datos antes de cambiarlos.', 'SLA_CONFIRMACION_PENDIENTE')
  }
```
Por eso el lote va de a una: enviar, esperar confirmación, siguiente. Un corte de red se reanuda con la misma llamada
pendiente y el mismo `p_operacion_id` (el recibo de la v4 devuelve la respuesta original con `replay: true`): sin
duplicados. «Todo o nada» exigiría una puerta DEFINER nueva que componga N registros (migración, LEVEL 3): el PRIMARY
recomienda parcial con estado por fila y «Reintentar las que faltan», deteniéndose en la primera que falle.

**F. Riesgos identificados.**
1. Dos pestañas: la base tiene un enlace único por llamada; si la otra pestaña ya cerró una, la v5 guarda el resultado
   igual y devuelve el enlace `no_enlazado`/`repetido` → una gestión de más sin llamada. Mitigación: releer la bandeja
   justo antes de cada envío y saltar la que ya no esté pendiente; la carrera residual es la misma del flujo actual.
2. Reasignación o nuevo dueño a mitad del lote: la v4 revalida el ámbito en cada llamada y el enlace exacto exige la
   llamada del mismo analista → la siguiente falla con mensaje y el lote se detiene. El nuevo dueño no entra por aquí
   (solo por la unión a mano, límite I-1 ya documentado en `SOPORTE.md`).
3. `estado_tecnico = 'desconocido'` excluido como propone la regla 3. SUPUESTO (no medido): con qué frecuencia C1 manda
   `desconocido`; si fuera frecuente, el lote serviría poco.
4. Deshechos: no aplican a pendientes. RLS: nada nuevo (misma puerta, mismos permisos).

**G. Decisiones que debería tomar Miguel antes de construir.**
1. Aceptar que la hora de cada gestión sea la de la confirmación (sin retrofechar) y, si quiere el pulso por hora real,
   encargarlo a F6.
2. Alcance: solo `no_contesto` y solo estados técnicos `no_atendida`, `rechazada`, `cancelada`.
3. Parcial con reintento (pantalla) frente a todo o nada (migración). El PRIMARY recomienda parcial.
4. Si el lote puede terminar en «No responde» (descartar) en la última llamada.
5. Prioridad frente a la pantalla de F4-e, #19 y #20.

## Qué te pido

1. ¿Hay algún hecho del análisis A–F que el código transcrito NO respalde, o alguna regla de la v4/v5 que lo invalide?
2. ¿Ves un riesgo de datos que falte (duplicados, gestiones huérfanas, métricas distorsionadas, ámbito)?
3. ¿La recomendación «parcial con reintento, de a una» es la correcta frente a una puerta nueva «todo o nada»?
4. ¿Qué decisión de G cambiarías o añadirías?
