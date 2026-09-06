# F0 — Inventario de pantallas y roles

Inventario documental del frontend actual, preparado después de consultar CodeGraph. **No es una auditoría de permisos/RLS ni acredita visualmente todos los roles.** En esta ejecución se inspeccionó Gerencia demo. Los otros roles se registran por sus reglas actuales y quedan para validación por rol.

Fuentes: `app/src/lib/router.ts`, `app/src/lib/vistas.ts`, `app/src/lib/roles.ts` y `app/src/components/app/sidebar.tsx`. Se conserva la política existente, incluidas las excepciones de autoridad de Portal. El estado de la llave operativa de leads depende de la sesión/entorno; no se deduce producción desde la demo.

V = Analista (`vendedor`); S = Supervisor; G = Gerencia; D = Directorio; C = Coordinador. Directorio permanece en consulta. Un destino visible no implica que todas sus acciones se permitan.

| # | Pantalla / ruta | Roles de aplicación previstos por fuente | Alcance / condición / evidencia |
| --- | --- | --- | --- |
| 1 | Hoy / Resumen · `hoy` | V, S, G, D | G conserva acceso; los demás dependen de la llave de leads. G muestra Resumen; otras variantes no revisadas visualmente en esta ejecución. |
| 2 | Pendientes / campana · `alertas` | V, S, G | G conserva acceso; V/S dependen de la llave. No se repite como destino en el menú. |
| 3 | Conversiones · `conversiones` | G | Exclusivo Gerencia. Capturas escritorio/móvil y comparación. |
| 4 | Ranking · `ranking-vendedores` | G | Exclusivo Gerencia. Capital total y detalle/regreso comprobados. |
| 5 | Citas · `reuniones` | G | Exclusivo Gerencia; se conserva evidencia histórica, sin ensayo nuevo del módulo completo. |
| 6 | Metas · `metas` | G | Reporte distinto de la edición de configuración. |
| 7 | Rendimiento · `rendimiento` | G | En metadatos históricos figura Equipo; UI actual muestra Rendimiento. Conservar destino y diferenciar de Gestión de equipo. |
| 8 | Pipeline · `pipeline` | V, S, G, D | Mundo leads y capacidad vigente; cerrado para C. |
| 9 | Leads · `cartera` | V, S, G, D | Mundo leads. No confundir esta ruta con Cartera de clientes/contratos. |
| 10 | Agenda · `agenda` | V, S, G, D | Mundo leads y ámbito de cada rol. |
| 11 | Cartera / Mi cartera · `mi-cartera` | V, S, G, D | Clientes y contratos agrupados; detalle y búsqueda auditados en G. Sustituye rutas retiradas clientes/contratos. |
| 12 | Repartir leads · `repartir` | G, C | Capacidad repartirCola. Es el destino base del coordinador. |
| 13 | Base para gestión · `rescate` | S, G | Capacidad repartirLeads y llave operativa de leads. |
| 14 | Carpeta de gestión · `rescate-carpeta` | S, G | Ruta interna; no duplica un ítem de menú. Condición de rescate. |
| 15 | Derivar leads · `derivaciones` | S | Capacidad verDerivacionesEquipo. No se añade a Gerencia por analogía. |
| 16 | Gestión de equipo · `equipo` | S, G, D | Capacidad verGestionEquipo; Directorio no escribe. |
| 17 | Configuración · `config` | V, G, D | V dispone de configuración propia; no se infiere edición de configuración global. S/C no tienen esta capacidad. |
| 18 | Usuarios y roles · `config-usuarios` | G, D; excepción Portal | G/D pueden alcanzar la vista; sus operaciones aplican autoridad adicional. Superadmin Portal con otro rol tiene una ruta de gobierno restringida. No revisado visualmente aquí. |
| 19 | Productos · `config-productos` | G, D | Vista interna de configuración. Directorio permanece en lectura. |
| 20 | Metas / edición · `config-metas` | G, D | No confundir con reporte Metas. G-F4 previo es antecedente, no revalidación en F0. |
| 21 | SLA · `config-sla` | G, D | Vista interna de configuración; operaciones conservan su autoridad actual. |

La excepción `rolPortal=superadmin` para un rol CRM distinto de Gerencia restringe la navegación a `config-usuarios`; no amplía el acceso comercial del rol. Gerencia + Superadmin conserva su navegación de Gerencia. Se registra porque existe en el código, sin modificarla ni probar autenticaciones reales.

## Superficies que no son rutas independientes

- Nuevo lead: diálogo global auditado en Gerencia demo; cuatro requisitos observados, sin envío. Visibilidad/acciones de otros roles pendientes de revisión visual específica.
- Detalle de Ranking: mismo responsable/mes/pestaña, con regreso; comprobado en escritorio y móvil.
- Comparación de analistas: sección ampliable de reportes, con base mensual explícita.
- Ficha de cliente: diálogo de consulta desde Cartera, con búsqueda conservada; retorno de foco pendiente de corrección.
- Ayuda, búsqueda global, avisos, menús, formularios de clientes/contratos y paneles secundarios: inventariar estados y prioridad por tarea en UX1–UX5, no asumirlos auditados por aparecer en la navegación.

## Priorización provisional

| Prioridad | Superficie | Razón disponible | Falta confirmar |
| --- | --- | --- | --- |
| A | Resumen | Miguel pidió lectura comercial con más gráficos. | Frecuencia y prueba de comprensión. |
| A | Conversiones | Rechazo visual explícito; alta carga de lectura. | Tareas frecuentes y jerarquía final. |
| B | Ranking | Piloto anterior y navegación reutilizable. | Usos más frecuentes por supervisión. |
| C | Cartera | Tabla/lista y acceso a trabajo comercial. | Acción principal real por rol. |
| C | Nuevo lead | Formulario accesible globalmente en G; problema móvil observado. | Frecuencia de altas y prueba con teclado real. |

Estas son cinco superficies elegidas para la muestra. Se pidió a Miguel confirmar las cinco más usadas y sus tres tareas recurrentes; no hay respuesta registrada todavía. Se reemplazará o ampliará la muestra si la evidencia de uso lo justifica.
