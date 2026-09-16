# Supervisor: creación y conversión de lead propio — 2026-09-16

Cambio de interfaz: Nuevo lead → Responsable comercial → **Yo — lead propio**.
La ficha conserva el nombre del responsable cuando no está en el selector de
analistas activos. La autorización permanece en los RPC/Edge existentes.

## Alcance y contratos

- `vendedor_id` es el responsable vigente; `creado_por` solo identifica al autor.
- La opción usa `yo.id`, incluso sin analistas. El RPC `crear_lead_si_disponible`
  recibe ese id; el store no hace INSERT directo para esta alta.
- Un lead propio tiene `asignado_supervisor_id = null`. Las opciones analista
  del equipo y Sin asignar conservan su comportamiento.
- No se amplía la reasignación de leads ya existentes: tomar/reclamar leads
  de la bandeja o recuperar uno cedido no forma parte de esta función.
- Propiedad y capacidad contractual son distintas. La conversión requiere
  `puede_contratar`; la ficha, Edge y SQL conservan sus verificaciones.
- Referido sigue exclusivo del analista. No cambia tasa, identidad ni RLS.
- El capital del supervisor aparece en Producción fuera del ranking, sin fila
  de analista. Oficina/alta manual no aporta al KPI de leads recibidos: esa
  fórmula vigente no cambia por esta función.

## Evidencia

- PASS `npm run check`: 247 archivos / 3641 pruebas, lint, tipos, cobertura,
  build, configuración del release, bundle y duplicación.
- PASS Playwright completo: 195 pruebas; 26 omisiones preexistentes. Tras la
  corrección visual del responsable: 13/13 en `acciones-demo.spec.ts`.
- PASS Edge: 32 pruebas de acceso, preflight y tasa de `crm-convertir-lead`.
- PASS banco SQL: 8 casos, cada uno en transacción terminada en ROLLBACK.
  Alta, idempotencia, responsable, reparto, Referido, supervisor ajeno, perfil
  revocado, tasa no autorizada, cooperativa y Avance con contrato y Cartera.
  Ambos cierres conservan S/ 20 000 y una operación bajo el supervisor fuera
  del ranking, sin alterar el KPI del canal oficina ni el número de analistas.
- NOT RUN `gate:realidad` por ausencia de credenciales CLI privilegiadas.
  Lectura alternativa vía MCP de producción: 21 periodos de metas, 1804 leads
  activos, 12191 actividades y 4432 tareas. No se simula que el CLI pasó.
- No se aplicaron migraciones ni desplegaron Edge Functions de esta tarea.
  Las lecturas de producción fueron solo de metadatos/conteos. Ningún cliente
  real fue creado o convertido para probar.

## Banco SQL local

```sh
node --test CRM-Avance-Corp/supabase/scripts/supervisor-propio/flujo-local.test.mjs
```

El runner acepta únicamente el contenedor `supabase_db_avancecorp-f5-bank` y
la base sintética `supervisor_propio_vigente_20260916`. Requiere Docker y los
usuarios ficticios de la matriz RLS (`sup1`, `sup2`, `vend1`, `gerencia`).
La base se clonó de `rls_vigente_20260916`: se aplicó la migración ya publicada
`20260916023055_crm_cartera_filtros_comerciales.sql` y se restauraron las
versiones productivas de `private.conversion_episodios` y
`private.metricas_distribucion_leads_core` (la matriz tenía variantes de test).
Las funciones relevantes de alta/conversión/contrato/Cartera/métricas se
contrastaron por firma y huella con producción. Seis diferencias de postventa
ajenas a este flujo no se presentan como equivalencia total del esquema.

La preparación transaccional completa únicamente datos ficticios incompletos:
DNI/teléfono del supervisor y la identidad de un cierre heredado de la matriz.
Para este último usa `crm.op_privilegiada` y lo apaga antes de cambiar al actor
`authenticated`. No deshabilita triggers ni RLS. El efecto Auth/perfil de la
Edge se simula como administrador después de reservar y marcar el claim;
las llamadas de negocio corren como el supervisor autenticado. No es una
prueba HTTP de la Edge desplegada. La atribución en tablas privadas se verifica
como administrador; las lecturas comerciales se verifican mediante Cartera.

## Evaluación de la revisión independiente

Claude emitió CHANGES_REQUESTED por falta de evidencia de ranking y porque
los fixtures aún impedían completar SQL. Se aceptaron ambos gaps: los ocho
casos finales verifican los dos caminos completos, la atribución y la exclusión
del ranking. La afirmación de que nunca existieron responsables supervisores
se descarta: el núcleo vigente y la decisión comercial del 2026-09-02 ya
contemplaban producción fuera del ranking.

La petición de ampliar la reasignación se descarta por alcance; la distinción
propiedad/capacidad contractual se mantiene y tiene test. Se añadió al comentario
la referencia del RPC de alta. El reviewer no detectó ampliación de acceso en
el diff. El PRIMARY cerró los gaps con evidencia, sin repetir consultas para
obtener un dictamen favorable.

## Integración protegida

GitHub rechazó el push directo: requiere PR, una revisión aprobatoria y el
check `verify`. El workflow aún llamaba `quality` al mismo gate. Se alinea
el nombre a `verify` y se quita el filtro de paths de pull_request para no
dejarlo eternamente pendiente en PR documentales. Los comandos del gate se
conservan. Este mismo ajuste ya estaba preparado en la tarea paralela; se
reproduce en la copia aislada sin modificar su árbol.

PR: https://github.com/avanza-digital/avancecorp-crm/pull/2
La publicación debe esperar aprobación e integración en `avancecorp/main`,
y reconstruirse desde ese commit. Un ZIP de la rama es solo preparación.
