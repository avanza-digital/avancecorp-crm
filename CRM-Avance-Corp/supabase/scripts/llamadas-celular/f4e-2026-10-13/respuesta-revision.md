# Respuesta del PRIMARY a Claude

La revisión adjunta devolvió `CHANGES_REQUESTED`, no PASS. Se acepta el análisis
de equivalencia del CTE y se resuelven los dos P2 antes de producción:

- La reversa ahora toma el mismo candado del registrador, exige contenido exacto
  de la entrada y la retira en la misma transacción que restaura el catálogo.
  El banco prueba registro → reversa → ledger vacío → reaplicación, y rechaza un
  ledger alterado sin modificar el núcleo.
- O9 ya incluía una deshecha de 40 días, pero su lead también tenía llamadas
  recientes. Se cambia a un lead independiente con solo la llamada antigua.
  Un mutante que elimina la segunda rama de la unión debe fallar por O9.

Sobre los P3:

- `persona_vetada` es SQL STABLE, sin actor ni excepciones explícitas; delega en
  `leads_vetados_persona`, también SQL STABLE. Evidencia:
  `20260904130000_crm_f2b_b2_veto_persona_mutaciones.sql:80–121`; su huella actual
  coincide en el banco y producción. El dominio extra no agrega efectos laterales.
- Se califican las consultas del catálogo de pre/postflight con `pg_catalog` y
  se actualiza la cabecera con la medición final (15–22 ms). Las huellas siguen
  certificando LF, fallo cerrado. No se cambian atributos del repositorio entero.
- El rechazo del registrador sobre el núcleo original se prueba: «definición
  alterada» sigue siendo correcto; no se amplía la lógica solo por el texto.
- Se prueba que el registrador rechaza un ledger distinto y la reversa rechaza
  el núcleo original. Su comprobación final incluye nombre de columna; las
  huellas y estados se verifican además por SQL, no solo por la letra `t`.
- El gate temporal se retira. El selector versionado `--llamadas` declara su
  alcance y exige la misma preparación que el gate; no sustituye la matriz global.
  El contrato `equipos[].personas[]` está en
  `20260924201358_crm_gestion_diaria_pulso_habitos.sql:290–318` y en la respuesta
  real verificada por el gate.
- La segunda pasada de enlaces deshechos se conserva: EXPLAIN está por debajo
  de 100 ms y no se justifica más complejidad ahora.

No se solicita otra revisión para obtener un PASS: los cambios se validan con
los checks reales y sus resultados quedan en el acta de aplicación.
