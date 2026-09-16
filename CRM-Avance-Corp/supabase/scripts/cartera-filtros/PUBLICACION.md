# Filtros comerciales de Cartera publicados — 15/09/2026

El usuario aprobó el SQL exacto, la publicación y el banco temporal de hasta
US$1. Cartera → Inversionistas permite consultar por mes de cierre comercial,
empresa, moneda, estado, responsable, contacto y próximos vencimientos. El mes
actual de Lima aparece inicialmente. La distribución aprovecha el ancho de
escritorio y se adapta a móvil; conserva la ficha aprobada y los núcleos F5.

## Instalación y entrega

- SQL fuente `20260916023055_crm_cartera_filtros_comerciales.sql`, SHA-256
  `8164cdc4203999a916d494fe1c2149a499e553e5b9227f6012514f9b9458de86`.
- Merge de la rama autorizada como `20260916042954`: doce sentencias literales;
  297 entradas anteriores del historial intactas. Cambian únicamente el lector
  v1 y las dos funciones nuevas aprobadas. [Recibo](publicacion/instalacion.json).
- Contratos, inversiones, identidades y banderas conservaron sus huellas.
  [Comparación](publicacion/datos-y-banderas.json). Los 20 Edge se preservaron:
  18 bundles idénticos y dos reempaquetados por Supabase con las 15 fuentes y
  configuraciones comparadas literalmente. Los valores/digests de 14 secretos
  productivos permanecen iguales; solo cambió la fecha de siete administrados.
  [Evidencia Edge](publicacion/edge.json).
- ZIP `crm-20260916T035915Z-a09ecad9aaed.zip`, SHA-256
  `1adbd4b31dc413e87d55a7de062da2dfc70020698ded81dc9b27709441896c1c`.
  Construido desde copia limpia de `a09ecad9aaedc99560f46d6bf42a96dc3b90b6ea`;
  Main local, avancecorp/main y ls-remote iguales antes de publicar mediante el
  MCP oficial de Hostinger. Build `build-20260916T035613621Z`.
- 91 recursos HTTP 200; los 78 de código/configuración coinciden byte a byte.
  Hostinger optimiza algunas imágenes. [Comprobación web](publicacion/frontend-http.json).
  El artefacto incluye los cambios de Main anteriores a estos filtros.
- El archivo histórico del build anterior no estaba en el inventario local.
  Se reconstruyó desde `6e01cb7` fijando su build ID y se cotejaron sus 91 recursos
  con el sitio vivo antes de publicar: mismo código, estilos y configuración.
  ZIP/manifiesto conservados en `releases/`, fuera del control de versiones;
  no se hizo pasar un respaldo inventado por el original.
  [Prueba del respaldo reconstruido](publicacion/respaldo-http.json).

## Verificación

PASS local: 3632 pruebas, 247 archivos, cobertura de líneas 78,92 %; lint,
typecheck, configuración de release, build, bundle, duplicación y preflights
backend. 26 recorridos E2E con API simulada. El commit de implementación recoge
el dictamen original de Claude y la [evaluación de sus hallazgos](evaluacion-claude.md).

PASS remoto: [17 grupos SQL](publicacion/pruebas-sql-remotas.txt) sobre las mismas
fixtures sintéticas del banco local; [siete comparaciones completas de v1](publicacion/compatibilidad-remota.json)
tras instalación, reversa y reinstalación, con propietario y ACL iguales.
[20 comprobaciones HTTP](publicacion/auth-http.json), incluyendo seis sesiones
GoTrue reales de usuarios ficticios, ámbitos, moneda, mes, v1, cliente/anónimo,
service_role y el candado F5 con el mismo token. P0409 conserva el HTTP 500 que
devuelve actualmente PostgREST; se verificó código y ausencia de datos.

La baja directa de un vendedor con dependencias fue rechazada por el candado
existente. No se deshabilitó ese candado para simular una baja. La comprobación
HTTP final de revocación ejercita F5 OFF; no acredita el flujo administrativo
de desactivación de un analista. Los rechazos por rol inactivo se cubren en SQL.

PASS producción: v1/v2 conservan total y el mes septiembre devuelve fechas
coherentes en las [23 cuentas activas](publicacion/roles-produccion.json):
18 vendedores, tres supervisores y dos Gerencia. Contexto SQL authenticated,
transacciones ROLLBACK; no son sesiones humanas de navegador.

Advisors remotos: [delta revisado](publicacion/advisors.json). Una RPC adicional
authenticated SECURITY DEFINER es intencional y revalida permiso, bandera y
ámbito en el núcleo. El wrapper v1 pasa de PL/pgSQL a SQL sin cambiar owner/ACL.
Se conservan las advertencias heredadas; no se declara cero WARN remoto.

NOT RUN: navegación autenticada humana en producción y matriz RLS general
heredada. Se ejecutaron E2E locales y la matriz específica SQL/Auth/HTTP del
cambio. No se modificaron los cálculos financieros ni los permisos de tablas.

## Banco y reversa

El arranque remoto falló al reproducir migraciones históricas. Se reconstruyó
el esquema vigente sin datos reales, se igualaron permisos, historial, políticas
Storage y trigger Auth y se apagó Cron en el banco. Las seis diferencias de
catálogo administradas o de representación están [documentadas](publicacion/paridad-banco.json).
La semilla SQL requería completar instancia, tokens vacíos y fechas de usuarios
e identidades antes de poder probar GoTrue; la corrección fue exclusiva del banco.

Banco `ymyynhxwuotwwywpezfp` eliminado y ausencia confirmada a las
**2026-09-16 04:54:36 UTC** (15/09 23:54:36 Lima). Coste estimado
**US$0,01496**, máximo autorizado US$1; no es una factura. Se conservaron las
ramas ajenas. [Recibo de cierre](publicacion/banco-cerrado.json).

Reversa preparada: restaurar primero el frontend anterior y después ejecutar
`reversa.sql` siguiendo el procedimiento SQL autorizado. Las pestañas anteriores
pueden seguir usando v1 durante la actualización. La publicación no sustituye
las conformidades humanas/financieras del plan principal.
