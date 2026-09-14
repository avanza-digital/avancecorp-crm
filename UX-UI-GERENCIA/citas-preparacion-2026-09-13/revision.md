# Revisión independiente y resolución

Codex fue PRIMARY y único escritor. El reviewer `revision_citas_predeploy` fue
SECONDARY_REVIEWER de solo lectura. La invocación protegida de Claude falló sin
dictamen; **no se contabiliza como PASS de Claude**.

## Hallazgos iniciales: CHANGES_REQUESTED

| Evidencia revisada | Corrección del PRIMARY | Verificación |
| --- | --- | --- |
| `avance.ts`, vínculo cierre/entrevista usaba fecha prevista | Usar `asistioEn`; sin registro no hay evidencia de entrevista anterior al cierre. | Prueba de entrevista registrada después del cierre. |
| `avance.ts`, roster omitía al responsable inicial tras transferencia | El SQL devuelve identidad del primer analista; schema, contexto y roster la conservan. | Regresión de atribución por origen. |
| `avance.ts`, mes de entrevista usaba fecha programada | Fecha real de actividad `reunion_realizada`; cohorte SQL incluye registros de entrevista del mes aunque la cita sea anterior. | SQL real y unidad con meses distintos. |
| `avance.ts`, citas futuras de otro mes elevaban previsión | Suman generación, pero el cierre proyectado usa citas previstas en el mes y población elegible. | Regresión septiembre/octubre. |
| `avance-mensual.tsx`, moneda estimada se confundía con importe real | Selector separado para moneda de los importes reales. | E2E con lead PEN y contrato USD. |
| `avance.ts`, atribución de capital distinta se rotulaba como importe ausente | Incidencia independiente `atribucionPendiente`; no se calcula ticket ambiguo. | Prueba de capital asignado a otro analista. |
| SQL/modelo, leads repetidos del mismo perfil multiplicaban dinero/incidencias | Contrato único en SQL, perfil único en ticket y en incidencias. | Dos leads, un perfil; dos contratos, un cliente; dos clientes. |

## Revisión focalizada final: PASS

El reviewer comprobó el enlace canónico `contratos.cliente_id=leads.perfil_id`,
el filtro de contratos nuevos y el modelo de ticket. Casos revisados:
un cliente USD 12.000 + 8.000 → ticket 20.000; dos clientes con total 30.000 →
ticket 15.000; dos leads del mismo perfil no duplican ni generan importe ausente;
capital atribuido a otro analista → ticket no disponible e incidencia explícita.

Las 14 pruebas unitarias del modelo y el oráculo SQL en la rama aportan evidencia
ejecutada por el PRIMARY. El reviewer no ejecutó SQL remoto.

## Hallazgo posterior de la prueba HTTP

`guardar_control_citas_fn` y `aplicar_control_citas_fn` usaban SQLSTATE `40001`
para una versión desactualizada. En la Data API la petición permanecía
reintentándose; SQL directo no reproducía ese comportamiento. Se cambió a
`PT409`/HTTP 409, conforme al contrato de errores personalizados de PostgREST.
La prueba Auth real comprueba ambos conflictos, HTTP 409 y un tiempo límite;
el frontend conserva la edición y recarga la versión sin sobrescribirla.

Verificación posterior: SQL de configuración PASS, 48 comprobaciones HTTP PASS,
3.512 pruebas frontend y build PASS, 14 E2E específicos PASS. No se inició otra
cadena de revisión para repetir una confirmación ya sustentada por estos casos.

El gate general RLS sigue FAIL con 55 casos. Los resultados de Citas y el PASS
del reviewer no autorizan a convertir ese resultado general en PASS.
