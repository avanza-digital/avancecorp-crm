# Conciliación puntual de una conversión reasignada

Aplicada en producción el 29/09/2026; verificada a las 15:12 Lima. Autorización
del usuario: «ok arregla esa para mantener la consistencia de la informacion,
es un trabajo de bekend rapido hazlo».

El lead `5cb6fb83-7a10-4d95-9bdd-a587e20388f2` pasó de Nayra a Linda,
pero su persona y el borrador conservaban a Nayra. La persona se había preparado
a las 14:39 y la última reasignación del lead fue a las 14:49. No había inversión
confirmada, perfil de cliente ni proceso de acceso pendiente.

Se ejecutó [la reparación acotada](../../supabase/scripts/conciliar-conversion-20260929.sql)
en una transacción, mediante `crm.reasignar_responsable_relacion_fn` y
`crm.revisar_solicitud_inversion_fn`. Se usó la cuenta administrativa existente
y un motivo que identifica expresamente la operación técnica autorizada en Codex.
No se atribuyó esta corrección a la supervisora del lead.

Resultado: lead, persona y solicitud coinciden con Linda. Un tramo histórico
cerrado y uno vigente; una revisión de responsable. La misma solicitud sigue
preparada y conserva datos, hash, condiciones, autoría y estado. Cero inversiones
creadas. Ningún cambio de esquema, funciones, permisos o frontend.

## Verificación

- **PASS:** [regresión SQL](../../supabase/scripts/test-conciliar-responsable-conversion.sql)
  en Docker sintético, siete comprobaciones: reproducción exacta del bloqueo;
  veto a analista en puerta de gerencia; tres asignaciones alineadas; historial;
  datos/autoría/hash intactos sin efectos económicos; nuevo analista recupera el
  mismo borrador; reintento sin duplicados. Terminó en rollback.
- **PASS:** el bloque exacto de reparación, con identificadores ficticios,
  rechazó un hash alterado, corrigió el caso y volvió a ejecutarse sin duplicar.
  Terminó en rollback. No quedaron solicitudes ni identidad del fixture.
- **PASS:** las cinco funciones principales tienen las mismas huellas en banco
  y producción; el script verifica esas huellas antes de escribir.
- **PASS:** relectura independiente de producción: tres responsables iguales,
  solicitud preparada, hash/autoría conservados, un tramo abierto, una revisión,
  cero inversiones. Consultas `contexto_conversion_inversion_fn` y
  `solicitud_inversion_fn` bajo la identidad de Linda recuperan la solicitud.
  Se usó una transacción con rollback: la segunda RPC toma `FOR UPDATE`, por lo
  que el primer intento con `READ ONLY` no podía ejecutarse (25006).
- **PASS:** revisión estática final y `git diff --check`.
- **Revisión independiente:** Claude devolvió `CHANGES_REQUESTED`, sin P0/P1,
  por guardas susceptibles a NULL. Se hicieron explícitas las comparaciones,
  se verificó `auth.uid()`, se añadieron las otras tres huellas y la actividad
  de auditoría. El PRIMARY volvió a probar el SQL exacto. No se solicitó otro
  dictamen ni se presenta el primero como PASS.
- **NOT RUN:** navegador/E2E y build frontend; no hubo cambios de interfaz.

El alcance es este incidente: no se cambió la regla general de reasignación ni
se introdujo sincronización automática para otros leads. La inversión queda
pendiente de que el equipo continúe y la confirme por su flujo habitual.
