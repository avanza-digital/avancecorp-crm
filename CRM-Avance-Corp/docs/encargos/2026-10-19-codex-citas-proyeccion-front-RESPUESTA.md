VERDICT: **CHANGES_REQUESTED**

SUMMARY: El diff contiene un acoplamiento que puede bloquear Proyección por un mes ajeno a su rango. La revisión es parcial: esta invocación carece de herramientas de lectura del árbol; no pude inspeccionar los archivos nuevos ni sus pruebas.

FINDINGS:

**[P2] Proyección depende del estado de carga de un mes que puede quedar fuera del rango.**

Archivo: [propuesta.tsx:240](/Users/usuario/dev/avancecorp-crm-proyeccion-citas/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx:240).

**Evidencia:** el ternario evalúa `cargando` y `errorCarga` de la consulta mensual principal antes de renderizar `ProyeccionCitas`. Esa consulta sigue ligada al mes superior mediante `useDatosCitasGerencia(mes)`.

**Escenario:** mes superior octubre; rango propio abril–septiembre. Los seis meses del rango cargan correctamente, pero octubre falla. La pantalla muestra el error de octubre e impide acceder a Proyección y a su control de rango, aunque sus datos estén disponibles.

**Impacto:** la disponibilidad de la pestaña depende de una consulta ajena al periodo solicitado.

**Recomendación:** resolver carga, error y reintento de Proyección exclusivamente mediante los meses de su rango. Comprobar este escenario en una prueba de integración del tablero, no sólo del hook.

RISKS / TEST GAPS:

- **Coste comprobable en el diff:** [citas-gerencia.tsx:22](/Users/usuario/dev/avancecorp-crm-proyeccion-citas/CRM-Avance-Corp/app/src/screens/hoy/citas-gerencia.tsx:22) conserva la consulta principal y añade `useMesesCitasGerencia`. El escenario anterior mantiene **siete meses activos** con refresco periódico. Compartir caché evita duplicar claves coincidentes; octubre no coincide con ninguno de los seis meses solicitados.
- **Hipótesis pendiente sobre la cohorte:** hay que comprobar que el RPC mensual incluya citas creadas en el mes pero programadas fuera de él. Si recorta exclusivamente por fecha programada, filtrar después por creación pierde citas. El diff no permite confirmar ni descartar este problema.
- **Los 14 mutantes no están auditados.** Sin su enumeración ni el contenido de las pruebas, no puedo identificar honestamente cuál sobrevive.
- Cálculos, identidad, TC, respaldo de Clientes, Σ, accesibilidad, CSV y aislamiento entre roles: **no verificados**, porque dependen de archivos no accesibles.
- `npm run check`, E2E y revisión a11y: **NOT RUN por este revisor**; los PASS corresponden al informe del implementador.

NEXT ACTIONS:

1. Desacoplar Proyección del estado mensual superior y verificar el caso octubre/abril–septiembre.
2. Resolver el séptimo mes activo y comprobar el contrato del RPC para citas creadas y programadas en meses distintos.
3. Contrastar cada mutante con una prueba que falle al introducirlo; el PASS general no demuestra esa cobertura.

CONFIDENCE: **MEDIUM**, limitada al diff transcrito.
