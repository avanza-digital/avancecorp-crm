# P-0XX — acta de publicación (25/09/2026)

> **Servidor, portal y CRM publicados.** Miguel autorizó el frontend con
> `$release-crm`; el PR #106 quedó integrado y `crm.miavance.com` sirve el build
> `build-20260925T220850705Z` desde Main `caf999794655`. El formulario compatible
> registra cuentas por RPC y acepta `origen='portal'`. Quedan las conciliaciones
> de datos y las dos advertencias de seguridad documentadas abajo; no se declara
> cumplido el criterio literal de cero excepciones.

Miguel autorizó explícitamente una excepción a la instrucción inicial de que
solo él fusionaría la rama Supabase. El Merge Request por diff de esquema se
cerró sin aplicarlo porque omitía el backfill de datos y proponía borrar
objetos ajenos. Se aplicaron **solo** las cuatro migraciones P-0XX ya ensayadas
en la rama, en orden S1 → S3 → S4 → S2. El CRM se publicó después, con la
autorización específica registrada al final de esta acta.

## Aplicación productiva

| Sprint | Migración registrada en producción | Resultado |
| --- | --- | --- |
| S1 | `20260925211205 p0xx_cuentas_cliente_backfill_lectura` | 241 cuentas y 257 vínculos insertados |
| S3 | `20260925211253 p0xx_pagos_solo_cuenta_contractual` | Guardas de pago por contrato habilitadas |
| S4 | `20260925211308 p0xx_portal_cliente_mis_cuentas` | RPC personal de lectura instalada |
| S2 | `20260925211353 p0xx_cuentas_cliente_escritura` | Escritura versionada y bloqueo de escritura bancaria en perfil |

Después de S2 se desplegaron `crear-cliente` v38,
`crm-convertir-lead` v20 e `importar-clientes` v18. Sus hashes coincidieron con
los de la rama. El portal está publicado en Hostinger desde el ZIP del commit
local `717e4c199f2991e73b4dc00b9e08f0c1acdb040e` (SHA-256
`e9d2afaab37f4a9c4b194fe759fda478434c479aa156e8472d74bd29cd733f7b`).
Los 15 archivos publicados que cambiaron en ese commit respondieron HTTP 200
y coincidieron byte por byte con el ZIP. El service worker usa `avance-v123`.

## Verificación y conciliación

- Verificación productiva de solo lectura: 241 cuentas y 257 vínculos figuran
  en `private.backfill_cuentas_p0xx`, con `marca_actor='migracion:p0xx:s1'`.
  Los triggers de auditoría registraron los 498 inserts; en esa ejecución
  `usuario_id` es `NULL` y la marca identifica la migración.
- Quedan **23 contratos activos sin vínculo**: 16 sin cuenta y 7 con varias
  candidatas. El reporte nominal con cliente, DNI, moneda y analista está en
  `_DEV_NO_SUBIR/releases/p0xx-conciliacion-actual-20260925.csv` (24 líneas,
  incluido encabezado; permiso 600). Coincidió exactamente con la proyección
  previa al despliegue. Ninguno se vinculó por aproximación.
- La query `verify-s1-validos-sin-equivalente.sql` contó **501** perfiles
  bancarios válidos y **3** sin equivalente activo por mismo CCI con otros
  datos. Requieren una decisión de Operaciones; el criterio literal de cero
  excepciones no se cumplió. No se reemplazaron las cuentas CRM.
- Caso testigo `02650333`: BCP PEN terminada en **6087** y BCP USD terminada
  en **9168**. La persona usuaria confirmó visualmente el 25/09 que las
  cuentas cargadas en CRM aparecen también en el portal.
- Backfill reejecutado en rama: **0** cuentas y **0** vínculos nuevos. Modos de
  contrato `existente`, `nueva` y `perfil` ensayados en rama. La matriz pertinente
  HTTP/RLS de contratos y cuentas pasó después: **287/287**. El conjunto global
  de otros dominios CRM sigue `NOT RUN`; no se atribuye a esta verificación.
  No se creó una cuenta bancaria ficticia en producción para probar la escritura.
- Security Advisor productivo: dos WARN nuevos para las dos RPC
  `SECURITY DEFINER` ejecutables por `authenticated`, ambas con autorización
  interna. El criterio literal de «sin hallazgos nuevos» queda abierto. El
  Performance Advisor no añadió tipos de hallazgo nuevos.

## Código y límites de entrega

- CRM: los commits P-0XX se integraron mediante PR #106, conservando Main remoto.
  La copia limpia de publicación tenía `main = avancecorp/main = caf999794655`.
  El árbol original conserva sus cambios ajenos sin confirmar; no fue fuente
  del paquete ni se sobrescribió para sincronizarlo.
- Portal: commit local `717e4c1`. El remoto GitHub del portal respondió
  `Repository not found`; el gitlink del repositorio padre aún apunta al
  commit anterior. La publicación Hostinger está verificada por separado.
- Checks finales de la integración limpia: CRM `npm run check` **PASS**, con
  **4440 tests**, lint, typecheck/build, configuración, bundle y duplicación.
  E2E local Docker **274 PASS / 26 SKIP / 0 FAIL**; HTTP/RLS **287/287 PASS**.
  Edge preflight y Deno check **PASS**; portal **112/112 PASS**. Los fallos de
  duplicación del árbol compartido no forman parte del código publicado.
- Quedan como deuda la conciliación de los 23 contratos y 3 discrepancias de
  perfil, el retiro futuro de columnas bancarias legado de `perfiles` y el
  modo `perfil` del alta de contrato. El bloqueo de pago protege los contratos
  sin cuenta vinculada. La rama temporal sigue disponible para investigar los
  pendientes y conserva un costo por hora.

## Verificación posterior y preparación del frontend CRM

- Snapshot de los 887 archivos versionados de `app/` contrastado byte a byte
  con el commit P-0XX: E2E completo en Docker, **267 PASS / 26 SKIP / 0 FAIL**.
  Un primer ensayo detectó que el enlace absoluto de `node_modules` en la copia
  temporal dejaba las fuentes fuera de la ruta de Vite; se retiró solo ese enlace
  temporal antes de la corrida válida. No se cambió código de producto.
- Matriz HTTP/RLS pertinente: `node supabase/scripts/test-rls.mjs --contratos`,
  **287/287 PASS** en `hhpjiygytwoayxymziqo`, con login real de los 13 usuarios
  ficticios de `fixtures.mjs`. Cubre acceso bancario por ámbito, roles, revocación,
  contratos y acceso anónimo. El conjunto global de dominios CRM queda sin ejecutar.
  Para montar el fixture se completaron por SQL privilegiado sus dos contratos,
  cuenta y vínculo: el seed genérico intenta hacerlo por API y no puede leer
  `crm.periodos_cerrados` desde ese trigger. No se ampliaron grants de tabla.
- La rama carecía del permiso `EXECUTE` de `service_role` sobre
  `public.contrato_tiene_pagos(uuid)`. Se comprobó la misma definición en ambas
  bases y el permiso existente en producción, y se reprodujo **solo en la rama**.
  Antes de repetir la matriz se restableció su fixture de domicilio y se
  desactivaron sus cuentas adicionales, sin alterar las cuentas P-0XX originales.
- Auditoría HTTP del CRM servido: `build-20260925T150218036Z`, 74 archivos JS
  descargados. `mi-cartera-BPDLxHJa.js` aún extiende el patch con `...r.bancarios`;
  ninguno de los archivos descargados llama `registrar_cuenta_cliente`. Esto
  prueba la incompatibilidad del formulario con la guarda S2 productiva.
- Se preparó una copia Git independiente desde `avancecorp/main` (`6d7be76f`)
  y se integraron únicamente los commits P-0XX. El único conflicto era el
  registro documental de migraciones; se conservaron ambas entradas. Las Edge
  Functions resultantes coinciden con las ya desplegadas. `npm run check` de
  esta combinación pasó: **4440 tests**, build/typecheck, lint, configuración,
  bundle y duplicación (0,49 % de líneas). Su E2E completo en Docker pasó:
  **274 PASS / 26 SKIP / 0 FAIL**. La publicación CRM requiere la invocación humana de
  `$release-crm`, según `CRM-Avance-Corp/CLAUDE.md` y la habilidad local.
- Se entregó un segundo reporte privado:
  `_DEV_NO_SUBIR/releases/p0xx-conciliacion-perfiles-20260925.md`, con los **3**
  conflictos (banco, número, titular/beneficiario, respectivamente) y los **17**
  grupos cliente/moneda con varias cuentas activas. Los valores bancarios están
  enmascarados. Su fuente de solo lectura es `reporte-conciliacion-perfiles.sql`.
  Estas filas pueden solaparse con los 23 contratos; no son clientes adicionales
  para sumar. No se decidió qué dato real prevalece sin evidencia de Operaciones.

La fuente CRM ya está respaldada en el [PR #106](https://github.com/avanza-digital/avancecorp-crm/pull/106)
desde una rama de trabajo que conserva `avancecorp/main` vigente. El árbol original
con trabajo ajeno no se cambió para hacer esa integración. El registro de migraciones
del PR se actualizó para indicar cuáles ya se aplicaron en producción.

Paquete candidato conservado, **nunca publicado**: `crm-20260925T215236Z-315f066b5767.zip`,
SHA-256 `d28dbf3144979060b719d4ed97e8315654e218b6b5a6c6219d86189e898398f1`.
El ZIP y manifiesto están conservados en `_DEV_NO_SUBIR/releases/p0xx-crm-candidato/`;
`release:crm:verify` pasó. Se reconstruyó después desde Main; el candidato no
se confundió con el artefacto efectivamente publicado.


## Publicación del frontend CRM autorizada con `$release-crm`

Miguel invocó explícitamente `$release-crm` el 25/09. El PR #106 quedó integrado
como **`caf99979465541b10014a66190e7a38e4083876e`**. El árbol `app/`, los scripts
CRM y las Edge Functions coincidían con el candidato ya verificado. Se reutilizó
esa evidencia y se ejecutó de nuevo `release:crm` y `release:crm:verify`: **PASS**.
Los cuatro controles de GitHub (app-check, cambios, preflight, verify) pasaron.
Antes de subir se comprobó nuevamente Main local/remoto idéntico y árbol limpio.

- URL: `https://crm.miavance.com`.
- Build: **`build-20260925T220850705Z`**.
- ZIP: `crm-20260925T220851Z-caf999794655.zip`.
- SHA-256: `f0ab9a500e87507b8d268cbb4fcb8452435d6fd00c437e0c4e42e5a261d550bc`.
- Publicación: MCP oficial Hostinger 1.59.0, `hosting_deployStaticWebsite`, dominio
  exacto; upload **success**, deploy **success / Request accepted**.
- Verificación posterior: portada **PASS**; **78/78 JS/CSS** HTTP 200 y SHA-256
  idéntico al manifiesto; `version.json` coincide. El código servido contiene
  `registrar_cuenta_cliente`. Los **116** archivos públicos responden HTTP 200;
  **104** coinciden byte a byte. Los otros **12 PNG** ya diferían antes de publicar
  y conservan exactamente sus bytes previos; no se atribuye un PASS de hash a
  esas imágenes ni se afirma una causa de esa diferencia sin evidencia.
- Navegador Chrome: acceso autenticado y pantalla Hoy de analista **PASS**.
  No se guardaron datos reales para probar. El ZIP no es accesible por la URL
  pública homónima: **HTTP 404**.
- Recuperación: ZIP/manifiesto del build anterior `build-20260925T150218036Z`,
  fuente `65e96df95511`, SHA-256
  `bf7351942b63599ee92531175ee45b696d5657035c843bd4f4839a437447e4ee`.
  Se guardaron aparte los 12 PNG servidos que diferían del ZIP.

Artefactos y evidencias privadas: `_DEV_NO_SUBIR/releases/p0xx-crm-publicado/`
y `_DEV_NO_SUBIR/releases/p0xx-crm-recuperacion/`. Un commit documental posterior
no cambia el commit fuente del despliegue ni exige publicar nuevamente.

## Resultado por fase y pendientes reales

| Fase | Entrega | Estado |
| --- | --- | --- |
| S1 | Lectura canónica, 241 cuentas y 257 vínculos, reversa y conciliación | Publicado; 23 contratos no conciliables y 3 discrepancias de perfil reportados |
| S2 | Registro versionado, validación compartida, edición por analistas/Gerencia y ficha CRM compatible | Servidor y frontend publicados; pruebas en rama aprobadas |
| S3 | Pagos/exportes desde cuenta contractual; bloqueo explícito sin vínculo | Portal y guardas productivas publicados |
| S4 | Lectura personal en portal y mismos valores en campos compartidos | Publicado; lectura de cuentas confirmada visualmente por Miguel |

Operaciones debe aportar datos para los 16 contratos sin cuenta, elegir con
respaldo la instrucción de pago de los 7 ambiguos y resolver las 3 discrepancias
con mismo CCI. No se elige una cuenta por aproximación. Se conservan como deuda
expresa las columnas bancarias de `perfiles`, su trigger y el modo `perfil` del
alta de contratos. Las dos advertencias del advisor para RPC autenticadas y el
criterio de cero perfiles válidos sin equivalente siguen documentados como
excepciones abiertas, sin atribuirles conformidad humana no recibida.
