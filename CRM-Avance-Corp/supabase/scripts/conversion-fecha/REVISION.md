# Evaluación de la revisión de implementación — 27/09/2026

Codex PRIMARY, Claude SECONDARY_REVIEWER read-only mediante el wrapper del repo.
LEVEL 3. Segunda consulta prevista, justificada por implementación nueva después
del diseño. Primer intento técnico no completó; reintento autorizado entregó
**CHANGES_REQUESTED, confianza MEDIA**, sin P0 ni vulnerabilidad demostrada.
No se pidió otra opinión para obtener PASS. La evidencia del reviewer era una
foto anterior a las correcciones siguientes; estas las verifica PRIMARY.

## Hallazgos aceptados

- **P1 — corrección de día reseteaba el vínculo.** El escritor conserva
  `vinculado_en` al corregir la misma fuente dentro del mismo mes. Cambio de mes
  mantiene recepción nueva: no adjudica un mes vencido retroactivamente.
  `prueba-integracion.sql`: corregir septiembre el 12 de octubre, antes del
  sello, conserva estado y timestamp exactos. PASS.
- **P1 — deuda por una fuente excluida antes de sellar.** Nuevo helper privado
  comparte elegibilidad entre núcleo, explicación y sello. El trigger de
  `crm.periodos_cerrados` guarda pertenencia por acreditación bajo el candado
  mensual; deuda exige `incluida_en_sello=true`. No se añaden triggers a public.
  `prueba-exclusion-sello.sql`: marcar demo por la puerta real, sellar y anular
  no genera deuda; UI muestra `fuente_demo`. Caso incluido y deuda legítima,
  siguiente mes, saldo único y capital cero: `prueba-integracion.sql`, PASS.
- **P2 — origen operativo de lead sellado.** Editarlo ya no reescribe el hecho
  congelado ni aborta la edición; prueba con la anulación posterior conserva
  el peso/origen original. PASS.
- **P2 — inserción de cooperativa.** Trigger incluye INSERT y cambios de
  fecha/lead/cierre inicial. No depende de un único orden de confirmación.
  Escritores oficiales Avance/cooperativa y reintentos: PASS.
- **P3 — defensas pequeñas.** Candidato de inversión requiere fuente no nula;
  activador usa coalesce(es_demo,false); identidad acreditada anterior a vigencia
  no bloquea la nueva política; peso de deuda se revalida después de leer la foto.

## Recomendaciones no aplicadas indiscriminadamente

- No silenciar todos los errores estructurales del trigger. Fuente ajena,
  doble captación y cambio de fuente en mes sellado deben fallar explícitamente,
  no devolver éxito con una pérdida de crédito invisible. Las puertas oficiales
  se ejecutaron realmente en el banco; las carreras retornan conflicto reintentable.
- La hipótesis de fusión que sustituye `leads.perfil_id` no coincide con
  `crm.fusionar_inversionistas_fn`: actualiza `inversionista_id`, no perfil_id,
  y conserva la fila fusionada. `private.fusion_bloqueos` ya prohíbe dos perfiles
  o dos leads en esa puerta. La FK histórica no impide esa fusión por borrado:
  no hay borrado de identidades allí. Prueba de unicidad canónica: PASS.
- Las FK de lead/episodio/identidad son restrictivas intencionalmente. Un
  episodio cerrado ya era inmutable y no eliminable antes del cambio
  (`private.trg_lead_asignaciones_inmutables`). No agregar CASCADE que borre
  evidencia. El UUID de contrato NO es FK: sobrevive a la retirada de fuente.
- Una inversión sin contrato NI cooperativa es impedida por CHECK vigente:
  exactamente una fuente. El filtro adicional es defensa, no reparación de
  un fallo reproducido en el flujo oficial.
- Fecha comercial futura respecto a la acreditación conserva `fecha_futura`:
  no se fabrica elegibilidad sólo por avanzar el reloj de lectura.
- Caché: corrección contractual invalida `crmQueryKeys.metricas()` en
  `contrato-detalle.tsx`, que incluye el prefijo nuevo. Corrección cooperativa
  usa el mismo prefijo; conversionExterna y anulaciones incluyen cierre/estado.

## Verificación posterior del PRIMARY

- Metas contrastada también con roster nominal y cuotas publicadas sintéticas,
  no sólo fuera_ranking; revisión nueva del periodo, con guards/auditoría activos.
- Retirada anterior y posterior al sello por `crm.contrato_eliminar_auditado`:
  hechos y fotos intactos; deuda sólo por la acreditación incluida al sellar.
- Identificada y cubierta la sincronización retirada/sello: trigger exclusivamente
  CRM sobre la auditoría previa al borrado. Lead NOWAIT, luego candado mensual;
  conflicto PT409 reintentable evita invertir la espera lead/contrato.
- Once carreras reales PASS: las tres iniciales y corregir/sellar, anular/sellar,
  corregir/anular, retirar/sellar en ambos órdenes. Espera advisory observada,
  reintentos y efectos finales comprobados en bases efímeras propias.
- Diez suites SQL y cinco mutantes PASS tras el último ajuste, incluida reversa.
  Estas comprobaciones no constituyen una nueva revisión de Claude.

## Límites honestos

- Claude no recibió el archivo de reversa. PRIMARY sí ejecutó su hash guard,
  restauración literal de cuatro funciones y compatibilidad de RPC/ledger.
- No hay PASS de reviewer posterior a las correcciones. Hay pruebas reales
  repetidas y evaluación razonada del PRIMARY.
- Quedan Auth/HTTP/RLS integral, advisors y regeneración integral de tipos en
  el banco remoto. Las pruebas locales de cuotas, retirada y carreras no
  habilitan publicación hasta completar el ensayo autorizado.
- Supabase 17.6.1.105 cae con denegación EXECUTE de roles hint_roles; permisos
  efectivos comprobados por catálogo. No reproducir ese crash en producción.

Actualización del ensayo: matriz remota base y candidata OFF 2267/0 cada una;
escritores HTTP 15/15, estado/plazo 5/5, tipos integrales, check y reversa remota
PASS. Advisors sin nuevas advertencias. Matriz activa final y publicación
pendientes, según `ENSAYO-REMOTO.md`. Estos son checks del PRIMARY, no un
dictamen nuevo del reviewer. Producción sigue intacta.
