---
fecha: 2026-10-13
tags: [crm, llamadas, f4-e]
---

# F4-e aplicada y entrega de pantallas

Miguel reanudó el encargo y autorizó completarlo. Las migraciones
`20261012192500` y `20261013145935` están aplicadas y registradas en
PortalAvanceCorp, comprobadas el 13/10 a las 10:39 Lima. La segunda conserva
el contrato y optimiza contactabilidad por lead: EXPLAIN de 20.000 llamadas
y 100 días pasó de unos 2,9 s a 15–22 ms, sin índices nuevos.

Banco 482/482; gate dirigido de llamadas con bandera F4-e 347/347; comparación
de JSON 7/7; catálogo/ACL/roles de producción, tipos y lint/typecheck PASS.
Advisors sin nuevas alertas de rendimiento; aviso esperado de función DEFINER
para authenticated, con rol supervisor/gerencia validado internamente.

Decisiones confirmadas: retención tomada de la política (hoy 30), nunca un
30 fijo; ningún porcentaje en la respuesta, los calcula la pantalla por cohorte.

**Jhosep y su agente hacen las pantallas en un PR aparte**: tercera pestaña de
gerencia y bloque «Su celular» de supervisión. Codex deja evidencia y entrega
en el PR #255 y en el PR de continuación. No modifica el plan de Jhosep.

Propuesta #21 no bloquea: recomendar hora de confirmación, solo `no_contesto`
con estado técnico conocido elegible, ejecución parcial serial con garantía
en servidor frente a dos pestañas, sin descarte «No responde» al inicio y
prioridad para F4-e. Son recomendaciones, no encargo de implementación.
Fotografía de producción: 46/46 salientes con estado desconocido; cero
elegibles para ese lote. La v5 actual puede guardar una gestión aunque falle
el enlace: releer en pantalla no elimina la carrera.

Pendiente operativo: MacroDroid C1 el 15/10; C2/C3 cuando Miguel los tenga.
Legal ya aprobó y realizó el trámite; no se crea otro trámite en el sistema.

Relacionado: [[Llamadas desde el celular - F4-e migracion preparada (2026-10-12)]]
y [[Llamadas desde el celular - F4.2.4 aceptada y macros de C1 exportadas (2026-10-12)]].
Acta detallada: `CRM-Avance-Corp/docs/encargos/2026-10-13-f4e-aplicacion-y-propuesta21.md`.
