VERDICT: CHANGES_REQUESTED

SUMMARY

Un P2 en (a): la apertura inmediata con caché permite desmontar una preparación de identidad todavía pendiente y descartar su resultado. No encuentro un fallo demostrado en (c). En (b) queda un riesgo de foco que la evidencia aportada no permite confirmar.

FINDINGS

**[P2] La relectura puede descartar una preparación de identidad en curso**

**File:** [inversion-desde-lead.tsx](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-wizard-foco/CRM-Avance-Corp/app/src/components/app/inversion-desde-lead.tsx:29)  
**Lines:** fragmentos `inicial`, `key={`${inicial.tipo}:${inicial.numero}`}` e `if (montado.current) {guardarConversionAbierta(...); setPersona(r)}`.

**Problem:** El formulario permite enviar la identidad usando la copia inicial, pero sigue expuesto a un desmontaje hasta obtener la persona o fijar la respuesta del documento.

**Evidence:** Este orden está permitido por el código:

1. Se abre con el documento en caché y se envía `prepararPersonaLeadInversion`; su respuesta queda pendiente.
2. La relectura devuelve otro `tipo/numero`. El envoltorio fija ese documento y cambia la `key`.
3. El formulario anterior se desmonta: `montado.current = false`. El nuevo no encuentra marca, porque todavía no se guardó.
4. Llega el éxito de preparación. El guard descarta tanto `guardarConversionAbierta` como `setPersona`.

La prueba «si la identidad se prepara antes de que el servidor responda…» cubre el orden contrario. Este fallo es anterior a `setPersona`; no depende de demostrar la carrera exacta entre commit y efecto.

**Impact:** La preparación puede haber terminado correctamente en el servidor, mientras la pantalla vuelve a pedir continuar con la identidad y permite repetir esa llamada. No hay evidencia para afirmar duplicación de contratos.

**Recommendation:** Impedir que la corrección del documento desmonte una preparación pendiente. Una opción es mostrar inmediatamente el formulario, conservando su origen de foco, pero habilitar el envío cuando el documento esté fijado. Otra es conservar la operación pendiente fuera del componente con `key`.

TEST GAPS · REGRESSION RISKS

- **(a):** Falta cubrir el orden documento → respuesta de preparación descrito arriba. La marca tampoco garantiza recuperación si falla `sessionStorage`: `guardarConversionAbierta` captura ese error.
- **(b), hipótesis:** En [dialog.tsx](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-wizard-foco/CRM-Avance-Corp/app/src/components/ui/dialog.tsx:60), el respaldo también se activa con un origen real fuera de cualquier diálogo. `.pop()` selecciona por orden del DOM; `isConnected` no acredita que la capa siga abierta o sea enfocable. Falta probar una capa saliente aún montada y un `Sheet` no modal adicional. No afirmo que esos casos ocurran actualmente.
- **(c):** El gesto que desarma no cancela el evento ni borra la marca; no veo que impida el clic posterior de «Convertir a cliente».
- **Verificación:** PASS reportado para las pruebas dirigidas. Ejecución propia: NOT RUN. El resultado final de `npm run check` y E2E completa no fue aportado.

RECOMMENDED NEXT ACTIONS

Corregir el P2 y verificar el orden inverso de respuestas. Comprobar los escenarios de foco indicados en navegador y recoger los resultados finales de los checks.

CONFIDENCE: MEDIUM
