**VERDICT: CHANGES_REQUESTED**

**SUMMARY:**
La partición SQL es correcta para una misma instantánea y las policies transcritas no muestran una fuga entre roles. Encontré tres problemas accionables: una guarda RLS incompleta y dos divergencias adicionales entre SQL, demo y doble E2E.

La revisión es estática. Los resultados de ejecución son evidencia aportada por el PRIMARY; no los he reproducido.

**FINDINGS:**

**[P2] El preflight puede aprobar una RLS que ya no sea coextensiva.**

Evidencia: `private.assert_actividades_de_lead_base()` comprueba las huellas de las policies permisivas y enumera únicamente las que cumplen:

```sql
polpermissive and polcmd in ('r', '*')
```

Para las restrictivas solo exige que exista `crm_actor_activo_gate`.

Contraejemplo: añadir una restrictiva de SELECT en actividades que exija `creado_por = auth.uid()`. Las huellas, el conjunto de permisivas y la existencia del gate seguirían pasando. Sin embargo, titular y supervisor podrían ver el mismo lead y clasificarlo de manera diferente.

Impacto: falso verde en una garantía de la que depende el filtro. **No afirmo que esa restrictiva exista hoy.**

Recomendación: comprobar también el conjunto completo de restrictivas de lectura y el contrato del gate —expresiones, comandos y roles—. Añadir este mutante al ensayo del preflight.

**[P2] Demo y doble E2E pierden microsegundos en la frontera de tenencia.**

Evidencia: `app/src/lib/pipeline-columnas.ts`, funciones `inicioTenencia` y `tieneGestionVigente`, y `app/e2e/_helpers.ts`, `conGestionVigente`, comparan mediante `Date.parse`.

Con estos instantes:

```text
tenencia:  2026-10-01T12:00:00.123456Z
contacto: 2026-10-01T12:00:00.123455Z
```

SQL devuelve **sin gestión**. Las comparaciones del navegador pierden la diferencia y pueden devolver **con gestión**. Es precisamente la condición del fixture SQL 10. El nuevo `test-rls.mjs` ya reconoce este problema y utiliza microsegundos.

Impacto: el espejo y el doble discrepan del servidor incluso después de excluir lo deshecho.

Recomendación: conservar precisión de microsegundos al comparar y ejecutar el mismo caso frontera en SQL, demo y doble.

**[P2] Un `tenencia_desde = NULL` explícito se transforma en una tenencia inventada.**

Evidencia:

```ts
// pipeline-columnas.ts
let inicio = Number.isFinite(sello) ? sello : Date.parse(lead.creado_en)

// _helpers.ts
tenenciaReiniciada.get(lead.id) ?? lead.tenencia_desde ?? lead.creado_en
```

Un lead con titular, tenencia nula y un contacto posterior al alta queda en **sin gestión** en SQL y en **con gestión** en ambos espejos. El fixture SQL 08 fija expresamente el primer resultado.

El respaldo para datos demo antiguos está documentado, pero constituye otra divergencia, además de la reactivación reconocida.

Recomendación: distinguir la ausencia del campo en un fixture antiguo del `NULL` explícito. Normalizar los fixtures antiguos por separado y conservar el significado contractual de `NULL` en el doble de sesión real.

**RIESGOS Y RESPUESTAS A LAS PREGUNTAS:**

- **a. Partición y cifras.** El booleano exterior es total: `IS NOT NULL` y `EXISTS` producen verdadero o falso. No hay huecos ni solapes por lógica ternaria. Incluso si `metadata` fuera SQL NULL, el contacto se excluiría dentro del `EXISTS`, pero el lead seguiría cayendo en una mitad. Falta el DDL para confirmar si ese NULL es posible y si excluirlo sería correcto. Todos los agregados recortan la misma `base`; los conteos y capitales son aditivos. **`conversion.pct` no lo es**: debe recalcularse con sus numeradores y denominadores, no sumarse entre mitades. La complementariedad presupone los mismos filtros y la misma instantánea.

- **b. Lectura bajo RLS.** Con las policies suministradas, cada actividad depende de la visibilidad de su lead, sin restricción por autor. Dos actores autorizados que vean el mismo lead ven sus contactos y obtienen el mismo veredicto bajo la misma instantánea. No encuentro información adicional protegida que pueda filtrarse mediante los conteos. El problema es la cobertura futura del preflight descrita arriba.

- **c. Escritura y falsificación.** `actividades_insert` limita al analista a sus leads, permite al supervisor operar sobre su equipo/bandeja y a gerencia globalmente. Que un supervisor registre un contacto y cuente para el titular concuerda con la decisión de medir por fecha. **No puede acreditarse la integridad de fechas y marcas con estos fragmentos**: la policy no restringe `creado_en`, faltan sus posibles sellos y no están las policies/grants completos de UPDATE/DELETE ni el comienzo del trigger de resultados. Hipótesis concreta por comprobar: si se acepta un contacto fechado en el futuro, podría sobrevivir a una reasignación y gestionar artificialmente la nueva tenencia. Tampoco puede determinarse si quitar `deshecho_en` queda bloqueado: depende, entre otras cosas, de cómo se construya `v_meta` con OLD y NEW.

- **d. Compatibilidad y publicación.** Los argumentos antiguos resuelven contra la firma ampliada gracias al nuevo valor por defecto. La transacción evita un estado **confirmado** sin función. Sin embargo, `NOTIFY` no espera a que PostgREST termine de recargar su caché: el frente nuevo puede recibir PGRST202 después del commit mientras la caché siga antigua. Hace falta comprobar la RPC real con `p_gestion` antes de publicar la pantalla. `resumen_cartera_fn` está respaldada por el ensayo; no hay evidencia suficiente para descartar todos los demás consumidores de la identidad antigua.

- **e. Guardas y catálogo.** No encuentro un falso verde causado por `IS NOT TRUE`, los tipos de `pg_catalog` con `search_path` vacío o la creación de una tabla TEMP sin calificar y su lectura como `pg_temp`. Comparar `proacl` convertido a JSONB puede rechazar ACL equivalentes con distinto orden; sería un falso rechazo, no una ampliación silenciosa de permisos. Fijar la huella nueva desde el banco es válido: producción comprueba posteriormente la definición instalada. No están transcritas las guardas anteriores, por lo que no puedo evaluar qué se perdió al quitarlas.

- **f. Reversa y registro.** La reversa protege una corrección posterior del **cuerpo de esta función** mediante su huella, y sus cambios de función, declaración y sello son transaccionales. Esa protección no acredita la compatibilidad de consumidores incorporados posteriormente. Retirar el despliegue del frente tampoco retira el JavaScript de pestañas abiertas, circunstancia ya advertida en el archivo. **`registrar.sql` no está incluido:** no puedo afirmar que registre el artefacto ensayado ni que sus guardas sean suficientes.

- **g. Semántica.** La igualdad temporal cuenta por decisión explícita; una asignación en lote comparte `statement_timestamp()`. Reasignar y reabrir renuevan la tenencia; un lead sin titular queda sin gestión. Pasar de `contactado` a `nuevo`, conservando titular y ciclo, **no** renueva el reloj. Por tanto, `destinosDeMovimiento()` puede ofrecer «Nuevo» y acabar mostrando la tarjeta en «Gestionado». Conviene ajustar o explicar esa operación en la interfaz; reiniciar artificialmente la tenencia alteraría el negocio. El avance automático ante una respuesta positiva no puede revisarse porque su implementación no está transcrita.

- **h. Rendimiento.** Los tiempos aportados no muestran una regresión que justifique cambiar índices ahora. El `EXISTS` puede ejecutarse como subplan correlacionado por candidato; no convertirse en semi-join no demuestra un problema. La cautela concreta es que el índice parcial tiene `(lead_id, creado_por, creado_en)` y no se restringe `creado_por`: que aparezca una condición sobre fecha no garantiza recorrer únicamente un intervalo pequeño. Un historial muy largo por lead, especialmente con muchos contactos deshechos, merece una prueba de distribución adversa.

**TEST GAPS:**

- El doble reinicia `tenenciaReiniciada` al cambiar vendedor y al deshacer un descarte. El PATCH transcrito no reproduce el reinicio de `descartado → nuevo` con el mismo titular. Probar la reapertura ordinaria por su flujo real de pantalla y comprobar dónde actualiza ese reloj.
- Probar escrituras negativas como `authenticated`: fecha futura/anterior explícita, contacto en lead ajeno, incorporación y eliminación de `deshecho_en`, modificación y borrado de contactos. Estos checks requieren la cadena completa de permisos y triggers.
- Las aserciones nuevas de `testCarteraKeyset` admiten que `con_gestion` esté siempre vacío y `sin_gestion` contenga todo: suma, disyunción y `every()` seguirían pasando. El oráculo SQL con identificadores esperados sí detecta ese defecto; la matriz HTTP necesita un caso positivo conocido por sí misma.
- Comparar claves o paginación contra otra llamada de la misma implementación demuestra consistencia interna, no equivalencia histórica. Las 256 comparaciones vieja/nueva aportadas cubren esa limitación.
- Probar la recarga real de PostgREST y la actualización de ambas listas tras registrar/deshacer. Dos peticiones independientes pueden observar estados distintos y mostrar transitoriamente duplicados o ausencias; la complementariedad SQL no garantiza una instantánea conjunta del tablero.

**VERIFICACIÓN:**
PASS comunicado para el ensayo SQL, oráculo y `npm run check`. E2E: 302 PASS, 2 FAIL reportados como previos y 26 omitidos. Matriz RLS nueva, preflight con credenciales y advisors: NOT RUN. El gate analítico continúa rojo por el contador ajeno; conservarlo no es una regresión de esta migración ni equivale a PASS.

**NEXT ACTIONS:**

1. Corregir las divergencias de precisión y NULL, completar la exclusión de deshechos y verificar la reapertura del doble.
2. Reforzar la guarda de restrictivas y añadir su mutante.
3. Acreditar los escritores de actividades y revisar `registrar.sql` y el diff de guardas anteriores.
4. Verificar disponibilidad HTTP de la firma nueva antes de publicar el frente y resolver el comportamiento visible de «Mover a Nuevo».

**CONFIDENCE: MEDIUM.**
Alta para el razonamiento de partición y los contraejemplos de paridad; limitada para integridad de escrituras y registro de migraciones por la evidencia ausente.
