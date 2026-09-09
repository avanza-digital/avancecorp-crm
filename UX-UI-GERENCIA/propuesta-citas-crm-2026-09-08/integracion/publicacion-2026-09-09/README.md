# Citas de Gerencia: publicación del 9 de septiembre de 2026

## Resultado y uso

Publicado en https://crm.miavance.com, **Gerencia → Citas**. Consulta compacta con
mes y cuatro semanas comerciales (1–7, 8–14, 15–21, 22–fin), filtros del equipo,
citas por lead y cumplimiento: 3 citas = 100%; 3,75 = 125%.

El recorrido horizontal muestra personas que no asistieron, reprogramaron,
asistieron y después se convirtieron en cliente. Cada etapa contiene únicamente
personas de la anterior y cada lead se cuenta una vez. La fuente de «Depositó»
es la conversión vigente a cliente confirmada por Miguel; la fecha visible es
la de conversión. No se infiere un importe a partir del capital estimado.

## Fuente y artefacto publicado

- Commit publicado: `887bef6e1bda65f2eb65b8cb9ae00d093f2bf883`.
- Main local, `avancecorp/main` y el checkout limpio coincidían antes de publicar.
- Release: `crm-20260909T045534Z-887bef6e1bda`.
- ZIP: SHA-256 `57c12c4a3bf7c4513088f7b079dcc50e767a787fcd568be740ee0ea5c3fdd0b4`.
- Versión web: `build-20260909T045533356Z`.
- Rollback conservado fuera del web root: `crm-20260908T222023Z-264ece653320`,
  SHA-256 `e78515505395f97bff558f192dcf0f99963cebea099b4e61194eb3c273d79065`.
- Los cambios no confirmados del checkout compartido quedaron fuera del paquete.
  El nuevo acabado F5 incorporado a Main durante la preparación se incluyó tras
  repetir el gate completo. Sus funciones nuevas conservan su activación propia.

## Base de datos y permisos

Ensayo en la rama temporal autorizada `citas-publicacion-20260909`
(`plaeuugsybujzymrcvgj`), integración por `merge_branch` y lectura posterior
en producción. La rama se eliminó al terminar; `banco-f7` se conserva.

| Archivo versionado | Versión registrada por Supabase |
| --- | --- |
| `20260909003243_crm_citas_gerencia_consulta_detallada.sql` | `20260909031832` |
| `20260909015744_crm_citas_deposito_por_conversion_cliente.sql` | `20260909031848` |

Supabase asignó las marcas al aplicar en el banco. No se renombraron ni editaron
migraciones versionadas. El merge conservó esas versiones; reserializó el array
de sentencias del registro nuevo, por lo que su hash de array difiere entre
banco y producción. Los cuerpos SQL y los permisos efectivos sí coinciden.

Sólo se añaden `private.citas_gerencia_consulta(date,date)` y su fachada
`crm.citas_gerencia_consulta_fn(date,date)`. Las 557 funciones anteriores
mantuvieron cuerpo, propietario, volatilidad, search_path y ACL; las 263
entradas anteriores del historial también coinciden. Columnas, triggers,
políticas RLS, RLS por tabla, índices, restricciones y vistas de producción
conservan las huellas anteriores.

La consulta exige la autoridad canónica de Gerencia activa. La fachada es
INVOKER y el núcleo DEFINER con search_path vacío. Anon/PUBLIC no tienen
EXECUTE; los demás roles autenticados reciben 42501.

El merge de Supabase también volvió a empaquetar ocho de las 17 Edge Functions,
incrementando versión y hash del paquete. Se cotejaron sus 39 archivos de fuente
contra la rama de origen: contenido idéntico, verify_jwt e import maps conservados.
Las otras nueve mantuvieron su hash. No se modificaron secretos ni configuración.

## Banco aislado y límites de la matriz general

La creación automática de una rama vuelve a fallar en el historial antiguo
(86 de 263 migraciones). Para este ensayo se restauró el esquema actual de
`public,crm,private` sin filas de personas, leads, clientes ni contratos reales,
y se repuso exactamente su historial registrado. Esto comprueba paridad actual;
**no equivale a un replay íntegro del historial antiguo**.

La comparación inicial cubrió nueve categorías de esquema, ACL de esquema,
tabla y columna, y arrays del historial. El dump omitía comentarios internos de
dos funciones; sus definiciones exactas se restauraron antes del ensayo. Las
únicas diferencias estructurales restantes del banco eran la parentización
equivalente de tres CHECK: `alertas_reconocimientos_miembros_check`,
`empresas_monedas_check`, `producto_condiciones_capital_check`.
Se comprobaron los operandos, la equivalencia ternaria de AND y
`convalidated=true` en ambos lados. Estos CHECK no forman parte del merge.

El seed general necesita configuración que no viaja en un dump sin datos.
Se prepararon políticas SLA, producto técnico histórico, empresas, flags,
pares de autoridad y el estado inicial de Rentabilidad que espera el banco.
Son datos exclusivos de prueba. El permiso temporal de seed sobre
`crm.periodos_cerrados` se revocó. La baja histórica de vendInactive conservó
auditoría y rotación ICS; sólo se suspendió/restauró su guard de jerarquía dentro
de una transacción, siguiendo LEEME-seed.

**La matriz general terminó FAIL: 1.590 aprobadas y 65 fallidas de 1.655.**
No se presenta como un gate aprobado. Los fallos están en [rls-fallos.txt](rls-fallos.txt).
La revisión independiente acotó causas verificadas:

- Ausencia de `conversion_pesos`, `sla_operacion_control`, configuración de
  lead libre y `auditoria_sello` en el banco: errores 55000/P0002 y del sello.
- Pruebas b5/E4 anteriores a la migración productiva que restringió la
  corrección del documento al administrador.
- El supuesto «segundo lead» partía de un fixture sin el primer lead/backfill:
  se midió una identidad con un único lead. No se observó duplicación.
- Otras expectativas antiguas, incluyendo errores exactos y datos de cohortes,
  permanecen como deuda del banco general; no todas se investigaron individualmente.

Decisión del PRIMARY: publicación acotada de este lector, sustentada en la
invariancia de las funciones/escritores existentes, ausencia de llamadas del
gate antiguo al lector nuevo, matriz específica y prueba REST. Este cierre
**no acredita la matriz general ni una activación de otros módulos**.

## Verificación ejecutada

| Comprobación | Resultado |
| --- | --- |
| `npm run check:all` en el commit publicado | PASS: lint, tipos, cobertura, 3.127 tests, build, bundle, duplicación |
| Playwright completo del commit publicado | PASS: 147; 26 omitidas por la suite |
| Scripts y preflights offline | PASS: sintaxis, seed/RLS preflight, Edge preflight |
| SQL de consulta Citas | PASS: roles/ACL, cohorte, vínculos, asistencia, postventa, límite 10.000/10.001 |
| SQL de depósito por conversión | PASS: unicidad, anulación, cliente inactivo, futuro y pertenencia |
| REST del banco con sesiones reales | PASS: Gerencia V2; rechazo de supervisor, analista, coordinación, directorio, cliente, inactivo y anon |
| Generación de tipos desde el banco | PASS: firma RPC idéntica a la versionada |
| Lectura de producción | PASS: V2, conversiones únicas dentro de la cohorte y anteriores al corte |
| Advisors de seguridad productivos antes/después | Sin avisos nuevos; avisos anteriores conservados |
| Matriz RLS general | FAIL: 65/1.655; causas y alcance arriba |
| Navegación de producción con sesión Gerencia real | NOT RUN: no había navegador/sesión autenticada disponible |
| Smoke público en navegador aislado | PASS: login visible, sin errores de consola |

La lectura productiva de septiembre devolvió 115 filas de **historial de la
cohorte** y dos conversiones de esa cohorte. No son el conteo exclusivo de citas
del mes ni el de depósitos recuperados del embudo.

Los dos bancos SQL pasaron antes del seed general. Al repetirlos después,
un fixture general ocupaba el mes que el test suponía vacío. Se aislaron las
citas mediante TRUNCATE transaccional exclusivamente en la rama ficticia y
ROLLBACK final; las mismas aserciones volvieron a pasar. No cambió el SQL de producto.

## Comprobación del hosting

**PASS: 79/79 archivos contrastados con el manifiesto**, mediante las dos vías
explicadas abajo. Los doce PNG tampoco cambiaron respecto al rollback.

Hostinger aceptó el ZIP y retiró el archivo de carga. Cache purgada; tres
lecturas consecutivas de version.json coinciden con el paquete. El ZIP devuelve
404 tanto en crm.miavance.com como en miavance.com.

Los 67 archivos públicos distintos de las doce imágenes transformadas por el
CDN coinciden por bytes y SHA-256 con el manifiesto, incluido HTML, JS, CSS y
version.json. Siete PNG conservan exactamente sus píxeles pese a la recompresión;
cinco logos se entregan reducidos a 1600 × 1484. La comparación binaria estricta
inicial de esos doce PNG es FAIL y se conserva como evidencia de la transformación;
no se afirma identidad binaria donde no existe.

La revisión independiente leyó los doce originales directamente desde
147.79.84.218 (registros A crm/ftp consultados en Hostinger), manteniendo TLS y el
hostname mediante `curl --resolve crm.miavance.com:443:147.79.84.218`.
**Los doce originales coinciden por bytes y SHA-256 con el manifiesto.**
El origen responde LiteSpeed y la ruta pública hcdn. La reducción de ancho y
la optimización de imágenes están [documentadas por Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/).

Evidencia saneada: [verificacion.json](verificacion.json),
[hosting.json](hosting.json), [imagenes-cdn.json](imagenes-cdn.json),
[api-roles.txt](api-roles.txt), [consulta-sql.txt](consulta-sql.txt),
[conversion-sql.txt](conversion-sql.txt) y [smoke-publico.txt](smoke-publico.txt).
