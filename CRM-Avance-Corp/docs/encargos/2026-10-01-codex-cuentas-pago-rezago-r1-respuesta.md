**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** Pediría exigir el aislamiento correcto y corregir el resultado del ensayo cuando faltan pruebas. La condición `ok` coincide con el bloqueo para una misma fotografía de datos. No encuentro una fuga nueva de los motivos mediante la puerta, pero sí un canal lateral previo y dependencias de concurrencia todavía sin demostrar.

**FINDINGS**

**P1 — La carga depende de READ COMMITTED, pero no lo exige.**

Evidencia: la migración comienza con `begin` y configura tiempos máximos; después del preflight adquiere `lock table crm.cuentas_bancarias in exclusive mode`. No fija ni comprueba `transaction_isolation`.

Contraejemplo bajo `REPEATABLE READ`:

1. El preflight establece la fotografía de la transacción; el cliente tiene una cuenta activa.
2. Otra sesión registra una segunda cuenta activa y confirma.
3. La carga adquiere el candado EXCLUSIVE.
4. Tanto el diagnóstico como el `SELECT ... INTO STRICT` siguen viendo solamente la primera cuenta.
5. Se crea el vínculo y las postcondiciones pasan sobre esa misma fotografía antigua.

El candado impide cambios posteriores, pero **no actualiza una fotografía ya adquirida**. Se puede elegir una cuenta cuando realmente existen dos, contrariando la decisión de negocio.

La reversa tiene una dependencia similar: esperar el contrato no garantiza ver después un sello confirmado durante la espera si la fotografía permanece fija.

**Condición no comprobada:** no afirmo que producción use `REPEATABLE READ`; su configuración no está transcrita. El contraejemplo exige ese aislamiento. Conviene fijar READ COMMITTED al iniciar cada transacción o rechazar otro aislamiento antes de proceder, incluyendo los derivados y el ensayo.

**P2 — El ensayo puede devolver verde sin ejecutar las comprobaciones esperadas.**

Evidencia en `ensayo-prod-sin-escribir.sql`, `$ensayo_fin$`:

- `v_todo boolean := true`.
- Cuando falta una cuota, asigna `v_bien := null`, pero no modifica `v_todo`.
- Si no encuentra contrato bloqueado, omite toda la prueba de identidad.
- Las consultas de perfiles pueden devolver cero filas; tampoco se exige que se prueben ambos papeles.
- La selección del contrato que «ya estaba bien» puede devolver cero filas sin afectar el resultado.

Así, `todo_como_se_esperaba = true` no demuestra que se probaron pagos e identidades.

Debe distinguir **PASS, FAIL y NOT RUN**, contabilizar la cobertura esperada y señalar los casos no aplicables. Una prueba requerida omitida no debe producir un verde global indistinguible de una ejecución completa.

**P2 — Persiste un oráculo de estado mediante los errores anteriores a RLS. Es previo a esta migración.**

Evidencia: `private.exigir_cuenta_pago_cronograma()` consulta el vínculo antes de decidir quién recibe detalle; sin vínculo válido emite `23514`. Con vínculo válido devuelve `NEW`, permitiendo llegar a la comprobación RLS.

Para un INSERT que alcance ese trigger, una identidad rechazada después por RLS puede distinguir:

- contrato bloqueado: `23514`;
- contrato con vínculo válido: rechazo posterior de autorización, normalmente `42501`.

Además, `private.proteger_cronograma_documental`, líneas 624–658, puede revelar antes estados de eliminación o congelación mediante `55000`.

El texto genérico oculta el motivo concreto, pero no elimina esos canales laterales. No exigiría resolver toda esta conducta previa dentro de esta migración; sí documentarla y limitar la afirmación de confidencialidad a lo realmente protegido.

**Riesgos y huecos de prueba**

- **Autorización y NULL.** Las condiciones `IS TRUE` / `IS FALSE` del código nuevo cierran correctamente ante NULL. La puerta no convierte NULL o un array vacío en un censo. `membresia_crm_revocada()` devuelve `EXISTS`, por lo que su implementación suministrada no produce NULL. Un rol API distinto de los habituales puede recibir detalle si su identidad satisface la tercera rama de gestor: esa rama no exige `v_rol = 'authenticated'`. Esto coincide con autorizar por perfil, pero debe ser una decisión consciente. Asimismo, la excepción de conexión directa confía en **cualquier** `session_user` distinto de `authenticator` sin rol declarado; no se aportó el inventario de logins para validar esa confianza.

- **Equivalencia.** Con la unicidad y los FK transcritos, ambos predicados exigen vínculo, mismo cliente y misma moneda; ambos aceptan cuentas inactivas. No encuentro divergencia lógica. Esto no garantiza respuestas idénticas entre consultas ejecutadas en momentos distintos: el diagnóstico no reserva una futura autorización de pago.

- **EXCLUSIVE y pagos en vuelo.** EXCLUSIVE permite lecturas ordinarias, pero bloquea el `ROW SHARE` requerido por `SELECT ... FOR KEY SHARE`. F5 inserta en `crm.cuotas_cuenta_pagada` —líneas 141–148—; **falta su DDL**. Si tiene FK hacia cuentas, los pagos también necesitan ese acceso para comprobarlo. Por tanto, «registrar un pago solo LEE cuentas» no demuestra compatibilidad. En el ensayo existe un posible ciclo concreto: mantiene EXCLUSIVE; un pago real retiene cuota/contrato y espera el FK; el ensayo intenta actualizar esa misma cuota y espera al pago. **Hipótesis condicionada al FK**, que requiere una prueba a dos sesiones. F3, en el fragmento aportado, toma primero la cuenta `FOR SHARE`, lo que sí respeta el orden esperado frente a la carga.

- **Postcondiciones y falsos rojos.** El candado sobre cuentas no congela todos los contratos del censo. Bajo READ COMMITTED, una eliminación concurrente de un contrato ajeno a los candidatos puede alterar los histogramas y cancelar una carga correcta. Es una cancelación conservadora, pero debe contemplarse operativamente. Los contadores agregados tampoco sustituyen comprobar las filas concretas afectadas.

- **Reversa.** La selección por marca, `fila_id` y `contrato_id` acota bien los borrados. Bajo READ COMMITTED, el candado del contrato permite esperar al pago y consultar después su sello. Sin embargo, comprobar hoy `tgenabled = 'O'` no demuestra que los sellos estuvieron siempre activos; tampoco verifica función, eventos y condiciones de esos triggers. Falta demostrar la concurrencia con pagos y productores de PDF. No identifico un borrado excesivo demostrado en el camino normal transcrito.

- **Huellas.** `CREATE OR REPLACE` no convierte `prosrc` en una representación canónica del SQL. Cambios de finales de línea, espacios, comentarios o caracteres recibidos pueden cambiar la huella aunque la lógica sea equivalente. Con el mismo texto almacenado y la misma codificación, no hay un motivo adicional para que `md5(prosrc)` cambie. Estos rechazos serían conservadores; conviene distribuir exactamente el artefacto ensayado.

- **Ensayo y persistencia.** El rollback revierte las filas y descarta `NOTIFY`. Los claims configurados con `true` son locales a la transacción y no contaminan otra sesión del pooler; el ajuste con `false` del resultado también se deshace si esa transacción aborta. **No equivale a ausencia de todo efecto:** pueden persistir consumos de secuencias, logs, estadísticas y WAL, además de existir bloqueos mientras corre. No se aportó el conjunto completo de triggers para descartar llamadas externas. El despacho habitual de `pg_net` ocurre después del commit, pero no debe extrapolarse esa propiedad a cualquier mecanismo HTTP.

- **Mensaje y HTML.** `format('%s', ct.numero_contrato)` incorpora el número sin escape HTML; también existe el fallback de moneda textual. La respuesta debe tratarse como texto no confiable y renderizarse mediante un mecanismo que escape, como `textContent`. **No hay XSS demostrado aquí:** faltan el renderizador y las restricciones del número. La procedencia del mensaje desde el servidor no lo convierte en HTML seguro.

**NEXT ACTIONS**

1. Exigir READ COMMITTED y probar el contraejemplo de incorporación concurrente de una segunda cuenta.
2. Corregir la cobertura y los estados del ensayo.
3. Aportar el DDL del sello y ejecutar pruebas a dos sesiones de pago contra carga, ensayo y reversa; añadir PDF concurrente.
4. Registrar el canal lateral previo y trasladar al encargo del portal el requisito de renderizar el mensaje como texto. Mantener la matriz HTTP como **NOT RUN** hasta ejecutarla.

**CONFIDENCE:** Alta en la equivalencia estática, el falso verde y el contraejemplo condicionado al aislamiento; media en concurrencia y reversa por las piezas ausentes. Verificación propia: **NOT RUN**, revisión exclusivamente textual.
