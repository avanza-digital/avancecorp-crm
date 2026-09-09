# F5 — ensayo de instalación y correcciones del 09/09/2026

Estado: **verificada en banco; instalación productiva pendiente**. F3 permanece
encendida; F4 y F5 permanecen apagadas. Las comisiones se calculan fuera del CRM.

Miguel confirmó instalar el SQL F5 original y usar un banco Supabase temporal
con el costo informado (desde US$0,01344/h de cómputo, más consumos). Las pruebas
detectaron una corrección SQL adicional; se presenta antes de instalarla conforme
a la regla del vault. No se vuelve a pedir autorización por el banco ni por el
SQL original. La corrección de descarga está incluida en la función F5.

## Archivos y orden exacto

| Orden | Archivo local | SHA-256 | Versión asignada por MCP en banco |
| --- | --- | --- | --- |
| 1 | [20260908230249_crm_f5_cartera_ficha_multiempresa.sql](../../migrations/20260908230249_crm_f5_cartera_ficha_multiempresa.sql) | `a13c7ec388993b8cba5299d61e33d9db1cff7d148146b06cbd0cd99cdcce22e5` | `20260909165335` |
| 2 | [20260909170900_crm_f5_candado_estado_cartera.sql](../../migrations/20260909170900_crm_f5_candado_estado_cartera.sql) | `36390b01ded88d7d1f90b8ca8036d3c864c0470df10b9673c348541d530353ab` | `20260909171452` |

El archivo original permanece inmutable. El segundo sustituye únicamente
`crm.cartera_inversionistas_estado_fn()`: mismos parámetros, respuesta JSON y
permisos. Exige el cuerpo original por huella antes de sustituirlo y F5 apagada.
Ambos archivos se aplican en orden, cada uno con transacción única. El manifiesto
del paquete incluye ambos SHA y `ordenSql`; no se normaliza el ledger remoto
ni se usa `migration repair`.

## Defectos reproducidos y reparación

**D-19 / cambio de modo.** La capacidad original leía la bandera F3 directamente
y era STABLE. El censo general encontró una función sin candado. La corrección
usa el helper compartido publicado, VOLATILE, espera limitada a cinco segundos
y vuelve a comprobar la membresía después de esperar. La prueba con dos sesiones
observa el bloqueo real en `pg_locks`, confirma que ve el apagado ya confirmado,
rechaza una membresía revocada durante la espera y rechaza REPEATABLE READ.
Cuatro subcasos fallan con el original y pasan tras el arreglo; censo remoto cero.
La elección de snapshot sigue la [documentación de PostgreSQL 17](https://www.postgresql.org/docs/17/xfunc-volatility.html).

**Descarga / clave opaca.** El runtime remoto proporciona una clave de servicio
`sb_secret_`. El proxy la enviaba como Bearer junto con una `apikey` pública:
Storage devolvía `400 Bucket not found`, aunque el objeto privado existía y
una descarga administrativa independiente entregaba sus 68 bytes exactos.
Ahora Storage recibe la clave de servicio en `apikey`; se conserva Bearer
solo para la clave JWT heredada. Auth y ambas RPC siguen usando el JWT del
usuario. La regresión detecta el fallo anterior para clave opaca y comprueba
ambos formatos. Se siguen las [cabeceras documentadas de Supabase](https://supabase.com/docs/guides/functions/auth-headers).
La versión diagnóstica temporal del banco fue sustituida por el entrypoint
normal; la función no devuelve ni registra claves.

## Banco remoto y correspondencia con producción

Banco exclusivo `f5-cartera-publicacion-20260909`,
ref `suzyimzjeybeaqozqifi`, creado a las 16:31:55 UTC, sin copiar datos.
El arranque histórico se detuvo en 86 de las 265 migraciones existentes.
Se reconstruyó únicamente el esquema actual de `public/crm/private` desde
un dump de estructura del padre y se verificó la equivalencia antes de registrar
su historial exacto. No se ejecutó replay global en producción.

Correspondencia previa: 559 funciones (cuerpo, propietario, permisos, configuración
y comentarios), 1.042 columnas, 243 triggers, 97 policies, 100 estados RLS,
395 índices, tres vistas y los 265 arrays exactos de migraciones.
Los permisos de esquema/tabla/columna coinciden. Tres CHECK solo difieren en
paréntesis asociativos de AND, con mismos operandos y validados en ambos destinos.
La metadata administrada de ubicación de `pg_net` difiere entre padre y banco;
ninguna de estas dos migraciones la modifica.

Las 1.340 funciones/restricciones preexistentes permanecen iguales tras F5.
La fixture usa usuarios ficticios del seed. Tres fuentes cooperativas ficticias,
creadas por el gate con F3 apagada, se conciliaron mediante helpers F4 publicados
y documentos sintéticos explícitos. No se trasladaron personas ni cuentas reales.
Los dos jobs Cron del banco se desactivaron; las otras ramas no se tocaron.

Las 17 funciones Edge existentes se cotejaron por archivos, JWT e import map
contra producción; coinciden. La nueva función documental tiene JWT habilitado.
Antes de integrar se debe repetir esa comparación y la del historial del padre,
porque otra tarea está preparando Tasa sobre el mismo Main.

## Resultados

**Integración posterior de Tasa:** el padre avanzó a 266 migraciones
(`20260909165815_crm_solicitud_tasa_lead_preconversion`). El control premerge
rechazó el cambio real de la base anterior. Se ejecutó `rebase_branch`, se
cotejaron las 1.353 funciones/restricciones del padre y las 17 Edge/50 archivos
y se repitieron las 15 comprobaciones remotas con PASS. El banco tiene 268
migraciones: las 266 del padre más las dos F5. La base versionada corresponde
ahora a esa integración, conservando los tres CHECK equivalentes documentados.

| Verificación | Resultado |
| --- | --- |
| Nueve grupos locales F5, secuenciales, después de ambas correcciones | **PASS: 46 pruebas** |
| Auth, REST, RLS, Storage y entrypoint Edge remoto con datos ficticios | **PASS: 15 comprobaciones** |
| D-19 antes/después, dos conexiones reales, revocación durante espera | FAIL del original → **PASS: 5 pruebas**, censo remoto cero |
| Descarga con claves opacas y JWT heredados | FAIL del original → **PASS**; descarga remota de bytes/SHA idénticos |
| Replay de ambos SQL en copia sintética nueva y reversa | **PASS**; funciones ajenas, Auth, fuentes, dinero y banderas conservados |
| Tipos generados desde `public,crm` del banco remoto | **PASS**: seis nodos F5 coinciden exactamente |
| Sintaxis/scripts, seed y RLS preflight, Edge preflight, Deno check, generadores | **PASS** |
| Gate previo al merge: historial/esquema/permisos/Edge/Main/banderas y captura reciente | **PASS: cinco pruebas**; detectó el cambio real de Tasa |
| Rutina D-19 exacta del gate general con la nueva aserción F5, ejecutada en banco remoto | **PASS: siete checks** |
| RLS general remoto antes de corregir D-19 | **FAIL: 1.589 PASS / 66 FAIL de 1.655** |
| Repetición completa del RLS general después de añadir fixtures F5 | **NOT RUN**; se ejecutaron D-19 y la matriz F5 después del arreglo |
| Instalación, comprobación de producción y eliminación del banco | Pendiente |

De los 66 fallos generales, **65 coinciden exactamente** con la línea base de
la publicación de Citas: configuración sintética de conversión/SLA/auditoría
ausente y expectativas antiguas sobre corrección documental de Administración.
El único fallo añadido era D-19, corregido y vuelto a comprobar directamente.
No se relajan assertions ni se presenta ese gate como aprobado.

El ensayo remoto comprueba OFF/ON, cobertura íntegra, roles y ámbito,
paginación de personas únicas, importes independientes por empresa/moneda,
cooperativas sin perfil Portal, Directorio, descarga exacta y origen inválido,
reasignación y baja con JWT vigente, auxiliares cerrados y auditoría sin PII.
Las lecturas y reasignaciones no cambian capital, contratos, cierres, cuotas ni Auth.

Advisors del banco: seguridad **0 ERROR, 179 WARN, 53 INFO** frente a
175 WARN/52 INFO del padre. Se añaden los cinco avisos esperados de RPC
SECURITY DEFINER explícitas para authenticated y el INFO de la tabla de auditoría
cerrada sin policies; desaparece del banco el aviso preexistente de ubicación
de `pg_net`. La matriz remota prueba la autorización de esas RPC.
[RLS sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
y [RPC SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Rendimiento: **0 ERROR, 5 WARN, 144 INFO**; uso de índices del banco sintético
distinto del padre. No se atribuye a F5 una mejora de los avisos anteriores.

El frontend del arreglo del salto ya publicado conserva su gate anterior:
3.131 unitarias y 150 E2E PASS, 26 omisiones anteriores. Este cambio no modifica
TypeScript/React ni exige otra subida de la web.

## Publicación pendiente y continuación

Evaluación de Claude y decisiones del PRIMARY:
[REVISION-INSTALACION-2026-09-09.md](REVISION-INSTALACION-2026-09-09.md).
Después del rebase, advisors: padre 0 ERROR/178 WARN/52 INFO;
banco 0 ERROR/182 WARN/53 INFO. Se conserva el mismo delta F5 explicado arriba.
Rendimiento del banco: 0 ERROR/5 WARN/145 INFO.

El manifiesto final incluye `baseProductiva`, las dos huellas SQL y los MD5
de la capacidad antes/después. Antes y después del build se compara también
el Main remoto vivo con `git ls-remote`. El control de instalación se ejecuta
con una captura recién recogida:

```sh
node supabase/scripts/f5/preflight-merge.mjs /ruta/manifiesto.json /ruta/captura-actual.json
```

La captura usa `estado-esquema.sql`, los permisos de `estado-permisos.sql`,
las banderas y las fuentes actuales de las 17 Edge. Si se reutiliza una lectura
de archivos, su versión/paquete/entrada/JWT deben reconfirmarse contra el
inventario vivo. Un FAIL impide el merge; no se renueva la base para ocultarlo.
Después de integrar se verifican otra vez SQL/Edge/datos/banderas.

Antes del merge: confirmar el segundo SQL, guardar commits e integrar Main remoto,
construir desde Main verificado, cotejar historial/esquema/Edge del padre y guardar
huellas de las tablas de negocio. Integrar solo esta rama; cotejar los dos SQL,
nueve funciones, ACL/RLS, tablas, fuentes, Edge y banderas en producción.
No instalar la candidata F4 antigua, no usar db push, force push ni ramas de release.

Las 15 fuentes reales sin identidad enlazada (13 Avance, dos Qorilazo) siguen
bloqueando el encendido. Su conciliación usa lotes F4 revisados. F6 incorpora
gestión postventa, próxima acción y reinversión trazable; F7/G6 concilia métricas;
F8/G7 exige piloto y aprobaciones; F9/G8 exige un ciclo mensual completo.
El desarrollo no sustituye esas verificaciones operativas.

Evidencia privada: `/private/tmp/avancecorp-f5-instalacion-20260909/`.
Las credenciales no forman parte del paquete ni del repositorio.
