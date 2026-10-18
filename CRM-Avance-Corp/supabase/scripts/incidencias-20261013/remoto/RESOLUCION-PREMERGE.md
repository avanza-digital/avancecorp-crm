# Evaluación del PRIMARY

La segunda revisión se pidió por la reconstrucción del banco y la preparación
del merge, nueva evidencia respecto de la revisión inicial. Dictamen original:
`CHANGES_REQUESTED`; no encontró defectos nuevos en los dos SQL de producto.

- **P1, contenido Git:** se rechaza su aplicación al merge de Supabase. La
  herramienta `merge_branch` transporta migraciones del ledger y Edge Functions;
  no fusiona una rama Git ni publica frontend. El PR Git conserva su revisión
  requerida. Se verificó el diff contra `avancecorp/main`: solo el incidente,
  sin cambios de Edge/configuración. No usar `origin/main`: es otro proyecto.
- **P2, atribución de evidencia:** se añade al premerge el commit de producto
  probado `bd59d35d878ed97df71bb45f83db117c71425222`, SHA-256 exactos de ambos SQL,
  comprobación de que SQL/transporte/tests no cambiaron, las huellas y versiones
  exactas del ledger ensayado, antigüedad máxima de los resultados y SHA-256 de
  cada informe. Esta vinculación es una comprobación posterior de los artefactos
  efectivamente usados; no se afirma que los runners antiguos la registraran al
  iniciar. Los commits posteriores de documentación no cambian el código probado.
- **P2, F7 fresco:** aceptado. Las filas F7 forman parte de la captura productiva
  de menos de 60 segundos y deben coincidir con la referencia original; el banco
  solo puede diferir en huella/nota de la función reparada.
- **P2, versiones:** el repositorio ya conserva archivos inmutables con mapeo a
  versiones asignadas por MCP. Se documentan las versiones del banco y se leerá
  el registro efectivo de producción tras el merge. No se usa `db push`, no se
  renombra una migración comprometida ni se aplica directamente al padre.
- **P2, capturas privadas:** el directorio fijo es
  `/private/tmp/incidencias-banco-f7`, fuera del checkout. Se añadió una aserción
  explícita de esa separación; se revisa el contenido de Git antes de commitear.
- **P3, normalizaciones:** aceptado. Se exigen exactamente los tres nombres de
  tabla/CHECK observados; no se acepta una lista ampliada silenciosamente.
- **P3, frescura del merge:** aceptado. Se revalida la ventana al terminar el
  premerge y se invoca el merge inmediatamente, comprobando que su PASS tenga
  menos de 60 segundos. Si expira, se recaptura y se vuelve a verificar.
- **P3, vigía F7:** ya estaba explícito en el informe principal, sección
  Aplicación y reversa, punto 2. Se mantiene como postflight obligatorio.

No se repite la consulta para obtener un dictamen favorable. El PRIMARY conserva
la responsabilidad de ejecutar el gate real y registrar PASS/FAIL por separado.
