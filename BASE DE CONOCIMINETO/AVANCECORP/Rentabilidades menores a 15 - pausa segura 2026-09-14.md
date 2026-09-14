---
tags: [crm, rentabilidad, pausa, no-deploy]
fecha: 2026-09-14
estado: pausado-con-revision-pendiente
---

# Rentabilidades menores a 15 — pausa segura

> Historial de la pausa inicial. La retoma y las correcciones posteriores están en
> [[Rentabilidades menores a 15 - entrega local sin deploy 2026-09-14]]. La última
> instrucción de Miguel sigue siendo no desplegar. El contenido siguiente conserva
> el estado exacto del respaldo anterior, no el estado final de verificación.

Miguel autorizó preparar el despliegue sin ejecutarlo y luego pidió:
«pon en pausa el trabajo e un momento seguro». **Trabajo pausado. No desplegar.**
La implementación está guardada, pero todavía NO se considera lista para publicar:
hay hallazgos de la revisión independiente pendientes de corregir y verificar.

## Objetivo y alcance acordado

Permitir al analista escribir una tasa positiva hasta la base (hoy15%), con hasta
dos decimales, para inversiones `nuevo`. Precargar15 y conservar la elegida desde
lead hasta contrato. Superar la base mantiene aprobación de Gerencia; bajar la tasa
no evita solicitudes pendientes. Renovaciones/upgrades conservan el mínimo heredado;
no se da permiso para rebajar condiciones de contratos emitidos.

## Dónde quedó el trabajo

- Clone separado: `/private/tmp/avancecorp-tasas-bajas-20260913`.
- Rama `main`, HEAD y `avancecorp/main`: `b5ca1eb92110dc997ec491ef1ff177aa195daaf5`
  en el último fetch. Los cambios de esta tarea están SIN COMMIT y SIN PUSH.
- Se aisló el trabajo porque otro PRIMARY modifica Citas en el original. No integrar
  ni sobrescribir esos archivos; no cambiar su `Inicio.md`, tipos o migraciones.
- Respaldo duradero y saneado: `_DEV_NO_SUBIR/pausas/tasas-inferiores-20260914/`.
  Incluye archivos modificados/nuevos, diff, manifiesto con hashes, evidencia,
  capturas de escritorio/móvil y la revisión de Claude. No incluye `.env` ni claves.
- Candidata SQL: `CRM-Avance-Corp/supabase/migrations/20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql`.
- Ensayo y reversa: `CRM-Avance-Corp/supabase/scripts/tasa-baja/`.
- No se creó ZIP de release ni se publicó frontend, SQL o Edge en producción.

## Implementación actual

`TasaPolitica` habilita el campo solo cuando el servidor comunica
`tasa_minima_sin_autorizacion`. El rango para alta nueva es0.01–base. El parser
acepta coma/punto y hasta dos decimales; el fallback del servidor anterior permanece
cerrado. `ContratoNuevo`, `CondicionesEditables` y `rangoEfectivo` usan el mínimo del
servidor y mantienen el bloqueo por pendientes/caducidad. La preselección del lead
se conserva al abrir contrato y actualmente se protege cuando queda bajo el mínimo.

La candidata añade un helper privado y modifica tres cuerpos mediante huellas MD5
y anclas únicas. Conserva ACL, propietarios y `search_path`; se corrigió la propiedad
del helper para permitir que los callers `postgres` lo usen cuando instala
`supabase_admin`. La tasa baja queda trazada en el ledger sin solicitud artificial.

## Verificado antes de la pausa

- PASS `npm run check`:244 archivos,3535 tests; lint,types,cobertura,build,configuración
  de release,SW,bundle y duplicación incluidos.
- PASS Playwright completo:182 aprobados y26 omitidos preexistentes. Nuevos3 aprobados
  (lead→contrato12.5 en1440/390px y cliente existente→contrato13.5/cronograma).
  Las capturas se inspeccionaron visualmente.
- PASS scripts,Edge/Deno,seed/RLS preflight OFFLINE con valores ficticios.
- PASS banco PostgreSQL propio: instalación/reversa exacta/reinstalación;
  regresiones de solicitudes pendientes y lead a base/12.5; dos sesiones concurrentes;
  altas a0.01,1,12,12.5,13.99,14.99,15 por sesión authenticated del analista, lectura
  RLS propia y persistencia exacta; rechazo >base/0/negativo; correcciones/PDF,
  herencia, identidad, ledger y conversión completa12.5; cierre de helpers de API;
  reversa bloqueada tras un contrato y reaplicación bloqueada.
- El template local F3 es sintético; falta su catálogo de pares. Solo en la copia
  desechable el setup repone el par analista/vendedor de F5.b y prepara el rol sin
  impersonación. Después prueba con JWT/SET ROLEauthenticated. Ningún trigger se apagó.
- NOT RUN gate general Auth/PostgREST de13roles, advisors de candidata instalada en
  destino remoto y smoke productivo. No se confunden con las pruebas locales.

## Revisión de Claude y siguiente paso concreto

Una revisión independiente terminó `CHANGES_REQUESTED`, sin P0/P1. Archivo
`revision-claude.md`. Codex aún NO cerró estos hallazgos:

1. **Decimales de alta directa.** El servidor del contrato puede redondear12.345
   aunque el lead y el front lo rechacen. Última lectura local: `contratos.tasa_anual`
   es `numeric(5,2)`. Por eso añadir `round` al trigger AFTER NO basta: ya recibe el
   valor redondeado. Revisar la validación del JSON antes de insertar, probablemente
   en `public.crear_contrato(jsonb,jsonb)`, preservando permisos y alcance. Su MD5 en
   el template es `2f619ddf650bd0db2ffa64790f894312`; AÚN NO contrastado con producción.
   Definición completa guardada en evidencia `tasa-baja-alta-esquema.txt`.
   Añadir el caso directo12.345 autenticado y comprobar rechazo sin alta parcial.
2. **Preselección.** Ampliar `preseleccionIncompatible` a fuera de todo[min,max] y
   mantener el bloqueo aunque otra parte escriba `tasa`. Ahora solo cubre por debajo
   del mínimo y depende de igualdad con la tasa actual. Probar lead12.5 con base12,
   autorización que ya no sirve y escritura externa durante el bloqueo.
3. **Reversa durante conversión.** Ahora solo mira ledger. Debe impedir revertir
   cuando una reserva/conversión está comprometida a tasa inferior aunque todavía
   no haya contrato. `crm.conversion_reservas` tiene `condiciones_tasa jsonb`,
   `reservado_en`, `expira_en`, `efectos_iniciados_en`, `vence_absoluto_en`, `lead_id`,
   `reservado_por`, `inversionista_id`, `claim_id`, `hash_payload`. Investigar también
   el guardado de condiciones del lead y reservas de identidad; probar reversa tras
   sellar12.5 sin contrato. No ampliar borrados ni cambiar datos para permitirla.
4. **Otras puertas.** Adjuntar evidencia de comparaciones con base en SQL vigente y
   Edge. El test existente `_supabase_functions/functions/crm-convertir-lead/tasa-preconversion.test.mjs`
   ejecuta el handler TypeScript en VM y comprueba ambas banderas antes de efectos.
   Añadir un caso12.5 verificando transporte y respuesta, sin Auth/correos reales.
   No llamar a un E2E con backend simulado una integración productiva.
5. Evaluar P3 sin modificar negocio por opinión: texto engañoso al corregir12.5→14;
   etiqueta«Tasa acordada»también a15 (puede ser válida); demo→real a tasa baja
   conservadoramente bloqueado; mínimo0.01 representa precisión positiva y no una
   nueva tasa comercial configurable. Revisar reportes de anomalía vsbase.

Después de corregir: ejecutar checks proporcionales, segunda revisión dirigida solo
si aporta a los cambios de riesgo (máximo habitual2), actualizar MIGRACIONES.md,
verificacion.md/vault y preparar commit+artefacto desde Main sincronizado. NO hacer
deploy sin una nueva instrucción de Miguel. No ejecutar `db push` general porque
hay candidatas ajenas de Citas pendientes.

Las pruebas terminaron. Las bases aleatorias del runner se eliminaron automáticamente;
el contenedor y template compartidos no se detienen. No hay proceso de deploy en curso.

Relacionadas: [[Rentabilidades menores a 15 - propuesta 2026-09-13]],
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Alertas de respuestas de tasa para analistas - 2026-09-11]], [[Inicio]].
