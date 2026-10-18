# Evaluación final del PRIMARY

Dos consultas por wrapper entregadas en total. Ambos dictámenes permanecen
**CHANGES_REQUESTED**; no se afirma un PASS del reviewer. La segunda revisión
no pidió cambios al SQL aprobado. El PRIMARY cerró sus verificaciones así:

- **P2 revisión de Gerencia, resuelto:** `inversionista_gestion_fn` devuelve
  `md5(to_jsonb(v_ce)::text)`; cuerpo completo en el preflight adjunto. Tres
  grupos (Qorilazo PEN, Prodelco PEN/USD) repitieron correcciones de contratos
  calendario y 360 con revisión obtenida por HTTP y token real de Gerencia.
  Coincidió con el hash persistido, se guardó una vez, se repitió sin duplicar
  y se rechazó una revisión anterior. Resultado total: 95 casos PASS.
- **P2 vista previa, hipótesis descartada:** `CorregirInversionCoopac` no usa
  `vencimientoCoopac` ni muestra fecha calculada cuando hay condiciones. Envía
  la revisión recibida y el plazo; el servidor calcula según la fila bloqueada.
  Dos pruebas de diálogo PEN/USD cambian un histórico de enero de 12 a 6 meses,
  comprueban la explicación, ausencia de fecha editable/calculada y el envío
  de la revisión del servidor. Solo históricos sin condiciones admiten fecha manual.
- **P2 CHECK productivo, resuelto en lectura:** 74 registros; 49 con condiciones;
  cero incompatibles con el predicado nuevo para `calendario`. Se adjunta el
  CHECK anterior. Repetir conteo y guardas justo antes de instalar: producción
  sigue operando y esta evidencia no garantiza datos futuros.
- **P3 dependientes, inventariados:** solo F3 obsoleto, el validador compartido
  y la corrección. F3 rechaza nuevas operaciones antes y después. El validador
  compartido sirve preparar/corregir/confirmar solicitudes nuevas. La corrección
  ya usa el helper con base de la fila. `pg_depend` no muestra dependientes del
  helper de tres argumentos, incluidos índices/columnas generadas.
- **P3 históricos sin condiciones:** conservan calendario también al agregar
  condiciones. Es la preservación de contratos anteriores ya documentada y
  aprobada; no se cambia el SQL para reinterpretar esos contratos.
- **P3 auditoría, sugerencia opcional no incorporada:** no se necesita para este
  cambio; el disparador de auditoría de filas conserva la nueva columna. No
  se modifica el payload específico ni el SQL exacto ya aprobado.
- **P3 esquemas PostgREST, límite de evidencia:** la consulta de overrides en
  `pg_db_role_setting` no devolvió filas en producción ni en rama. Eso no
  acredita la configuración efectiva completa del servicio. El banco pudo
  exponer `public,storage,graphql_public,crm` al configurarse. No se amplió
  ningún permiso de tablas/funciones; las sondas de acceso directo rechazaron
  todas las escrituras de convención. La rama se eliminó sin fusionarla.

La comprobación de Gerencia descubrió un error previo del cliente: solo
aceptaba PEN aunque el servidor devuelve USD para Prodelco. Se amplió el
parser a PEN/USD y la etiqueta de capital usa la moneda recibida. Las dos
pruebas nuevas recorren lectura, diálogo y envío; el servidor mantiene sus
restricciones de moneda por cooperativa. No cambia el SQL aprobado.

Advisors: seguridad 380→380; rendimiento 345→332. Cero hallazgos nuevos en
ambos; 13 avisos de índices sin uso desaparecieron tras ejecutar tráfico.
La comparación aplana `findings` y solo ignora `observed_at` y orden de claves.

No se hicieron más consultas para buscar un dictamen favorable. Los gates
integrales RLS, el gate de realidad y E2E completo de release siguen
pendientes antes de publicar. check:scripts y el preflight Edge sí pasaron en la copia final;
seed y RLS preflight se detuvieron por falta de SUPABASE_URL. Las pruebas de este expediente no los sustituyen.
