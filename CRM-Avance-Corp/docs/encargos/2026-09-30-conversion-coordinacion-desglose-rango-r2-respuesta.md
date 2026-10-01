VERDICT: **CHANGES_REQUESTED**

SUMMARY: Las correcciones de la suma empresarial, el suelo por persona y la fórmula sellada resuelven los problemas descritos de r1. Quedan dos problemas del formulario y una suposición del oráculo que necesita corregirse o refutarse con su preparación completa. No identifico un P0/P1 demostrado en la evidencia recibida.

FINDINGS:

**[P2] El modo mes ignora la fecha mínima del propio formulario.**

Archivo: [conversion-coordinacion.ts](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-conv-desglose-20260930/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.ts), símbolo `motivoConsultaInvalida`; componente `ConversionCoordinacion`, entrada `type="month"`.

Contraejemplo: `{ modo: 'mes', mes: '2024-12' }` con hoy `2026-09-30` devuelve `null`, aunque el control declara `min="2025-01"`. También acepta un año parcial como `0202-09`. El atributo HTML `min` no impide ejecutar `onChange` ni la consulta automática; `cargar` únicamente consulta este validador.

Impacto: se envían consultas anteriores al mínimo y el campo no recibe `aria-invalid`. Además, en modo mes se envían inmediatamente.

Recomendación: aplicar el mínimo también en la validación mensual y probar un mes inferior al límite introducido por teclado.

**[P2] La tabla conservada no identifica visiblemente el período al que pertenecen sus cifras.**

Archivo: [conversion-coordinacion.tsx](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-conv-desglose-20260930/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.tsx), símbolos `claveEstable`, `cargar`, `mensajeEstado` y `etiquetaPeriodo`.

Secuencia reproducible por el código:

1. Se muestra el rango A.
2. El usuario cambia los controles al rango B; durante 350 ms sigue visible A.
3. Si B queda inválido, `cargar` conserva A indefinidamente.

Las fechas exactas de A solo aparecen en `mensajeEstado`, que tiene `sr-only`; cuando B es inválido, ese mensaje también se sustituye por la ayuda. Los textos visibles «del mes» o «del período» no identifican A.

Una respuesta de A todavía puede aceptarse durante la espera, porque su controlador se aborta al cambiar `claveEstable`. **No veo una sobrescritura tardía después del aborto**, pero sí cifras de otro período bajo controles distintos, sin identificación visible.

Recomendación: conservar la tabla mostrando sus fechas exactas desde `datos.periodo`, e indicar que corresponde a la última consulta mientras los controles difieran. Cubrirlo con promesas diferidas y temporizadores.

**[P2] E09 presupone que el mes anterior está abierto.**

Archivo: [oraculo-divisor-coordinacion.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-conv-desglose-20260930/CRM-Avance-Corp/supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql), diff de `E09a`, `E09a2` y `E09b2`.

Si el banco conserva setiembre sellado al ejecutar el 01/10:

- E09a exige `fuente.modo = 'mensual'`, aunque el resultado correcto sería `'foto'`.
- E09a2 exige una llegada sintética que una foto anterior a la siembra no tiene por qué contener.
- E09b2 exige `cruza_meses_sellados = false`, aunque el rango desde el 15 de setiembre sí toca ese cierre.

Esto afecta al **oráculo**, no demuestra que el postflight de la migración falle por ese cierre anterior.

Para refutarlo, hace falta mostrar una preparación anterior a E09 que garantice expresamente ese mes abierto. Si existe, sigue faltando cubrir el escenario contrario. La recomendación es controlar ambos estados mediante fixtures explícitos.

Riesgos y respuestas restantes:

- **Igualdades:** la empresa ya comprueba suma de netos; la fórmula sellada no equipara partes con neto, y el rango no promete multiplicar todas las renovaciones por un único peso. No encuentro otra igualdad incorrecta demostrada en esas ramas.
- **Fotos y `conversiones_*`:** E07 acredita el lector de una foto construida manualmente. No acredita qué escribe siempre `crm.cerrar_periodo`: falta ese cuerpo y se desactiva el trigger durante la siembra. Para un objeto sin esas claves, devolver `desglose_disponible = false` es una degradación correcta.
- **Riesgo condicional con fotos antiguas:** si `cartera` admite **SQL NULL** y `origenes_ranking.disponible = true`, `con_desglose` devuelve NULL, no false. El esquema del navegador exige un booleano y rechazaría el payload. Refutar con la restricción correspondiente o cubrir ese caso; no está acreditada su posibilidad en los datos actuales.
- **`cruza_sellados`:** el `BETWEEN` cubre exactamente los meses tocados por un intervalo inclusivo, suponiendo `periodos_cerrados.periodo` normalizado al primer día. La exclusión del mes exacto es coherente con servir su foto.
- **Postflight:** el tratamiento del último día quedó corregido. El tramo que empieza el 15 evita leer la foto del mes anterior. Las comprobaciones mensuales siguen presuponiendo el **mes vigente abierto**; si pudiera sellarse el 30/09 antes de aplicar, exigirían desgloses que la rama sellada devuelve nulos. Falta el contrato de `cerrar_periodo` para descartar ese escenario.
- **Validación por campo:** en rango no encuentro discrepancia entre tener motivo y tener algún campo marcado. Con errores simultáneos pueden marcarse ambos y explicarse primero uno. El mínimo mensual ausente es otro problema.
- **Huellas:** aplicar el mismo contenido conserva `prosrc`; `#variable_conflict` no provoca una reescritura del cuerpo almacenado. Cambiar finales de línea podría cambiar la huella: sería contenido distinto del probado. La coincidencia comunicada en el banco respalda este control.

TEST GAPS:

- **PASS comunicado:** migración, oráculo, registrador y 5.055 pruebas.
- **E2E:** pendiente en la evidencia.
- **`test-rls.mjs`: NOT RUN.**
- Esta revisión fue estática; no ejecutó verificaciones.

NEXT ACTIONS:

1. Refutar los contraejemplos del formulario con pruebas específicas o corregirlos.
2. Acreditar la preparación de E09 y probar el 01/10 con setiembre sellado.
3. Aportar evidencia del escritor de fotos y de la nulabilidad de `cartera`; completar los checks pendientes sin presentar como PASS los no ejecutados.

CONFIDENCE: **MEDIUM**. Alta para las ramas y aserciones citadas; limitada para los productores, restricciones y núcleos no transcritos.
