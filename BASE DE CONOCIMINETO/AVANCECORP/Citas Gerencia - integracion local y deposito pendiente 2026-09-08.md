---
fecha: 2026-09-08
estado: integrada-en-local-sin-publicar
tags: [crm, citas, gerencia, ux, datos]
---

# Citas: integración local y depósito pendiente

Miguel autorizó comenzar el desarrollo de la propuesta ya adaptada al CRM. Continúa [[Citas Gerencia - tablero horizontal y flujo por persona 2026-09-08]] y [[Fundamentos UX del CRM]].

El módulo se monta en Gerencia → Citas usando el marco real del CRM y componentes compartidos con el prototipo. Conserva filtros compactos por mes/cuatro semanas, recuperación horizontal, citas por lead, meta 3=100% y objetivo 3.75=125%, desglose y ficha a demanda. El promedio usa leads distintos con cita del conjunto filtrado; no la cartera completa, y no prorratea la meta por semana. No cambia la política productiva de metas mensuales.

La consulta nueva `crm.citas_gerencia_consulta_fn` entrega citas activas del mes y todo el historial activo de esos leads para seguir reprogramaciones explícitas incluso fuera del mes/semana. Autoriza mediante `private.rol_crm`: solo Gerencia activa. Directorio conserva su lector agregado. Se registra el responsable de la cita, sin afirmar que sea el creador ni atribuir pertenencias históricas que no existen.

Asistencia se toma del resultado de actividad vinculado y su timestamp es el registro del resultado, no una medición de llegada. Cierres posteriores se basan en los resultados convertidos de asignaciones y excluyen anulados, con la misma evidencia de [[Capa semantica del servidor - plan por nucleos (episodios)]]. Se incluyen cierres anteriores al mes para describir el historial correctamente.

**Un cierre no acredita un depósito.** El censo no encontró fecha de depósito y confirmación bancaria utilizables; el módulo real muestra — / Sin verificar. Se preguntó a Miguel dónde registran el depósito y quién lo confirma: respuesta pendiente. El ejemplo anterior de depósitos permanece solo en el prototipo. No sustituir esta ausencia por cero, monto estimado o cierre comercial.

Censo remoto solo de lectura: 152 citas activas de leads, 55 no-show, 27 con sucesora vinculada al mismo lead, ninguna con varias sucesoras en competencia, ninguna completada sin actividad de resultado asociada. Solo se obtuvieron conteos. No se modificaron datos remotos.

Migración `20260909003243_crm_citas_gerencia_consulta_detallada.sql` aplicada únicamente al banco local aislado `citas_integracion_20260908`. No publicada. Tipos de su RPC generados con CLI local; no se reemplazaron otros tipos. Tope 10.000 citas de historial: exceso produce error explícito, no un total parcial.

PASS: gate frontend (3.130 pruebas), build, 7 E2E de Citas/gráficas y SQL de permisos, vínculos, fechas, cierre histórico, postventa y 10.000/10.001. Suite E2E completa inicial: 136 PASS, 26 SKIP, 3 FAIL; se resolvió la aserción antigua de Citas, quedan fallos ajenos en correo de ClienteForm y revisión de límite en Distribución. Preflights seed/RLS generales NOT RUN por falta de SUPABASE_URL; matriz SQL específica sí pasó. Claude entregó revisión independiente, evaluada con evidencia por Codex.

Guía, capturas de app 1280/390, código, pruebas y límites: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/integracion/README.md`. Ver en `http://127.0.0.1:4180/`, Demo → Gerencia → Citas. Una sesión real sin la migración muestra que la consulta aún no está habilitada. Esta entrega no implica aprobación visual del cliente ni autorización de publicación.
