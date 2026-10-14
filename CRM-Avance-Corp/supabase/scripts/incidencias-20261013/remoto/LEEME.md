# Banco remoto de la incidencia

Miguel autorizó expresamente reconstruir `banco-f7` (`cwkiejoaqadcnaieghnf`).
Los scripts fijan ese destino en `banco.mjs`; ninguna escritura de estos scripts
se dirige al padre `dctqcbznekcyxhjujuci`. No son migraciones del producto ni
deben ejecutarse como parte de un despliegue habitual.

## Preparación realizada

- Respaldo privado previo, SHA-256
  `3e5ae6e27f3e786c660c813bb00c38bcd6d3183bff6f3c4b170b3f5dd03807a1`.
- Cron detenido antes de reemplazar el contenido. Vault y cola HTTP vacíos.
- Esquema vigente `public`, `crm`, `private` y ledger; preservados los esquemas
  administrados Auth/Storage, OID de public y privilegios administrados.
- Configuración técnica del padre; autores remapeados al gerente ficticio y
  NULL originales conservados. Ningún cliente ni contrato productivo copiado.
- 13 cuentas Auth, 7 leads, 5 tareas y dos contratos del seed canónico. El
  catálogo legacy se genera exclusivamente a partir de esos contratos ficticios.
- Cinco buckets con configuración técnica vigente y sin archivos productivos.
- 23 Edge Functions copiadas desde sus fuentes vivas del padre. Se compararon
  todos los archivos literalmente, JWT, entrada e import map; un SHA de paquete
  distinto entre proyectos no se tomó como diferencia de código.
- Incorporadas al banco las dos migraciones concurrentes de atención/venta ya
  instaladas en el padre. Paridad: 149 tablas, 1.085 funciones, roles, RLS, ACL y
  ninguna FK huérfana. Ledger base: 473 registros idénticos, incluidos NULL,
  autores, rollback e idempotency_key; no se volvió a ejecutar el historial viejo.

La restauración inicial heredó 50 privilegios de las ACL por defecto: fueron
retirados antes de validar. `db dump` omitió comentarios de dos cuerpos SQL;
se recuperaron de `pg_get_functiondef` y se contrastaron las huellas completas.
Tres CHECK conservan sus predicados y validación, con distinta asociación de
paréntesis de AND por el deparser; `cotejar.mjs` limita expresamente esa excepción.

## Verificación

Las dos migraciones del PR se aplicaron con MCP **solo al banco**, con registros
remotos `20261014013757` (F7) y `20261014013830` (SLA). Los archivos originales del
repositorio no se renombran ni editan.

`probar-sql.mjs` ejecutó 13 bloques con rollback: guardas, rechazos, reversa,
nueve casos límite, seis ámbitos del núcleo y 44 comparaciones de RPC y roles.
EXPLAIN sintético remoto: **2.383,839 → 873,048 ms**. F7: 15 piezas correctas.

La primera corrida HTTP se interrumpió por la ausencia del bucket de pruebas:
`Bucket not found` causó fallos derivados en las conversiones. Se conservó el
log, se restauró la fotografía sintética previa y se crearon los buckets antes
de repetir. Ese intento no cuenta como gate aprobado.

Las credenciales, dumps y logs completos quedan en archivos privados fuera del
repositorio. El resultado definitivo del gate, los advisors y la aplicación
productiva se registran en [el informe de la incidencia](../LEEME.md).

## Repetición controlada

Los scripts de reconstrucción exigen fotografías privadas específicas y sus
guardas de estado; no ejecutarlos a ciegas ni cambiar el ref para reutilizarlos.
`banco.mjs` lee una credencial 0600, valida host/usuario/proyecto, elimina variables
PG heredadas y no pone contraseñas en argumentos ni imprime archivos privados.

Después de instalar y contrastar las dos migraciones en el banco:

```sh
node supabase/scripts/incidencias-20261013/remoto/probar-sql.mjs --solo-rama-autorizada
node supabase/scripts/incidencias-20261013/remoto/gate-http.mjs --solo-rama-autorizada
```

Antes del merge se exige que el padre conserve la base verificada, que el banco
solo tenga las dos migraciones extra previstas y que las 23 Edge sigan iguales.
El frontend conserva su ciclo independiente de revisión y `$release-crm` humano.
