# Backend SLA-R2 — núcleo, autorización y consumidores

Decisión de arquitectura incorporada por instrucción expresa del usuario, 2026-09-06. Complementa el [plan](../PLAN-FINAL-SLA-2026-09-06.md) y el [contrato externo](CONTRATO-V2.md). [N1](../NUCLEO-IMPLEMENTADO-N1.md) ya tiene implementación local de núcleo, estado y cola; la arquitectura completa sigue siendo el objetivo. Nada de N1 está instalado en producción.

**Necesidad comprobada**

Se necesita **un núcleo operativo de SLA** dentro del dominio SLA. El inventario vivo conserva los núcleos de capital, conversión y citas, más el cálculo agregado `private.metricas_sla_global_core` y el lector `crm.estado_sla_leads_fn`. El primero de estos dos últimos calcula primera gestión y cohortes; el segundo reúne las fotografías versionadas. Sus contratos no proporcionan cobertura de compromisos, seguimiento recurrente ni presupuestos de prórroga. Incorporar esa pregunta operativa no requiere una calculadora financiera ni un servicio externo.

[nucleos-vivos.json](nucleos-vivos.json) guarda el inventario de firmas/retornos/huellas y el código de las tres funciones contrastadas para esta decisión. Esto amplía las diez funciones de recorridos guardadas en `funciones-vivas.json`; no se presenta como un censo completo del servidor.

**Reutilización por responsabilidad**

| Responsabilidad | Fuente existente que gobierna | Uso en SLA-R2 |
|---|---|---|
| Versión vigente y plazos originales | `private.sla_politica_vigente`, políticas, ciclos, asignaciones, hitos y episodios SLA | Leer la versión/snapshot correctos. El anexo añade reglas, no vuelve a calcular ni sobrescribe el pasado. |
| Estado base de cada lead | Proyección actual de `crm.estado_sla_leads_fn` | Extraer su lectura a un proveedor privado compartido, con paridad exacta del contrato v1. V2 consume ese mismo hecho base. |
| Usuario vigente y ámbito | `private.rol_crm`, `private.es_lector_global`, `private.vendedor_ids_visibles` y capacidades vigentes | Una ventana de lectura común resuelve la autorización; los núcleos reciben el ámbito resuelto. |
| Restricción de contacto | `private.persona_vetada` | Reutilizar su decisión canónica. No reinterpretar la identidad ni el veto por pantalla. |
| Ciclo de vida de tareas/reuniones | Writers actuales de creación, cierre, reprogramación y sincronización | Mantener transiciones y validaciones, incorporando orden de locks y confirmación. El núcleo observa sus hechos. |
| Estadísticas de citas | `private.citas_episodios` | Si una salida necesita banderas/estadísticas de citas por vencimiento, obtiene esos hechos del núcleo existente, con el mismo instante y filtro autorizado. El margen SLA no redefine «cita realizada» o «pendiente de cierre». |
| Conversión y capital | `private.conversion_episodios`, `private.capital_episodios` | Siguen gobernando sus cifras. El inventario operativo de pendientes no se deduce del divisor de conversión ni se convierte en otra cuenta de capital. |

Elegir la primera tarea pendiente para cobertura es una regla del núcleo SLA sobre tareas de llamada, WhatsApp y reunión; no es una nueva estadística de citas. Las lecturas operativas de filas se distinguen de los agregados de esa métrica. No se añaden llamadas a otros núcleos solo para aparentar reutilización: cada dependencia debe aportar el hecho cuya semántica necesita el consumidor.

**Capas obligatorias**

| Capa | Objetos/responsabilidad | Contrato y prohibición |
|---|---|---|
| Hechos | Ledgers existentes y cinco tablas aditivas del plan; proveedor privado de estado base | Hechos persistidos con causa y política. La foto de evaluación es una función, no una nueva tabla de métricas derivadas. |
| Núcleo SLA | `private.sla_operacion_leads` y auxiliares privados de hechos y reglas de prórroga | Una evaluación por lead/instante; misma semántica para todos. Sin `auth.uid()` ni decisiones de rol propias; sin grants API. |
| Ventana autorizada | `private.sla_operacion_autorizada` | Resuelve actor, vigencia, rol, visibilidad y reloj una vez. El ámbito solo puede reducirse por filtros del solicitante. |
| Adaptadores de lectura | Estado v1/v2, cola v2, agenda v2 y configuración | Validan entrada y empaquetan/agregan hechos. No fijan umbrales, eligen otro compromiso ni inventan prioridades de negocio. |
| Comandos de negocio | Puertas v2, writers compartidos, recibos y `private.sla_conceder_prorroga` | Autorización y revalidación propias de la mutación bajo locks; el núcleo decide regla/ganancia, el writer aplica y audita atómicamente. Una RPC de lectura nunca concede ajustes. |
| Interfaz | Hoy, Pipeline, ficha, agenda, campana y supervisión | Validar contrato, mostrar y formatear. No recalcular si corresponde cobertura/prórroga ni contar trabajo global desde páginas descargadas. |

No se exige una función monolítica. Un auxiliar es parte del núcleo cuando tiene una única responsabilidad, entradas/salida declaradas y llamadores inventariados, y sus reglas no se repiten en RPC o componentes.

**Contrato interno que debe cerrar SLA-0**

- `private.sla_hechos_actuales(p_lead_ids uuid[], p_global boolean, p_visibles uuid[])`: proveedor compartido de los hechos ya reunidos por v1, más identidad de episodio y referencias necesarias para operar. No contiene umbrales nuevos. La proyección v1 conserva exactamente filtros, ausencia de filas sin foto y todas sus columnas; el núcleo operativo distingue un lead autorizado sin foto del sujeto fuera de ámbito. No se cambian los permisos de v1 para conseguir paridad.
- `private.sla_operacion_leads(p_lead_ids uuid[], p_global boolean, p_visibles uuid[], p_ahora timestamptz)`: devuelve filas-hecho equivalentes a `Estado` del contrato, con motivos, elegibilidad operativa y prioridad dominante. IDs null significa el ámbito completo, permitido solo por llamadores privados; array vacío significa ningún lead. Nunca inferir global por recibir un array vacío. Exige ámbito y reloj explícitos y filtra ese ámbito antes de recorrer tareas/actividades.
- `private.sla_operacion_autorizada(p_lead_ids uuid[], p_incluir_operacion boolean)`: única ventana del dominio para los lectores. Resuelve parámetros de autoridad y un instante. Para v1 invoca el proveedor base; para v2 invoca el núcleo operativo, que consume ese mismo proveedor. No hace dos lecturas independientes del hecho base. Los adaptadores públicos no permiten que el navegador elija `p_global`, `p_visibles`, `p_ahora` ni desactive los gates. Los límites de 200 IDs se validan en el adaptador de estado v2, no limitan el cálculo privado de toda la cola.
- La fila interna añade a `Estado` dos decisiones: `accion_atencion` y `accion_supervision`. Cada una tiene los campos de acción del contrato de cola (bucket, severidad, prioridad, referencia y tarea dominante), o es null si no aplica. El núcleo resuelve ambas decisiones sin inferir roles; la ventana selecciona la perspectiva permitida por las capacidades del actor. La cola únicamente proyecta y ordena esos campos y cuenta hechos autorizados. El contrato público de estado no incorpora campos extra que sus validadores desconozcan.
- `private.sla_conceder_prorroga` es el writer de la misma familia, no otra calculadora. Después de obtener los locks y de verificar el mismo episodio antes/después del avance, consume la regla canónica de elegibilidad, presupuesto y ganancia del núcleo. El helper de regla puede extraerse para uso común; ninguna RPC reproduce la fórmula. Se conserva el orden de locks del plan y se revalida el modo al admitir el ajuste.

La autorización única de lectura no elimina las revalidaciones transaccionales de escritura. Reservar un recibo no reemplaza las reglas de acceso o estado de la tarea. Publicación y cambio de modo reutilizan las capacidades existentes de configuración y tienen los checks específicos del contrato, sin crear roles nuevos.

La agenda paginada usa una proyección de hechos de tarea de la misma familia. El paginado se aplica después de fijar el universo autorizado y los totales; no obliga a recalcular el SLA completo por cada fila de agenda. Las tareas administrativas permanecen accesibles aunque no concedan cobertura.

**Gobernanza y verificación**

1. Fichar núcleo, auxiliares, ventana, comandos y consumidores en la memoria y el manifiesto SLA-0. Una función nueva tiene dominio rector y motivo; no queda como puerta aislada de pantalla.
2. Registrar las declaraciones y huellas afectadas según los controles actuales. El proyecto ya tiene censo de contadores crudos, exenciones selladas, tope que solo baja y `gate:analitica`. No elevar topes, deshabilitar censos ni renovar huellas indiscriminadamente para hacer pasar una migración. Si un cambio cae en el censo, resolver su clasificación y la dependencia del núcleo antes de cerrar SLA-2.
3. La extracción del proveedor base debe conservar payload v1 y autoridad por rol, probados antes/después en la misma foto. Los núcleos ajenos de capital/conversión/citas conservan definiciones, propietarios, ACL y resultados salvo ampliación expresamente justificada en un cambio futuro.
4. Para v2, estado, cola y totales deben concordar por lead/motivo al mismo instante. Las fachadas y pantallas no leen tablas crudas para rehacer cobertura, reprogramaciones, techo o prioridad.
5. Un mutante del núcleo, aplicado solo en el banco, debe romper los tests de todos los consumidores de esa decisión. Añadir el control de dependencias de SLA a los checks de arquitectura existentes y revisar reglas duplicadas en frontend. No marcar como «dependiente del núcleo» una RPC que lo llama pero descarta su resultado y recalcula después.
6. Modo demo usa fixtures canónicos de respuesta del backend y los mismos presentadores/validadores. Los contraejemplos de `verificar_plan.py` son evidencia de auditoría, nunca una segunda implementación que la aplicación pueda importar.

El trabajo necesario adicional es este núcleo operativo y su integración bajo las reglas existentes. No se propone una calculadora visible adicional ni otro núcleo de capital, conversión o citas para resolver el SLA.
