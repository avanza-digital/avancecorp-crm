# F8 — Cartera, Ficha 360 y condiciones COOPAC preparadas

**Acta histórica del ensayo local.** La autorización y el ensayo remoto posteriores se documentan en [ajustes del 15/09](../ajustes-2026-09-15/README.md).
G7-R01 y G7 siguen abiertos hasta repetir la comprobación en el entorno remoto
y el recorrido real. Esta entrega responde a las observaciones del solicitante
sobre el [primer caso real](../recorrido-real-2026-09-14/README.md).

## Comportamiento preparado

- Cartera y ficha consultan el mismo núcleo de personas, resolviendo cada
  identidad una vez por consulta. Conservan ámbitos, fusiones, exclusión demo,
  fuentes económicas y límites de consulta.
- Ficha 360 recupera contacto, continuidad comercial, seguimiento, inversiones,
  información del cliente, historial y banca plegable. Comparte componentes con
  la ficha anterior. Totales y vencimiento vienen del núcleo autorizado, incluso
  cuando hay varias páginas. Un cliente sólo COOPAC no recibe perfil Avance.
- Si falla una actualización, lista y ficha conservan los últimos datos que esa
  sesión ya había confirmado. Se muestra el error y se bloquean nuevas acciones.
  Una revocación retira los datos. El foco vuelve a inversiones al cerrar un alta.
- Qorilazo y Prodelco piden **plazo en meses** y **rentabilidad anual manual**,
  en el primer cierre y las inversiones adicionales. Escribir `12` significa
  **12 % anual**. También se acepta `12,50` / `12.50`. La tasa no se precarga.
- El vencimiento se deriva con meses naturales, ajustando fin de mes. Ejemplo:
  31/01/2026 + 1 mes = 28/02/2026. En el cierre inicial el servidor fija el día
  de Lima; la fecha del formulario es una previsualización. El cliente envía
  plazo y porcentaje, para conservar reintentos aunque cambie el día local.
- La inversión adicional conserva su fecha comercial elegida. Plazo, tasa y
  vencimiento viajan juntos por preparación, revisión, corrección, confirmación,
  idempotencia y lectura. El modo demo conserva esos mismos campos.

No se inventan condiciones para contratos históricos: los campos quedan NULL.
Las solicitudes y bundles anteriores siguen siendo compatibles. No se generan
comisiones, cuotas ni pagos de intereses a partir del porcentaje COOPAC.

## SQL exacto pendiente de aprobación

Aplicar en este orden, sólo tras aprobación del solicitante y ensayo remoto:

1. [Consulta eficiente de Cartera](../../../migrations/20260914213634_crm_f8_cartera_lectura_eficiente.sql).
2. [Plazo y rentabilidad anual COOPAC](../../../migrations/20260914213928_crm_coopac_condiciones_anuales.sql).

[SHA-256 y tamaños](sql-huellas.json). Ambas migraciones comprueban que las
definiciones previas coincidan con el corte inspeccionado; si existe deriva,
aborta la transacción. La segunda añade dos columnas nullable y una restricción
de coherencia en `crm.cierres_externos`, adapta los escritores F3/F4 y añade los
campos a los lectores existentes. La firma F3 anterior se sustituye sin CASCADE
y conserva los argumentos nuevos opcionales, los hashes antiguos y sus ACL.
No modifica tablas, triggers o políticas de `public`, banderas ni importes.

## Verificación

| Control | Resultado y alcance |
|---|---|
| `app/npm run check` final | PASS: lint, TypeScript, 245 archivos / 3.579 pruebas, cobertura, configuración de release, build, bundle y duplicación |
| E2E completo inicial | 181 PASS, 26 SKIP, 3 FAIL por rótulos F6 antiguos; el primer intento dentro del sandbox no pudo abrir el puerto y se repitió con permiso |
| F5/F6 después de corregir los rótulos y el review | PASS, 15 recorridos; incluye móvil, error recuperable, revocación, foco y error asociado a tasa |
| `npm run check:scripts` y `npm run test:edge-preflight` | PASS |
| `seed:preflight`, `test:rls:preflight`, script `gate:realidad` | NOT RUN: falta `SUPABASE_URL` en el entorno; no se afirma PASS |
| Paridad SQL de personas | PASS: todos los campos y arrays para 7 contextos, incluidas sesiones inactivas, sin sesión y Directorio |
| Demos y fusiones | PASS: 7 formas de enlace demo/mixto × todos los actores, más antecedentes fusionados del banco |
| Condiciones SQL | PASS: altas inicial/adicional, fechas, corrección, revisión obsoleta, reintentos, conflictos y lectura desde fuente |
| Compatibilidad anterior | PASS: una operación escrita por la firma vieja se reintenta tras sustituirla sin duplicar ni cambiar hash |
| Permisos | PASS: ACL completa, propietario y configuración iguales para todos los roles de la RPC sustituida; sin grants directos o RPC anónima |
| Replay exacto local | PASS: dos SQL completos en otra copia; siete firmas de datos, atributos/ACL y funciones ajenas conservados |
| Tipos | Generados con Supabase CLI 2.114.0 desde el banco; integrados únicamente los bloques afectados, preservando schema posterior ajeno |
| Capturas | Inspección visual de escritorio y móvil; no desbordamiento horizontal en el recorrido móvil |
| SQL/Auth HTTP en Supabase, advisors y publicación | NOT RUN: pendientes de autorización y banco remoto |

En la muestra sintética se agregaron 500 personas y 1.700 leads sobre el banco
existente. Las RPC reales de lista y ficha, juntas, excedían 8 s con el núcleo
anterior para los tres roles. La versión corregida respondió entre 0,355 y
0,423 s en el último ensayo, concurrente con los checks frontend. Son mediciones
locales del proceso completo, **no tiempos productivos ni un benchmark de carga**.

Un conteo SQL de producción, sólo lectura, confirmó 492 personas, 1.691 leads,
11.334 actividades, 1.059 tareas pendientes activas, 21 miembros comerciales,
21 periodos de metas, cero vendedores huérfanos y cero revisiones bajo el sello.
La divergencia histórica de 296 clientes sin domicilio sigue presente; las
COOPAC no requieren crear un perfil Avance. Los conteos no sustituyen el gate
Auth/Data API ni resuelven esa divergencia ajena a esta entrega.

Evidencia: [recibo](recibo.json), [ensayo SQL](sql-local.json),
[review de Claude](claude-review.md), [evaluación y correcciones](EVALUACION-REVIEW.md),
[ficha escritorio](ficha-gerencia.png), [tres empresas](ficha-tres-empresas.png) y
[formulario móvil](coopac-movil.png).

## Reproducción y límites

El banco exige Docker `supabase_db_avancecorp-f5-bank` y las bases sintéticas
`multiempresa_f8_20260913` (origen) y `multiempresa_f8_ajustes_20260914`
(copia con los dos SQL aplicados y la corrección posterior `20260915015315`). No acepta URL ni destinos remotos. Todas las
fixtures, cambios temporales de funciones y banderas del test hacen ROLLBACK.
No reutilizar el preparador F8 para borrar/resembrar un banco compartido.

Desde la raíz:

```sh
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/test-ajustes-local.mjs
```

Guarda el recibo en `/private/tmp/avancecorp-f8-ajustes-20260914/resultado-local.json`.
El replay separado se realizó en `multiempresa_f8_replay_20260914`, creada como
copia del mismo origen, sin tocar la base original.

Antes de instalar: aprobación de estos dos SQL; banco Supabase propio con base
vigente y coste aprobado; matriz RLS/Auth antes/después, ensayo específico,
advisors y comprobación de deriva. `banco-f7` es antiguo, tiene replay fallido
y no contiene F4/F5/F8; no sirve para aplicar directamente esta entrega.
No usar `apply_migration` sobre producción. Tras los gates, merge de la rama y
lectura de comprobación; publicar el artefacto del commit Main/remoto verificado.
Después repetir el caso real en los cuatro actores y obtener conformidad visual.

La reversa operativa de frontend usa el artefacto anterior: las columnas nuevas
son compatibles. No borrar columnas ni datos nuevos como reversa. Si hubiera
que revertir una función, preparar otra migración guardada y revisada a partir
de su definición anterior. No deshacer el estado nominal F8 ya aprobado.

El ajuste posterior del plazo de un contrato confirmado no se añade aquí.
La RPC histórica de corrección conserva el resto de campos; cambiar sólo el
vencimiento de una fila nueva es rechazado por coherencia. Los históricos sin
plazo/tasa siguen admitiendo su edición anterior. La continuidad conserva la
regla Ficha 360: una inversión vencida requiere revisión aunque haya otra
futura; una inversión adicional no demuestra renovación o liquidación de la vieja.
