# Evaluación PRIMARY — históricos F4, 08/09/2026

Claude actuó como SECONDARY_REVIEWER, mediante `scripts/claude-review`, sin herramientas ni escritura. El informe terminó correctamente con **CHANGES_REQUESTED**. No es aprobación de G4 ni revisión integral de la candidata final. Esta evaluación corresponde al bloque histórico: siete grupos de censo, lote transaccional y carreras SQL independientes.

## Hallazgos y decisiones

| Observación | Evaluación del PRIMARY y evidencia |
|---|---|
| P1: `es_primera_conversion` no coincide entre altas e históricos | No se confirma el defecto. La columna distingue conversión inicial del lead de inversión adicional; no define la elegibilidad de renovaciones/upgrades. `01-base.sql` lo documenta en `es_cierre_inicial`, `generar-migracion.mjs` adapta al conversor inicial con `true`, y `02-confirmacion.sql` registra las adicionales con `false`. `private.capital_episodios` continúa leyendo contratos/cierres. La evaluación anterior `auditoria-claude-2026-09-07/evaluacion-codex.md` conserva el inventario y las pruebas económicas. No se cambian reglas comerciales por esta hipótesis. |
| P1: no se demuestra el candado de identidad/inversión en la confirmación | La cadena existe: `crm.confirmar_inversion_fn` → `private.inversion_persona_autorizada` → `private.inversiones_escritura_bajo_candado` → `private.resolver_en_puertas_bajo_candado`. Este último toma el advisory compartido transaccional y exige READ COMMITTED. Se añadió una carrera con la **función real**, rol authenticated y claims ficticios: espera al commit administrativo y luego rechaza porque F4 está apagada. Es un ensayo SQL, no HTTP. |
| P1: el borrado contractual podría ganar después del censo | La reserva vigente llama `private.bloquear_fila_contrato_pdf`, que bloquea `public.contratos FOR UPDATE`; luego autoriza al actor y rechaza si hay inversión vinculada. El lote bloquea esa misma fila NOWAIT y repite el censo. Se añadieron pruebas usando la reserva real, en ambos estados: reserva previa impide enlazar, inversión enlazada impide reservar. La carrera genérica sobre la fila fuente y su recuperación también está cubierta. |
| P1: cobertura incompleta del protocolo de escritores F3/mapa/documentos | La exclusión de los escritores que usan la bandera es real. **Sigue pendiente para G4** el inventario exhaustivo de escritores administrativos/F2, correcciones de identidad y jobs, y demostrar todas sus carreras con el lote. No se interpreta el ensayo como protección frente a cambios ad hoc de un superusuario. No se autoriza promoción mientras ese alcance esté sin resolver. |
| P2: UUID demo incrustado | Se conserva la exclusión duradera del antecedente demo publicada en F2. La clase E del mapa no significa demo: descarta una identificación inválida o conflictiva. Cambiar una por otra alteraría la semántica. Se añaden fixtures revertidas para ese UUID de cooperativa y para un contrato `es_demo=true`; ambos se rechazan sin enlace. |
| P2: acta en crm, RLS sin FORCE y TRUNCATE administrativo | La regla local exige tablas nuevas en `crm`; RLS sin políticas deniega a roles API y todos sus privilegios, incluido TRUNCATE, están revocados. FORCE RLS no limita a un superusuario. El trigger protege UPDATE/DELETE, no un TRUNCATE administrativo ni a quien puede deshabilitar triggers; esa es una limitación explícita, no una garantía contra el propietario. No se añade una política permisiva ni se mueve la tabla en contra de la convención. |
| P2: mantenimiento puede superar cinco segundos con cien fuentes | **Pendiente de cierre** medir lotes máximos y el presupuesto de mantenimiento en el corpus final. El oráculo fija statement_timeout fuera de la función; lock_timeout no es un tiempo total. Las pruebas actuales son lotes pequeños. No se afirma que 100 fuentes estén aceptadas por rendimiento. |
| P2: DDL no idempotente | Se mantiene instalación atómica con guardas que rechaza instalaciones previas/derivadas. IF NOT EXISTS ocultaría una instalación parcial. El nuevo cargador comprueba cuerpos y triggers exactos si está instalado; si no, los ensayos crean el bloque dentro de una transacción revertida. El ensayo ya pasó sobre la instalación persistente del banco. |
| P3: clase NULL en mapa | `crm.backfill_multiempresa_mapa.clase` es NOT NULL: la fila hipotética no es válida. No se modifica el censo por ella. |
| P3: acta incompleta inalcanzable | Se conserva como diagnóstico defensivo ante una intervención administrativa incoherente. Una acta nueva incompleta no puede confirmar por la restricción diferida; la prueba fuerza ese rechazo. |
| P3: código para fuente ausente | La desaparición tras el censo provoca primero diferencia de previsualización, SQLSTATE 40001. Un censo que ya dice ausente es una entrada no aplicable (P0409). No se confunden ambos casos. |
| P3: GUC no definido restaurado como off | La restauración coincide con el contrato vigente de `crm.op_privilegiada`: solo `on` habilita esa rama. Se prueba que el valor no queda elevado y que el rechazo revierte los cambios. No se introduce una semántica nueva de privilegio por NULL. |
| P3: OR en búsqueda de fuente | Hay unicidad e índices para las dos fuentes; el helper exige exactamente un parámetro. No se cambia el plan sin medición. Forma parte de la medición pendiente del lote máximo. |

## Pruebas añadidas o ampliadas

- Auditoría de inicio/final: mapa y resultado enmascarados con `***`, huella conservada; los rechazos comparan también `public.audit_log` para el lote.
- READ COMMITTED obligatorio; reserva real de borrado antes y después del enlace; demos de ambos tipos; atribución nula admitida por contratos sin inventar creador.
- Dos lotes diferentes sobre las mismas fuentes pendientes: uno confirma y el otro exige recenso; no duplica relaciones.
- Confirmación real detenida hasta el commit del lote, luego rechazo por bandera apagada.
- Foto de concurrencia ampliada con identificadores, leads, documentos, titulares documentales, inversiones, titulares neutrales y Capital. El banco original debe coincidir íntegro; la copia permite solo sus enlaces esperados antes del ensayo explícito de deriva.
- Ventana de observación reducida de 4,5 a 2,5 segundos frente al lock_timeout real de cinco, sin relajar el código bajo prueba.
- Desconexión real de psql tras retorno de la función, antes de COMMIT: ausencia de acta durable y recuperación posterior.

## Límites de aceptación

G4 permanece abierto. Faltan inventario completo y carreras con todos los escritores F3/F2/jobs, prueba de lote máximo, reconstrucción/reversa íntegra, corpus histórico F2 original y aceptación restante de F4 (titularidad neutral, permisos dinámicos, correcciones de payload y paridad financiera completa). La copia SQL excluye cron y replicación, no duplica Storage ni prueba transporte HTTP. El resultado retornado antes de COMMIT no es una confirmación durable; una acta de ejecución no sustituye un recenso actual de los vínculos.

Las fallas iniciales de fixtures (cierre adicional sin campos obligatorios; snapshot contractual reutilizado; fecha comercial enviada en alta; fila_id de auditoría tratada como UUID) se corrigieron en el **oráculo** respetando los triggers/constraints reales. No se desactivaron controles del producto para aprobar pruebas.

No se aplicó un backfill productivo, no se enciende F4 en producción, no cambió el PDF. La instalación histórica local preservó los 34 cuerpos anteriores y añadió tres funciones con acta auditada.
