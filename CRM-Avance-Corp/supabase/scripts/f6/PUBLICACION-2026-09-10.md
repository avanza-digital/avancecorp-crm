# F6 — publicación del 10/09/2026

**Publicada e instalada, apagada. Resultado operativo: PASS CON OBSERVACIÓN.**
Miguel autorizó la publicación de F6 manteniéndola apagada. Se publicó el frontend
compatible y después se fusionaron exclusivamente los tres SQL F6 ensayados.
F3 sigue encendida; F4, F5 y F6 siguen apagadas. No se ejecutó piloto,
conciliación de identidades reales ni aceptación humana F6.

## Artefacto y trazabilidad

- Código publicado: `b54fe94219fa516ab3824ec1be9ae756fc3144e1`.
  Main local, `avancecorp/main` y Main remoto coincidían al construir/publicar.
- Release: `crm-20260910T191116Z-b54fe94219fa`.
- Build: `build-20260910T191115966Z`.
- ZIP SHA-256: `45633b2a2a1115e72585336da95e204d988f351ea4cceb7da94d9978c309ad3f`.
- [CI frontend y E2E](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34518609571)
  y [CI backend](https://github.com/avanzadigitald/avancecorp-crm/actions/runs/34518609577):
  SUCCESS, ambas ligadas al commit publicado.
- Banco aislado: `f6-postventa-publicacion-20260910`
  (`nspgwzfowwoqlgrkdfvp`). Merge completado; banco eliminado y ausencia
  comprobada a las 19:38 UTC. `banco-f7` se conservó.

| SQL local inmutable | Versión productiva | SHA-256 |
|---|---|---|
| `20260910150039_crm_f6_postventa_persona.sql` | `20260910181248` | `b88987c481119593f2dd5b0908aafff1e965f67e35455301a5bb56d91e6256cd` |
| `20260910190000_crm_f6_conflicto_http_sin_reintento.sql` | `20260910185512` | `18b25277490bb4777a9b6a4cbdb3838bb96e1e1cf100a178c17dc1ba7bfc5da5` |
| `20260910191000_crm_f6_consulta_conflicto_http.sql` | `20260910185624` | `278c809ca018513f8744095a2db2396162ccacd14de7c90a8c418da65736b0ee` |

Los 268 registros anteriores conservan todos sus campos. Los tres nuevos
contienen exactamente el texto y orden ensayados, aunque el merge los separó
en 79, 4 y 4 sentencias. Total final: 271. No hubo reparación del historial,
reproducción de migraciones históricas ni aplicación directa en producción.

## Verificación

| Control | Resultado |
|---|---|
| Cinco grupos F6 en Auth/PostgREST/Postgres remotos, datos sintéticos | PASS 43/43 |
| Frontend integral del commit publicado | PASS 3.182 pruebas en 225 archivos; lint, tipos, cobertura, build, bundle y duplicación |
| E2E completo en CI | PASS 159; 26 SKIP, no contadas como aprobadas |
| E2E específico F6 | PASS 7/7 |
| Regresión F5 local | PASS 46/46 |
| Replay de los tres SQL, reversa local/remota y D-19 | PASS |
| Tipos regenerados desde banco final | PASS 18 nodos |
| Cuatro preflights backend y CI | PASS |
| Matriz RLS general antes/después, mismo seed limpio | **FAIL 45/1.817 en ambas; 1.772 PASS. Comparación PASS: cero regresiones** |
| Catálogo, privilegios y registro productivo | PASS |
| Datos comerciales previos | PASS, con tarea legacy concurrente identificada |
| Huella integral Auth | **INCONCLUSA: cambió durante actividad de sesión; ver observación** |
| Capacidad real bajo rol authenticated/Gerencia | PASS `{version:1, habilitada:false}`, transacción revertida |
| Hostinger y acceso público | PASS 79 recursos, versión estable, formulario visible y cero errores de navegador |
| Revisión manual F6, conciliación F7, piloto F8 y observación F9 | **NOT RUN / pendientes** |

La matriz general no está aprobada. Se preservan sus 45 fallos, iguales como
multiconjunto antes y después de las correctivas, normalizando sólo UUID de
fixtures. Su reparación es mantenimiento pendiente y no se simula un cierre
del piloto. La instalación OFF se acepta por el alcance demostrado: pruebas
específicas, igualdad de esquema/datos de negocio y ausencia de regresiones.
No se deduce que la diferencia con los 65 fallos históricos de F5 represente
veinte correcciones de producto: corresponde a otro banco/configuración.

El banco comenzó vacío y falló la inicialización histórica automática. Se
reconstruyó desde el esquema vivo y sus permisos, se comprobó paridad y se
sembraron sólo datos ficticios antes del candidato. No se copiaron usuarios
reales. Sus metadatos de autoría del historial pertenecían al operador del
banco; la comprobación productiva sí exige todos los campos previos intactos.
Los cron del banco estuvieron desactivados.

## Corrección encontrada en el ensayo remoto

PostgREST 14 reintentaba automáticamente el error `40001`: una operación
bloqueada agotaba 30 segundos y podía completarse después de liberar el
candado. Las dos correctivas conservan el SQL original y traducen esos conflictos
a `PT409`/HTTP 409 después del rollback completo. La misma reproducción
respondió en 223 ms, sin efectos parciales.

Se verificaron 19 cuerpos exactos, manteniendo firmas, ACL, propietarios y
configuración. Las cuatro entradas F4 traducen sólo solicitudes con origen F6.
La operación ordinaria F4 conserva su contrato. El journal conserva la clave
si hubo respuesta desconocida; un primer rechazo explícito libera el envío.
No se cambia globalmente el contrato de conflictos F3/F4.

## Producción y observación de concurrencia

La captura final demuestra 579 funciones previas (diez ampliaciones previstas),
25 nuevas, cinco tablas cerradas con RLS y triggers habilitados, 29 constraints
nuevos y la ampliación prevista del constraint de tareas. No hay DDL de
`public`; las 18 Edge Functions conservan paquete, identidad, estado y JWT.

Trece tablas comerciales conservan exactamente cantidad y huella. Las 3.411
tareas anteriores también: al excluir una tarea WhatsApp creada en la ventana
se reproduce el hash previo. Esa nueva tarea tiene lead, sin inversionista ni
revisión F6; no se alteró ni eliminó actividad legítima. Las nuevas tablas F6
y las tareas neutrales quedaron vacías. Permanecen 15 fuentes con identidad
pendiente: 13 Avance y dos Qorilazo; bloquean el encendido.

Auth conserva 479 usuarios, pero su hash completo cambió. Un usuario existente
actualizó su timestamp en el mismo segundo que su sesión y refresh token;
esto respalda actividad concurrente. No existe snapshot previo por columna
para demostrar qué campos cambiaron. **No se acredita Auth íntegramente
inmutable ni se afirma que sólo cambió el timestamp.** Los tres SQL revisados
no ejecutan DML sobre Auth. El fallo original de igualdad está conservado en
la evidencia; el resultado operativo incorpora esta observación.

Advisors productivos: seguridad 0 ERROR / 195 WARN / 58 INFO; rendimiento
0 ERROR / 5 WARN / 114 INFO. Frente al baseline productivo, los nuevos avisos
de seguridad son doce RPC authenticated SECURITY DEFINER intencionales y cinco
tablas cerradas sin políticas API. No se abrió acceso anónimo.
[Documentación de funciones](https://supabase.com/docs/guides/database/functions#security-definer-vs-invoker)
y [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

Los JS/HTML/CSS publicados coinciden con el ZIP. Doce PNG conservan simultáneamente
el SHA original y la representación HTTP histórica de F5, transformada por CDN;
no se afirma hash directo del origen para esos PNG. `.htaccess` coincide al
reponer el salto final omitido por la API de lectura. ZIP e internos responden
403/404, y el HTML raíz del portal conserva su hash. El login se comprobó en
contexto anónimo nuevo; no sustituye una prueba humana autenticada.

## Continuidad y reversa

Evidencia saneada en [publicacion-2026-09-10](publicacion-2026-09-10/).
La copia privada conserva ZIP/manifiesto, SQL, logs, dump sintético y bundle Git;
no se versionan claves, credenciales ni datos identificables.

La [reversa operativa](reversa-operativa.sql) apaga F6 y conserva historia/recibos.
El frontend anterior `crm-20260909T171132Z-8ccb0ca14fcf` está conservado.
No se ejecutó una reversa productiva, pues F6 nació apagada.

Sigue la [revisión manual F6](REVISION-MANUAL.md), conciliación F7/G6,
piloto F8/G7 y activación/ciclo mensual F9/G8. Las comisiones siguen fuera
del sistema. La publicación no declara terminado el plan F1–F9.
