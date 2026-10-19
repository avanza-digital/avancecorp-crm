# Fase 3 · Visita y entrevista en oficina

Puerta candidata `crm.recorrido_atender_oficina_fn` y hardening `20261019001600–01`. El usuario confirma la asistencia y el resultado comercial; el servidor registra una cita presencial inmediata y delega su cierre en `cerrar_reunion_v3`. Se conservan capital, próxima acción y «Saltar esta vez» del flujo actual. El componente reutiliza `FormCierre`; su entrada desde la guía de la ficha corresponde a fase 4.

## Contrato y revisión Codex

- Autoridad: analista propietario, supervisor del ámbito o gerencia activos. Exige analista asignado y respeta «No insistir» del lead/persona. No obliga a resolver anticipadamente identidad para una inversión.
- No acepta una fecha de visita del cliente. Tarea y actividad reciben hora del servidor y el contexto causal de su ciclo actual.
- Recibo por actor/operación en `multiempresa_idempotencia`, con hash íntegro del payload, incluido capital y siguiente acción. No amplía el dispatcher ni recibos del núcleo SLA.
- La marca de oficina exige recibo privado pendiente, actor, clave y hash que vincula tarea/lead. Una GUC aislada o metadata del cliente no la acredita. El recibo pendiente y su resultado final se escriben en la misma transacción; no quedan reservas parciales confirmadas.
- El cliente reutiliza su mecanismo de guardados por confirmar, con cubo propio de oficina y validación de su sobre. Una respuesta perdida conserva UUID y payload; cambiar capital mientras está incierto no inicia otro envío.
- El formulario espera confirmación antes de anunciar éxito. No inserta una tarea optimista ni cierra una tarea ficticia. El refresco es posterior e independiente: un error de lectura no repite ni desmiente la escritura.
- El ensayo concurrente inicial no observó una espera porque `application_name` superaba los 63 bytes de PostgreSQL. Se acortó el prefijo del ensayo; la repetición verificó las seis carreras. No se cambió producto para hacer pasar el oráculo.

## Comprobaciones

| Comprobación | Resultado | Evidencia |
|---|---|---|
| Instalación íntegra + hardening sobre objetos de fase 2 | PASS local | 20261019001600–01; preflight de huellas |
| RPC con rol authenticated, permisos, veto, sin asignar, cerrado y rechazo de anon/service_role | PASS | evidencia/fase3-oficina-sql.log |
| Capital inválido o siguiente inválida revierte todo; replay preserva capital; GUC forjada sin efecto | PASS | evidencia/fase3-oficina-sql.log |
| Doble envío simultáneo y recuperación tras rollback, además de las cuatro carreras del evaluador | PASS · 6 escenarios | evidencia/fase3-concurrencia.log |
| Cierre existente, formulario de oficina y recuperación cliente | PASS · 67 tests en 3 archivos | evidencia/fase3-frontend.log |
| Tipos desde banco, TypeScript, lint del proyecto y build | PASS; avisos de lint en archivos ajenos al cambio | evidencia/fase3-typecheck.log, fase3-lint.log y fase3-build.log |
| Realidad productiva antes de la interfaz | PASS de medición, con 2 divergencias de datos conocidas | evidencia/fase3-realidad.json |
| Entrada de la guía, revisión a11y conjunta, E2E y gate RLS integral | NOT RUN en esta fase; integración/validación en fases 4–6 | No implica protección final instalada |

El gate de realidad midió cartera, actividades, tareas, equipo y consistencia de conversión. Sus dos divergencias son 45 ventas históricas de analistas de baja y 273 clientes activos sin domicilio legal; no son regresiones de oficina ni se alteran en este goal. Se ejecutó con la sesión CLI vigente y claves solo en memoria. El intento inicial de lint con ESLint no era aplicable al proyecto; el comando correcto `npm run lint` usa Oxlint y pasó.

Revisión Codex: PASS local del contrato y de los artefactos de esta fase. No hay hallazgos aceptados pendientes. La protección definitiva de primera conversión continúa en fase 5; el entorno productivo sigue intacto.
