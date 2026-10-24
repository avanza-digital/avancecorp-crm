# Publicación P-0XX — 24/10/2026

Publicado en https://crm.miavance.com. Fuente **`2d4f8eadb39141f86d546ab984e8d484a61ef388`**, PR #361, #362 y #363. Build **`build-20261024T050621234Z`**.

ZIP `crm-20261024T050622Z-2d4f8eadb391.zip`, SHA-256 `1032a2e1d7288856402474a1cbadb5011a167a8c54e011f38943d69fdca08b36`. Main y remoto coincidían al publicar; fuente limpia e idéntica al árbol probado `7fe3fc7b`. Los commits posteriores de documentación no son la fuente del build.

## Resultado productivo comprobado

- Antes: revisión 69, 175 operaciones; tres PEN ya valorados fuera de la foto y US$ 20.000 sin TC.
- Tras el ciclo natural de las 04:50 UTC: revisión 70, 178 operaciones, cero PEN valorados fuera de la foto. El USD continúa separado como pendiente. No se disparó manualmente la reconciliación ni se introdujeron fixtures en producción.
- Facturación lista/cuadro: **S/ 6.648.834,10**, mismo rango y corte. Metas conciliadas por persona contra producción: 30 personas. Smoke SQL en transacción de solo lectura con rol authenticated; no se presenta como una nueva sesión Auth HTTP.
- El navegador con la sesión existente de Gerencia confirmó el aviso «US$ 20,000 pendiente de tipo de cambio» en Facturación, Ranking y Metas; también la venta de S/ 5.000 del 23/10 en el detalle del analista afectado. Al pasar medianoche el corte visible avanzó al 24/10.
- Portada HTTP 200 y **133 archivos**, incluidos todos los JS/CSS, índice y versión, con bytes/huellas idénticos al manifiesto. [Resultado HTTP](publicacion-http.json).

## Base de datos

Migración **`20261024030000_crm_capital_pendientes_sin_bloquear`** instalada mediante `merge_branch`, no mediante un push general. El merge es asíncrono: se comprobó el catálogo efectivo después de la aceptación.

La rama propia `yzujybpofdjgsuritmky` volvió a presentar el fallo histórico de bootstrap. Se restauró solo esquema vacío preservando owners/ACL, con cron desactivado. Esa restauración no fue registrada como migración. Se alinearon 541 entradas de historial; antes del merge sus metadatos eran idénticos a producción y la única entrada adicional coincidía byte a byte con la candidata. El procedimiento de apply_migration normalizó 82 autores del historial en la rama; se restauró solo esa metadata antes del cotejo final.

Postflight: 541 registros anteriores intactos, huella `e07ee2c150d7e642bbde5224c45bb8fc`; solo una migración nueva. Publicador MD5 `90b53525ad7693c5ff4b77ff15da07d2`; RPC v2 MD5 `6420116af5c3705c087a6389640849e1`. La RPC permite únicamente authenticated y delega autorización a v1. Definiciones, owner, configuración y ACL de sello, cerrar_periodo, estado y v1 permanecen iguales. Los 24 paquetes Edge conservan contenido y verify_jwt. Cron de capital activo cada cinco minutos.

Advisors productivos: única adición, advertencia de RPC SECURITY DEFINER ejecutable por authenticated, intencional y probada por ámbito; ningún aviso nuevo de rendimiento. [Referencia del linter](https://supabase.com/docs/guides/database/database-linter). La rama vacía presenta más índices sin uso que producción; esa diferencia no se interpreta como regresión productiva.

## Verificación y ajustes finales

- Rama nueva: **26 aserciones SQL + 12 comprobaciones Auth/PostgREST + 26 aserciones al repetir tras HTTP**, todas PASS. Conexiones PostgreSQL con verify-full y CA oficial explícita. La fixture con correo NULL es rechazada antes de TRUNCATE y la transacción se revierte.
- App final: `npm run check` **PASS, 477 archivos / 7.748 pruebas**, tipos, lint, cobertura, build, bundle y duplicación. Ocho E2E relacionados en Docker PASS; el caso de Gerencia recorre ahora Metas antes y después de la llegada del TC. Un intento intermedio de cobertura coincidió con otro proceso Vitest y falló por su directorio temporal; ambos terminaron y la ejecución final exclusiva pasó.
- CodeRabbit: corregidos TLS, correo NULL, ayuda obsoleta y explicación antes del primer corte. Los hilos conocidos quedaron resueltos. Subagente confirmó el montaje mínimo de cobertura de Metas; no cambió el cálculo ni el ámbito de datos.
- El smoke inicial detectó que Metas de Gerencia omitía el aviso aunque el capital ya era correcto. PR #363 añadió el componente común y amplió el E2E. La versión final de esta acta incluye ese ajuste.
- CI de #362 y #363: app quality y RLS PASS. [App quality #363](https://github.com/avanza-digital/avancecorp-crm/actions/runs/40064791906) y [RLS #363](https://github.com/avanza-digital/avancecorp-crm/actions/runs/40064791904). El gate local completo del mismo árbol es PASS. El reanálisis automático de CodeRabbit seguía pendiente al cierre; no equivale a un hallazgo abierto.
- `gate:realidad` productivo ejecutado en lectura: 10 supuestos medidos, ocho conformes y dos divergencias existentes (ventas de analistas de baja y domicilios legales ausentes). No se presenta como un gate estricto totalmente conforme ni se alteran esos datos.

## Publicación y limpieza

Release, verificación y preflight PASS. El cliente antiguo recibió HTTP401 antes de subir nada. Se usó la sesión OAuth existente del servidor oficial Hostinger 1.59.0, sin leer/copiar credenciales ni cambiar configuración. Recibo final upload=success y deploy=success; luego se comprobaron los archivos servidos. El paquete intermedio `28e7446e` y el anterior `a7a2521d` quedan conservados como historial de recuperación, junto con sus manifiestos.

Rama temporal eliminada y ausencia confirmada. Ninguna rama de otras tareas fue tocada. Credenciales temporales de rama, claves productivas temporales y exportación de historial eliminadas. El repositorio original conserva su trabajo local; el clon de publicación queda sincronizado con avancecorp/main tras registrar esta acta.

[Evidencia agregada, sin clientes ni credenciales](publicacion-verificacion.json).
