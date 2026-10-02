# Encargo original (Miguel, 01/10/2026) — texto íntegro

> Las decisiones D1–D10 del 02/10 (ver `README.md`) **mandan** donde difieren de este texto; la Fase 0 demostró que
> varios supuestos no se cumplen en el CRM (etapa al reactivar, enum de resultados, `origen` inmutable, etc.).

# P-0XX: Base de gestión para analistas con seguimiento y reactivación de leads

Trabajas con el estándar de un ingeniero de software senior: te mido por correctness, seguridad y mantenibilidad, no por rapidez. Entiende antes de tocar, piensa en fallas mientras escribes y revisa tu propio diff antes de declararlo terminado.

## Objetivo (estado final)
Los analistas tienen la misma vista "base para gestión" que hoy usan los supervisores, limitada a los leads fuera del pipeline de los que son dueños actuales. Desde ahí llaman, registran cada intento con resultado y notas, agendan rellamadas y reactivan leads al pipeline en la etapa Contactado. Un lead tiene un solo dueño: si el supervisor lo reasigna, desaparece de la vista del analista anterior y aparece en la del nuevo con todo su historial.

## Contexto
- Proyecto Supabase: `dctqcbznekcyxhjujuci` (Avance Corp / MásCapital).
- Frontend: portal Next.js. *(F0: en realidad el CRM es Vite + React + TS, SPA con router por hash.)*
- Existe una vista "base para gestión" solo para supervisores. Ubícala en la Fase 0.
- No dupliques la definición de "base" ni de "descartado": reutiliza la existente.

## Protocolo de ejecución
- Ejecuta por fases en este orden: F0 → B1 → B2 → B3 → B4 → [merge de Miguel] → F1 → F2 → F3 → F4 → QA.
- Al terminar cada fase: reporta y DETENTE hasta que Miguel confirme.
- Todo cambio de esquema, RLS, funciones y triggers se hace en una **branch de Supabase**. Nunca en producción. Miguel revisa y hace el merge.
- El frontend empieza solo después del merge de la base de datos.

## FASE 0: Reconocimiento (sin modificar nada)
Reporta: 1. archivos, ruta, query/RPC y filtros por rol de la vista "base para gestión" del supervisor. 2. qué estados incluye esa base. 3. campo que define el analista dueño. 4. tabla de actividades/notas: estructura, tipos, campo de resultado. 5. etapa máxima alcanzada, motivo de descarte, origen, fecha de descarte. 6. cómo funciona la reasignación. 7. políticas RLS de leads y actividades por rol. 8. triggers al cambiar etapa, incluido SLA. 9. cómo se definen los roles.
**Término:** informe entregado. Ningún archivo ni objeto de base de datos modificado.

## BASE DE DATOS (en branch)
### B1: Esquema
- En leads: `origen` (valor `reactivacion_base`), `reactivado_en`, `no_contactar` (bool, default false), `no_contactar_por`, `no_contactar_motivo`, `enfriado_hasta`.
- En actividades: `resultado_llamada` (enum: `no_contesta`, `no_interesado`, `volver_a_llamar`, `interesado`), `proxima_llamada_en`.
- Check: `resultado_llamada = volver_a_llamar` exige `proxima_llamada_en`.
- Constantes de negocio en un solo lugar: máximo 3 intentos sin resultado positivo, 30 días de enfriamiento.
- Índices: (dueño, estado), `proxima_llamada_en`.
- Si algún campo ya existe con otro nombre, reutilízalo y repórtalo.
**Término:** migración aplicada en branch, tipos regenerados, datos existentes intactos.

### B2: RLS
- Analista: lee y escribe solo leads de la base cuyo dueño actual es él, y las actividades de esos leads.
- Analista NO puede reasignar ni quitar `no_contactar`.
- Supervisor: conserva su acceso actual sobre su equipo.
**Término:** pruebas SQL ejecutadas bajo rol analista: acceso propio permitido, acceso ajeno denegado.

### B3: Funciones (RPC)
- `obtener_base_gestion()`: devuelve la base según el rol del usuario. Excluye `no_contactar = true` y `enfriado_hasta > hoy`. Orden: rellamadas vencidas o de hoy → etapa máxima alcanzada (desc) → días desde descarte (asc). Incluye por lead: conteo de intentos, último resultado, próxima llamada.
- `registrar_intento(lead_id, resultado, nota, proxima_llamada)`.
- `reactivar_lead(lead_id, nota)`: mueve a la etapa Contactado, mismo dueño, `origen = reactivacion_base`, `reactivado_en = now()`.
- `marcar_no_contactar(lead_id, motivo)`. Quitar la marca: solo supervisor.
- Reasignación: las rellamadas agendadas pasan al nuevo dueño y queda registro en el historial (dueño anterior, nuevo dueño, quién reasignó, cuándo).
- Toda comparación de fechas con `(col at time zone 'America/Lima')::date`.
- Cada función valida que el usuario tenga permiso sobre el lead.
**Término:** cada RPC probada con usuario analista y supervisor en la branch.

### B4: Triggers
- Al registrar intento: si el lead acumula 3 intentos sin resultado `interesado`, setear `enfriado_hasta = hoy + 30 días`.
- Al reactivar: el reloj de SLA arranca desde la reactivación.
- Respeta el orden por prefijos existente (`00_`, `01_`, `zz_`, `zzz_`). El orden de ejecución es alfabético dentro de cada bloque BEFORE/AFTER.
**Término:** enfriamiento y SLA verificados simulando fechas. Reporta y espera el merge de Miguel.

## FRONTEND (después del merge)
### F1: Vista del analista
- Reutiliza el componente del supervisor alimentado por `obtener_base_gestion()`. Agrega el acceso en la navegación del analista. Oculta acciones de supervisor (reasignar, quitar no contactar).
**Término:** analista A ve solo sus leads; analista B no los ve.
### F2: Ficha del lead (notas e intentos)
- Historial completo de notas e intentos, del más reciente al más antiguo, con fecha, hora, autor y resultado. Legible de corrido, sin truncar ni colapsar. Eventos de reasignación visibles. Buscador por palabra dentro de las notas.
- Formulario de intento: resultado obligatorio + nota libre + fecha obligatoria si es `volver_a_llamar`.
- Botón Reactivar con confirmación. Botón No contactar con motivo.
**Término:** cada resultado se registra; Reactivar saca el lead de la base y aparece en Contactado.
### F3: Organización del trabajo
- Bloque superior "Llamar hoy" con rellamadas del día y vencidas. Filtros: motivo de descarte, etapa máxima alcanzada, último resultado. Contador de intentos visible por lead.
**Término:** una rellamada agendada para hoy aparece primero.
### F4: Vista del supervisor
- Por lead: intentos, último resultado, analista gestor. Acción para quitar la marca no contactar. Indicador de reactivaciones por analista.
**Término:** el supervisor ve la actividad de su equipo sin perder ninguna función actual.

## Alcance
ENTRA: lo descrito en las fases. NO ENTRA: cambios al pipeline fuera de la reactivación a Contactado; notificaciones push o por correo; dashboards o reportes nuevos fuera del indicador de F4; cambios a la lógica de cierre o contratos.

## Casos límite
- Supervisor reasigna mientras el analista tiene la ficha abierta: la reasignación gana; el analista recibe error claro al intentar guardar.
- Lead reactivado y luego descartado otra vez: vuelve a la base con su historial y el contador de intentos reinicia.
- Lead sin etapa máxima o sin fecha de descarte: va al final del orden, sin error.
- Analista sin leads en la base: estado vacío claro.
- Doble clic en Reactivar: operación idempotente.

## Seguridad
- La RLS es la garantía; el filtro del frontend no sustituye la RLS. Sin datos de otros analistas en respuestas ni en mensajes de error. Migraciones reversibles. Nunca pérdida de datos.

## QA final (reporta resultado de cada punto)
1. Analista ve solo su base; no ve leads activos del pipeline ni ajenos.
2. `volver_a_llamar` sin fecha falla; con fecha aparece primero ese día.
3. `interesado` → Contactado, `origen = reactivacion_base`, sale de la base. *(D3/D9: Reactivar explícito; marca = `reactivado_en`.)*
4. 3 intentos fallidos ocultan el lead; reaparece pasados 30 días (simulado).
5. Lead con no contactar oculto para todos los analistas.
6. Reasignación A → B: sale de A, aparece en B con historial y rellamadas.
7. Acceso a lead ajeno vía SQL bajo rol analista: denegado.
8. SLA correcto al reactivar.
9. Build, typecheck y lint sin errores (descubre los comandos del repo). *(`npm run check` en `app` + `test:rls` en raíz.)*

## Revisión propia antes de cada reporte
Relee tu diff como un PR que debes aprobar: criterios cumplidos, sin código de debug ni TODOs, sin rutas de error sin manejar, RLS verificada, sin salirte del alcance.

## Autonomía
Alto riesgo (RLS, triggers, migración). Al inicio de cada fase de base de datos presenta un plan corto y espera confirmación de Miguel antes de escribir código. Fases de frontend: ejecuta y reporta las decisiones tomadas.

## Reporte por fase
Qué hiciste (2-4 líneas), decisiones no obvias, supuestos a validar, lo que dejaste fuera a propósito, riesgos pendientes y resultado de las verificaciones.
