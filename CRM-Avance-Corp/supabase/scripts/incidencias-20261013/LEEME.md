# Incidencias PostgreSQL del 13/10/2026

Estado: **F7 y optimización SLA aplicados y verificados en producción** mediante
merge de `banco-f7` el 14/10/2026 a las 02:38 UTC (13/10 en Lima). El transporte
que bloquea consultas sin sesión está publicado y verificado en el frontend desde
el 13/10 a las 22:19 Lima. [Acta de publicación](PUBLICACION.md).

## Cambios

- F7: la migración de Coordinación cambió el cuerpo de `crm.metricas_cartera_fn(date)`.
  La corrección reconoce exclusivamente ese cuerpo y conserva el cierre de acceso.
- Rendimiento: `sla_operacion_leads` agrupa tareas una sola vez por lead.
  Elimina un recorrido completo del CTE por cada lead, sin ampliar tiempos límite.
- Sesión: el transporte del cliente CRM devuelve un 401 local si el SDK entrega
  la clave pública en lugar del JWT. Evita enviar consultas anónimas durante una
  pérdida de sesión o refresh fallido. No cierra la sesión, no repite escrituras,
  permite Auth/refresh y mantiene la autorización del servidor.

## Evidencia de verificación

14/10/2026 UTC (13/10 en Lima):

| Prueba | Resultado |
|---|---|
| `app/npm run check` | PASS integrado con `avancecorp/main` db63676b: 419 archivos, 6.689 tests; lint, tipos, cobertura, build, bundle y duplicación |
| Transporte CRM | PASS: 13 tests, incluyendo cliente compartido real, concurrencia, token renovado y escritura no reenviada |
| E2E Docker de sesión, refresh/foco y cierre de sesión | PASS integrado con main: 3 tests, 11,0 s; primera pasada 3 tests, 41,3 s |
| Banco SQL | PASS: rechazos F7/SLA, 6 ámbitos del núcleo, 44 pares de RPC y 9 casos límite |
| F7 | PASS: 15 piezas, candado activo, rechazos de sello repetido/ACL/atributos |
| SLA, avisos, cola v3 y Gestión Diaria | PASS |
| Reversa SLA y reaplicación | PASS; huellas exactas y permisos preservados |
| `check:scripts`, preflights seed/RLS | PASS; preflights offline con valores sintéticos, sin conexión |
| `gen:types` | PASS; firmas públicas/CRM iguales a main vigente; solo difiere el comentario generado de metadatos HTTP |
| Revisión Claude / auditor RLS | CHANGES_REQUESTED; puntos evaluados y corregidos por PRIMARY, ver resolución |
| Matriz HTTP remota `test-rls.mjs` | PASS: 3.931 aserciones; grupo A exigido. Restauración del timestamp corregida por separado, ver reconstrucción |
| Merge Supabase y postflight | PASS: versiones `20261014013757` / `20261014013830`, 473 registros anteriores intactos, solo delta SLA y huella/nota F7 |
| Vigía F7 productivo | PASS: 15 piezas, cero alertas F7 abiertas; cierre 02:39:01 UTC |
| Advisors posteriores | PASS sin avisos nuevos; las incidencias anteriores se conservan |
| Edge Functions después del merge | PASS: 23/23 con contenido, JWT, entrada e import map equivalentes |
| Publicación del frontend | PASS: PR #273 fusionado, `$release-crm` humano, Main e791502f; portada y 121 JS/CSS idénticos, acceso sin errores. Detalle en PUBLICACION.md |

EXPLAIN ANALYZE del núcleo completo, con hechos reales del banco y datos sintéticos:
2.009 leads, 6.860 tareas nuevas; 667,874 ms antes / 301,780 ms después. Primera
pasada independiente: 878,721 / 445,102 ms. Es evidencia local, no un compromiso
de latencia productiva. El coste restante de los hechos y de las RPC exige
observar carga real; las mediciones productivas puntuales figuran a continuación.

Mediciones posteriores en producción, con el mismo corte solicitado y consultas
de solo lectura: núcleo **1.808,639 → 1.244,137 ms**, con 3.594 filas en ambos;
`gestion_diaria_equipo_fn`, bajo rol authenticated y gerencia activa,
**1.644,650 → 1.369,887 ms**. Son EXPLAIN puntuales, sin promesa de latencia HTTP
ni de ausencia de timeouts bajo carga. El banco remoto sintético midió
2.383,839 → 873,048 ms. [Evidencia estructurada](EVIDENCIA.json).

Los 44 pares cubren cuatro RPC (`cola_accion_v3_fn`, `gestion_diaria_analista_fn`,
`gestion_diaria_equipo_fn`, `gestion_diaria_pulso_fn`) con 10 actores del banco y
sin identidad. Coinciden respuesta completa y SQLSTATE. `anon`, `authenticated`
y `service_role` siguen sin EXECUTE del núcleo privado; `anon` sin USAGE de `crm`.

## Reproducción local

Banco Docker preparado: `supabase_db_avancecorp-pr190-20261006`, base separada
`crm_incidencias_verificadas`; nunca se modificó la base original `postgres`.
Es una copia de fixtures locales con las funciones implicadas y las 15 filas
del catálogo F7 contrastadas con producción; no contiene datos comerciales
copiados de producción. El banco tiene nueve FK históricas no validadas y una
tabla de metadatos de cron que no ejecuta trabajos: no sustituye al gate remoto.

Desde la raíz del CRM, con ambas migraciones instaladas en ese banco:

```sh
python3 supabase/scripts/incidencias-20261013/probar-local.py \
  supabase_db_avancecorp-pr190-20261006 crm_incidencias_verificadas
```

Todos los fixtures y mutaciones negativas terminan en rollback. `oraculo.sql`
usa la definición anterior preservada y compara las seis columnas JSON del
núcleo. `rpc-paridad.sql` alterna las dos definiciones en una transacción y usa
`SET LOCAL ROLE authenticated` con identidad; no equivale a una sesión HTTP.

## Bloqueos y línea base ajenos al cambio

La rama Supabase existente `banco-f7` (`cwkiejoaqadcnaieghnf`) se intentó actualizar
desde producción. El replay terminó `MIGRATIONS_FAILED` el 14/10 a las 00:27:25 UTC:
`F2.b b4: crm.reservar_conversion_lead(uuid) no es el texto vivo esperado
(c9fc656c5f9b57d0688a5ecccd747e73)`. Miguel autorizó reconstruir ese banco: se
preservó su respaldo privado y se instaló el esquema vigente con datos sintéticos.
No se reejecutó ni alteró el historial. [Reconstrucción y scripts](remoto/LEEME.md).

El guardián analítico general ya detecta contadores no declarados y huellas
desfasadas en producción. `assert_gestion_diaria_pulso()` falla por esa deriva
también en el banco. No se han declarado como correctos ni actualizado en masa
sus sellos. Los cuatro guardianes específicos del cambio pasan.

Los advisors de producción, antes de aplicar, devuelven 5 categorías de seguridad
y 6 de rendimiento. Tras aplicar conservan exactamente los mismos hallazgos:
no se declara la base libre de avisos. Referencias de la línea base:
[RLS sin políticas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
y [funciones DEFINER públicas](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable).
`scripts/codex-review-mcp --check` falla porque `in_app_local_automation` no está
deshabilitada en ese wrapper; no se cambió configuración como parte del arreglo.
La revisión Claude se ejecuta por su wrapper separado, con herramientas y MCP
deshabilitados.

Dictamen original: [REVISION-CLAUDE.md](REVISION-CLAUDE.md).
Evaluación y correcciones: [RESOLUCION-REVISION.md](RESOLUCION-REVISION.md).

## Aplicación y reversa

1. Completado: reconstrucción autorizada, SQL, gate HTTP, advisors y premerge con
   capturas de menos de 60 segundos. Merge Supabase aceptado y aplicación verificada.
   El proyecto prohíbe `apply_migration` directo a producción.
2. Completado: huellas, atributos, catálogo completo, ledger y vigía F7. El merge
   separó los SQL en 10/8 sentencias; solo difieren los separadores y líneas vacías
   entre sentencias respecto de los archivos inmutables. Versiones conservadas;
   huellas del array de sentencias productivo registradas en la evidencia.
3. Completado: frontend publicado mediante la invocación humana `$release-crm` y
   comprobado por HTTP/navegador. La observación de solicitudes anónimas y timeouts
   bajo carga posterior queda fuera del smoke; no se promete ausencia absoluta.

`reversa-sla.sql` restaura exactamente la función anterior y pasa sus guardianes;
se convierte en una migración nueva, sin borrar historial. F7 no cambia el
comportamiento: revertir solo el sello volvería a crear la alerta. Una reversa
de Coordinación debe restaurar conjuntamente el cuerpo autorizado y su sello,
en una migración aparte y con su propia validación.
