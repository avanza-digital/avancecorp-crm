# H3: revisión independiente y resolución

23/09/2026. LEVEL 3 por contrato SQL y autorización. Un único review mediante
`scripts/claude-review`, Claude SECONDARY_REVIEWER, herramientas/MCP deshabilitados;
Codex PRIMARY y único escritor. No se consultó Jev ni se añadieron dependencias.
CodeGraph no tiene índice en esta copia; su CLI indicó continuar con herramientas
normales sin indexar. Se adjuntaron 91.507 caracteres de evidencia saneada.

## Dictamen recibido

VERDICT:
PASS

SUMMARY:
Dentro de la evidencia adjunta no encontré P0, P1 ni P2 reproducibles.

- **SQL:** puerta y núcleo son INVOKER con `search_path=''`. EXECUTE queda solo para `authenticated`, y el núcleo tiene guard propio para la llamada directa. El roster se resuelve con un único helper. Resumen y página salen de la misma sentencia bajo RLS. El cursor `(vence_en,id)` es estricto y la integridad falla cerrada (22000). No hay DDL sobre tablas, policies ni `public` (la fixture solo lee `public.perfiles`).
- **Cliente:** la validación estricta, la limpieza por prefijo ante 42501 y el congelamiento con 2+ páginas son coherentes con la semántica de TanStack v5 (`hasNextPage` con `pages=[]` es seguro y `resetQueries` vuelve a `initialPageParam`).

Dejo solo hallazgos P3 y huecos de test. El cierre queda condicionado a fullcheck y fullE2E, que siguen pendientes.

FINDINGS:

[P3] Posible doble anuncio en la celda Contacto (cambio fuera del alcance H3)
File: `CRM-Avance-Corp/app/src/components/gestion-diaria/tabla-equipo-diaria.tsx` (hunk `@@ -45`)
Problem: el `<td>` recibe `aria-label={contextoContacto}` y además conserva `<span className="sr-only">{contextoContacto}</span>`.
Evidence: el diff añade el `aria-label` sin retirar el sr-only. Según el lector de pantalla, el nombre de la celda y su contenido se leen juntos o el label sustituye al contenido. Es una hipótesis: no hay prueba con lector adjunta.
Impact: posible verbosidad duplicada o comportamiento distinto entre NVDA y VoiceOver en una tabla H2 ya aprobada.
Recommendation: conservar un solo mecanismo. Si el `aria-label` se añadió por el layout móvil de `data-etiqueta`, justificarlo en el acta; si no, revertir esa línea.

[P3] El refresco externo puede absorberse en una petición anterior
File: `app/src/data/gestion-diaria-queries.ts` (`recargar`, `cancelRefetch: !compartirPrimeraPagina`)
Problem: cuando `actualizacion` sube durante un refetch por intervalo o foco ya en vuelo, `refetch({cancelRefetch:false})` devuelve esa promesa iniciada antes.
Evidence: el test «Resumen y Registro comparten… refresco simultáneo» confirma la deduplicación (1 llamada nueva para 2 `recargar`).
Impact: tras un evento que motiva la actualización, «Últimas gestiones» o el Registro pueden mostrar la foto previa hasta el siguiente latido (≤60 s). El riesgo es bajo.
Recommendation: aceptar y documentar la limitación, o cancelar solo cuando la petición en vuelo se inició antes del incremento de `actualizacion`.

[P3] Cambio de frescura al reabrir el Registro
File: `app/src/data/gestion-diaria-queries.ts` (`staleTime` condicional), `panel-analista-supervisor.tsx` (`abrirRegistro` remonta por `key={registro.apertura}`)
Problem: con `compartirPrimeraPagina`, remontar el Registro dentro de 60 s ya no reconsulta al montar. Antes, con `staleTime: 0`, sí lo hacía.
Impact: «Ver registro» puede mostrar datos de hasta 1 minuto sin indicarlo. Es coherente con el intervalo, pero es un cambio de comportamiento respecto a H2.
Recommendation: dejarlo explícito en el acta. Opcionalmente, forzar `recargar()` cuando la apertura es explícita y no un cambio de pestaña.

[P3] Petición duplicada al reiniciar en consumidores no compartidos
File: `app/src/components/gestion-diaria/registro-actividad.tsx` (`reiniciar` → `setReinicio`)
Problem: desde una página con cursor, `setCursor(null)` cambia la key a la primera página. Con `staleTime: 0` eso ya dispara un fetch, y el efecto `versionRecarga` llama además a `refetch()` con `cancelRefetch: true`, que cancela el primero y lanza otro.
Impact: una petición extra por reinicio. No hay error de datos.
Recommendation: llamar a `recargar()` solo si `compartirPrimeraPagina`, o solo si `cursorVigente === null`, como antes.

[P3] Comparación de UUID dependiente de locale
File: `app/src/lib/gestion-diaria-pendientes.ts:44`
Problem: `localeCompare` en lugar de comparar códigos. PostgreSQL ordena uuid byte a byte, que equivale al orden lexicográfico ASCII del hex en minúsculas.
Impact: hoy coincide en es/en. Una colación distinta rompería el orden y la validación de páginas; fallaría cerrado, sin fuga.
Recommendation: `x < y ? -1 : x > y ? 1 : a < b ? -1 : a > b ? 1 : 0` sobre los ids en minúsculas.

[P3] `dateTime` con microsegundos no es válido en HTML
File: `pendientes-supervisor.tsx:55`, `ultimas-gestiones-supervisor.tsx:31`
Problem: el spec HTML admite 1–3 dígitos fraccionarios; `vence_en` y `creado_en` llegan con 6.
Impact: validadores y algunas tecnologías de apoyo pueden ignorar la fecha máquina. El texto visible es correcto.
Recommendation: normalizar el atributo a milisegundos, por ejemplo con `new Date(x).toISOString()`.

[P3] UX y a11y menores en PendientesSupervisor
File: `pendientes-supervisor.tsx:29-30, 55, 33`
- La `<section aria-label>` duplica el h4. Conviene usar `aria-labelledby` apuntando al h4.
- `tarea.tipo` se muestra en crudo («reunion», «llamada»). Conviene reutilizar un mapa de etiquetas existente.
- La línea de primer intento y datos incompletos sale de `fila` aunque haya `sinPermiso`. Conviene ocultarla también en ese caso, por coherencia con «Se retiraron los datos anteriores».

TEST GAPS:
- `test-pendientes.sql:134`: tras la pérdida de visibilidad postventa solo se comprueba el total 1008. Falta afirmar que «H3 POSTVENTA» ya no aparece en `items`. Además, el conteo depende de la inserción previa «INSERTADA ANTES», lo que lo hace frágil.
- La paridad de extracción compara el JSON de respuestas exitosas. No consta que se haya comparado la precedencia de errores antes y después, por ejemplo un supervisor con destino ajeno más un día inválido (42501 vs 22023).
- No se adjuntaron `gestion-diaria-pendientes-api.ts`, sus tests, `pendientes-supervisor.test.tsx` ni el spec E2E. No pude verificar que la API rechace (y no devuelva vacío) cuando `validarPaginaPendientes` retorna null, ni el mapeo de PGRST202 y 22000.
- Falta un test de hook: fallo en `fetchNextPage` con 2+ páginas. Debe conservar las páginas, ocultar «Cargar más» y mostrar «Consulta incompleta».
- No se ejecutó la matriz general `test-rls.mjs` remota. Queda cubierta localmente por SQL y HTTP; debe declararse NOT RUN.

ARCHITECTURE RISKS:
- `assert_gestion_diaria_equipo` se re-sella con `replace()` del hash dentro de su propia definición. Está protegido por el md5 previo del cuerpo completo, pero cada extracción futura debe repetir este patrón.

SECURITY RISKS:
- No encontré ninguno dentro del alcance.
  - `ambito` ejecutable por `authenticated` en `private` solo devuelve lo que `equipo_visible_fn` ya permite bajo RLS.
  - `referencia_tipo='lead'` con enlace nulo revela solo la existencia de la tarea propia del analista, lo cual está aceptado en el contrato.

REGRESSION RISKS:
- Los tres puntos que tocan H2: la celda Contacto, la frescura de 60 s del Registro y el `recargar` demo, que ahora es no-op. Este último es una corrección, pero cambia el comportamiento.

RECOMMENDED NEXT ACTIONS:
1. Ejecutar fullcheck y fullE2E y reportar los resultados reales. `DONE` depende de esto.
2. Decidir sobre el `aria-label` de la celda Contacto: revertirlo o justificarlo.
3. Endurecer la aserción postventa del SQL y, opcionalmente, aplicar los P3 de UUID, `dateTime` y la etiqueta de tipo.

CONFIDENCE:
MEDIUM. Es alta para el SQL y el hook, que se revisaron completos. Baja para la capa API y los tests de componente, que no se adjuntaron.

## Decisiones y correcciones del PRIMARY

- **Contacto H2:** se retiró el aria-label añadido durante H3; se conserva su
  texto accesible original. La posible lectura doble era una hipótesis, no una
  prueba con lector real. No se cambió la tabla por ese aviso del linter.
- **Actualización compartida:** se conserva la deduplicación de una petición en
  curso. Un clic durante una lectura ya iniciada se une a esa lectura; no promete
  una transacción posterior al clic. Resumen muestra ahora la hora de consulta.
  El latido es de 60 segundos. No se usa esta lectura para confirmar escrituras.
- **Abrir Registro:** puede reutilizar la misma primera página, con frescura de
  hasta un minuto, que Últimas gestiones. Apertura explícita reinicia filtros y
  páginas; Actualizar exige una lectura. Es una decisión para cumplir la fuente
  compartida sin cargas duplicadas; las horas de consulta se muestran.
- **Reinicio no compartido:** desde una página posterior se aprovecha el fetch de
  la clave inicial; el efecto explícito se reserva a los casos que lo necesitan.
- **UUID:** comparación ASCII del hexadecimal normalizado, independiente del locale.
- **Fechas HTML:** dateTime normalizado a milisegundos; el cursor conserva todos
  los microsegundos del servidor para ordenar y validar.
- **Interfaz:** sección vinculada a su encabezado, etiquetas `TIPO_EVENTO`
  (Cita/Llamada/WhatsApp/Tarea) y retiro de señales antiguas tras 42501.
- **Pruebas:** agregado el recorrido completo tras revocar una referencia de
  postventa, vacío confirmado, comparación de precedencia de errores del núcleo
  previo/nuevo y Pendientes de un descendiente bajo puente inactivo. Añadidos
  fallo de tercera página, limpieza de otro filtro y respuesta tardía real.
- **Lint SQL:** retirada la variable y el array no utilizados al extraer el roster;
  nuevo sello calculado dentro de rollback. Paridad/replay/matriz repetidos.

No hubo segunda consulta: las correcciones son locales y tienen comprobaciones
concretas. La ausencia de archivos API/tests en el paquete del reviewer limita
su revisión, no la ejecución del PRIMARY: frontera API, componentes y E2E sí se
probaron. Los resultados finales constan en el acta de evidencia, no se atribuyen
al PASS de Claude.
