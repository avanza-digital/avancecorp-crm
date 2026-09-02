---
tags: [crm, ranking, metas, conversion, tipo-de-cambio]
actualizado: 2026-09-02
estado: DECISIÓN APROBADA — implementación en validación
---

# Rankings por mes calendario (decisión 2026-09-02)

Relacionado con [[Ranking de conversion del supervisor (RPC pendiente)]],
[[Ranking de capital total unificado (TC BCRP)]], [[Conversion mensual - definicion cerrada]]
y [[Cierre de mes]].

## Regla de negocio

Miguel confirmó que los rankings de Gerencia y Supervisión se comparan por
**mes calendario**, no por el rango libre exacto:

- la fecha final del filtro de Gerencia selecciona el mes del ranking;
- un mes pasado abarca del día 1 al último día calendario;
- el mes vigente abarca del día 1 hasta hoy en `America/Lima`;
- Conversión general, Capital total y Cosecha del lote deben usar el mismo mes,
  la misma población y el mismo alcance del usuario.

Para convertir USD a PEN en un mes histórico se usa el promedio de los últimos
**7 días publicados/hábiles** disponibles hasta el último día de ese mes. No se
inventa una tasa ni se usa el tipo de cambio actual para reescribir el pasado.

## Población mensual

Los tres núcleos existentes siguen siendo la única autoridad; no se crea una
función comercial paralela:

| Pestaña | Núcleo existente |
|---|---|
| Conversión general | `crm.conversion_mensual_fn(date)` |
| Capital total | `crm.cumplimiento_metas_fn(date)` + metas del mes + `crm-tipo-cambio` |
| Cosecha del lote | `crm.metricas_conversiones_equipo_fn(date,date)` |

La población se resuelve así:

- mes vigente: roster vivo;
- mes pasado todavía abierto: última revisión publicada de
  `crm.meta_periodos` / `crm.metas_vendedor`;
- mes cerrado: foto sellada y alcance histórico de
  `private.cierre_mes_visible`, incluido el supervisor que correspondía al
  momento del cierre.

El 2026-09-02 la comprobación de producción confirmó el caso real que motivó
la regla: agosto seguía abierto, su foto tenía 16 analistas y el roster vivo 17;
había 2 altas posteriores y 1 integrante de agosto ya inactivo. Mezclar ambos
conjuntos hacía divergir las pestañas o invalidaba toda la Conversión por su
defensa fail-closed.

## Restricciones de implementación

- Se reemplazan solo los núcleos existentes; no nacen RPC, tablas ni Edge
  Functions nuevas.
- `crm.cumplimiento_metas_fn` no se modifica: ya entrega la foto mensual.
- Mientras la identidad mensual carga o falla, las tres pestañas quedan en
  carga/error; ninguna muestra nombres o cifras de otro mes.
- El selector demo permanece fijado al mes vigente.
- La Edge existente `crm-tipo-cambio` debe desplegarse antes del frontend que
  solicita una fecha de corte histórica.
