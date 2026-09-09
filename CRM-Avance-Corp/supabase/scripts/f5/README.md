# F5 — cartera y ficha del inversionista

Candidata implementada y ensayada con datos sintéticos. F5 reúne Avance,
Qorilazo y Prodelco por persona; conserva monedas, fuentes, responsable vigente
y documentos separados. El registro reutiliza F4, el acceso Avance y el PDF v8.
Las comisiones se calculan fuera del CRM. No se enciende producción con este paquete.

## Entregables

- Cinco RPC CRM autorizadas, cuatro auxiliares privados y una tabla de accesos
  cerrada con RLS/auditoría. Fuente: `01-lecturas.sql`.
- Mi cartera con búsqueda, filtros, total y paginación del servidor. Ficha sin
  perfil ficticio, con historia, tareas, cotitulares y documentos autorizados.
- Nueva inversión: empresa, formulario, revisión y confirmación F4. Conserva
  UUID/contenido/revisión; puede retomar una corrección, acceso o PDF pendiente.
- `crm-inversion-documento`: proxy binario con permiso verificado antes y después
  de descargar. Nunca recibe una ruta arbitraria del navegador ni entrega URL firmada.
- Migración exacta `20260908230249_crm_f5_cartera_ficha_multiempresa.sql`, tipos
  cotejados por introspección y `reversa-operativa.sql` sin borrado de fuentes.

## Verificación reproducible

El banco es exclusivamente `/private/tmp/avancecorp-f5-bank`: API loopback
58321, Postgres 58322 y contenedor `supabase_db_avancecorp-f5-bank`. Los scripts
rechazan otro destino o un emisor de claves distinto del banco Supabase demo.
`start.log`/`fixtures.json` y el dump **sintético** se conservan en el respaldo
privado; nunca se suben al repositorio. El servicio local no envía correos.

Desde `CRM-Avance-Corp`, con el banco F4 sintético restaurado:

```sh
node supabase/scripts/f5/generar-migracion.mjs --check
node supabase/scripts/f5/replay-local.mjs
node supabase/scripts/f5/verificar-banco.mjs
node supabase/scripts/f5/verificar-tipos.mjs
npm run check:scripts
npm run seed:preflight
npm run test:rls:preflight
npm run test:edge-preflight
```

Los preflights de seed/RLS reciben únicamente variables del banco local.
`replay-local.mjs` restaura una copia nueva, con `pgcrypto`, `uuid-ossp`,
`btree_gist` y `pg_trgm`, aplica **en una sola transacción** el archivo exacto,
compara todas las funciones publicadas ajenas a F5, fuentes, Auth e identidades
y ensaya la reversa. No hace replay global del ledger histórico. El banco HTTP
debe tener el mismo módulo instalado; no sustituye ese ensayo por mocks.

`verificar-banco.mjs` ejecuta secuencialmente ocho grupos (38 pruebas). Sus
fixtures crean antecedentes e inversiones ficticias; devuelven las banderas
al estado anterior en `finally`. No lanzar los archivos en paralelo.

Desde `CRM-Avance-Corp/app`:

```sh
npm run check:all
```

Ver [aceptación y límites](ACEPTACION.md), [evaluación independiente](REVISION.md)
y [contrato de lectura](CONTRATO.md). Las capturas en `evidencias/` muestran
personas inventadas. El PDF generado se conserva en el respaldo privado.

## Instalación futura y reversa

Con Main y `avancecorp/main` sincronizados, desde una copia con las fuentes
guardadas en commits y desde `CRM-Avance-Corp`:

```sh
node supabase/scripts/f5/preparar-paquete.mjs
```

El comando comprueba los commits y las fuentes antes y después del build,
verifica el bundle y deja frontend, SQL, función y manifiesto SHA-256 en
`/private/tmp/avancecorp-f5-paquete-<commit>`. No ejecuta la instalación.

1. Integrar los cambios remotos y verificar igualdad entre Main local,
   `avancecorp/main` y el commit del artefacto. No usar `origin/main`, `tronco`,
   ramas de release ni force push.
2. Revisar y autorizar el SQL exacto antes de instalarlo en producción. Mantener
   `ficha_360_neutral=false` e `inversiones_escritura=false`. Prerrequisito: F4
   **publicada** `20260908211349`; su candidata anterior no se vuelve a ejecutar.
3. Instalar únicamente esta migración con transacción única, comprobar nueve
   funciones, ACL, RLS, auditoría, tipos y fuentes; ejecutar advisors del destino.
4. Publicar la función documental desde `_supabase_functions/functions/` y el
   frontend del commit verificado. F5 apagada mantiene la cartera anterior;
   antes de instalar la RPC, la respuesta `PGRST202` conserva esa compatibilidad.
5. Conciliar los huecos de identidad del censo mediante los lotes F4 revisados.
   La cobertura incompleta bloquea el encendido; no mostrar cifras parciales.
6. El encendido económico y su piloto conservan G6/G7 y el despliegue progresivo
   de F9. F5 terminada no autoriza por sí sola el piloto.

Para volver a la pantalla anterior: `reversa-operativa.sql`, en el destino
revisado. Conserva todas las inversiones, solicitudes, archivos e identidades.
Los escritores F4 tienen su propia reversa con sus candados publicados.

## Decisiones operativas

- La consulta de capacidad reutiliza la validación F4. Si otra sesión bloquea
  el lead/persona, la ficha sigue disponible y desactiva temporalmente la nueva
  inversión. La confirmación siempre vuelve a validar bajo los candados F4.
- Una consulta continuada registra como máximo un acceso por actor, persona y
  categoría cada 60 segundos. Los refrescos cada 15 segundos siguen comprobando
  permisos; no duplican el rastro de auditoría. No se borran registros de auditoría
  automáticamente; conservación/archivo se define en la operación de F9.
- Al revocar acceso se purgan PII, banca, caché y token local. Puede mostrarse
  únicamente la referencia opaca de la solicitud para su revisión autorizada.
- La recuperación automática del contenido/token utiliza `sessionStorage`:
  soporta recarga y cierre del diálogo en esa sesión. Otra sesión puede consultar
  una referencia, pero no suplanta un token Auth ya reclamado; una reserva de
  acceso sin su token original requiere la conciliación operativa publicada de F4.
- Cooperativas nuevas usan PEN por contrato F4 vigente. Lecturas conservan la
  moneda histórica. La anulación comercial conserva capital según ATR-4.
- El SHA del PDF sellado acredita sus bytes archivados. En documentos históricos
  o comprobantes sin SHA persistido, el proxy acredita transporte y acceso,
  no una procedencia criptográfica que la fuente no proporciona.
