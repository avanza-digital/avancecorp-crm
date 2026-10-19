**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

La v2 resuelve las objeciones sobre la definición temporal. No encuentro una clasificación incorrecta demostrada con la evidencia aportada, ni exigiría calcular por conjunto antes de instalar. Solicito una protección pequeña en la reversión y completar la evidencia del lector con corte existente.

**FINDINGS**

**[P2] La reversión sobrescribe el sello sin comprobar su consistencia inicial.**

Archivo: [revertir-20261019170214-citas-es-cliente.sql:48](/Users/usuario/dev/avancecorp-crm-proyeccion-citas/supabase/scripts/revertir-20261019170214-citas-es-cliente.sql:48).

- **Evidencia:** se recalcula el sello en las líneas 48–50; su primera comprobación explícita aparece después, en las líneas 56–59. Falta la comprobación inicial que sí tiene la instalación.
- **Problema:** el postflight demuestra que el sello recién escrito corresponde al ledger resultante, pero no que el estado recibido estuviera autorizado y fuera consistente. La foto del censo no sustituye esa comprobación.
- **Impacto:** puede desaparecer la señal de una modificación previa del ledger que necesitaba conciliación. No afirmo que ese estado exista actualmente.
- **Corrección:** comprobar el sello inmediatamente después del `LOCK`, antes de modificar los lectores. Ensayar que un sello inicialmente inconsistente provoca rechazo sin cambios.

**RISKS / TEST GAPS**

1. **Clasificación de negocio.** Acepto «anterior y vigente hoy», incluido el tratamiento especial de `perfil_id`. Queda una hipótesis concreta: si un lead apunta actualmente a B pero conserva un enlace `inversionista_leads` abierto hacia A, con canónicas distintas, la auxiliar combina ambas personas. Una conversión de A podría marcar como cliente una cita de B. Que `hasta` esté siempre nulo no demuestra que esos enlaces sean inequívocos. No lo considero un fallo observado: conviene descartar leads con más de una canónica entre ambos orígenes.

2. **Diferencias entre banco y producción.** Los hashes y comprobaciones aportados dan buena cobertura. Los tres `ALTER OWNER` fallidos necesitan identificación: igualdad de `prosrc` no acredita igualdad de ejecución bajo `SECURITY DEFINER` y RLS. Si afectan a objetos ajenos al recorrido, no son impedimento; si afectan a una dependencia ejecutada, hay que contrastar sus atributos.

   Existe además una ventana condicional entre el preflight y la lectura de `pg_get_functiondef` del parche: otro DDL podría cambiar un lector conservando el ancla y las cadenas comprobadas. El bloqueo del ledger no bloquea por sí solo toda modificación de funciones. Con migraciones serializadas queda cubierta operativamente; comprobar también los hashes finales esperados reforzaría la garantía.

3. **Coste.** **Aceptaría el coste mensual medido.** Medio segundo para unas 600 citas, con refresco cada 60 segundos, no justifica por sí solo exigir una reescritura. La extrapolación a 10 000 citas es aproximadamente **7–8 segundos sólo en la auxiliar**; es una estimación, no una medición del lector completo. Mediría el mayor rango utilizado y su margen frente al timeout efectivo. No extrapolaría la aceptación mensual a cualquier carga concurrente.

4. **Reversión después de otra migración.** Si cambia el cuerpo de cualquiera de los lectores, el MD5 posterior a retirar la clave rechazará la reversión. La transacción también deshará la modificación del primer lector si falla el segundo: no queda una reversión parcial ni se alcanzan las actualizaciones de huellas.

   Si otras migraciones legítimas modifican declaraciones ajenas, el sello recalculado puede diferir de `0262227b…`; eso es correcto. No debe restaurarse a la fuerza el sello histórico. El hallazgo anterior se refiere a aceptar un **sello de entrada inconsistente**.

5. **Prueba funcional pendiente.** El corte inexistente no acredita el comportamiento con un corte existente. Falta ejecutar la puerta pública v2 con un corte válido seleccionado, verificando las marcas esperadas y las claves anteriores. Sin el cuerpo completo del lector no puedo determinar si el ensayo aportado recorrió el código parcheado o una ruta alternativa.

**NEXT ACTIONS**

Para aprobar pediría:

- Añadir y probar el rechazo de la reversión ante un sello inicial inconsistente.
- Acreditar el lector v2 con un corte existente.
- Identificar los tres cambios de propietario fallidos y resolver su relevancia.
- Descartar enlaces abiertos hacia canónicas diferentes, o aportar el invariante que los impide.

No exigiría una implementación por conjunto con las mediciones actuales.

**CONFIDENCE: MEDIUM**

Ensayos aportados: **PASS reportado**. Ejecución independiente por este revisor: **NOT RUN**. Las hipótesis sobre enlaces, propietarios y concurrencia están separadas de los defectos observados en el SQL.
