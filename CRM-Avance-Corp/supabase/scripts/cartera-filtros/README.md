# Filtros comerciales de cartera multiempresa

Estado: candidato local; **sin publicar en producción**. Solicitud de Miguel:
retomar los pendientes de filtros comerciales y aprovechar mejor la pantalla.

## Contrato

- `fecha_comercial` del núcleo F5 determina el mes, sin conversión UTC de fechas
  de calendario. Mes actual de Lima al abrir; Todos y Sin fecha disponibles.
- Empresa, moneda y estado se aplican a **la misma fuente**. El servidor filtra
  antes de paginar y calcula capital registrado por empresa y moneda. Nunca se
  suman PEN y USD. El listado presenta capital registrado; la ficha conserva sus
  indicadores de capital activo/registrado y todo el historial.
- Los clientes sin inversiones permanecen visibles al consultar un mes sin
  filtros adicionales de inversión. «Sin inversiones» selecciona ausencia real
  dentro del ámbito permitido («Sin inversiones Avance» para Directorio);
  no incluye clientes cuyas inversiones simplemente quedan fuera del mes.
- «Por vencer en 30 días» incluye hoy y día 30, solo activo/vigente, y al activarlo
  limpia el mes para abarcar toda la cartera. Al desactivar recupera los filtros
  anteriores si el usuario no los cambió. El radar F6 conserva su consulta.
- Responsable y opciones proceden del mismo ámbito de personas F5. Directorio
  mantiene exclusivamente Avance. Fuentes demo fuera, flags y permisos vigentes.
- `cartera_inversionistas_fn` conserva v1, incluida su búsqueda anterior.
  `cartera_inversionistas_filtrada_fn` entrega v2; cliente rechaza respuesta v1,
  incompleta o de acceso denegado. Núcleo compartido, sin cálculos paralelos.

## Banco y verificación

Destino cerrado en `banco.mjs`: copia sintética propia dentro del contenedor
local existente. Sin credenciales de producción, sin banco remoto de pago.

```bash
node supabase/scripts/cartera-filtros/preparar.mjs
node --test supabase/scripts/cartera-filtros/filtros.test.mjs
node supabase/scripts/cartera-filtros/http.mjs
```

`preparar.mjs` restaura en la copia la definición anterior antes de comparar
v1, aplica el SQL candidato y verifica siete respuestas completas; ejecuta la
reversa y reinstala, comparando en cada paso respuestas, propietario y ACL.
Las 17 pruebas SQL usan transacciones ROLLBACK y JWT de roles sintéticos.
El caso de vencimientos prepara fechas históricas omitiendo exclusivamente el
candado del PDF dentro de la transacción local y lo restaura antes de leer;
no acredita una modificación de términos por usuarios. Los restantes candados
y las consultas de autorización siguen activos.

`http.mjs` arranca un PostgREST temporal en loopback, usa JWT firmados con una
clave efímera propia y detiene/elimina su contenedor al terminar. Verifica el
transporte y los permisos reales de RPC, no un login humano por Supabase Auth.

Frontend: gate integral y E2E con API simulada; SQL/HTTP se prueban por separado
en la copia real. Capturas de escritorio 1440 px y móvil 390 px. La ficha de
620 px conserva navegación, foco, operaciones y detalles aprobados.

## Publicación y reversa

1. Revisar y aprobar la migración exacta
   `../../migrations/20260916023055_crm_cartera_filtros_comerciales.sql`.
2. Completar el procedimiento de publicación SQL autorizado. No instalar otras
   migraciones pendientes del repositorio por arrastre.
3. Probar v1 y v2 con roles y comparar selección/totales; luego publicar el
   frontend construido del commit verificado en `avancecorp/main`.
4. Reversa: primero volver al frontend anterior. `reversa.sql` restaura el
   lector v1 y elimina las dos funciones nuevas. No cambia datos de clientes,
   inversiones, capital, responsables, permisos de tablas o periodos sellados.

## Resultado verificado

- PASS: 17 grupos SQL, 7 comparaciones completas v1 en instalación, reversión y
  reinstalación, y 6 peticiones HTTP reales.
- PASS: lint y typecheck; 3632 pruebas en 247 archivos, cobertura de líneas 78,92 %;
  configuración de release, service worker, build, verificación del bundle y
  duplicación. Se ejecutaron los pasos de `npm run check` con cobertura limitada
  a cuatro workers. El primer intento sin límite tuvo tres timeouts en tests
  ajenos y un fallo encadenado; desaparecieron con concurrencia acotada, sin
  modificar esos tests.
- PASS: 26 E2E de cartera F5/F6, ficha anterior, permisos y eliminación auditada.
  Capturas: [escritorio](vista-escritorio.png) y [móvil](vista-movil.png).
- PASS: `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight`.
- PASS: advisors de seguridad locales, 0 ERROR/WARN; 60 INFO de tablas previas
  con RLS sin policy (acceso por RPC). Sin avisos sobre las funciones candidatas.
- NOT RUN: publicación, banco remoto y login humano en producción. No se solicitó
  ni se creó infraestructura de pago para esta mejora.

Claude emitió `CHANGES_REQUESTED`; Codex corrigió los hallazgos accionables y
contrastó las hipótesis con la base y los tests. [Evaluación y decisiones](evaluacion-claude.md).
`verificacion.json` contiene la huella del SQL probado. Las evidencias no
acreditan una publicación. Una segunda consulta no fue necesaria.
