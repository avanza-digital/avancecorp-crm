# F5 — Publicación y verificación productiva

**PUBLICADA Y VERIFICADA el 24/09/2026 a las 21:57:11 Lima**
(`2026-09-25T02:57:11Z`). Ese instante inicia la observación real de F3–F5.
El [registro de observación](../OBSERVACION-F3-F5.md) conserva pendientes los
siete días y la retirada final de Seguimiento. No se anticipa el corte del
sábado 26/09 ni se atribuye una nueva aceptación humana.

## Autorización y fuente publicada

Miguel respondió **«Sí, publicar F5 con esa integración»** a la propuesta de
usar la integración manual del PR #94 como aprobación para SQL F5 y
`$release-crm`. Esa respuesta sustituye la condición anterior únicamente para
esta publicación. GitHub no registra una revisión APPROVED: `miguejbs98`
integró externamente el PR #94; Codex no ejecutó ese merge ni una excepción
de administrador. El [registro previo](../f5-2026-09-24/PREPUBLICACION-F5.md)
se conserva como historia.

Main local de la copia separada y `avancecorp/main` coincidieron antes de
construir y justo antes de subir. Se integraron sin sobrescritura los PR #95
(documentación) y #96 (SQL ya instalado y sus actas). El código de frontend,
scripts de build y Edge de F5 conservó la [equivalencia](main96-equivalencia.json)
con el candidato probado. Se reutiliza el gate F5 4.386/297, Chromium 256/0/26
y WebKit 5/0; no se atribuye otra ejecución completa por los cambios documentales.
La revisión independiente anterior fue CHANGES_REQUESTED, con correcciones
verificadas por Codex; no se reetiqueta como un PASS del revisor.

| Dato | Valor |
| --- | --- |
| Sitio | https://crm.miavance.com/#/gestion-diaria |
| Commit servido | `b402a7f1b5c9789c1d592baa428f0bde8e1e9752` |
| Artefacto | `crm-20260925T023617Z-b402a7f1b5c9.zip` |
| SHA-256 del ZIP | `70b94da52e9002e92a4729579e7726a13f7539f0c9b16c0eb7a9de479eb41fe0` |
| SQL | `20260924201358_crm_gestion_diaria_pulso_habitos.sql` |
| SHA-256 SQL | `5f904c2b9b492b72fdb1ff1815aac2376d881939d6a8eaed938d1404380bf6b2` |
| Producción Supabase | `dctqcbznekcyxhjujuci` |
| Despliegue Hostinger | 24/09, 21:53:05–21:53:13 Lima; herramienta oficial `hosting_deployStaticWebsite` |

El [resumen del manifiesto](release-resumen.json) identifica los 116 archivos
y la fuente limpia. El ZIP y manifiesto completos están en el checkpoint privado
`gestion-diaria-f5-2026-09-24/release-main96/`. El acta posterior no cambia el
commit atribuido al sitio ni exige publicar nuevamente.

## Ensayo actualizado y promoción SQL

Se creó la rama temporal `gd-f5-publicacion-20260924` con datos ficticios,
sin copiar filas comerciales. El aprovisionamiento automático volvió a fallar
en el historial heredado: no se declara un replay completo exitoso. Se restauró
el baseline sintético autorizado y se cotejó con el catálogo productivo vigente.
Se incorporaron al banco las diferencias ya publicadas de veto SLA y auditoría
de solo añadir, conservando sus permisos; no fueron cambios de esta publicación.

La [matriz completa](matriz-candidato.json) terminó **2.267 aserciones / 0 fallos**.
Las [21 solicitudes HTTP](http-f5.json) con siete actores Auth sintéticos pasaron:
lectores permitidos, roles denegados, anonimato, fechas/períodos inválidos,
revocación con el mismo JWT y aislamiento del supervisor. El log íntegro queda
versionado y su huella consta en el resumen.

Durante la matriz se registraron en producción dos antecedentes de Main #96.
El catálogo no cambió durante esa ejecución; la [alineación](alineacion-main96.json)
dejó 357 migraciones previas y una única candidata F5. Se corrigieron en el
banco los permisos adicionales que introdujo la restauración antes del cotejo
final; no se relajó la comparación para aceptarlos.

El [merge nativo](merge-nativo.json) se solicitó a las 21:43:40 Lima. La respuesta
solo confirmó aceptación; se esperó a comprobar efectivamente F5 en producción.
La [verificación SQL](sql-produccion-verificada.json) acredita:

- 358 migraciones: los 357 antecedentes conservan versión, nombre y SQL.
- 774 funciones: 12 nuevas y dos cuerpos cambiados, exactamente el delta F5.
- Tablas, políticas, roles y permisos conservados; guardas y censo intactos.
- El merge nativo dividió el SQL en 42 sentencias. Cada fragmento coincide
  byte a byte y en orden con el SQL autorizado; entre ellos solo hay separadores
  y espacios. No se exige que el ledger conserve una única cadena.
- [Advisors y Edge](advisors-edge-produccion.json): cero hallazgos nuevos y
  las 21 funciones Edge con idénticos hashes, versiones y configuración JWT.

## Publicación y cifras reales

`release:crm` y `release:crm:verify` PASS. Publicación mediante el servidor oficial
`@hostinger/mcp@1.63.3`, con credencial autorizada del Llavero en memoria y sin
cambios de DNS ni configuración MCP. [Recibo](hostinger-publicacion.json).
[HTTPS](frontend-publicado-verificado.json): **78/78 archivos HTML, JS y CSS
idénticos al manifiesto**, más la portada raíz. El cotejo HTTP no incluye PNG
ni `.htaccess`; el ZIP completo sí fue verificado localmente.

Consultas productivas de solo lectura conciliaron el tablero contra actividades
y tareas originales en el mismo snapshot:

| Día | Llamadas | Útiles | Contestadas | Contacto | Leads distintos | Citas creadas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 24/09 | 243 | 241 | 74 | 30,7 % | 206 | 33 |
| 23/09 | 169 | 168 | 58 | 34,5 % | 152 | 21 |

Los 756 pendientes vencidos corresponden al instante actual, también al consultar
ayer. Once controles por fecha PASS: [hoy](produccion-sonda-hoy.json) y
[ayer](produccion-sonda-ayer.json). No son cifras congeladas para usos posteriores.

[Hábitos](produccion-sonda-habitos.json): 7/14/30 días, 19 personas y 969 filas
persona/día conciliadas; recuentos, primeras/últimas llamadas, tasas e intervalo
mayor con sus extremos dentro de jornada PASS. Totales de contacto: 471/1.192,
1.035/2.421 y 2.208/5.170. La sonda no sustituye los tests de jerarquía ni toda
la auditoría histórica de cortes. Su SQL queda en [sonda-habitos.sql](sonda-habitos.sql).

El [recorrido vivo de gerencia](recorrido-produccion.json) pasó con la cuenta
ya autorizada: hoy/ayer; hábitos de 7/14/30; detalle diario; operación → equipo
de diez personas → analista → registro de quince llamadas → ficha → cierre
con contexto y foco conservados. Comprobación visual de fecha e indicadores
PASS. No se escribieron datos de negocio ni se reconocieron/pospusieron avisos
para probar. Los controles negativos de roles se ejecutaron en el banco.

## Recuperación, coste y continuidad

El respaldo inmediato anterior es Main #93, `a1bbe24d46a607ef472671b985931af059ccc1e4`:
`crm-20260925T011259Z-a1bbe24d46a6.zip`, SHA-256
`f62ef077bf806aaf29e49b9d3c76fc718a4f4431042117ea7f2f4011c2643bef`.
Integridad local y 78 archivos HTML/JS/CSS servidos antes de publicar PASS.
Conservado en `release-anterior-main93/` del checkpoint privado; no usar como
respaldo inmediato el antiguo paquete `929fbbcc` de la preparación inicial.

[Rama eliminada y ausencia comprobada](banco-eliminado.json) a las 21:57:31 Lima.
Credenciales temporales locales retiradas; `banco-f7` ajeno intacto. Estimación
de esta rama US$0,010464 y acumulado US$0,029838 frente al máximo total US$5;
es una estimación por duración, no una factura.

F4.1 y la alerta de tasa muy baja siguen apagadas. La preparación F6 está en
el [PR #97](https://github.com/avanza-digital/avancecorp-crm/pull/97), con
4.393 pruebas, Chromium 265/0/26 y WebKit 14/0, dos revisiones independientes
PASS; no fue parte del ZIP publicado. La retirada final requiere siete días
reales estables, como mínimo hasta **01/10/2026 a las 21:57:11 Lima**, y evidencia
de ausencia de incidencias relevantes. No hay vigilancia automática prometida.
El corte único del sábado 26/09 conserva su comprobación pendiente.

El mismo Figma fue actualizado y comprobado visualmente:
[F5 publicada](figma-f5-publicada.png), [F6 en observación](figma-f6-observacion.png)
y [recibo de nodos](figma-publicacion.json).
