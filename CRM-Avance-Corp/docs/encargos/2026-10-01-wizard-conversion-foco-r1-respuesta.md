VERDICT: CHANGES_REQUESTED

SUMMARY

El arreglo corta los dos desmontajes descritos para una misma instancia, actor y lead. Encontré un fallo demostrable: cerrar la precarga del documento conserva la marca y provoca una reapertura posterior.

Los `setState` durante render están acotados por condiciones que cambian inmediatamente; no veo un bucle ni una doble apertura por StrictMode. Deshabilitar este observador tampoco deshabilita el de Datos: `gcTime: 0` no elimina una consulta que mantiene observadores.

Checks: **PASS informado por PRIMARY**. Verificación propia: **NOT RUN**, revisión exclusiva de la evidencia transcrita.

FINDINGS

**[P2] El cierre durante la precarga no elimina la marca**  
**File:** [inversion-desde-lead.tsx](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-wizard-foco/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx:34)  
**Lines:** 34–40 y 71–73.

**Problem:** Una conversión retomada puede cerrarse explícitamente mientras carga el documento o cuando su consulta falla, sin eliminar `conversion-abierta`.

**Evidence:** La rama `!inicial` conecta tanto el diálogo como «Volver a la ficha» directamente a `props.onClose`. La limpieza nueva solamente aparece en los callbacks de `InversionNueva`, que todavía no está montado.

**Impact:** Secuencia reproducible: marca existente → recargar → cerrar «Documento del lead» mientras carga o muestra error → volver a montar la ficha. `Ficha` encuentra la misma marca y reabre la conversión, contradiciendo el cierre explícito. Las pruebas aportadas solamente comprueban el cierre desde el wizard ya montado.

**Recommendation:** Aplicar la limpieza al cierre explícito del envoltorio, incluidas carga y error, conservando la decisión de no limpiar por desmontaje.

TEST GAPS

- **Cierre durante carga/error:** añadir la secuencia anterior y comprobar que montar otra vez la ficha no reabre nada.
- **Caché compartida:** precargar un documento antiguo, retrasar la respuesta nueva y verificar que se fija esta última. Mantener un segundo observador activo y comprobar que sus relecturas siguen funcionando sin desmontar el wizard.
- **Condiciones reales:** el test de retoma emite `{bloqueo: null}` y sustituye el wizard. No demuestra que una tasa aprobada llegue a `ContratoNuevo` antes de inicializarse. Cubrir también error de condiciones, lead descartado y lead sin analista.
- **Cancelar → iniciar otra inversión → recargar:** la marca conserva el `solicitud_id` recibido al preparar la identidad. Falta demostrar qué ocurre cuando la solicitud activa cambia posteriormente; el código que resuelve esa prioridad no está transcrito.

REGRESSION RISKS

**Hipótesis: reutilización entre actores o leads.** `fijado` y `preparada` se inicializan una sola vez, y se retiró la `key` que incluía `l.id`. Si el padre reutiliza la instancia para otro lead, conservará documento y persona anteriores. La prueba de otra cuenta desmonta primero, por lo que no cubre esa transición. Verificar que existe una frontera de montaje por actor/lead o proteger explícitamente esa identidad.

Para los cambios de `actualizado_en`, documento y token descritos, no veo un desmontaje restante dentro del envoltorio. Tras confirmar, `preparada` mantiene estable la persona aunque `recargar()` cambie la etapa. No puede descartarse un desmontaje decidido por padres cuyo código no aparece aquí.

SECURITY RISKS

**Hipótesis: retoma después de perder capacidad de contratación.** En `lead-drawer.tsx`, líneas 166–184, la apertura automática no consulta `puedeConvertir`. El SQL aportado comprueba ámbito y asociación canónica persona↔lead, pero ese fragmento no comprueba `puede_contratar`. Verificar la conducta cuando esa capacidad desaparece y que las operaciones posteriores la controlan. Esto **no demuestra escrituras no autorizadas**.

La marca manipulada no permite, por sí sola, superar la asociación persona↔lead mostrada en SQL. Tampoco identifico una nueva llamada de creación introducida por la retoma que demuestre duplicación.

RECOMMENDED NEXT ACTIONS

1. Corregir el cierre de carga/error y añadir su regresión.
2. Comprobar las fronteras actor/lead, pérdida de capacidad y entrega efectiva de condiciones.
3. Validar cancelación seguida de una nueva solicitud y recarga.

CONFIDENCE: MEDIUM
