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

La segunda corrida llegó a la matriz D-17 y falló por cinco diferencias del
arnés respecto del esquema/entorno vigente. Se conservaron sus logs y se
restauró nuevamente el fixture antes de repetir la matriz completa:

- D-2 ya vive en el núcleo privado de atención/venta. Se verifica la cadena
  adaptador → ejecutor → implementación, sus atributos y ausencia de grants API.
- El límite de referidos aprobado el 12/10 usa los propios cierres referidos.
  El oráculo exige la delta exacta según peso y límite del mes, sin redondeo.
- B7 interpreta `relacl=NULL` mediante `acldefault`; sigue exigiendo RLS,
  propietario postgres y ningún privilegio para terceros. No cambia grants.
- Potencial viene encendido de producción. El wrapper guarda su fila, inicia
  OFF para los bloques OFF/ON y restaura exactamente activo/fecha en `finally`.
- El pooler puede reutilizar una sesión con `pg_temp.excepcion_d17` ya creada.
  El helper temporal usa `CREATE OR REPLACE`; no altera funciones del producto.

Estos ajustes no declaran válidos los intentos fallidos. La nueva corrida
registra hash del gate y de ambos SQL al iniciar, y exige que el gate permanezca
igual al finalizar. Main añadió por separado el alcance `--atencion-venta`;
la matriz general conserva el cuerpo probado, con verificaciones más estrictas
de D-2 y de las deltas de conversión.

Resultado definitivo: **3.931 aserciones HTTP PASS**, incluido el grupo A.
El wrapper falló después del resumen aprobado al restaurar `actualizado_en`:
`trg_multiempresa_flags_touch` lo sustituía por `now()`. Se conservó ese fallo
y `cerrar-gate.mjs` exigió el resumen canónico sin fallos, el hash exacto del
código probado y la foto original. `restaurar-bandera.mjs` suspende solo touch
dentro de una transacción, restaura la fecha y lo habilita antes del commit;
confirmados bandera/fecha originales y cero marcas. No se convirtió ninguna
aserción fallida en aprobada ni se omitió un bloque. El runner quedó corregido
para futuras corridas; esta recuperación está identificada en la evidencia.

Premerge PASS 02:36:56 UTC; merge solicitado dentro de su ventana de 60 segundos.
Aplicación productiva confirmada 02:38:30 UTC y cierre del vigía 02:39:01 UTC.
El catálogo conserva 149 tablas y 1.085 funciones: solo cambió el cuerpo SLA;
en F7 solo huella/nota. Los 473 registros anteriores del ledger siguen idénticos.
Las 23 Edge conservan sus archivos, JWT, entrada e import map, aunque el merge
reempacó parte de ellas. Advisors productivos posteriores sin hallazgos nuevos.

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
