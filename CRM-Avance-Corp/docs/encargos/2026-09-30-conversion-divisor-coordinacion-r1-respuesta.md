**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** La composición respeta el alcance global autorizado y conserva el núcleo existente. No identifico exposición de datos de leads en el payload. Sin embargo, hay una contradicción sobre la nulabilidad del gate, un caso problemático en la foto sellada y código del front ausente que impide resolver la pregunta sobre falsos rechazos.

**FINDINGS**

**[P1 condicionado] El guard acepta NULL; la descripción del gate y el PASS reportado necesitan reconciliarse.**

- **Evidencia:** en `20260930185623_crm_conversion_divisor_coordinacion.sql`, `crm.conversion_divisor_coordinacion_fn`:
  ```sql
  if not private.puede_operar_reparto_crm() then
  ```
  El contexto describe el gate como `private.rol_crm(auth.uid()) in ('coordinador','gerencia')`. El oráculo S03 confirma que `rol_crm` devuelve NULL para la coordinadora inactiva.
- **Problema:** si esa expresión describe literalmente el gate, devuelve NULL para ese actor. En PL/pgSQL, `IF NOT NULL` no entra en la rama de rechazo: la consulta continúa.
- **Límite de la evidencia:** esto contradice el PASS reportado de E02. **No doy por demostrado un bypass en producción**: el cuerpo real podría normalizar NULL a false, detalle ausente de la transcripción.
- **Acción:** aportar el cuerpo del gate para resolver la contradicción y hacer explícito el rechazo:
  ```sql
  if private.puede_operar_reparto_crm() is not true then
  ```
  No cambia qué roles autoriza.

**[P2] Una foto con `conversion_sin_analista: null` produce un objeto con cifras nulas.**

- **Evidencia:** la rama sellada de `sin_analista` comprueba únicamente:
  ```sql
  when v_cierre.cobertura ? 'conversion_sin_analista'
  ```
  y después construye un objeto extrayendo `divisor` y `numerador`.
- **Reproducción por inspección:** con cobertura `{"conversion_sin_analista":null}`, devuelve:
  ```json
  {"divisor": null, "numerador": null}
  ```
  La rama abierta, cuando no existe esa fila, devuelve `null`.
- **Impacto:** representación inconsistente de ausencia; podría rechazarla el esquema del front. El total de empresa no se infla, porque esas extracciones nulas terminan aportando cero.
- **Límite:** el comportamiento SQL está demostrado para esa entrada; no se acredita que existan fotos así en producción ni que el esquema las permita.
- **Acción:** distinguir valor objeto de ausencia/JSON null, o acreditar una restricción que excluya esa entrada. Probar las tres variantes contra el parser real.

**Riesgos y respuestas a las preguntas**

- **Ámbito y PII:** `p_global=true` coincide con la autorización empresarial solicitada. Salen nombres e identificadores de empleados, que sí son datos personales, pero forman parte del reporte autorizado. No aparecen contactos, identificadores ni filas de leads. No veo un oráculo de datos previo al gate, sujeto a resolver su nulabilidad.

- **Duplicación:** `por_origen` agrupa por identificador y une correctamente el grupo NULL mediante `IS NOT DISTINCT FROM`. Los nombres repetidos no multiplican filas; el agregado final desempata por UUID. **`equipo` y `roster` sí pueden multiplicarlas si contienen varias coincidencias**. Faltan la restricción de unicidad de `crm.equipo.perfil_id` y el contrato/cuerpo del roster para descartarlo. El postflight acredita los datos del mes ejecutado, no una garantía estructural futura.

- **Supervisor histórico:** `coalesce(r.supervisor_id, equipo.supervisor_id)` usa el supervisor actual también cuando existe una fila del roster cuyo supervisor es NULL. Si ese NULL significa «sin supervisor en ese mes», la etiqueta histórica sería incorrecta. Es un riesgo condicionado al contrato del roster, no un defecto de divisor demostrado.

- **Mes sellado:** la suma escrita reproduce la fórmula descrita de la puerta mensual: foto por persona + `fuera_ranking[*].conversion` + `conversion_sin_analista`. El divisor y numerador no se recalculan. E07, sin embargo, deja `fuera_ranking` vacío: no prueba esa contribución.

- **Período NULL:** resolverlo al mes vigente antes del gate solo calcula fechas; no consulta información protegida. Es coherente con autorizar antes de validar. Los errores de conversión de texto a `date`, anteriores a ejecutar la función, quedan fuera de esa garantía.

- **Postflight:** no es enteramente tautológico: detecta multiplicación de filas y discrepancias de la composición. Comparar cifras copiadas del núcleo no valida independientemente las reglas del núcleo. El candado mediante expresiones regulares es heurístico; por ejemplo, no detectaría una referencia escrita como `"crm"."leads"`. Los mutantes A/B fueron rechazados por ese candado, no por las aserciones funcionales de atribución.

- **Falso rojo del front:** **no puede resolverse con lo entregado**. Faltan `ConversionCoordinacionSchema`, `conversionCoordinacionConsistente` y el componente nuevo. El referido, según el contrato aportado, pesa cero y no justifica una diferencia. La mera existencia de `divisor_aproximado` tampoco demuestra que formulario + landing pueda diferir del divisor; falta acreditar su semántica para períodos históricos.

- **Alcance NO ENTRA:** en los cambios transcritos no se modifican núcleo existente, pesos, reporte de entregas ni conteos operativos. E08 acredita seis cuerpos concretos, no todas las dependencias ni los datos de configuración.

**TEST GAPS**

- Foto con `fuera_ranking` no vacío y numeradores distintos de cero; comprobar también numerador y porcentaje de empresa.
- Cierres reales, ajustes de meses pagados, renovación/upgrade y casos históricos con `divisor_aproximado > 0`. La siembra presentada prueba principalmente llegadas y reasignaciones.
- Contrato completo del front con meses abiertos/sellados, ausencia de analista y numeradores afectados por ajustes. El E2E de cambio de mes espera la solicitud, pero no verifica que el nuevo resultado termine mostrándose.
- La ejecución de la matriz RLS añadida no figura entre los resultados reportados.

**NEXT ACTIONS**

1. Resolver la contradicción del gate y garantizar rechazo de NULL.
2. Resolver y probar la representación de `sin_analista` en fotos nulas.
3. Aportar los cuerpos nuevos del front, las restricciones de unicidad y el contrato del roster.
4. Completar las pruebas focalizadas de foto y numerador indicadas.

**CONFIDENCE: MEDIUM.** Revisión estática de la transcripción. Ejecución propia: **NOT RUN**; los PASS mencionados son los reportados por el PRIMARY.
CODEX_EXIT=0
