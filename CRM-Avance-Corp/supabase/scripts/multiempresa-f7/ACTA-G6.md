# G6 — conciliación multiempresa

**G6 CERRADO: lectura real verificada y conformidad humana/financiera recibida.**
No se infiere una firma del ensayo sintético, del review de IA ni de esta lectura.
Relacionada con el plan principal F7/G6 y [CONTRATO.md](CONTRATO.md).

## Corte y método

- Producción `dctqcbznekcyxhjujuci`, 11/09/2026 **17:51:44 Lima**
  (`2026-09-11T22:51:44.761352Z`). Agosto completo y septiembre hasta el día 11.
- F7 publicado desde `32eae8a22cbeef8bc54c20e989c6612c0f201efe`, release
  `crm-20260911T211821Z-32eae8a22cbe`. SQL instalado con registro
  `20260911212526`, archivo aprobado `20260911163243` y SHA-256
  `7b9cb56992dea24ead99d2d14c8ac79f9dabc7e9b40765f666117a5986e3c8e7`.
- **F3 ON; F4/F5/F6/F7 OFF**, sin backfill ni activación. La consulta
  administrativa autorizada evalúa el SELECT exacto del cuerpo instalado,
  fijado por huellas; no invoca la RPC pública de cifras apagada.
- Transacción `REPEATABLE READ READ ONLY`, `search_path` vacío, ejecutor y
  propietario F7 `postgres`, tiempos máximos 30 s / bloqueo 1 s, `ROLLBACK`.
  El claim de Gerencia es local a esa transacción para los reportes de referencia;
  no crea una sesión Auth ni equivale a aceptación humana.
- Capital contrastado por empresa/moneda/analista y por cada fuente económica
  con `EXCEPT ALL`; capital oficial por categoría y conversión oficial con
  comparación `NUMERIC` exacta antes de JSON. Pasa también el contrato real
  Valibot del frontend. Las monedas y empresas se conservan separadas.
- La conversión oficial global de agosto procede de la foto sellada; septiembre
  comparte el núcleo publicado. La consistencia entre lectores no sustituye
  la revisión financiera ni una conciliación con contabilidad externa.

## Resultado técnico del corte

| Comparación | Evidencia real | Resultado |
|---|---|---|
| Capital por empresa/moneda y reporte oficial por categoría | Ocho grupos en dos meses; diferencias exactas cero | PASS |
| Inversiones y fuentes únicas | Agosto 161; septiembre 57; total 218, sin duplicados | PASS |
| Atribución por inversión, fecha y tipo | Comparación bilateral por fuente; cuatro operaciones fuera del ranking en agosto y una en septiembre, incluidas con dinero y responsable en el anexo | PASS |
| Nuevos, renovaciones y upgrades | Grupos contrastados; cero fuentes de capital sin analista o con anulación comercial en los meses elegidos | PASS; anulación de capital sin caso real en este corte |
| Conversión global: numerador, divisor, tasa y factor | Igualdad exacta con ambos reportes oficiales; controles del núcleo identificados como consistencia de parámetros | PASS |
| Personas e identidad | 580 fuentes históricas: 570 coherentes, diez sin identidad, cero contradictorias; 434 personas identificadas | PASS de paridad; diez identidades pendientes |
| Cotitulares/personas en varias empresas | Cero casos reales presentes; evidencia sintética F7 conservada por separado | NOT RUN con casos reales |
| Mes sellado y custodia | Agosto: foto de 16 filas idéntica antes/después; diez funciones, conteo de 275 migraciones y banderas sin diferencias a las 17:52:21 Lima | PASS de comparación seleccionada |
| Vencimientos | Grupos y capital coinciden con fuentes vigentes | PASS |
| Oportunidades / No contactar | Conteos consistentes con el mismo predicado y helper; cero personas con veto en el universo observado | PASS de consistencia; ejercicio real de veto NOT RUN |

Los diez titulares sin identidad resuelta **no forman parte de las 434 personas**.
Sus importes del mes sí permanecen en el capital. El anexo de identidad abarca
toda la historia conocida, por lo que no se confunde con las 218 inversiones
de los dos meses. Las 566 fuentes sin fila relacional F4 son cobertura legado
admitida por el contrato, no 566 regresiones nuevas. Esta lectura no sanea ni
da por resuelto el inventario histórico de quince huecos de F4/F5.

Miguel confirmó el 12/09/2026 que los diez registros corresponden a **clientes
reales**. Esta confirmación valida su naturaleza comercial; todavía no determina
si cada registro está vinculado a la ficha única correcta ni resuelve posibles
duplicados de identidad. No se modificaron clientes, contratos ni capital.

Miguel confirmó también el 12/09/2026 que los **nombres y referencias mostrados
para los diez registros son correctos**. Esta validación comercial completa la
revisión visible del anexo; la vinculación técnica a una ficha única continúa
pendiente y queda fuera de esta aceptación.

Capital renovado completo no equivale a dinero nuevo. Comisiones fuera del CRM.
Las cifras son las del corte: la primera lectura de las 17:22 contenía 217
inversiones; una nueva operación registrada antes del corte final explica las 218.

## Evidencia y entrega privada

- [Procedimiento reproducible](g6/README.md) y
  [resumen sin datos personales](evidencias/g6-lectura-2026-09-11.json).
- Comparativo autónomo con importes reales, referencias, responsables y diez
  pendientes: `/Users/usuario/Desktop/Revision G6 - AVANCECORP 2026-09-11/Comparativo G6.html`.
- Captura SHA-256: `5a430de720f1f28468845e47957951fbed46a67026e58577001e69d560080ab1`.
  Consulta SHA-256: `06d7c4000883efe43401927145301ab82bb635f7d5b2af1c44f462f69170099f`.
- Respaldo privado: `/Users/usuario/.codex/backups/avancecorp-g6-20260911`.
  Capturas, consultas ejecutadas, anexo y reviews completos fuera de Git;
  carpeta 0700 y archivos de evidencia 0600.
- Review G6 y decisiones del PRIMARY: [g6/REVISION.md](g6/REVISION.md).
  Los reviews F7 anteriores conservan su alcance y sus propios dictámenes.

## Aceptación humana

- Revisión de Miguel de este corte y sus límites: **conforme, 13/09/2026**.
- Confirmación de que los diez pendientes son clientes reales: **recibida de Miguel el 12/09/2026**.
- Confirmación de nombres y referencias del anexo: **recibida de Miguel el 12/09/2026**.
- Responsable financiero: **Miguel**.
- Conformidad financiera: **recibida el 13/09/2026** con la declaración
  «Doy conformidad financiera al corte G6».
- Alcance temporal aceptado: corte del **11/09/2026 a las 17:51:44 Lima**.
  Miguel dejó constancia de que pueden existir variaciones en los montos al día
  de la aceptación. Esas variaciones posteriores son esperadas por nuevas ventas
  y no cambian ni invalidan la conciliación histórica de este corte.
- G6: **CERRADO**. F8 y F9: **NOT RUN**.

La aceptación registrada cierra la conciliación del corte concreto y conserva
sus límites de cobertura. No certifica ventas registradas después del corte,
no resuelve las vinculaciones de identidad pendientes y no modifica datos ni
habilita funciones. G6 permite preparar F8, pero no constituye por sí solo la
autorización para iniciar o activar el piloto.
