# Casos complementarios autorizados — 15/09/2026

Miguel aprobó usar las veinte inversiones reales revisadas como muestra y
completar los casos ausentes en una copia aislada: «sii claro hazlo».
La aprobación corresponde al método de prueba; las firmas G7 y la activación
general siguen pendientes. No se crearon operaciones ficticias en producción.

## Resultados

| Control | Resultado y evidencia |
|---|---|
| Seis recorridos exigidos | PASS sintético: Avance→Qorilazo, Qorilazo→Avance, Qorilazo→Prodelco, segunda Qorilazo, Prodelco→Avance y Avance→Prodelco |
| Recuperación de acceso | PASS: pérdida de respuesta después de crear Auth, registrar Auth, crear perfil y enlazar; cada recuperación deja un acceso y una inversión. Anónimo, cliente y analista ajeno rechazados sin efectos; tokens cruzados/inventados rechazan mientras está pendiente |
| Monedas | COOPAC rechaza USD antes de guardar; Avance admite USD. Fichas y totales agrupados por empresa/moneda coinciden con el núcleo |
| Lectura y acceso | Sesiones Auth reales de prueba: vendedor, supervisor y Gerencia leen sus fichas; otro analista recibe `null`, sin datos. El cliente entra a su contrato; otro analista no lo lee |
| Retiro | Solicitud y revisión por Gerencia, denegación al vendedor y reintentos; contratos/cierres económicos idénticos |
| Anulación comercial | Inversión anulada, un evento; Capital conserva importe, moneda, fuente, fechas y atribución, mostrando el nuevo estado |
| Identidad provisional | Fixture explícito sin documento verificado: P0409 con mensaje específico y sin guardar solicitud; al verificar, permite continuar |
| Cotitular | Titularidad contractual y canónica única, sin duplicar persona, Auth ni stock |
| Upgrade y renovación | Stock 800, capital renovado 700, adicional 100. Reasignar la cabeza mueve atribución viva de la renovación y conserva autor |
| Mes sellado | Agosto con dos fotografías reales del ensayo; reasignar e invertir después no cambia ninguna fila del sello. Fecha comercial conservada, imputación al mes vivo y ajuste único |
| Modo general | 56 contextos SQL presentes en el banco acumulado, incluidos clientes de corridas previas. Seis casos especiales, cuatro lecturas ajenas y dos Directorio conservados; todas las páginas y 44 fichas por Directorio comprobadas |

[15 grupos HTTP](casos-http.json) y [3 grupos financieros](casos-finanzas.json)
PASS. El suplemento financiero termina en ROLLBACK y compara doce tablas,
incluyendo banderas, perfiles, inversiones, solicitudes, ajustes y Storage.
Los 56 contextos son una descripción del banco acumulado, no 56 casos de negocio
independientes ni usuarios productivos. El número crece con las corridas HTTP.

## Procedencia y límites

- Base fija `g7_cierre_20260915`, copia sintética local; ningún ejecutor acepta
  un proyecto, URL remota ni nombre de base alternativo.
- Auth, PostgREST y Storage locales reales; los comprobantes se suben como
  bytes. El handler versionado `crm-inversion-portal` corre en Node con tráfico
  restringido a `127.0.0.1`; no se ensaya el entrypoint Deno ni el navegador.
- Las operaciones HTTP usan JWT de cuentas sintéticas. El suplemento SQL y la
  matriz de roles preparan fixtures con el administrador local y cambian a
  `authenticated` para ejecutar las operaciones y lecturas del producto.
- [203 funciones y tres auxiliares](cotejo-casos.json), propietarios/ACL,
  columnas y restricciones de tres tablas coinciden con la
  [captura productiva READ ONLY de 23:56:17 UTC](captura-versiones.json).
  Consulta, captura, inventarios y ejecutores están vinculados a los recibos
  mediante SHA-256. Se alinearon dependencias ya publicadas, incluyendo el
  sujeto obligatorio de solicitudes y el default PDF v9. No es paridad de todo
  el esquema, de todos los triggers o de todas las políticas RLS.
- Los tres contenedores propios terminan detenidos y eliminados. La copia SQL
  y el volumen `avancecorp_g7_objetos_20260915` conservan fixtures/comprobantes
  para inspección. No se creó un banco remoto de pago.
- También permanecen propietarios Auth/Storage, configuración REST por base y
  teléfonos sintéticos faltantes. Auth usa una lista explícita de configuración,
  sin SMTP, hooks ni proveedores externos. La red Docker se comparte con el
  banco fuente; los destinos de datos y HTTP están fijados a la copia.
- No se generó el PDF ni se probaron sesiones humanas productivas. No hay
  cálculos de comisiones, firma financiera ni autorización de apertura en estos
  recibos. El ensayo de mes sellado no sustituye el ciclo real de G8.
- El alta conserva la política previa de clave inicial por documento y marca
  `debe_cambiar_password=true`; no se comprobó el cambio por navegador. Faltan
  en este suplemento reanudaciones HTTP simultáneas, negativos Storage y revisión
  HTTP obsoleta. No se presentan las carreras SQL como prueba de esos escenarios.

Claude entregó [CHANGES_REQUESTED](REVISION-CASOS-CLAUDE.md). Se corrigieron los
ejecutores y se repitieron sus ensayos; el dictamen permanece original.
[Evaluación PRIMARY y límites](EVALUACION-CASOS.md). Dos pruebas deliberadas
comprueban que una captura alterada o la falta de Docker invalidan un PASS anterior.

## Ajustes del ejecutor durante la preparación

La copia había perdido propietarios Auth/Storage al restaurarse como postgres;
su configuración REST heredaba un esquema GraphQL ausente y un bind de macOS
no admitía los atributos extendidos exigidos por Storage. Se restauraron los
propietarios de esos servicios en la copia, se configuró REST **solo para esa
base** y se usó un volumen Docker propio. No se modificaron roles globales.

También se corrigieron expectativas del oráculo: las COOPAC usan soles, una
ficha ajena devuelve `null`, la anulación sí cambia estado/anulado y el número
de clientes del banco crece con Auth. Directorio puede leer un perfil del Portal
todavía sin contratos; se comprueba que no vea fuentes/totales COOPAC.
No se cambió el producto para forzar PASS.
Las corridas intermedias quedaron FAIL; los recibos finales son los ensayos
completos terminados correctamente.

## Refresco productivo

El conector volvió a responder. [Corte 18:32:41 Lima](refresco-final.json):
**614 inversiones, 468 personas y cero diferencias internas**. Hay una nueva
inversión Avance desde el corte anterior; es actividad normal. Banderas,
control nominal, siete definiciones y las 16 filas del sello de agosto siguen
idénticos. La muestra de veinte y sus diecinueve fichas conserva su corte
original; no se presenta la muestra recalculada como una nueva prueba de fichas.

Antes de activar: completar aceptación/conformidad G7, preparar y ensayar el SQL
productivo exacto de apertura y reversa, confirmar que el código publicado y
los permisos siguen vigentes y ejecutar el procedimiento de soporte.

## Reproducción

Desde la raíz, con la copia acumulada y las imágenes locales existentes. Esto
repite los ensayos sobre ese banco; no reconstruye desde cero todo el esquema.
Si el primer cotejo detecta otra deriva, detenerse y actualizar su captura/DDL
solo desde la versión productiva autorizada. No adaptar el inventario para ocultarla.

```sh
docker exec -i supabase_db_avancecorp-f5-bank psql -X -qAt -U postgres -d g7_cierre_20260915 -v ON_ERROR_STOP=1 -f - < CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/dependencias-local.sql
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/banco-http.mjs --inventario
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/casos-http.mjs
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/casos-finanzas.mjs
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/roles-general-local.mjs
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/banco-http.mjs --inventario
node --test CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/integridad-recibos.test.mjs
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/verificar-evidencia.mjs
npm --prefix CRM-Avance-Corp run check:scripts
```

El wrapper de roles usa `supabase_admin` solo para sus fixtures Auth; las
comprobaciones cambian a `authenticated`. Corre después de HTTP e incluye sus
clientes nuevos; termina en ROLLBACK. El cotejo final debe ser posterior a los
tres ensayos para superar el verificador. La captura productiva se obtiene con
`capturar-versiones.sql` mediante el conector Supabase del proyecto indicado en
el recibo; no contiene credenciales ni se ejecuta como migración.
