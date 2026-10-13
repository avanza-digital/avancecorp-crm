# Renovaciones sin aporte a conversión · 12/10/2026

Decisión de Miguel: quitar renovaciones **a nivel de sistema**. Desde octubre
de 2026, todavía abierto, su peso pasa de 0,15 a **0**. Los meses cerrados
conservan sus fotos y la versión de pesos de julio conserva el histórico.

Migración: `../../migrations/20261012184345_crm_conversion_sin_renovaciones.sql`.
Reversa: `reversa.sql`, que se niega si hay meses afectados sellados o cambió
la configuración. No modifica el historial de migraciones: el circuito de
publicación debe registrar tanto la aplicación como cualquier reversa.

Estado: **ACTIVA EN PRODUCCIÓN** desde el 12/10/2026, versión remota `20261012213521`.
Ver [acta de publicación](PUBLICACION.md) y [evidencia productiva](activacion.json).
Se completó el circuito de rama Supabase, gates y merge de
`supabase/migrations/LEEME.md`. Las ramas remotas existentes (`banco-f7` y
`plan-backend-fase4`) pertenecen a otros trabajos y figuran `MIGRATIONS_FAILED`.
No se han reutilizado ni alterado.

## Alcance

- Solo cambia `crm.conversion_pesos.peso_renovacion` para la versión de octubre.
- Default cero y CHECK para versiones desde octubre impiden reactivarlo por omisión.
- Referido sigue con peso 1 y tope 15 %; upgrade elegible sigue con peso 1.
- Las operaciones, el capital, la atribución y la API conservan su estructura.
- Se mantiene una **primera operación elegible por cliente/mes**: si primero
  renueva y después hace upgrade, la operación elegida sigue siendo renovación,
  ahora con aporte cero. Liberar ese cupo sería otra decisión comercial.
- La migración y su reversa comparten el candado global de `cerrar_periodo` y
  bloquean las escrituras sobre configuración y periodos durante la comprobación.

## Evidencia del ensayo

Banco Docker propio: `avancecorp-conversion-sin-renovaciones-20261012`, puerto
local `55482`, Postgres `17.6.1.105`. Esquema descargado de producción sin datos
personales; configuración de pesos, política y censo copiada en modo lectura.
Las siete funciones relevantes tienen las mismas huellas que producción.
La carga del esquema tiene únicamente la ausencia esperada de `storage.objects`
en la imagen PostgreSQL; no interviene en estas pruebas.

`prueba.sql`: **22 comprobaciones PASS** con fixtures sintéticos y rollback:
pesos, futuro, primera operación, septiembre idéntico, divisor y tope,
cartera e importes no vacíos PEN/USD, oficial/Coordinación/Metas, sellado y
lectura de foto, default, restricción futura y denegación de lectura/escritura
de la configuración para `authenticated`.

El sellado usa septiembre con peso cero solo dentro del ensayo: octubre sigue
en curso y la puerta real prohíbe sellarlo. No se ha simulado que octubre ya cerró.

También PASS: ejecución completa de la migración, reversa y reaplicación;
rechazos ante octubre cerrado, pesos distintos, versión futura y doble
aplicación; espera del candado de sellado en otra conexión (2,02 s).

Frontend: **108 pruebas PASS** de `conversion-vendedores`, `conversion-mensual`
y `conversion-coordinacion`; incluye regresión de peso cero frente a referido 1.
Typecheck PASS; lint PASS con avisos ajenos; `git diff --check` PASS.
No cambia ningún tipo de columna, firma RPC ni payload TypeScript.

Rama `conversion-sin-renovaciones-20261012` (`bnevvswisucbaowjpewn`): **22 SQL PASS**
y **319 aserciones PASS** de `test-rls.mjs --contratos` con sesiones Auth reales.
Es la matriz de contratos, jerarquía y banca; la matriz RLS global y E2E: **NOT RUN**.
No cambia código de pantalla ni se publica frontend.

El replay histórico falló en el punto conocido tras 86 migraciones. Se reconstruyó
solo la rama vacía desde el esquema actual, sin clientes: 1.067 funciones,
1.489 columnas, 382 disparadores, 111 policies y las 463 migraciones previas
coinciden. Tres CHECK normalizan paréntesis de AND sin cambiar su predicado.
El CHECK de atribución recuperó su carácter CR literal antes del ensayo.
Las 23 Edge conservan hashes, versiones y configuración iguales al padre.
La reconstrucción, configuración y fixtures no se registran como migraciones.

Candidata remota: `20261012202228`, SHA-256
`2eaeedc130cf7c629126328f33865d180400fb7956231d2b176e6a4f1327c56c`,
idéntica al archivo. Advisors antes/después: 364 seguridad y 343 rendimiento,
**cero altas/bajas**; los avisos heredados permanecen.

Review independiente: CHANGES_REQUESTED sin P0/P1. Se corrigieron las guardas de
nota no nula, default y nulabilidad, y el bloqueo exclusivo inicial; se verificaron
candado concurrente y auditoría, y se repitió el ciclo real migración/reversa/pruebas.
La hipótesis de NULL no aplica: la columna ya es NOT NULL. Ver `verificacion.json`.

Ejecutar desde la raíz CRM, solo contra el banco propio:

```sh
PGPASSWORD=postgres /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 55482 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f supabase/scripts/conversion-sin-renovaciones/prueba.sql
npm --prefix app run test:run -- src/lib/conversion-vendedores.test.ts \
  src/lib/conversion-mensual.test.ts src/lib/conversion-coordinacion.test.ts --maxWorkers=2
```

Medición agregada de producción, solo lectura, 12/10/2026: en octubre existen
2 episodios de renovación que aportan 0,30; el numerador bruto era 37,30 y el
divisor 779. Con los mismos registros, el cambio deja el bruto en 37,00.
Estas cifras son la foto de esa consulta, no un valor fijo del sistema.

## Figma

[Conversión del analista · Gerencia](https://www.figma.com/board/tO6Lpx3ieJ6QuwUxfZcSvM?node-id=50-19).
Se reemplazaron los 12 bloques anteriores por una sola vista: cuatro pasos,
regla de referidos y ejemplo. El aviso visible confirma que el cambio está activo en el sistema, tras verificar
producción. Captura final revisada sin recortes.
