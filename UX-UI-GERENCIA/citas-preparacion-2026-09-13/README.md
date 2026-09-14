# Citas: preparación del avance mensual, sin publicación

**Solicitud:** «prepara todo para poder hacer deploy, pero no lo hagas todavía».
Estado: implementación integrada y verificada en local/banco propio; **NO DEPLOY**.
Producción fue consultada exclusivamente en lectura. No se instalaron estas
cuatro migraciones, no se activaron reglas comerciales ni se subió un artefacto.

## Entrega preparada

- Citas → Resultados utiliza los componentes del CRM, el recorrido horizontal
  de inasistencias y la tabla mensual por analista; conserva Bandeja y Agenda.
- Filtros compactos de supervisor, analista, mes y cuatro semanas comerciales:
  1–7, 8–14, 15–21 y 22–fin. El resto se encuentra en «Más filtros».
- La semana y los filtros operativos de cita delimitan el seguimiento; avance,
  ticket y proyección se calculan sobre el mes. Los filtros de población sí
  delimitan el conjunto mensual y están declarados en la ayuda.
- Meta interna 1,25; objetivos 70/70; manuales incluidos; cada cita atendida
  cuenta como entrevista. La cifra de 1,25 no aparece en el tablero comercial.
- Colores aprobados: azul al alcanzar objetivo, ámbar por mejorar, rojo para
  brecha importante, gris sin base y navy para clientes recuperados. Se conserva
  texto, icono y detalle accesible: el color no es la única señal.
- Superadmin dispone de guardado de borrador y aplicación explícita con vigencia,
  historial inmutable, auditoría y conflicto de edición. Guardar no aplica.
  No se permiten meses anteriores ni meses sellados.
- El selector «Moneda de los importes reales» separa PEN/USD del filtro avanzado
  de moneda estimada del lead. No hay conversión cambiaria inventada.

Las capturas `crm-1440.png`, `crm-1280.png`, `crm-768.png` y `crm-390.png`
corresponden al **módulo real con respuestas de prueba**, dentro del shell del CRM.
No acreditan datos ni despliegue de producción. Los prototipos previos se conservan.

## Fuentes y reglas de cálculo

| Dato | Fuente y unidad |
| --- | --- |
| Base de leads | Ledger `crm.lead_asignaciones`, personas distintas por analista y mes, incluidos manuales y leads sin cita. Total recalculado por persona. |
| Citas generadas | Tareas de cita del CRM creadas en el mes. Agendar para otro mes suma actividad, pero no acelera la previsión del mes consultado. |
| Entrevistas | Estado canónico de `private.citas_episodios` y registro de actividad `reunion_realizada`. Dos visitas suman dos entrevistas. |
| Avance de entrevistas | Configuración inicial `actividad_real`: entrevistas / citas con resultado (entrevista o no-show). Pendientes y futuras no son resultados observados. La alternativa por meta proyectada existe en Superadmin. |
| Clientes | Conversión nativa a perfil cliente, fecha y responsable de `private.conversion_cierres`, sin anulación. La relación con una entrevista exige que su registro sea anterior al cierre. |
| Recuperación | Personas que faltaron → nueva cita vinculada → entrevista vinculada → conversión posterior. Seguimiento hasta el corte, incluso fuera del mes de origen. |
| Ticket mensual | Capital canónico de contratos nuevos del mes de clientes convertidos ese mes / perfiles cliente distintos. Se suma cada contrato una vez, sin multiplicarlo por leads repetidos. |
| Proyección | Ritmo de citas previstas dentro del mes, tasa de entrevistas observada, repetición de visitas, conversión y ticket del analista. Se limita a la población elegible; no cae por debajo del capital real. Un mes terminado muestra su resultado real. |

El ticket enlaza **`contratos.cliente_id = leads.perfil_id`**, a través de
`private.capital_episodios`; no depende de `leads.contrato_id`. La inspección
productiva encontró 27 leads convertidos activos con perfil cliente, ninguno
con `contrato_id` y 23 con contratos por perfil. Se verificó el flujo canónico y
se corrigió ese enlace. Se excluyen renovaciones, upgrades y desgloses; los
contratos nuevos adicionales del mismo cliente sí se suman en su mes.

El ticket conserva la atribución real mensual del cierre y del capital aunque
el seguimiento se configure por origen. Si falta importe o los responsables no
coinciden, se muestra la incidencia y no se fabrica el ticket. La proyección
queda sin calcular con monedas mixtas, sin clientes con importe o sin base.
El total de proyección suma analistas calculables y declara cuándo es parcial.

## Decisiones pendientes de Miguel

Estas preguntas se enviaron durante la preparación y no tienen respuesta.
Se implementaron ambas opciones; el sistema no elige por silencio.

1. Base del 70% de clientes: entrevistas totales o personas entrevistadas únicas.
   Ejemplo: 70 entrevistas, 60 personas y 42 clientes equivalen a 60% o 70%.
2. Mes del resultado: mes en que ocurrió o mes de primera asignación del lead.
3. Analista del resultado: quien lo obtuvo o quien recibió inicialmente el lead.

Esas tres claves y el mes de entrada en vigor permanecen `null` en la
configuración inicial. Se muestran cantidades; las tasas dependientes y la
proyección requieren reglas completas aplicadas por Superadmin. Los valores
1,25 y 70/70, los manuales y el conteo repetido de entrevistas sí están confirmados.

## SQL preparado y orden de instalación futura

1. `20260911212756_crm_control_citas_superadmin_borradores.sql`
2. `20260913204847_crm_citas_base_asignada_meta_interna.sql`
3. `20260913225042_crm_citas_gestion_mensual_configurada.sql`
4. `20260913225755_crm_citas_avance_fuentes.sql`

Archivos en `CRM-Avance-Corp/supabase/migrations/`; hashes en `inventario.json`.
Son candidatas nuevas, todavía sin instalar en producción. El banco propio
`citas-validacion-20260912` (`xhgsjtzpmwlqfkninphl`) contiene el ensayo y los ajustes
de revisión. Las funciones finales se contrastaron con las candidatas.
No se instalaron scripts de prueba en producción.

El banco se devolvió a `INACTIVE` al terminar. Su estado histórico de creación
de rama conserva `MIGRATIONS_FAILED`; las pruebas usaron el esquema completo
reconstruido previamente y las candidatas ensayadas. No se presenta ese ensayo
como un replay limpio de todo el historial. La base de la rama tampoco incluye
las dos últimas migraciones de Leads presentes en producción.

El lector conserva la firma y los grants existentes; añade `gestion.version=2`
al contrato JSON. El frontend conserva lectura de contratos históricos y deja
el cumplimiento sin base cuando el servidor antiguo no entrega asignaciones.
No reemplaza esa base con las personas que ya tenían una cita.

Los tipos `public,crm` se generaron desde el banco y se incorporaron únicamente
las dos tablas y la RPC nuevas. No se reemplazó el archivo entero: esa rama no
contiene las últimas RPC de Leads y hacerlo habría borrado contratos ajenos.

## Verificación

| Gate | Resultado | Evidencia / límite |
| --- | --- | --- |
| `npm run check` final | PASS | 243 archivos, **3.512 pruebas**, lint, typecheck, cobertura, build, release, bundle y duplicación 0,56%. |
| Playwright global | FAIL inicial | 178 PASS, 26 SKIP, 1 expectativa histórica antigua en `graficas.spec.ts`. |
| Corrección y repetición proporcional | PASS | 14 E2E de Citas, Superadmin y Gráficas; incluye el único fallo anterior. No se afirma una nueva corrida global completa. |
| SQL del avance en esquema real | PASS | Manuales, base sin citas, fechas, entrevista anterior, conversión nativa con contrato por perfil, USD, atribución, roles y anulación; BEGIN/ROLLBACK. |
| SQL de configuración | PASS | PostgreSQL temporal: ocho perfiles, validación, permisos, auditoría, edición concurrente, vigencia, meses anteriores/sellados y aplicación explícita. |
| Auth/PostgREST de configuración | PASS | **48 comprobaciones**; Superadmin activo, perfiles ajenos/inactivos, anónimo, sin acceso directo a tablas, guardar/aplicar y conflictos HTTP 409. |
| Backend offline | PASS | `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight`. |
| RLS general remoto | **FAIL** | **55 / 1.828**. Los 55 nombres normalizados coinciden con la corrida anterior 55/1.829; no es un A/B contemporáneo ni demuestra cero regresiones. |
| Control analítico | PASS | 34 declarados, 30 bajo techo, cuatro auxiliares y cero sin declarar. Sin subir topes ni añadir excepciones ajenas. |
| Advisors de Citas | Revisados | RLS sin policies y RPC DEFINER para authenticated son intencionales y tienen denegaciones comprobadas. Se añadieron índices FK; quedan dos avisos INFO de índices recién creados sin uso. |
| Revisión independiente | PASS con correcciones | Ver `revision.md`. La opinión no sustituye los gates. |
| Preflight productivo de solo lectura | PASS | 279 migraciones; el lector y el capital conservan las huellas esperadas; configuración nueva ausente. |
| Reversión limitada | PASS en banco | `rollback-lector.sql` restauró exactamente el lector capturado y pasó el censo dentro de una transacción finalmente revertida. |
| Instalación / deploy / smoke productivo nuevo | **NOT RUN** | El usuario pidió expresamente no desplegar todavía. |

La prueba HTTP detectó que `40001` dejaba el conflicto de versión reintentándose.
Se sustituyó por `PT409`, que devuelve HTTP 409; el frontend conserva la edición
y solicita la última versión. El ensayo real terminó correctamente después de
la corrección. Referencia: [errores personalizados de PostgREST](https://docs.postgrest.org/en/v14/references/errors.html).

La prueba HTTP conservó su historial sintético con vigencia `2099-01`; no aplica
al mes actual. Los perfiles ficticios creados quedaron inactivos y bloqueados,
sin correos enviados. El test SQL mensual revierte sus filas. No se borró el
historial del banco general ni se alteró producción para conseguir un PASS.

La revisión visual final corrigió el ancho del contenedor del selector de moneda
para mantener su flecha alineada y la cabecera en una fila. Build y E2E del módulo
en cuatro anchos se repitieron tras ese ajuste CSS y pasaron.

## Publicación futura: pasos todavía no ejecutados

1. Resolver las tres decisiones, definir vigencia y diagnosticar los fallos del
   gate general; una coincidencia de nombres no sustituye la comparación A/B.
2. Revisar/confirmar el SQL exacto y volver a ejecutar `preflight-produccion.sql`
   inmediatamente antes de cualquier instalación autorizada.
3. Integrar cualquier cambio remoto conservándolo. El commit definitivo debe
   ser idéntico en `main` y `avancecorp/main`, sin release branches ni force push.
4. Construir desde ese commit limpio con `npm run check` y crear/verificar el
   artefacto usando `scripts/crear-artefacto-release.mjs`. No usar `--allow-dirty`
   para presentar un ZIP como publicable. El build local actual es de validación.
5. Sólo tras autorización de deploy: instalar las cuatro candidatas, comprobar
   contratos/grants/censo, publicar el artefacto y hacer smoke autenticado.
6. Superadmin revisa y aplica las reglas acordadas; comprobar tasas, entrevista,
   conversión, anulación, moneda y cambios de responsable/mes con casos conocidos.

Si se decide revertir, `rollback-lector.sql` restaura exclusivamente el lector
capturado y su declaración; conservar el historial de configuración y volver al
artefacto frontend anterior verificado. La reversión rechaza una huella diferente
para evitar borrar una modificación posterior de otra sesión.

Esta preparación no autoriza ni ejecuta los pasos productivos anteriores.
