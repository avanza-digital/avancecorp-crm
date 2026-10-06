import os, sys
S = os.path.dirname(os.path.abspath(__file__))
M = '/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/bases-cargadas-b11-20261005/CRM-Avance-Corp/supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql'
mig = open(M).read()
i = mig.index('-- Exclusión de migraciones ANTES'); j = mig.index('-- ── 2 · Las piezas')
pre = mig[i:j]
k = mig.index('-- ── 4 · Censo analítico'); post = mig[k:]
cab = mig[:i]
proto = open(os.path.expanduser('~/.config/ai-collaboration/REVIEW_PROTOCOL.md')).read()
anexo = open(os.path.join(S, 'anexo.md')).read() if os.path.exists(os.path.join(S, 'anexo.md')) else ''
F = '```'
t = f"""ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

# Encargo: refutar B11 de «Bases cargadas» (CRM Avance Corp) — LEVEL 3 (datos/conversión)

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

## Pantalla (diff exacto, sin los tests)
{F}diff
{open(os.path.join(S, 'front-prod.diff')).read()}{F}

## Resultados medidos (banco Docker a paridad 922/922 funciones crm+private con producción; huella agregada idéntica)
- Migración aplicada en UN mensaje: preflight y postflight en verde (0,35 s).
- Paridad A/B (b11-paridad.sql, como Gerencia, ago/sep/oct + rango): 32 salidas (coordinación, conversión mensual sin
  cartera, Equipo, Inteligencia comercial, Distribución v3, conversión mensual por vendedor, divisor de empresa proyectado,
  cierres, crm.conversion_mensual_fn, alarma) IDÉNTICAS antes y después; la única diferencia es la clave nueva
  base_cargada = 0. Foto de trinquetes idéntica.
- Suite de comportamiento (clona un cierre real de octubre como contacto de base y como «otro»): 23/23. Base: numerador
  +1, divisor +0, cierres +1 en mensual/Equipo/Distribución/Inteligencia comercial, coordinación con base +1 y partes =
  bruto en cada fila, sondas de paridad de Equipo y Distribución en verde, la sonda «cierre sin episodio» ve un contacto
  de base convertido sin episodio. «Otro»: +0 y cuenta en «otros». Mes sellado con foto: cierres_base_cargada NULL en filas
  y total; el ajuste de un cierre de base anulado pesa 1; el de «otro», ninguno.
- Mutantes: 16/16 caen (cada copia vieja de cada función, ayudante sin base, base contada como 0, «otros» con base, mes
  sellado con 0 inventado, coordinación sin la clave).
- Frenos probados: con un cierre de base presente, la migración y la reversa se niegan (P0409) y sueltan el candado.
- Reversa: deja el banco con las 922 funciones y el censo IDÉNTICOS a producción.
- Front: npm run check (oxlint + typecheck + 6134 tests) PASS.
{anexo}
## Lo que quiero que intentes refutar (además de lo que encuentres)
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
