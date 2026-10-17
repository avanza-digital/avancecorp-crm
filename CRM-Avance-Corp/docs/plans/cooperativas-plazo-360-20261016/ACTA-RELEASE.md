# Cooperativas 360 días — release

Estado: **GATES APROBADOS; publicación pendiente**. Miguel reanudó con
«sigamos!!!» la pausa segura del 16/10. Autorizó `$release-crm` y «corrige
el control y continúa la publicación». Destino: crm.miavance.com,
repositorio avanza-digital/avancecorp-crm, Main sigue avancecorp/main.

## Cambio autorizado

Qorilazo y Prodelco: cada mes entero equivale a 30 días corridos desde el
inicio comercial; 12 meses son 360 días. La tasa anual se conserva.
Los contratos anteriores mantienen calendario y sus fechas, incluso en
correcciones de Gerencia. Se corrige también la lectura de Prodelco USD.

Dos ajustes adicionales actualizan cuatro huellas de tres validadores que
retenían policies anteriores a la consulta de Coordinación ya publicada.
No cambian policies, ACL, owners, firmas ni restricciones. Cada ajuste exige
el cuerpo y las policies exactos antes de actuar y ejecuta sus validadores.

| Migración | SHA-256 aprobado y comprobado |
|---|---|
| 20261016195003 | `518641adaee9ca85d8eecf50cfe09dd50d79af377cee3613af6a96bac0acd363` |
| 20261016231301 | `be058004682a2f198da54ff8be3a49d3cb461f4178e50be759c42edd2a59a827` |
| 20261016232742 | `9cc1490237da010ab3849a956fbb26024cda2af865e243a4fa3d5b748d076a37` |

## Verificación final

Se integraron #313 (Citas) y #314 (texto de renovación) sin conflictos.
App verificada: `61281001217df76cdfc1295654559f21dcc073b9`; los commits
posteriores solo agregan actas y corrigen sondas. No cambió el runtime.

| Gate | Resultado |
|---|---|
| App integral | PASS: 7.000 pruebas / 435 archivos, lint, tipos, cobertura, release-config, build, bundle, duplicación |
| E2E Docker completo | PASS proceso 0: 438 passed / 1 flaky / 26 skipped, 18 minutos |
| Sonda móvil corregida | PASS: 9/9, sin reintentos, tres repeticiones del archivo |
| RLS integral | PASS: **4.059 aserciones**, cero fallos |
| Facturación histórica | PASS: doce oráculos, fechas de sonda en el pasado |
| Scripts / preflights seed, RLS, Edge | PASS; scripts repetidos tras las correcciones |
| Cooperativas Auth/PostgREST/Storage | PASS: 95 comprobaciones originales, mismo SQL exacto |
| Mutantes de auditoría | PASS: 5 + 18 + 20 detectados y cuatro adicionales rechazados |
| Paridad final del banco | PASS: catálogo idéntico antes/después de RLS y mutantes; 62 ACL por columna idénticos a producción |
| Tipos | Bloque cierres_externos remoto idéntico al versionado, tres apariciones de base_plazo |
| Seguridad advisors | 380→380, cero nuevos |
| Rendimiento advisors | 336→215; 122 retirados y un índice preexistente marcado sin uso tras reconstruir, sin índices nuevos |
| Realidad productiva, solo lectura | Ejecución correcta; dos divergencias preexistentes, sin errores de consulta |

El E2E flaky intentaba pulsar «Ocultar menú» durante la sustitución del sidebar
por la navegación móvil. Se corrigió exclusivamente la espera de la sonda,
se mantuvieron las comprobaciones visuales y se repitió sin retries.
Una sonda RLS opcional de nombre por perfil canónico quedó NOT RUN porque
clientBank ya tenía identidad; no se cuenta como PASS. Los 26 E2E omitidos
se conservan como skipped. Salidas y detalle en [RETOMA-20261017.md](RETOMA-20261017.md).

Las divergencias de realidad son 45 ventas de analistas inactivos y 273
clientes sin domicilio; no se corrigieron ni se presentan los diez supuestos
como satisfechos. El aviso dinámico del índice está documentado en
[advisors-retoma.json](advisors-retoma.json), con enlace de remediación.

## Banco y flujo SQL

Banco actual: coopac360-retoma-20261017, ref qlsukwhdouhgzkjgsebe,
ID 94cba615-4071-46ea-b69a-85c2092041ad, creado 17/10 02:24:08 UTC.
Misma organización y tarifa autorizada US$0,01344/h. Eliminar al terminar.
Los dos bancos anteriores fueron eliminados; constancia en PAUSA.md.

El replay histórico falla antes del candidato. Se reconstruyó esquema vacío,
sin datos de clientes, con 1.110 funciones y 154 relaciones comparadas,
owners/ACL/membresías/Storage/Auth, y las 487 entradas exactas del historial
fuente. Digest base: c2bb35ce082c65d2948ca2724548aece. Tres CHECKs ajenos solo
difieren en agrupación equivalente de AND. No se alteraron sus guards.

Se usó una carpeta CLI privada con las 487 versiones ya aplicadas y las tres
candidatas, verificadas por SHA. Las entradas históricas sin sentencias
conservadas NO se ejecutaron ni se presentan como replay. La CLI aplicó solo
las tres candidatas con sus versiones originales; cada sentencia registrada
es texto exacto del fichero aprobado. No se reparó historial productivo.

Después del candidato solo cambian cierres_externos y cinco cuerpos de
función y se añade el helper de cuatro argumentos. No cambian owners/ACL/config
de funciones existentes. Toda configuración y persona de pruebas es ficticia.
Las 23 Edge Functions conservan versiones, configuración y hashes del origen.

Preflight productivo reciente: 487 migraciones / última 20261016190408,
helper/corrección/CHECK originales exactos, base_plazo ausente,
84 cierres / 59 con condiciones, cero incompatibles. Repetir antes del merge.

## Revisión independiente y límites

Dos revisiones originales del cambio cooperativo devolvieron CHANGES_REQUESTED;
se cerraron con evidencia en evaluacion-revision-final.md. El wrapper del review
adicional de auditoría no entregó VERDICT en dos intentos acotados: **NOT RUN**.
No se reintentó buscando conformidad. El PRIMARY decidió con guards exactos,
paridad, mutantes y gates reales. No se atribuye PASS a esa revisión fallida.

## Publicación y recuperación

Pendiente: Main local/remoto idénticos, ZIP limpio, verificación de manifiesto y
preflight obligatorio, merge nativo Supabase de solo las tres migraciones,
publicación por MCP Hostinger, smoke de bytes/versión y acceso básico,
eliminación del banco y sus credenciales privadas.

Hostinger: la prueba inicial forzaba un token antiguo del llavero y dio 401.
La sesión OAuth MCP ya configurada sí funcionó. No se cambió la configuración
MCP ni se pidió un token por chat.

Recuperación: ZIP anteriormente publicado
crm-20261016T184742Z-0d6aa930fe3b.zip, SHA-256
595bc1deeb84014b7813699b761e3346f34fdb317dd395dba2ff5f5f8c1d79be.
El paquete antiguo preparado desde d4d4750 no se publicó ni es el candidato final.
No se revierte SQL ni frontend automáticamente. La reversa conserva base_plazo
y los contratos 360 ya creados; cualquier rollback lo decide Miguel.

Las sesiones/PWA antiguas necesitan actualizarse: el servidor rechaza fechas
calendario de nuevas altas en lugar de guardar un vencimiento incorrecto.
Los borradores existentes no se reescriben silenciosamente. Una revisión de
Gerencia abierta durante el cambio puede requerir volver a abrir la fuente.
