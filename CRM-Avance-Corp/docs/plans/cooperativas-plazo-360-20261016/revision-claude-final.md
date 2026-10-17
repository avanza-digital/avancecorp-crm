VERDICT:
CHANGES_REQUESTED

SUMMARY:
El SQL aprobado parece correcto y bien acotado. El orden de DDL es seguro, el CHECK persiste la convención y la corrección de Gerencia lee `base_plazo` de la fila bloqueada. El helper nuevo queda sin EXECUTE para PUBLIC/anon/authenticated, y `CREATE OR REPLACE` conserva owner y ACL de las funciones reemplazadas. La matriz HTTP de 92 casos cubre bien roles, alcance, idempotencia, revisión obsoleta y borradores previos. No pido cambios al SQL. Pido tres verificaciones concretas antes de publicar, porque la evidencia no cubre esas rutas: la revisión optimista tal como la obtiene la app, la vista previa del formulario de corrección para filas `calendario` y la validación del nuevo CHECK contra las filas reales de producción.

FINDINGS:

[P2] La revisión optimista de la corrección se obtiene por SQL de administración, no por la ruta real de la app
File: script de pruebas API, función `correccion()`; SQL `crm.inversionista_corregir_coopac_fn`
Lines: `const revision=sql(\`select md5(to_jsonb(c)::text) ...\`)`; en SQL: `if p_revision is distinct from md5(to_jsonb(v_ce)::text)`
Problem: Tras la migración, `to_jsonb(v_ce)` incluye la clave nueva `base_plazo`. El hash cambia para todas las filas. La prueba calcula la revisión directamente con el usuario admin, así que no demuestra que la RPC o lectura que usa la PWA de Gerencia produzca el mismo hash.
Evidence: El hash del servidor se calcula sobre la fila completa. La prueba lo obtiene con `sql(...)` y no con la RPC de lectura autenticada. Las 6996 pruebas unitarias y las 29 de navegador usan HTTP simulado, según el propio dossier.
Impact: Si la revisión que entrega la app sale de una proyección o de un `jsonb_build_object` de columnas seleccionadas, o se calcula en el cliente, toda corrección COOPAC fallaría siempre con PT409 tras la migración. Si sale de `md5(to_jsonb(c))` sobre la fila completa, no hay problema. La evidencia no permite distinguir los dos casos.
Recommendation: Identificar la RPC que entrega `p_revision` a la PWA, mostrar su cuerpo, y en la rama obtener la revisión vía HTTP con el token de Gerencia antes de llamar a `inversionista_corregir_coopac_fn`. Las correcciones abiertas antes del despliegue darán PT409 una sola vez; eso es benigno, pero conviene incluirlo en la nota operativa.

[P2] La vista previa del vencimiento al corregir no conoce la convención de la fila (hipótesis)
File: helper de app `vencimientoCoopac`/`condicionesCoopac`
Lines: `vencimiento.setUTCDate(vencimiento.getUTCDate() + meses * 30)`
Problem: El único helper de cliente aportado aplica siempre 30 días por mes y no recibe `base_plazo`. En el servidor, la corrección de una fila `calendario` calcula meses calendario e ignora `p_datos.vence_en` en esa rama.
Evidence: La rama `else` usa `coopac_validar_condiciones_base(..., v_ce.base_plazo)`. El helper de app no tiene parámetro de base. No se aportó el componente de corrección de Gerencia ni la lectura que expone `base_plazo` al cliente.
Impact: Si el formulario de corrección usa este helper para mostrar el vencimiento, Gerencia vería por ejemplo 2027-04-14 y el servidor guardaría 2027-04-16 en un contrato histórico. No se corrompe nada, porque el servidor manda, pero el dato confirmado difiere del mostrado en una operación financiera revisada.
Recommendation: Aportar el componente de corrección. Si previsualiza el vencimiento, exponer `base_plazo` en la lectura y calcular por convención, o mostrar el vencimiento devuelto por el servidor. Añadir una prueba unitaria con una fila `calendario` de 6 meses.

[P2] El nuevo CHECK no se validó contra las filas reales de producción
File: SQL aprobado, `add constraint cierres_coopac_condiciones_completas`
Problem: La rama se reconstruyó desde un esquema vacío, sin datos de clientes. `ADD CONSTRAINT ... CHECK` valida todas las filas existentes con `base_plazo='calendario'`. Solo el hash del cuerpo anterior asegura la equivalencia, y ese cuerpo no se adjuntó.
Evidence: "branch was rebuilt from an empty schema export, without customer data"; el guard de deriva compara `md5` del CHECK anterior, pero ese cuerpo no está en el dossier.
Impact: La transacción haría rollback de forma segura, pero fallaría dentro de la ventana coordinada de instalación, con el frontend ya preparado para seguir.
Recommendation: Antes de la ventana, ejecutar en producción un preflight de solo lectura: `select count(*) from crm.cierres_externos where plazo_meses is not null and not (<predicado nuevo con 'calendario'>)`, que debe dar 0. Adjuntar también el cuerpo del CHECK anterior para confirmar la equivalencia.

[P3] Inventario de dependientes de `private.coopac_validar_condiciones`
Problem: El helper ahora fija `dias_360`. Cualquier otro llamador que recalcule `vence_en` de una fila existente fallaría contra el CHECK en filas `calendario`. Es un fallo ruidoso, no corrupción. Si el helper IMMUTABLE se usara en un índice de expresión o en una columna generada, esas entradas quedarían obsoletas.
Evidence: La comparación de catálogo prueba que no cambió ninguna otra definición, pero no lista llamadores ni `pg_depend`.
Recommendation: Adjuntar la lista de funciones cuyo cuerpo menciona `coopac_validar_condiciones` y una consulta a `pg_depend`/índices. Confirmar que solo preparar, confirmar, corregir solicitud y F3 bloqueado lo usan.

[P3] Filas históricas sin condiciones a las que Gerencia añade plazo
Problem: Una fila previa sin plazo ni tasa tiene `base_plazo='calendario'`. Si Gerencia le agrega condiciones después, se calcularán en meses calendario, aunque la condición se fije ahora. Las filas sin plazo creadas tras la migración usarían 360.
Evidence: `add column ... default 'calendario'` y la rama `else` con `v_ce.base_plazo`.
Recommendation: Es una decisión de negocio. Confirmarla con el usuario o dejarla documentada; el comentario de columna ya lo sugiere.

[P3] La auditoría no registra la convención
File: `inversionista_corregir_coopac_fn`, `condiciones_antes`/`condiciones_despues`
Recommendation: Añadir `base_plazo` a ambos objetos para que la auditoría explique por qué un vencimiento es de 180 días o de 6 meses. Es opcional y no bloquea.

[P3] Exposición de esquemas en la rama
Evidence: `antes()` puede fijar `pgrst.db_schemas='public,storage,graphql_public,crm'`.
Recommendation: Confirmar que coincide con producción. Exponer `storage` vía PostgREST solo amplía la superficie y no relaja lo probado, pero la paridad debe constar.

TEST GAPS:
- La revisión de corrección no se obtiene por la RPC real de lectura.
- No hay prueba de UI o unidad de la vista previa de corrección con `base_plazo='calendario'`.
- El CHECK no se validó sobre datos de forma productiva (preflight).
- No hay casos HTTP con fecha de inicio a fin de mes; solo una aserción SQL con `2026-01-31`. Es bajo riesgo, porque la aritmética de días es lineal.

ARCHITECTURE RISKS:
- Hay dos fuentes de cálculo de vencimiento: cliente con 360 fijo, servidor por convención. El servidor es la autoridad, pero el cliente debe conocer la convención donde muestra fechas de filas existentes.

SECURITY RISKS:
- No encontré ninguno nuevo. El helper es privado con EXECUTE revocado, `search_path=''`, y el DEFINER y owner se conservan por `CREATE OR REPLACE`. INSERT y PATCH directos de `base_plazo` dan 42501, y la clave enviada por el cliente da 22023. El delta de advisors de seguridad es 380→380, sin avisos nuevos.

REGRESSION RISKS:
- PT409 en correcciones abiertas durante el despliegue: benigno.
- Sesiones PWA antiguas rechazadas con 22023 hasta actualizar: limitación operativa ya declarada.
- Posible PT409 permanente en correcciones si la revisión de la app no es `md5(to_jsonb(fila))` (P2 arriba).

RECOMMENDED NEXT ACTIONS:
1. Adjuntar la RPC de lectura que produce `p_revision` y repetir `correccion()` obteniéndola por HTTP con Gerencia.
2. Adjuntar el componente de corrección y, si previsualiza el vencimiento, hacerlo depender de `base_plazo`, con una prueba unitaria.
3. Ejecutar en producción el preflight de solo lectura del nuevo CHECK (0 filas) y adjuntar el cuerpo del CHECK anterior. Repetir la comparación de hashes justo antes de aplicar.
4. Adjuntar el inventario de dependientes de `coopac_validar_condiciones`.
5. Borrar la rama de Supabase y dejar constancia, como exige la aprobación.

CONFIDENCE:
MEDIUM. Alta sobre el SQL y la matriz de permisos aportados; media porque no se adjuntó la ruta de revisión ni el formulario de corrección del cliente.
