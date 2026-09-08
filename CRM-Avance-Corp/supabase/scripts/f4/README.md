# F4 — motor multiempresa y banco de aceptación

Actualizado el 08/09/2026. Candidata completa versionada y probada con datos
sintéticos: **48 funciones (18 adaptadas, 30 nuevas), 11 módulos y siete tablas
nuevas**. **G4 sigue abierto por la comprobación de comisiones/liquidaciones**:
no se identificó su fuente de pagos. El estado exacto está en
[ESTADO-ACEPTACION.md](ESTADO-ACEPTACION.md), con pruebas y límites.
No está aplicada ni encendida en producción.

El desarrollo vive en `/private/tmp/avancecorp-f4-desarrollo`, rama
`codex/f4-cierre`. Se conserva la separación del checkout de Miguel, que tenía
cambios ajenos a F4. El archivo SQL preparado es
`../../migrations/20260907191832_crm_f4_inversiones_base_y_escritores.sql`.
Una vez versionado, no se modifica silenciosamente: una revisión posterior
requiere dejar evidencia de un nuevo artefacto y repetir los gates afectados.

## Contrato de negocio para F5

- Una persona puede invertir varias veces en Avance, Qorilazo o Prodelco sin
  otro lead ni otra identidad. La fuente económica sigue siendo contrato o
  cierre externo: **no se suma dinero desde `crm.inversiones`**.
- El cierre inicial conserva la conversión; una inversión adicional es otra
  fuente de producción, no otro episodio de conversión del lead. Renovaciones
  y upgrades conservan elegibilidad/peso publicados por cliente y mes.
- `inversiones.estado='anulada'` es anulación comercial; el stock se conserva
  según ATR-4. El retiro financiero no se infiere de ese estado.
- Cooperativa: fecha comercial pasada en mes abierto se imputa allí. Mes
  sellado: fecha comercial conservada, imputación al vivo y ajuste trazable.
  No existe un límite nuevo de N días aprobado por este trabajo.
- El responsable actual decide permisos; la atribución histórica del cierre
  permanece. Sin responsable actual no se recupera teléfono por tenencia antigua.
- Cotitularidad neutral registra una procedencia verificada. No crea Auth, lead,
  permiso compartido ni consentimiento. Corrección/fusión siguen F3 y conservan
  el snapshot contractual. El PDF mantiene plantilla, texto, firma y fuentes;
  agregar cotitulares impresos requiere aprobación previa de Miguel.
- Preparar/corregir/confirmar usan clave, hash y revisión. La corrección de datos
  deja acta inmutable; una revisión vieja no confirma cambios no vistos.
- Una vez reclamado Auth, sus datos originales quedan fijos: se recupera la misma
  solicitud, sin adoptar ni borrar otro usuario. Reasignación requiere revisión
  del responsable vigente. `cancelada` es reservado, sin RPC de cancelación.
- Una fuente vinculada no admite borrado destructivo, tampoco por marcar demo.
  La anulación comercial conserva registro y evidencia.

## Dos bancos cerrados y sintéticos

| Selector `F4_BANCO` | Proyecto | API / PostgreSQL |
|---|---|---|
| `desarrollo` (predeterminado) | `avancecorp-f4-bank` | 56321 / 56322 |
| `reconstruccion` | `avancecorp-f4-reconstruccion` | 57321 / 57322 |

`banco-local.mjs` solo acepta estos destinos, sus contenedores exactos y claves
con emisor `supabase-demo`. No admite URL remota. `start.log`, `estado.json`,
fixtures, dumps y tokens son privados en `/private/tmp/avancecorp-f4-*`.
No se publican sus contenidos. Los JSON de `../evidencia-f4` están saneados.

La segunda instalación se reconstruyó desde un volcado de **solo esquema** del
07/09; se crearon usuarios Auth y operaciones ficticias por APIs/RPC reales
ANTES de aplicar F4. Conservó propietarios y ACL, cuatro contratos, dos cierres,
52 cuotas y PEN 8000. [RECONSTRUCCION-Y-RESTAURACION.md](RECONSTRUCCION-Y-RESTAURACION.md)
detalla el orden, las copias y los límites.

## Ensamblado e instalación inicial

Desde la raíz del repositorio:

```sh
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/preparar-fixtures.mjs
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/preparar-operaciones-base.mjs
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/capturar-paridad.mjs antes
node CRM-Avance-Corp/supabase/scripts/f4/generar-migracion.mjs CRM-Avance-Corp/supabase/migrations/20260907191832_crm_f4_inversiones_base_y_escritores.sql
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/aplicar-candidato.mjs
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/capturar-paridad.mjs despues
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/verificar-estructura.mjs
```

Solo en una instalación nueva. `aplicar-candidato` rechaza una base con F4 y
comprueba referencia económica no vacía. Ensamblar no conecta a bases. La
migración compara huellas originales e inventario completo de consumidores;
rechaza deriva, vistas/políticas nuevas y una segunda instalación.
No registra una aplicación productiva ni enciende banderas.

## Oráculos y orden

Los oráculos HTTP que escriben el banco se ejecutan **secuencialmente**. Añaden
fixtures identificadas; no borran ni restauran datos para forzar un PASS.

1. `probar-cooperativas`, `probar-avance-existente`, `probar-concurrencia`,
   `probar-fechas-anulacion`, `probar-conservacion-historia`.
2. `probar-portal-nuevo`, `probar-portal-veto`, `probar-revision-responsable`,
   `probar-revision-controles`, `probar-documento`, `probar-fusion`,
   `probar-identidad-controles`, `probar-reintento-confirmado`.
3. `preparar-edge-portal-local` + `probar-portal-edge`; `preparar-pdf-local` +
   `probar-pdf-real`. Requieren el runtime en la red del banco.
4. `probar-portal-lease` y `probar-revision-lease`: esperan diez minutos reales;
   `probar-pdf-real` espera la reserva de 120 segundos. No alterar reloj/leases.

Todos tienen extensión `.mjs` y están en esta carpeta. Algunas pruebas requieren
F4 ON en el banco; comprobar sus precondiciones. Apagar al terminar. La prueba
de fechas sella julio: no repetirla suponiendo meses sin sello.

Oráculos SQL crean bases nuevas con `copia-sql-local.mjs`, sin mutar el original:

- Históricos: `probar-historicos-censo`, `-lote`, `-concurrencia`, `-identidad`,
  `-mantenimiento`, `-limite`; incluyen el máximo mixto de 100 fuentes.
- `probar-corpus-f2`: copia anterior a F4, corpus y oráculo originales de F2,
  instala candidata íntegra y verifica tratamiento acotado y dos mutantes del inventario.
- `probar-finanzas-integral`: copia anterior a F4 + candidata completa; 13 grupos,
  incluidas ambas carreras sello/alta y mes antiguo abierto.
- `probar-cotitulares-neutrales`, `probar-correccion-solicitud`,
  `probar-permisos-dinamicos`, `probar-multirrol`.
- `inventariar-consumidores`, `verificar-estructura`, `actualizar-tipos-local`
  comprueban catálogo, permisos y tipos. El último incorpora solo los 17 nodos
  distintos entre esquemas antes/después, preservando tipos ajenos a F4.
- `probar-restauracion`: DB y Storage hacia destinos NUEVOS, con F4 OFF.
- `verificar-pdf-interrumpido <UUID>`: readback de ensayo fallido recuperado;
  mantiene su FAIL original y verifica fuente/job/snapshot/objeto/bytes.

Los scripts `instalar-*-local` y `actualizar-funciones-local` documentan iteraciones
anteriores del primer banco. No reconstruyen la candidata final y exigen versiones
previas exactas; **no usarlos en lugar de la instalación íntegra**.

## Verificación y operación

La matriz enlaza resultados del protocolo `.ai/VERIFICATION.md`: cuatro gates
backend, Deno, pruebas SQL/HTTP, frontend completo, build y restore. Claude emitió
CHANGES_REQUESTED; Codex documenta cada aceptación/refutación y su prueba.
No se transforma ese dictamen en PASS ni se atribuye revisión de cambios posteriores.

F2 global se retira **al instalar** F4, incluso apagada: devuelve 55000 antes de
escribir. El reemplazo es censo + lote administrativo máximo 100, con F3 ON y F4
OFF, recenso/hash bajo candados. No ejecutar un backfill global después del cambio
1:N. Recuperación operativa: F4 OFF e historia retenida; no hay DOWN destructivo.
