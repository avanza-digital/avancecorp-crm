# Configuración operativa del CRM — plan y estado de producción

> Fecha: 2026-08-07
> Alcance: Usuarios y jerarquía, Productos de inversión, Metas y Tiempos de atención
> Estado actualizado 2026-08-08: cuatro migraciones aplicadas, Edge
> `crm-usuarios` v1 activa y CRM + Portal desplegados. El cierre integral sigue
> abierto únicamente porque todavía no existe una condición comercial no legacy
> publicada; el bridge se mantiene habilitado para no interrumpir las altas.

## Objetivo

Convertir las cuatro tarjetas de Configuración en módulos operativos completos,
sin caminos de escritura paralelos ni valores de negocio duplicados entre SQL y
TypeScript. Gerencia administra las personas y la jerarquía del CRM; una cuenta
global `superadmin`, designada por el propietario, conserva en exclusiva la
asignación y el cambio de roles.

## Estado ejecutado al 2026-08-07

| Dominio | Implementación local | Evidencia dedicada | Estado |
|---|---|---|---|
| Usuarios y jerarquía | Migración `20260807203740`, Edge Function `crm-usuarios`, capa de datos y pantalla operativa | `test-usuarios-jerarquia.sql` → `USUARIOS_JERARQUIA_TX_OK`; Edge v1 `ACTIVE`, `verify_jwt=true`, OPTIONS 204 y POST sin sesión 401 | ✅ Producción |
| Productos de inversión | Migraciones `20260807203751` + `20260807235933`, catálogo versionado, selector y wrappers contractuales en CRM/Portal | `test-productos-inversion.sql` → `PRODUCTOS_INVERSION_TX_OK`; 325 snapshots legacy verificados | ⚠️ Producción; falta publicar el primer producto y cerrar bridge |
| Metas | Primera mitad de la migración `20260807203757`, consumidores y pantalla versionada | `test-metas-versionadas.sql` → `METAS_VERSIONADAS_TX_OK` | ✅ Producción |
| SLA | Segunda mitad de la migración `20260807203757`, snapshots, métricas, alertas y pantalla versionada | `test-sla-versionado.sql` → `SLA_VERSIONADO_TX_OK` | ✅ Producción |
| Configuración y demo | Cuatro rutas reales, riel de estado por permiso y fixtures demo estrictos de solo lectura | Gate oficial: lint, typecheck, coverage, 118 archivos / 1,404 pruebas y build | ✅ Producción |

Los tokens anteriores corresponden a oráculos transaccionales con rollback. La
aplicación remota fue un paso separado, autorizado por Miguel después de mostrar
los cuatro archivos SQL. Supabase registró las versiones remotas
`20260808160113`, `20260808160129`, `20260808160137` y `20260808160148`.

El gate local final se ejecutó sobre PostgreSQL 16 desechable creado desde un
clon de esquema de producción: las migraciones `203740 → 203751 → 203757 → 235933`
aplicaron en orden y quedaron verdes `USUARIOS_JERARQUIA_TX_OK`,
`PRODUCTOS_INVERSION_TX_OK`, `METAS_VERSIONADAS_TX_OK`,
`SLA_VERSIONADO_TX_OK` y `METRICAS_DISTRIBUCION_TX_OK`. En el gate de release la
app aprobó 118 archivos / 1,404 pruebas unitarias con cobertura, typecheck, lint
y build. Las Edge Functions aprobaron
10/10 pruebas de Usuarios y 3/3 del importador, además de check y formato. Los
advisors no mostraron errores de seguridad; permanecen advertencias históricas
del esquema base y avisos esperados sobre RPC `SECURITY DEFINER` con autorización
interna. La verificación posterior confirmó objetos, ACL, 325 snapshots legacy y
el bridge abierto en revisión 1.

## Decisión de administración confirmada

- **Gerencia** crea y edita usuarios, activa o desactiva su membresía CRM y
  organiza la jerarquía comercial.
- **Superadmin Portal** solo interviene en la asignación o cambio de roles. No
  obtiene por ello permisos para administrar jerarquía, productos, metas, SLA
  ni la operación comercial.
- Una membresía CRM activa de Vendedor, Supervisor, Coordinador o Directorio no
  amplía esa autoridad: el rol efectivo sigue siendo nulo. Solo una membresía
  activa de Gerencia suma expresamente la operación completa.
- La cuenta superadmin será preparada y administrada manualmente por el
  propietario antes de las pruebas de aceptación. La implementación no debe
  promoverla automáticamente ni depender de su correo.
- Correos, contraseñas y demás credenciales reales no se guardan en el código,
  migraciones, seeds, pruebas ni documentación.

## Fronteras de autorización

| Acción | Gerencia CRM | Superadmin Portal | Directorio | Supervisor/Vendedor |
|---|---:|---:|---:|---:|
| Crear y editar una persona CRM | Sí | No | No | No |
| Activar/desactivar membresía CRM | Sí | No | No | No |
| Organizar jerarquía | Sí | No | No | No |
| Asignar/cambiar `rol_crm` | No | Sí | No | No |
| Administrar productos, metas y SLA | Sí | No, salvo que además sea Gerencia | No | No |
| Consultar configuración | Sí | Solo el directorio mínimo para administrar roles | Sí, solo lectura | Solo lo necesario para operar |

Ninguna autorización depende del correo. Las RPC y Edge Functions comprueban
el rol vivo y el estado activo en cada llamada. El navegador solo refleja esa
decisión para la experiencia de usuario.

## 1. Usuarios y jerarquía

### Modelo y flujo

- Gerencia crea una identidad con rol global neutro `comercial`, sin elegir ni
  cambiar el rol CRM.
- Hasta que Superadmin asigne `rol_crm`, la persona aparece como **Pendiente de
  rol** y no puede entrar al CRM.
- Gerencia puede editar datos permitidos, organizar la jerarquía, enviar una
  recuperación de acceso y activar/desactivar únicamente la membresía CRM.
- Superadmin ve únicamente los datos necesarios para asignar o cambiar
  `rol_crm`; no puede editar los demás datos de la persona ni su jerarquía.
- Desactivar un perfil global del Portal queda fuera de Gerencia.
- Cambios de rol, jerarquía o estado usan control optimista por versión/fecha.
- No se permiten ciclos, supervisores inactivos, subordinados incompatibles ni
  dependencias abandonadas. Toda transferencia necesaria es atómica.
- Nunca se inserta directamente en `auth.users`; Auth Admin vive solo en una
  Edge Function con `service_role` del servidor.

### Evidencia local

- El oráculo transaccional cubre Gerencia, Superadmin, Directorio, Supervisor,
  Vendedor, Coordinador, cliente, inactivo y anónimo; incluye jerarquía,
  transferencia atómica, concurrencia optimista y baja/reactivación.
- Las pruebas enfocadas de `crm-usuarios` cubren autenticación, separación de
  autoridad, CORS exacto, alta pendiente y recuperación sin devolver secretos.
- El flujo está preparado para la aceptación autenticada Gerencia → Superadmin
  → Gerencia, pero no se ejecutó contra producción porque este ciclo continúa
  exclusivamente local.

## 2. Productos de inversión

### Modelo

- `crm.productos_inversion`: identidad estable y archivo lógico.
- `crm.producto_versiones`: revisión comercial; publicada/retirada es inmutable.
- `crm.producto_condiciones`: combinaciones normalizadas de categoría, moneda,
  plazo, modalidad, tipo de interés, capital y tasa de referencia.
- `public.contratos.producto_condicion_id`: referencia histórica con
  `ON DELETE RESTRICT` e índice.

El contrato conserva sus columnas actuales como snapshot legal de lo pactado.
La versión del producto explica el origen comercial. Una versión nueva jamás
reescribe contratos previos.

### Reglas

- Nuevo/Renovación/Upgrade continúa siendo una decisión humana; no se infiere
  por cronología ni diferencia de capital.
- Un alta contractual selecciona una condición publicada/vigente. El servidor
  valida categoría, moneda, plazo, modalidad, interés, capital y rango de tasa.
- Una tasa de referencia no reemplaza la tasa efectiva pactada.
- Archivar impide nuevas selecciones pero conserva toda la historia.
- Un cierre por renovación exige que el contrato destino sea Renovación.
- La migración contiene `crm.cerrar_altas_legacy_productos(p_expected_revision)`,
  cierre irreversible que se ejecutará únicamente cuando exista al menos una
  condición no legacy publicada/vigente y el smoke autenticado pueda seleccionarla.
  Todavía no corresponde invocarlo: producción tiene cero condiciones seleccionables.

### Migración histórica

- No se recategoriza ni corrige automáticamente ningún contrato existente.
- Se crea un origen histórico interno y se vincula cada contrato copiando sus
  términos exactos, incluidas categorías nulas.
- Antes y después se compara cantidad, términos, cronograma y relaciones.

## 3. Metas

### Fuente canónica

- `crm.meta_periodos`: periodo y revisión publicada.
- `crm.metas_vendedor`: vendedor, supervisor snapshot y conversión objetivo.
- `crm.metas_vendedor_detalle`: categoría × moneda con capital y contratos.
- Totales de supervisor y empresa siempre derivados.

La publicación recibe `expected_revision`; una segunda sesión con una revisión
vieja recibe conflicto y debe recargar. Ninguna baja de personal elimina metas
históricas.

### Semántica

- Capital y contratos reales = contratos confirmados, creados dentro del
  periodo y enlazados a un lead CRM; un lead convertido sin contrato no suma en
  esas dos métricas.
- Conversión real = leads convertidos / (convertidos + descartados), usando los
  sellos terminales dentro del periodo. El RPC declara ambas fuentes por
  separado; no presenta la conversión como si proviniera de contratos.
- El contrato expuesto es explícito y estricto:
  `fuentes_reales.capital_y_contratos = 'contratos_confirmados'` y
  `fuentes_reales.conversion = 'leads_resueltos'`; el campo ambiguo anterior no
  forma parte del contrato vigente.
- Pipeline abierto se muestra únicamente como pronóstico.
- PEN y USD tienen objetivos y avances separados; nunca se suman crudos.
- Nuevo/Renovación/Upgrade conserva cantidades y capital por separado.
- La UI permite mes actual, histórico, futuro y copiar el mes anterior.

## 4. Tiempos de atención y SLA

### Fuente canónica

- `crm.sla_politicas`: versión, vigencia, zona horaria y tipo de reloj.
- `crm.sla_politica_etapas`: límites por etapa.
- Cada ciclo, asignación y episodio de etapa conserva política y fecha límite;
  cambiar una política no modifica el cumplimiento histórico.

Se distinguen explícitamente:

- **Primera gestión:** primer intento del asesor, incluso sin respuesta.
- **Contacto efectivo:** conversación o reunión realmente realizada.
- **SLA por etapa:** permanencia máxima en una etapa.
- **Escalamiento de agenda:** retraso de una tarea; no es el mismo SLA.
- **Cadencia y horario legal:** reglas de contacto; no son umbrales de SLA.

Las métricas nuevas usan nombres genéricos (`objetivo_minutos`, `cumplidos`,
`fuera_objetivo`, `pendientes`) y eliminan contratos semánticos como `*_en_24h`
cuando el límite ya es configurable.

La V2 de Distribución quedó saneada: conserva capacidad, asignación y resultados,
pero ya no transporta `sla_en_24h`, umbrales de etapa fijos ni “estancados”
calculados con esa política histórica. `configuracion_sla_fn`,
`metricas_sla_fn` y `estado_sla_leads_fn` son las fuentes canónicas de tiempos.

## Diseño de interfaz

La pantalla implementada es el **panel de gobierno comercial** de Avance Corp,
no una galería de ajustes. Conserva el sistema navy/azul y la tipografía del
CRM. Su firma es un riel de estado, limitado por los permisos del actor, que
muestra personas habilitadas, cantidad/revisión del catálogo, cobertura/revisión
de metas y versión/primera gestión del SLA.

```text
Configuración del CRM                         [Gerencia]
┌ Estado operativo ─────────────────────────────────────┐
│ Usuarios 20 activos · Productos v3 · Metas ago · SLA v2│
└────────────────────────────────────────────────────────┘

┌ Usuarios y jerarquía ┐  ┌ Productos de inversión ┐
│ estado + acción real │  │ revisión + acción real  │
└──────────────────────┘  └─────────────────────────┘
┌ Metas mensuales ─────┐  ┌ Tiempos de atención ───┐
│ periodo + cobertura  │  │ vigencia + umbrales    │
└──────────────────────┘  └─────────────────────────┘
```

- Responsive desde móvil, foco visible y navegación por teclado.
- Estados de carga, vacío, error, conflicto y solo lectura son explícitos.
- Guardar/publicar espera confirmación del servidor antes del mensaje de éxito.
- Directorio ve la misma información sin controles mutables.
- Superadmin puede editar roles sin obtener escritura operativa general.
- En demo, Gerencia y Directorio recorren las cuatro tarjetas con una fotografía
  ficticia validada por los mismos esquemas estrictos; toda mutación se rechaza
  antes de llegar a la API y el E2E exige cero solicitudes a Supabase.

## Estado del orden de entrega

1. ✅ Modelos, restricciones, índices, RLS/RPC y oráculos transaccionales,
   materializados localmente.
2. ✅ Edge Function de usuarios y pruebas de frontera Auth, materializadas
   localmente.
3. ✅ Tipos y capa dedicada de queries/mutations de configuración.
4. ✅ Cuatro rutas y pantallas reales, riel operativo y demo de solo lectura.
5. ✅ Integración local de productos con contratos y de SLA con
   métricas/alertas; el SLA fijo fue retirado del contrato de Distribución.
6. ✅ Consumidores del CRM y del repo hermano `public_html` migrados a los
   wrappers catalogados; Portal publicado con service worker `avance-v107`.
7. ✅ Migraciones, Edge `crm-usuarios`, CRM y Portal desplegados y verificados.
   Miguel pasa el smoke remoto de identidad/alcance; el selector devuelve cero
   por ausencia de producto publicado, no por un fallo de permisos.

## Definición de terminado

- Las cuatro tarjetas abren módulos reales y no contienen estados “próximamente”.
- No hay escritura directa que evite reglas, auditoría o control de concurrencia.
- No hay constantes duplicadas de metas/SLA entre servidor y cliente real.
- Ningún dato histórico cambia al publicar nuevas versiones o desactivar usuarios.
- Reproducción limpia de migraciones, pruebas completas, advisors revisados y
  smoke autenticado por rol.
- No quedan TODO, compatibilidades temporales, scripts obsoletos ni documentación
  que contradiga el comportamiento entregado.

La definición de terminado **aún no se cumple de forma integral**: las cuatro
tarjetas ya son reales y Metas/SLA tienen una sola semántica vigente, pero
Productos conserva una compatibilidad temporal necesaria. No se declara deuda
técnica saldada mientras ese bridge siga habilitado.

## Gate único de cierre

El Portal ya no llama las RPC legacy: Admin y Analista usan exclusivamente los
wrappers públicos catalogados. El despliegue vivo quedó comprobado byte por byte
en los HTML, callers, módulos de Productos y `_helpers.js`; el ZIP, las pruebas y
`CLAUDE.md` no son públicos.

El bridge permanece abierto por un solo motivo: no existe una condición comercial
no legacy publicada. Cerrarlo ahora impediría cualquier alta nueva. El cierre
requiere, en este orden:

1. acordar código/nombre, moneda, categoría, plazo, modalidad, interés, capital y
   rango de tasa del primer producto real;
2. crear el borrador y publicar su versión desde Configuración;
3. repetir el smoke autenticado y confirmar que CRM/Portal reciben la condición;
4. ejecutar una sola vez `crm.cerrar_altas_legacy_productos(1)` y comprobar que
   no puede reabrirse ni crear snapshots legacy nuevos.

Hasta completar esos cuatro pasos, el sistema está desplegado y operativo con
compatibilidad controlada, pero no se declara el cierre integral irreversible.
