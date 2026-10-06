import os, sys
S = os.path.dirname(os.path.abspath(__file__))
M = '/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/bases-cargadas-b11-20261005/CRM-Avance-Corp/supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql'
mig = open(M).read()
i = mig.index('-- Exclusión de migraciones ANTES'); j = mig.index('-- ── 2 · Las piezas')
pre = mig[i:j]
k = mig.index('-- ── 4 · Censo analítico'); post = mig[k:]
cab = mig[:i]
rev = open(os.path.join(S, '..', 'reversa-b11.sql')).read()
rev_pre = rev[rev.index('do $preflight$'):rev.index('$preflight$;') + len('$preflight$;')]
rev_post = rev[rev.index('do $postflight$'):]
proto = open(os.path.expanduser('~/.config/ai-collaboration/REVIEW_PROTOCOL.md')).read()
anexo = open(os.path.join(S, 'anexo.md')).read() if os.path.exists(os.path.join(S, 'anexo.md')) else ''
F = '```'
t = f"""ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

# Encargo r2 (ÚLTIMA ronda): refutar B11 de «Bases cargadas» (CRM Avance Corp) — LEVEL 3 (datos/conversión)

Tu tarea es intentar REFUTAR que este cambio es correcto y seguro. No tienes base de datos ni red: todo lo que necesitas
está transcrito abajo (diffs exactos contra los cuerpos vivos de producción y resultados medidos). Responde en español.

## Protocolo de revisión (global, transcrito)
{proto}

## Qué se pide (decisión de negocio CERRADA, no se discute)
E10 de Miguel: el cierre de un contacto de «base cargada por archivo» (origen `base_cargada`) cuenta ENTERO (peso 1) en
el numerador de la conversión del analista que lo consigue y NO entra al divisor (como la regla cerrada del «registro
manual»). Los armados desde el CRM conservan su origen y su regla. «Resultados por origen» NO lleva fila de base.
Conversión = numerador / divisor por analista y mes (Lima). Divisor = llegadas landing/formulario sin alta manual
(private.conversion_episodios, NO se toca). Numerador = cierres ponderados (landing/formulario 1, referido su peso,
oficina y otros 0) + upgrade 1 + renovación su peso. Desde 09/2026 los cierres salen de crm.conversion_acreditaciones.
Regla de Miguel: la anulación de gerencia es la única puerta que puede mover un mes ya liquidado.

## Medido en producción antes (solo lectura, 05/10/2026)
- 0 leads con origen base_cargada; 0 cierres de base (ledger y acreditaciones); crm.periodos_cerrados VACÍA (ningún mes
  sellado); política de acreditación activa.
- El origen de un lead NO se puede cambiar tras el alta (private.leads_before_update lanza P0409); el origen base_cargada
  solo lo pone la carga de bases (trigger con válvula de sesión).
- La lista ('landing','formulario','referido') estaba copiada en 8 funciones; la pantalla «Divisor de coordinación»
  exige en el navegador que formulario + landing + referido_aporte + upgrade + renovacion_aporte = numerador_bruto.
- Rojo PREVIO y ajeno en el censo analítico: private.gestion_diaria_cola_hechos sin declarar (también en prod).
- Dueño de todas las piezas: postgres; las privadas con ACL {{postgres=X/postgres}}; las dos crm.* con authenticated.
  private.metricas_distribucion_leads_v3_core es INVOKER y la llama private.metricas_distribucion_leads_autorizada
  (DEFINER, dueño postgres); el resto son DEFINER.

## Cabecera de la migración (la explicación del autor)
{F}sql
{cab}{F}

## Preflight y ayudante nuevo (texto exacto)
{F}sql
{pre}{F}

## Diffs EXACTOS: texto vivo de producción → migración (cada cuerpo completo = texto vivo + estos cambios)
{open(os.path.join(S, 'diffs.txt')).read()}

## Censo y postflight (texto exacto)
{F}sql
{post}{F}

## Reversa (reversa-b11.sql): cabecera y sus dos bloques de comprobación (texto exacto)
Entre los dos bloques repone, con CREATE OR REPLACE, el texto vivo de producción de las ocho piezas que no cambian de
firma; hace drop + create de las dos privadas del divisor con su firma vieja, su revoke y su comentario; borra el
ayudante; y actualiza las cuatro huellas del censo y el sello con las mismas dos sentencias de la migración.
{F}sql
{rev[:rev.index('begin;')]}{rev_pre}

-- … cuerpos vivos de producción, drop del ayudante y resello del censo …

{rev_post}{F}

## Pantalla (diff exacto, sin los tests)
{F}diff
{open(os.path.join(S, 'front-prod.diff')).read()}{F}

## Resultados medidos (06/10/2026; banco Docker con las 933 funciones crm+private de producción: las 922 del 05/10 más la
## migración 20261005200945 «eliminar inversión», ya en producción; huella agregada antes de B11 `933 | 2c2f2612…`)
- Migración aplicada en UN mensaje, como `postgres`: preflight y postflight en verde (0,4 s). Huella después `934 | 2f359f3e…`.
- Paridad A/B (b11-paridad.sql, como Gerencia, ago/sep/oct + rango): 41 salidas (coordinación, conversión mensual sin
  cartera, Equipo, Inteligencia comercial, Distribución v3, conversión mensual por vendedor, divisor de empresa proyectado,
  cierres, crm.conversion_mensual_fn, alarma) con huella IDÉNTICA antes y después; la única diferencia es la clave nueva
  base_cargada = 0. Censo analítico (38 filas) idéntico antes y después.
- Las 11 huellas (md5 de prosrc) tras aplicar = las del postflight.
- Suite de comportamiento (clona un cierre real de octubre como contacto de base y como «otro»): 23/23. Base: numerador
  +1, divisor +0, cierres +1 en mensual/Equipo/Distribución/Inteligencia comercial, coordinación con base +1 y partes =
  bruto en cada fila, sondas de paridad de Equipo y Distribución en verde, la sonda «cierre sin episodio» ve un contacto
  de base convertido sin episodio. «Otro»: +0 y cuenta en «otros». Mes sellado con foto: cierres_base_cargada NULL en filas
  y total; el ajuste de un cierre de base anulado pesa 1; el de «otro», ninguno.
- Mutantes: 16/16 caen (cada copia vieja de cada función, ayudante sin base, base contada como 0, «otros» con base, mes
  sellado con 0 inventado, coordinación sin la clave).
- **Ensayo de DOS SESIONES del freno (nuevo en r2, por tu P1):**
  A · control SIN el candado, con la ventana abierta 2 s tras el preflight: otra sesión confirma un cierre de base y la
      migración se confirma igual → tu carrera existe.
  B · mismo candado en modo espera: un escritor tiene un cierre de base sin confirmar; la migración espera, el escritor
      confirma, y el preflight VE ese cierre y se niega (la instantánea nace después del candado); no se aplica nada.
  C · migración final (NOWAIT) con un escritor a medias: `could not obtain lock on relation`, al instante; huella
      intacta y 0 candados consultivos retenidos.
  D · migración final con la ventana abierta 2 s: el escritor que llega en medio queda en espera 1,6 s, hasta el commit
      de la migración; su cierre nace ya con la regla nueva.
  E · reversa final: con un cierre de base confirmado se niega (freno); con un escritor a medias se niega al instante.
- Frenos en negativo (10/10): con un cierre de base presente, la migración y la reversa se niegan (P0409) y sueltan el
  candado; la reversa se niega si otra función nombra al ayudante, si hay un llamador nuevo del divisor de empresa, si el
  sello del censo no está al día o si una de las cuatro declaraciones caducó; la migración se niega con un llamador nuevo
  del divisor de empresa; ningún rechazo deja nada (huella igual) ni retiene candados.
- Reversa (como `postgres`): deja el banco con las 933 funciones y el censo IDÉNTICOS a antes de B11. Corrida como otro rol
  (supabase_admin) su postflight la rechaza y hace rollback (el dueño de las dos privadas recreadas no sería postgres).
- Gate de RLS completo (test-rls.mjs, siembra + 2817 aserciones) ANTES y DESPUÉS de B11: los mismos 8 rojos de fondo
  (ajenos y previos: R2/hito de activación, una fila bancaria y la bandera potencial_lead), ninguno nuevo; el bloque nuevo de B11 8/8 (núcleo sin EXECUTE para anon/authenticated/service_role,
  ayudante INVOKER e IMMUTABLE, ACL de la puerta intacta, empresa.cierres.base_cargada y la de cada analista enteras en un
  mes abierto, partes = numerador bruto con la base).
- Tiempo de private.metricas_conversiones_implementacion con 366 días (5 corridas, ms): sin B11 {{90.2,86.6,87.6,96.9,89.9}},
  con B11 {{98.7,89.6,88.9,87.7,91.9}}; misma salida (md5 igual).
- Registrador: se niega sin la migración; con ella registra 1 sentencia cuyo md5 = el del archivo; idempotente.
- Front: npm run check (oxlint + typecheck + 6201 tests) PASS.
{anexo}
## Lo que quiero que intentes refutar en esta ronda (además de lo que encuentres)
0. ¿El candado nuevo cierra de verdad tu P1? ¿Introduce un problema (bloqueo de usuarios, interbloqueo, una tabla que
   falte, un camino por el que el cierre de un contacto de base nazca sin escribir en esas dos tablas)?

1. ¿Algún consumidor (servidor o pantalla) suma partes del numerador o cuenta cierres por origen con otra copia de la lista
   que NO esté en el diff, y quedaría descuadrado con un cierre de base? (p. ej. alarma, metas, ranking, fotos del cierre
   de mes, crm.cerrar_periodo / cierre_mes_vendedor). Si lo afirmas sin texto transcrito que lo pruebe, márcalo HIPÓTESIS.
2. Mes SELLADO: el divisor de coordinación devuelve base NULL (la foto no lo guarda). ¿Es correcto devolver NULL y que la
   pantalla no valide la suma en un mes sellado? ¿Qué pasa cuando se selle por primera vez un mes con cierres de base?
3. ¿El drop + create de las dos funciones privadas puede romper algo en caliente (llamadas concurrentes, planes en caché,
   dependencias), o deja ACL/seguridad distinta?
4. ¿El ayudante con `set search_path` (no inlineable) puede tener un costo relevante en las métricas grandes?
5. ¿La actualización de huellas del censo analítico es correcta o abre una vía para esquivar el trinquete?
6. ¿El orden «pantalla primero, servidor después» es seguro en los dos sentidos (pantalla nueva + servidor viejo;
   pantalla vieja + servidor nuevo)?

Formato: VERDICT (APPROVE / APPROVE_WITH_NITS / BLOCK), SUMMARY, FINDINGS P0–P3 (cada uno con la evidencia transcrita que lo
sostiene; si no la hay, HIPÓTESIS), RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.
"""
open(os.path.join(S, sys.argv[1]), 'w').write(t)
print(len(t))
