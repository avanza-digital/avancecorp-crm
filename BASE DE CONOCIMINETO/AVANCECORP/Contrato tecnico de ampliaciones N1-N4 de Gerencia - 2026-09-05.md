---
tags: [crm, gerencia, metricas, contrato, n1, n2, n3, n4]
requerimiento: REQ-GER-MET-001
fecha: 2026-09-05
estado: sql-productivo-aplicado-y-verificado-frontend-pendiente
---

# Contrato técnico de ampliaciones N1–N4 de Gerencia

Relacionado con [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]], [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] e [[Inventario de indicadores de Gerencia - Contrato de lectura]].

## Resultado local

Se ampliaron exclusivamente las respuestas existentes de Conversión y Citas. No se creó RPC, función ni calculadora independiente. Los núcleos `private.conversion_episodios`, `private.citas_episodios` y `private.capital_episodios`, y las fachadas `crm.metricas_conversiones_fn` y `crm.metricas_reuniones_fn`, permanecen con sus definiciones y permisos anteriores.

La terminología visible acordada por Miguel es **«Resultados de los leads del mes»**. Se retiraron «Resultados de las llegadas · hasta hoy» y «Cosecha del lote» de Resumen, Conversiones y Ranking. Es sólo un cambio de presentación: la población sigue siendo los leads recibidos en el mes y el servidor conserva su corte y atribución canónicos.

SQL exacto confirmado por Miguel y aplicado en producción el 5 de septiembre, 12:53 Lima: `CRM-Avance-Corp/supabase/migrations/20260905175342_gerencia_contrato_cuatro_datos.sql`. El archivo se renombró desde el identificador preparado `20260905155129` al registrado por Supabase, sin cambiar un byte del contenido aprobado. Reversión exacta: `CRM-Avance-Corp/supabase/scripts/rollback-gerencia-contrato-cuatro-datos.sql`. Huellas, permisos y respuestas reales comprobados en [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]]. La publicación del frontend ya está autorizada y sigue en curso.

## N1 · Llegadas con cita registrada como realizada

- Respuesta: `crm.metricas_conversiones_fn` → `citas_reales`; desgloses compatibles en `origenes[]` y `responsables[]`.
- Unidad: `lead_id` único. No deduplica identidad de persona entre leads diferentes.
- Población: llegadas comerciales únicas del rango y filtro de origen ya fijados por el núcleo de conversión.
- Hecho de cita: fila clasificada `realizada` y vencida por `private.citas_episodios`.
- Fecha disponible: `vence_en`, la fecha prevista. No se inventa hora física de asistencia.
- Corte: desde la llegada hasta `seguimiento_hasta`, que coincide con `generado_en`.
- Atribución de la llegada: primer analista. El autor de la cita no cambia esa propiedad.
- Una cita anterior al alta no entra al indicador; viaja separada en `citas_anteriores_al_alta` como anomalía.
- Campos principales: `leads_base`, `leads_con_cita_real`, `citas_realizadas`, `pct_llegadas_con_cita_real`.

## N2 · Explicación de realización por modalidad

- Respuesta: `crm.metricas_reuniones_fn` → cada fila de `modalidades[]`.
- Se proyectan tres valores que el agregador ya usaba: `divisor_realizacion`, `canceladas_sistema_vencidas` y `reprogramadas_vencidas`.
- El porcentaje continúa siendo `pct_realizacion` servido por el servidor. El frontend no lo recalcula ni invierte un valor redondeado.
- Con contrato nuevo: «4 realizadas de 17 computables» y sus exclusiones. Con respuesta anterior/parcial: el porcentaje se conserva y la base se declara no disponible. Divisor cero con porcentaje nulo no se convierte en 0 %.

## N3 · Operaciones elegidas y aporte exacto

- Respuesta: `crm.metricas_conversiones_fn` → `conversion_operaciones`.
- Fuente: las filas `tipo='operacion'` ya seleccionadas por `private.conversion_episodios`. No se repite `row_number` ni la fórmula de pesos.
- Lectura declarada `viva`, completa y global respecto del origen de leads, con `desde`, `hasta` y `America/Lima`.
- `detalle[]` conserva `operacion_id`, analista atribuido, categoría, período, fecha del numerador y `aporte_numerador`. Incluye una operación seleccionada aunque su aporte sea cero.
- Mi Cartera sólo interpreta una ausencia como «no aportó» cuando Gerencia recibió el mapa completo del mismo mes y rango. Error, mapa incompleto o rango distinto permanecen desconocidos; nunca se convierten en cero.

## N4 · Cierres por fecha real del cierre

- Respuesta global: `crm.metricas_conversiones_fn` → `cierres_por_semana`; cada `responsables[]` recibe su arreglo homónimo.
- Fuente temporal: `fecha_numerador` del episodio de cierre; no la fecha de llegada.
- Atribución: analista que consiguió el cierre.
- Agrupación: bloques consecutivos de siete días desde el inicio solicitado, con límites y zona Lima explícitos.
- Se separan `cierres` y `aporte_cierres`. Las operaciones de Cartera no se mezclan y se declara `incluye_operaciones_cartera=false`.
- Los cierres cuyo autor no pertenece al roster no se reasignan: se declaran explícitamente mediante residuales globales y semanales, tanto en cantidad como en aporte.
- La tendencia histórica por semana de llegada permanece intacta y conserva su rótulo propio.

## Evidencia aislada

En el cluster temporal sin TCP se ejecutaron, en este orden:

1. migración completa con cuerpos productivos exactos;
2. rollback completo al estado previo;
3. migración final nuevamente;
4. prueba sintética transaccional `test-gerencia-citas-extremos.sql`.

La prueba cubre N1–N4. Para N1 usa tres `lead_id`: uno con avance comercial pero sin cita completada, dos con tres citas válidas en total y una cita anterior al alta excluida. También verifica divisor y exclusiones por modalidad; llegada a Ana/cierre de Luis; renovación ×0,15; upgrade ×1; identidad, analista, período, fecha y aporte de la operación elegida; segunda operación del mismo cliente/mes no elegida aun cuando el rango parcial la deje sola; cambio de día UTC frente a 23:30 Lima; filtro de origen; varias semanas; residuales fuera del roster; PEN/USD; Gerencia autorizada y vendedor/sin identidad/núcleo privado denegados. Los fixtures se revierten.

Huellas de definición nuevas esperadas:

| Objeto existente ampliado | MD5 |
| --- | --- |
| `private.metricas_conversiones_implementacion(date,date,text)` | `be4e1c283a1f3042828cbb8c66332252` |
| `private.metricas_reuniones_implementacion(date,date)` | `6e8935eae3cf1a4c049a93cb20e1f3bd` |

Las huellas anteriores exigidas por el preflight son `372a4cfaf71bbbfcc1c921ca48096125` y `7f4f885e2d044afdd2fd0766991517a0`.

SHA-256 de los artefactos SQL auditados:

- migración: `2b8430679c77219fd3de8df8fe3c23ee3a4c8b24147d34363473d9959d902bd0`;
- rollback: `c7886e7f3369d801e9f6845948c949d2f975eabc31d334e6e787bf395f24e021`;
- prueba: `65957b31642e9779ac2a3c558e0a7c2ed9482b7ce9a9bdd34806ba97c5afb18d`.

## Verificación final local

- `npm run check`: 194 archivos y 2.819 pruebas aprobadas; typecheck, cuatro pruebas de release, build y bundle correctos; duplicación 0,68 %. Persisten únicamente cuatro advertencias previas de accesibilidad en `coverflow-carousel.tsx`.
- Pruebas focales finales de Resumen, Conversiones y Ranking: 97/97.
- `npm run test:e2e -- --workers=2`: 121 aprobadas, 26 omitidas por configuración y cero fallos.
- Revisión independiente del SQL: GO técnico; ningún hallazgo crítico, alto o medio abierto. La observación no bloqueante es vigilar el rendimiento de N1 en rangos históricos muy antiguos.

## Estado heredado del censo productivo

Lectura de sólo lectura del 5 de septiembre: el censo global ya estaba rojo antes de esta ampliación. Tenía 33 contadores frente a tope 30, cuatro sin declarar y seis declaraciones caducas. Entre estas últimas estaba el agregador de conversión: huella registrada `081face102b1b9e39b0ecc29d0eb50e0` frente a huella actual `bc43ad9e4a3616079ce062434de8949d`. El agregador de reuniones sí coincidía con `d94f54fb29b8ea11dfd84f107684c326`. El sello de la lista coincidía.

REQ-GER-MET-001 no obtiene permiso para reparar esos objetos ajenos. La migración bloquea las dos filas afectadas, toma una fotografía del resto del censo y exige igualdad exacta al terminar. Sólo actualiza y re-sella los dos agregadores que cambia; no convierte el rojo heredado en un falso verde. El rollback restaura incluso la declaración caduca anterior de conversión para ser una reversión fiel.

## Puertas pendientes

Actualización de ejecución: el SQL exacto ya se presentó; aún falta su confirmación. Candidato `5ada0c5` guardado, sincronizado y empaquetado, con cambios concurrentes posteriores por revisar antes de publicar. La publicación del frontend ya está autorizada. Evidencia vigente en [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]].

- [x] Contrato N1–N4 implementado localmente.
- [x] SQL, rollback y prueba aislada focal aprobados.
- [x] Revisión final y batería completa de frontend.
- [ ] SQL exacto mostrado y confirmado por Miguel.
- [ ] SQL aplicado y leído nuevamente en producción.
- [ ] Commit final, Main local/remoto sincronizados y frontend publicado con autorización.
- [ ] Verificación productiva de los cuatro datos y cierre del punto 5.
