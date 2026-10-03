# Rama con datos + gate de RLS — 02/10/2026 (noche, sesión 119d2a01)

**Veredicto:** las 7 migraciones (B1, B1b, B2, B3, B4, B4b, B3b) están listas para el merge de Miguel. Aplican sobre la copia
de producción con datos, no hacen falta índices nuevos, no añaden alertas nuevas fuera del patrón de diseño, y el gate de
RLS completo no tiene ningún rojo nuevo (base para gestión 74/74).

**Sin contraseña de BD.** El MCP de Supabase no estaba conectado en la sesión. Todo pasó por la Management API: la CLI
(`supabase db query --linked --project-ref dpjojnpfcwkeikyagtxj --workdir <carpeta aparte>`), en una carpeta del scratchpad
enlazada SOLO a la rama. La carpeta compartida sigue enlazada a producción. Es la misma vía del merge (`db query --linked --file`).

## 1. Rama `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`)

| Paso | Resultado |
|---|---|
| Estado antes | B1–B4b false · **intentos previos 0** (acredita el punto (a) de Codex r2) · historial 411 versiones, última `20261002163158` · 2806 leads · 1078 descartados vivos · 26 analistas |
| Aplicar | 7/7 sin error, en orden y un mensaje cada una |
| Estado después | las 7 true · 0 intentos, 0 reactivados, 0 enfriados, 0 rellamadas (los postflights deshacen sus ensayos) |
| ACL de las puertas | `obtener_base_gestion`, `registrar_intento_base`, `reactivar_lead_base`, `base_gestion_resumen`, `levantar_no_contactar`: EXECUTE solo `postgres` y `authenticated` |

**EXPLAIN (ANALYZE) con datos reales** (analista con más descartados: 149):

| Consulta | Plan | Tiempo |
|---|---|---|
| Base por analista | índices `idx_leads_etapa` + `idx_leads_vendedor_creado_en` | 1,7 ms |
| Llamar hoy | `idx_leads_base_rellamada` (B1b) | 0,05 ms |
| Total descartados (supervisión/gerencia) | `idx_leads_descarte` | 0,8 ms |
| `obtener_base_gestion()` como analista | 149 filas | 73 ms |
| `obtener_base_gestion()` como gerencia | 1069 filas | 78 ms |
| `obtener_base_gestion()` como supervisores | 441 / 628 / 0 / 0 filas | 128 / 137 / 98 / 82 ms |
| `base_gestion_resumen()` como gerencia | 26 filas | 50 ms |

Sin SEQ SCAN: **la B5 de índice NO hace falta**.

**Advisors** (`supabase db advisors --linked`, todos los niveles), antes 630 → después 623: 0 ERROR. Solo 4 WARN nuevas, todas
`authenticated_security_definer_function_executable`: son las 4 puertas, el patrón por diseño del CRM (ya hay 238). Ninguna
nueva en `anon_*`. Las 11 INFO `unused_index` que desaparecen las borró el propio EXPLAIN.

## 2. Gate de RLS en banco Docker propio, a paridad total

- Stack propio `avancecorp-base-gestion-20261002` (puertos 569xx: db, auth, rest, kong, storage). Worktree aparte en `c0a72f50`.
- Carga sin errores: esquema `public,crm,private` volcado de la rama, 24 tablas de configuración (1842 filas, sin datos
  personales), 5 buckets y 19 políticas de storage, roles `crm_metricas_bridge` y `crm_gestion_diaria_lector`. ACL igualadas
  a la rama: funciones, tablas, columnas, secuencias y privilegios por defecto.
- **Paridad acreditada por huellas:** el banco quedó idéntico a la rama. Coinciden los cuerpos de crm 292, private 568 y
  public 38 funciones; las ACL; las 108 políticas; las 137 relaciones; los 344 triggers y `auth.uid`.
- **Reversas B3b → B1 en el banco → huellas idénticas a PRODUCCIÓN** (crm 288, private 558, 341 triggers). Eso acredita las 7
  reversas y que producción no cambió desde que se creó la rama.
- La reversa de B1b falló la primera vez por el CHECK de B1, porque había intentos con fecha que dejó el gate. Tras limpiar
  esos datos pasó. Ver riesgos.

| Corrida | Aserciones | Rojos | Base para gestión |
|---|---|---|---|
| ANTES (= producción) | 2418 | 77 | bloques B1/B3 saltados; 9 rojos `#5 B2` (B2 no está) |
| DESPUÉS (las 7 + test corregido) | 2483 | 68 | **74 ✓ / 0 ✗** |

Rojos que solo salen DESPUÉS: **ninguno**. Los que solo salen ANTES son los 9 de `#5 B2`. Los 68 restantes son de fondo y
aparecen idénticos en las dos corridas: cola v3 (23), postventa, cortes, tareas, fila bancaria. Son huecos de fixtures del
banco, no efecto de estas migraciones.

- Al reaplicar las 7 sobre el banco = producción, los 7 postflights dieron OK y las huellas volvieron a ser las de la rama.
- **Hallazgo del gate:** había 2 expectativas viejas en el bloque B1 de `test-rls.mjs`. Con B3, el sello
  `trg_00_actividades_base_gestion_solo_nucleo` corta el INSERT directo de `intento_base` con 42501 antes que «claves del
  núcleo» y que el CHECK. Este último sigue acreditado fuera de banda. Corregido en `72189f04`; `check:scripts` PASS.
- **Registradores** en `supabase/scripts/base-gestion/registrar/<version>.sql`, uno por migración, generados con
  `potencial-lead/banco/generar-registrador.py`. Su `statements` es el archivo entero y el md5 coincide con el archivo.
  Probados dos veces en el banco: registran las 7 y la segunda pasada no duplica.

## 3. Riesgos que quedan

- La reversa de B1b no corre si ya hay intentos con fecha: el CHECK de B1 no los admite. Con el módulo en uso, revertir B1b
  exige tratar antes esas actividades. Hasta el primer intento real, la reversa está limpia.
- `obtener_base_gestion()` devuelve a gerencia las 1069 filas de una vez (78 ms). En F4 conviene filtrar por analista o paginar.
- Hasta el merge, el gate de cualquier otra sesión con `test-rls.mjs` de `main` verá los 9 rojos `#5 B2`, porque B2 aún no
  está en su base.
- El postflight de B4 ensaya por la puerta sobre un lead real con un candado breve: aplicar fuera del horario de gestión.
