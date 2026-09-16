# Cierre de revisión independiente

Codex PRIMARY; dos consultas a Claude mediante el wrapper aislado del proyecto.
El reviewer fue consultivo y no modificó archivos. Ambos dictámenes pidieron
cambios; las correcciones y los checks reales son responsabilidad del PRIMARY.

## Incorporado

- RPC antiguas sin EXECUTE externo: evita saltarse la copia o borrar Storage.
- Protección de la copia ante UPDATE, DELETE y TRUNCATE; registro del actor.
- Archivo de las altas idempotentes y detección recursiva de dependencias nuevas.
- La migración aditiva `20260916003000` también comprueba la acción exacta de
  cada FK permitida y rechaza un UUID vivo que ya tenga auditoría de eliminación.
  La primera migración ya estaba versionada y se conserva intacta.
- Conflictos de concurrencia y referencias restrictivas devuelven HTTP 409 con
  mensaje público; detalles SQL quedan ocultos. La guarda local de UI utiliza
  `ContratoEliminacionError` para mantener su mensaje deliberadamente público.
- Guardas de permisos/empresa/historial en ficha e invalidación de las consultas
  de contratos, cartera, métricas, leads y postventa después de eliminar.

## Hipótesis contrastadas con evidencia

- **INSERT concurrente de un hijo:** el bloqueo no se limita a las cuotas.
  `private.bloquear_fila_contrato_pdf(uuid)` ejecuta `SELECT ... FOR UPDATE` sobre
  el padre antes de tomar la copia. La FK del hijo necesita KEY SHARE en esa
  misma fila, incompatible con el bloqueo del padre. El catálogo productivo
  y la definición copiada al banco fueron inspeccionados. No se sustituyó la
  transacción por borrados individuales de hijos.
- **Reintento de alta después del borrado:** la migración
  `20260905234500_crm_alta_idempotente_replay_no_en_eliminacion.sql`, bloque de
  `v_contrato_id is null`, devuelve `P0409` / `ALTA_ELIMINADA`. La referencia
  SET NULL funciona como marca de eliminación y no recrea el contrato.
- **Supuesta ausencia de pruebas:** `auditoria.test.mjs` comprueba copia exacta,
  rol/inactividad, permisos, inmutabilidad, historial F4, dependencia nueva y
  rollback tras un fallo en DELETE. Los dos casos finales cubren colisión de
  UUID y cambio de acción FK. Siete grupos PASS en PostgreSQL real local.
- **Almacenamiento:** el ensayo HTTP prueba descarga byte a byte después del
  borrado y deniega el acceso público. Los objetos permanecen en rutas privadas;
  no se afirma retención WORM ni se altera la administración general de Storage.

## Decisiones y límites

Se mantiene la identidad del cliente dentro de la copia privada solicitada; no
se abre una ruta de edición ni purga de esa auditoría. Los accesos SQL de owner
siguen sujetos a administración autorizada. Las referencias de leads conservan
la semántica existente SET NULL; no se cambia la anulación comercial.

La validación del cambio usa datos ficticios y servicios reales en la rama
autorizada. El acta `README.md` y `VERIFICACION.json` distinguen estos resultados
de los fallos heredados de la matriz global. Ningún dictamen sustituye esos gates.
