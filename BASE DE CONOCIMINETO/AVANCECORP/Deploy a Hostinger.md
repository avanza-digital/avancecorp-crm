# Deploy a Hostinger

Desde el **2026-06-10** el deploy del portal ya **no es manual**: Claude puede desplegar directo con el **MCP de Hostinger** (Miguel instaló el token de la API).

## Procedimiento (vía MCP)

1. Armar un ZIP de **todo** `public_html/` (fuente única) excluyendo contenido local: `CLAUDE.md`, `.git/`, `.claude/`, `.codegraph/`, `.gitignore`, `.DS_Store`, `tests/`, `node_modules/` y artifacts que empiecen con `_` **solo en la raíz**.
   - En `rsync`, usar `--exclude='/_*'`, con la `/` inicial. **Nunca** `--exclude='_*'`: ese patrón también elimina `js/admin/_helpers.js` y rompe los módulos administrativos en una sesión sin caché.
   - Antes de comprimir, exigir `test -f "$stage/js/admin/_helpers.js"`; después, confirmar con `zipinfo` que el ZIP contiene `js/admin/_helpers.js`.
2. Desplegar con la herramienta `hosting_deployStaticWebsite` al dominio **miavance.com** (root: `/home/u318796122/domains/miavance.com/public_html`).
3. Verificar en vivo:
   - `curl https://miavance.com/service-worker.js` → `CACHE_VERSION` debe ser la versión nueva.
   - Spot-check de los archivos cambiados (HTTP 200).
   - Confirmar que el ZIP **no** quedó accesible públicamente (debe dar 404).
   - **Verificación fuerte (recomendada):** contrastar el md5 de CADA archivo del ZIP contra `https://miavance.com/<ruta>`. Solo deberían "diferir" los archivos que cambiaste.
   - ⚠️ **Dos falsos positivos permanentes de ese método** (2026-08-17): (1) `.htaccess` responde **403** —usar `-w %{http_code}`, porque `curl -f | md5` devuelve el md5 del vacío y parece una diferencia real—; (2) las **15 imágenes de `img/`** siempre difieren: Hostinger las **sirve optimizadas** (más pequeñas que el original en disco). Ninguna de las dos es drift.

## ⚠️ Regla del `?v=` — OBLIGATORIA al cambiar cualquier JS del portal

Los módulos del portal se importan con query de versión (`auth.js?v=20`, `login.js?v=22`…) y los
navegadores cachean por URL COMPLETA. **Cambiar el contenido de un JS sin subir su `?v=` = los
usuarios siguen con la copia vieja** aunque el server ya sirva la nueva. Ya mordió 2 veces
(2026-05-07 con `auth.js?v=7`, y 2026-07-16 con el cierre de la puerta del analista).

Al cambiar un JS: (1) subir el `?v=` en TODOS sus importadores (otros JS **y** los `<script>` de
los HTML — el import es en cadena: HTML→page.js→auth.js, cada eslabón cachea); (2) usar un número
VIRGEN (nunca reutilizar uno ya publicado); (3) bump del `CACHE_VERSION` del SW; (4) tras el
deploy, purgar la caché del hosting (`hosting_clearWebsiteCacheV1` — LiteSpeed sirve versiones
mezcladas hasta la purga) y verificar con 3 lecturas consecutivas del sha.

## CRM (crm.miavance.com)

Mismo mecanismo, dominio distinto (**2026-07-10**, primer update por esta vía):

1. Desde `CRM-Avance-Corp/`, ejecutar `npm run release:crm`. Construye la app y genera en `releases/` un ZIP del **contenido** de `dist/`, su manifiesto, hashes por archivo y SHA-256 del paquete. Por defecto exige un commit limpio.
   - Un worktree limpio **no trae los archivos ignorados**, incluido
     `app/.env`. Antes de construir, comprobar que existen
     `VITE_SUPABASE_URL` y una llave pública/anon del project ref esperado;
     rechazar `service_role`, `sb_secret` o cualquier llave privilegiada.
   - Auditar el ZIP, no solo el árbol fuente: debe contener el project ref y
     exactamente la configuración pública esperada, nunca secretos. La preview
     debe mostrar el acceso con cuenta habilitado antes de autorizar el deploy.
2. Verificar antes de desplegar: `npm run release:crm:verify -- releases/<release>.manifest.json`. Conservar ese release y el anterior fuera del web root. Resolver además el build que está vivo a su último manifiesto y exigir `git merge-base --is-ancestor <commit-vivo> <commit-candidato>`: si devuelve distinto de cero, ambas ramas son paralelas y deben integrarse antes de construir. Un artefacto limpio no prueba por sí solo que contenga todo lo que ya estaba publicado.
3. `HOSTINGER_API_TOKEN="$(cat ~/.hostinger_token)" node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs deploy crm.miavance.com <zip>` — la tool resuelve el usuario del subdominio sola.
4. Verificar: HTML en vivo referencia los hashes del build nuevo · asset nuevo responde 200 · el ZIP da 404 en `crm.miavance.com/` y en `miavance.com/` · smoke visual (login carga, sin errores de consola). El 404 del ZIP es una protección esperada; la trazabilidad vive en el manifiesto local persistente.

- El **token** vive en `~/.hostinger_token` (chmod 600, fuera del repo). Si se rota en hPanel, actualizar ese archivo.
- El CRM **no usa service worker**: no hay `CACHE_VERSION` que bumpear; el cache-busting lo hacen los hashes de Vite.

## Notas

- **Deploy 2026-09-04 (~14:50 hora de Lima) — CRM: desglose de entregas por
  fecha, analista y origen para Coordinación:** amplía el reporte de
  **Repartir leads → Distribución** con filtros combinables de supervisor,
  analista y origen, períodos Ayer/Últimos 7/Rango, resumen filtrado, tabla
  paginada y separación explícita frente a la cartera actual. La base salió
  primero: migración
  `20260904174534_crm_reporte_derivaciones_origen_coordinacion`, registrada
  con cuerpo exacto (MD5 `b2fa0249f50f64e4db72a08cd1b8968e`) después de
  ensayar migración, oráculo y reversa en `banco-f7`; sonda autenticada de
  producción confirmó contrato, conciliación, ACL, ausencia de PII de leads e
  índice. Commit **`d75be7b5d8d3`**, release
  **`crm-20260904T194458Z-d75be7b5d8d3`**, build
  **`build-20260904T194456335Z`**, ZIP SHA-256
  **`91dd6ee84d4225f74c948192aed50d800c66d7eb57c68066cd18e6e37b40d79a`**.
  Gate: 189 archivos y **2.648/2.648 pruebas**, lint, tipos, build, bundle y
  duplicación; Repartir **29/29** en Playwright. En vivo: **76/76** entradas
  verificadas (63 exactas, 12 imágenes HTTP 200 y `.htaccess` 403), versión
  estable, ZIP 404 en CRM y portal; login visual HTTP 200 sin errores de
  consola, página ni red. Se purgó la caché y el entry anterior
  `index-hhe_-52_.js` pasó a 404. **Rollback frontend inmediato:**
  `crm-20260904T194617Z-41a24d3bb98a.zip`. Respaldo privado de BD:
  `releases/rollback-20260904174534-predeploy.sql`, SHA-256
  `0424d4b7f73e5d462606d3e40df8611064157f44b52718426d5a02147afe4750`.

- **Deploy 2026-09-04 (~11:14 hora de Lima) — CRM: reporte diario de
  derivaciones para Coordinación:** en **Repartir leads → Distribución**, la
  coordinadora puede consultar cuántos leads entregó cada supervisor a cada
  analista por día, con Ayer, Últimos 7 días o rango manual. Backend agregado
  sin PII y basado en el ledger; Coordinación/Gerencia permitidas y Supervisión
  denegada. Migración `20260904153431_reporte_diario_derivaciones_coordinacion`
  aplicada y registrada por cuerpo completo; advisors sin errores. Commit
  `dc6c83e5aa37`; release
  **`crm-20260904T161303Z-dc6c83e5aa37`**, build
  **`build-20260904T161302294Z`**, ZIP SHA-256
  **`007e61bbd1204b286dfbb46155e1c8a4851703878e3e873a92ae3f284bc7eae6`**.
  En vivo: 76/76 entradas verificadas (61 exactas, 14 imágenes 200 y
  `.htaccess` 403), tres lecturas consecutivas del build, portada 200 y ZIP
  404 en CRM y portal. No había navegador conectado para el smoke visual;
  2.644/2.644 pruebas y el bundle vivo byte a byte cubren la entrega.
  **Rollback frontend:** `crm-20260903T230001Z-4b18f42edfa0.zip`. Respaldo
  privado previo: `releases/reporte-derivaciones-predeploy-20260904.sql`,
  SHA-256
  `dd86370aa674f056bc33f046ea5e93a57aeb75939b148c05ce3711588b4d109c`.

- **Deploy 2026-09-03 (~18:00 hora de Lima) — CRM: el capital estimado deja de
  colapsar en la ficha del lead:** hotfix exclusivamente de frontend. El
  wrapper `w-full` del selector de moneda reclamaba toda la fila flexible y
  reducía el input del monto a unos pocos píxeles. El ancho fijo ahora vive en
  el flex-item real, Capital ocupa la fila completa y las parejas de campos se
  apilan en viewport estrecho. Commit `4b18f42edfa0`. Gate limpio: 188 archivos,
  **2.638/2.638 pruebas**, lint, tipos, build y bundle; regresión E2E real a
  390×844 con monto ≥120 px, moneda ≥80 px, sin solape ni desborde. Release
  **`crm-20260903T230001Z-4b18f42edfa0`**, build
  **`build-20260903T230000818Z`**, ZIP SHA-256
  **`8b18c23a96b70b78abe1abfee209dd7e5808c3305da360e8563131bca26c6309`**.
  En vivo: 75/75 entradas verificadas (62 exactas, 12 imágenes 200 y
  `.htaccess` 403), tres lecturas consecutivas del build, login visual correcto
  y ZIP 404 en CRM y portal. `miavance.com` siguió 200 y sin el build del CRM.
  No hubo cambios de SQL, datos, RLS ni Edge Functions. **Rollback:**
  `crm-20260903T223116Z-7f6e1d4b2961.zip`.

- **Deploy 2026-09-03 (~17:31 hora de Lima) — CRM: capacidad única para
  convertir leads:** corrige a los usuarios creados desde Gerencia con la
  combinación válida `comercial + vendedor`, sin cambiar roles ni recrear
  cuentas. PostgreSQL es ahora la fuente única de la capacidad
  `puede_contratar`; frontend, cuatro puertas SQL y las Edges dejan de mantener
  allowlists divergentes. Commit de código `7f6e1d4b2961`; migración
  `20260903215149_crm_capacidad_conversion_unica`, con cuerpo completo
  registrado y postflight productivo verde. Identidad real
  `comercial + vendedor`: `true`; Coordinación: `false`, en prueba de solo
  lectura con `ROLLBACK`. Advisors: cero errores. Edges activas con JWT:
  `crm-convertir-lead` v13 y `crear-cliente` v32; `OPTIONS` 200 y POST sin
  sesión 401. Release **`crm-20260903T223116Z-7f6e1d4b2961`**, build
  **`build-20260903T223115104Z`**, ZIP SHA-256
  **`c06b2332890583022676355f85046405157c1ef8f2191a0fb6d7c65972a48b00`**.
  Gate limpio: 188 archivos, 2.637/2.637 pruebas, 49/49 Edge, 5/5 Deno,
  tipos, lint y build. En vivo: 75/75 entradas verificadas (62 exactas, 12
  imágenes 200, `.htaccess` 403), tres lecturas consecutivas del build, login
  visual correcto y ZIP 404 en CRM y portal. `miavance.com` respondió 200 y no
  contiene el build del CRM. No se ejecutó una conversión autenticada real para
  no crear un cliente productivo; la autoridad quedó ejercitada con identidad
  real en transacción revertida. **Rollback frontend:**
  `crm-20260903T164522Z-f767a5f976f5.zip`. Respaldo privado previo:
  `releases/p058-predeploy-crm-private-20260903.sql`, SHA-256
  `7d537830fe8754d0189dcf011ab2df8c023a6e9cecf5fc5053a83becc1f7cdf9`.
  Detalle en [[Capacidad única de conversión de leads (2026-09-03)]].

- **Deploy 2026-09-02 (~09:54 hora de Lima) — CRM: rankings históricos por mes
  calendario:** Gerencia y Supervisión seleccionan agosto sin perder la meta
  mensual; Conversión, Capital total y Cosecha comparten el mismo mes, alcance
  y foto histórica. El mes vigente conserva el roster vivo. Los USD históricos
  usan los últimos siete días publicados por BCRP hasta el cierre del mes.
  No se crearon RPC, tablas ni Edge Functions paralelas: se reemplazaron dos
  núcleos existentes, `crm.cumplimiento_metas_fn` quedó intacta y la Edge
  existente `crm-tipo-cambio` pasó de v7 a v8 con `verify_jwt=true`. Commit
  publicado desde `main` hacia `avancecorp/tronco`: `5b1c808f9138`;
  migración `20260902070052_crm_ranking_poblacion_mes_calendario`. Release
  **`crm-20260902T145408Z-5b1c808f9138`**, build
  **`build-20260902T145407204Z`**, ZIP SHA-256
  **`3b7797c1f57c939fc7d6b362337a3f3e7082ae3229d3a9a5be90fae001d01132`**.
  Gate: 2.524/2.524 unitarias; E2E 113 aprobadas, 26 omitidas y 0 fallidas;
  focal Gerencia/Supervisión 9/9; Edge 30/30 Node y 5/5 Deno; Advisors sin
  errores. `CRM app quality` quedó verde (`33644821968`). El primer preflight
  RLS detectó que Deno no instalaba en limpio una dependencia transitiva de los
  tipos de Supabase; `eca2dcb85cef` fijó el lock y el modo auto+frozen sin tocar
  runtime, y el rerun `33646311542` terminó verde. Oráculo productivo: Gerencia
  agosto 16/16/16 y setiembre 17/17/17;
  Supervisor agosto 8/8/8 y setiembre 10/10/10. En vivo: 62/62 archivos de
  código idénticos, 12/12 imágenes 200, ZIP 404 y asset anterior 404. La sesión
  de navegador disponible era de reparto: verificó el build y el guard de rol,
  mientras las vistas autenticadas se cubrieron por E2E y consultas con
  identidad real. **Rollback inmediato frontend:**
  `crm-20260902T060243Z-5c208ad9bf31.zip`; rollback SQL y Edge v7 constan en
  [[Rankings por mes calendario (decision 2026-09-02)]].

- **Deploy 2026-09-02 (~01:03 hora de Lima) — CRM: rankings de supervisión y
  gerencia reconectados a sus núcleos canónicos:** cambio solo de frontend,
  sin RPC, función SQL, migración ni cálculo paralelo. Cada pestaña usa su
  fuente autoritativa y conserva carga, error y reintento independientes;
  Gerencia deja de depender de `crm.metricas_conversiones_fn` para componer el
  ranking. Commits en el `main` local y publicados a su espejo correcto
  `avancecorp/tronco`: `2d1cd0c` (documentación multiempresa) y `5c208ad`
  (ranking). Release **`crm-20260902T060243Z-5c208ad9bf31`**, build
  **`build-20260902T060242726Z`**, ZIP SHA-256
  **`a5c942832ba452a540653c79c8464bd4e16cdb7a0b5fce5983eae5871a3e72d1`**.
  Gate limpio: 184 archivos / 2.495 pruebas, lint, TypeScript, cobertura,
  build, bundle y duplicación; el pre-push repitió 2.495/2.495. El ZIP contiene
  el project ref esperado, una llave `anon` y cero credenciales privilegiadas.
  Preflight: el candidato desciende del vivo `75c03d0`. En producción, 60/60
  archivos no transformados coincidieron por SHA-256, 14/14 imágenes
  respondieron 200, `.htaccess` 403, ZIP 404 en CRM y portal y el bundle viejo
  quedó 404 después de purgar caché. Smoke autenticado de Gerencia: ranking de
  17 analistas cargó sus tres pestañas con datos y cero errores de consola.
  **Rollback:** `crm-20260902T033133Z-75c03d0c0ee1.zip`. Detalle en
  [[Ranking de conversion del supervisor (RPC pendiente)]].

- **Deploy 2026-08-31 (~16:49 hora de Lima) — CRM: restauración de la Ficha
  360 sobre el release vivo:** el build del 30/08 provenía de una rama paralela
  y sustituyó la ficha completa por el detalle básico. Se integraron ambos
  historiales en el merge `f6dd76f` (padres `c9d875b` + `e8ac426`) y se publicó
  **`crm-20260831T214847Z-f6dd76fa5b7b`**, build
  **`build-20260831T214847197Z`**, ZIP SHA-256
  **`38b916999bef740f8d5b811ebed58865276234dd57311e5b0b06fc407e4f9661`**.
  Gate: 184 archivos y 2.492/2.492 pruebas, 145 focalizadas y E2E de Ficha 360
  6/6; lint, tipos, cobertura, build, bundle y duplicación en verde. En vivo,
  HTML, versión, JS/CSS principal, Mi cartera y cliente API coinciden byte por
  byte; ZIP 404 en CRM y portal. El empaquetado exige ahora las tres secciones
  distintivas de la ficha y la herramienta de deploy rechaza ramas que no
  desciendan del release vivo. Detalle en
  [[Incidente y restauracion Ficha 360 2026-08-31]].

- **Deploy 2026-08-27 (~16:17 hora de Lima) — CRM: terminología visual de citas:**
  cambio exclusivamente de frontend: toda la interfaz presenta **cita / citas**,
  mientras conserva internamente `reunion`, `reunion_agendada`, rutas, métricas,
  RPC, campos y textos históricos. Una segunda auditoría cubrió también títulos
  heredados escritos `Reunion` sin tilde y añadió una aserción E2E de ausencia
  del término viejo en el drawer. Release final
  **`crm-20260827T211722Z-722a7477cab1`**, build
  **`build-20260827T211722350Z`**, ZIP SHA-256
  **`b4f95732841b0dce2b341294b20487e7545803587e6c148a7ed0451d743d5998`**.
  Gate: 2.344/2.344 pruebas, E2E focalizado 11/11, TypeScript, lint y build en verde (solo cuatro
  warnings a11y preexistentes en `coverflow-carousel.tsx`). En vivo: `version.json`
  correcto; HTML, versión, JS/CSS principal y chunks de Agenda, Alertas, Hoy,
  Gerencia y Mi cartera coinciden byte por byte; ZIP 404 en CRM y portal.

- **Deploy 2026-08-25 (~10:04 hora de Lima) — CRM: 38.º release, cierre de la
  segunda regresión (RETOMAR-55):** publica el merge **`b3f6e98`** =
  `90b90e2` (supervisor F4.4, el 37.º) + `f924b91` (portada del vendedor
  «Ahora y Después» + paginación de Derivar + teléfono alternativo), cero
  archivos solapados y ambos padres ancestros — la regla de ascendencia del
  ledger, esta vez aplicada. El artefacto es EL MISMO construido y verificado
  la noche anterior (Miguel paró aquella subida a la mitad; prod nunca se
  movió): release **`crm-20260825T005045Z-b3f6e98f9f15`**, build
  **`build-20260825T005045176Z`**, ZIP SHA-256
  **`402b1d9c7e0c5d0ca8adc86e4b43ae430f3abbb4496e114936a44693b89f47fc`**,
  gate 2.243/2.243 + E2E 9/9. **Secuencia de hoy:** SHA-256 del ZIP re-
  verificado; señales y llave re-confirmadas DENTRO del ZIP; `version.json`
  vivo seguía en `build-20260824T182716934Z` (nadie publicó en paralelo);
  primer intento 429 de Hostinger, aceptado al reintento tras 90 s
  (`removeArchive:false`, copia en `releases/` conservada). **En vivo:**
  `version.json` = build nuevo a la primera lectura; **58/64 archivos al
  byte** contra el ZIP — las 6 diferencias son exactamente los falsos
  positivos permanentes (`.htaccess` 403 y 5 PNG optimizados por el CDN);
  `hoy-DNJIiTvG.js` contiene las 5 señales del vendedor («Tu siguiente
  movimiento» · «Después en tu agenda» · «Tu cartera en contexto» · «Hoy,
  tres cosas» · «Nuevo aquí»); `derivaciones-L48j9Z25.js` 200; ZIP 404 en
  CRM y portal. El `index-BTHZ7kln.js` del build anterior aún responde 200
  **solo desde el edge del CDN** (`x-hcdn-cache-status: HIT`, age ~14 h):
  asset inmutable con hash, no es drift y nada lo referencia. Rollback
  inmediato: `crm-20260824T182717Z-90b90e280479` (37.º — pero vuelve a
  quitar la portada del vendedor; el rollback SANO completo es este mismo
  38.º). Ver episodio 2 en [[Hoy del vendedor - Ahora y Después]].

- **Deploy 2026-08-23 (~15:02 hora de Lima) — CRM: «Ahora y Después» del
  vendedor, integrado con la F3 viva del supervisor:** Miguel autorizó
  explícitamente publicar `04dc37e`. Ese primer artefacto sí puso en producción
  la nueva jornada del vendedor, pero el smoke detectó una regresión de línea
  base: `04dc37e` y `fdcd4d1` eran ramas hermanas nacidas en `71c068f`, por lo
  que el chunk vivo ya no contenía «Hoy, tres cosas». Se corrigió antes de
  cerrar: worktree aislado sobre `fdcd4d1`, cherry-pick limpio de `04dc37e` y
  ajuste del selector E2E ambiguo (`Hoy` vs. «urgente hoy»). El resultado es
  **`c79d54a`**, que conserva la F3 del supervisor y añade **Ahora / Tu
  siguiente movimiento**, máximo tres decisiones sin duplicar leads, Después,
  contexto de cartera y cumplimiento mensual progresivo del vendedor. **Sin
  tablas, migraciones, RPC ni cambios de RLS.** Gate combinado: **2.166/2.166
  pruebas**, lint, TypeScript, cobertura, build, bundle y duplicación en verde;
  pruebas dirigidas supervisor+vendedor **80/80**; E2E por rol **9/9**, incluidos
  teclado, retorno de foco, móvil 390×844, targets de 44 px y ausencia de
  desborde. Release **`crm-20260823T195728Z-c79d54acdcd2`**, build
  **`build-20260823T195727965Z`**, ZIP SHA-256
  **`e09b335dd4964bcd84b7d7e45ea7fa134b8875f3f91420fc7c54014b484b04af`**,
  `worktree_sucio:false`, `removeArchive:false`. En vivo: portada/version/nuevo
  index 200; los dos indexes anteriores 404; ZIP 404; `.htaccess` 403;
  **58/58 archivos públicos no transformados coinciden byte a byte** con el
  manifiesto. Los cinco PNG difieren por la optimización automática del CDN,
  pero el árbol remoto conserva exactamente sus tamaños originales. El chunk
  vivo `hoy-D-gsKlkB.js` contiene simultáneamente «Hoy, tres cosas» y todas las
  señales de «Tu siguiente movimiento». El smoke autenticado tuvo dos fallos
  transitorios de sesión/datos y recuperó al reintentar; al final el supervisor
  cargó datos reales, la región F3 quedó visible y una ventana estable no
  registró errores nuevos. No había una sesión real de vendedor disponible: su
  runtime vivo queda probado por hash+strings del chunk y los E2E; la validación
  humana con vendedores sigue pendiente. Rollback recomendado:
  `crm-20260823T192043Z-fdcd4d17abdf` (conserva supervisor F3); el intermedio
  `crm-20260823T192806Z-04dc37e1c7ac` no debe usarse como rollback porque vuelve
  a quitar esa F3. **Lección operativa:** antes de desplegar ramas paralelas,
  probar la ascendencia del commit vivo, no solo la limpieza del candidato.

- **Deploy 2026-08-23 (~14:25 hora de Lima) — CRM: «Hoy, tres cosas» (F3):**
  Miguel autorizó el deploy al terminar la auditoría («ok cuando termine hace
  deploy»). **Alcance (solo interfaz):** franja navy sobre los KPIs con ≤3
  intervenciones del día (`lib/tres-cosas.ts` pura: rojo primero, determinista,
  sin dato no hay tarjeta; «Ver →» salta a la pestaña de la cola con el foco);
  el KPI «Nuevos sin responder» pierde su último rojo. **Auditorías
  aplicadas:** Codex F3 (0 bloqueantes; 5 importantes + 1 menor: severidad
  alineada con RPC/campana — un nuevo fresco es ámbar, sin acción ≥5 crítico —,
  la fila del propio supervisor no ocupa cupo, «50+» al tope, coherencia
  franja↔campana documentada como misma-decisión/lentes-distintas, mutantes
  muertos) y revisor-a11y (A1: severidad también en texto «urgente hoy / esta
  semana» + `SEMAFORO_SOBRE_NAVY` con tonos claros — el rojo normal daba
  2.53:1 sobre navy). Commit **`fdcd4d1`** (worktree
  `/private/tmp/crm-hoy-sin-ruido`). Gate: **2.160 pruebas**, check exit 0,
  `ARTEFACTO_OK`. Release **`crm-20260823T192043Z-fdcd4d17abdf`**, build
  **`build-20260823T192043536Z`**, ZIP SHA-256
  **`95291fb43dc95bc8973ff30643ab5035130a44fe2fa2111fd04bc0e4efdb6d1b`**
  (copiado a `releases/` del árbol principal ANTES de desplegar, y
  `removeArchive:false` — la trampa del deploy anterior). En vivo: portada
  200, `version.json` correcto, **7/7 archivos byte a byte contra el ZIP**
  (`index-D8_f07q4.js`, `index-C9Mc0ci3.css`, `hoy-DjzHlIME.js`, alertas,
  repartir); el chunk de HOY contiene «Hoy, tres cosas», «urgente hoy» y
  «esta semana»; ZIP 404. Rollback inmediato:
  `crm-20260823T182815Z-71c068f9b054`. Con esto las FASES 1–3 del rediseño
  están completas en producción; queda F4 (reconocer, toca servidor) y F5
  (prueba de usabilidad real).

- **Deploy 2026-08-23 (~13:40 hora de Lima) — CRM: «Hoy del supervisor, sin
  ruido», Fases 1 y 2:** Miguel aprobó visualmente el rediseño en local
  (demo de supervisor) y lo publicó con `/release-crm`. **Alcance (solo
  interfaz, sin SQL/RPC/Supabase/portal):** F1 — la campana del supervisor
  agrupa POR DECISIÓN (≤4 grupos: bandeja · nuevos sin responder · plazos
  vencidos · vendedores sin acción; cada lead cuenta una vez y el grupo hereda
  la severidad más alta), «Leads sin movimiento» deja de ser tarjeta y pasa a
  pestaña de «Cola del equipo» (Urgente · Sin movimiento · Todo, con teclado),
  y el rezago de agenda vive solo en «Tu equipo hoy». F2 — presupuesto de
  color: severidad en tira de 3 px, bucket/«sin asignar»/montos en texto gris,
  KPIs neutros (solo «Nuevos sin responder» conserva rojo hasta F3), único chip
  rojo «N no asistió» en solid por contraste AA. **Auditorías:** Codex F1
  (8 hallazgos, 1 bloqueante: la bandeja hereda la criticidad de una tarea
  vencida ≥24 h), Codex F2 (1 importante: el rezago de agenda también enciende
  el punto; 4 menores) y revisor-a11y (anillo de foco en filas, gris fuerte en
  pestañas, Home/End) — TODO aplicado y sellado con pruebas. Construido en el
  worktree aislado `/private/tmp/crm-hoy-sin-ruido` (rama
  `feat/hoy-supervisor-sin-ruido`, commits `d0931db`→`6e3fb0d`→`71c068f`, el
  primero commitea el reparto compacto que estaba vivo sin commit). Gate:
  **2.140/2.140**, lint, TS, cobertura, build, bundle y duplicación en verde;
  `release:crm:verify` OK. Release **`crm-20260823T182815Z-71c068f9b054`**,
  build **`build-20260823T182815099Z`**, ZIP SHA-256
  **`935c3e21be389c31d187fc82756581e464a4fc23d7d1817164fc9fe9cbff2858`**.
  Un 429 de Hostinger en el primer intento; el segundo, tras 75 s, aceptado.
  En vivo: portada 200 y **8/8 archivos clave byte a byte contra el ZIP**
  (`index.html`, `version.json`, `index-2vco1tXu.js`, `index-Cawf09wt.css`,
  `hoy-6dYgfiVx.js`, `alertas-BaOvTJ-K.js`, `data-vendor`, `repartir`); ZIP
  404, `.htaccess` 403, asset inexistente 404. ⚠️ Dos lecciones operativas:
  (1) `removeArchive: true` de `hosting_deployStaticWebsite` **borra el ZIP
  LOCAL de origen** — conservar siempre la copia en `releases/` del árbol
  principal ANTES de desplegar; (2) el `dist/` local deja de ser comparable
  tras re-correr `npm run check` (rebuild con hashes nuevos): la comparación
  válida del vivo es contra el **ZIP del manifiesto**, no contra `dist/`.
  Rollback inmediato: `crm-20260823T151159Z-94fd5304e5a3`. Queda F3 («Hoy,
  tres cosas») y F4 (reconocimiento, toca servidor). Ver
  [[Fundamentos UX del CRM]] y [[Hoy del supervisor - reparto compacto]].

- **Deploy 2026-08-23 (~10:20 hora de Lima) — CRM: reparto compacto en HOY del
  supervisor:** Miguel aprobó visualmente el cambio local y pidió publicarlo.
  **Alcance:** la tarjeta `Por repartir` concentra el conteo autoritativo del
  servidor, el rezago observable y el CTA hacia `#/derivaciones`; con cero queda
  como acceso neutral y sin resumen muestra `—`; desaparecen de HOY la bandeja
  grande, los selectores y los botones de asignación. La operación completa
  sigue en Derivar leads. **Sin SQL, RPC, Supabase ni portal.** Para no arrastrar
  el trabajo paralelo del árbol compartido, se reconstruyó el último frontend
  vivo en un worktree aislado: antes del cambio, **67/67 archivos** coincidieron
  byte por byte con el manifiesto anterior. Solo después se copiaron los tres
  archivos del cambio. Gate: **2.133/2.133** unitarias, lint, TypeScript,
  cobertura, build, bundle y duplicación en verde; E2E específico de foco +
  Enter hacia Derivaciones en verde. Release
  **`crm-20260823T151159Z-94fd5304e5a3`**, build
  **`build-20260823T151131Z`**, ZIP SHA-256
  **`841570a22fea37b55da70ff556f31427e419e8737e3485c49cb392bf43fa652d`**.
  Hostinger limitó dos intentos de credenciales con 429 antes de recibir bytes;
  producción siguió en el build anterior hasta que el tercer intento, tras el
  enfriamiento, fue aceptado. En vivo: `index-CMrftHuS.js`,
  `index-D2ucvuxc.css`, `hoy-BZ3-HP8m.js`, `index.html` y `version.json`
  coincidieron con el manifiesto en **tres lecturas consecutivas**; el chunk de
  HOY contiene `Más rezagado`, `Bandeja al día` y `Ver derivaciones`, y ya no
  contiene `Por repartir — tu bandeja`. ZIP 404 en CRM y portal,
  `.vite/license.md` 404, `.htaccess` 403, CSP/HSTS intactos y assets principales
  anteriores 404; no hizo falta purgar caché. Rollback inmediato:
  `crm-20260821T233421Z-4335bb5f88e3`. Ver
  [[Hoy del supervisor - reparto compacto]].

> ⚠️ **Hueco conocido en este ledger.** Entre el 2026-08-10 y el 2026-08-15 hubo releases
> del CRM (al menos el de la conversión mensual del 11/08 —commit `c43036e`— y el de la
> anulación de cierres del 14/08 —`bbc9829`, ZIP `crm-20260814T215933Z-e1995d5d5eab`—) que
> **no se anotaron aquí**. Están en sus notas de tema y en `releases/`. Se deja dicho en vez
> de dejar el hueco mudo: un ledger con lagunas silenciosas es peor que uno que las declara.
> El hueco alcanza también los del **16-17 de agosto** (26.º-29.º: PDF v2, F1 lead libre
> 28.º `crm-20260817T151109Z-42f02cbdc1ca` y 29.º `crm-20260817T160102Z-cbc95900091f`):
> viven en `MIGRACIONES.md` (adendas 16-17/08), sus notas de tema y `releases/`.

- **Deploy 2026-08-18 (~18:10 UTC / ~13:10 hora de Lima) — CRM: F3.1, la auditoría doble
  del F3 aplicada entera (TRIGÉSIMO SEGUNDO release):** publica `7fb3118` y con él TRES
  commits: `75156a6` (F3.1 entero), `7fb3118` (soporte de compilación del reparto — ver
  abajo) y el vault `d2d2437`. **Lo que cambia:** la campana DICE sus fallos (mensaje +
  Reintentar real); la fecha vaciada avisa junto al campo; el estado del recordatorio
  queda ANCLADO al teléfono (ni un blur sin editar ni el DNI borran la fecha o la
  confirmación — muere la reprogramación silenciosa); candado por contacto a nivel de
  módulo (cerrar y reabrir no permite dos guardados); el «Guardando…» no disfraza a otro
  contacto; el foco tras Quitar se decide por la REALIDAD del dato con fallback al
  encabezado y el rescate en error va vía efecto (focus() sobre un disabled es no-op
  también en navegador real — bug destapado por su propio mutante); el dni viaja
  EXPLÍCITO en el upsert (sin DNI = limpiar el anterior, probado en frontera HTTP con
  MSW); la sugerida se acota al máximo; min/max con `useAhora`; la campana ya no pide el
  dni (§8). **14/14 mutantes muertos** — la caza destapó además que `blur()` y
  `body.focus()` son NO-OP en jsdom (dos aserciones de rescate pasaban con el rescate
  borrado; la simulación correcta del foco huérfano es `body.tabIndex=-1` + focus).
  Gate **2.053/2.053** (161 ficheros). **La trampa del ciclo — TERCERA sesión paralela
  (cola de reparto) activa sobre el árbol:** sus cambios a `crm-api.ts` (compartido)
  viajaron dentro de los commits F3/F3.1 y el worktree limpio del 32.º NO COMPILABA
  (import de `lib/ingresos-reparto` untracked + RPC fuera de types) → commit `7fb3118`
  registra las TRES piezas mínimas (lib + test + 1 línea de types); su pantalla,
  migración `20260818174456` (sin aplicar) y resto siguen EN CURSO sin commitear — y su
  trabajo NO está en este bundle (nunca estuvo vivo: nada se borra). Artefacto
  **`crm-20260818T181041Z-7fb31185d9f3`**, ZIP SHA-256 **`faf553c0…4978`**, llaves
  verificadas DENTRO (`crm-queries-FCvlSIZs.js`; el hit de «sb_secret/service_role» del
  barrido es el REGEX del guard de config.ts compilado, no una llave), vivo verificado
  ANTES de publicar (seguía el 31.º — nadie deployó en medio). Publicado por la tool MCP
  directa + purge. **En vivo:** `index-DSC-mTPn.js` + `crm-queries-FCvlSIZs.js` +
  index.html **AL BYTE (3/3)**, «Elige la fecha del recordatorio» (F3.1) y «Centro de
  ayuda» presentes en el asset servido, ZIP en 404. Decisiones de Miguel del ciclo:
  PII de la caducidad en audit_log → **deuda F4**; campana a las 09:00 y teléfono en el
  toast → **aceptados y documentados** en [[Verificación y toma de lead libre]].
  Rollback inmediato: `releases/crm-20260818T153614Z-1a8a51fb3c03.zip` (el 31.º).

- **Deploy 2026-08-18 (~15:36 UTC / ~10:36 hora de Lima) — CRM: «Recordarme revisar este
  contacto» (TRIGÉSIMO PRIMER release; F3 del plan «lead libre» COMPLETA — servidor en la
  madrugada, front ahora):** publica `1a8a51f` y con él DOS commits: `3d5b686` (registra
  el front del **Centro de ayuda** que la sesión paralela ya tenía VIVO en prod pero sin
  commitear) y `1a8a51f` (el F3 entero). **Lo que estrena:** sobre un ocupado SIN puerta
  (tomado/enfriamiento) el alta ofrece el mini-form «¿Quieres que te lo recuerde?» — nota
  personal con fecha sugerida (enfriamiento → día real de liberación; tomado → +7d
  editable), guardar = reprogramar (upsert del servidor); los vencidos suenan en la
  campana como «Revisar contacto» con **Verificar disponibilidad** (reabre el alta con el
  teléfono precargado: el MISMO circuito F1/F2) y **Quitar**. **Doble dictamen aplicado
  en el retomo:** a11y A1/M1–M4/N1–N3 (rescate de foco del mini-form — hallazgo: el foco
  huérfano de un botón desmontado NO cae a body, el FocusScope de Radix lo recoge en el
  panel del Dialog; grupo nombrado, error inline anclado, fechas/teléfonos legibles con
  «setiembre» de es-PE, foco al contador tras Quitar solo si la fila desaparece) y Codex
  R2–R6 (la campana respeta el gate `funcionesLeadsVisibles`; `max` = hoy+**364** en Lima
  porque el instante viaja a las 09:00 y el CHECK usa clock_timestamp+365d; invalidación
  ANTES del guard de montaje; secuencia anclada contra la respuesta tardía de otro
  contacto; el test de Quitar espía el queryClient real). **9/9 mutantes nuevos muertos**
  (una mutación a la vez, revert garantizado). Gate: **2.023/2.023** (158 ficheros) ·
  `tsc -b` limpio **SIN el filtro `ayuda_vendedor`** (el types del árbol ya trae esos RPC
  y su migración está en prod — el precedente del grep filtrado del 16/08 quedó obsoleto)
  · oxlint limpio. **El punto crítico del árbol compartido:** lo vivo era el bundle del
  Centro de ayuda y su front estaba untracked — publicar un worktree solo de mi commit lo
  habría BORRADO de producción; por eso el commit `3d5b686` primero, y se verificó por
  grep DENTRO del ZIP que el bundle conserva «Centro de ayuda» ANTES de publicar.
  Artefacto **`crm-20260818T153614Z-1a8a51fb3c03`**, ZIP SHA-256 **`197d2e0b…86e1`**,
  worktree git limpio (lo único sucio: el symlink de node_modules — `--allow-dirty`
  explícito, precedente RETOMAR-48) con `.env` copiado y llaves verificadas DENTRO
  (`crm-queries-vOeM8rl_.js`). **Publicado por la tool MCP de Hostinger DIRECTA**
  (`deployStaticWebsite`, cuenta `u318796122` verificada antes): el script casero exige
  `HOSTINGER_API_TOKEN` y el acceso al token quedó bloqueado en esta sesión — misma vía,
  un envoltorio menos. Autorización de Miguel en sesión (AskUserQuestion). **En vivo:**
  `index-B6VWJWhY.js` + `crm-queries-vOeM8rl_.js` + `index-a7hXt_lB.css` **sha256
  idéntico local↔prod (3/3)**, index.html al byte, y el cambio verificado por grep DENTRO
  del asset servido («Recordarme revisar» ✓ y «Centro de ayuda» ✓ — ambas funciones
  conviven); purga de caché vía MCP tras el deploy. Rollback inmediato:
  `releases/crm-ayuda-vendedor_20260818_012100.zip` (lo vivo hasta hoy — ⚠️ el 30.º
  `crm-20260818T044028Z-2bbedf6314f3` NO trae el Centro de ayuda: volver a él lo
  borraría). ⚠️ Para el vendedor real siguen faltando metas publicadas y el gate
  `FUNCIONES_LEADS_APROBADAS`; `crm.leads` sigue vacía en prod para la prueba visual.
  Detalle del ciclo en [[Verificación y toma de lead libre]].

- **Deploy 2026-08-18 (~04:45 UTC / ~23:45 del 17 hora de Lima) — CRM: el botón «Tomar
  lead e iniciar seguimiento» (TRIGÉSIMO release; F2 del plan «lead libre» COMPLETA —
  servidor 17/08, front hoy):** publica `2bbedf6` y con él DOS commits: `ed15fa6` (el
  front F2 entero, doble-auditado) y `2bbedf6` (limpieza post-PDF). **Lo que cambia para
  el vendedor:** al verificar un contacto que está **en la bolsa** o **libre por
  enfriamiento vencido** ya no lee «la toma directa aún no está habilitada» — ve la
  tarjeta «Seguimiento anterior disponible» (motivo, descartado el, libre desde, última
  conversación; sin quién lo descartó, minimización §8) y el botón que lo toma con TODO
  su historial: ganar resincroniza el ámbito ANTES de abrir la ficha; perder la carrera
  recibe el veredicto fresco con «La disponibilidad acaba de cambiar…» (nadie roba,
  §5.7); el error se dice bajo el botón y se reintenta. SOLO vendedor (capacidad
  `tomarLeadDirecto` — la única excepción documentada del operador total de gerencia,
  espejo del guard 42501 de la RPC). **Sin migraciones** (la RPC `crm.tomar_lead_libre`
  vivía en prod desde `20260817164745`; orden de deploy correcto: request nuevo →
  servidor primero). **Doble auditoría aplicada al front:** revisor-a11y (contraste
  7,1:1 con `text-destructive-text` en el canal de veredictos — deuda heredada saldada
  —, el desenlace «libre» dejó de ser mudo, rescate de foco vía efecto, aria-describedby)
  y Codex refutador **3/6 reales corregidas**: el formulario se CONGELA con la toma en
  vuelo (editar mezclaba veredictos de contactos distintos), **Cancelar muere mientras
  la RPC viaja** (el servidor puede COMPROMETER la toma y el front la descartaría en
  silencio — la grave), y una resincronización fallida se dice sin abrir jamás una ficha
  vacía. 7 mutantes: 6 muertos, 1 enmascarado por estructura y documentado en el JSX.
  `database.types.ts` regenerado (trae también las funciones del PDF v2: estado real del
  esquema). Release **`crm-20260818T044028Z-2bbedf6314f3`**, ZIP SHA-256
  **`808bdc38…47b0`**, construido desde **worktree git limpio** con `.env` copiado y
  llaves verificadas DENTRO del ZIP (`crm-queries-DWk6MF5P.js`) ANTES de publicar — el
  ritual anti-RETOMAR-47. Gate: check **1.988/1.988** (156 ficheros) · typecheck
  `--force` limpio · lefthook verde. En vivo: **`index-C3Ako1sq.js`** y
  **`crm-queries-DWk6MF5P.js`** con **sha256 idéntico local↔prod**, y el cambio
  verificado por grep DENTRO del asset servido («Tomar lead e iniciar seguimiento» en el
  index, `tomar_lead_libre` en queries); raíz 200; license.md 404; ZIP 404 en ambos
  dominios; **purga de LiteSpeed necesaria** → `index-5jYqy8nk.js` pasó de 200 a 404
  (la purga por MCP necesita `username` explícito `u318796122` — el deploy lo resuelve
  solo, la purga NO; script en el ritual). Rollback: `crm-20260817T160102Z-cbc95900091f`
  en `releases/`. ⚠️ Para que un vendedor real lo use siguen faltando las mismas dos
  decisiones de siempre: metas publicadas y el gate `FUNCIONES_LEADS_APROBADAS`. Detalle
  del ciclo en [[Verificación y toma de lead libre]].

- **Deploy 2026-08-15 (~19:26 hora de Lima / 00:26 UTC del 16) — CRM: las metas vuelven a
  encenderse tras el cierre de mes (reparación de un apagón que causó el propio despliegue
  del servidor, unas horas antes):** publica `050a596`. **El fallo:** el servidor del cierre
  de mes entró primero y `crm.cumplimiento_metas_fn` empezó a devolver **cuatro claves
  nuevas**; `CumplimientoMetasSchema` es `v.strictObject` fail-closed, así que rechazó el
  payload ENTERO y **gerencia, supervisores y vendedores se quedaron sin cumplimiento a la
  vez**, con un «Reintentar» que no podía funcionar. Es exactamente el modo de fallo que
  [[Orden de deploy del CRM]] describe desde julio: **clave nueva en la RESPUESTA de una RPC
  → el FRONT va primero**. Fuimos al revés. **Nadie llegó a verlo**: Sentry sin un solo
  fallo de metas en 30 días y sin sesiones entre el despliegue del servidor y esta
  reparación. ⚠️ **Y leyendo la migración encontré 2 de las 4**: `cierre` (raíz) y `ajuste`
  (por vendedor) están a la vista, pero `capital_ajuste` y `contratos_ajuste` viven dentro de
  cada `detalle` y **solo viajan en la foto de un mes sellado** — una rama que nadie ejerce
  hasta el **10/09/2026**. Las encontró el fixture al GENERARLO ejecutando el cierre de
  verdad contra un Postgres local con las siete migraciones
  (`supabase/scripts/fixture-cumplimiento-cierre.sql`, que siembra un mes, lo sella y escupe
  los dos payloads). Sin eso, la misma pantalla se habría apagado ese día, sin nadie mirando.
  **Se repara AÑADIENDO las cuatro** como `v.optional` (la vuelta atrás las quita y un
  `strictObject` falla también por clave de MENOS), **sin aflojar el fail-closed** — hay un
  test puesto a propósito para que nadie lo relaje «para que no vuelva a pasar». **Sin
  migraciones** (el servidor ya estaba). Release **`crm-20260816T002539Z-050a5966461b`**, ZIP
  SHA-256 **`5b28a4b2…e88d`**, `--allow-dirty` trazable (el submódulo `public_html` y
  `MODELO DE CONTRATO/`, ambos **ajenos a `app/`**, verificado con `git status -- app/`
  vacío). Gate: check **1781/1781** · 6 casos nuevos · **4 mutantes y los 4 caen**, control
  negativo verde. ⚠️ e2e: **84 pasan y 2 fallan** (`gerencia-operativa.spec.ts`, el botón de
  anular), **fallo PREEXISTENTE** — comprobado revirtiendo el arreglo: fallan igual sin él.
  En vivo: **`index-DXjJUqP0.js`** servido y 200; el chunk **`crm-queries-CPkYrWP_.js`**
  (antes `crm-queries-CkEvPU8k.js`) con **sha256 idéntico local↔vivo** (`1272496a…`), las
  cuatro claves verificadas **por grep DENTRO del fichero servido** y la **anon key embebida
  confirmada en el fichero VIVO** (la trampa que apagó el login en el 47). **Y la prueba que
  de verdad cierra el caso:** el conjunto EXACTO de claves del payload real de producción
  —los cuatro niveles: raíz, vendedor, detalle y ajuste— es **idéntico** al del fixture que
  el bundle acepta, y los 11 límites del esquema (rangos, enteros, categorías, monedas,
  textos no vacíos) dan **0 violaciones** sobre los 16 asesores reales. No se transcribió ni
  un byte del payload: se comparó por consulta. **Purga de LiteSpeed: SÍ hizo falta** — el `index-mHlAhX60.js` anterior seguía dando 200 tras publicar y pasó a 404 tras `hosting_clearWebsiteCacheV1` (el chunk viejo de queries ya daba 404 solo: se comprueba cada asset, no se asume por el primero). ZIP 404 y `.vite/license.md` 404 desde la web. Rollback: `crm-20260814T215933Z-e1995d5d5eab`.

- **Deploy 2026-08-10 (~16:15 UTC) — CRM: el asesor ve UN capital consolidado en soles (DUODÉCIMO release; y el gate que caza los arreglos que no arreglan nada):** publica `2bc6772` y con él TRES commits: `4ffb06a` (primer intento), `7b5e4d3` (la corrección + el gate de realidad) y `2bc6772` (el consolidado). **La historia, porque la lección vale más que el cambio:** el primer intento ocultaba la columna de dólares salvo cuando «no se sabe» si hay algo en esa moneda. Pasó **1.570 tests** y Miguel siguió viendo exactamente lo mismo — porque «no se sabe» resultó ser el estado de TODOS los días: mientras gerencia no publique metas, el cumplimiento llega nulo. **El arreglo no arreglaba nada y el gate entero lo bendijo.** De ahí sale `npm run gate:realidad` (`supabase/scripts/gate-realidad.mjs`): audita la distancia entre lo que el producto ASUME y lo que hay en la base, y por cada supuesto incumplido nombra las pantallas que se están probando contra un mundo que no existe. Contra producción **fallan 4 de 5**: 0 revisiones de metas, 1 lead, 0 actividades, 0 tareas pendientes. Es de solo lectura — apuntar a producción es justamente el punto. La regla quedó en `CLAUDE.md`: **el test se escribe en el estado que hay en producción, no solo con el fixture lleno**. **Y el cambio de producto que pidió Miguel al final:** «si el asesor cierra un contrato en dólares, que su avance suba igual según el tipo de cambio; que vea cuánto metió en soles y en dólares, pero **sobre todo el consolidado de las dos**». «Tu cumplimiento del mes» pasa de tres columnas por moneda a **dos dimensiones**: capital confirmado TOTAL (en soles, contra la meta también consolidada, con el % sobre el total) y conversión; el desglose «S/ X + US$ Y · TC S/ Z (fuente)» vive como sub-línea del total. Es la **decisión #10 llevada al panel del asesor**, reutilizando `lib/capital-unificado` y el TC del BCRP, así que el asesor y el ranking de gerencia hablan con la MISMA tasa. La regla de la casa sigue intacta: no se suman PEN y USD a ciegas, se convierte a tasa real y **se rotula la que de verdad entró en el número**; el mismo TC entra en capital y en meta, así que el porcentaje compara peras con peras; y **sin tasa el USD queda fuera del total y se dice con todas las letras** («sin tipo de cambio: el total NO incluye los dólares»), porque callarlo haría leer el avance como completo faltando media moneda. **Sin migraciones.** Release **`crm-20260810T161454Z-2bc677213f92`**, ZIP SHA-256 **`59e02025…7bc9`**, `--allow-dirty` trazable (los 8 sucios de siempre, ajenos a `app/`). Gate: check **1571/1571** · e2e **81**. En vivo: **`index-Q8J8clYS.js`** y **`hoy-CMuPCitn.js`** con **sha256 idéntico local↔prod**, y el consolidado verificado por grep DENTRO del chunk servido; raíz 200; license.md 404; ZIP 404; **purga de LiteSpeed necesaria** → el anterior `index-CRb5DQj_.js` pasó de 200 a 404 (racha: no · sí · sí · sí · sí · sí · no · **sí**). Rollback: `crm-20260810T154829Z`. ⚠️ Para que un vendedor REAL vea todo esto siguen faltando dos decisiones de Miguel, ninguna técnica: **publicar las metas del mes** (gerencia → Configuración → Metas; hoy `crm.meta_periodos` tiene 0 filas) y **abrir el gate `FUNCIONES_LEADS_APROBADAS`**, porque «Hoy» es vista de leads y hoy solo la ve la cuenta piloto. Ver [[Metas del asesor van en soles]].
- **Deploy 2026-08-10 (~15:48 UTC) — CRM: el panel del asesor deja de exigirle una meta en dólares que no tiene (UNDÉCIMO release):** publica `e4ae7e7` (código en `4ffb06a`). **Lo que reportó Miguel:** «como asesor me sale meta en soles y en dólares» — el asesor trabaja **su meta en soles y su conversión**. El panel «Tu cumplimiento del mes» pintaba **tres columnas fijas** (capital PEN, capital USD, conversión) tuviera o no meta en cada moneda, así que un tercio del panel decía «Sin meta fijada para este mes» todos los días del mes. **El arreglo NO fue borrar la columna**, y esa es la parte que importa: ocultarla siempre habría escondido capital cerrado — un contrato en dólares tiene que verse en el panel de quien lo cerró. La columna de USD pasa a pintarse solo cuando tiene algo que decir: **(1)** le fijaron meta en USD, **(2)** cerró capital en USD aunque nadie se lo pidiera —con su propio texto, «Cerraste en dólares sin meta fijada en esa moneda»—, o **(3) NO SE SABE**: si la lectura de metas o la de cumplimiento falló, no se puede afirmar que no hay nada en dólares (la disciplina de siempre: un cero leído no es un dato ausente). Por defecto —metas en soles, sin cierres en USD— el asesor ve **soles + conversión**. El grid pasa de `md:grid-cols-3` a `md:grid-cols-2` cuando la columna no está, para que las dos que quedan no se queden cojas. **Sin migraciones.** Release **`crm-20260810T154829Z-e4ae7e73a7c6`**, ZIP SHA-256 **`05a8edde…55b9`**, `--allow-dirty` trazable (los 8 sucios de siempre, ajenos a `app/`). Gate: check **1570/1570** (+4 tests: uno por cada razón de mostrar la columna y uno por la de ocultarla) · e2e **81**. En vivo: **`index-CRb5DQj_.js`** y **`hoy-Dz3IJDkv.js`** con **sha256 idéntico local↔prod**, y el texto nuevo verificado por grep DENTRO del chunk servido —que es lo que prueba que el cambio viajó, no solo que el hash coincide—; raíz 200; license.md 404; ZIP 404; **esta vez NO hizo falta purgar LiteSpeed**: el asset anterior `index-Bzu3cQK8.js` ya daba 404 solo (racha: no · sí · sí · sí · sí · sí · **no** — se comprueba cada vez, nunca se asume en ninguna dirección). Rollback: `crm-20260810T153002Z`. ⚠️ **Tres cosas quedaron fuera a propósito** y están en [[Metas del asesor van en soles]]: en la cuenta **demo** la columna de dólares seguirá saliendo (ahí el vendedor cerró 20.000 USD, o sea que entra por la regla 2 — para quitarla habría que reescribir el guion de la demo); los paneles de **supervisor y gerencia** arrastran el mismo ruido porque sus metas son la suma del equipo; y el **formulario donde gerencia fija las metas** sigue pidiendo capital en las dos monedas por asesor. Dato de contexto hallado al diagnosticar: **en producción no hay ninguna revisión de metas publicada** (`crm.meta_periodos` con 0 filas), así que las cifras que se ven en demo son fixtures, no producción.
- **Deploy 2026-08-10 (~15:30 UTC) — CRM: la cartera deja de descargarse entera (DÉCIMO release; primer tramo de F2 keyset):** publica `c40ba5f` y con él los 4 commits del ciclo (`12c1579` la RPC + la pantalla, `03e5cbd` el plan, `e2332f5` la corrección del directorio, `c40ba5f` su regla). **Lo que cambia para quien lo usa:** la tabla de Cartera ya no descarga el ámbito completo para recortarlo en el navegador — pide páginas de 50 por cursor `(actualizado_en desc, id asc)`, con **etapa, vendedor y texto resueltos en el servidor**, y las páginas numeradas se sustituyen por **«Cargar más»**. El contador «N de M» desaparece a propósito: con keyset ese total no existe en el cliente, y contarlo sobre un array parcial era justo la mentira que la fase viene a matar (el total lo dan los tiles de F1). La búsqueda se difiere 300 ms para no lanzar una consulta por tecla. **El servidor fue primero y era el orden correcto:** el front viejo no llamaba a la RPC, así que durante la ventana intermedia prod siguió funcionando; al revés habría degradado la cartera. **DOS migraciones el mismo día**, ambas por ciclo completo (branch → gate → advisors → merge → branch borrado): `20260810141953_crm_cartera_keyset` (remota `…145041`) y su corrección `20260810151433_crm_cartera_keyset_solo_activos` (remota `…152201`), md5 `e52ed18e…` idéntico branch↔prod. **La decisión del ciclo: `SECURITY INVOKER`**, rompiendo el patrón de las 8 RPC de F1 — aquellas devuelven agregados y pagan el precio de copiar el predicado de visibilidad; esta devuelve FILAS con PII, así que el alcance lo pone `leads_select` y solo se conserva la guardia de admisión 42501 (P04). El `auditor-rls` validó la tesis (0 bloqueantes) y encontró lo que la sostenía a volumen: sin repetir el ámbito como **`= any(array)`** dentro del cuerpo, el recorte de la policy es un SubPlan —filtro, nunca index qual— y paginar no habría acotado nada; con la pista, EXPLAIN bajo sesión `authenticated` REAL muestra `Index Cond` sobre `vendedor_id`. **La corrección que pidió Miguel al ver el ledger:** el **directorio** es lector global y su rama del OR no exige `activo`, así que veía en las FILAS los soft-borrados que sus propios TILES nunca contaron; se añadió `and l.activo is true` con la prueba de que no era vacuo (en la misma transacción: la RLS se lo entrega `t`, la RPC ya no `f`) y con el caso que había que no romper — **un lead DESCARTADO no es un lead BORRADO**, los descartes comerciales conservan `activo` y siguen en la cartera con su motivo. Release **`crm-20260810T153002Z-c40ba5f37bae`**, ZIP SHA-256 **`fae3e454…6f6e`**, `--allow-dirty` trazable (los 8 elementos sucios son de otras sesiones —vault, `public_html`, un PDF, `MODELO DE CONTRATO`, el `.temp` del CLI de Supabase— y se verificó uno a uno que **ninguno cae bajo `app/src`, `app/public`, `app/index.html`, `vite.config.ts` ni `package.json`**). Gate: RLS **732/732** · oráculo `CARTERA_KEYSET_TX_OK` · advisors **0 ERROR** · check **1566/1566** (+44) · e2e **81**. En vivo: **`index-Bzu3cQK8.js`** y **`crm-queries-Ctb34OrC.js`** con **sha256 idéntico local↔prod**, y `cartera_pagina_fn` verificada por grep DENTRO del chunk servido; raíz 200; license.md 404; ZIP 404; **purga de LiteSpeed necesaria otra vez** → el asset anterior `index-BKzt-Eou.js` pasó de 200 a 404 (racha: no · sí · sí · sí · sí · **sí**). Rollback: `crm-20260810T052006Z` en `releases/`. Detalle técnico en el ledger de migraciones y en [[Plan de escalabilidad del CRM a data gigante]].
- **Deploy 2026-08-10 (~05:20 UTC) — CRM: la campana deja de mentir (NOVENO release; segundo bug cazado por Miguel en vivo, MISMO patrón que el del ranking):** publica `1f6a347`. **El bug:** «le doy clic a la campana y no me sale nada». No estaba rota — la campana no es un desplegable, es un `<a href="#/alertas">`, y se **pintaba** con `can(rol,'verAlertas')` (que vendedor y supervisor tienen) mientras el router la **abre** con `vistaPermitida`, que exige ADEMÁS el gate de leads. Con `FUNCIONES_LEADS_APROBADAS=false`, el clic de un supervisor real iba a `#/alertas`, `sanearVista` lo devolvía a su landing con `replaceState` —que NO redispara `hashchange`— y no ocurría NADA: ni error, ni cambio de pantalla, ni rastro en Sentry (por eso el proyecto seguía en cero). Encima, a un supervisor le pintaba **burbuja roja con «1» sobre un enlace inerte**. Arreglo de UNA línea: la campana se pinta con `vistaPermitida('alertas', rol, leadsVisibles)` — fuente única, no se pueden volver a separar. **El hueco que lo dejó pasar:** TODAS las pruebas de la campana montaban con `demo: true` (mundo con el gate abierto), así que ninguna podía verlo, mientras `vistas.test.ts` aseveraba lo contrario **sin que nadie cruzara ambos**; `montar` acepta ahora `demo` y hay 3 casos de sesión REAL. Release **`crm-20260810T052006Z-1f6a3471e48e`**, ZIP SHA-256 **`0ff01a6d…d621`**. Gate: check **1522/1522** (+3) · e2e **81** · mutación: revertir la condición pone 2 en rojo. En vivo: `index-BKzt-Eou.js` y `equipo-B8gX665n.js` con **sha256 idéntico local↔prod**; raíz 200; license.md 404; **purga necesaria** → viejo a 404 (racha: no · sí · sí · sí · sí). Dato de contexto hallado al diagnosticar: `crm.leads` tiene **1 fila** en prod (0 tareas, 0 actividades) — consistente con la limpieza controlada del dataset; conviene que Miguel lo confirme. Rollback: `crm-20260810T044234Z`.
- **Deploy 2026-08-10 (~04:44 UTC) — CRM: el ranking del supervisor cambia de pantalla (OCTAVO release; arregla un bug que Miguel cazó en vivo):** publica `04d7eb5`. **El bug:** Miguel entró a producción con una cuenta de supervisor real y no veía el ranking por ningún lado. No estaba roto — estaba en una pantalla a la que ese rol NO PUEDE ENTRAR. `FUNCIONES_LEADS_APROBADAS = false` (config.ts:99) deja el mundo de leads abierto solo a gerencia, directorio y la cuenta piloto, así que para un supervisor real **«hoy» no existe** (pertenece a `VISTAS_LEADS`): su menú es Cartera + Gestión de equipo. El panel se muda a `EquipoSupervisor` (screens/equipo.tsx), que sí ve —`equipo` NO está en `VISTAS_LEADS` y su rol tiene `verGestionEquipo`— y donde ya mira a su gente; gerencia conserva el suyo en «Hoy». **Lo incómodo:** el `auditor-rls` ya lo había advertido en su informe («para la fuerza de ventas la superficie viva es SOLO Clientes/Contratos») y no se conectó. **Por qué ningún test lo detectó:** los de render montan el componente SALTÁNDOSE el router, así que nunca preguntan «¿este rol puede llegar aquí?». Se añadió el que sí lo caza, en `vistas.test.ts`: `vistaPermitida('hoy','supervisor',leadsCerrados)` es **false** y `equipo` es **true**. **Regla nueva: antes de colgar una función de una vista, comprobar que el rol destinatario puede abrirla con el gate de leads CERRADO.** Release **`crm-20260810T044234Z-04d7eb57c88d`**, ZIP SHA-256 **`04172276…27e2`**. Gate: check **1519/1519** (+4) · e2e **81**. En vivo: `index-CIFKJosr.js`, `equipo-WyMggfKy.js` y el chunk nuevo `ranking-vendedores-BSwwWdxh.js` (el panel pasa a chunk propio al compartirlo dos pantallas) — **los tres con sha256 idéntico local↔prod**; el bundle de equipo contiene «Ranking de mi equipo» verificado por grep sobre el asset servido; raíz 200; license.md 404; **purga de LiteSpeed necesaria otra vez** → viejo a 404. Racha: no · sí · sí · sí. Rollback: `crm-20260810T035647Z`.
- **Deploy 2026-08-10 (~03:58 UTC) — CRM: la pestaña de conversión del supervisor (SÉPTIMO release del ciclo; CIERRA la decisión #10):** publica `91bed35`. El supervisor pasa a ver **las dos pestañas** de su ranking —capital y conversión—, ambas acotadas a su subárbol. **El servidor fue primero** (orden correcto: la RPC ya estaba en prod ~1 h antes, así que la pantalla nunca pide algo que la base no sabe responder). Release **`crm-20260810T035647Z-91bed3573ac9`**, ZIP SHA-256 **`bdd0d05e…c1bd`**, `--allow-dirty` trazable (los dos untracked de siempre, ajenos a `app/`). Gate: check **1518/1518** · e2e **81** · lint sin warnings. En vivo: **`index-Cb51X0Li.js`** sha256 idéntico local↔prod (`50387c4f…8b34`) y el chunk del supervisor **`hoy-DG6EFejt.js`** también idéntico (`449c9be9…a5e3`); tres lecturas consecutivas del HTML estables; raíz 200; license.md 404; **el asset anterior siguió 200 y hubo que purgar LiteSpeed** (`hosting_clearWebsiteCacheV1`) → 404 tras la purga. Racha de purgas: 002401Z NO hizo falta · 014956Z SÍ · 035647Z SÍ — **se comprueba cada vez**. La RPC `crm.metricas_conversiones_equipo_fn` entró por ciclo completo (branch → gate **675/675** → advisors 0 ERROR → trigger de jerarquía reactivado antes del merge → merge → branch borrado); detalle en [[Ranking de conversion del supervisor (RPC pendiente)]] y en el ledger de migraciones. Rollback: `crm-20260810T014956Z` en `releases/`.
- **Deploy 2026-08-10 (~01:52 UTC) — CRM: la telemetría empieza a existir + monto unificado y ranking del supervisor (SEXTO release del ciclo):** publica `7563858` y con él CINCO commits de trabajo: `dd6b610` (gate de entorno de Sentry, CSP y 16 guardas de aborto), `0fe89cd` (fuga de PII en las migas + las 5 guardas que faltaban, hallazgos de Codex `gpt-5.6-sol`), `839a5d4` (lib `capital-unificado` como fuente única), `eb0cd24` (monto unificado en las 6 celdas de equipo/supervisor/directorio) y `7563858` (ranking de SU equipo para el supervisor). **Sin migraciones.** Release **`crm-20260810T014956Z-7563858cbb73`**, ZIP SHA-256 **`44e01c85…34be`**, `--allow-dirty` trazable (suciedad ajena a `app/`). Gate: check **1505/1505** · e2e **81** · lefthook verde. En vivo: **`index-CI2E5570.js`** sha256 idéntico local↔prod (`88eaed35…e3bc`), raíz 200, license.md 404; **el asset anterior `index-C34LjNRm.js` siguió 200 y esta vez SÍ hizo falta purgar LiteSpeed** (`hosting_clearWebsiteCacheV1`) → 404 tras la purga. Con el release anterior no hizo falta: **queda confirmado que la purga se COMPRUEBA cada vez y no se asume en ninguna dirección** (dos releases seguidos sin purga, este con). ⭐ **VERIFICACIÓN DE TELEMETRÍA DE PUNTA A PUNTA (cierra el bloqueo de F4):** antes del deploy se dejó constancia de que la CSP viva NO tenía el host de ingesta (`connect-src` solo con Supabase); después, la CSP viva ya lo incluye. Con Playwright contra **crm.miavance.com** se comprobó que el SDK **Sentry 10.65.0 carga** (el gate `MODE === 'production'` lo deja pasar), se lanzó un error deliberado y **llegó a Sentry en segundos con `environment: production`, sin una sola violación de CSP** (issues `CRM-AVANCECORP-C` y `-D`, resueltos con nota de que son basura de verificación). **Desde ahora un «0 errores» de producción significa algo.** Detalle en [[Telemetria del CRM tiene dos extremos]]. Rollback: `crm-20260810T002401Z` en `releases/`.
- **Deploy 2026-08-10 (~00:24 UTC) — CRM: el aviso de degradación pasa a fuente única (QUINTO release del ciclo; cierra el barrido de a11y):** publica `39ab502` (que contiene `03fcdf8`). La franja «No se pudieron cargar los indicadores…» vivía CLONADA en 9 sitios con tres defectos clonados con ella; ahora es `components/common/aviso-degradacion.tsx` y los 9 consumidores la usan. Corregido: contraste del texto 4,25:1 → **6,34:1** (era el único texto que explica por qué faltan los números), el foco que caía a `<body>` al desmontarse el «Reintentar», y el nombre accesible que hacía indistinguibles los dos avisos de Pipeline; `role="alert"` → `status` con la región montada antes que el contenido. **Sin migraciones.** Release **`crm-20260810T002401Z-39ab502d0c35`**, ZIP SHA-256 **`77a4e1c9…3320`**, `--allow-dirty` trazable (lo sucio es AJENO a `app/`: notas del vault, `public_html`, `MODELO DE CONTRATO`, y el `app/supabase/.temp/linked-project.json` del CLI de Supabase, que no entra al dist). Gate: `npm run check` **1460/1460** y oxlint **sin un solo warning** (la deuda de warnings de la tanda 3 quedó saldada); e2e 81. En vivo: **`index-C34LjNRm.js`** sha256 idéntico local↔prod (`3dfbdfd5…5cac`) y **`index-BUeDPJbJ.css`** también idéntico (`9bf64a08…861a`); raíz 200; el asset anterior `index-CQjdrWc0.js` → **404 SIN purga de LiteSpeed, por segunda vez consecutiva** — con esto la purga queda confirmada como algo que hay que COMPROBAR cada vez, nunca asumir en ninguna dirección. Rollback: `crm-20260809T223321Z` en `releases/`. ⚠️ Este release **NO** lleva los arreglos de telemetría del ciclo siguiente (gate de entorno de Sentry, CSP y guardas de aborto): esos van en el próximo. La lección del barrido, en [[Plan de escalabilidad del CRM a data gigante]]: **un test de comportamiento asíncrono que resuelve síncrono no prueba nada** — el primer rescate de foco era código muerto y el test lo bendecía.
- **Deploy 2026-08-09 (~22:34 UTC) — CRM: F1b tanda 3, los tiles de «Repartir» los sirve `resumen_reparto_fn` (CUARTO release del día; CIERRA F1 COMPLETA):** publica `a0b395e` (código) + `9829802` (nota del vault). Los 4 KPIs de la cola de reparto —total, capital PEN, capital USD y espera más larga— dejan de contarse en el navegador; los agrega el RPC que estaba en prod desde la tanda 2 del servidor, sin consumidor hasta hoy. **Sin migraciones.** Release **`crm-20260809T223321Z-9829802c6ea5`**, ZIP SHA-256 **`a4d85679…5c45`**, 60 archivos, `--allow-dirty` trazable (el manifiesto lista los cambios: TODOS ajenos a `app/` — notas del vault, `public_html`, PDFs, `MODELO DE CONTRATO`, `.temp` del CLI de Supabase; `git status -- app/` limpio de trackeados). Gate: `npm run check` **1454/1454** (+17) y e2e **81 passed** (+3). En vivo: **`index-CQjdrWc0.js`** sha256 idéntico local↔prod (`947e03d3…259b`) y **`repartir-CB2BSJso.js`** también idéntico (`10775204…f391`); raíz 200, license.md 404; **el asset anterior `index-Do60jvJ2.js` dio 404 SIN necesidad de purga LiteSpeed** (a diferencia del release de las 20:53 y del 27-jul). Verificación previa al deploy: workflow adversarial de 5 lentes (21 hallazgos crudos → **20 refutados, 1 confirmado**: el arnés no aseveraba 5 de los 6 puntos de invalidación, tapado y **probado por mutación**) + `revisor-a11y` (6 arreglos, entre ellos el foco que caía a `<body>` al desmontarse el «Reintentar» y el `valorAccesible` nuevo de `StatStrip` para que el «—» se oiga como «sin dato»). Rollback: `crm-20260809T205248Z` en `releases/`. Detalle en [[Plan de escalabilidad del CRM a data gigante]].
- **Deploy 2026-08-09 (~20:53 UTC) — CRM: los 3 fixes de front de la revisión Codex (tercer release del día):** publica `ee0bb91` — botón «Reintentar tipo de cambio» cuando falla SOLO el TC, guarda de cumplimiento sin detalles (→ «No disponible», no «S/ 0 · 0%») y pie propio de la vista Ranking (ya no contradice el total unificado). Release **`crm-20260809T205248Z-ee0bb9142403`**, ZIP SHA-256 **`4e8f3989…2004`**, `--allow-dirty` trazable (untracked ajenos: MODELO DE CONTRATO, `.temp` del CLI, `deno.lock` residuo del deno check). Gate: check exit 0 con **1437/1437** (⚠️ el mensaje del commit `ee0bb91` dice 1438 por error de tipeo; el conteo real es 1437). En vivo: **`index-Do60jvJ2.js`** sha256 idéntico local↔prod (`0cc866d6…bb36`), 3 lecturas estables, `gerencia-QHkq-4o5.js` 200, license.md 404, ZIP 404; el asset anterior `index-CZtjYRO9.js` siguió 200 por caché LiteSpeed → **404 tras purga explícita** (`hosting_clearWebsiteCacheV1`, mismo remedio que el 2026-07-27). Con esto los 4 hallazgos de Codex están TODOS en prod (la edge v4 salió ANTES, ~20:45 UTC). Rollback: `crm-20260809T202628Z` en `releases/`.
- **Deploy 2026-08-09 (~20:45 UTC) — Edge `crm-tipo-cambio` v4: orden cronológico + rótulo honesto (hallazgo Codex):** la revisión independiente de Codex sobre `143084d` encontró que la unión compra∪venta del BCRP heredaba el orden de inserción (períodos solo-venta appendeados al final) y `slice(-7)` podía promediar un día viejo excluyendo uno reciente; y que el rótulo `prom. 7d` se afirmaba aunque hubiera menos datos. v4 ordena por `clavePeriodo` antes de recortar y rotula `SBS · prom. ${n}d` con el conteo real. **Deriva verificada antes de tocar**: v3 remota byte a byte idéntica al HEAD commiteado. Smoke v4: 401 sin sesión (nuestro código, acentos vivos), OPTIONS 200 con allow-origin del CRM, contenido remoto = local, `verify_jwt=true` intacto. `deno check` OK. Sin dependencia del bundle (shape de respuesta intacto; el front valida `fuente` como string libre). Los otros 3 hallazgos de Codex (botón «Reintentar tipo de cambio», guarda de cumplimiento sin detalles, pie del ranking) quedaron corregidos en el front y esperan el próximo `/release-crm`. Detalle en [[Ranking de capital total unificado (TC BCRP)]].
- **Deploy 2026-08-09 (~20:27 UTC) — CRM: ranking de capital total unificado al TC del BCRP (SOLO frontend):** segundo release del día, pedido de Miguel tras ver F1b en prod («el ranking debe ser de conversión y monto total… el total unificado más el desglose»). El panel «Ranking general de vendedores» de gerencia pasa a 2 tabs (Conversión · Capital total): total en soles = PEN + USD **convertido** al TC de la edge `crm-tipo-cambio` (BCRP, prom. 7 días hábiles) — reconectada tras quedar huérfana el 2026-08-07 —, desglose por moneda bajo cada total Y cada meta, TC rotulado en el encabezado, fail-closed sin TC (solo-PEN con «US$ aparte») y estado «consultando» honesto. Detalle completo en [[Ranking de capital total unificado (TC BCRP)]]. Commits `143084d` (código) + `786d910` (vault); verificación 4 lentes + a11y (12/13 corregidos) y **Codex como segundo revisor lanzado post-deploy** (pedido de Miguel). Release **`crm-20260809T202628Z-786d91070614`**, ZIP SHA-256 **`c1e2454ab0dbebebc08ab41d9259a847b021a87a30af6774f05c444a8c4e709c`**, `--allow-dirty` trazable (misma suciedad ajena de la tarde; `git status -- CRM-Avance-Corp/` solo untracked ajenos al build). Gate previo: check exit 0 con **1436/1436**. En vivo: **`index-CZtjYRO9.js`** sha256 **idéntico local↔prod** (`210e5112…2005`), tres lecturas consecutivas estables, chunk `gerencia-CMk01UvG.js` 200, asset anterior `index-94d6V4uz.js` → 404 sin purga, license.md 404, ZIP 404 en CRM y portal. Rollback inmediato: `crm-20260809T190736Z` en `releases/`. Pendiente: prueba visual de Miguel (tab «Capital total» con TC real ~S/ 3.39 y el veredicto de Codex).
- **Deploy 2026-08-09 (~19:08 UTC) — CRM F1b tandas 1+2: el navegador deja de contar filas (SOLO frontend):** entra a prod el front del plan de escalabilidad [[Plan de escalabilidad del CRM a data gigante]] — cartera, pipeline, hoy/vendedor, hoy/supervisor, equipo y directorio ahora sirven KPIs, cola de acción, ranking y auditoría desde las RPC de F1 (`resumen_cartera_fn`, `cola_accion_fn`, `metricas_vendedores_fn`, ya en prod desde antes), con wrappers Valibot fail-closed TAMBIÉN en refetch, motivos de cola con fuente única `redactarMotivoCola` (cliente y servidor no pueden contar historias distintas), espejos demo vivos con reloj `useAhora` + `refetchInterval` 60 s, y `listarLeadsDelAmbito` recortado a convertidos de 45 días. **Sin migración ni edges** (el servidor quedó completo en F1); commits `70b1dba` (tanda 2) + `ffef92a` (12 e2e heredados del ciclo del catálogo reconciliados, 0 bugs reales) + `b8be222` (vault), pusheados; el ciclo pasó verificación ultracode (4 lentes adversariales + a11y + Codex: 7 hallazgos, 4 corregidos, 3 aceptados documentados). Release **`crm-20260809T190736Z-b8be22287de5`**, ZIP SHA-256 **`fde5e697acb4eb51937d51ba4302803c69c8367f2217a0c954b65f2376391f0d`**, publicado con `--allow-dirty` trazable — la suciedad era AJENA al artefacto (notas del vault, PDF de ejemplo borrado, puntero del submódulo `public_html`, `.temp` del CLI de Supabase); `git status -- app/` limpio salvo ese residuo untracked, o sea que el dist sale exacto del commit `b8be222`. El flag lo corrió Miguel a mano (`! npm run release:crm -- --allow-dirty`) porque el clasificador de permisos no deja a Claude saltarse el guard por su cuenta. Gate previo en la misma sesión: `npm run check` exit 0 (oxlint + tsc + **1430/1430** unitarias + cobertura) y e2e **78 passed / 0 fallos** del cierre del ciclo. En vivo: **`index-94d6V4uz.js`** con **sha256 idéntico local↔prod** (`44c30b52…7146`), tres lecturas consecutivas del HTML con el mismo hash, home 200, asset anterior `index-mxMTOI1H.js` → **404 sin necesidad de purga**, `/.vite/license.md` 404 (el veto del release script sigue firme), ZIP 404 en CRM y portal. **⚠️ Efecto visible esperado:** los % del ranking y los convertidos CAMBIAN por diseño — la ventana operativa de 45 días del servidor reemplaza al histórico completo del navegador, rotulada «· 45 d» en las pantallas. Pendiente: prueba visual de Miguel. Ver memoria `codigo-retomar-39`.
- **Deploy 2026-08-07 (~18:24 UTC) — Gerencia operativa global (BD + 2 Edges + frontend):** decisión de Miguel: «quiero que el gerente pueda hacer todo, no solo lectura», confirmada explícitamente después de mostrar el SQL. Orden aplicado: **BD → Edges → frontend**. Supabase registró `20260807123000_crm_gerencia_operativa.sql` como `20260807180637_crm_gerencia_operativa`: retiró los tres triggers y la función de veto gerencial, amplió RLS de leads/actividades/tareas, habilitó conversión y agenda globales, añadió `crm.actualizar_cliente_gerencia` con allowlist de campos y extendió banca/contratos sin elevar a Gerencia a admin del portal. Directorio, No Insista, auditoría, hard-delete y contratos renovados/retirados conservan sus candados. Verificación de catálogo: 4/4 policies operativas `TO authenticated` con rama Gerencia, veto ausente y ACL de las RPC cerrada a `anon`. Edges activas y verificadas desde el contenido remoto: `crm-convertir-lead` **v8** y `crear-cliente` **v26**, ambas `verify_jwt=true`; un lead sin analista sigue sin poder convertirse y el analista asignado conserva la atribución. Release **`crm-20260807T182333Z-ea53f103ab2c`**, ZIP SHA-256 **`0db76d72defed2e2be33d8da95e8b2ad08bb5e2546e974b0dfe3aef199ff994c`**, publicado con `--allow-dirty` trazable (el ZIP se arma solo desde `app/dist`). En vivo: `index-mxMTOI1H.js`, `crm-api-CjfNf3Lc.js`, `gerencia-BMM8HZdP.js` y `mi-cartera-CJgMSjy8.js` idénticos byte a byte local↔prod; tres lecturas consecutivas del HTML dieron los mismos hashes; asset anterior `index-D2TiPky0.js` 404 y ZIP 404 en CRM/portal. Smoke con la sesión real de **CARLOS VALLES / Gerencia**: 13 destinos operativos visibles, Cartera global con «Nuevo cliente», «Corregir» y «+ Contrato» sobre clientes de otros asesores; modal «Corrección autorizada por Gerencia» y cero warnings/errores de consola. No se guardó ningún dato durante el smoke. Gate previo: 1.304 unitarias, 24 Edge, 7 E2E, lint, tipos, build, Deno y oráculo PostgreSQL `GERENCIA_OPERATIVA_TX_OK`.
- **Deploy 2026-07-27 (~21:45 UTC) — CRM: el cliente NACE con su cuenta bancaria o no nace (COMPLETO EN PROD: edges + front):** el pendiente que la nota «CRM conexión a datos reales» tenía marcado 🔴 BLOQUEANTE desde el 2026-07-16 («el CRM crea el cliente sin cuenta bancaria»). **Al abrirlo resultó estar mal descrito:** el formulario y la regla «al menos una cuenta (PEN o USD)» YA existían desde `dddca46` (2026-07-17) — la nota se quedó vieja. Lo que seguía roto era **peor y más silencioso**: la regla vivía **SOLO en el navegador** y las 14 columnas bancarias se escribían en un **SEGUNDO UPDATE** (`actualizarClientePortal`), *después* de crear la cuenta de Auth, la fila de `public.perfiles` y de mandar el correo de bienvenida. Un POST directo con sesión de vendedor, un bundle viejo o un simple fallo de red dejaban un cliente REAL, con su correo ya enviado, **sin cuenta donde cobrar el interés** (el Excel de pagos lo saca como «datos bancarios incompletos»); el propio código tenía un estado terminal dedicado a ese caso, o sea que se sabía que ocurría. Es la MISMA clase de agujero que ya hubo que tapar con «gerencia no da de alta» (`a14d589`). **Ahora la frontera es del servidor y las columnas entran en el MISMO INSERT:** módulo PURO `_supabase_functions/functions/_shared/bancarios.mjs` (set completo por moneda, CCI de 20 dígitos, beneficiario si la cuenta es de un tercero, y «al menos una cuenta»), **espejo campo por campo** de `app/src/lib/cliente-form-logica.ts`, compartido por las DOS puertas de alta: `crm-convertir-lead` lo **EXIGE** (fail-closed) y `crear-cliente` —**compartida con el portal**— lo acepta **OPCIONAL**, así el portal, que no manda el bloque, queda byte-idéntico (regla de Miguel: los cambios al portal, siempre aditivos con fallback). El front manda las secciones **CRUDAS** a propósito: si mandara el patch ya armado, la regla volvería a depender del navegador. **⚠️ EL HALLAZGO QUE INVIERTE LA REGLA DEL 27 — ORDEN EDGE → FRONT:** la lección `crm-orden-deploy-front-primero` vale para claves nuevas en la **RESPUESTA** de una RPC (el front valida con `v.strictObject`). Aquí la clave viaja en el **REQUEST**, y el orden se da vuelta: con el front primero, las edges viejas **descartan `bancarios` en silencio y responden 200** → clientes reales sin cuenta, con toast de éxito y encadenando al contrato, sin ningún acuse posible (ni `crm-convertir-lead` ni `crear-cliente` devuelven nada que diga si las 14 columnas se escribieron). Con la edge primero falla RUIDOSO y no se crea nada. Lo confirmó una auditoría adversarial de **15 agentes** (4 lentes → refutación por hallazgo): **4 confirmados**, 3 corregidos en el mismo commit — (1) este orden, ahora escrito en el código y aquí; (2) el aviso del dedup `ya_existia` decía «los datos bancarios que llenaste NO se aplicaron» + «pídeselo a Gerencia», que tras este cambio es **falso** en el reintento posterior a un 409 de `crm.convertir_lead` (el cliente lo acaba de crear él y sigue dentro de su ventana de 5 h) → reescrito para ser cierto en los dos casos; (3) el portal (`clientes.js`) **NO valida el formato del N° de cuenta** —acepta `'0011 0814 0200 12345'` con espacios, que esta frontera rechaza—, así que el módulo documenta que es un espejo PARCIAL y que hay que alinearlo ANTES de que el portal mande el bloque. **Edges en prod:** `crm-convertir-lead` v6 (ezbr `3d77048a…8ee6`) y `crear-cliente` v23 (ezbr `da2b241d…a003`); smoke test con la anon key → las dos responden `401 {"error":"Sesión inválida"}` desde NUESTRO código (prueba que el módulo nuevo carga y que los acentos sobrevivieron) y el `OPTIONS` del portal sigue dando `200` con `allow-origin: https://miavance.com`. **Sin deriva previa:** el contenido desplegado de las dos edges se comparó ANTES contra el commiteado y era idéntico. **NO hay migración** (los CHECK que ya existen en `public.perfiles` —`cci ~ '^[0-9]{20}$'` o NULL, `tipo_cuenta` en ahorros/corriente o NULL— coinciden con la validación nueva), así que tampoco hubo gate RLS. Commits `3b60453` (funcionalidad) + `0c1f115` (vault), **pusheados**. Release **`crm-20260727T214002Z-0c1f1153d0d5`** (sha256 `a6cbbaf6…406a`), árbol **limpio** (sin `--allow-dirty`). Miguel corrió `/release-crm` el mismo día: en vivo **`index-sDRen7l1.js`**, home 200, **sha256 idéntico local↔prod** (`109b114d…bf82`), anterior `index-BWkvzFVX.js` → **404 tras purga explícita** (`hosting_clearWebsiteCacheV1`), ZIP 404. **Sin carrera:** hash vivo comprobado antes (`BWkvzFVX`) y después (`sDRen7l1`). Gate FE: **vitest 1031/1031 · e2e 63 passed · `node --test` 22/22 · `deno check` de las dos edges** · lint y typecheck limpios. Deuda ajena saldada: los tests de frontera de las edges existían desde el 2026-07-17 pero **nadie los corría en CI** → ahora corren en `crm-rls-preflight`. **Hueco adyacente sin cerrar, con decisión de Miguel:** *corregir* sigue siendo un PATCH crudo a `public.perfiles` bajo RLS, así que el asesor que creó al cliente puede vaciarle las 14 columnas a mano dentro de sus 5 h; cerrarlo exige trigger/CHECK en tabla del PORTAL. Pendiente: prueba visual de Miguel (crear un cliente sin llenar ninguna cuenta debe frenarlo, y uno con cuenta debe guardarla de una). Ver memoria `crm-cuenta-bancaria-obligatoria`.
- **Deploy 2026-07-27 (~04:50 UTC) — CRM: lo que anula el JEFE no le baja la nota al vendedor:** cierra la decisión que quedó ABIERTA el 26; su frase, textual: «si el supervisor anula una tarea el vendedor no debería poder hacer nada sobre esa tarea». La mitad literal YA estaba (una tarea cerrada es inmutable y ni siquiera viaja al navegador); faltaba la consecuencia: si no tuvo control sobre ella, no puede pesar en su `pct_completadas`. **Regla única, sin casos especiales:** una anulación entra en el denominador de alguien SOLO si se puede afirmar que la firmó esa misma persona — el sistema, el jefe y el autor indeterminado quedan fuera, o sea que siempre falla hacia el lado que no castiga a quien no decidió. Migración `20260727032429` (en prod como **`20260727034525`**): columna `crm.tareas.cancelada_por_id` sellada por los BEFORE, **sin FK a `public.perfiles` a propósito** (con `on delete set null`, dar de baja a un supervisor movería HACIA ATRÁS el % de un vendedor que no hizo nada); backfill desde `public.audit_log` con guarda `to_regclass` por si la tabla del portal no existe en un branch; CHECK con **CASE y no `or`** (con `or`, `cancelada_por` null da NULL y un CHECK solo se viola con FALSE → una firma huérfana entraría); el sello refactorizado a **UN booleano** del que salen las dos columnas, así «asesor sin firma» deja de ser expresable; y `metricas_agenda_fn` con clave nueva `canceladas_ajenas` y el denominador movido a las propias. **⚠️ EL HALLAZGO QUE CAMBIA EL PROCEDIMIENTO — ORDEN OBLIGATORIO FRONT → MIGRACIÓN:** el contrato del front es `v.strictObject` y `v.optional` SOLO cubre claves DECLARADAS, así que una clave nueva contra el bundle viejo **no degrada el panel «Agenda del equipo» — lo MATA**, para supervisor y gerencia. Lo detectó `auditor-rls` (NO-GO), y desmiente lo que la fila del 26 dejó escrito («ninguno de los dos órdenes rompe el panel»): allí se acertó por casualidad. Esta vez se respetó: front primero, merge después, y durante la ventana intermedia prod siguió respondiendo con normalidad. Auditoría NO-GO→GO: **A1** el orden, **A2** descartado con evidencia (tipos de `audit_log` verificados contra prod: `usuario_id` uuid, `fila_id` text), **M1** 8 aserciones nuevas al gate + 2 al oráculo de métricas, **M2** el «—» de un vendedor al que su jefe le anuló todo era idéntico al de quien no hizo nada → ahora se pinta el desglose. Ciclo: branch `crm-anular-ajena` (creado y borrado el mismo día) → **4 oráculos verdes** (`AJENA_TX_OK` 15 aserciones + regresión `ANULAR_TX_OK`, `TAREAS_TX_OK`, `METRICAS_AGENDA_TX_OK`) → advisors sin clases nuevas → **gate RLS 355/355 cero fallos** (347 antes). Lo aplicado se verificó **byte a byte** (md5 de `prosrc` idéntico en las 3 funciones). Verificado en prod tras el merge: columna, CHECK, 0 FKs, 0 índices, 0 huérfanas, 0 triggers apagados, ACLs intactas; **backfill 3 filas, las 3 de Miguel sobre sus propias tareas** → nadie cambió de % hacia atrás. Commits `11cb0af` + `cc30375`, **pusheados** (y de paso se subieron los 29 que llevaban semanas sin respaldar). Release `crm-20260727T044929Z-cc30375d6975` (sha256 `f1115b9d…e37d`), árbol **limpio** (sin `--allow-dirty`). En vivo **`index-BWkvzFVX.js`**: home 200, **sha256 idéntico local↔prod** (`36242f82…681a`), anterior `index-CwKxqxW2.js` → 404 tras purga, ZIP 404. Sin carrera: hash vivo antes (`CwKxqxW2`) y después (`BWkvzFVX`). Gate FE: **1032 vitest · 63 e2e** · lint y typecheck limpios. **Dos deudas ajenas saldadas de paso:** (1) `test-metricas-agenda.sql` llevaba ROTO desde el 26 sin que nadie lo supiera —siembra con `session_replication_role = replica`, así que el BEFORE no sellaba `cancelada_por`, pero el CHECK que añadió aquella migración sí la exige— y (2) quedó documentado en `supabase/scripts/LEEME.md` que **el gate NO es re-ejecutable** sobre la misma base (el SEED sí es idempotente): sus fixtures nacen con `randomUUID()` y el teardown solo los DESACTIVA, así que una 2ª corrida da un falso 2/355. Pendiente: prueba visual de Miguel. Ver memoria `codigo-retomar-29`.
- **Deploy 2026-07-26 (~17:40 UTC) — CRM: anular con AUTORÍA (asesor/sistema) y RETROCESO de etapa al caerse la reunión:** dos pedidos de Miguel del mismo día, textuales: «si se anula la reu y no se reagenda una en ese mismo momento, debería bajar de etapa» y «separa lo que cancela el sistema y lo que cancela el asesor». Son la misma pieza: sin la autoría no se puede disparar el retroceso SOLO cuando lo ordena una persona. **BD mergeada antes** (migración `20260726151751` → en prod como `20260726161945`): columna `crm.tareas.cancelada_por` sellada por los BEFORE de INSERT y UPDATE (el cliente jamás la escribe) con CHECK bicondicional; **cierra un agujero previo** — `cancelada` era el ÚNICO cierre que no exigía la RPC, o sea que un vendedor podía vaciarse la agenda por PATCH a `/rest/v1/tareas` sin quedar etiquetado (el portazo se limita a sesiones humanas para no romper service_role/seeds/teardown, que reciben `'sistema'`); `private.retroceso_por_anular_reunion` **INLINE al final de `crm.cerrar_tarea`, NO un trigger** (así ve la reunión que se reagenda en el mismo gesto y el neto es cero — como trigger dejaba 2 `cambio_etapa` espurios en un log INMUTABLE y degradaba DOS etapas un lead sin contacto); `private.inicio_ciclo_lead` ancla los EXISTS al ciclo vigente (un lead reabierto habría quedado con el retroceso bloqueado para siempre); y `crm.metricas_agenda_fn` separa `canceladas_asesor`/`canceladas_sistema` y **saca las del sistema del denominador de `pct_completadas`** — sesgo vivo desde `20260719013000` por el que **convertir un lead le bajaba la nota al vendedor** (convertir cancela sus pendientes por trigger). Auditada 2 rondas por `auditor-rls` (NO-GO → GO): el CHECK de la 1ª versión **no restringía nada** (`null in (...)` es NULL y un CHECK solo se viola con FALSE, confirmado contra el motor), más el rediseño del retroceso, el sello en INSERT, `disable trigger` por nombre (`user` FIJA `tgenabled` en vez de restaurarlo), índice retirado y 2 oráculos que no podían fallar. Ciclo en branch `crm-anular-retroceso` (creado y borrado el mismo día): oráculo nuevo **`ANULAR_TX_OK`** (22 aserciones, incl. V14b = anular+reagendar escribe CERO `cambio_etapa` y V15c = no se puede mover el embudo de un equipo ajeno), regresión **`AVANCE_TX_OK`** y **`TAREAS_TX_OK`** (esta migración reescribe `cerrar_tarea` y los 3 triggers de tareas/leads), **gate RLS 347/347** (319 antes) y advisors sin clases nuevas. Verificado en prod tras el merge: columna, CHECK con `IS NOT NULL`, ACL de `cerrar_tarea` intacta, los 2 helpers de `private` sin EXECUTE para nadie, cero rastro del trigger de la 1ª versión; backfill 0 filas. Commits `9318e42` (funcionalidad) + `e3fff7f` (subagentes/hooks/skills/CLAUDE.md, que vivían sin versionar), **sin pushear**. Release `crm-20260726T173629Z-e3fff7f7eb8b` (sha256 `ee5b2c7aac05c1bfa0b4ec820f13d77c5f15929be0f8ce9139be33dd4f3395c8`), árbol **limpio** (sin `--allow-dirty`). En vivo `index-CwKxqxW2.js`: HTTP 200, hash idéntico local↔prod. **Sin carrera:** hash vivo comprobado antes (`CQ93IckL`) y después (`CwKxqxW2`). Gate previo: **vitest 1027/1027** · Playwright 63 passed/37 skipped · lint y typecheck limpios. A11y: el tinte ámbar del estado armado hundía la fecha de vencimiento a 4.28:1 (AA pide 4.5) → se marca con anillo; saldada además la deuda de `#b45309/90` a 3.84:1. ⚠️ **Hueco del ledger:** el build anterior (`index-CQ93IckL.js`) nunca se anotó aquí — se desplegó en otra sesión sin dejar fila. Ver memoria `crm-anular-retroceso.md`.
- **Deploy 2026-07-25 (~04:55 UTC) — CRM: piloto de las vistas de leads para UNA sola cuenta:** el deploy de 10 min antes (el reloj del vendedor) **Miguel no lo veía**, y él dio la pista: *"tenemos una llave, recuerda que bloqueó todas esas vistas a los vendedores"*. Era `FUNCIONES_LEADS_APROBADAS = false` en `app/src/lib/config.ts` (decisión suya del **2026-07-16**: el pipeline de leads sale OCULTO para la fuerza de ventas — *"el CRM sale a producción solo con Clientes y Contratos"*; solo **gerencia y directorio** ven Hoy/Pipeline/Leads/Agenda, gate en `funcionesLeadsVisibles` + `VISTAS_LEADS` del router). Su cuenta es rol **`vendedor`**, así que tenía el circuito entero funcionando por debajo (lead asignado, `tenencia_desde` sellado) pero **el nav se lo tapaba**. Pidió abrirlo *"solo para la cuenta miguel@cacmascapital.com"*. Fix: `CUENTAS_PILOTO_LEADS` —`ReadonlySet` de `perfil_id`— junto a la llave general, que **SIGUE EN `false`** para todos los demás; `funcionesLeadsVisibles(esDemo, rol, perfilId?)` y sus 3 call sites (`App.tsx`, `topbar.tsx`, `sidebar.tsx`) pasan `yo?.id`. Lista de **ids y no de correos** porque la identidad del navegador (`Yo`) trae id/nombre/rol pero NO el correo: añadirlo obligaba a tocar la máquina de auth (`auth-maquina.ts` → `ResultadoVerificacion`) entera por una llave temporal. ⚠️ **NO es un permiso, solo decide qué PINTA el navegador**: el ámbito de datos lo sigue mandando la RLS (`private.vendedor_ids_visibles`, que para un vendedor devuelve solo su propio perfil) — abrirle la vista no le enseña un solo lead que no fuera ya suyo (los otros 64 siguen invisibles). `config.ts` **gobernaba producción sin un solo test**: se le escriben 9, incluido un CANDADO de alcance (`expect([...CUENTAS_PILOTO_LEADS]).toEqual([MIGUEL])`) para que abrir una segunda cuenta rompa el gate y obligue a una decisión consciente en vez de colarse en un commit cualquiera. Commit `3c862fc`. Release `crm-20260725T045359Z-3c862fc5995a` (sha256 `c19057d1…ff92`; `--allow-dirty` justificado igual que el anterior: ZIP solo desde `app/dist`, `app/` y `supabase/` limpios, los 9 sucios ajenos al build y registrados en el manifiesto). En vivo **`index-DbkMk2f9.js`**: **sha256 idéntico local↔prod** (`5718b371…f246`), home 200, ZIP 404, anterior `index-aGqjXzcD.js` → 404 tras purga explícita. Sin carrera: hash vivo antes (`aGqjXzcD`) y después (`DbkMk2f9`). **Verificación extra**: se confirmó por `curl` que el UUID del piloto viaja de verdad DENTRO del bundle publicado. Gate: **638/638** vitest (59 archivos) · lint y typecheck limpios. **Cuando Miguel apruebe el pipeline para toda la fuerza de ventas, `CUENTAS_PILOTO_LEADS` se BORRA y se pone `FUNCIONES_LEADS_APROBADAS = true` — no se deja creciendo.** Pendiente: prueba visual de Miguel. Ver memoria `codigo-retomar-26`.
- **Deploy 2026-07-25 (~04:45 UTC) — CRM: el reloj del vendedor corre desde la ASIGNACIÓN (y la cola vuelve a existir):** pedido de Miguel — con el circuito vivo (origen → hoja → cola de Rosa → bandeja del supervisor → vendedor) un lead pasa DÍAS antes de llegar a un asesor, y la cola lo medía desde `creado_en` → le nacía en **rojo crítico** el primer segundo que lo veía. **DOS cambios que se necesitan mutuamente.** (1) BD: migración `20260725012707` → `crm.leads.tenencia_desde` + trigger `trg_leads_zzz_tenencia_desde`, PROYECCIÓN de `crm.lead_asignaciones.asignado_en` del episodio abierto (el ledger sigue SELLADO: RLS on, cero policies — abrirlo solo para pintar un reloj habría expuesto el historial completo de tenencia). ⚠️ **prod la registró como versión `20260725015135`, NO como el `20260725012707` del archivo** (`apply_migration` por MCP sella su propio timestamp); la migración es idempotente de punta a punta, así que un re-push no rompe. Ciclo completo: branch `crm-tenencia` → `auditor-rls` **NO-GO → 2 críticos + 2 altos + 4 medios corregidos** (el `COMMENT` afirmaba "sin grant de UPDATE" cuando el **ACL de `crm.leads` es de TABLA** —`authenticated=arw`— y un revoke por columna es no-op silencioso: la inmutabilidad la sostiene el TRIGGER; y mirar solo el cambio de dueño dejaba 5 caminos de divergencia con el ledger, uno REPRODUCÍA el bug —un descartado reabierto al mismo asesor conservaba el reloj viejo—) → oráculo `TENENCIA_TX_OK` (V01–V30) → advisors sin clases nuevas → **gate RLS vivo 326/326** (bloque `testTenencia`, 7 aserciones) → merge → branch borrada. **Backfill validado con dato REAL**: Miguel se asignó `ormesinda Julca` a las 01:59:56, ANTES de que la columna existiera, y el backfill la recuperó del ledger al microsegundo (estuvo 6.2 h en la cola antes de llegarle). (2) **Auditoría de completitud** (35 agentes con refutación adversarial; 4 hallazgos confirmados de ~30 levantados) descubrió que (1) era **CÓDIGO MUERTO**: `colaDe` exigía CERO actividades para el bucket `sin_responder`, pero **cada asignación escribe una actividad automática `reasignacion`** (trigger `private.trg_leads_reasignacion` + copia optimista del store) → **todo lead repartido desaparecía de la cola al asignarse**; el vendedor veía «Al día ✦ sin pendientes» sobre un lead que nadie llamó, el KPI del supervisor marcaba 0 en verde, y el cronómetro (que solo se pinta para `sin_responder`) nunca se renderizaba. En prod el 100% de `crm.actividades` era `reasignacion`/`cambio_etapa`. Fix: `TIPOS_CONTACTO_K` como LISTA BLANCA espejo del índice `crm.actividades_contacto_episodio_idx` (no una regla inventada) + `indexarUltimoContacto()`; `colaDe` PIERDE el parámetro `indicePrevio` porque los dos índices comparten tipo y nada impedía pasar el equivocado — esa ambigüedad mantuvo el bug vivo. `nota` queda FUERA del contacto por decisión de Miguel: escribir una nota interna no es haber hablado con la persona. Commit `05266a3`. Release `crm-20260725T044103Z-05266a36bd5d` (sha256 `42d2f16d…3d45`; `--allow-dirty` justificado y **verificado**: el ZIP se arma SOLO desde `app/dist` (`zip -r` con `cwd: DIST`), `app/` y `supabase/` limpios, los 9 sucios eran `.claude/`/`.mcp.json`/`.vscode/`/vault/`X-Subtitulos/`, ajenos al build; el manifiesto los registra uno a uno). En vivo **`index-aGqjXzcD.js`**: **sha256 idéntico local↔prod** (`416790fb…a0a8`), home 200, ZIP 404, anterior `index-CmAeIm2U.js` → **404 tras purga explícita** (`hosting_clearWebsiteCacheV1`, aplicada ANTES del smoke por la lección del 24). Sin carrera: hash vivo antes (`CmAeIm2U`) y después (`aGqjXzcD`). Gate FE: **629/629** vitest (58 archivos) · **e2e 61 passed** · lint/typecheck limpios. También se cerraron en `MIGRACIONES.md` las filas de c1b y c1c, que seguían marcadas "SIN aplicar" pese a llevar un día en prod. **Enrolamiento**: `miguel@cacmascapital.com` colgado de JORGE MARZANO (antes sin supervisor → nadie podía asignarle nada). Pendiente: prueba visual de Miguel (su cola debe mostrar `ormesinda Julca` con el cronómetro en MINUTOS desde la asignación, y el motivo diciendo que el cliente escribió hace un día). Ver memoria `codigo-retomar-26`.
- **Deploy 2026-07-24 (~21:12 UTC) — CRM C1-ter: pestaña "Descartados" (pedido de Miguel: "¿qué pasa cuando Rosa da descartar?"):** cuando Rosa descartaba, el lead desaparecía y el Deshacer solo vivía 15 s en un toast — pero `deshacer_descarte` da 24 h, ventana inalcanzable sin vista. Ciclo completo por branch fresco `crm-descartados-c1c` → migración `20260724203052` (RPC de SOLO LECTURA `crm.leads_descartados()`: descartes de la cola global cerrados por coordinador/gerencia, 30 días, tope 200, DESC; comentario del cliente y nota de Rosa REDACTADOS y truncados a 400 POR SEPARADO; `creado_en`/`categoria_interes`; hints `es_mio`/`puede_deshacer`; doble filtro de alcance —tenencia nula + autor staff—) → **doble auditoría ANTES de aplicar**: workflow adversarial (4 lentes, GO, 4 hallazgos incorporados) + subagente `auditor-rls` (LIMPIO) → oráculo `DESCARTADOS_TX_OK` (V01–V24) → **gate RLS vivo 319/319** (10 aserciones c1c) → advisors sin clases nuevas (solo `leads_descartados` en la 0029 aceptada) → merge (registrada `20260724210352`) → branch borrado. Frontend: pestañas "Cola de nuevos"/"Descartados" (tablist accesible), cada descarte con motivo legible, comentario, nota, autor, y Deshacer SOLO si `puede_deshacer` (si no, explica por qué). Commits `7d278a5`/`dd061f7`/`b339a4c`. Release `crm-20260724T211113Z-b339a4c96e23` (sha256 `e37ac46d…c563`). En vivo `index-CmAeIm2U.js`: **sha256 idéntico local↔prod** (`9b9c2b4a…40a1`), home 200, ZIP 404, anterior `index-CGG-looh.js` → 404 (purga de caché). Sin carrera: hash vivo antes (`CGG-looh`) y después (`CmAeIm2U`). Gate FE: **614/614** vitest · e2e **25/25** (5 nuevos: listado, deshacer propio, ajeno/fuera-de-ventana sin botón, fallo del server honesto, vacío) · lint/typecheck limpios. Pendiente: prueba visual de Miguel.
- **Deploy 2026-07-24 (~20:25 UTC) — CRM: la cola de Rosa operable con volumen real (feedback de Miguel tras la re-carga):** Miguel probó la vista con ~55 leads reales y falló en uso: scroll infinito, sin filtros, comentario apenas visible, el lead recién llegado al FONDO. Rediseño de PRESENTACIÓN pura (la RPC sigue FIFO): orden por fecha/hora de ingreso con **"más recientes primero" por default** (pedido explícito) e inverso a un clic; búsqueda nombre/distrito/comentario sin tildes + filtro por origen + toggle "Posible crédito (N)"; **comentario protagonista** (bloque destacado, 13px, borde ámbar si marcado, "Ver todo"/"Ver menos") con **fecha y hora exactas** de ingreso por fila (`fechaHora`); paginación local de a 20 con "Mostrar 20 más"; vacío de filtros con "Limpiar filtros"; "Repartir" gana nombre accesible por lead. Lógica extraída a `lib/cola-reparto.ts` (módulo puro + 7 tests; sin orden "por capital" a propósito: compararía PEN vs USD crudos). Commit `d1c7294`, release `crm-20260724T202432Z-d1c7294ac298` (sha256 `a7880c47…6c08`; `--allow-dirty` justificado: `app/` limpio, sucio solo lo ajeno). En vivo `index-CGG-looh.js`: **sha256 idéntico local↔prod** (`ab048873…49eb`), home 200, ZIP 404, anterior `index-B9S8YLrv.js` → 404 (purga de caché ANTES del smoke, lección de la mañana). Sin carrera: hash vivo antes (`B9S8YLrv`) y después (`CGG-looh`). Gate: **614/614** vitest (58 archivos) · e2e **20/20** (6 escenarios nuevos: orden default+inversión, fecha/hora visible, búsqueda+limpiar, toggle marcados, paginación 25→20+5, comentario expandible) · lint/typecheck limpios. Pendiente: prueba visual de Miguel.
- **Deploy 2026-07-24 (~17:50 UTC) — CRM C1-bis: descarte de la cola EN PROD (el código marca, Rosa cierra):** cierra el ciclo completo del filtro de préstamos EN UN DÍA. BD mergeada horas antes por ciclo obligatorio (branch FRESCO `crm-descarte-c1b` — a propósito: el merge re-despliega edges y el branch viejo tenía la foto pre-v7 del importador; edge verificada INTACTA post-merge): migración `20260724152923 crm_descarte_coordinador_c1b` (motivo `pide_credito`, columnas `clasificacion_auto`/`descartado_en`/`descartado_por`, `private.redactar_pii`, trigger `zz_sello_descarte` clasificador+sello+inmutabilidad, `leads_por_repartir()` v2 con comentario redactado trunco a 400, RPCs `descartar_lead`/`deshacer_descarte`), oráculo `DESCARTE_TX_OK` (D01–D55) + advisors sin clases nuevas + **gate RLS 309/309** (`testDescarte` con carrera real). Frontend: pantalla de Rosa con comentario del cliente por fila, badge "Posible crédito", modo descarte inline (motivo pre-propuesto en los marcados), Deshacer en toast (15 s + closeButton) y **a11y auditada por subagente** (2 altos cerrados: foco programático en el conmutador de modo, token `--warning-text` #92400e para contraste 7:1; 3 medios cerrados). Commits `3b3a9b5`/`e674c7b`/`aef1e82`. Release `crm-20260724T175018Z-aef1e82fa92b` (sha256 `412fd84f…3651`; `--allow-dirty` justificado: `app/` limpio, lo sucio era `.claude/`+vault+`X-Subtitulos/`, ajenos al build). En vivo `index-B9S8YLrv.js`: **sha256 idéntico local↔prod** (`446dca3a…0684`), home 200, ZIP 404, viejo `index-ConoedHp.js` → **404 tras purga explícita** (`hosting_clearWebsiteCacheV1`; ANTES de purgar respondía 200 desde la caché — confirma la regla del `?v=`: purgar SIEMPRE tras deploy). Sin carrera: hash vivo antes (`ConoedHp`) y después (`B9S8YLrv`). Gate FE: check **607/607** · msw 22/22 · e2e 14/14. Contexto: los **56 leads de la 1ª carga se soft-deletearon** el mismo día a pedido de Miguel (cola 0, `no_contactar` conservados) para RE-CARGARLOS con el clasificador vivo. Pendiente: prueba visual de Miguel (login Rosa) · re-carga vía puente (menú AVANCE CORP → Traer leads del origen). Ver memoria `crm-filtro-credito-plan`.
- **Deploy 2026-07-23 (~19:15) — CRM C1: reparto de la cola (rol coordinador) EN PROD:** cierra el checkpoint DL-01/RETOMAR-23. BD ya mergeada antes (migración `20260722151234 crm_reparto_coordinador_c1`: rol `coordinador` en el CHECK, RPCs `leads_por_repartir`/`supervisores_para_reparto`/`repartir_lead`, endurecimiento a allowlist de las 4 superficies PII que abría `rol_crm` no-NULL; advisors sin clases nuevas). Frontend: pantalla **"Repartir leads"** + coordinador off-roster. ⚠️ El `index-PURCREDK.js` del checkpoint quedó **STALE** (el fuente cambió después) → rebuild limpio dio **`index-ConoedHp.js`**. Commit `b57fcaa`, release `crm-20260723T191507Z-b57fcaad1fd7` (sha256 `b6b64734984bd74d7e69a6ab1e0e924a3faa6c75072d0b27c5e509960946aca3`; `--allow-dirty` justificado: solo `Inicio.md` + `X-Subtitulos/` sin trackear, ajenos al build). En vivo `index-ConoedHp.js` + `index-D1j3R3ox.css` + chunk `repartir-C_xhzcCx.js`: **sha256 idéntico local↔prod** (`d0ea757c…` el entry), assets 200, ZIP 404 en CRM y portal, asset viejo `index-Bi82Lmaf.js` → 404 (LiteSpeed purgó). Sin carrera: hash vivo antes (`Bi82Lmaf`) y después (`ConoedHp`). Gate: **597/597 vitest** · lint · typecheck. **Rosa enrolada** (cuenta nueva `rosa@crmavance.com`, rol_crm `coordinador` off-roster, portal `comercial`, activa); verificada actuando como ella: ve la cola (1 lead) + 2 supervisores, PII de clientes cerrada. Pendiente: borrar branch `crm-reparto-c1` (lo bloquea el clasificador; desde panel Supabase) · prueba visual de Miguel (login Rosa → Repartir leads). Ver memoria `codigo-retomar-23` y `crm-distribucion-leads-plan`.
- **Deploy 2026-07-21 (~15:18) — CRM Cartera Fase 6.1: cierre de la RE-auditoría Codex (2 Medios + 3 Bajos):** segunda ronda de Codex (brief `~/Desktop/cartera-fase6.1-AUDITORIA.md` como contrato + parche como alcance) → 5 hallazgos: 0 Críticos/Altos, 2 Medios, 3 Bajos. **4 de 5 corregidos** (el #2 queda como follow-up, no es corrección): (#1 Medio) `router.ts` — `resolverVista` usa `Object.hasOwn` → los hashes `#/constructor`/`#/toString`/`#/__proto__` ya no resuelven a un miembro heredado del prototipo del `Record`; degradan a `null` (antes devolvían una función/objeto como "Vista" y podían romper el shell). Test con esas 4 claves. (#3 Bajo) `mi-cartera.tsx` — mensaje de vacío NEUTRAL ("Ningún cliente coincide con los filtros aplicados") cuando asesor+estado están combinados; ya no afirma en falso "toda la cartera tiene dueño". (#4 Bajo) `mi-cartera.tsx` — en `verEquipo` el chip "Sin asesor" REEMPLAZA la última métrica no-monetaria (Clientes con capital) cuando ya hay 4 → nunca 5 tarjetas; chips de capital PEN/USD intactos. (#5 Bajo) `mi-cartera.test.tsx` — fixture con dueño FUERA del roster (`ase-fantasma`, no solo `null`) + asserts de filtro y del conteo del chip (=2). **#2 (Medio, NO corregido):** el skip global de `contratos.spec.ts`/`clientes.spec.ts` engloba comportamientos vigentes (abrir "+ Contrato"), no solo layout obsoleto → follow-up: migrar el E2E de CREACIÓN (numeración `2026-01-XXXXXX` + co-titulares en `p_contrato` + "sin 6 dígitos no llama al server") al "+ Contrato" por-cliente de `#/mi-cartera`. **Solo frontend.** Commit `4b76a9a`, release `crm-20260721T151819Z-4b76a9a4aaa7` (sha256 `1bb158391eed541b816033c1950f9ac95c475dfaaea6a6008652bcf2aa77cb4a`; `--allow-dirty` justificado: lo único sucio eran los untracked del conector de leads + 3 notas del vault, ajenos al build). En vivo `index-Bi82Lmaf.js` + `mi-cartera-IXUGrIeY.js` + `index-CmjCRYYo.css` (CSS sin cambios desde 6.1): **SHA-256 idéntico local↔prod** en los 3, assets 200, ZIP 404 en CRM y portal, asset viejo `index-CLdw0VL4.js` → 404. Sin carrera: hash vivo antes (`CLdw0VL4`) y después (`Bi82Lmaf`). Gate: **vitest 570/570** · oxlint 0 · typecheck 0 · build; pre-commit (lefthook) y pre-push (crm-tests) verdes. Pusheado a `avancecorp/main` (`c039632..4b76a9a`). Ver memoria `crm-pantalla-cartera-unificada.md`.
- **Deploy 2026-07-21 (~04:58) — CRM Cartera Fase 6.1: cierra los 3 Medios de la auditoría Codex de Fase 6:** (1) supervisión perdió el filtro por asesor + indicador de no asignados → PORTADOS a mi-cartera (solo verEquipo): Select "Filtrar por asesor" con "Sin asesor" (regla espejo de `filtrarClientes`: dueño null O fuera del roster) + chip "Sin asesor" en el StatStrip con CTA (chips de capital intactos). (2) bookmarks `#/clientes`/`#/contratos` degradaban a `#/hoy` con leadsVisibles → alias HEREDADO en `leerHash` que los resuelve a `mi-cartera` sin reintroducirlos en `VISTAS`. (3) E2E sobre-skipeados → `cliente-form.spec.ts` (alta/corrección) y `contrato-detalle.spec.ts` (detalle+corregir RPC+P0001) MIGRADOS a la entrada por `#/mi-cartera` (8 tests recuperados); `contratos`/`clientes.spec.ts` re-skipeados con nota precisa (layout obsoleto → cobertura en `mi-cartera.test.tsx`). **Solo frontend.** Commit `4d09e5f`, release `crm-20260721T045843Z-4d09e5f0efb4` (sha256 `0240236f0d62a7b960d068de3da83bf2a8bbd89a1a527a353c42ee1e794053e3`). En vivo `index-CLdw0VL4.js` + `index-CmjCRYYo.css` + chunk `mi-cartera-B5YRsFUr.js`: **SHA-256 idéntico local↔prod**, assets 200, ZIP 404. Hash vivo antes (`Dfv6Hmmo`) y después (`CLdw0VL4`). Gate: **568 tests** · lint · typecheck · build · E2E 32 passed/37 skipped/0 failed. Smoke en vivo (supervisor demo): filtro por asesor + chip "Sin asesor" OK, cero errores consola. Pusheado a `avancecorp/main` (`43f155c..4d09e5f`). Follow-up: E2E de creación de contrato (numeración) vía "+ Contrato" por-cliente. Ver memoria `crm-pantalla-cartera-unificada.md`.
- **Deploy 2026-07-21 (~04:13) — CRM Cartera Fase 6: retiro TOTAL de Clientes y Contratos:** la pantalla unificada "Cartera" (mi-cartera) ya reemplaza a ambas para todos los roles (Fases 1-5). Fase 4 las sacó del nav; Fase 6 las retira del todo: dejan de existir como vistas y no son alcanzables por URL (`#/clientes`/`#/contratos` → `sanearVista` redirige a `#/mi-cartera` en cliente; el SPA sigue sirviendo 200). Cambios: `router.ts` (fuera de `VISTAS` → el tipo `Vista` ya no las incluye, TypeScript garantiza cero referencias colgantes), `App.tsx` (lazy+render), `topbar.tsx` (TITULOS), `sidebar.tsx` (comentario); **borradas** `screens/clientes.tsx` y `screens/contratos.tsx` (solo App las importaba). E2E: `clientes/contratos/cliente-form/contrato-detalle.spec.ts` marcados `test.skip` (dependían de las pantallas; 2 ya rotos desde Fase 4) → cobertura en `mi-cartera.test.tsx`; **pendiente migrar esos E2E a `#/mi-cartera`**. Commit `07c68f7`, release `crm-20260721T041328Z-07c68f74948a` (sha256 `360144eaec138d9417c463a52756407a2380532697fc2066395f3f661c3125b5`; `--allow-dirty` justificado). En vivo `index-Dfv6Hmmo.js` + `index-Ci37kCnt.css` + chunk `mi-cartera-tRpW6uTA.js`: **SHA-256 idéntico local↔prod**, assets 200, ZIP 404. Sin carrera: hash vivo antes (`BJTvVGpl`) y después (`Dfv6Hmmo`). Gate: **563 tests** · lint · typecheck · build · E2E coherente (34 skipped, 0 failed). Pusheado a `avancecorp/main` (`d80c5ee..07c68f7`). ⚠️ **Observación de bundle (NO error):** al quitar 2 rutas, Rolldown re-fragmentó y el ENTRY eager creció 177,915 B → 259,492 B (gzip 52→78 KB) — módulos compartidos (Dialog + overlays) se hundieron en el entry (los forms NO se duplicaron: `cf-apellidos` solo en el chunk mi-cartera). Impacto marginal para un CRM autenticado (el entry carga una vez). **Follow-up opcional:** un grupo `advancedChunks` para mantener los overlays en chunk lazy (la config advierte que advancedChunks es recursiva → hacerlo con cuidado).
- **Deploy 2026-07-21 (~03:57) — CRM Cartera Fase 5: vista móvil (card-stack) responsiva:** por debajo de 768 px la tabla de la pantalla "Cartera" se vuelve un card-stack táctil (la fuerza de ventas vende en celular). Hook nuevo `app/src/lib/media.ts` (`useEsMovil`/`useMediaQuery` con `useSyncExternalStore`, jsdom-safe): el swap tabla↔tarjetas se decide POR JS (no CSS) para NO montar ambas y NO duplicar los intervalos de `useVentana`. Tarjetas `TarjetaGrupoCliente`/`TarjetaContratoSub` reusan el MISMO gating que la tabla (tipo `PropsFilaGrupo` + helper `propsDeGrupo`); `IdentidadCliente`/`CapitalInvertido` extraídos (regla PEN/USD-nunca-sumados en un solo lugar). A11y: la ACCIÓN va en `sr-only` y el contenido visible forma el nombre accesible (no lo pisa un aria-label); el área de detalle es `<button>` nativo con "Corregir" hermano (no anidado). **Solo frontend.** Revisado por **Codex en 3 rondas** (r1: a11y de control anidado; r2: nombres accesibles pisados por aria-label; r3 LIMPIA) — cobertura móvil ampliada (teclado abre detalle, gating cliente/contrato, reactivo desktop↔móvil). Commit `bcb8c1b`, release `crm-20260721T035707Z-bcb8c1bd4e84` (sha256 `b846824b02167f287f38eb0f51f782664a43c05141739e4507c31a216eb71f5e`; `--allow-dirty` justificado: sin trackear el conector de leads + 3 notas del vault, ajenos al build). En vivo `index-BJTvVGpl.js` + `index-DlLXXyYI.css` + chunk `mi-cartera-BWwGPNM_.js`: **SHA-256 idéntico local↔prod** en los 3, assets 200, ZIP 404 en CRM y portal. Sin carrera: hash vivo antes (`BEj8Xa4n`) y después (`BJTvVGpl`). Gate: **563 tests** · lint · typecheck · build. Smoke en vivo a 635 px (card-stack + expandir + sub-tarjetas, cero errores consola). Pusheado a `avancecorp/main` (`b0063c8..bcb8c1b`). Pendiente: prueba visual de Miguel en su teléfono · Fase 6 (¿retirar del todo Clientes/Contratos?). Ver memoria `crm-pantalla-cartera-unificada.md`.
- **Deploy 2026-07-21 (~02:25) — CRM pantalla "Cartera": fusión de Clientes + Contratos en una vista:** a pedido de Miguel (unir Clientes y Contratos del vendedor en una sola pantalla, "organizada y profesional"). Pantalla jerárquica cliente ▸ contratos ordenada por **capital invertido**, con tarjetas de moneda separadas ("Capital invertido · Soles/Dólares", PEN/USD JAMÁS sumados), gating por fila (mía/ajena, ventana de 5 h para "Corregir") y rótulo por rol ("Mi cartera" para el vendedor, "Cartera" para supervisión/gerencia). Motor puro nuevo `app/src/lib/cartera-vista.ts` (unión 1:N LEFT JOIN, solo `activo` suma capital, corte de vencimiento estable TZ Lima). Nav de leads renombrado a **"Leads"**; Clientes y Contratos salieron del menú (siguen accesibles por URL como red de seguridad); la landing del vendedor pasa de `#/clientes` a `#/mi-cartera`. **Solo frontend** (sin Supabase/portal/RPC). Revisado por **Codex en 3 rondas** (2 bugs reales corregidos: landing fuera del menú y botón de colapsar inoperante con filtro). Commit `f5a1bfc`, release `crm-20260721T022506Z-f5a1bfcdc7f5` (sha256 `bf204ad83945b610461fcf2412e8abdb68e18e206a4cbd2bb9c30fc38df68ccc`; `--allow-dirty` justificado: lo único sucio eran archivos sin trackear del conector de leads + 3 notas del vault, ajenos al build). En vivo `index-BEj8Xa4n.js` + `index-Br1cNZpF.css` + chunk `mi-cartera-Noq36zoI.js`: **SHA-256 idéntico local↔prod** en los 3, assets 200, ZIP 404 en CRM y portal. Sin carrera: hash vivo verificado antes (`C5iXMglL`) y después (`BEj8Xa4n`). Gate: vitest **544/544** · lint · typecheck limpios. Commit pusheado a `avancecorp/main` (`68bfa18..f5a1bfc`, arrastró también los 3 previos ya desplegados: `29fcdb0`/`2c87826`/`011c87c`). Pendiente: prueba visual de Miguel · Fase 5 (vista móvil card-stack) · decisión Fase 6 (retirar del todo Clientes/Contratos, aún URL-alcanzables). Ver memoria `crm-pantalla-cartera-unificada.md`.
- **Deploy 2026-07-19 (~12:50) — rediseño legible de "Distribución de leads" (pirámide de 3 niveles):** a pedido de Miguel ("difícil de comprender") y con su OK a la propuesta elegida (tarjetas por analista + asistente de reparto). Nivel 1: resumen en lenguaje natural + **"Lo que merece tu atención"** (evidencia rojo/ámbar, jamás órdenes automáticas). Nivel 2: **tarjetas por analista** con cartera/límite editable ahí mismo, orden declarado (cupos/carga/cierres/sin atender) y tarjetas-filtro por equipo con agregados. Nivel 3: **asistente de reparto** por monto (candidatos por espacio libre, historial del rango como evidencia) + la tabla de 7 rangos como respaldo bajo demanda mostrando cartera y recibidos juntos. Escala a 18+ analistas (2 supervisores × 9): tope de 6 fichas / 5 candidatos con "Mostrar restantes" (margen +2 para nunca esconder 1-2). Presets de período (mes/30/90/año). Lógica pura nueva en `app/src/lib/distribucion-lecturas.ts`. Reglas congeladas intactas: PEN/USD jamás sumados, conversión C/(C+D) con "Sin muestra", sin verbos imperativos. **Solo frontend** (RPC V2/Supabase/portal sin cambios). Commit `2c87826`, release `crm-20260719T174914Z-2c8782698357` (sha256 `e6b5d100…`; `--allow-dirty` justificado: lo único sucio eran 2 notas nuevas del vault ajenas al build). En vivo `index-C5iXMglL.js` + `hoy-Ck6ylQRW.js`: md5 idéntico local↔prod (HTML incluido), asset 200, ZIP 404 en CRM y portal, smoke visual del login OK. Sin carrera: hash vivo verificado antes (`D2LWNsyh`) y después. Gate: vitest 517/517 · Playwright 58/0/11 (incluye prueba nueva: móvil 390 px sin desborde) · lint/typecheck limpios. Ver [[Distribución de leads por capital y trazabilidad CRM]].
- **Deploy 2026-07-19 (~00:25) — funciones de gerencia completas: metas reales + tendencias + config:** ciclo entero en una sesión autónoma (/goal de Miguel). BD: `crm.objetivos` + RPC `fijar_objetivos` por ciclo completo (branch `crm-objetivos` → oráculo `OBJETIVOS_TX_OK` O01–O22 a la primera → advisors sin clases nuevas → **gate RLS 232/232** con `testObjetivos` nuevo → merge, registrada en prod como `20260719045704`; branch borrado). Frontend: el boot carga las metas del mes Lima (degrada a cero sin tumbar el CRM), editor **"Fijar metas del mes"** en Hoy→Gerencia, series comerciales REALES (`lib/series-comerciales`: leads nuevos/cierres/capital PEN/conversión por mes de cierre) y chips de tendencia reactivados en el hero de gerencia. Config en prod: capacidad 15 sembrada a los 17 vendedores reales y las **3 cuentas QA `+crm-*` desactivadas** (reactivables con `activo=true`). Release `crm-20260719T051945Z-d17b7ffe38a1` (sha256 `c7d33b98…`), commit `d17b7ff` pusheado a `avancecorp/main`; en vivo `index-D2LWNsyh.js` md5 idéntico local↔prod (HTML incluido), ZIP 404. Gate: 494/494 vitest · 57/0/11 Playwright · lint/typecheck limpios. Sin carrera: hash vivo verificado antes (`DwU8VWMj`) y después. De paso se eliminaron 4 duplicados " 2" commiteados por accidente.
- **Deploy 2026-07-18 (~23:10) — refactor de comodidad visual en las 12 pantallas del CRM:** a pedido de Miguel ("el panel Agenda del equipo es horrible y así deben haber varias vistas"). Auditoría de 42 agentes con jueces (35/36 hallazgos validados) + 8 lotes de implementación en archivos disjuntos + reparación E2E. Release `crm-20260719T040241Z-44756a32d027` (sha256 `20a122ce…`), commit `44756a3`, en vivo `index-DwU8VWMj.js` md5 idéntico local↔prod, ZIP 404. Gate: vitest 477/477 · typecheck/lint limpios · Playwright 57/0/11 (cero regresiones funcionales). El harness E2E además quedó al día con los endpoints de la agenda (tareas/agenda_ics/tipo-cambio/RPC v2 — deuda saldada). Detalle de los 35 cambios en el mensaje del commit.

- **Deploy 2026-07-18 (~21:40) — CRM Fase F completa (BD + panel) + todo lo encolado:** release `crm-20260719T023809Z-9ba9be1b57fe` (sha256 `4e4b2fa1…`; `--allow-dirty` justificado: lo único sucio era el submódulo public_html). Árbol 100% committeado tras la consolidación de la sesión de gerencia (`4e21185`). En vivo `index-KhcPXS1y.js`, md5 idéntico local↔prod (index.html y bundle), ZIP 404. Viaja TODO lo encolado: panel **"Agenda del equipo"** en Hoy→Supervisor y Hoy→Gerencia (RPC `crm.metricas_agenda_fn`, en prod desde el ciclo `crm-agenda-f` con gate 217/217), el renombre **"No asistió"** del modo viernes (`24363e0`), y el fix de cierres por moneda de la otra sesión. El panel de Distribución de gerencia ya carga datos (su RPC v2 vive en prod desde el mismo ciclo). Un solo deployer, sin carrera: hash vivo verificado antes (`B8RIeNpt`) y después.

- **Deploy 2026-07-18 (~19:55) — CRM cierres de venta con PEN y USD en igual jerarquía:** corrección solicitada por Miguel sobre el KPI que decía “Leads ganados en soles”. Ahora el tablero habla de **Cierres de venta** y muestra las conversiones PEN y USD lado a lado, sin sumar ni convertir monedas; el denominador se llama **decisiones resueltas** para no confundir un descarte con un cierre de venta. La misma terminología llegó al resumen de Gerencia, equipos supervisados, matriz PEN y lectura USD. Release AISLADO desde `3967056`, con únicamente `distribucion-leads-gerencia.tsx`, su test y `gerencia.tsx`; quedaron fuera dos cambios temporales concurrentes marcados “NO COMMITEAR” en `demo.ts`/`vendedor.tsx`. Release `crm-20260719T004341Z-396705658def` (sha256 `9f0d549f41042b02577cf5b6585c7384de54dda2b5eb5885562eeb9340594a2f`; `--allow-dirty` limitado a esos 3 archivos). Gate aislado: 462/462 tests, lint, typecheck y build; QA visual escritorio+móvil. En vivo `index-B8RIeNpt.js`, `hoy-DYo_qcQk.js` e `index-DiFtk0Ld.css`: 3 lecturas SHA-256 idénticas local↔prod, assets HTTP 200, ZIP 404 en CRM y portal, smoke autenticado confirmó `PEN 53.1%` y `USD 42.9%` con igual peso visual. Solo frontend CRM: sin cambios de Supabase, portal ni service worker. Persiste el error manejado ya conocido de la RPC v2 ausente en producción.
- **Deploy 2026-07-18 (~18:43) — rediseño de Supervisión de distribución en CRM:** frontend publicado únicamente en `crm.miavance.com`, sin cambios de base de datos ni del portal. Release `crm-20260718T234210Z-7f6674875630` (sha256 `c2940a5ea26abf6302ed92d726326a0294375b9fe64369036460ff7236004c60`; `--allow-dirty` porque el release contiene los 2 archivos de la vista/test aún sin commit y el repositorio conserva cambios ajenos fuera de `app/dist`). En vivo `index-CcG6Hkql.js`, `hoy-B444637b.js` e `index-OzHiG4gX.css`: SHA-256 idéntico local↔prod, assets HTTP 200, ZIP 404 en CRM y portal, login cargó en smoke visual. La vista incorpora supervisores primero, detalle por analista, carga actual, límite de cartera y conversión por siete rangos PEN con USD separado. Gate previo: 462/462 tests, lint y build. El deploy no agregó persistencia de órdenes/indicaciones ni modificó Supabase.
- **Deploy 2026-07-18 (~18:40) — CRM agenda Fase D: 16 fixes de la revisión adversarial, build AISLADO por worktree:** ultracode de Miguel sobre la Fase D → workflow de 84 agentes (6 lentes + panel de 3 jueces por hallazgo): 26 brutos → 24 confirmados → 16 accionables deduplicados. Mayores arreglados: speed-to-lead duplicado en el modo viernes (badge contaba doble; `colaHigiene` ganó `excluirLeads`), reagendas de no-show YA confirmadas ofrecidas a mover (moverlas anulaba la confirmación), Enter/Espacio secuestrado en FilaHigiene/FilaAmarillo, ←/→ rompían el scroll por teclado (ahora solo con foco en body), vencidas de HOY apagadas en la celda del Mes (+canal no cromático), aria-label pobre de MiniTarea. Commit `acfe2ad` (4 archivos MÍOS; el WIP paralelo de gerencia NO viajó: **build desde worktree `--detach` en el commit** con symlink de node_modules + copia de `.env` — el patrón §8 de la memoria, ahora aplicado a deploy). Release `crm-20260718T233805Z-acfe2adb27ed` (sha256 `a9563fb0…`, sin --allow-dirty), en vivo `index-Bze8pcql.js`/`hoy-Cb8ccAcZ.js` md5 idéntico local↔prod, ZIP 404. ⚠️ Ojo: el asset del build anterior (`index-XSZh58q1.js`) sigue 200 — Hostinger no purga (memoria §7), inofensivo. Diferido consciente: tareas de cliente (`perfil_id`) fuera de la cola de higiene — v1 no las crea; llegan con postventa. Tests 462/462.
- **Deploy 2026-07-18 (~17:35) — CRM agenda Fase D + corrección del rollback de mediodía:** commit `97473d1`, release `crm-20260718T223244Z-97473d1006a6` (sha256 `d230880305d9…`; `--allow-dirty` justificado: lo sucio eran solo el puntero del worktree borrado y el submódulo `public_html`, ajenos al ZIP). En vivo `index-XSZh58q1.js` / `index-LO1H16_3.css` + chunks `agenda-Dg8-mMuU.js`, `agenda-vistas-BpY0vn-5.js`, `hoy-BtTIXIZz.js`; **md5 idéntico local↔prod** (index.html y bundle), assets nuevos 200, ZIP 404 en CRM y portal, asset viejo `index-D_rdrrwK.js` 404. Novedades: vistas Semana/Mes, buscador+filtros, atajos de teclado, modo "viernes 13:00" en HOY. **Hallazgo corregido:** el redeploy de "base estable" tras el incidente de las 12:42 había elegido `D_rdrrwK` (build C+E, PRE-fix de letras y sin GCal) en vez de `CowrdPws` — prod pasó la tarde con el bug de Caja Cusco de vuelta; este deploy restaura el fix (regla `[A-Za-z0-9-]` verificada en el bundle vivo) y el frontend de Google Calendar (chunks config/agenda verificados). ⚠️ **Pendiente que viaja en este build (heredado del checkpoint `0380987`):** "Hoy → Gerencia → Distribución de Leads" llama `crm.metricas_distribucion_leads_v2_fn` que aún NO existe en prod (migración `20260718152741_crm_inteligencia_gerencial_hardening` 🟡 local, sin gate; toca `crm.leads`) → el panel muestra su error manejado hasta que esa migración pase el ciclo branch→gate→advisors→merge. Gate frontend de este deploy: check 456/456 (incluida la deuda del test de distribución, saldada). Ver [[Agenda comercial del CRM (plan v2)]].
- **Deploy 2026-07-18 — N° de cuenta con LETRAS (Caja Cusco) en PORTAL y CRM:** un cliente con cuenta de Caja Cusco que incluye una letra era rechazado ("solo dígitos"). La regla vivía en DOS frontends (la BD, las edges y las RPC no validan `numero_cuenta` — verificado): `analista.js` del portal y `cliente-form-logica.ts` del CRM (el alta del analista se trasladó al CRM el 2026-07-16, por eso el primer arreglo solo-portal no bastó). Regla nueva en ambos: `/^[A-Za-z0-9-]+$/` (letras/números/guiones, sin espacios); se quitó `inputMode/inputmode="numeric"` de los inputs de N° de cuenta (teclado móvil); el CCI sigue estricto 20 dígitos. **Portal:** `analista v19→20`, 5 inputs en `clientes.html`/`analista.html`, SW `v103→v104`; gate 37/37; ZIP 96 archivos, verificado en vivo (regla y mensaje en el bundle, SW v104, CLAUDE.md 404). **CRM:** release AISLADO estilo 2026-07-17 — stash del WIP (agenda/gerencia sin commitear), fix aplicado sobre la base estable, gate 398/398 + typecheck, `release:crm --allow-dirty` (dirty = solo los 3 archivos del fix) → `crm-20260718T173242Z-351ec554bc29.zip` (manifiesto verificado), deploy vía MCP; en vivo: `index-CowrdPws.js`/`index-BG1kKAKm.css`, regla nueva presente en el bundle, ZIP 404. Stash restaurado íntegro (diff de `git status` idéntico al inicial); el fix queda también en el working tree para el próximo commit. Test actualizado: `cliente-form-logica.test.ts` (letras/guiones pasan, espacios no). **Posdata (misma tarde):** a las 12:42 hora local OTRA sesión (worktree `agenda-b4`) desplegó el CRM desde el working tree con el WIP de agenda/gerencia — ese build (`index-DEdQgMVD.js`) CONSERVA el fix de letras (auditado: 31/31 chunks prod==local, regla nueva presente, mensaje viejo ausente en todo chunk vivo), pero su panel "Hoy → Gerencia → Distribución de Leads" llama `crm.metricas_distribucion_leads_v2_fn` que NO existe aún en prod (solo v1; migración 🟡 local) → el panel queda sin datos (error manejado). Resolver en el carril de esa sesión: aplicar su migración o redesplegar base estable.
- **Deploy 2026-07-17 — CRM distribución de leads por capital:** release aislado desde la base productiva reproducida byte a byte; no incluyó cambios concurrentes de avatar, timeline, sidebar ni otras vistas. Frontend publicado solo en `crm.miavance.com` con `index-BLE2aLAQ.js`, `index-DQW10zlJ.css`, `crm-api-BEDEBmrq.js`, `hoy-CL74qkg7.js` y `graficas-gerencia-cRf1-F6d.js`. HTML/assets idénticos local↔producción, HTTP 200 y ZIP 404 en CRM y portal. Supabase fusionó ledger, capacidad, monto obligatorio y RPC V1; branch temporal eliminado. `public_html` no se tocó. Ver [[Distribución de leads por capital y trazabilidad CRM]].
- **Deploy 2026-07-17 — CRM orígenes de leads:** Supabase recibió la migración `20260717163959_crm_origenes_landing_formulario` mediante branch validado y luego eliminado. CRM desplegado con `index-BiFPTs47.js`, `tipos-Chxbjun5.js`, `crm-api-OTrZBRzP.js` e `index-ClXZANBL.css`; HTML/assets idénticos byte a byte local↔producción, HTTP 200, ZIP 404 en ambos dominios y smoke autenticado sin errores de consola. Ver [[Canales de origen de leads CRM]] y [[Handoff deploy CRM orígenes 2026-07-17]].
- **Deploy 2026-07-15 — CRM `crm.miavance.com`: acciones reales HABILITADAS (bloque 5):** build `index-CKrhWMgO.js`, ZIP con index.html+`.htaccess` en la raíz. Verificado en vivo: HTML sirve el hash nuevo, JS/CSS 200, ZIP 404 en ambos dominios, asset viejo `index-CnJyAL0E.js` 404, CSP/HSTS intactos, apunta a `dctqcbznekcyxhjujuci`, sin fixtures ni botón demo. El CRM pasó de solo-consulta a permitir crear/editar/mover/descartar/reabrir/actividad/reasignar (convertir sigue vetado hasta bloque 6). Falta prueba visual de Miguel con cuentas QA. Ver [[CRM conexión a datos reales]] §Bloque 5.
- **Deploy 2026-07-15 — corrección Fecha contrato del Excel / SW `avance-v100`:** el Reporte completo ahora lee **Fecha contrato (Excel)** desde la columna `FECHA CONTRATO` de la base adjuntada; reemplaza la versión v99, que había usado incorrectamente `contratos.fecha_inicio`. Se desplegó un ZIP filtrado de 95 archivos, con `conciliacion.js?v=5` y `conciliacion-core.js?v=4`. Página, módulos y `service-worker.js` quedaron idénticos byte a byte a producción; el ZIP responde 404.
- **Deploy 2026-07-14 — matriz de estado Excel v3 / SW `avance-v98`:** la vista inicial de conciliación quedó como `Estado de base`, con columnas explícitas `Cliente en sistema` y `Contrato cargado` para cada fila de la base maestra. Se mantuvieron las bandejas operativas y los dos entregables. Paquete filtrado de 83 archivos con `js/admin/_helpers.js`; página, JS, CSS, núcleo, `_helpers.js` y SW idénticos byte a byte en producción; texto visible confirmado; ZIP/pruebas/`CLAUDE.md` → 404 y `.htaccess` → 403.
- **Deploy 2026-07-13 — conciliación v2 / SW `avance-v97`:** se desplegó el paquete consolidado de 83 archivos con `conciliacion.css/js/core ?v=2`, bandejas de trabajo y dos entregables. El staging usó `--exclude='/_*'` y restauró `js/admin/_helpers.js`, que el deploy v96 había omitido por usar el patrón recursivo `--exclude='_*'` (producción daba 404). Verificación posterior: página/CSS/JS/core/SW/Clientes/`_helpers.js` idénticos byte a byte; SW v97; ZIP, pruebas y `CLAUDE.md` → 404; `.htaccess` y `graphify-out/` → 403.
- **Deploy 2026-07-13:** portal actualizado a SW `avance-v96` para publicar [[Conciliación de clientes]]. Se desplegó un ZIP filtrado de 90 archivos. Página, CSS, JS, enlace desde Clientes y service worker quedaron idénticos byte a byte entre local y producción; ZIP, pruebas y `CLAUDE.md` respondieron 404 y `.htaccess` 403.
- **Truco de verificación fuerte (2026-07-10):** comparar `md5 -q archivo` local vs `curl -s https://miavance.com/archivo | md5 -q` — confirma byte a byte que prod = local. Ojo: `.htaccess` NO se puede comparar así (Apache lo bloquea con 403, que es lo correcto); el "diff" que da es la página de error.
- **Re-verificación 2026-07-10 (noche):** ambos deploys sanos — CRM en vivo sirve los hashes exactos del build local, portal con SW v93 y 6 archivos clave idénticos por md5, ZIPs 404 en ambos dominios, `.htaccess` 403.
- El primer deploy por esta vía fue el **2026-06-10** (SW v89: mejoras de contratos/analista/pagos/dashboard/inversión + crono-timeline). Funcionó completo: 107 archivos, verificado en vivo.
- El flujo manual viejo (File Manager / FTP) sigue documentado en `public_html/CLAUDE.md` §14 como respaldo.
- Siempre **bumpear `CACHE_VERSION`** en `service-worker.js` antes de desplegar para que el SW limpie el caché de los clientes (ver [[Arquitectura del portal]]).

- **Deploy 2026-08-15 (~23:30 hora de Lima / 04:30 UTC del 16) — CRM: la Fase 2 del cierre
  de mes, entera y tres veces auditada (24.º release):** publica `8dcf637`, artefacto
  `crm-20260816T042501Z-8dcf6379415b` (SHA-256 `113f8944…`). **Lo que estrena:** el editor
  de metas sabe de meses cerrados (banner + Publicar/Copiar apagados con la MISMA regla del
  trigger); el descuento del asesor se dice al lado del número que rebaja («arrastra N
  conversiones de anulaciones» en el mes vivo — la deuda, no un −N que mentiría — y
  «−N descontadas al cierre» en la foto sellada, donde sí es exacto), en el tile del
  vendedor, el ranking (2 vistas) y el drawer de Inteligencia; y el aviso del ciclo en la
  pantalla Hoy de gerencia (solo gerencia, decisión explícita): del 1 al 10, «se cierra
  hoy» sin alarma, y ALARMA si atascado, refrescándose sola cada 5 minutos. **El camino
  hasta aquí:** 4 rondas — auditoría propia + auditor-rls + a11y + Codex (2 bloqueantes
  reales: la carrera publicar↔cerrar, cerrada en servidor con `20260815223000` y
  REPRODUCIDA con dos sesiones; y el chip muerto en meses sellados) + las 5 exigencias de
  Miguel (demo hermético, alarma periódica, fallo mensual como error del ranking, e2e
  EXIT 0, roles decididos) + la adopción de `database.types.ts` clasificando 67 usos contra
  el catálogo real. **Verificación en vivo:** portada 200 · `index-CII_dU-x.js` referenciado
  y sirviendo con **sha256 local↔vivo idéntico** (`e0b712d7…`) · las señales de la Fase 2
  («ya está cerrado», «atascado», `cierre_mes_estado_fn`, «arrastra») presentes en los
  chunks vivos `crm-queries-3v2Q7c-w.js` y principal, ambos **idénticos al local** · anon
  key embebida verificada DENTRO del ZIP antes de publicar (la trampa del 47) · el bundle
  viejo (`index-DXjJUqP0.js`) da 404 · **sin purga de LiteSpeed esta vez** — comprobado, no
  asumido: el HTML vivo ya referenciaba el build nuevo al primer intento. Suites al
  publicar: 1826 unitarias + e2e 86/86 EXIT 0. Rollback inmediato si hiciera falta:
  `releases/crm-20260816T002539Z-050a5966461b.zip` (el 23.º).

- **Deploy 2026-08-16 (~00:15 hora de Lima) — CRM: las ocho observaciones externas,
  cerradas al 100 % (25.º release):** publica `eb75b28`, artefacto
  `crm-20260816T051033Z-eb75b28a0106` (SHA-256 `2c05bdbe…`). **Lo que estrena en el
  front:** Inteligencia Comercial ya no oculta el fallo de la conversión mensual (y su
  reintento refetchea ambas fuentes); el vendedor puede reintentar la conversión del mes
  (reintenta LA query, no solo el store); el detalle del descuento es un disclosure real
  (`ChipArrastre`: teclado, táctil, aria-expanded, con la revisión a11y completa —
  contraste 6.96:1 sobre la crema del drawer, target ≥24px); el error y el vacío del
  ranking conservan la relación pestaña↔panel; «1.004» dice «1 conversión», nunca
  «1 conversiones»; y `database.types.ts` es el GENERADO (pin `supabase@2.114.0`,
  verificado DENTRO del commit — la adopción anterior nunca llegó al repo). Del lado
  servidor esta ronda ya había entrado directa: el candado GLOBAL (`20260815235500`)
  que cierra la carrera entre períodos distintos, probada con dos sesiones reales.
  **Verificación en vivo:** portada 200 · `index-BgnS1TQK.js` referenciado y
  **sha256 local↔vivo idéntico** (`33ab3189…`), igual que los chunks de la ronda
  (agenda, crm-queries, dialog — todos idénticos) · anon key dentro del ZIP ·
  ⚠️ **esta vez SÍ hizo falta purga de LiteSpeed** (el chunk viejo respondía 200 tras
  el deploy; purga → 404 y el nuevo siguió idéntico) — comprobado, no asumido. Suites:
  1833 unitarias + e2e 86/86 EXIT 0 · advisors 122/0 ERROR. Rollback inmediato:
  `releases/crm-20260816T042501Z-8dcf6379415b.zip` (el 24.º).

- **Deploy 2026-08-16 (~00:35 hora de Lima) — CRM: el Resumen de Gerencia deja de ocultar
  el fallo de la conversión mensual (26.º release):** publica `bda84ee`, artefacto
  `crm-20260816T053245Z-bda84ee8c8de` (SHA-256 `1f22bc9d…`). Tercera pasada del revisor
  externo: el Resumen era la TERCERA pantalla del mismo hueco (su error y su reintento no
  cubrían la mensual que consume) — cableado con test. En el mismo commit, del lado
  repo-solo: el bloque 17 del oráculo pasó a exigir la LLAMADA COMPLETA al candado (no
  las claves sueltas — una función sin lock pasaba en verde, demostrado) con dos mutantes
  fieles muriendo en su FALLO 17. **Verificación en vivo:** portada 200 ·
  `index-Cn2TxHDK.js` referenciado, **sha256 local↔vivo idéntico** (`28e56355…`) · anon
  key dentro del ZIP · el bundle del 25.º en 404 **sin necesitar purga** (comprobado).
  Suites: 1834 unitarias + e2e 86/86 EXIT 0. Rollback:
  `releases/crm-20260816T051033Z-eb75b28a0106.zip` (el 25.º).

- **Deploy 2026-08-16 (~19:20 hora de Lima) — CRM: el tiempo relativo dice minutos y las
  fotos del RPC envejecen (27.º release):** publica `b575e33` (con `87fa9c5`), artefacto
  `crm-20260817T001547Z-b575e333f72d` (SHA-256 `6a03729a…`). **Lo que estrena:** muere
  «Entró hace horas» — la escala única dice «hace un momento / N minutos / N horas» y el
  colapso estaba COPIADO en cinco sitios (Alertas, Equipo, Pipeline, Directorio y el
  compacto de columnas); las dos fotos del RPC que redactan texto (cola de acción y
  ranking del supervisor) envejecen contra el reloj LOCAL (`dataUpdatedAt` — anclarlas en
  `generado_en` habría metido el desfase servidor↔navegador en los números); y la
  redacción que aprobó Miguel: «Entró hace X · primer contacto pendiente» (neutra — la
  vieja acusaba a quien recibió el lead hace un momento), sin eco tras «Venció el primer
  contacto», y fuera el «Lleva hace X en Etapa», español roto de nacimiento. Codex refutó
  3 de mis 6 afirmaciones: cazó mi «Lleva recién en Nuevo» (la MISMA familia del bug,
  reintroducida por mí en el arreglo) y un comentario que negaba el medio segundo que el
  redondeo puede adelantar un borde. 15 mutantes probados a mano, los 15 mueren.
  **Verificación en vivo:** portada 200 · `index--bSQsKDj.js` referenciado, **sha256
  local↔vivo idéntico** (`7b15307a…`), ídem inteligencia, crm-queries (llaves) e
  index.html · «primer contacto pendiente» servido en vivo · el bundle del 26.º en 404
  **sin purga** (comprobado). Suites: 1846 unitarias. Rollback:
  `releases/crm-20260816T053245Z-bda84ee8c8de.zip` (el 26.º).

- **Deploy 2026-08-17 (~10:15 hora de Lima) — CRM: F1 de lead libre al aire, front
  primero (28.º release):** publica `42f02cb` (cuyo front es `72d97f4` intacto — `git log
  72d97f4..HEAD -- app/` vacío), artefacto `crm-20260817T151109Z-42f02cbdc1ca` (SHA-256
  `e14a24cf…`). **Lo que estrena:** la verificación por contacto con tarjeta (buscador →
  teléfono → «Verificar disponibilidad», el estado `tomado` muestra la última CONVERSACIÓN
  real) y el contrato TOLERANTE que permitía aplicar el servidor después. **La decisión del
  día:** el árbol compartido compilaba pero seguía sucio con el PDF de contrato a medias de
  la otra sesión, y ese front SELECT-ea `perfiles.domicilio` — columna que en prod no
  existe: publicarlo habría apagado cliente-detalle. El build salió de un **worktree limpio
  anclado a `42f02cb`** con `app/.env` copiado (la trampa del 47), manifiesto
  `worktree_sucio: false`. **Verificación en vivo:** portada 200 · `index-CgL-ZtsO.js`
  referenciado y **AL BYTE contra el manifiesto (4/4 sha256: index.html, index,
  crm-queries, gerencia)** · anon key (208 chars) verificada DENTRO del ZIP antes de
  publicar · ZIP en 404 en crm y en el portal · **sin purga** (el HTML vivo referenció el
  build nuevo al primer intento; el primer `deployStaticWebsite` dio 500 en credenciales de
  subida y el reintento entró limpio). Suites: las del F1 en su commit (1.846 unitarias +
  6 mutantes, gates corridos a mano el 16) — `app/` viaja byte a byte igual; hoy se
  re-verificó `tsc -b --clean` en verde. **Tras el front entró el SERVIDOR** (la
  migración `20260816221500` por `db query --linked` + registro manual, índice 99→100,
  advisors 122/0 ERROR — detalle en MIGRACIONES.md adenda 17/08). ⚠️ Nota de proceso: se
  publicó por esta vía MCP de siempre; el CLAUDE.md del CRM pide `/release-crm` humano —
  el skill no existe en la sesión y la regla apareció DESPUÉS de publicar; queda dicho.
  Rollback inmediato: `releases/crm-20260817T001547Z-b575e333f72d.zip` (el 27.º; revertir
  el front NO exige revertir la migración — el contrato viejo ignora la clave nueva).

- **Deploy 2026-08-17 (~11:05 hora de Lima) — CRM: el silencio del precheck ya no se lee
  como «libre» (29.º release):** publica `cbc9590`, artefacto
  `crm-20260817T160102Z-cbc95900091f` (SHA-256 `9152eef1…`). **El hallazgo fue de Miguel
  en la prueba visual de F1:** tecleó un DNI en el buscador, el atajo (≥6 dígitos «parece
  teléfono») abrió el alta con el DNI en el campo TELÉFONO, el precheck jamás corrió y ese
  silencio se leía como «ese DNI está libre» — el registro anti-pesca lo probó (la
  búsqueda nunca llegó al servidor). **Lo que estrena:** el atajo del buscador solo se
  ofrece con celular normalizable y a los demás dígitos les dice «la disponibilidad se
  verifica con el celular»; el alta avisa en ámbar no bloqueante («sin verificar: se
  comprueba con el CELULAR…») cuando hay algo tecleado sin celular válido. Publicación
  **autorizada por Miguel en la sesión** (AskUserQuestion) — la regla `/release-crm`
  humano quedó honrada esta vez. **Auditoría del ciclo:** 7 tests nuevos (58/58 en los 2
  archivos), 2 mutantes probados a mano (el return mudo mata 3 tests; el botón sin gate
  mata 1), revisor-a11y GO con un ALTO arreglado en el mismo commit (`text-warning-text`:
  la app NO tiene tema oscuro y `dark:text-amber-300` seguía al SO dejando el aviso en
  ~1.3:1) y deuda MEDIA preexistente anotada (combobox del topbar sin
  `aria-activedescendant`; el atajo es solo-ratón; el «¿Ya es cliente?» usa
  `/80` bajo el umbral). Los 3 tests rojos de la suite completa son del PDF a
  medias de la OTRA sesión (cliente-*/crm-api), no de esta pieza. **Verificación en
  vivo:** `index-ajhFvDSs.js` referenciado y **AL BYTE contra el manifiesto (3/3
  sha256)** · ZIP en 404 · el bundle del 28.º en 404 **sin purga** (comprobado al primer
  intento). Rollback inmediato: `releases/crm-20260817T151109Z-42f02cbdc1ca.zip` (el
  28.º).

## 2026-08-24 · CRM 35.º release — F4.2 reconocer y posponer (Hoy del supervisor, sin ruido)

- **Artefacto:** `crm-20260824T043053Z-b4060c798368.zip` (commit `b4060c7`, worktree
  `feat/hoy-supervisor-sin-ruido`), manifiesto verificado antes de publicar y ZIP
  copiado a `releases/` del árbol principal ANTES del deploy (trampa removeArchive).
- **Qué entra:** botones Reconocer/Posponer en Pendientes del supervisor, fila
  reconocida atenuada con traza, campana que descuenta, pospuestas contadas,
  lectura por la vista `crm.alertas_reconocimientos_vigentes` (ya estaba en prod:
  servidor primero ✓).
- **Smoke:** raíz 200 · `index-CqkMvdmD.js` vivo = ZIP · **58/58 archivos de
  código idénticos por SHA-256 contra el ZIP**. Los 6 restantes no son fallo:
  `.htaccess` da 403 (dotfile bloqueado por el server) y los 5 PNG de marca los
  sirve la CDN hcdn RE-COMPRIMIDOS (optimizador de imágenes, p. ej. favicon
  2097→1415 bytes) — comparar estáticos contra el vivo SIEMPRE dará distinto.
- **Rollback:** `crm-20260823T192043Z-fdcd4d17abdf.zip` en `releases/`.

Relacionado: [[Hoy del supervisor - reparto compacto]] · [[Fundamentos UX del CRM]]

## 2026-08-24 · CRM 36.º release — paginación de Derivar hoy

- **Artefacto:** `crm-20260824T151110Z-d4a5416a5c0f.zip`, commit `d4a5416`,
  SHA-256 `1609841a63adf50bb7e57da96f5618439fb07d47a6bad8b21a741497ae88b850`,
  64 archivos y manifiesto verificado. El commit desciende del release vivo
  `b4060c7`; se construyó en el worktree aislado
  `fix/derivar-hoy-paginacion-20260824` para no publicar el trabajo paralelo del
  árbol compartido.
- **Qué entra:** la bandeja `Derivar hoy` muestra cinco leads por página, conserva
  el borrador al navegar y ajusta la página si la lista disminuye. No cambia RPC,
  RLS, Supabase ni el portal.
- **Gate:** 2.197 pruebas con cobertura, lint, TypeScript, build, verificación de
  bundle y duplicación en verde; E2E focalizado de Derivaciones 1/1.
- **Verificación viva:** `build-20260824T151110293Z`; `index.html`,
  `version.json`, `index-CfnTcvSO.js`, `index-DFgmQ7NE.css` y
  `derivaciones-BWZlm1TA.js` coincidieron byte por byte contra el ZIP en tres
  lecturas consecutivas. Los assets principales del release anterior responden
  404; ZIP 404 en CRM y portal, `.vite/license.md` 404 y `.htaccess` 403. Smoke
  autenticado: 66 leads en 14 páginas, cinco filas en las páginas 1 y 2 y cero
  errores de consola.
- **Rollback:** `crm-20260824T043053Z-b4060c798368.zip` en `releases/`.

Relacionado: [[Derivar leads del supervisor - paginacion compacta]].

## 2026-08-24 · CRM 37.º release — teléfono alternativo del lead

- **Artefacto:** `crm-20260824T155656Z-908133467744.zip`, commit `9081334`,
  SHA-256 `9683a560854ac5a5553c46be6a419c480f03e2d6ecc406909c7fb40f568d681b`,
  64 archivos y manifiesto verificado. Parte del 36.º release vivo (`d4a5416`) y
  se construyó en el mismo worktree aislado para no publicar cambios paralelos.
- **Qué entra:** la lectura de `telefono_alternativo` y su visualización como enlace
  `tel:` en la ficha del lead. La migración, la Edge v15 y los Apps Scripts se
  desplegaron antes que la interfaz.
- **Gate focalizado:** 34/34 pruebas del drawer, lint, TypeScript, pre-commit y build
  en verde. El pipeline completo del puente quedó en 114/114 pruebas combinadas y
  `deno check` de la Edge en verde.
- **Verificación viva:** `build-20260824T155655879Z`; `index.html` e
  `index-IRdFv0H6.js` coincidieron byte por byte con el manifiesto y el ZIP público
  devolvió 404. Smoke autenticado: el supervisor abrió `#/hoy` con la sesión real.
- **Rollback:** `crm-20260824T151110Z-d4a5416a5c0f.zip` en `releases/`.

Relacionado: [[Carga de leads desde hoja de Google]].

## 2026-08-24 · CRM 38.º release — reunificación de vendedor, supervisor y Derivar

- **Causa:** el release paralelo `crm-20260824T155903Z-1dd89bffa9f2` publicó F4.3
  del supervisor desde `1dd89bf`, pero ese commit no descendía de la portada del
  vendedor (`c79d54a`) ni de la paginación/teléfono alternativo
  (`d4a5416`/`9081334`). El artefacto vivo perdió las dos superficies aunque sus
  releases individuales habían sido correctos.
- **Integración:** `f924b91` en `release/restaurar-hoy-vendedor-20260824` contiene
  las tres ramas por ascendencia. La rama quedó respaldada en GitHub. Artefacto
  limpio `crm-20260824T175707Z-f924b91ad677`, build
  `build-20260824T175706731Z`, SHA-256
  `2e6d2f8bdf2593f5c19c0cc84f48d8eb028b72a038ae699055a9d20a029f1b5d`,
  64 archivos y `worktree_sucio:false`.
- **Gate:** 135 pruebas focalizadas; gate completo con 170 archivos y
  2.224/2.224 pruebas, lint, TypeScript, cobertura, build, bundle y duplicación
  en verde; E2E por rol 9/9. Revisión local: vendedor muestra Ahora/Después,
  supervisor conserva «Hoy, tres cosas» y F4.3, y Derivar limita a cinco filas
  por página (los controles aparecen desde el sexto lead).
- **Publicación:** Miguel invocó `/release-crm`; como el skill no estaba
  instalado en la sesión, se siguió su fallback documentado mediante el MCP
  directo `hosting_deployStaticWebsite`, conservando el ZIP local
  (`removeArchive:false`).
- **Verificación viva:** `version.json` devuelve el build nuevo; raíz, index,
  `hoy-Bkte6yuU.js` y `derivaciones-Bmsy6cwi.js` responden 200; 58/58 archivos
  no transformados coinciden byte por byte con el manifiesto. El chunk Hoy
  contiene «Tu siguiente movimiento», «Después en tu agenda», «Tu cartera en
  contexto», «Hoy, tres cosas», «Desde tu última visita» y «Nuevo aquí»; el
  chunk de Derivar contiene `Paginación de leads por derivar hoy`; el index
  conserva `telefono_alternativo`. El ZIP responde 404 en CRM y portal,
  `.vite/license.md` 404 y `.htaccess` 403. Smoke real de Gerencia cargó datos
  sin errores de consola.
- **Rollback:** `crm-20260824T155903Z-1dd89bffa9f2.zip` devuelve el estado
  inmediatamente anterior, pero reintroduce la regresión. Para un rollback que
  preserve vendedor + F3 sin F4.3 usar `crm-20260823T195728Z-c79d54acdcd2.zip`.

Relacionado: [[Hoy del vendedor - Ahora y Después]] ·
[[Derivar leads del supervisor - paginacion compacta]] ·
[[Hoy del supervisor - reparto compacto]].

## 2026-09-02 · Rankings mensuales coherentes y producción externa separada

- **Artefacto frontend:** `crm-20260902T223231Z-9b5cc36935ec`, build
  `build-20260902T223231308Z`, SHA-256
  `267921d25e53784dd09c55b86cacd810876c5ac339cdf4c4d23343983e25abb4`.
  Se construyó desde un worktree limpio del commit `9b5cc36` y se publicó antes
  del servidor porque el contrato nuevo añade `fuera_ranking`.
- **Verificación viva:** 62/62 archivos no imagen coincidieron por SHA-256 y
  12/12 imágenes respondieron 200. Tres lecturas consecutivas de
  `version.json` devolvieron el build nuevo; el ZIP y `.vite/license.md`
  respondieron 404. Tras purgar la caché, el asset principal anterior quedó en
  404.
- **Servidor:** se aplicaron y registraron
  `20260902202247_crm_ranking_foto_mensual_coherente` y el ajuste incremental
  `20260902224847_crm_conversion_total_analistas_solo_ranking`. El segundo no
  exigió otro despliegue frontend: solo alinea `total.analistas` con las filas
  que ya mostraba el bundle.
- **Prueba viva final:** agosto 16/16 filas en Conversión, Capital y Cosecha;
  tres identidades externas y ninguna en posiciones; septiembre 17/17. La
  conversión quedó en 6,79 % para agosto y 4,95 % para septiembre. Censo 30/30,
  owner/ACL/`SECURITY DEFINER`/`search_path` verificados.
- **Rollback frontend inmediato:**
  `crm-20260902T170713Z-e9d9a283175b`. Las migraciones conservan el mismo
  contrato público y solo sustituyen núcleos existentes; cualquier reversión
  de servidor debe hacerse con un SQL focal auditado, nunca borrando fotos.

Relacionado: [[Produccion fuera del ranking (decision 2026-09-02)]] ·
[[Rankings por mes calendario (decision 2026-09-02)]].
