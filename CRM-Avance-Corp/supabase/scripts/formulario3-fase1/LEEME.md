# Formulario 3 — fase 1 terminada y ensayada

**14/10/2026: implementación y validación aislada completadas. No publicada.**
La campaña se guarda al crear el lead y acompaña los reingresos y solicitudes
de clientes. El canal sigue siendo `formulario`, con su reparto y conversión.
La etiqueta y el filtro de pantallas corresponden a la fase 2.

Producción conserva el importador anterior y todavía no tiene la columna.
n8n continúa inactivo, `enviar_crm=false` e «Importar en CRM» deshabilitado.
No se importó ninguna fila real de Google Sheets.

## Cambio y contrato

- [Migración](../../migrations/20261014210146_crm_formulario3_campania_origen.sql):
  columna nullable `campania_origen`, sin reclasificación histórica. Texto de
  1–80 caracteres Unicode, espacios ASCII extremos recortados, sin controles;
  valores explícitos inválidos rechazados. Ausencia y NULL siguen compatibles.
- Alta y campaña se confirman juntas, sin PATCH posterior. Formulario 3 exige
  canal formulario en la entrada; el CHECK valida la forma, sin bloquear una
  corrección posterior de canal por servidor.
- Duplicados conservan toda la fila, origen, campaña y responsable. Los
  reingresos conservan la campaña de origen y anotan la nueva en su actividad.
  No se construye un sistema de atribución múltiple.
- Para clientes sin ficha viva, nota y tarea muestran la campaña antes del
  texto largo. Se conserva el sufijo de huella y la deduplicación de siete días
  sin número de fila. Omitir campaña no introduce una clave NULL en la huella.
- El caso de lead cerrado identificado y otra ficha viva confirmó un defecto
  previo. Búsqueda de repetición y escritura ahora usan `v_lead_vivo`.
  Un reenvío posterior puede añadir una nota correcta a la ficha viva si la
  anterior quedó mal ubicada en la cerrada; no crea otro lead.
- El Edge conserva autenticación y validación por fila. El manejador real
  `handler.ts` se separó de `Deno.serve` para probar HTTP. Las cinco piezas
  modificadas/nuevas coinciden con el directorio canónico
  `_supabase_functions/functions/crm-importar-leads`.

## Permisos

La ACL viva daba UPDATE de tabla a authenticated. Se convierte en los mismos
permisos efectivos de todas las columnas anteriores, antes de agregar la nueva.
No se cambian policies ni filas visibles. La campaña se lee bajo el RLS
existente y no se edita por authenticated. El trigger también rechaza cambios
a través de una puerta DEFINER con sesión humana.

El mantenimiento directo de postgres/service_role se conserva y está probado;
la garantía de no reclasificación corresponde al importador. **Una columna
futura necesita su propio GRANT UPDATE** si debe poder editarse. Normalizador
y trigger no exponen EXECUTE a los roles de API. Las tres puertas conservan
firma, owner, ACL, DEFINER y configuración. El preflight comprueba cuerpo y
definición completa; el postflight comprueba atributos y permisos.

El catálogo vivo tiene tres escritores INSERT: el importador,
`crm.crear_lead_si_disponible` y `private.bases_carga_cargar_lote_core`.
Los dos últimos enumeran columnas y no copian una fila completa con campaña.
La reapertura humana actualiza la misma ficha y conserva la campaña: probado.
No se propaga automáticamente a otra ficha.

## Verificación ejecutada

| Comprobación | Resultado |
|---|---|
| Contrato SQL con RPC real como service_role | PASS: 36 locales y 36 remotas |
| Permisos y RLS con roles SQL y claims | PASS: 18 locales y 18 remotas |
| Ficha cerrada frente a otra viva | Defecto previo reproducido; corrección PASS local y remota |
| Tests Edge | PASS: 40 unitarios + manejador HTTP con 4 pasos |
| deno check del index | PASS |
| npm run check:scripts | PASS |
| npm run check desde app | PASS: lint, tipos, cobertura, build y verificaciones; 11 warnings previos de lint |
| Tipos | Generados desde el banco local; integrado solo el bloque nuevo de crm.leads |
| Columnas anteriores y atributos de las tres puertas | Idénticos antes/después en remoto |
| Histórico remoto | Huellas de 8 conjuntos de filas idénticas después de migrar y probar |
| Advisors de seguridad | Sin diferencias; ninguna alerta nueva |
| Advisors de rendimiento | Ninguna alerta nueva; 27 índices dejaron de figurar sin uso |
| Matriz general ajena al cambio | NOT RUN; ejecutado el gate focalizado test:rls -- --formulario3 |
| Auth/HTTP remoto y E2E visual | NOT RUN en fase 1; pruebas integradas y pantallas pendientes en fases 2–3 |
| Publicación e importación real | NOT RUN; fases 4–6 |

Se prueban altas legacy y campaña, paridad de fila, ledger y divisor, duplicado
sin alteraciones, validación sin alta parcial, reintentos con fila movida,
campañas distintas y solicitud de cliente con nota larga. RLS cubre vendedor,
supervisor, gerencia, coordinador, inactivo, anónimo y servidor. Coordinador
conserva su restricción actual de lectura directa de leads.

Las fixtures no sustituyen funciones ni desactivan triggers. Todo se revierte
con ROLLBACK; las colisiones con identidades de prueba rechazan el ensayo.
El test HTTP del manejador sustituye solo fetch a PostgREST; la persistencia
real se acredita por separado con SQL.

## Bancos y evidencia

Banco local final: `formulario3_fase1_20261014_v2`, contenedor
`avancecorp-coordinacion-pg-actual`, clon vacío del esquema real
`conversion_cierres_20261012`. Las tres puertas coincidían con producción.
El banco fuente y las bases de otros trabajos no se modificaron. Tipos
generados con CLI 2.117.0: se conservaron las definiciones locales más recientes
ajenas a esta columna, sin sobrescribir todo el archivo.

Rama autorizada `formulario3-fase1-20261014`, ref `sdgqkuejylkeqabpplyk`:
creada 21:25:58 UTC y retirada 21:35:41 UTC; ausencia confirmada. Sus 12 cron
quedaron desactivados antes del ensayo. La primera rama sin datos falló al
reconstruir el historial anterior; se retiró y se recreó como copia actual.
No se reparó el historial productivo ni se tocaron las otras ramas.
Tarifa autorizada: US$0,01344/h; no es una factura calculada.

Versión remota de ensayo `20261014213157`; archivo local `20261014210146`.
La rama se retiró sin merge. No repetir versiones ni hacer db push masivo.

- [Antes](remoto-antes.json) y [después](remoto-despues.json): 3.677 leads,
  4.075 asignaciones, 27.098 actividades, 119 actividades de clientes,
  10.685 tareas, 650 perfiles, 650 usuarios Auth y 6 flags intactos.
- [Advisors](advisors-comparacion.json): avisos existentes documentados sin
  atribuirlos al cambio. [Referencia del linter](https://supabase.com/docs/guides/database/database-linter).
- [Acta de verificación](verificacion.json) y [revisión de Claude](revision-claude.txt).

## Revisión y decisiones

Una revisión de implementación por `scripts/claude-review`, solo lectura:
**CHANGES_REQUESTED, confianza MEDIUM, sin P0/P1 demostrados**.
Codex evaluó los hallazgos, aplicó las mejoras justificadas y las verificó;
no se pidió otro dictamen para obtener PASS.

Se aceptaron desacoplar permanentemente canal/campaña, reforzar guardas y ACL,
retirar EXECUTE innecesario, probar todas las rutas como service_role y fijar
el orden de publicación. La hipótesis de copias humanas no aparece en los
escritores vivos; la reapertura real pasó. Los controles C1 se rechazan con
la colación real. No se añadió normalización NFC ni espacios Unicode: n8n
envía el literal canónico; ampliar etiquetas requiere una regla explícita.

## Reproducción y siguiente paso

Desde la raíz CRM, con el banco local preparado:

```sh
docker cp supabase/scripts/formulario3-fase1/. avancecorp-coordinacion-pg-actual:/tmp/formulario3-fase1
docker exec avancecorp-coordinacion-pg-actual psql -X -U postgres -d formulario3_fase1_20261014_v2 -v ON_ERROR_STOP=1 -f /tmp/formulario3-fase1/contrato.sql
docker exec avancecorp-coordinacion-pg-actual psql -X -U postgres -d formulario3_fase1_20261014_v2 -v ON_ERROR_STOP=1 -v corregido=1 -f /tmp/formulario3-fase1/reingreso-ficha-viva.sql
npm run test:rls -- --formulario3
npm run test:importar-leads-edge
```

`branch-prueba.py` fija la ref del ensayo ya eliminado. Para repetirlo hace
falta otra rama autorizada y actualizar esa ref y la guarda de fixtures.
`estado.sql` es de solo lectura.

**Sigue fase 2: etiqueta y filtro en pantallas.**
En fase 4: SQL aditivo → comprobar columna, permisos y huellas de las puertas
nuevas → Edge → frontend → prueba integral. El Edge nuevo no debe apuntar al
SQL viejo que ignora campaña. Mantener n8n detenido hasta verificar la versión
publicada y realizar el ensayo de una fila real.
