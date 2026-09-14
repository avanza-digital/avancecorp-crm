# G7 — primer caso real verificado, 14/09/2026

**Resultado: capital e identidad conciliados; P1 abierto por timeout de lista y
ficha para supervisor/Gerencia. G7 permanece ABIERTO.** Referencia saneada:
`G7-REAL-20260914-01`. El solicitante comunicará sus observaciones después de
esta verificación; todavía no ha dado conformidad al resultado.

## Corte y alcance

Código local inspeccionado: `faa1059745aa852c4fb8275ff23f5a039f09e2a4`.
También se consultaron los cuerpos activos con `pg_get_functiondef` en producción.
Corte de invariantes: 14/09/2026, 15:58:19–16:13:09 Lima.

El caso combina una inversión inicial en Prodelco, registrada a las 11:53 Lima
antes del encendido F8, con una inversión adicional en Qorilazo confirmada a las
14:56 Lima durante el piloto. No se atribuyen ambas altas al piloto.

| Dato del caso | Prodelco | Qorilazo |
|---|---:|---:|
| Capital registrado PEN | 4,500 | 4,500 |
| Fecha comercial / imputación | 14/09/2026 | 11/09/2026 |
| Conversión inicial | Sí | No |
| Estado | Vigente | Vigente |

Una identidad canónica, un lead convertido y dos fuentes: **PEN 9,000**. La
fuente histórica de Prodelco no tiene fila relacional en `crm.inversiones`;
esto es compatible con el lector canónico que integra fuentes históricas y
nuevas. La inversión de Qorilazo sí tiene solicitud, inversión y titular
principal enlazados. El cliente externo no requiere perfil de acceso Avance.

## Verificaciones ejecutadas

| Control | Estado | Evidencia / límite |
|---|---|---|
| Identidad y atribución | PASS SQL | Documento vigente/verificado, una identidad canónica para ese documento, mismo analista y lead |
| Confirmación y depósito | PASS caso | Una solicitud confirmada, un evento de registro y una reclamación del depósito; referencias coherentes |
| Comprobante | PASS metadatos | JPEG de 63,220 bytes en bucket privado, vinculado a Qorilazo y al autor correcto |
| Fuente económica, lista y ficha del analista | PASS SQL | Dos fuentes de PEN 4,500, total PEN 9,000; una fila de persona en la búsqueda |
| Conversión | PASS núcleo | Un episodio de cierre con aporte 1; la inversión adicional no produce otra conversión |
| Facturación de Gerencia | PASS SQL | Lee `private.capital_episodios`; Qorilazo aporta PEN 4,500 el 11/09 al analista y supervisor correctos |
| Ficha de otra analista | PASS exclusión | Devuelve `null` para una persona fuera de su ámbito |
| Ficha de supervisor y Gerencia | FAIL rendimiento | Ambas consultas aisladas excedieron 20 s; SQLSTATE `57014` |
| Listado de supervisor y Gerencia | FAIL rendimiento | Comprobado después del review: ambos excedieron 8 s en el mismo núcleo; `57014` |
| Postventa multirrol | PASS SQL | Acceso para analista responsable, supervisor y Gerencia; otra analista recibe `42501`; sin retiros en este caso |
| Estado del informe F7 | PASS alcance | `habilitada=false` para Gerencia; conserva el OFF aprobado |
| Conservación del caso | PASS | Cinco firmas idénticas antes/después: persona, lead, cierres, inversiones y solicitud |
| UI, sesión Auth/HTTP, descarga y contenido del comprobante | NOT RUN | El runtime del navegador no encontró ningún navegador disponible |
| Reintentos, carreras, nuevos pagos/tareas/retiros | NOT RUN | No se fabricaron ni reenviaron operaciones económicas reales |

Los roles se comprobaron mediante `SET LOCAL ROLE authenticated` y UID local en
transacciones `READ COMMITTED`, terminadas en `ROLLBACK`. No son inicios de
sesión reales. Los lectores F5 registran auditoría y algunas funciones toman
locks: una transacción `READ ONLY` no sirve para este recorrido. Los errores
abortan la transacción; no hubo `COMMIT` en las consultas de comprobación.

Las duraciones del recibo incluyen la llamada a la herramienta. Los límites de
20 s y 8 s los impuso PostgreSQL. La ficha del analista también pasó un ensayo
con límite de 8 s (5.653 s totales); su lista respondió en 3.449 s. Estas muestras
no constituyen un benchmark ni permiten calcular el margen de ejecución de la
base a partir del tiempo total de pared.

## Hallazgo G7-R01 (P1): lista y ficha lentas en ámbitos amplios

Reproducción: ejecutar `crm.inversionista_ficha_fn` para esta misma persona con
el actor supervisor o Gerencia, `statement_timeout='20s'` y `ROLLBACK`.
Ambas ejecuciones aisladas terminan con `57014` en la selección inicial desde
`private.cartera_f5_personas_visibles()`. Gerencia también falló en el ensayo
compuesto anterior. Los roles `authenticated` y `authenticator` tienen 8 s
configurados en producción. El listado también falla con `57014` para ambos
actores bajo límite local de 8 s, con filtro de búsqueda del mismo caso.
No se aumentó el límite productivo ni se alteró una función. Es un defecto
reproducido del backend; no se observó directamente una pantalla o sesión Auth.

Ubicación: `20260910150039_crm_f6_postventa_persona.sql:1065` define la ficha;
`20260908230249_crm_f5_cartera_ficha_multiempresa.sql:149` define la base del
lector de personas, modificado en
`20260914025926_crm_f8_excluir_fuentes_demo.sql:103`. Las migraciones están en
`CRM-Avance-Corp/supabase/migrations/`.

El cuerpo publicado materializa personas autorizadas y repite búsquedas de
identidad canónica en enlaces laterales. Es una hipótesis del coste, **no una
causa raíz demostrada**: no se ejecutó `EXPLAIN ANALYZE`. El corte contiene
491 personas y 1,690 leads. El polling de cartera/ficha es de 15 s en
`app/src/data/inversionistas-queries.ts:18`; no se midió concurrencia de UI.

Siguiente corrección: medir el plan y el coste en un entorno de ensayo,
optimizar el núcleo compartido manteniendo ámbitos, fusiones y exclusión demo,
y volver a verificar los cuatro actores. No resolverlo duplicando lectores o
subiendo el timeout de producción. No se implementó ese cambio en esta revisión.

## Fechas e interpretación de los indicadores

La solicitud de Qorilazo ya contenía `fecha_comercial=2026-09-11`, revisión 0.
El formulario permite elegirla y el núcleo preservó ese valor; el mes estaba
abierto. No se atribuye esa elección al usuario como hecho observado ni se
considera un error automático. El texto `upgrade` está en la referencia libre
de cooperativas: no acredita un upgrade contractual de Avance.

La consulta publicada de facturación devuelve para ese analista/cooperativas
PEN 4,500 / una operación el 11/09 y PEN 9,000 / dos operaciones el 14/09.
El agregado del 14/09 incluye otra fuente además de los PEN 4,500 de Prodelco
de este caso. No es el total de esta persona ni demuestra un duplicado. La
conciliación de persona usa sus dos fuentes identificadas, entre las dos fechas.

## Cadena de núcleos comprobada

`InversionNueva` → `inversion-solicitud-api.ts` →
`crm.confirmar_inversion_revisada_fn` → fuente `crm.cierres_externos` y enlace
canónico de inversión/persona. Lista y ficha →
`private.cartera_f5_fuentes_reales` → fuentes canónicas existentes.
Capital/facturación → `private.capital_episodios`; conversión →
`private.conversion_episodios`. El informe F7, todavía apagado, también consume
el núcleo de capital mediante `private.metricas_f7_fuentes`.

No se añadió cálculo paralelo ni se modificaron código, datos económicos,
permisos o banderas. Lint, tests y build completos del producto: NOT RUN, al
tratarse de evidencia/documentación sin cambio de runtime.

Los importes conciliados son `capital_registrado`. Para cooperativas,
`capital_activo=null` corresponde al contrato publicado de lista/ficha: esa
medida se calcula exclusivamente para Avance. No se ha detectado un error por
esa diferencia de significado.

Evidencia: [recibo saneado](recibo.json), [review de Claude](claude-review.md) y
[evaluación del PRIMARY](EVALUACION-REVIEW.md). El primer
intento del wrapper falló dentro del aislamiento; se reintentó con el mismo
wrapper y evidencia saneada fuera de ese aislamiento, sin habilitar herramientas
al reviewer.

El caso aporta evidencia parcial de un recorrido representativo
**Prodelco → Qorilazo** y una inversión nueva confirmada durante F8. No completa
las cuotas por empresa, la matriz de G7, los reintentos ni las firmas.

Validación documental: PASS para parseo JSON, coherencia del recibo, enlaces,
wikilinks, revisión de UUID/tokens y `git diff --check`.
