# F4 — ensayo remoto autorizado, 22/09/2026

## Estado actualizado: bloqueo de concurrencia remota

**No publicar todavía.** El ensayo identificó un defecto real: las dos RPC de
configuración devuelven `40001` ante una versión obsoleta. PostgREST hosted
14.5 reintenta ese código y la solicitud vence sin devolver el conflicto. El
diagnóstico inicial de transporte era incompleto: dos conexiones TLS separadas
permitieron observar las dos esperas reales y reproducir el fallo igualmente.
El banco local usa PostgREST 16.2; por eso su PASS anterior no cubría este defecto.
[Supabase documenta el problema](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).

Corrección preparada en `20260923021512_crm_gestion_diaria_conflicto_http.sql`:
solo `40001` → `PT409` en publicar política y controlar canal, más las dos
huellas del verificador. Mantiene candados, mensajes, permisos y datos. Es un
quinto archivo nuevo: **aplicación remota y publicación pendientes de autorización
adicional sobre el SQL exacto**, después del ensayo local en PostgREST 14.5.
Los cuatro archivos aprobados no se modifican. Producción conserva v1 OFF y
todavía no recibió ninguno de los cuatro nuevos SQL.

Avances acreditados después del resumen anterior:

- Main `e5957443` integrado en `e0ab5216`. `npm run check`: **4.158 pruebas / 277
  archivos PASS**; Docker **234 PASS / 26 SKIPPED / 0 FAIL**, 9,3 minutos.
- Once migraciones ajenas ya productivas, hasta `20260923013213`, incorporadas
  **solo al banco** desde un snapshot coherente: ocho cuerpos, comentarios y
  tres declaraciones técnicas; 331 entradas anteriores intactas. Ledger remoto
  342 = 338 productivas + cuatro F4. F4, ACL/owners y datos sintéticos preservados.
- Carga sintética: 2.200 leads añadidos y 15.400 actividades, 120 lecturas HTTP
  sin errores. p95 por equipo/modo entre 2,153 y 3,343 s. No son tiempos reales
  medidos en navegadores productivos.
- Rendimiento: los dos INFO originales de FK de política se difieren (una fila,
  sin consultas por esas FK). F4 agrega dos WARN `auth_rls_initplan`, en las
  policies internas de entregas/control; optimización futura, sin retirar RLS
  ni ampliar acceso. [Criterio](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan).
- Concurrencia HTTP remota: **FAIL**, no PASS. El último intento observó ambas
  peticiones bloqueadas; una confirmó y la otra venció por el problema `40001`.
  Los intentos anteriores dejaron versiones futuras OFF solo en el banco.
- Repetición posterior de `ensayar.mjs`: **FAIL de precondición del fixture**,
  pues el ensayo antiguo fija versión inicial 1 y el banco conserva las versiones
  auditadas de concurrencia. La transacción se revirtió. No sustituye ni invalida
  los PASS previos de las matrices 2.196/0; no se atribuye un PASS nuevo.

Evidencia privada: `avances-sincronizados.json`, `carga.json`,
`concurrencia-diagnostico-43.json`, `advisors-rendimiento-f4.json` en
`/private/tmp/gd-f4-remoto-20260922`; logs frontend
`gd-f4-check-main74-20260922.log` y `gd-f4-e2e-docker-main74-20260922.log`.

Los apartados siguientes conservan la secuencia previa; este estado prevalece.

## Permisos y estado productivo

Miguel confirmó la organización `fzxtxnkvslpcsscxqfbr`, autorizó «SQL,
conciliación y banco hasta US$1» sobre la propuesta exacta del PR #73 y luego
invocó `$release-crm`. Las autorizaciones siguen vigentes; no pedirlas otra vez.
Los cuatro SHA-256 de la propuesta no cambian.

La conciliación administrativa de etapa 3 **PASS y confirmada en producción**:
`20260922164159` → `20260921214018`, 33 sentencias y demás campos idénticos;
327 migraciones antes/después, seis gates PASS, v1 OFF conservada. No se reejecutó
SQL de etapa 3. Respaldo privado `gd-f4-ledger-etapa3-respaldo-20260922.json`,
preflight `gd-f4-preprod-autorizado-20260922.json` y readback
`gd-f4-ledger-conciliado-20260922.json`, en `/private/tmp`.

Los cuatro SQL nuevos están instalados **solo en la rama sintética**. Sus SHA-256
coinciden también con las sentencias guardadas por Supabase. Sus cuatro versiones
administrativas ya coinciden con los archivos canónicos; las 327 previas se
conservaron idénticas. Merge SQL, frontend y activación productiva: **NOT RUN**.
Los dos dictámenes recuperados de Claude siguen siendo CHANGES_REQUESTED;
resolución del PRIMARY documentada, sin atribuir PASS al reviewer.

## Banco propio y coste

- Rama `gestion-diaria-f4-cierre-20260922`, id
  `5ff71dc3-f44e-49b1-b648-86867231a984`, ref `vqfeicbqhrmiyihpxcsl`.
- Creada `2026-09-22T22:56:25.989974Z`, **with_data=false**.
- US$0,01344/h, tope US$1. Eliminar al terminar y, como máximo,
  `2026-09-23T22:56:25.989974Z`; verificar ausencia y calcular duración real.
- Dos Cron heredados se desactivaron solo en esta rama. Cero activos comprobados.
  Los nueve Cron productivos y la rama ajena `banco-f7` permanecen ajenos al ensayo.
- Directorio privado `/private/tmp/gd-f4-remoto-20260922`; credenciales separadas
  con modo 600. Los scripts fijan destino y vencimiento; no aceptan otro proyecto.

## Reconstrucción y evidencia

El replay histórico se detuvo en migraciones antiguas. Se reconstruyó solo la
rama con esquema y fixtures locales, preservando los servicios Auth/Storage de
Supabase. Las tentativas fallidas se revirtieron completas; se corrigieron el
permiso temporal SET ROLE, el orden users/identities, el conteo real de 17 actores
y las referencias de comprobantes ficticios. No se desactivaron guardas Storage:
se conservaron sus buckets y se agregó el bucket propio del fixture.

Primer respaldo usado: `gd-f4-antes-etapa4-20260922.dump`, SHA-256
`45d000344a7760dd7ab995f25a7e30fdb47bc35710f9523330e637fdb342067f`.
Resultado: 17 usuarios sintéticos, 76 leads, cero Cron activos, v1 OFF.

Producción ya incluía los vigilantes `20260922153708`, `20260922182454` y
`20260922200514`. Se incorporaron en la rama sus definiciones vigentes y
declaraciones técnicas; no se copiaron alertas reales ni se ejecutaron preflights
que dependían de su historia. Se acreditó:

- **721 funciones**: cuerpo, dueño, definer, search_path/configuración y ACL.
- **120 tablas/vistas**: columnas, restricciones, índices, triggers, RLS y ACL;
  solo tres CHECK cambian paréntesis por la normalización de AND de pg_restore.
- Roles y membresías propios, policies Storage y trigger de Auth coincidentes.
- **21 Edge Functions**: versiones, verify_jwt y SHA-256 coincidentes.
- Ledger de la rama: **327 migraciones**, versiones, nombres y sentencias
  idénticos al respaldo productivo. Esta reconstrucción administrativa no
  reejecuta el historial ni introduce migraciones nuevas para fixtures.

Gestión Diaria, SLA, analítica y vigencia PASS. El gate de F7 falla por
`crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)`, huella
`802c0318fd3ec5636e174b4f98b3c965`, **igual en producción y banco antes de F4**.
Es deuda previa de otra tarea; no repararla ni atribuirla a los candidatos.

La matriz general exige siete leads activos exactos. El primer respaldo
conservaba 16 activos de pruebas locales anteriores. Antes de instalar F4 se
prepara la semilla limpia `semilla-base.dump`, SHA-256
`571b82179c858748a6b66f181b9102d01e57234da0d375e554a646af7aaaf26b`:
siete leads y cinco tareas, con el esquema previo a etapa 4 y política v1 OFF.
Respaldo adicional remoto `antes-semilla-limpia.dump`. Auth, Storage e historial
se conservan. Tras resembrar, repetir alineación/cotejo; el primer PASS no basta
para atribuir paridad al estado nuevo.

## Retoma y gates pendientes

**Pruebas remotas terminadas:** baseline 2.196/0 (12 min 51 s) y candidato
2.196/0 (12 min 18 s), matriz canónica completa Auth/PostgREST 14.5.
24 mutantes remotos, horarios Lima, ámbitos, reintentos, reconocimiento,
aplazamiento, claves/tipos/rangos, publicación futura y grupos SLA PASS.
Auth/API de seis roles y tasa baja no activable PASS. BYPASSRLS solo se ensayó
con administrador local; no atribuir ese mutante al hosted.

Advisors seguridad: cero ERROR. Se agregan seis WARN
`authenticated_security_definer_function_executable`, correspondientes a las
seis puertas deliberadas de F4. Cada puerta verifica actor/rol; anonimato y
roles ajenos denegados, helper lector bajo RLS. No otorgar acceso a tablas
para silenciar el linter. [Criterio del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

**Trabajo simultáneo:** la otra sesión ya fusionó PR #73 a las 23:32 UTC en
`182b098f`; no repetirlo. Main avanzó a `e5957443` con PR #74. El sitio aún sirve
`build-20260922T221442353Z` (comprobación por HTTPS al origen), correspondiente
a `7d65fcdb`; un ZIP preparado de `e5957443` no acredita publicación.
Producción incorporó nueve SQL de conversiones hasta `20260923011513`:
336 migraciones, Gestión Diaria todavía v1 OFF, sin tabla de entregas. Antes de
merge SQL hay que incorporar en la rama esas definiciones/historial y repetir
los gates afectados. No usar la vieja comparación 327/331 como preflight final.

1. Incorporar los avances de Main y los nueve SQL ya productivos de la otra tarea.
2. Conservar los cuatro archivos exactos y versiones canónicas, sin reinstalarlos.
   Nunca un db push general ni DDL directo a producción.
3. Cerrar concurrencia, carga y advisors; repetir gates tras integrar cambios.
   Respetar el reloj real: fuera de jornada no inventar un PASS de entrega HTTP.
4. Reconfirmar Main, catálogo productivo, ledger diferencial de solo cuatro
   migraciones y Edge intactas; merge y postflight OFF.
5. Seguir `$release-crm` con respaldo del sitio vigente, artefacto nuevo desde Main
   coincidente, verificación HTTP y registro de la fuente realmente desplegada.
6. Política futura con gerencia, tasa baja NULL hasta F5, primera jornada real.
   Eliminar la rama propia sin esperar esa jornada si ya terminó su uso.

Scripts versionados en `supabase/scripts/gestion-diaria-seguimiento/remoto/`.
Las pruebas locales previas siguen siendo evidencia local, no remota.
