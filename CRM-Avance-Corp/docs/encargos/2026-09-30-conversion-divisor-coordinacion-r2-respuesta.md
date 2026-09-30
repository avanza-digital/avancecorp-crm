**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** Encontré un caso válido de mes sellado que produce un mensaje falso de ausencia de llegadas y una validación incompleta del mes en el formulario. No identifico una apertura adicional de permisos en lo transcrito. La paridad exacta con la puerta mensual oficial sigue sin poder acreditarse: se aporta su huella, pero no su implementación.

**FINDINGS**

**[P2] Un mes con producción exclusivamente fuera del ranking muestra «Sin llegadas».**

Archivo: `app/src/components/app/conversion-coordinacion.tsx`, símbolos `hayFilas` y `PanelVacio`.

Evidencia:

```tsx
const hayFilas = (datos?.analistas.length ?? 0) > 0 || sinAnalista !== null
```

Cuando es falso, se muestra `titulo="Sin llegadas en este mes"`.

Contraejemplo permitido por el SQL: mes sellado sin filas en `cierre_mes_vendedor`, `conversion_sin_analista: null` y:

```json
{"fuera_ranking":[{"conversion":{"divisor":5,"numerador":1}}]}
```

`conversion_divisor_empresa_totales` devuelve empresa **5 / 1 / 20 %**, `analistas: []` y `sin_analista: null`. El validador acepta ese payload, pero la pantalla muestra simultáneamente cinco llegadas y «Sin llegadas».

Recomendación: distinguir ausencia de filas mostrables de ausencia de producción. Para este caso, explicar que existe producción fuera del ranking conservada en el cierre.

**[P3] Un mes futuro se trata como fallo de carga y ofrece un reintento inútil.**

Archivos: `app/src/components/app/conversion-coordinacion.tsx` y `app/src/lib/conversion-coordinacion.ts`.

Evidencia: `mesInvalido` solo comprueba `periodoDesdeMes(mes) === null`; esa función valida formato y número de mes, sin comprobar el máximo. El atributo `max` del input no impide que un valor fuera del rango llegue al estado mediante edición.

Por ejemplo, con máximo `2026-09`, `2026-10` pasa la validación local, dispara la RPC y recibe `22023`. Termina en `PanelError`, con reintento y sin `aria-invalid`, pese a ser un error corregible del formulario.

Recomendación: validar también el rango antes de cargar y presentar el motivo junto al campo.

**RESPUESTAS A LAS CUATRO PREGUNTAS**

1. **Suma sellada:** la implementación suma divisor y numerador independientemente. Una conversión `{"numerador":2}` en `fuera_ranking` aporta **0 al divisor y 2 al numerador**. Los numeradores nulos se omiten; si todos son nulos, el total resulta cero por `coalesce`. Esto no provoca por sí mismo un error SQL. Sin el bloque sellado de la puerta oficial, no puedo confirmar que coincida con su tratamiento de esos casos.

2. **`INTO STRICT`:** no encuentro un camino que devuelva cero o varias filas cuando la consulta termina correctamente. `suma`, sin `GROUP BY`, produce exactamente una fila; los subselects con `LIMIT 1` no multiplican el resultado. Los errores de extracción o conversión JSON serían excepciones distintas.

3. **Consistencia del frontend:** las desigualdades de formulario y landing no rechazan una salida abierta válida con aportes no negativos: la empresa incluye las filas visibles y la fila sin analista. Los numeradores nulos tampoco intervienen en ese validador. Hay una frontera contractual pendiente: un objeto `conversion_sin_analista` sin divisor produce `divisor: null` en SQL y falla el esquema del cliente. No se ha demostrado que tal objeto sea una foto legítima; lo considero riesgo pendiente, no hallazgo confirmado.

4. **NO ENTRA:** no observo modificaciones de las funciones existentes ni de las reglas operativas excluidas en el material aportado. E08 respalda la conservación de los cuerpos enumerados; no acredita por sí solo cambios fuera del diff transcrito.

**RIESGOS Y TEST GAPS**

- E07 comprueba cifras esperadas manualmente, pero no compara contra la puerta oficial bajo gerencia.
- Varias aserciones E07 usan `<>`: por ejemplo, un divisor empresarial JSON `null` convierte la comparación en SQL `NULL` y puede dejar pasar E07c. Usar comprobaciones que también fallen ante ausencia o nulos inesperados.
- Faltan los casos de producción exclusivamente fuera del ranking y mes futuro introducido en el formulario.
- Verificación independiente: **NOT RUN**. Los PASS son los reportados por el PRIMARY; `npm run check` y E2E actuales todavía no tienen resultado final aportado.

**NEXT ACTIONS**

1. Corregir el estado vacío y la validación de rango, con pruebas específicas.
2. Endurecer E07 frente a nulos y contrastar los casos límite con la suma oficial.
3. Incorporar los resultados finales de los checks pendientes antes de cerrar.

**CONFIDENCE: MEDIUM.** Alta en los dos hallazgos; limitada para certificar equivalencia con la implementación oficial ausente.
CODEX_EXIT=0
