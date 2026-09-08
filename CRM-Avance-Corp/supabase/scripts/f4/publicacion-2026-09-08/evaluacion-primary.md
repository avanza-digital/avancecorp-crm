# Evaluación de la revisión de publicación

Claude entregó `CHANGES_REQUESTED`. Codex conserva la decisión como PRIMARY y
contrastó los hallazgos con código, catálogo productivo y ensayos. No se cambió
el SQL publicable ni se debilitó su preflight.

- **Permisos y tasas, aceptados:** el ensayo verifica RLS de flags, política y
  ledger; ningún rol API escribe estas tablas. Un vendedor no lee ni enciende
  flags. Política/ledger mantienen su SELECT autorizado vigente, por lo que no
  se adoptó la recomendación de revocar todas sus lecturas. El upgrade exige el
  campo exacto de origen, regla `heredada_upgrade`, base y tasa final; el núcleo
  R4 rechaza un origen de otro cliente.
- **Concurrencia, aclarada:** `inversiones_escritura_bajo_candado` adquiere un
  candado **compartido**. Dos sesiones lo adquirieron simultáneamente con la
  primera transacción aún abierta. No serializa altas entre sí. El cambio OFF
  añade esta lectura; no se afirma ausencia absoluta de cambios por apagar flags.
- **F2 global, decisión conservada:** cero llamadores en frontend/Edges, cero
  funciones llamadoras en el catálogo y cero jobs cron, activos o inactivos.
  Los runbooks históricos que nombran F2 son sustituidos por el censo y lote
  administrativo F4, disponibles desde la instalación. Restaurar el backfill
  global con F4 instalada contradice el cierre G4 y permite duplicar la vía de
  reconstrucción; se rechaza esa recomendación. La reversa operativa permanece
  OFF, conservando fuentes y estructura; un defecto posterior exigiría una
  corrección SQL nueva y verificada, no deshacer parcialmente 18 funciones.
- **Cotitularidad, falso supuesto descartado:** el índice único parcial
  `inversiones_contrato_uidx` impide dos vínculos para el mismo contrato;
  `inversion_cotitulares_vincular` aborta con `P0002` cuando no encuentra la
  inversión, también con NULL. Ambas condiciones se verifican en el ensayo.
- **GUC R4, contrato vigente:** se consume una sola vez y valida el origen con
  el núcleo `private.resolver_tasa`. F4 confirma una inversión por RPC y
  transacción. No se añade creación por lotes. El caso específico de aumento
  posterior a fusión es **NOT RUN en este ensayo de publicación** y queda
  explícito en la matriz F5; G4 ya cubrió fusiones/recuperación y esta revisión
  conserva los 47 cuerpos restantes. No se cambia aquí la regla de R4.
- **F5 y reproducibilidad, aceptados:** se nombraron fuentes por empresa,
  se explicitó el ámbito del buscador, la auditoría sin PII y el caso de fusión.
  El generador admite destino ausente y valida ocurrencias de las dos huellas;
  conserva el mismo SHA-256. La evidencia diferencia la copia sintética de la
  lectura productiva y se emite únicamente tras terminar todos los asserts.

Resultado final previo a publicar: **13 grupos SQL PASS**, 48 cuerpos exactos,
3.082 tests unitarios PASS; lint/typecheck/build/bundle/duplicación PASS; Deno
49 tests PASS; Playwright **140 PASS, 26 SKIP preexistentes, cero FAIL**; preflights
offline backend PASS. El preflight productivo se repite al aplicar. La revisión
no sustituye la verificación posterior del despliegue.

Orden y estados: frontend compatible primero (operación actual); SQL con F4/F5
OFF (sigue operación actual y F2 global se retira); PDF Edge con el mismo v8
y mapeo de error F4; Edge de acceso nuevo, JWT obligatorio y flag OFF. No hay
formulario F5 publicado ni invocación de altas reales para probar producción.
