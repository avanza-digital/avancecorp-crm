VERDICT: **CHANGES_REQUESTED**

SUMMARY: La autorización se comprueba antes de consultar el sellado, la RPC queda concedida solo a `service_role` y el cliente verifica tamaño, cabecera PDF y hash. Las seis claves que devuelve la RPC coinciden con las que exige `datosAnexoValidos`. Aun así, hay fallos en la vigencia bajo concurrencia, la validación del cronograma y la fiabilidad de la bitácora que deben resolverse antes de producción.

FINDINGS:

**[P1] Se puede emitir un anexo de una revisión que ya dejó de ser la vigente.**  
Archivo: `supabase/migrations/20260929151350_crm_contrato_pdf_anexo_snapshot.sql`, función `crm.contrato_pdf_anexo_snapshot`.  
Evidencia: `v_estado := private.contrato_pdf_estado_base(...)` y el posterior `select ... into v_pdf` son lecturas separadas, sin bloquear la fila padre. Si se crea una revisión pendiente entre ambas, la segunda lectura todavía puede recuperar el PDF del `job_id` anterior. Eso incumple la regla explícita de responder `ANEXO_SIN_PDF_SELLADO` ante una revisión nueva pendiente. Bloquear el contrato con el mutex existente y comprobar vigencia y autorización bajo ese bloqueo.

**[P1] `clasificarCronograma` acepta formas que el generador no produce.**  
Archivo: `anexo-v1.ts`, `clasificarCronograma`.  
Evidencia: tras comprobar el `retorno`, trata toda fila con `tipo !== "retorno"` como parcial. Por sí sola acepta, por ejemplo, una `devolucion` en interés simple o una `cuota` en compuesto; también admite parciales posteriores al vencimiento. Contradice su comentario «Cualquier otra forma aborta». Exigir `cuota` para simple y exactamente una `devolucion` al vencimiento para compuesto, conservando las comprobaciones del `retorno`.

**[P1] El borrado de un perfil choca con el candado de la bitácora.**  
Archivo: migración, columna `actor_id` y trigger `contrato_pdf_anexo_impresiones_solo_insert`.  
Evidencia: `actor_id ... references public.perfiles(id) on delete set null` requiere un `UPDATE` de la bitácora al borrar el perfil; el trigger `before update or delete` siempre lanza `P0409`. El comentario «NULL si el perfil se borró» no puede cumplirse y el borrado queda bloqueado. Definir una política de conservación del identificador que sea compatible con la inmutabilidad y probar el borrado del perfil.

**[P1] La bitácora registra impresiones que nunca llegaron a generarse.**  
Archivos: migración, `insert into private.contrato_pdf_anexo_impresiones`; `handler.ts`, `anexo()`.  
Evidencia: el `INSERT` se confirma dentro de la RPC antes de que la Edge valide los datos y renderice. Un 409 por cronograma incoherente, un 502 por datos inválidos o un 503 de render deja igualmente un asiento llamado «impresión». Además, el asiento no conserva el hash del anexo; tras borrar el contrato tampoco queda el snapshot para contrastar sus bytes. Registrar explícitamente la *solicitud* y su resultado, o registrar la generación exitosa con el hash del anexo. Ninguna de esas opciones debe afirmar que el navegador efectivamente lo imprimió.

**[P2] El 409 de cronograma se decide por una excepción demasiado amplia.**  
Archivo: `handler.ts`, `catch` de `renderizarAnexo`.  
Evidencia: cualquier `TypeError` se convierte en `ANEXO_CRONOGRAMA_INCOHERENTE`, aunque el bloque llamado también valida el snapshot y ejecuta el renderizador PDF. Un `TypeError` de esas capas recibiría un diagnóstico de negocio incorrecto. Usar un error específico emitido por `clasificarCronograma`; reservar 502/503 para datos o render fallidos.

**[P2] El candado «solo añadir» no cubre `TRUNCATE`.**  
Archivo: migración, trigger `before update or delete ... for each row`.  
Evidencia: ese trigger no se ejecuta para `TRUNCATE`; las pruebas solo intentan `UPDATE` y `DELETE`. Si la garantía incluye operaciones del dueño de la tabla, añadir un trigger `before truncate for each statement` y su prueba.

TEST GAPS:

- **PASS reportado, no reejecutado por este reviewer:** Deno 70/70, front 4 853 y arnés SQL local. **Sin resultado final:** e2e Docker. **NOT RUN:** gate RLS completo y `gen:types`.
- Falta una prueba que pase la respuesta **real** de PostgreSQL/PostgREST a `datosAnexoValidos` y al renderer. El fixture Edge usa `generado_en` terminado en `Z`; SQL devuelve un `timestamptz`. Sin el cuerpo de `fechaIso` ni esa prueba, su compatibilidad es una **hipótesis**, no un fallo demostrado.
- Los e2e interceptan la Edge: prueban la interacción del front, pero no integran autorización, selección del sellado, render y bitácora reales. Tampoco acreditan que el visor haya mostrado o impreso los bytes.
- El golden de 165 463 bytes implica **220 620 caracteres base64**, más el JSON. Prueba determinismo para ese fixture y versión desplegada; falta medir la respuesta en el caso máximo y verificar el límite de recepción del cliente.

REGRESSION RISKS:

- La reversa conserva la tabla, mientras el preflight impide reaplicar la misma migración si esa tabla existe. Hace falta un camino de recuperación hacia adelante probado.
- El pin transcrito del registrador comprueba objetos y ACL, pero no demuestra que la definición instalada de la función sea el cuerpo embebido. Confirmar esa comprobación en el registrador completo antes de usarlo como garantía de despliegue.

RECOMMENDED NEXT ACTIONS:

1. Corregir el bloqueo de vigencia, la forma del cronograma y la contradicción entre FK y trigger; añadir reproducciones de esos tres casos.
2. Definir qué acredita la bitácora, registrar resultado y hash según esa definición, y separar el error de cronograma de los errores de render.
3. Ejecutar el e2e Docker pendiente y una prueba integrada con la RPC real; completar los gates aplicables antes de publicar.

CONFIDENCE: **MEDIUM**. Los cuatro hallazgos P1 se apoyan directamente en el código transcrito; no tuve ejecución ni acceso a los cuerpos auxiliares omitidos.
