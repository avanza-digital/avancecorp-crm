ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude. Do not
delegate to another coding agent. Do not create another review chain.

Eres el revisor secundario. Intenta REFUTAR lo de abajo; no lo confirmes por
cortesía. Repo: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`
(CRM en `CRM-Avance-Corp/`). No tienes acceso a producción: el cuerpo VIVO de
antes está EXACTO en `CRM-Avance-Corp/supabase/scripts/conversion/reversa-origenes-ponderada.sql`,
y el nuevo en la migración.

## LA DECISIÓN

Miguel (dueño): en Resumen de Gerencia, «Resultados por origen» tiene que contar
el referido al 15 %, como el número grande, y «el servidor siempre que haga todo».
Migración: `CRM-Avance-Corp/supabase/migrations/20260923185001_crm_origenes_conversion_ponderada.sql`.
Añade a cada fila de `origenes` de `private.metricas_conversiones_implementacion`
(puerta `crm.metricas_conversiones_fn`) la clave
`conversion_ponderada_pct = round(100 * contratos * peso / leads, 1)`, donde el peso es
el mismo que ya declara `peso_en_nucleo` (v_factor para referido, 1 para el resto).

## LO QUE DEBES INTENTAR REFUTAR

**B1 — LA IMPORTANTE.** Ningún otro valor del paquete cambia: la migración compara,
para 28 personas × 4 casos (mes vigente, mes anterior, rango parcial y mes con filtro
«referido»), cada respuesta por TEXTO con la de antes quitada la clave nueva. Ensayado
en prod con rollback: 112/112 idénticas; la tabla queda Formulario 3,1→3,1, Landing
1,6→1,6, Referido 72,7→10,9. Ciclo migración→reversa: 0 distintas.

**B2.** La fórmula es la correcta para «la misma cifra con el referido a su peso», y
el postflight que la recalcula desde la propia fila no puede dar verde en falso
(incluido `leads = 0`, donde ambos lados deben ser JSON null).

**B3.** El orden de despliegue es seguro con el servidor PRIMERO: el front vivo valida
la fila con `v.object` (`app/src/lib/metricas-conversiones.ts`, ConversionPorOrigenSchema),
que ignora una clave desconocida. `test-rls.mjs` fija las claves exactas de la fila:
¿hay otro consumidor que la fije y se rompa?

**B4.** Censo y reversa. La migración se generó por anclas sobre el cuerpo que dejó
`20260923172517` (otra sesión, ya en prod): preflight md5 `1af7e330…` y huella del censo
`6dc8df00…`. Re-sella la huella con la normalización del censo y exige el trinquete en
verde. El postflight fija el resultado: md5 `6e4fedb3…` y huella `315549aa…`. La reversa
exige esos dos y restaura el cuerpo, el comentario, la huella (`6dc8df00…`) y la razón,
todo literal. Ensayado en prod: pasada con resultado fijado verde; ciclo migración →
reversa con 112/112 idénticas y md5 de vuelta a `1af7e330…`.

**B5.** Ya se aplicaron los hallazgos del auditor RLS:
- anti-vacuidad por caso y por rol, con una denegación 42501 obligatoria;
- atributos fijados en absoluto, con `is_grantable`;
- resultado fijado en el postflight.

¿Queda algún camino por el que el postflight dé verde en falso?

## FORMATO

VERDICT · SUMMARY · FINDINGS P0–P3 (archivo:línea y evidencia; separa hipótesis de
hecho) · RIESGOS · NEXT ACTIONS · CONFIDENCE. Sin hallazgo sin evidencia.
