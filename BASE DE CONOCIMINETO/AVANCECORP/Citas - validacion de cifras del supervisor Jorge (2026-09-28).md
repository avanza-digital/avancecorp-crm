---
fecha: 2026-09-28
estado: validado
tags: [crm, citas, supervision, validacion]
---

# Citas — validación de cifras del equipo de Jorge (28/09/2026)

Miguel vio en Citas → Resultados, pie «Total del equipo» con Jorge Marzano como supervisor:
**160 citas · 37 entrevistas · 40,2 %**, y preguntó si era coherente (37/160 = 23,1 %).

**Veredicto: las tres cifras son exactas y coherentes con las reglas acordadas el 13–14/09.**
Reproducidas en producción con SELECT (CLI `supabase db query --linked`, 28/09 15:41 Lima) por dos vías
(réplica del lector `private.citas_gerencia_consulta` y conteo directo sobre `crm.tareas`); Codex las
confirmó como revisor (`CRM-Avance-Corp/docs/encargos/2026-09-28-codex-citas-cifras-jorge*.md`).

## Qué mide cada cifra

- **160 citas** = citas CREADAS en septiembre (por fecha de creación), del responsable de la cita
  (`tareas.vendedor_id`), de CUALQUIER estado: 35 realizadas, 55 no asistió, 24 vencidas sin resultado,
  29 programadas (17 en octubre), 12 canceladas, 5 reprogramadas. 95 leads distintos.
- **37 entrevistas** = citas completadas con asistencia registrada (`reunion_realizada`) en septiembre.
  29 personas distintas; 5 leads repiten (13 entrevistas), como manda la regla «dos asistencias = dos entrevistas».
- **40,2 %** = 37 / **92 citas con resultado** (37 realizadas + 55 no asistió, por fecha prevista), con
  `base_avance = actividad_real`. El divisor NO son las 160: excluye 71 de ellas (futuras, vencidas, canceladas,
  reprogramadas) e incluye 3 creadas en agosto con resultado en septiembre. 160 − 71 + 3 = 92.
- Las 25 vencidas sin resultado mueven la tasa cuando se cierren: entre 31,6 % (todas «no asistió») y 53,0 %.

## Hallazgos que no son de cálculo

1. **El pie «Total del equipo» no muestra el divisor** (solo el detalle por analista imprime «37 entrevistas /
   92 citas con resultado», `avance-mensual.tsx:54`; el pie no abre detalle y el CSV no lo exporta). Por eso la
   fila parece decir «37 de 160». Codex lo clasifica P2 de presentación. Cabe en [[Todo numero se abre]].
2. **Un «no asistió» con fecha futura**: cita `53b4ac59` (Fiorella), reprogramación de `4f73735d`, creada el
   23/09 17:15 con fecha 30/09 17:14 (parece +7 días automático) y marcada no asistió 2,5 min después. Hoy no
   cuenta; el 30/09 17:14 entra sola al divisor (37/93 = 39,8 % si nada más cambia). Falta reconstruir el flujo.
3. **Dos reuniones de Vladimir con inversionista y sin lead** no las cuenta el módulo (el lector exige lead).
4. **Asistencias registradas antes de la fecha prevista** (dos de Alan, 23/09 para citas del 24 y 25): el CRM
   lo permite; reunión adelantada o cierre anticipado. No altera la fórmula.
5. El **perfil de pruebas de Miguel** está en el equipo de Jorge: aporta 1 de las 160 citas (vencida) y 0 al
   divisor. Ver [[Cuenta piloto CRM Miguel]].
6. Inactivo hoy: con `conteo_entrevistas = personas_unicas` la tasa usaría personas (29/92 = 31,5 %) pero el
   detalle seguiría imprimiendo «37 entrevistas» (`avance.ts:125,173`).

Reglas y contexto: [[Citas Gerencia - avance integrado sin deploy 2026-09-13]],
[[Citas Gerencia - decisiones finales para publicar 2026-09-14]],
[[Citas Gerencia - Supervisión por equipo 2026-09-27]]. Consultas reproducibles en el encargo a Codex.
