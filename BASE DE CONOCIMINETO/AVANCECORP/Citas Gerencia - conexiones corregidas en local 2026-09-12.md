---
fecha: 2026-09-12
estado: candidato-local-sin-publicar
tags: [crm, citas, gerencia, nucleos, verificacion]
---

# Citas Gerencia — conexiones corregidas en local

Tras [[Citas Gerencia - auditoria de conexion a nucleos 2026-09-11]], Miguel autorizó trabajar en las correcciones. Se reparó la actualización de Citas y se preparó una candidata SQL que consume los núcleos, preservando los resultados anteriores. No se instaló SQL ni se publicó.

La caché del detalle ahora cuelga de `reuniones`. Las mutaciones y el `recargar()` posterior a convertir cancelan primeras respuestas antiguas antes de invalidar. Con la ventana activa se refresca cada minuto y al recuperar foco/conexión. El frontend acepta el estado comercial del núcleo y es compatible con los contratos previos.

Candidata: `20260912151320_crm_citas_consulta_nucleos.sql`. Cohorte, estados, historial y postventa proceden de `citas_episodios`, con una sobrecarga privada que acota por leads. `conversion_cierres` comparte una única regla de cierre entre `conversion_episodios` y Citas, sin calcular pesos en el detalle. Las firmas anteriores delegan y conservan sus resultados. La conversión a cliente conserva su evidencia nativa y el anulador compartido: no se cambia la regla de [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]]. No hay capital/ticket inventado ni conexión nueva de proyección.

Se conserva cohorte mensual Lima, seguimiento entre meses, permisos exclusivos de Gerencia y error si el historial excede 10.000. Se declara sólo este lector en el registro de consumidores mixtos con huella. El gate global no queda verde: al inicio había 34 contadores con tope 30, además de cuatro lectores ajenos pendientes. No elevar el techo ni concederles exenciones para disimularlo.

Pruebas: `npm run check` PASS (3.465 tests/240 archivos, tipos, build y bundle), 3 E2E focalizados PASS, SQL PG17 local PASS con paridad exacta del lector y ambos núcleos previos, roles, estados/cierres, conversiones sin ledger, 10.000/10.001, deriva, rollback y grants indebidos. Scripts y preflight de Edge PASS. `seed:preflight`, `test:rls:preflight` y `gate:realidad`: NOT RUN por falta de `SUPABASE_URL` en comandos. No hubo ensayo completo en rama ni advisors. Las dos revisiones se evaluaron y se cerraron las correcciones locales indicadas debajo. Con 20.000 leads y 60.040 tareas ficticias la consulta acotada midió aproximadamente 30 ms; no es un SLA de producción.

Informe reproducible: `UX-UI-GERENCIA/citas-conexiones-2026-09-12/README.md`; SQL y captura saneada en esa carpeta y `supabase/migrations`.

Cierre de revisiones: dos dictámenes CHANGES_REQUESTED. Codex corrigió los puntos
pertinentes y volvió a pasar el banco, sin solicitar una tercera opinión ni
presentar un PASS independiente. Se probó equivalencia con selección no vacía,
10.000 citas/2.500 leads con cierres y reagendas, ambos núcleos antes/después,
permisos y consumidor de cierres no declarado. Se sustituyeron EXISTS de
historial/cierres por joins y agrupación; el servidor rechaza estados sin
clasificación. `decision-review.md` conserva decisiones, costes y límites.
La instalación productiva, RLS/advisors y planes reales siguen pendientes.

## Nuevas métricas todavía pendientes

No confundir la reparación con la activación de [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]] y [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]]. Siguen confirmados 1,25 citas/lead (interno), 70% entrevistas y 70% depósitos. Se consultó ticket por moneda/período, personas vs. entrevistas repetidas, actividades de leads manuales, atribución y semana acumulada. Sin respuestas todavía; no asumirlas aprobadas. La tabla real aún conserva meta histórica 3/125% sobre leads con cita.

Falta resolver esas reglas, conectar base de asignados/configuración/capital/proyección y ensayar la integración completa antes de publicar. La autorización para trabajar en local no instala automáticamente el SQL productivo.

Relacionado: [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]], [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]].
