# Llamadas desde el celular — decisiones de Miguel y plan v2 de la corrección (2026-10-03)

**Estado: NADA APLICADO.** Las 4 migraciones de F2 + F3 están en `main` sin aplicar. El plan v2 de la corrección
espera el OK de Miguel en el PR #179 (borrador). Sin ese OK no se escribe SQL.

## Decisiones de Miguel (03/10, PR #175)
1. **A:** F2 + F3 se publican junto con F4-a, el enlace exacto encuesta ↔ llamada.
2. Entrantes bloqueadas; la #14 después, como paso propio.
3. La llamada a un lead de otro analista se trata como número sin lead.
4. Las llamadas sin resultado se borran a los 30 días; las registradas se conservan como historial del lead.
5. La pista por tiempo de respuesta es un riesgo aceptado por escrito.
6. Se retira la bandeja vieja.
7. **Leads sin dueño y descartados reutilizables son candidatos.** La llamada se guarda «por revisar», quien llamó no
   la ve y le aparece a quien tome el lead.
- MacroDroid Pro **no se compra todavía**: solo hace falta para las entrantes.
- La corrección la escribe la sesión de Jhosep; la de Miguel la verifica en su banco y corre Codex r2.

## Lo que encontró Codex r1 sobre el plan v1 (BLOCK, 6 P2 + 1 P3)
- La Edge no acompañaba el arreglo: rechazaba los inválidos sin gastar cupo e ignoraba la respuesta de la base.
- El sha256 del id no protegía un teléfono.
- Una etiqueta reutilizada podía perder una llamada nueva.
- Los candados no cubrían asociar ni enlazar.
- Un reloj adelantado rechazaba la encuesta del enlace exacto.
- No había barrera si fallaba la quinta migración.
- Rotar la clave reinicia el límite de envíos (menor).

## Cómo los cierra el plan v2 (PR #179)
- **Id con forma fija** `C<n>-<segundos>`, con la etiqueta del celular y una ventana de 30 días: no puede esconder un
  teléfono y se guarda tal cual.
- **Recepción** de cada aviso en `private`, antes de mirar el número; se borra a los 32 días.
- **La base es la única que valida**, y todo inválido gasta cupo.
- **Candados en un solo orden:** resultado → lead → llamada → enlace, el mismo de Deshacer y de la encuesta.
- **Barrera:** ni Edge ni altas de celulares hasta verificar la quinta.
- **Propuesta nueva (N1):** el panel de salud deja de mostrar `envios_hoy` y `ultimo_envio_en`, que cuentan llamadas
  personales.

## Lecciones
- **Dentro del CRM, saber si un teléfono existe no es secreto:** «Nuevo lead» se lo dice a cualquier analista. Las
  protecciones de la ingesta sirven frente a quien tiene la clave de un celular sin sesión del CRM. Con eso se calibra
  la gravedad de los fallos de «oráculo».
- **Un arreglo de privacidad puede abrir otra fuga.** Actualizar `ultimo_envio_en` siempre cerraba una pista, pero le
  mostraba a supervisión cuándo llamaba el analista, llamadas personales incluidas. Lo encontró el análisis de F5–F7.
- **El orden de los candados sale de las rutas reales**, no de la intuición: Deshacer bloquea primero el resultado, y
  la encuesta, primero el lead.
- **Los PR se abren como borrador:** el #169, el #171 y el #173 se fusionaron antes de que llegara la revisión.

## Relacionado
- [[Llamadas desde el celular - revision antes de publicar (2026-10-02)]]
- [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]]
- [[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]]
- Para retomar: `CRM-Avance-Corp/docs/plans/llamadas-celular/HANDOFF-2026-10-04.md`.
- Análisis de F5–F7: `CRM-Avance-Corp/docs/plans/llamadas-celular/F5-F7-ANALISIS.md` (PR #178).
