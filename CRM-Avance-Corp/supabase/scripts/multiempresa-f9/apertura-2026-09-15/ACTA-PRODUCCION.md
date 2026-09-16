# Multiempresa habilitada para el equipo

**Ejecutado y verificado el 15/09/2026 a las 21:08 Lima** (16/09 02:08 UTC).
Miguel autorizó «OK ACTIVALO PRO FAVOR» y reanudó tras la pausa con «seguimos».
Codex ejecutó la activación administrativa en `dctqcbznekcyxhjujuci` desde el
artefacto guardado en `dde47fcd84b8629c010a4fa4155ea54c56f939a0`, idéntico a
`avancecorp/main` antes de ejecutar.

ACTIVAR SHA256: `d844c1093e50bea579ba2a852388783770e455db4800f98ecc45277be4069e92`.
La huella coincide con la del ensayo final de 17 escenarios. No se reconstruyó
ni publicó otro frontend: el existente ya consultaba las banderas del servidor.

## Resultado productivo

| Capacidad | Estado verificado |
|---|---|
| Cartera/Ficha 360, nuevas inversiones y postventa | Habilitadas para 18 analistas, 3 supervisores y 2 Gerencia |
| Coordinación | Cartera inversionistas denegada 42501; postventa deshabilitada |
| F3 / identidad única | ON, conservada |
| F4 / inversiones_escritura | ON |
| F5 / ficha_360_neutral | ON |
| F6 / postventa_neutral | ON |
| F7 / metricas_multiempresa_sombra | OFF, conservada |
| Piloto nominal F8 | OFF, revisión 2; cuatro miembros conservados como historial |

La disponibilidad general ya no depende del vencimiento del piloto el 21/09.
No se cambió la jerarquía ni se reasignaron clientes. Los accesos siguen siendo
los definidos por los núcleos para cada rol y ámbito.

[Recibo de activación y lectura independiente](activacion-produccion.json):
COMMIT confirmado, fuentes conservadas, **723,128 ms** con candados exclusivos.
El límite efectivo de sentencia fue tres segundos. Las cuatro comprobaciones
representativas consumieron 491,959 ms dentro de ese tramo.

[Capacidades de las 24 cuentas](capacidades-produccion.json): 23 gestores
habilitados y Coordinación excluida. Se usaron claims SQL con rol authenticated
y ROLLBACK; no se inició sesión humana ni se creó una operación económica real.

[Lecturas productivas](lecturas-produccion.json): tres cuentas fuera del piloto
(analista, supervisor y Gerencia), diez filas de muestra por cuenta, ficha propia
y totales exactos del núcleo. Analista y supervisor no acceden a ficha ajena.
Los universos visibles son 54, 252 y 494 personas respectivamente; la lista
incluye perfiles sin inversión y no equivale al universo de fuentes económicas.

[Conciliación posterior 21:09 Lima](conciliacion-posterior.json): **614 inversiones
y 468 identidades con fuentes económicas**, cero duplicados, identidades
incoherentes o diferencias entre Cartera, Capital y el lector F7. Los sellos
mensuales mantienen las mismas huellas que antes de activar.

## Revisión, límites y continuidad

Dos revisiones Claude entregaron CHANGES_REQUESTED. Se conservan originales;
Codex corrigió los puntos aplicables y refutó hipótesis con pruebas en
[EVALUACION-REVIEW.md](EVALUACION-REVIEW.md). No se presenta el dictamen como PASS.
17 escenarios SQL finales y `check:scripts` PASS; integridad de artefactos,
sintaxis y enlaces PASS. Las pruebas adicionales de browser/Login Auth humano
en producción son NOT RUN; el frontend respondió HTTP 200 y las capacidades y
lecturas productivas se comprobaron por SQL.

`actualizado_por` identifica a Carlos como responsable operativo declarado.
El motivo literal es «Apertura general F9-20260915-01; autorizada por Miguel;
ejecución administrativa Codex». No es firma ni sesión de Carlos. Las lecturas
de capacidad no agregaron auditorías a nombre de usuarios en el ensayo.

Reversa preparada y ensayada: [REVERTIR.sql](REVERTIR.sql). Apaga F4/F5/F6 para
todos, conserva operaciones y no restaura automáticamente el piloto. No se
ejecutó en producción porque las comprobaciones posteriores pasaron.

La apertura operativa está terminada. **G8 sigue abierto**: observar el ciclo
mensual, conservar rutas anteriores y tratar las métricas F7 aparte. Las
conformidades financieras G7 no se atribuyen automáticamente a esta orden.
Los filtros comerciales/mensuales y la distribución de Cartera siguen en el
pendiente solicitado por Miguel. No se creó un banco remoto de pago.
