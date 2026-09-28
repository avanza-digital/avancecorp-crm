---
tags: [crm, ranking, origen, correccion]
fecha: 2026-09-28
estado: siete reclasificaciones aplicadas y verificadas
---

# Ranking — corrección auditada de «Otro»

Miguel señaló S/60.000 bajo «Otro» después de publicar el desglose de Cartera.
«Otro» es una opción real del catálogo de alta, no un residual del cálculo.
La investigación anterior solo contabilizó `sin_origen`: fue incompleta al
presentarlo como el único tipo de procedencia sin aclarar.

La lectura productiva de septiembre encontró siete inversiones con `otro`,
por 98.100 PEN + 11.000 USD, además del contrato real de 10.000 PEN sin vínculo.
En los siete leads, INSERT y todos los UPDATE de audit_log conservaban `otro`;
notas, actividades, operaciones y solicitudes no acreditaban otro canal.

## Decisiones expresas y resultado

Miguel confirmó **Formulario** para los dos casos de la ficha reportada,
40.000 PEN de Avance y 20.000 PEN de Qorilazo. Para los otros cinco instruyó:
«ponles formulario y landing distribuye tu mismo».

Se asignaron administrativamente tres casos a Formulario (32.000 PEN y
11.000 USD) y dos a Landing (6.100 PEN). Esta distribución **no recupera ni
acredita el canal histórico**. Cada ficha lleva nota visible que lo declara;
la auditoría diferencia `confirmacion` de `asignacion_administrativa`.
El manifiesto con identificadores personales permanece privado.

Resultado productivo:

- Siete cambios aplicados en una sola transacción, siete recibos de auditoría
  de negocio y auditoría automática del lead. Lote
  `67f59b1d-6757-4f02-813f-f2cac51e5e22`.
- Septiembre: **cero inversiones bajo Otro**. Permanece el caso de 10.000 PEN
  `sin_origen`, no incluido en la autorización de reparto de cinco casos.
- Ficha reportada: Formulario pasa de 160.000 PEN + 5.000 USD a
  **220.000 PEN + 5.000 USD**. Conversión de ese canal: 4,69 % → 7,58 %
  (66 leads, 5 cierres). Con TC 3,3776, Formulario S/236.888; total S/371.057,60.
- El servidor sincronizó seis acreditaciones abiertas al cambiar los leads.
  El séptimo lead fue convertido antes de septiembre y conserva la política
  histórica existente. No se le creó una acreditación retroactiva.
- La conversión mensual general también se recalculó: 5,84 % → 6,22 %, numerador
  89 → 95 y divisor 1.525 → 1.527. No afirmar porcentajes intactos: los cambios
  de canal, incluidos los administrativos, afectan estas métricas. Los cambios
  de responsables se limitan a cuatro analistas del lote.
- Huellas de contratos, cuotas, cierres externos, operaciones de Cartera,
  episodios y fotos mensuales idénticas dentro de la transacción. Sin cambios
  de capital, moneda, fechas comerciales ni atribución financiera.
- Control analítico: cero pendientes, sello válido.

## Implementación y verificación

Mantenimiento DML con `corregir-otros-confirmados.sql`; no migración, nuevo
endpoint, permisos ni despliegue de frontend. Usa la válvula administrativa
existente `crm.op_privilegiada` en SQL y mantiene todos los triggers normales,
incluido `conversion_acreditacion_evento_trg`. No deshabilita triggers ni cambia
`session_replication_role` en producción.

Guardas: postgres + identidad de Gerencia activa, REPEATABLE READ, candado del
mes y rechazo si está sellado, filas exactas con NOWAIT, fuente/cliente/analista/
importe/moneda/mes concordantes, origen anterior `otro`, canal y evidencia
explícitos, preservación de los demás campos del lead y huellas protegidas.
El lote es idempotente mediante su recibo y no duplica notas ni auditorías.

Banco propio `ranking_origen_correccion_20260928` en Docker, clonado del banco
ficticio `conversion_tipos_v3_20260927`. Las cuatro funciones críticas de origen,
acreditación e inmutabilidad se compararon con producción por MD5: idénticas.
Fixtures propios: contratos y COOPAC, PEN/USD, lead convertido antes de
septiembre. Los primeros dos intentos de carga detectaron relojes SLA y una
activación de política incompleta; ambas se corrigieron solo en el fixture,
con rollback del ensayo fallido.

PASS: siete correcciones y seis acreditaciones sincronizadas; notas visibles
de los cinco casos administrativos; repetición con cero cambios y siete recibos;
importe incorrecto, actor sin Gerencia, duplicado, motivo ausente y mes sellado
rechazados por la causa esperada. Todos los ensayos usan ROLLBACK. Sintaxis
Node y `git diff --check` PASS. Readback productivo y auditoría PASS.

Revisión Claude: **sin dictamen válido (NOT RUN)**. El primer intento no completó;
segundo, autorizado fuera del sandbox, devolvió salida sin VERDICT válido.
No se atribuye PASS a esos intentos ni se repitió buscando una aprobación.
PRIMARY verificó las guardas y los ensayos concretos. No se ejecutó de nuevo
el gate frontend: no cambió ningún archivo de la aplicación.

Límite: «Otro» continúa disponible en el alta. Esta corrección de datos no
impide futuros registros ambiguos ni declara resuelto el canal del contrato
restante. Retirar esa opción y exigir canal concreto requiere cambio separado
de captura y servidor; no se oculta esta limitación.

Evidencia privada: `/private/tmp/ranking-origen-confirmado-20260928`.
El PR #122 anterior terminó sus controles de GitHub en PASS y quedó fusionado.

Relacionado con [[Ranking - desglose completo y nueva inversion de cartera (2026-09-28)]].
