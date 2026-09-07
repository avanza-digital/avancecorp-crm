# Núcleo operativo SLA — arquitectura y consumidores

Fecha: 2026-09-06. Estado: diseño incorporado al plan SLA-R2, con núcleo N1 implementado en código y 42/42 pruebas locales. Sin cambios productivos. Ver [[Nucleo SLA N1 - implementacion local y ajustes guiados 2026-09-06]].

El usuario indicó expresamente reutilizar los núcleos existentes para obtener información y organizar los cálculos nuevos necesarios en backend bajo sus propios núcleos, sin funciones o calculadoras sueltas. Se debe comunicar cuando un núcleo nuevo sea necesario; no proponerlo si la pregunta ya tiene una fuente canónica adecuada.

Para SLA es necesario un núcleo operativo: seguimiento recurrente, compromiso dominante y prórrogas todavía no están en las respuestas actuales. La verificación de solo lectura mostró `private.metricas_sla_global_core` para primera gestión/cohortes y `crm.estado_sla_leads_fn` como proyección de snapshots; se conservan sus significados.

Arquitectura normativa: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/auditoria-r2/ARQUITECTURA-NUCLEO-SLA.md`.

- Fuentes de políticas, ciclos, asignaciones, hitos y episodios reutilizadas; proveedor privado compartido para el hecho base que ya consume v1.
- `private.sla_operacion_leads`: núcleo privado que recibe ámbito y reloj resueltos; produce hechos y decisiones de atención/supervisión. Sus auxiliares y regla de prórroga pertenecen al mismo dominio.
- `private.sla_operacion_autorizada`: ventana de lectura común que usa los helpers vigentes de usuario/rol/ámbito y selecciona la perspectiva permitida.
- RPC de estado, cola y agenda: presentación, filtros autorizados y agregación de hechos; no reglas paralelas. Interfaz: validación, presentación y acciones.
- Writer transaccional de prórroga aplica la decisión canónica con locks, recibos y auditoría. La lectura no escribe.
- Citas, conversión y capital usan sus núcleos cuando se pide la métrica correspondiente; no se mezclan con el inventario de pendientes ni se altera su semántica para encajar el SLA.
- Inventario de consumidores, declaraciones/huellas vigentes, paridad v1, pruebas de dependencia y mutantes en banco. No elevar topes ni saltar censos para admitir funciones nuevas.

Relacionadas: [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]] · [[Auditoria del plan SLA - correcciones R2 2026-09-06]] · [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] · [[Capa semantica del servidor - plan por nucleos (episodios)]] · [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]].
