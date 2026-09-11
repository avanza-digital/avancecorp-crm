# F7 publicada e instalada, inicialmente apagada

11/09/2026. Codex PRIMARY. SQL exacto y coste autorizados por Miguel.
**Entrega técnica publicada y verificada; G6 continúa pendiente de cifras
reales y firma humana.** F3 ON; F4/F5/F6/F7 OFF. Comisiones externas.

## Publicación del CRM

Se integró `avancecorp/main@6293d24` sin sobrescribir trabajo ajeno. Antes de
construir y publicar, Main local, `avancecorp/main` y la copia limpia de trabajo
compartían `32eae8a22cbeef8bc54c20e989c6612c0f201efe`.

- Release: `crm-20260911T211821Z-32eae8a22cbe`.
- Build: `build-20260911T211820504Z`.
- ZIP SHA-256: `1f8d624a310d01b13c63f36720a7aab4148ba8178e235a2b53158594e5a2140f`.
- Destino verificado: `https://crm.miavance.com/`.
- Entorno productivo correcto y demo deshabilitado. Se inspeccionó el login
  de la vista previa del ZIP exacto, sin introducir credenciales.
- 90 recursos cotejados: 78 con SHA-256 exacto, once imágenes optimizadas
  por el servidor sin cambios respecto a la publicación anterior y `.htaccess`
  protegido. La lectura del archivo mediante el gestor confirmó todas sus
  líneas y sus 2.977 bytes; esa API omite el salto de línea final al devolverlo.
- ZIP inaccesible por HTTP en ambos dominios (404). Portal `miavance.com`
  conservado con el mismo hash. Los commits posteriores de actas no cambian
  el código ni el origen de este artefacto.

El ZIP anterior verificado se conserva para recuperación:
`crm-20260911T210409Z-6293d24ec071.zip`, SHA-256
`3b672665987f0b442c3d60311759e8efd1862c09663dd12c3cfc187778973fe5`.
Ambos ZIP y manifiestos están en `CRM-Avance-Corp/releases/`, fuera de Git.

## SQL instalado y cotejo productivo

Se instaló mediante **merge de la rama Supabase propia** en
`dctqcbznekcyxhjujuci`, después de igualar y verificar su base con el padre.
No se utilizó `apply_migration` directo a producción, `db push` ni repair.

Archivo aprobado, conservado sin renombrar ni editar:
[`20260911163243_crm_multiempresa_f7_metricas_sombra.sql`](../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql).
SHA-256 `7b9cb56992dea24ead99d2d14c8ac79f9dabc7e9b40765f666117a5986e3c8e7`.
El registro remoto tiene versión **`20260911212526`**, nombre
`crm_multiempresa_f7_metricas_sombra`. El banco registró el archivo completo
como una sentencia; el merge productivo lo dividió en 18 sentencias y dejó
`created_by=null` en la entrada nueva. Se comprobaron sus bytes y orden
contra el archivo aprobado, admitiendo solo la separación de espacios/saltos
entre sentencias. Las 274 entradas anteriores, incluidos sus autores y
sentencias, permanecen idénticas; total posterior: **275**.

Comparación productiva de 21:40:21 a 21:41:23 UTC:

- Las 619 funciones previas, sus permisos y el resto del esquema permanecen
  intactos. Las cuatro funciones F7 nuevas coinciden con las del banco.
- Las huellas de Capital, conversión, fuentes F5 y atribución se conservan.
  Auth, contratos, meses, cierres, Vault y cron conservan sus capturas de
  integridad. No hubo backfill ni escritura financiera.
- Las 19 Edge Functions conservan código, configuración y estado ACTIVE.
  Se verificaron además doce políticas Storage y tres relaciones Realtime.
- Consulta autenticada de Gerencia en transacción de solo lectura: estado
  `habilitada=false`; la consulta de cifras responde `P0409` por F7 OFF.
  HTTP anónimo real: ambas RPC rechazan con `42501`.
- Banderas: `resolver_en_puertas=true`; `inversiones_escritura`,
  `ficha_360_neutral`, `postventa_neutral` y `metricas_multiempresa_sombra=false`.

## Verificación y límites

- Gate frontend completo: **3.355 pruebas PASS**, lint, tipos, cobertura,
  configuración, service worker, build, bundle y duplicación. Pre-push completo
  también PASS. E2E: **172 PASS / 26 SKIP** preexistentes.
- Banco remoto: **16 SQL PASS + 12 HTTP PASS**. Los doce HTTP se repitieron
  después de registrar la candidata y restaurar la misma semilla: PASS.
  Incluye siete roles, anon, service_role sin identidad y revocación de
  perfil/membresía con el mismo JWT. Las dos firmas generadas coinciden.
- **Matriz RLS general: FAIL**, tanto antes como después:
  **1.772 PASS / 57 FAIL de 1.829**. Comparación: **PASS, cero regresiones**.
  Se restauró exactamente la misma semilla sintética; solo se normalizaron
  UUID ficticios al comparar el multiconjunto de fallos. Algunos son conteos
  afectados por la coexistencia de fixtures F7 y generales. Este resultado
  no acredita un PASS global de RLS ni 57 defectos productivos nuevos.
- Advisors del banco: seguridad 259 → 261 observaciones; las únicas dos
  nuevas son WARN por las RPC F7 `SECURITY DEFINER` ejecutables por
  `authenticated`. Es intencional: el servidor exige Gerencia y perfil activos,
  y los auxiliares privados no son ejecutables desde la API. SQL y HTTP
  comprobaron denegaciones y revocaciones. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  Rendimiento 278 → 145, ninguna observación nueva; desaparecieron 133
  observaciones de índices sin uso al ejercitar el banco. No equivale a un
  PASS global de seguridad o rendimiento. Advisors productivos archivados
  por separado: 262 observaciones de seguridad y 118 de rendimiento.
- Claude emitió dos `CHANGES_REQUESTED`; Codex evaluó y corrigió lo confirmado
  según [REVISION.md](REVISION.md). No se convierte ese dictamen en PASS.
- **NOT RUN:** rendimiento con volumen productivo, conciliación/revisión
  manual F7 y firma G6, piloto F8 y operación mensual F9. VoiceOver F6 conserva
  el NOT RUN aprobado por Miguel. El ensayo usa cifras ficticias.

## Banco cerrado y continuación

Banco exclusivo `multiempresa-f7-20260911` (`awshxyerdsvgjnteetfa`), rama
`429fa19f-d018-428c-94a5-731541fde6ed`: creado a las 20:42:52 UTC con coste
autorizado de US$0.01344/h; **eliminado y ausencia comprobada a las 21:47:18 UTC**.
Se conservó el banco anterior `banco-f7`, que pertenece a otro trabajo.

Evidencia saneada: [instalación productiva](evidencias/instalacion-produccion-2026-09-11.json)
y [ensayo remoto](evidencias/ensayo-remoto-2026-09-11.json). Detalles del montaje:
[ENSAYO-REMOTO-2026-09-11.md](ENSAYO-REMOTO-2026-09-11.md).
Respaldo privado duradero: `/Users/usuario/.codex/backups/avancecorp-f7-20260911`;
incluye bundle, artefactos/evidencias y un punto de retoma sin claves en Git.

Sigue preparar y ejecutar la conciliación de cifras reales de
[G6](ACTA-G6.md), con Gerencia y responsables, antes de solicitar F8.
No se ha firmado el acta ni autorizado encendido, backfill o piloto económico.
