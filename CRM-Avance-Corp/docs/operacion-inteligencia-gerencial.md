# Operación de Inteligencia Gerencial V2

## Contratos vigentes

- `monto_estimado` es obligatorio, positivo y de hasta dos decimales. La migración aborta si encuentra historia incompatible; no inventa ceros.
- PEN y USD se agregan y presentan por separado. V2 no aplica conversión ni publica un total monetario mixto.
- El SLA principal comienza en el ingreso o reapertura del ciclo y no se reinicia por asignación, transferencia o parqueo.
- El SLA de asignación sigue existiendo como indicador operativo de cada tramo y se etiqueta como tal.
- No existe descuento de pausas. Parqueos y transferencias continúan consumiendo el SLA global.

## Seguridad de las RPC

Las RPC expuestas V1 y V2 pertenecen a `crm_metricas_bridge`, un rol `NOLOGIN`, `NOINHERIT`, sin `SUPERUSER`, `BYPASSRLS`, creación de roles o acceso directo a tablas. El puente solo puede ejecutar `private.metricas_distribucion_leads_autorizada`, que vuelve a validar `auth.uid()`, Gerencia activa o lector global antes de consultar.

V1 se conserva para rollback del frontend. El frontend nuevo consume `crm.metricas_distribucion_leads_v2_fn`.

## Orden de despliegue

1. Aplicar la migración en un branch de Supabase.
2. Ejecutar el oráculo `supabase/scripts/test-metricas-distribucion-leads.sql`, RLS y advisors.
3. Fusionar la migración. El frontend anterior continúa usando V1.
4. Desde `CRM-Avance-Corp/`, ejecutar `npm run release:crm`.
5. Verificar el manifiesto con `npm run release:crm:verify -- releases/<release>.manifest.json`.
6. Conservar el release anterior y desplegar solo el ZIP aprobado en `crm.miavance.com`.
7. Verificar HTML, assets con hash, login y respuesta JSON V2. El ZIP debe seguir dando 404 públicamente.

## Rollback

- Ante un fallo de interfaz, desplegar el ZIP y manifiesto del release anterior. La RPC V1 permanece disponible.
- No eliminar las columnas de SLA global ni reescribir el ledger: contienen historia adquirida después de la migración.
- Ante un incidente específico del endpoint V2, revocar temporalmente su ejecución a `authenticated` y volver al frontend V1.
- Confirmar el SHA-256 del artefacto anterior antes de desplegarlo.

## Puerta de producción

- Cero registros incompatibles con `monto_estimado`.
- Vendedor y `anon` denegados en V1/V2; Gerencia y lector global permitidos.
- `crm_metricas_bridge` sin login, atributos privilegiados ni `SELECT` sobre el ledger.
- Una transferencia conserva el mismo `sla_global_iniciado_en` en ambos episodios.
- El resumen global incluye ciclos aún no asignados y no descuenta parqueos.
- Panel, contrato runtime y RPC reportan JSON V2.
- ZIP, manifiesto y release anterior conservados fuera del web root.

## F2: inteligencia comercial y reuniones auditables

Esta ampliación quedó **liberada en producción el 2026-08-06** por orden explícita.
Las equivalencias de versión remota y la evidencia del release están registradas
al final de esta sección.

### Contrato operativo

- Gerencia ve inteligencia comercial global y edita metas mensuales y capacidad
  de analistas.
- Gerencia no opera leads, tareas ni actividades. El veto existe en navegación,
  capacidades de frontend, RLS y triggers de base de datos.
- Pipeline, Agenda, Leads operativos, Repartir, gestión de Equipo y configuración
  técnica no forman parte de la superficie de Gerencia.
- Una reunión nueva exige modalidad explícita.
- Presencial exige lugar o dirección.
- Virtual exige enlace HTTPS sin credenciales.
- La historia anterior se conserva como `sin_clasificar`; nunca se infiere una
  modalidad.
- Reprogramar conserva la fila original como `reprogramada` y crea otra fila
  enlazada por `reagendada_de`.
- Realizada exige resultado comercial.
- No-show fija `cliente_no_asistio`.
- Cancelada exige motivo; `otro` exige detalle.

### Definiciones de métricas

- Al abrir cualquier vista de Inteligencia Gerencial, el período predeterminado
  es el mes calendario vigente en Lima: desde el día 1 hasta hoy, ambos
  inclusivos. No se usan 30 ni 90 días móviles como valor inicial.
- Los campos «Desde» y «Hasta» son un borrador hasta pulsar «Aplicar». Al
  aplicarlos, el mismo rango viaja a conversiones, reuniones, ranking y
  distribución; las fechas forman parte de las claves de consulta.
- El rango aplicado se conserva al navegar entre las vistas de Gerencia. El
  borrador sin aplicar se descarta al salir de la vista.
- La interfaz rechaza antes de consultar fechas futuras, fechas invertidas y
  diferencias mayores de 365 días, igual que los RPC. Si la aplicación sigue
  abierta al cambiar el día en Lima, el período automático avanza al nuevo MTD;
  un rango personalizado no se reemplaza.
- Conversión por cohorte: sigue los leads ingresados en el periodo hasta cliente,
  contrato confirmado y capital real.
- Producción del periodo: atribuye clientes, contratos y capital por la fecha real
  de cierre, aunque el lead haya ingresado antes.
- Reuniones pactadas: filas de agenda dentro del periodo.
- Debieron ocurrir: reuniones cuya fecha ya venció al momento de generar la
  fotografía.
- Porcentaje de realización: realizadas sobre las que debieron ocurrir, excluyendo
  cancelaciones automáticas y filas originales reprogramadas.
- Por responsable, una cancelación firmada por otra persona tampoco penaliza al
  analista dueño de la tarea.
- Asistencia: realizadas sobre realizadas más no-show.
- Una reprogramación no duplica conversiones: para cada lead se atribuye desde la
  última reunión realizada del periodo.
- PEN y USD permanecen separados; no se inventa tipo de cambio.
- La página `#/ranking-vendedores` no fija un máximo de participantes: muestra
  todo el equipo real y deja la fila técnica «Sin vendedor asignado» fuera del
  ranking.
- El ranking de conversión ordena clientes sobre leads. El ranking de capital
  ordena el porcentaje de capital confirmado PEN sobre la meta individual PEN;
  cualquier capital USD se muestra aparte y nunca entra en ese cociente.
- Las metas cargadas y editables corresponden al mes vigente de Lima. La
  comparación predeterminada queda así alineada con el período mes-a-la-fecha.
  En cualquier otro rango se muestran los resultados, pero no un porcentaje de
  cumplimiento contra la meta mensual ni un prorrateo inventado.
- La conversión objetivo inicial es 15% por vendedor. Los agregados incluyen
  ese 15% para vendedores activos que todavía no tengan fila guardada. Una meta
  personalizada prevalece; un error de lectura queda como «No disponible» y
  nunca activa el valor inicial.
- El detalle, ranking y tendencia por vendedor usan exclusivamente
  `responsables` de `crm.metricas_conversiones_fn`. Una respuesta ausente,
  duplicada o parcial invalida el bloque completo: no se completan faltantes con
  ceros ni se otorgan puestos a un subconjunto.
- El arranque de Gerencia carga roster y metas, pero no descarga leads,
  actividades ni tareas operativas. Esta minimización reduce PII en el cliente;
  no sustituye las políticas RLS como frontera de seguridad.
  Los indicadores rotulados como «actual» (capacidad, cartera o cola) siguen
  siendo una fotografía operativa del momento, aunque se consulte otra cohorte.

### Orden de liberación F2

1. Crear respaldo y confirmar el destino de Supabase antes de cualquier escritura.
2. Aplicar `20260805180000_crm_inteligencia_comercial_reuniones.sql` en branch o
   staging, nunca primero en producción.
3. Ejecutar `supabase/scripts/test-inteligencia-comercial-reuniones.sql` en una
   base aislada y ejecutar RLS/advisors del branch.
4. Validar con sesiones reales de vendedor, supervisor y Gerencia en branch.
5. Aplicar la migración de producción solo con la orden explícita de liberación.
   El bundle anterior queda temporalmente compatible mediante
   `sin_clasificar`, sin inventar presencial o virtual.
6. Desplegar `crm-agenda-ics` después de la migración.
7. Generar y verificar el release del frontend; desplegar el ZIP aprobado con
   assets versionados.
8. Hacer smoke read-only de login, permisos, reportes y feed ICS. No crear datos
   ficticios en producción.

### Rollback F2

- Interfaz: restaurar el ZIP y manifiesto anteriores.
- Edge Function: restaurar la versión anterior de `crm-agenda-ics`.
- Base de datos: la migración es aditiva y adquiere historia; no eliminar columnas
  ni filas para retroceder. El frontend anterior continúa funcionando.
- Incidente de reportes: revocar temporalmente `EXECUTE` de las RPC de métricas a
  `authenticated` mientras se vuelve al frontend anterior.
- Incidente operativo: revocar las RPC de reuniones y conservar las filas para
  auditoría; nunca borrar o reescribir cierres.

### Evidencia local requerida

- `npm run typecheck`
- `npm run lint`
- `npm run test:run`
- `npm run build`
- PostgreSQL 16 aislado con
  `supabase/scripts/test-inteligencia-comercial-reuniones.sql`
- Resultado SQL esperado:
  `OK: inteligencia comercial, detalle por vendedor, metas y reuniones auditables`

### Liberación ejecutada el 2026-08-06

- Migración local `20260805180000_crm_inteligencia_comercial_reuniones.sql` →
  versión remota `20260805180000`.
- Migración local `20260805213000_crm_objetivos_por_vendedor.sql` → versión
  remota `20260805211322` por la reescritura de timestamp al fusionar la rama.
- Migración local `20260805200000_crm_conversion_vendedor_detalle.sql` → versión
  remota `20260806160412` por `apply_migration`. Los archivos locales conservan
  sus nombres originales; no usar `db push --include-all` para reconciliar este
  drift deliberado.
- `crm-agenda-ics` en producción ya era byte a byte igual a la fuente local;
  no se redesplegó.
- RPC de conversiones verificada con 16 responsables; `anon` sin `EXECUTE` y
  `authenticated` con invocación gateada internamente por Gerencia/lector global.
- Frontend final: release `crm-20260806T162840Z-a0ba40c3cad5`, SHA-256
  `e3c411e10cb45e15069f6c64da50d8e09004bc135f08f799a49ccfb5ae542245`.
  Producción sirve `assets/index-Dj0Pmxpc.js`, `assets/index-l5NnIPoE.css` y
  `assets/gerencia-ByB9meds.js`, idénticos byte a byte al artefacto verificado.
  El ZIP devuelve 404 tanto en CRM como en el portal.
- Validación local final: 99 archivos de prueba, 1,208 pruebas aprobadas, lint
  sin advertencias, tipos y build correctos.

### Ajuste de período liberado el 2026-08-06

- El período inicial de todas las vistas de Gerencia quedó alineado al mes
  calendario en curso de `America/Lima`, desde el día 1 hasta hoy.
- Frontend: release `crm-20260806T165331Z-a0ba40c3cad5`, SHA-256
  `2d735bd24a7294c5a353a07a0440c385ca26157beecffa5450d39685d1b02cfc`.
  Producción sirve `assets/index-DFpzfCBC.js`, `assets/index-l5NnIPoE.css` y
  `assets/gerencia-CkkduXi1.js`; el HTML y los archivos comparables coinciden
  con el artefacto verificado. El CDN reoptimiza los cuatro PNG de marca sin
  alterar sus dimensiones ni su apariencia visual.
- Controles públicos: `.htaccess` y `.env` devuelven 403; manifiestos de npm y
  el ZIP del release no están expuestos.
- Validación local final: 99 archivos de prueba, 1,212 pruebas aprobadas, lint
  sin advertencias, tipos y build correctos.

### Ajustes de robustez liberados el 2026-08-06

Quedaron liberados en producción:

- filtro compartido y persistente para todas las vistas de Gerencia, con MTD de
  Lima, cambio automático de día y validación previa de límites;
- estados de carga, error y ausencia separados de un cero real;
- ranking/tendencia/detalle con contrato RPC completo o indisponible;
- meta inicial 15% coherente en vendedor, supervisor, resumen y altas nuevas;
- rollback visual del editor de metas después de un rechazo del servidor;
- asistencia basada en `pct_asistencia` y estados vacíos parciales del resumen;
- arnés SQL ampliado a las migraciones de detalle y metas individuales, con
  pruebas de ACL, RLS, atomicidad, PEN/USD y acceso anónimo rechazado.

Evidencia final: 103 archivos de prueba, 1,256 pruebas aprobadas, lint sin
advertencias, tipos y build correctos. PostgreSQL 16.14 aislado aprobó el arnés
con `ON_ERROR_STOP`.

- Frontend: release `crm-20260806T183526Z-a0ba40c3cad5`, SHA-256
  `393e00e7e5a80380e4f393d2b5e5e8ab80884e8db9b23335c4516f49bb31cf15`.
- Producción sirvió `assets/index-Bw5QuEp_.js`,
  `assets/index-Ccac-TBa.css` y `assets/gerencia-W_Bq1wls.js`, idénticos al
  artefacto. Este release fue reemplazado el mismo día por el Centro de alertas.
- Las migraciones ya estaban presentes en producción con sus equivalencias
  remotas documentadas; no se volvieron a aplicar. La rama temporal de
  validación se eliminó después de comprobar el estado de producción.

### Centro de alertas gerenciales liberado el 2026-08-06 (reemplazado)

> Registro histórico del release `crm-20260806T185215Z-a0ba40c3cad5`. La
> propuesta se retiró el mismo día porque concentraba señales operativas en
> Gerencia y funcionaba como otro reporte, no como una bandeja de trabajo.

- La ruta `#/alertas` es exclusiva de Gerencia y también se abre desde la
  campana de la barra superior.
- Siempre representa el estado del mes en curso de Lima, desde el día 1 hasta
  hoy. No hereda un rango histórico personalizado porque su propósito es
  priorizar la operación actual.
- Señala tareas vencidas, leads sin próxima acción, inasistencias a reuniones,
  conversión individual por debajo de la meta y caída global de conversión
  contra el corte comparable del mes anterior.
- La comparación anterior usa desde el día 1 hasta el mismo ordinal disponible
  del mes previo; por ejemplo, un día 31 se recorta al último día real de ese
  mes.
- Las señales se ordenan por criticidad y permiten filtrar por prioridad, tipo,
  responsable o equipo. La tabla de escritorio tiene una variante compacta
  para móvil y cada señal enlaza a su módulo gerencial pertinente.
- Cada fuente falla cerrada. Un error parcial muestra «Información incompleta»
  y nunca convierte una consulta ausente en cero ni en supuesto cumplimiento.
- El navegador recibe métricas agregadas, responsables y equipos; esta primera
  versión no descarga leads, tareas ni actividades sensibles y no expone un
  listado de casos individuales.
- No hubo cambios de esquema ni una nueva migración: el centro deriva sus
  señales de las RPC agregadas que ya estaban protegidas y desplegadas.
- Frontend final: release `crm-20260806T185215Z-a0ba40c3cad5`, SHA-256
  `3c53cc5c7410ffac917d3dbdd242705205461433c8c6eed335b4b25ed14e5071`.
- Producción sirve `assets/index-CJOddw0W.js`,
  `assets/index-C8JOBtw4.css`, `assets/gerencia-D6qAxCGB.js` y
  `assets/gerencia-CNWpqr_q.js`; los cinco hashes, incluido `index.html`,
  coinciden byte a byte con el artefacto local.
- El ZIP devuelve 404 en CRM y en el portal; el manifiesto y `package.json`
  devuelven 404, y `.htaccess` y `.env` devuelven 403.
- Validación final: 105 archivos de prueba, 1,277 pruebas aprobadas, lint sin
  advertencias, tipos y build correctos.

### Bandeja de pendientes por responsabilidad

La corrección reemplaza el centro anterior por condiciones activas que cada rol
puede resolver o escalar:

| Rol | Qué recibe | Cuándo aparece | Destino |
| --- | --- | --- | --- |
| Vendedor | Tarea propia vencida, lead propio sin responder o sin próxima acción | Desde que requiere su intervención; máximo una señal por lead | Caso exacto en Agenda o Cartera |
| Supervisor | Lead de su bandeja por repartir, tarea del equipo vencida por 24 h, cola crítica de al menos un día o vendedor con varios leads sin próxima acción | Solo al superar el umbral de escalamiento | Caso exacto o vista de Equipo |
| Gerencia | Conversión individual materialmente bajo meta y caída global contra el corte comparable anterior | Desde el día 10 y con muestra mínima; la comparación global exige 30 leads por cohorte | Ranking o Conversión |

- `#/alertas` deja de ser exclusiva de Gerencia. La campana es el único acceso
  canónico; no se duplica en el menú lateral.
- Directorio y Coordinador no reciben una bandeja hasta que exista una
  responsabilidad concreta y datos adecuados para esos roles.
- Son pendientes derivados del estado actual, no notificaciones persistentes:
  no existe leído/no leído. Al resolver la condición de origen, la señal
  desaparece en la siguiente sincronización.
- Vendedor y Supervisor derivan sus señales de leads, actividades y tareas ya
  recortados por el ámbito/RLS del store. Gerencia conserva únicamente las RPC
  agregadas de conversión; no descarga casos operativos globales.
- Cada fecha o fuente inválida falla cerrada. No se inventa urgencia a partir de
  timestamps corruptos, respuestas incompletas ni metas que no cargaron.
- Las inasistencias no generan una señal mientras el agregado disponible no
  pueda distinguir una cita ya reprogramada. El capital continúa en sus paneles
  de meta y producción: una desviación de monto no identifica por sí sola una
  acción operativa ni un responsable inequívoco.
- No se agregó tabla de notificaciones, Realtime, RPC ni migración. Si luego se
  requiere historial, acuse o escalamiento con SLA, deberá diseñarse como un
  sistema persistente aparte de esta bandeja de condiciones activas.
