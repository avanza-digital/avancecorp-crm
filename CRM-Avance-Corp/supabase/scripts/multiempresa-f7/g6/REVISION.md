# Revisión de preparación G6 — 11/09/2026

Codex PRIMARY; Claude SECONDARY_REVIEWER mediante `scripts/claude-review`,
sin herramientas, escritura, persistencia ni delegación recursiva. Nivel 3
por tratar conciliación financiera. Dos consultas; no se solicita una tercera.
Esto no altera los dos dictámenes de la tarea anterior de implementación F7.

## Primera consulta: CHANGES_REQUESTED

El PRIMARY contrastó cada hallazgo con la instalación, el SQL y las pruebas:

| Observación | Decisión y evidencia |
|---|---|
| Contexto de ejecución de la proyección | Ejecutor y propietario reales son `postgres`; no se demostró diferencia de visibilidad en el corte inicial. Se reforzó con guardia de propietario, `search_path` vacío y registro en captura/postflight. SQL local y productivo PASS |
| Figuras insuficientes para aceptación humana | El reviewer recibió evidencia saneada. La entrega privada contiene importes de ambos informes por empresa/moneda, conversión, detalle por fuente/responsable y pendientes. La firma sigue pendiente |
| Postflight sin comparador reproducible adjunto | Se versionaron `metadatos.sql.in` y `verificar-postflight.mjs`: diez definiciones, banderas, conteo de migraciones y fotos cerradas. Captura y postflight quedan ligados por SHA-256 al informe. Comparación productiva PASS |
| Riesgo de PII en Git | Las capturas siempre estuvieron fuera del repositorio en carpeta 0700; no hubo filtración evidenciada. Plantillas sin datos, exclusiones adicionales y permisos 0600 para resultados. Se mantiene el anexo privado |
| Precisión monetaria tras JSON/Number | Se añadió cotejo `NUMERIC` exacto en el servidor y `EXCEPT ALL` para el reporte de capital publicado; conversión oficial exacta antes de serializar. Un control negativo impide PASS si SQL discrepa aunque Number coincida |
| Misma fórmula de conversión y veto | Renombrados como consistencia de parámetros/predicados. La conversión oficial cerrada lee la foto; septiembre comparte núcleo. Veto, cotitulares y varias empresas sin casos reales: NOT RUN, sin atribuirles el PASS sintético |
| Fuera del ranking, sin analista y anulaciones | El comparativo incluye cantidades, importes por empresa/moneda, referencias y responsables; el verificador coteja cobertura contra detalle. Capital sin analista/anulado: cero casos en este corte |
| Posible capital futuro en RPC publicada | Hipótesis descartada: su definición limita hasta hoy+1 Lima igual que la proyección. No se agregó un filtro sobre un conjunto que ya estaba cortado |
| Posible NULL del canonizador con entrada no nula | Descartado: `private.inversionista_canonica` conserva `p_id` como fallback; candidatos nulos excluidos en su origen. No ocultar una eventual anomalía filtrándola después |
| Orden no único de foto sellada | Descartado: PK `(periodo,vendedor_id)` verificada; el hash por periodo ordena por vendedor |
| PASS anterior después de error / permisos existentes | Ambos verificadores escriben FAIL ante error y fuerzan 0600. Prueba con JSON corrupto, archivo PASS previo y permiso 0644: PASS |
| Gerencia podía parecer aceptación humana | Campo `actor_referencia_gerencia` y explicación de claim local; no sesión Auth ni firma |
| Cruce de medianoche / alcance del extractor | Fecha exigida antes y durante la consulta; una proyección vacía se rechaza. Cuerpo fijado por huella e inspeccionado: la sustitución no es un parser SQL general |

No se añadió reconciliación monetaria por columnas inexistentes en las fotos
de vendedor; la foto cerrada aporta el total oficial de conversión y su
integridad. Capital/atribución del mes cerrado se rotulan como consulta actual.
No se calcula ni propone pago de comisiones.

## Segunda consulta: entrega FAIL, sin dictamen válido

Justificada por el método reforzado, las nuevas pruebas y las definiciones
productivas que resolvían hipótesis del primer review. Se adjuntaron código,
CodeGraph, comparador, fuente de los helpers y resultados saneados.

El wrapper terminó con código **1**:

> ERROR: Claude devolvió un resultado incompleto o sin VERDICT válido.

No se interpreta como PASS, CHANGES_REQUESTED ni BLOCK del reviewer: no existe
dictamen final válido. La causa interna no quedó acreditada; no se atribuye a
un error de cifras ni se elude el wrapper. Se preservan prompt/log y sus huellas
en el respaldo privado y el resumen versionado.

## Decisión del PRIMARY

La **preparación técnica** queda lista con la primera revisión evaluada y las
correcciones comprobadas: lectura real, contrato del cliente, NUMERIC exacto,
custodia, 19 controles negativos y generación/visualización del anexo PASS.
La segunda opinión final queda **NOT RUN por entrega incompleta**; no se afirma
aprobación final de Claude. No cambió el runtime ni se desplegó esta tarea.

**G6 sigue ABIERTO**: aceptación humana/financiera de este corte y sus límites
pendiente. No se activan F4/F5/F6/F7 ni se inicia F8. Evidencia y límites de
casos reales en [ACTA-G6.md](../ACTA-G6.md).
