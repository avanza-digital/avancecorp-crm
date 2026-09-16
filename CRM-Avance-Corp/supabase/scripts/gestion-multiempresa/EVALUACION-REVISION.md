# Evaluación de revisiones — Codex PRIMARY

Nivel 3. Dos revisiones mediante `scripts/claude-review`, SECONDARY_REVIEWER sin
herramientas/escritura. Ambos dictámenes originales fueron CHANGES_REQUESTED,
conservados en [primera](REVISION-1.md) y [segunda](REVISION-2.md). No se pidió una
tercera confirmación. Las correcciones y pruebas siguientes son evaluación del
PRIMARY; no se atribuye un PASS posterior a Claude.

| Observación | Decisión y evidencia |
| --- | --- |
| Lectura con búsqueda por persona (P1 primera) | Corregido con CTE `contactos` materializado, unido una vez a identidades. `test-sql.mjs` valida IDs visibles y EXPLAIN con 600 contactos. |
| Auditoría COOPAC incompleta (P2 primera) | La gestión neutral incluye importes/referencia/nota antes y después, además de condiciones. HTTP verifica valores originales. |
| Permisos Avance inconsistentes | Se usa `es_gestor_cartera`, revocación y lector PDF. Se mantiene `puede_registrar_ventas` porque lo exige `actualizar_contrato_con_cuenta` para todos los roles. |
| Posible exposición Directorio | Proyección explícita y prueba de igualdad con columnas/redacción de `contratos_cartera`. Domicilio y revisión de contacto son NULL para Directorio. |
| Casts y conflictos ambiguos | Casts inválidos se normalizan a 22023; PT409 identifica versiones antiguas/carreras, P0409 fuente perdida y 42501 ámbito perdido. Pruebas HTTP y formularios. |
| Adaptación altera llamada directa COOPAC (P2 segunda) | Aceptado: el salto de actividad sobre lead archivado requiere contexto local `crm.gestion_neutral`, puesto y restaurado solo por el wrapper nuevo. Test directo conserva rechazo y fotografía exacta; el flujo neutral guarda su gestión. |
| Falta evidencia del lock (P2 segunda, hipótesis) | El cuerpo existente `private.postventa_persona` calcula canónica, bloquea documentos, hace `select ... where id=v_id for update` y revalida canónica/documentos. No se duplica el lock. Carrera HTTP confirma un ganador y PT409; fusión comprueba fila canónica revision=42, alias=41, identidad del recibo y de la gestión. |
| Posible falso negativo vendedor (P3 segunda, hipótesis) | El flujo efectivo usa `actualizar_contrato_con_cuenta_pdf_v3`, sin contexto de producto. `public.actualizar_contrato` requiere analista o gestor/gerencia en esa ruta. Vendedor comercial sin rol analista recibe capacidad false y rechazo 42501 del escritor; analista propio dentro/fuera 5 h coincide. No se amplían permisos. |
| Revisión deriva de domicilio oculto | Aceptado: se devuelve NULL a Directorio y se comprueba por HTTP. |
| Omisión de vencimiento histórico | Aceptado: sin condiciones, omitir `vence_en` conserva la fecha; NULL explícito mantiene su semántica. Test transaccional sobre histórico. |
| Reintento descarga cartera completa | Detectado por PRIMARY: detalle con contrato concreto solo reintenta cuotas/titulares. Test unitario comprueba que no refetch del listado. |

`crm.cierres_externos` tiene `trg_audit_cierres_externos`, AFTER INSERT/DELETE/UPDATE,
que llama `private.log_audit_sin_secretos('documento')`. La adaptación conserva ese
trigger; no se usa como sustituto de la gestión neutral de negocio.

El caso sugerido «operaciones sin membresía» no es un rol operativo CRM admitido
por el lector F5. No se infiere acceso desde un rol portal aislado. Las pruebas
acreditan los roles de la matriz del módulo; no se inventa una nueva capacidad.

Pendientes de entorno: ensayo/advisors remotos y comprobación posterior a la
publicación. Las conformidades G7/G8 anteriores conservan su estado propio.
