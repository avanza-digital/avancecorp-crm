# Cooperativas: vencimiento a los 360 días

**Release PAUSADO por petición de Miguel (16/10/2026, 23:45 UTC).**
Producción sigue intacta; no se publicó ni se hizo push. Los dos bancos
temporales de esta tarea fueron eliminados. Trabajo y punto de continuación
guardados en `PAUSA.md` y `ACTA-RELEASE.md`. El estado inicial y su evidencia
se conservan abajo como historial.

Para Qorilazo y Prodelco, cada mes representa 30 días corridos: 12 meses son
360 días desde el inicio. Ejemplo: 16/10/2026 + 12 meses → 11/10/2027.
Se conserva el porcentaje anual. Los contratos ya registrados mantienen su
fecha y su convención, incluso al corregirse desde Gerencia.

## Entrega

- [SQL exacto aprobado](20261016195003_crm_coopac_plazo_360_dias.sql), SHA256
  `518641adaee9ca85d8eecf50cfe09dd50d79af377cee3613af6a96bac0acd363`.
- [Parche de implementación y pruebas](cambio-desde-main.patch), 13 archivos,
  contra `avancecorp/main` observado `1170a5e36b957d186f079edf053d2e7745351cd5`.
  El código de app coincide con la base inicial probada; se conservó la nueva
  entrada ajena del ledger al actualizar el parche.
- [Reversa que preserva contratos ya creados](reversa.sql).
- [Huellas](huellas.json), [resultado HTTP](resultado-http-autenticado.json),
  [preflight productivo de solo lectura](preflight-productivo-solo-lectura.json).

La carpeta compartida estaba en `crm/conversion-adicional-renovacion-20261014`
con numerosos cambios ajenos y sin contener Main. Se conservó ese trabajo.
Implementación inicial: `/private/tmp/avancecorp-coopac-360-20261016/CRM-Avance-Corp`.
Copia completa sobre Main observado con parche aplicado:
`/private/tmp/avancecorp-coop360-main-1170/CRM-Avance-Corp`.
La [aplicación comprobada del parche](aplicacion-parche.txt) conserva las
entradas ajenas del ledger.
Solo este expediente se añadió al checkout compartido. No se creó worktree,
no se cambió de rama y no se incluyeron cambios de otras tareas.

El SQL añade `crm.cierres_externos.base_plazo`: anteriores `calendario`, nuevas
`dias_360`. El servidor valida meses × 30 días y Gerencia conserva la base de
la fuente. Un CHECK valida ambas convenciones. No se amplían permisos ni
firmas públicas. El formulario muestra el vencimiento y la equivalencia.
También se corrigió la lectura de Prodelco USD y su etiqueta en Gerencia.

## Verificación

| Control | Resultado |
|---|---|
| Lint / TypeScript / build finales | PASS, avisos previos: [salida](estaticos-build.txt) |
| Unitarias completas finales | PASS: 434 archivos, 6.998 pruebas |
| E2E F5/F6 locales en Docker | PASS: 29 recorridos sin reintentos; ver salida final adjunta |
| SQL desde cero y reversa local | PASS: ensayos adjuntos, conserva filas ficticias |
| Auth/PostgREST/Storage reales en rama | PASS: 95 comprobaciones, dos cooperativas y PEN/USD |
| CHECK sobre producción, solo lectura | PASS: 74 registros, 49 con condiciones, 0 incompatibles |
| Paridad de catálogo / delta candidato | PASS con tres CHECKs ajenos equivalentes; detalle adjunto |
| Advisors seguridad | PASS: 380→380, 0 nuevos |
| Advisors rendimiento | PASS: 345→332, 0 nuevos; 13 avisos de índice sin uso retirados por tráfico |
| Tipos | Generados del banco local; incorporado solo bloque de cierres |
| Revisión por wrapper | Dos CHANGES_REQUESTED, [cierre con evidencia](evaluacion-revision-final.md) |
| `check:scripts` | PASS sobre Main observado; [salida](check-scripts.txt). Primer intento bloqueado por sandbox al abrir servidor local; repetición autorizada PASS |
| Preflight Edge Functions | PASS sobre copia de Main observado; [salida](test-edge-preflight.txt) |
| `seed:preflight` / `test:rls:preflight` | NOT RUN: comandos detenidos por falta de SUPABASE_URL; salidas adjuntas |
| `gate:realidad` | NOT RUN: falta SUPABASE_URL en el entorno del gate |
| Matriz RLS integral y E2E completo de release | NOT RUN: pendientes antes de publicar |

La matriz real cubre alta, upgrade, reinversión, corrección de ambas bases,
revisión obsoleta, idempotencia, roles/ámbitos, rechazo de borrador anterior
sin efectos, posterior edición/revisión/confirmación y convención no elegible
por el cliente. No se desactivaron disparadores para esas operaciones HTTP.
F3 obsoleto exige el formulario compartido; se comprobó su rechazo sin alta.
Los ensayos locales de restricciones sí usan fixtures controladas con
disparadores desactivados; no se confunden con las operaciones autenticadas.

## Banco temporal y coste

Miguel aprobó la organización de PortalAvanceCorp y US$0,01344/h, con eliminación
al terminar. Rama `coopac-plazo-360-20261016`, proyecto `kfqjwcgwutxpgrpqeoqc`,
creada 16/10/2026 20:33:34 UTC y eliminada 22:01:02 UTC; la lista posterior
confirma su ausencia ([constancia](banco-eliminado.json)). Se eliminaron los
archivos privados de credenciales, tokens y estado del ensayo. Tiempo aproximado 1 h 27 min: unos US$0,02 según la
tarifa cotizada, no una factura. No se tocaron otras ramas.

El historial remoto antiguo falló al reproducirse. Se reconstruyó un esquema
vacío equivalente, sin copiar datos de clientes: 1.110 funciones y 154
relaciones, con propietarios, ACL, RLS, índices y disparadores comparados.
Antes del candidato no había diferencias en funciones. Tres CHECKs ajenos
solo difieren en paréntesis de AND. El candidato cambia únicamente las dos
funciones previstas, añade el helper y modifica cierres_externos.
Esta rama de ensayo **no era apta para merge automático** y se eliminó.

## Publicación pendiente

1. Integrar el parche sobre Main vigente preservando cambios ajenos/remotos.
   Repetir los gates integrales requeridos. Main local y avancecorp/main deben
   coincidir antes de construir el artefacto publicable.
2. Preparar una rama autorizada con historial de migraciones apto para el
   flujo de release; repetir las guardas y preflight de lectura antes de aplicar.
   El banco reconstruido y ya eliminado no autoriza saltarse el flujo de merge.
3. Coordinar una ventana sin altas cooperativas: servidor y pantalla deben
   actualizarse juntos. Publicar requiere la invocación humana `$release-crm`
   en Codex o `/release-crm` en Claude, según CLAUDE.md:76–80.
4. Actualizar las sesiones/PWA antes de reanudar altas. El aviso actual permite
   posponer; no fuerza recarga. Un cliente antiguo envía calendario y el
   servidor nuevo lo rechaza. Guardar borrador, actualizar y editar/revisar.
   Una corrección abierta durante el despliegue puede necesitar refrescar su revisión.
5. Se observaron tres solicitudes COOPAC preparadas en una consulta anterior.
   Recontarlas en la ventana y revisarlas con sus responsables dentro del CRM.
   El cambio no reescribe fechas de solicitudes guardadas silenciosamente.
6. Verificar PWA y artefacto publicado, vencimientos de fuentes nuevas,
   conservación de anteriores y ausencia de duplicados.

Si se revierte, aplicar reversa.sql junto con pantalla calendario. Conservar
base_plazo, el CHECK y la corrección por convención para respetar contratos 360
ya registrados. No se ha escrito en la base productiva ni publicado el CRM.

`pruebas-http.mjs` conserva las aserciones usadas como evidencia de código;
requiere el transporte y la configuración privada del banco ya eliminado y
no es un comando autónomo de release. No contiene credenciales.
