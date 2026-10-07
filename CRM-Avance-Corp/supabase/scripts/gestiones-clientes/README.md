# Banco de gestiones de clientes

Destino fijo: contenedor `supabase_db_crm-avance-corp-local`, base `gestiones_clientes_20261006`, comentario de base obligatorio `BANCO SINTETICO gestiones clientes 20261006 / sin produccion`. No acepta URL ni nombre de otra base.

El banco parte de la plantilla sintética `base_gestion_20261002`. `esquema` incorpora solamente las funciones publicadas de G4b/pendientes que faltan en esa plantilla, desde un snapshot local de esquema, y la ACL de `auth.uid()` del stack local. No copia datos productivos.

```sh
node supabase/scripts/gestiones-clientes/banco.mjs crear
node supabase/scripts/gestiones-clientes/banco.mjs esquema /private/tmp/ruta/esquema-productivo.sql
node supabase/scripts/gestiones-clientes/banco.mjs ensayar
```

`ensayar` instala las dos migraciones, ejecuta los cuatro archivos de pruebas y revierte la transacción completa. `instalar` deja únicamente el DDL en el banco propio para introspección y pruebas concurrentes; rechaza reinstalar sobre un writer cuya huella ya cambió. Después de instalar, se usa `probar` para ejecutar y revertir los casos sin repetir el DDL.

```sh
node supabase/scripts/gestiones-clientes/banco.mjs instalar
node supabase/scripts/gestiones-clientes/banco.mjs probar
node supabase/scripts/gestiones-clientes/concurrencia.mjs
node supabase/scripts/gestiones-clientes/banco.mjs tipos
```

Durante el desarrollo local de la segunda migración, `actualizar-lecturas` reemplaza únicamente esos lectores en el banco sellado. Retira las firmas privadas anteriores de tres argumentos; no toca otras funciones ni el writer. **No es un comando de instalación productiva.** Las cinco firmas RPC públicas permanecen iguales.

`probar` obtiene los catálogos de llamadas y entrevistas de los módulos TypeScript reales del formulario mediante `catalogo-ui.mjs`; requiere Node con `stripTypeScriptTypes` (verificado con Node 26.7.0). Prueba todos sus valores contra el writer, además de cursor, roles, redacción, nombres vacíos y guardas de detalle. Una sonda temporal hace fallar cualquier consulta F5 para demostrar que los conteos y las páginas solo de leads no la necesitan; se revierte antes de finalizar.

```sh
node supabase/scripts/gestiones-clientes/banco.mjs actualizar-lecturas
node supabase/scripts/gestiones-clientes/banco.mjs volumen
```

`volumen` ejecuta primero las pruebas normales y luego carga 90.000 eventos sintéticos, 30.000 por fuente, sobre hasta 300 días y sin fechas de tarea anteriores a enero de 2026. Verifica incrementos exactos, toma EXPLAIN ANALYZE con sesión de gerencia y revierte toda la carga. Tiempo de sentencia limitado a 45 s. Durante la preparación masiva suspende triggers de las cuatro tablas sintéticas; los reactiva antes de leer como authenticated. No sustituye la prueba de RLS/esquema en el entorno autorizado de instalación ni reproduce la cardinalidad productiva de personas.

`concurrencia.mjs` abre dos conexiones PostgreSQL independientes: mismo recibo al repetir clave y un solo ganador con claves distintas. Deja dos tareas sintéticas cerradas, tituladas «Concurrencia sintética», para inspección. `probar` tolera esas llamadas iniciales y comprueba el incremento exacto producido por su caso.

Para tipos, generar con el CLI instalado de Supabase sobre **esta base local** y los esquemas `crm,public`. El script siguiente integra solo las cinco RPC nuevas; el banco no contiene todas las migraciones recientes de Main y no debe sustituir el archivo completo.

```sh
node supabase/scripts/gestiones-clientes/integrar-tipos.mjs app/artifacts/gestiones-clientes-tipos-locales.ts
node supabase/scripts/gestiones-clientes/integrar-tipos.mjs app/artifacts/gestiones-clientes-tipos-locales.ts --verificar
```

Las pruebas de permisos preparan identidades sintéticas con triggers desactivados únicamente dentro de su savepoint; los reactivan antes de consultar y revierten todo después. Esto prueba los lectores, no las transiciones administrativas entre roles.

## Preparación de instalación

`preflight.sql` y `comprobar-tras-aplicar.sql` son controles de catálogo de solo lectura. El primero coteja 17 dependencias con el destino vigente y rechaza objetos nuevos ya existentes; el segundo exige las 13 funciones resultantes, sus permisos y los tres índices. Se ejecutan en transacciones READ ONLY y terminan en ROLLBACK. No sustituyen la matriz funcional/RLS del banco autorizado.

`ensayar-entrega.mjs` prueba la secuencia completa sobre el banco sintético fijo: comprueba su catálogo instalado, reconstruye temporalmente el estado previo, ejecuta el preflight, las dos migraciones exactas, el control posterior y las cuatro suites, y revierte todo. Usa la definición original del writer de un snapshot de esquema en `/private/tmp/`; no copia datos ni acepta otro destino.

```sh
node supabase/scripts/gestiones-clientes/ensayar-entrega.mjs /private/tmp/gestiones-clientes-esquema-20261006.sql
```

Para la entrega del 06/10 se actualizó en el banco únicamente `private.cartera_f5_personas_visibles(uuid)` a su definición productiva vigente (la optimización del nombre del cierre externo). Las otras dependencias coincidían. Ensayo completo PASS; cada función/índice nuevo tiene comentario de catálogo.

Orden, autorización, gates remotos y recuperación: `docs/encargos/2026-10-06-cierre-gestiones-clientes-DESPLIEGUE.md`. El rollback operativo conserva SQL compatible e historial; no borra resultados ni recibos.

Los ejecutores del banco no publican, no se conectan a producción y no autorizan aplicar las migraciones fuera del banco. Los controles SQL de solo lectura también pueden cotejar el destino productivo sin modificarlo.
