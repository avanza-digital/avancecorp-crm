# P-0XX — ventas pendientes de tipo de cambio

Banco de regresión de `20261024030000_crm_capital_pendientes_sin_bloquear.sql`.
Solo datos sintéticos. Los runners rechazan destinos distintos de los bancos de esta tarea.

## SQL: cinco casos y cierre

Desde la raíz del CRM, con el esquema completo y la candidata aplicados en un banco vacío:

```sh
node supabase/scripts/capital-pendientes/verificar.mjs --local --fixtures
CRM_CAPITAL_SSL_ROOT_CERT=/ruta/privada/proveedor-ca.crt CRM_CAPITAL_BRANCH_CREDENTIALS=/ruta/privada/rama.json node supabase/scripts/capital-pendientes/verificar.mjs --rama
```

El banco local es `avancecorp-capital-banco-20261023`, PostgreSQL de Supabase, sin red ni puertos publicados.
La rama autorizada es `yzujybpofdjgsuritmky`; el archivo privado procede de `supabase branches get --output json`.
El runner valida URL y destino PostgreSQL, elimina variables PG heredadas y nunca acepta producción.
La conexión remota exige `verify-full`: verifica la cadena de confianza y el nombre del servidor.
Descargar el certificado CA del proveedor desde la configuración de la rama en Supabase y pasarlo por
`CRM_CAPITAL_SSL_ROOT_CERT`; el runner rechaza certificados ausentes, vacíos o no legibles. No usa el
almacén ni las opciones PG heredadas. [Guía de SSL de Supabase](https://supabase.com/docs/guides/platform/ssl-enforcement).
`prueba.sql` exige una base vacía, ejecuta las puertas nativas, verifica permisos con `SET LOCAL ROLE authenticated`
y termina con `ROLLBACK`. El runner exige evidencia de los cinco casos y al menos 26 aserciones.

`--fixtures` guarda seis respuestas nativas en `app/test-fixtures/capital-pendientes/`.
No son respuestas reconstruidas a mano: incluyen los importes, cortes y reglas de privacidad de las RPC.
La lista de Facturación conserva la ocultación de números de contrato cuando el cliente pertenece a otro equipo.

## Auth/PostgREST

```sh
CRM_CAPITAL_SSL_ROOT_CERT=/ruta/privada/proveedor-ca.crt CRM_CAPITAL_BRANCH_CREDENTIALS=/ruta/privada/rama.json node supabase/scripts/test-rls.mjs --capital-pendientes-cloud
```

Este modo focal del gate crea siete cuentas ficticias por Auth Admin, inicia cinco sesiones reales y ejecuta
las lecturas con JWT de analista, supervisor y gerencia. Comprueba 403 de equipos ajenos, ausencia de acceso
anónimo/service_role a la puerta nueva, privacidad de la tabla global, coherencia lista/cuadro, llegada del TC
e idempotencia. La service_role solo prepara usuarios; las aserciones funcionales usan sesiones reales.

Se ejecuta después de la matriz SQL, porque conserva la fixture hasta eliminar la rama completa.
Para repetir SQL sobre esa fixture, usar `--rama --repetir-tras-http`: exige sus siete usuarios y tres contratos
exactos y vacía sus tablas dentro de la transacción; el rollback final restaura también la fixture HTTP.
`CRM_CAPITAL_HTTP_REANUDAR=fixture-inicial` solo permite retomar antes del TC y valida IDs/correos sintéticos,
cantidades y ausencia de cotización. No es un modo para reutilizar una base de negocio.

## Interfaz

```sh
cd app
npm run check
npm run test:e2e:docker -- e2e/capital-pendientes.spec.ts e2e/capital-valorado.spec.ts e2e/citas-capital-valorado.spec.ts e2e/capital-rangos-mixtos.spec.ts --workers=2
```

Los E2E usan los payloads SQL capturados y el backend interceptado; las sesiones HTTP reales se verifican
separadamente en el gate anterior. No se realizan pruebas de escritura ni despliegues en producción.

Preparación, límites y resultados: [acta de verificación](../../../docs/encargos/capital-pendientes-20261023.md).
