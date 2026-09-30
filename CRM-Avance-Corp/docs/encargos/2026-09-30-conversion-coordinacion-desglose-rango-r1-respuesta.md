**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

Hay un falso rechazo de totales correctos, desgloses sellados incompletos marcados como disponibles y fórmulas que pueden mostrar igualdades falsas. Además, el PASS del 30/09 no acredita la rama «1 → hoy» como rango: ese día es exactamente el mes completo.

**FINDINGS**

**[P1] El navegador aplica el suelo en cero al agregado, pero SQL suma los netos individuales.**

Evidencia:
- Migración, `conversion_divisor_empresa_totales`, CTE `suma`: `sum(f.numerador)`.
- `app/src/lib/conversion-coordinacion.ts`, `desgloseConsistente`: exige `Math.max(bruto - ajuste, 0) === numerador`, también para `empresa`.
- `conversion-coordinacion.test.ts`, caso `conSuelo`: espera que la empresa tenga `8.15`.

Contraejemplo usando ese mismo test:

| Fila | Bruto | Ajuste pendiente | Neto |
|---|---:|---:|---:|
| Astrid | 11,15 | 0 | 11,15 |
| Merlys | 9 | 12 | 0 |
| Empresa: suma SQL | 20,15 | 12 | **11,15** |

El navegador exige **8,15**, rechaza los **11,15 correctos** y acepta el total incorrecto del test. Reproduje ambas decisiones en memoria.

**Corrección:** conservar la suma SQL. Validar el neto empresarial contra la suma de netos de analistas y `sin_analista`; mantener la comprobación del suelo por persona. La fórmula empresarial tampoco debe afirmar que restar toda la deuda pendiente al bruto produce ese neto.

**[P1] El desglose empresarial sellado omite producción que sí incluye su numerador.**

Evidencia: migración, `conversion_divisor_empresa_totales`, CTE `suma`:

- `numerador` incorpora `filas` **más** `fuera_foto`.
- Cierres y cartera suman únicamente `filas`.
- `desglose_disponible` depende únicamente de `bool_and(f.desglose_disponible)`.

`fuera_foto` incluye tanto `cobertura.fuera_ranking` como `conversion_sin_analista`.

Contraejemplo: foto con un cierre directo y numerador 1; cobertura externa con numerador 2. Se devuelve empresa con numerador **3**, desglose de **1** y `desglose_disponible=true`. El frontend sellado lo acepta.

**Corrección:** declarar disponible el desglose empresarial solo cuando cubra todos los componentes incluidos en el total. Si la cobertura externa no conserva desglose suficiente, devolverlo como no disponible; conservar el numerador congelado.

**[P2] La fórmula visual afirma igualdades que el contrato no garantiza.**

Evidencia: `app/src/components/app/conversion-coordinacion.tsx`, `formulaDelNumerador`:

```ts
`${cartera.renovacion_aporte} ... (${cartera.renovacion} × ${datos.peso_renovacion})`
const total = bruto ?? numerador
return `Cierres ponderados ${numero(total)} = ...`
```

Dos casos independientes:

- **Rango con pesos distintos:** una renovación ponderada a 0,10 y otra a 0,20 suman 0,30. SQL devuelve como `peso_renovacion` el del mes de `hasta`: 0,20. La pantalla afirma **«0,30 … (2 × 0,20)»**.
- **Foto sellada con ajuste:** bruto/ajuste son desconocidos. Un neto congelado de 8 y componentes que suman 10 pasan el candado sellado, pero la fórmula muestra **«8 = 10»**.

**Corrección:** en rangos, mostrar el aporte acumulado o los pesos por mes, sin atribuir un único multiplicador. En sellados, presentar composición registrada y neto congelado separadamente; no afirmar igualdad ni llamar «ajuste» a una diferencia cuya causa no está almacenada.

**[P2] Los checks de rango dependen del calendario y contienen expectativas incompatibles con el contrato.**

Evidencia:

- Oráculo, `E09a`: llama incondicionalmente con `p_hasta = v_fin` del mes actual. Antes del último día, la puerta correctamente devuelve `22023` por futuro.
- Postflight: el **30/09/2026**, `(v_mes, v_hoy)` y `(v_mes, v_fin_mes)` son idénticos. Ambas llamadas recorren la rama mensual.
- Postflight y `E09b`: exigen ajuste cero incluso cuando «1 → hoy» se convierte en mes exacto. Un mes válido con ajuste incumpliría ese check.
- `E09b` compara numerador del rango con numerador mensual: cuando existe ajuste, está comparando bruto con neto.
- `test-rls.mjs`: el supuesto rango invertido `{desde: hoy, hasta: primer_día}` es válido el día 1.

**Corrección:** separar pruebas de mes exacto, rango libre y ajuste mensual. Añadir un rango inequívocamente parcial y otro entre meses con pesos diferentes. Comparar el bruto donde corresponda y construir fechas inválidas que lo sean cualquier día.

**[P2] El registrador no acredita que los cuerpos vivos correspondan al artefacto registrado.**

Evidencia: `supabase/scripts/registrar-20260930221500.sql`.

Comprueba propiedades, ACL y referencias textuales; después registra `array[v_cuerpo]`. Los MD5 de `prosrc` solo se imprimen al final, sin compararlos contra valores esperados.

Un cuerpo de `conversion_divisor_empresa_totales` que sustituyera `sum(f.numerador)` por `sum(f.numerador) * 2` conservaría todas las propiedades verificadas por este registrador y podría quedar registrado como el artefacto original.

**Corrección:** comparar las cuatro huellas vivas con las esperadas del artefacto antes de registrar. La comprobación actual sí rechaza contenido distinto **ya registrado**, pero no demuestra correspondencia entre registro y funciones instaladas.

**RESPUESTAS A LAS DUDAS RESTANTES**

- **Pesos del rango:** usar ponderaciones distintas para referido y renovación no rompe por sí mismo la suma. El desglose suma `aporte_numerador`, que es lo adecuado. No está transcrito el cuerpo de `conversion_mensual_por_vendedor`, por lo que no puedo acreditar que invoque episodios con exactamente los mismos parámetros. La multiplicación visual sí está refutada arriba.
- **Rango que cruza sellados:** calcula en vivo, como establece el contrato suministrado. El frontend ya avisa «sin ajustes … ni fotos de cierre»; no ocurre completamente sin aviso. Un indicador específico de intersección sería una decisión adicional de negocio, no un bloqueo demostrado.
- **Bruto NULL / solo deuda:** falta el cuerpo de `conversion_neta_por_vendedor` y de `conversion_con_ajuste` para demostrar si existe esa fila y qué significa. Si devuelve bruto y neto NULL, la base transforma solo el bruto a cero y el candado rechaza el neto NULL. Es un caso pendiente de acreditar, no un hallazgo confirmado.
- **Puerta:** para los argumentos descritos, el gate precede a la validación y el límite de diferencia ≤365 implementa **366 días inclusivos**. No encuentro una fuga demostrada.
- **Fechas del frontend:** `diasInclusivos` usa ambas fechas a mediodía UTC; no veo un desfase por zona horaria. Aceptar un mes exacto solicitado como rango es coherente con el contrato.
- **Alcance:** el DDL suministrado no redefine los núcleos originales, pesos, entregas ni las otras puertas de conversión.

**RIESGOS Y TEST GAPS**

- Faltan fixtures de deuda superior al bruto, fila solo con deuda, foto sellada con ajuste y foto con producción externa.
- Falta probar pesos de renovación diferentes entre meses y un rango que intersecte un mes sellado.
- Conviene verificar visualmente las cabeceras: mantienen `colSpan={3}` y `colSpan={7}` mientras se ocultan columnas en distintos tamaños.
- El cambio de `hasta` exclusivo a inclusivo manteniendo `version: 1` requiere comprobar compatibilidad con clientes anteriores durante la publicación.
- **NOT RUN por este reviewer:** suites del repositorio, SQL y E2E. Los PASS recibidos son evidencia reportada; ejecuté únicamente contraejemplos aritméticos en memoria. `npm run check` y E2E seguían pendientes según el encargo.

**NEXT ACTIONS**

1. Corregir la validación empresarial y el test `conSuelo`.
2. Corregir disponibilidad del desglose sellado y las fórmulas visuales.
3. Reparar los checks dependientes del calendario y añadir los fixtures anteriores.
4. Acreditar las cuatro huellas antes del registro y completar los checks pendientes.

**CONFIDENCE: HIGH** en los hallazgos sustentados por los fragmentos; limitada para la semántica de NULL y la composición interna de los núcleos no transcritos.
CODEX_EXIT=0
