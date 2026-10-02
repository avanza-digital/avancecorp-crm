**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

En `READ COMMITTED`, la operación mostrada protege correctamente cliente, moneda, vigencia, estado y unicidad del vínculo. La compuerta rechaza `NULL`; los permisos nuevos eliminan el `EXECUTE` público y lo conceden únicamente a `authenticated`, sujeto a la autorización interna.

Quedan problemas de aislamiento, garantías incompletas en reversa/reapertura y verificaciones que pueden dar un resultado favorable sin demostrar el efecto esperado. Esta revisión es exclusivamente estática: no ejecuté pruebas ni consulté recursos externos.

**FINDINGS**

1. **P1 — El núcleo admite una fotografía anterior a una revocación y pierde idempotencia en `REPEATABLE READ`.**

   Evidencia: `20261002005004_crm_asignar_cuenta_pago.sql`, función `private.asignar_cuenta_pago_contrato_autorizado`. Ejecuta:

   ```sql
   if not coalesce(private.admin_banca_vigente(v_actor), false) then
   ```

   y posteriormente el candado consultivo y la lectura de la constancia, sin exigir aislamiento.

   Hay dos secuencias distintas:

   - Una transacción fija su fotografía; otra registra la revocación en `crm.equipo` y confirma; la primera llama al núcleo. La compuerta todavía puede ver al administrador vigente. Cuenta y contrato pueden permanecer intactos, por lo que sus candados no provocan necesariamente un error de serialización.
   - Dos solicitudes idénticas esperan el mismo candado consultivo. En `REPEATABLE READ`, quien espera conserva una fotografía sin la constancia del ganador. Intenta insertar el vínculo y recibe «ya tiene cuenta», en lugar del resultado idempotente.

   El candado consultivo ordena ejecuciones; no actualiza la fotografía. Debe rechazarse el aislamiento incompatible en el núcleo, o demostrarse otra solución que conserve ambas garantías. Son secuencias deducidas del código, pendientes de reproducción.

2. **P1, riesgo previo — F4 puede retirar la cuenta recién asignada si F4 corre en `REPEATABLE READ`.**

   Evidencia: F4, `20260927012948_crm_retirar_cuenta_cliente.sql:178`, bloquea la cuenta `FOR UPDATE`; en `:203` consulta los contratos abiertos. Asignar únicamente bloquea la cuenta `FOR SHARE`, sin modificarla.

   Intercalado posible, si F4 admite ese aislamiento:

   1. Asignar mantiene el candado compartido sobre la cuenta.
   2. F4 establece una fotografía anterior al vínculo y espera el candado exclusivo.
   3. Asignar inserta vínculo y constancia y confirma.
   4. F4 obtiene la cuenta, cuyo contenido no cambió. Su fotografía todavía no contiene el vínculo; supera la comprobación y desactiva la cuenta.

   Es una anomalía previa de F4 que esta ruta también hereda. **Una guarda únicamente en Asignar no resuelve este caso.** Debe acreditarse que F4 exige `READ COMMITTED`, o corregirse esa condición. No afirmo que el canal HTTP actual permita seleccionar otro aislamiento: esa configuración no está transcrita.

3. **P2 — La reversa no cumple su garantía de cierre ante cualquier alteración de las piezas.**

   Evidencia: `supabase/scripts/cuentas-pago-asignar/reversa.sql`:

   - La precondición exige que existan los cuatro objetos y lanza una excepción antes de revocar permisos. Si falta el candado auxiliar pero sobreviven puerta y núcleo, ambos conservan sus permisos.
   - `v_intactas` comprueba únicamente tres cuerpos `prosrc`. Cambios en la tabla, los triggers o los atributos de las funciones no impiden declarar intacto el conjunto y entrar en la rama de retirada.
   - El cierre revoca permisos a cuatro destinatarios conocidos y comprueba únicamente `authenticated`. Un permiso añadido a otro rol independiente puede sobrevivir mientras el resultado anuncia `PUERTA_CERRADA`.

   Son escenarios de alteración del esquema, no hechos observados en el banco. Precisamente corresponden al supuesto que el guion promete manejar.

   El cierre de las funciones supervivientes debe poder realizarse independientemente de las condiciones necesarias para retirar objetos. La comprobación de cierre debe considerar todos los permisos efectivos relevantes, salvo el dueño expresamente admitido.

4. **P2 — La reapertura no verifica las dependencias que sostienen autorización e inmutabilidad.**

   Evidencia: `reabrir-puerta.sql` comprueba dos `md5(prosrc)` y la existencia de la tabla. No verifica la compuerta `private.admin_banca_vigente`, los candados de la constancia ni su bitácora.

   Por ejemplo, una modificación de la compuerta que amplíe los roles permitidos deja intactos ambos cuerpos comprobados. La reapertura la acepta y devuelve `EXECUTE` a `authenticated`. También acepta una constancia con sus triggers deshabilitados.

   La instalación sí identifica mediante huella la compuerta compartida. La reapertura debe recuperar esa comprobación y verificar las protecciones esenciales de la constancia, además de los atributos de seguridad de las funciones. Actualmente, «las piezas vivas son las de la migración» es una afirmación más fuerte que lo comprobado.

5. **P2 — Se traducen otras violaciones de unicidad del vínculo.**

   Evidencia: el manejador del núcleo obtiene únicamente:

   ```sql
   get stacked diagnostics v_esquema = schema_name, v_tabla = table_name;
   ```

   y convierte cualquier `23505` de `crm.contrato_cuentas_pago` en «ya tiene cuenta».

   Esa tabla tiene, como mínimo, dos unicidades diferentes: `id PRIMARY KEY` y `contrato_id UNIQUE` —antecedente `20260803221622…:174` y `:175`. Una colisión del identificador también se traduciría incorrectamente. Su probabilidad normal es mínima, pero contradice expresamente la decisión 3 y puede ocultar un defecto del generador o de otro índice.

   Debe identificarse también la restricción o índice infractor y traducir exclusivamente la unicidad por contrato.

6. **P2 — El ensayo puede declarar «pagada» una cuota que no cambió.**

   Evidencia: `ensayo-prod-sin-escribir.sql`, bloque `$ensayo_fin$`:

   ```sql
   update public.cronograma_pagos ... where id = v_cuota;
   v_resultado := 'pagada';
   ```

   Para los casos `ok`, después basta con que `v_resultado = 'pagada'`. No se comprueba la fila afectada ni su estado resultante.

   Un `UPDATE` que afecte cero filas termina sin excepción. También un trigger puede devolver una fila conservando el estado anterior. En ambos casos esta comprobación considera exitoso el pago.

   La clasificación `FALLA / INCOMPLETO / PASA` está bien ordenada y mejora la cobertura ausente, pero debe apoyarse en el efecto real: fila modificada, estado, fecha, importe y sello esperado cuando corresponda. Un mutante que suprima únicamente un pago permitido debe producir `FALLA`.

7. **P3 — La validación del motivo en pantalla no reproduce la del servidor.**

   Evidencia: `js/admin/asignar-cuenta-core.js`, `validarAsignacion`, utiliza `texto.length` después de `trim()`. El servidor exige cinco caracteres después de retirar **todos** los espacios de su clase.

   Ejemplo reproducible: `a b c` pasa en pantalla y falla en SQL. También difieren el tratamiento de `U+200B` y el conteo UTF-16 frente a caracteres de PostgreSQL.

   No permite eludir la validación ni duplicar una asignación. Sí provoca rechazos evitables y contradice el comentario «misma regla». Conviene compartir explícitamente la definición y probar esos límites.

**RIESGOS Y HUECOS DE PRUEBA**

- **Marcadores de éxito reutilizables.** Las tres piezas nuevas guardan resultados mediante `set_config(..., false)`. El valor sobrevive en la sesión tras una ejecución correcta. Si una ejecución posterior falla y el ejecutor continúa hasta el `SELECT` final, puede devolver el resultado anterior. La posibilidad de ese falso verde depende del ejecutor, no transcrito. Probar éxito seguido de fallo en la misma conexión; detenerse ante el primer error y vincular el resultado a la ejecución actual.

- **Concurrencia en `READ COMMITTED`.** Los candados mostrados sí bloquean un retiro o una modificación del contrato entre validación e inserción. No encuentro un ciclo con el pago descrito: este toma primero el contrato y únicamente `AccessShareLock` sobre cuentas, compatible con el `EXCLUSIVE` de la carga. Tampoco aparece una inversión nueva frente a F3. No certificaría todos los caminos del alta sin su cuerpo completo.

- **Idempotencia entre actores.** Otro administrador vigente puede repetir exactamente la solicitud y recibir `ya_aplicada`; no cambia la autoría original. Esto concuerda con la comparación global especificada. En `READ COMMITTED`, reutilizarla para otro contrato se rechaza.

- **Portal.** El diff conserva las condiciones de bloqueo de pago y exportación. Los textos nuevos visibles pasan por escape o `textContent`; el doble envío ordinario queda protegido por `enviando`. La lectura directa de `cliente_id` sigue sometida a permisos y RLS: no constituye por sí misma un bypass.

- **Ventanas y respuestas tardías.** El cierre normal está bloqueado durante el envío y la carga de cuentas verifica la identidad de la ventana. Sin embargo, `abrirModalAsignar` puede reemplazar `ASIGNACION`, y la continuación del envío no comprueba que siga siendo la misma. Debe probarse una segunda apertura mientras el primer envío está pendiente, incluida navegación por teclado; su accesibilidad real es una hipótesis pendiente de navegador. Tras un error de transporte, cerrar tampoco cancela una transacción todavía en curso: una recarga inmediata puede preceder a su confirmación.

- **Sesión caducada.** El servidor debe denegar la operación, pero los errores de autenticación no contemplados terminan como mensaje de conexión. Falta verificar recuperación de sesión con Supabase real.

- **Seguimiento anterior.** La guarda explícita de `READ COMMITTED` es correcta. No reabro la objeción del FK del sello ni la lista fija de `session_user`: la evidencia aportada no sostiene esas objeciones.

**NEXT ACTIONS**

1. Resolver los hallazgos del núcleo, reversa/reapertura y diagnóstico de unicidad; reforzar las comprobaciones del ensayo.
2. Ejecutar intercalados con barreras: asignación simultánea, solicitud repetida, revocación, F4 en ambos órdenes y aislamientos, pago, F3 y carga automática. Comprobar vínculo, constancia, autoría y bitácora.
3. Añadir mutantes de los guiones operativos: dependencia alterada, pieza ausente, trigger deshabilitado, permiso adicional y marcador de éxito previo.
4. Completar banco, matriz HTTP y navegador real. Verificar también que asignar conserva intactos los sellos previos y que el pago posterior crea el sello correcto.

**Estado de verificación:** los PASS del portal y del preflight son resultados comunicados por el PRIMARY. El banco nuevo de Asignar, la matriz HTTP completa y la repetición completa del seguimiento siguen **NOT RUN / EN CURSO** según el encargo; no los considero aprobados.

**CONFIDENCE**

Alta en los defectos estáticos señalados. Media en la exposición operativa de los escenarios de aislamiento y reapertura: faltan ejecución reproducible y configuración efectiva del canal.
