# Respuesta de Codex (28/09) — código G4b

Reenviada al implementador de G4b: coherencia de la secuencia de páginas (P1), leads visibles/ocultos (P2), postventa con banderas, 42501 tras página válida.

**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

Hay un defecto reproducible en la coherencia entre páginas: la lista puede terminar mostrando más o menos filas que el total anunciado. Además, las pruebas aportadas no acreditan el aislamiento de leads ni la visibilidad específica de postventa.

El núcleo comprueba explícitamente el rol antes del ámbito. El sellado y la reversa incluyen controles transaccionales y de huella. No identifico una fuga demostrada en el SQL transcrito.

**FINDINGS**

**[P1] La paginación puede presentar una lista completa cuya longitud contradice su total**

Evidencia:

- `gestion-diaria-citas-queries.ts`, `useCitasGestion`: conserva `total: paginas[0]?.resumen.total ?? null`.
- `gestion-diaria-citas.ts`, `validarPaginaCitas`: exige igualdad entre filas y total al terminar únicamente cuando `!pedido.cursor`.
- `unirPaginasCitas` combina páginas y sobrescribe identificadores repetidos mediante `porId.set(...)`, sin validar la coherencia del conjunto.
- Cada llamada SQL calcula nuevamente `resumen.total`; no existe una instantánea compartida entre llamadas.

Reproducción derivada del código:

1. Primera página: total **26**, devuelve 25 citas.
2. Se crea otra cita del mismo día y ámbito, posterior al cursor.
3. Segunda página: total **27**, devuelve las dos restantes, `hay_mas=false`.
4. Ambas páginas pasan el validador. La pantalla anuncia **26 citas** y muestra **27**, sin advertencia.

La retirada de una tarea pendiente de descargar puede producir el resultado inverso.

**Recomendación:** validar también la secuencia completa: total coherente entre páginas, identificadores únicos y longitud acumulada igual al total al finalizar. Ante cambios, invalidar la consulta y ofrecer o realizar una recarga completa. Si se exige una instantánea persistente, hace falta soporte adicional del servidor; cambiar al total de la última página no resuelve todos los casos.

**[P2] El banco no ejercita la protección de leads que debe acreditar**

Archivo: `supabase/scripts/g4/test-g4b.sql`.

Evidencia:

- Ninguno de los dos `INSERT INTO crm.tareas` de los fixtures incluye `lead_id`.
- La comprobación de contrato solo verifica:
  ```sql
  ((x->>'lead_id') is null) <> ((x->>'lead_nombre') is null)
  ```
  Esa comprobación pasa cuando ambos campos son siempre nulos.
- No hay una cita con tarea visible y lead oculto cuya respuesta se compruebe explícitamente.

Por tanto, estas pruebas no detectan una regresión en la ocultación del identificador o nombre de un lead inaccesible. Esto es un defecto de cobertura; **no demuestra una fuga actual**.

**Recomendación:** añadir fixtures con lead visible y con tarea visible pero lead inaccesible para el actor efectivo. Comprobar los identificadores concretos de las citas, su permanencia en la lista y que el segundo caso devuelve ambos campos del lead nulos. Incluir el caso de nombre vacío que trata el SQL.

**TEST GAPS**

- **Postventa:** el encargo reconoce `multiempresa_flags` vacía. Además, ninguna aserción exige expresamente la inclusión o exclusión de `G4B V1 POSTVENTA`. La igualdad entre lista y cifra puede pasar si ambas omiten esa cita. Ejercitar la configuración efectiva de producción y comprobar los IDs esperados por rol.
- **Revocación con datos cargados:** el test titulado «un 42501 retira las filas» configura el rechazo desde la primera petición. Nunca carga filas. Falta provocar el 42501 después de una página válida y comprobar retirada de datos, limpieza de caché y ausencia de consultas automáticas posteriores.
- **Cambios entre páginas:** el banco consulta fixtures estáticos del día anterior. Falta insertar o retirar una cita entre peticiones y verificar el tratamiento de la incoherencia descrita en P1.
- **Ejecución:** `npm run check`, G4A_OK/G4B_OK, mutantes y reversa tienen **PASS comunicado por el implementador**. Ejecución independiente del reviewer: **NOT RUN**, conforme al aislamiento solicitado. No se adjunta evidencia de E2E del CRM en Docker.

**REGRESSION RISKS**

- `base AS MATERIALIZED` y `array_agg(b.id)` procesan el ámbito completo en cada página. El límite de 25/100 filas no acota ese trabajo. El impacto en el ámbito operación requiere medición; no hay una regresión de rendimiento demostrada.
- Los cuerpos de las funciones de cifra, roster y políticas RLS no están transcritos. Sus hashes permiten detectar cambios, pero no permiten revisar aquí su semántica. La equivalencia con producción queda apoyada en las verificaciones comunicadas, especialmente limitada para postventa.
- La reversa exige la huella exacta del paraguas G4b: rechazará correctamente un paraguas modificado posteriormente. No debe forzarse ante esa situación.

**RECOMMENDED NEXT ACTIONS**

1. Corregir la coherencia entre páginas y añadir las reproducciones de crecimiento y reducción del conjunto.
2. Completar los casos de leads, postventa y revocación con filas previamente cargadas.
3. Reejecutar los checks pertinentes, el banco G4a/G4b y los E2E locales en Docker. Registrar resultados y cualquier **NOT RUN**.
4. Publicar en este orden: verificar G4a viva → aplicar G4b en base → comprobar gates → publicar el front construido desde el commit verificado, idéntico en Main local y `avancecorp/main`. Para revertir: **front primero, base después**, como indica el script.

**CONFIDENCE: MEDIUM**

Alta para la incoherencia entre páginas y los vacíos concretos de pruebas; limitada para certificar RLS y paridad completa con producción sin sus cuerpos ni ejecución independiente.
