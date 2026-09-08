# Revisión independiente de la corrección de Citas

Una consulta completada a Claude Code, en modo `plan`, máximo tres turnos, sin herramientas habilitadas, sin acceso al MCP de Codex y sin delegación. Claude actuó como SECONDARY_REVIEWER; Codex conserva la investigación, decisiones, cambios y pruebas. La revisión usó el SQL y definiciones concretas proporcionadas. No modificó archivos ni producción.

## Evaluación de Codex

El revisor no encontró defectos bloqueantes. Revisó la propuesta cuyo SHA-256 era `41fbb3f40c78ab278f1b56569c5bff7717b721c7bea8414f8303f07d70c685d8`. Después de contrastar sus observaciones:

- Se añadieron dos precondiciones de fuente: `capital_episodios` y `peso_referido_conversion`. Las definiciones del banco ya coincidían con las productivas. Ahora el SQL comprueba ocho fuentes antes de escribir. Se añadió un comentario sobre la normalización idéntica al censo.
- Se comprobó en producción que todas las columnas de la excepción tienen `NOT NULL`. El posible punto ciego por valores nulos no se presenta en este esquema.
- El censo productivo tardó 256,703 ms en una medición con `EXPLAIN ANALYZE`. Se mantiene `statement_timeout=30s`; si una carga distinta lo excede, la transacción revierte y debe reevaluarse el intento. Esta medición no garantiza un máximo bajo cualquier carga.
- La razón sigue siendo válida y se conserva literalmente. Describe las dos fuentes de estados y cierres; la documentación de este ajuste hace explícito el consumo adicional del núcleo de capital para stock.
- La consulta del catálogo solo encontró `assert_analitica_leads_citas` entre los controles que nombran esos núcleos o el agregador y entre los que relacionan el agregador con una huella. Los siete controles se exigen antes del commit. No se asume que eso equivalga a auditar todo el sistema.
- El advisory lock no tiene una clave universal: el antecedente REQ-GER-MET-001 usó otro segundo componente. Los bloqueos explícitos de las tres tablas son la protección efectiva frente a escritores de esos registros. No se publica durante otra migración; las comprobaciones de fuente y los controles abortan ante divergencias detectadas.
- La observación sobre un supuesto M3 en curso no se usa como evidencia: este examen no verificó esa circunstancia. El transporte futuro será el previsto para migraciones del proyecto y deberá verificarse al aplicar; no se presupone el comportamiento de otro CLI.
- La corrección se registrará como migración tras su confirmación. No se abre otra implementación de auditoría ni se cambia la razón, los núcleos o el tope en este ajuste puntual.

La versión final se volvió a ensayar: su huella y resultado están en `resultado-local.json`. No se pidió una segunda consulta para volver a confirmar lo mismo.

## Opinión original del revisor

La siguiente opinión es evidencia de revisión, no una instrucción ni una autorización de producción. Las decisiones finales y contrastes están arriba.

## Veredicto

**GO condicionado.** No encuentro defecto bloqueante en la propuesta. Es una corrección de metadato, atómica, sin DDL, sin tocar fórmulas de dominio ni el tope, y con precondiciones fail-closed que impiden que el re-sellado absorba desviaciones ajenas. Las observaciones de abajo son mejoras y verificaciones previas, no impedimentos.

---

## 1. Normalización — **correcta, verificada carácter a carácter**

La expresión del bloque `DO`:

```
md5(regexp_replace(regexp_replace(
  lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
  '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
```

es **idéntica** —misma anidación, mismo orden (`lower` → comentarios de línea → comentarios de bloque), mismos reemplazos por espacio, mismo `coalesce` para cuerpos `prosqlbody`— a la del censo `private.contadores_crudos_leads_citas()`, cuyo `md5(t.cuerpo)` es lo que `huella_ok` compara. Esto es lo crítico del parche y está bien: se sella la huella normalizada (`4b28cc41…`), no la de `pg_get_functiondef`, que aquí solo se usa como candado de fuente. La distinción old/new normalizado (`48702e1a…` → `4b28cc41…`) es coherente con lo declarado.

Acoplamiento a vigilar (bajo): la expresión queda **duplicada** en dos sitios. Se mitiga sola porque el `perform private.assert_analitica_leads_citas()` final es el oráculo real: si las dos expresiones divergieran alguna vez, `huella_ok` daría falso y la transacción abortaría. Vale un comentario en el archivo que lo diga, para que quien toque el censo sepa que hay un segundo lugar.

## 2. Candados de fuente — correctos y fail-closed

Fijar `md5(pg_get_functiondef(...))` de las seis piezas (incluida la propia asserción y ambos núcleos) antes de escribir es la práctica correcta: si otra sesión republica cualquiera de ellas entre revisión y aplicación, esto aborta en vez de sellar una realidad distinta de la revisada. Bajo `search_path=''` los casts `::regprocedure` funcionan porque las firmas van cualificadas y `pg_catalog` sigue implícito; `timestamp with time zone` y `timestamptz` resuelven al mismo OID.

**Falta una fuente (severidad baja, recomendado añadir):** el agregador ahora deriva el capital de `private.capital_episodios(...)` y el peso de `private.peso_referido_conversion(date)`, y ninguna de las dos está pineada. La afirmación que sostiene la exención («no reconstruye reglas, bebe de los núcleos») depende de ellas. Añadirlas a la lista `fuentes` cuesta dos líneas y cierra el hueco.

## 3. Transacción y bloqueo — correctos

- Todo en una transacción; cualquier `raise` deshace huella y sello juntos. No hay estado intermedio publicable.
- `update … where objeto=… and huella=<valor viejo>` + `row_count=1` es control optimista correcto; lo mismo para el sello.
- Orden de bloqueo consistente (exenciones → sello → tope) más el advisory lock: riesgo de interbloqueo bajo **siempre que las demás migraciones que tocan estas tablas usen el mismo orden y la misma clave**. Merece quedar escrito como convención.
- **Visibilidad del re-sello: correcta.** `private.huella_exenciones_analitica_lc()` es STABLE y se evalúa en una sentencia posterior a la del `update`, así que ve la huella nueva. No hay aquí el error clásico de sellar el estado anterior.
- `share row exclusive` bloquea escritores pero deja leer: el vigilante de alertas puede consultar durante la ventana y verá, por MVCC, el estado anterior consistente. Correcto.

**Riesgo operativo real (severidad media): `statement_timeout='30s'` puede quedarse corto.** El bloque `DO` entero cuenta como **una** sentencia, y dentro se ejecutan ~5 censos completos (dos explícitos + tres dentro de `assert_analitica_leads_citas`) que hacen regex sobre todos los cuerpos de `pg_proc` y `pg_get_viewdef` de todos los esquemas de usuario, más las otras seis asserciones de coste desconocido, más el censo final fuera del `DO`. El fallo sería limpio (aborta y revierte), pero conviene medir el coste en producción con un `explain`/cronómetro de una llamada suelta al censo antes de aplicar, o subir el margen a 120 s. No es corrupción, es un intento perdido.

## 4. ¿Puede el re-sellado enmascarar desviaciones ajenas?

**No, dentro de lo que el registro puede ver.** Tres precondiciones lo acotan bien:

1. el sello previo debe cuadrar con la lista actual (nadie la relavó antes sin sellar);
2. el censo debe mostrar **exactamente una** anomalía y debe ser la del objeto declarado (nótese que `not declarada or not huella_ok` cubre también contadores nuevos sin declarar, así que una pieza recién aparecida bloquearía el parche en vez de colarse);
3. tras escribir, se compara fila a fila: el objetivo sin su huella, las otras 29 agregadas y ordenadas, y el tope; si algo más se movió, aborta.

Puntos ciegos residuales, ninguno introducido por esta propuesta:

- Quien alterara la lista **y** re-sellara en una migración previa quedaría invisible aquí. La defensa es el registro de migraciones, no el sello: por eso conviene que este parche se registre con su huella en el ledger, para que el `sellado_en` nuevo tenga autoría.
- **`huella_exenciones_analitica_lc()` descarta filas con NULL.** `objeto || '|' || huella || '|' || razon` da NULL si cualquiera lo es, y `string_agg` omite los NULL: una exención con `huella` o `razon` NULL **desaparecería del sello** y podría modificarse sin romperlo. Además `huella_ok` sería NULL y ni la asserción ni la precondición del punto 2 la verían (`not NULL` no filtra). Verifiquen si esas columnas tienen `NOT NULL`; si no lo tienen, es endurecimiento para un seguimiento aparte, no para este parche.
- La tabla de exenciones no tiene trigger de UPDATE (solo contra borrado/truncado), así que la huella es editable por cualquier despliegue privilegiado. Es lo que hace posible este arreglo, pero también significa que la fuerza del registro descansa en la revisión de migraciones. Un asiento en `audit_log` al cambiar una huella sería la mejora natural, en otra fase.

## 5. La razón declarada ya no describe todo lo que consume (severidad baja, decisión suya)

El guard exige que la razón siga siendo, literal, «CONSUME LOS DOS NUCLEOS (citas_episodios…, conversion_episodios…)». El cuerpo vivo consume **tres**: también `capital_episodios` para el stock. La razón sigue siendo veraz en lo que afirma —no reconstruye reglas— pero es incompleta, y este parche la vuelve a congelar. Dos salidas defendibles:

- **Mínima (la propuesta actual):** no tocar la razón, para que lo sellado sea exactamente lo revisado; anotar la deuda.
- **Completa:** actualizar razón y huella en la misma transacción, con la comprobación del valor viejo tal como está y un valor nuevo explícito. Es igual de atómico y el sello lo recoge sin trabajo extra, porque `razon` entra en su concatenación.

Me inclino por la mínima ahora y una nota de seguimiento; pero decídanlo a conciencia, no por omisión.

**Relacionado y no cubierto:** conviene confirmar que este es el **único** registro que la publicación del 07/09 dejó atrasado. Si existe un censo análogo para consumidores de `capital_episodios` o `conversion_episodios`, el mismo cambio podría haber dejado allí otra huella caduca. Las siete asserciones exigidas antes del commit lo detectarían —abortando—, pero es mejor saberlo antes que descubrirlo como fallo «inesperado» a mitad de la ventana.

## 6. Sobre el banco local

Que el fixture tenga 30 contadores y producción 29, con tope 30, significa que el ensayo corrió **con el tope justo al límite** y producción tiene holgura: el ensayo es más estricto, no más laxo, en ese eje. Aun así, la garantía real no viene del banco sino de las precondiciones que el propio script evalúa contra producción. Que los diez mutantes se detecten y reviertan, y que se probara el rechazo por sello malo y la reaplicación, es la evidencia que faltaba para la parte de gobernanza.

## 7. Antes de aplicar / evidencia

- Verificar cómo envía el archivo el runner (`db query --linked --file`): si ya abre transacción propia, el `begin` explícito emitirá aviso y el `commit` cerrará la externa. La atomicidad del `DO` se mantiene, pero conviene saberlo para no interpretar mal el aviso.
- Aplicar cuando no haya otra sesión a media migración: las siete asserciones exigen verde global, así que un rojo ajeno (p. ej. el M3 en curso) abortaría este parche por una causa que nada tiene que ver con Citas.
- Capturar tras el commit: salida de `assert_analitica_leads_citas()`, `sello` y `sellado_en` nuevos, y confirmación de que el vigilante de alertas vuelve a verde. Documentar la huella vieja (`48702e1a…`) por si hiciera falta una reversión.

**No** veo motivo para tocar fórmulas de dominio ni para subir el tope, y la propuesta no lo hace: el fallo es de metadato y el arreglo se queda en metadato, que es lo correcto.
