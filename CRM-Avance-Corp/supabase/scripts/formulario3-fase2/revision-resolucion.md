# Decisiones tras revisión de Claude · fase 2

Una consulta mediante `scripts/claude-review`, sin herramientas ni escrituras.
Salida válida y exit 0: `CHANGES_REQUESTED`, confianza MEDIA; sin P0/P1 ni fuga
de permisos confirmada. La salida literal se conserva en `revision-claude.txt`.
Codex es PRIMARY y ejecuta la corrección y las verificaciones siguientes.

1. **Payloads humanos de escritura — hipótesis no reproducida.** El alta del
   store construye los campos explícitamente (`store.tsx`, `insertarLead`); la
   ficha también (`lead-drawer.tsx`, `guardar`). Ninguno reutiliza COLUMNAS_LEAD,
   que solo aparece en SELECT. La edición del store reenvía el parche recibido,
   no el Lead leído. Se reforzaron pruebas de ficha y store con un lead que sí
   tiene campaña: el payload de edición no incluye la columna y la etiqueta
   permanece. El alta tampoco la envía. Los tests HTTP existentes de ambos
   caminos de documento/alta/edición verifican los cuerpos exactos. La matriz
   real comprueba UPDATE de nota permitido y campaña conservada; UPDATE de
   campaña, denegado. No se cambió la lógica de escritura del producto.
2. **Llamadores no registrados en pg_depend — mejora aceptada.** La búsqueda
   de `prosrc` en producción devuelve las dos puertas, `resumen_cartera_fn` y
   `cierres_estado_fn`. Solo resumen llama a la cartera, por argumento nominal
   `p_limite=>1`; cierres la menciona en comentarios. Se anclaron sus cuerpos en
   el preflight, se acotó pg_depend a pg_proc y se amplió la comparación del
   envoltorio a toda su respuesta frente a la consulta anterior.
3. **Contraste — hipótesis descartada con el tema real.** `--accent` es
   `#2563eb` (index.css), no el fondo claro de otros temas. Badge outline lo usa
   como texto; los ratios son 5,169 sobre blanco, 4,861 sobre background y 4,600
   sobre muted. El proyecto usa tema claro. Cambiarlo a accent-foreground
   produciría texto blanco. Se conserva el azul y se registra `contraste.json`.
4. **Comentarios del catálogo — defecto confirmado y corregido.** Ambas
   funciones tenían comentarios. La migración ahora los captura y restaura
   dentro de la transacción, y comprueba su igualdad; si aparecen security
   labels nuevas, aborta para revisarlas. Aplicación de la versión final PASS
   en un clon nuevo. La huella del wrapper también se releyó en producción y
   coincide con `4a896597486e8b23788a2b2497f16309`.
5. **Pruebas adicionales — aceptadas.** Se verifica anon sin EXECUTE del lector
   anterior, respuesta completa del wrapper y la combinación de campaña con
   origen/procedencia al forzar la ruta integrada. Los locales y producción
   usan en_US.UTF-8, proveedor ICU (`i`). 43 SQL y 262 pruebas enfocadas PASS;
   typecheck PASS. La repetición final E2E terminó 9/9 PASS sin reintentos, tras
   corregir un selector de diálogo y separar la ejecución del check completo.
6. **Producto — decisiones ya autorizadas.** El usuario pidió persistencia al
   recargar y conservar campaña de origen en contactos existentes. Se mantiene
   selección por pestaña/cuenta/modo, con filtro visible y Limpiar filtros.
   Un reingreso no reclasifica la campaña del lead. No se vuelve a pedir esa
   decisión ni se transforma esta fase en historial multicanal.

La revisión del PRIMARY queda cerrada para esta entrega local. Auth/HTTP con la
base real y ensayo remoto de la migración final corresponden a fase 3. El gate
general `gate:realidad` quedó NOT RUN por credenciales ausentes; la inspección
SQL de producción confirmó columna ausente y cartera sin cambios. No se
publicó, no se importaron contactos ni se activó n8n.
