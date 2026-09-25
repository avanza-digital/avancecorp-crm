# P-0XX — acta de publicación (25/09/2026)

> **Pendiente funcional identificado después de publicar el portal:** el frontend
> servido en `crm.miavance.com` aún es anterior a P-0XX. Su formulario de edición
> manda las claves bancarias al perfil, que S2 ahora rechaza. También le falta
> aceptar `origen='portal'`. Se debe publicar el frontend CRM compatible antes de
> cerrar el trabajo; la confirmación visual del portal no acredita ese formulario.

Miguel autorizó explícitamente una excepción a la instrucción inicial de que
solo él fusionaría la rama Supabase. El Merge Request por diff de esquema se
cerró sin aplicarlo porque omitía el backfill de datos y proponía borrar
objetos ajenos. Se aplicaron **solo** las cuatro migraciones P-0XX ya ensayadas
en la rama, en orden S1 → S3 → S4 → S2. No se publicó un build del CRM.

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
  contrato `existente`, `nueva` y `perfil` ensayados en rama. La matriz RLS
  integral quedó `NOT RUN` por falta de credenciales limpias; las pruebas
  específicas de autorización de P-0XX pasaron en rama. No se creó una cuenta
  bancaria ficticia en producción para probar la escritura.
- Security Advisor productivo: dos WARN nuevos para las dos RPC
  `SECURITY DEFINER` ejecutables por `authenticated`, ambas con autorización
  interna. El criterio literal de «sin hallazgos nuevos» queda abierto. El
  Performance Advisor no añadió tipos de hallazgo nuevos.

## Código y límites de entrega

- CRM: commits locales `f1a947b2`, `a06321ec`, `94ee1e2d` y esta acta.
  El árbol local `main` diverge de `avancecorp/main` y contiene trabajo ajeno;
  **no** se hizo push ni se publicó su frontend.
- Portal: commit local `717e4c1`. El remoto GitHub del portal respondió
  `Repository not found`; el gitlink del repositorio padre aún apunta al
  commit anterior. La publicación Hostinger está verificada por separado.
- Checks del snapshot P-0XX: CRM lint, typecheck, build, tests (4421/4421),
  Edge preflight y Deno check `PASS`; portal tests (112/112) `PASS`. La
  duplicación del árbol CRM compartido `FAIL` por archivos ajenos no
  confirmados. E2E CRM integral y matriz RLS `NOT RUN`.
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
  bundle y duplicación (0,49 % de líneas). Su E2E y publicación se registrarán
  al completarse. La publicación CRM requiere la invocación humana de
  `$release-crm`, según `CRM-Avance-Corp/CLAUDE.md` y la habilidad local.
- Se entregó un segundo reporte privado:
  `_DEV_NO_SUBIR/releases/p0xx-conciliacion-perfiles-20260925.md`, con los **3**
  conflictos (banco, número, titular/beneficiario, respectivamente) y los **17**
  grupos cliente/moneda con varias cuentas activas. Los valores bancarios están
  enmascarados. Su fuente de solo lectura es `reporte-conciliacion-perfiles.sql`.
  Estas filas pueden solaparse con los 23 contratos; no son clientes adicionales
  para sumar. No se decidió qué dato real prevalece sin evidencia de Operaciones.
