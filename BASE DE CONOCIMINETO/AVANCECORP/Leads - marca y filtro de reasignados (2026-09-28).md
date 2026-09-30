# Leads: marca y filtro de reasignados (2026-09-28)

Pedido de Miguel: saber cuántos leads fueron reasignados, filtrarlos y ver una
marca en la fila y la ficha sin perder «Sistema»/«Manual». Relacionado con
[[Procedencia del lead - sistema o manual (2026-09-19)]],
[[Leads - filtro de origen (2026-09-16)]] y
[[Distribución de leads por capital y trazabilidad CRM]].

**Regla:** «Reasignado» indica trayectoria de asignación, no procedencia del
alta. Cuenta si hoy tiene analista y antes estuvo a cargo de un analista,
con evidencia en la actividad `reasignacion` y `vendedor_anterior` no nulo.
La primera entrega automática o desde la bandeja no cuenta. A → B, A →
bandeja → B y A → bandeja → A sí cuentan. Un lead aparcado sin titular actual
no figura en la cifra de reasignados. Sistema/Manual permanece como marca
separada: un lead puede ser «Sistema · Reasignado» o «Manual · Reasignado».

La migración `20260929195918_crm_leads_reasignados.sql` amplía la cartera
keyset con `p_reasignados`, `reasignado` por fila y
`resumen.totales.reasignados`. El conteo sale de la misma base filtrada que
los indicadores y la tabla, antes de paginar; respeta la RLS y se combina con
etapa, origen, procedencia, analista, búsqueda y fechas. La ficha relee por id
y comprueba su historial bajo RLS para conservar la marca si se abre desde
otra pantalla. En demo se aplica la misma regla al historial local.

**PUBLICADO 29/09/2026.** Migración `20260929195918` integrada por `merge_branch` desde el banco validado. Producción tiene 390 migraciones, función INVOKER de 12 argumentos, ACL `postgres/authenticated`, sello analítico vigente y huella de función `7169d94239dcb191bafa3faed46f916f`, idéntica al banco. La integración nativa separó el SQL en 16 sentencias sin sus separadores; los cuerpos no cambiaron (el hash del registro concatenado es distinto al archivo por ese formato).

Frontend en https://crm.miavance.com: `build-20260929T200401559Z`, fuente limpia `ec6eb4eb754ab5ff19f896564c29d7048c137348`, paquete `crm-20260929T200402Z-ec6eb4eb754a.zip`, SHA-256 `fd52c3c02b23a84f834f802d838ea0e3f3089792c7651163c8c52ddb35ede9c9`. Publicado mediante el cliente MCP oficial de Hostinger, con el token existente. Preflight y verificación del ZIP PASS. Smoke HTTP: 93 archivos (portada, versión, JS y CSS) devueltos con sus hashes exactos; portada HTTP 200. La primera petición con `curl --compressed` fue rechazada por 403; la descarga normal verificó todos los bytes. La automatización del navegador no arrancó por falta de su app-server local; no se acredita un recorrido autenticado en navegador productivo.

El rescate se construyó sobre el commit vivo y su árbol de `CRM-Avance-Corp/app` coincide al byte con la integración preparada desde `avancecorp/main` (árbol `7a28cafda631616b9337057293303abb062a6a32`). La integración incorpora el anexo que ya estaba publicado y los cambios de Reasignados; no arrastra la historia local ajena. La rama de prueba fue eliminada tras verificar producción. Las 22 Edge conservan exactamente su hash y configuración tras el merge.

## Verificación

- Base viva conservada: `ce9e688f28d43502c6ee66eac49a6a867774d25d`, build `build-20260929T164822097Z`; incluye anexo y cola v3 ya publicados. Copia aislada `rescue/reasignados-ce9`.
- `npm run check`: PASS, 317 archivos / 4909 tests, cobertura, tipos, build y bundle.
- Docker E2E completo: 285 PASS / 1 flaky / 26 omitidos. Se corrigió el selector heredado de Acceso Avance (el correo existía en aviso y resumen); repetición limpia del spec 3/3 PASS. El cambio solo afecta la prueba.
- SQL local `avc_leads_reasignados_test4`: PASS. Tipos generados: bloque completo de `cartera_filtrada_fn` idéntico al versionado.
- `check:scripts`: PASS de nuevo tras incorporar la corrección remota #132; preflights offline de seed/RLS PASS.
- Banco remoto propio `reasignados-banco-manual-20260929` (`goqrvtqfovrvxhlzlhzx`): migración nativa `20260929195918`, SHA-256 `67962db6cf5ff44c7452ee532ee3a955884af99a9ea8b46f67691cae2fcffbcc`.
- Oráculo SQL transaccional: PASS (primera entrega, A→A, A→B, bandeja, filtros, cursor, consumidor, roles y eventos no falsificables). Los leads ficticios previos se ocultan dentro de la misma transacción; ROLLBACK restaura todo.
- Matriz HTTP focal con sesiones reales: 272/272 antes y 272/272 después. Usa las funciones de la suite general para visibilidad, jerarquía, lecturas cruzadas, escrituras, trigger y cartera/keyset. El arnés declara su alcance; no sustituye la suite global.
- HTTP específico nuevo: 41/41; primera entrega no cuenta, reasignación real, siete roles, contador/filas, Sistema/Manual, paginación, anon y falsificación de eventos.
- Advisors: cero avisos nuevos de seguridad o rendimiento frente a la referencia.

La suite general original se detuvo en el origen ficticio `otro`, que el sistema vigente rechaza. La corrección oficial #132 (`a3711aed`) ya se incorporó. El banco necesitó configuración sintética de SLA/etapas, control SLA y gestión diaria para registrar contactos; esos prerrequisitos están resueltos. La suite global completa NO se acredita como PASS; la matriz pertinente anterior sí pasó completa.

## Fidelidad del banco y alcance de integración

El replay automático se detuvo en la migración histórica 86. Se reconstruyó exclusivamente nuestra branch vacía desde estructura productiva, siguiendo el precedente del proyecto; no se copiaron clientes reales. Se verificaron 1320 columnas, 850 funciones, 331 triggers, 106 policies, 131 tablas RLS, 477 índices y 3 vistas. Tres CHECK difieren solo en asociación de AND equivalente. Se alinearon 1427 privilegios explícitos y los ocho permisos predeterminados sobrantes del arranque.

Los 389 registros históricos coinciden íntegros con producción (hash `f1709d754ee3a02727e3b406288b722d`). Solo se añadió la migración de Reasignados. El cotejo posterior cambia exactamente una función: `cartera_filtrada_fn`. Las 22 Edge Functions tienen el mismo hash y configuración que producción. Los cron de la branch están desactivados. El banco costaba US$0,01344/h y fue eliminado al terminar (solo esta branch).

La revisión secundaria señaló policies ALL/permisos de escritura futuros; el preflight y postflight ahora los rechazan. No cambia RLS ni permite editar la marca: se deriva del evento sellado. Producción conserva sus datos y el frontend anterior puede seguir llamando la función con argumentos por defecto.

Hostinger funciona mediante la vía local documentada en [[Deploy a Hostinger]], usando el token ya guardado; no hace falta solicitar otro ni cambiar configuración. El paquete pasa el preflight de ascendencia y conserva el build vivo.

Evidencia privada (sin incluirla en el ZIP): `/private/tmp/reasignados-banco-remoto-20260929/`. El estado recuperable se guarda también en `CRM-Avance-Corp/releases/REASIGNADOS-20260929-ESTADO-ACTIVO.md`. El historial de primera branch fallida y eliminada corresponde al intento anterior, no al banco remoto vigente.
