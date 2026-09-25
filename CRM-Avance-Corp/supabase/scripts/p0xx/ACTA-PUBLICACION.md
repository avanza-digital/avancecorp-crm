# P-0XX — acta de publicación (25/09/2026)

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
