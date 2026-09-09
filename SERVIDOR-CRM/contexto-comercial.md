# SERVIDOR CRM — contexto comercial y leyenda del mapa

Fecha: 2026-09-06 (Lima). Lectura documental del vault, sin modificar código ni servidor. Este documento distingue el estado que las notas declaran del estado que una comprobación nueva de Supabase pueda confirmar. No contiene datos personales ni credenciales.

## Cómo leer la evidencia

- **Documentado en producción:** una nota registra publicación y comprobación. Su fecha importa; no sustituye la lectura actual del servidor.
- **Instalado, apagado:** el código existe en producción, pero su interruptor conserva el comportamiento anterior.
- **En observación:** mide qué pasaría con la regla nueva sin impedir la operación actual.
- **Plan / pendiente:** diseño aprobado o propuesto que todavía no opera. Debe dibujarse con contorno discontinuo.
- **Histórico:** explica un problema anterior; una nota posterior puede haberlo resuelto. No presentarlo como fallo actual.

El punto de entrada real del vault es `Inicio.md`; `Bienvenido.md` no existe. La instrucción vigente de Git es Main → `avancecorp/main`; las referencias a `tronco` de las notas son históricas.

## Glosario para una persona comercial

| Lo que puede aparecer en el diagrama | Explicación comercial |
|---|---|
| Servidor / backend | La oficina central que guarda información, aplica permisos y decide las reglas del CRM. |
| Supabase | La plataforma que reúne la base de datos, los accesos, los archivos y los servicios automáticos. |
| Base de datos / PostgreSQL | El archivo estructurado del negocio: personas, contratos, gestiones, pagos e historial. |
| Tabla | Una lista de un solo tipo de información; por ejemplo, contratos o tareas. |
| Esquema `crm` | El área de trabajo comercial: prospectos, equipo, agenda, cierres y configuración. |
| Esquema `public` | El área histórica compartida con el Portal: perfiles, contratos, cuotas y documentos. El nombre no significa que cualquiera pueda ver esos datos. |
| Esquema `private` | La sala de reglas internas. Contiene calculadoras, permisos y controles que las pantallas utilizan por las puertas autorizadas. |
| Auth | Comprueba quién inicia sesión. Identificar a una persona no determina por sí solo qué puede hacer. |
| RLS / permisos por fila | El control que limita qué registros puede ver o modificar cada usuario según su ámbito. |
| RPC / función SQL | Una operación de negocio que la pantalla encarga al servidor: registrar contrato, consultar cartera o calcular resultados. |
| Edge Function | Un servicio que coordina pasos fuera de la base: crear accesos, generar PDF, enviar avisos o importar prospectos. |
| Núcleo | El lugar único donde se define un cálculo o una regla. Evita que cada pantalla invente su propia cuenta. |
| Ventana autorizada | La puerta que comprueba al usuario y su ámbito antes de solicitar datos al núcleo. |
| Episodio / fila-hecho | Un hecho concreto que cuenta: una llegada, una venta, una renovación o una cita. Conserva cuándo ocurrió y a quién corresponde. |
| Lead / prospecto | La oportunidad que se está atendiendo comercialmente. No equivale a un contrato ni a una cuenta del Portal. |
| Inversionista | La persona real que puede tener varias inversiones. La identidad neutral que la reúne todavía está preparada y apagada según el checkpoint más reciente. |
| Perfil del Portal | La ficha asociada al acceso del cliente a Avance. No debe confundirse con toda la relación comercial del grupo. |
| Contrato Avance | Una inversión legal/económica en Avance con condiciones y cronograma propios. |
| Cierre externo | El registro comercial de una inversión en Qorilazo o Prodelco. No es un contrato Avance. |
| Renovación | Al vencer un contrato, se crea otro enlazado al anterior. Se distingue capital que continúa de dinero adicional. |
| Upgrade / aumento | Una nueva inversión que amplía una línea o la relación del cliente. Su atribución puede seguir reglas de cadena. |
| Responsable de cartera o relación | Quien atiende actualmente al cliente. No necesariamente recibe el reconocimiento de todas sus ventas. |
| Analista de la venta | A quien se acredita una operación concreta. Es distinto de quien digitó el registro. |
| Pipeline | Dinero esperado en oportunidades todavía no cerradas. Se separa del capital real. |
| Capital del período | El dinero de los hechos comerciales que corresponden al período consultado. |
| AUM / capital vigente | El capital que sigue gestionándose en este momento. Responde una pregunta diferente de cuánto se vendió este mes. |
| Cohorte | El grupo de prospectos que llegó en un mismo período, aunque cierre después. |
| Índice para la meta mensual | Una medida ponderada para metas; puede incluir aportes distintos según el origen o tipo de operación. No equivale al porcentaje de prospectos que cerró. |
| Ledger / bitácora | Un libro de hechos que conserva el historial sin reemplazar lo anterior. |
| Auditoría | Registro de quién cambió qué y cuándo, para poder explicar y revisar una operación. |
| Snapshot / foto sellada | El resultado guardado de un momento o mes cerrado. Una consulta actual puede cambiar; esa foto se conserva. |
| Idempotencia | Si se repite el mismo envío por un corte o un doble clic, se recupera la misma operación en lugar de crear otra. |
| SLA | El plazo comprometido para atender o avanzar un prospecto. No es la cita ni el porcentaje de conversión. |
| Cron / tarea programada | Un reloj del servidor que ejecuta una acción sin que alguien abra la pantalla. |
| Storage | El almacén de archivos, como los PDF de contratos. Guardar el contrato y generar su PDF son pasos relacionados pero diferentes. |
| Bandera / modo | Un interruptor de activación. Que exista una función no demuestra que ya esté funcionando para el usuario. |

Idioma visible: usar **analista**. El valor técnico heredado `vendedor` y los campos `asesor_*` permanecen por compatibilidad; no representan automáticamente otra clase de persona.

## Ocho bifurcaciones que el mapa debe distinguir

| # | Separación que hay que mostrar | Para qué le sirve a negocio | Estado y cautela |
|---|---|---|---|
| 1 | **CRM ↔ Portal**, ambos sobre Supabase; `crm` ↔ `public`, con reglas internas en `private` | Permite ver dos entradas al mismo negocio. El CRM gestiona captación y postventa; el Portal atiende inversión, contratos y pagos. | Operativos. Sus roles tienen propósitos diferentes. P-055 declara unificación de capacidades y revocación en producción desde 30/08; no representar el problema de permisos del 29/08 como pendiente. |
| 2 | **Captación de prospecto → inversión Avance / inversión en cooperativa** | Un cierre Avance lleva a perfil/contrato/cuotas; Qorilazo y Prodelco siguen el registro de cierre externo. Ayuda a localizar por qué dos inversiones tienen recorridos distintos. | Ambos cierres existen. La identidad neutral que los une está instalada pero apagada; el modelo objetivo no debe dibujarse como conexión activa universal. |
| 3 | **Seguimiento de lead ↔ postventa del cliente** | Una llamada para captar y una llamada para renovar comparten Hoy/Agenda, pero no deben alterar el mismo historial ni el SLA de captación. | Postventa y su historial propios están implementados. En la rama de identidad activada, el retorno por formulario necesita lead vivo o nota+tarea de cartera; D-20 figura ensayado, no productivo en el checkpoint. |
| 4 | **Nueva inversión / renovación / upgrade** y **responsable de relación / analista de venta / quien registra** | Distingue dinero nuevo del que continúa, quién atiende de quién recibe atribución y quién solo digitó. Evita “arreglar” rankings que responden preguntas distintas. | ATR-1/ATR-3 documentados en producción. ATR-2 de capital heredado por renovación de upgrade está preparado para después del sello (11–12/09). El Directorio del Portal conserva ranking por asesor actual; el CRM usa atribución de ventas/cadena deliberadamente. |
| 5 | **Capital del período / capital vigente / pipeline**, con carriles separados para **PEN / USD** y **Avance / cooperativas** | Permite entender por qué “vendimos este mes” difiere de “capital que gestionamos”. Una oportunidad estimada no es dinero recibido. | Capital centralizado en producción desde 30/08. Cartera Avance excluye cooperativas de su resumen. Algunas vistas de ranking convierten moneda bajo regla explícita; no sumar PEN+USD sin ella. |
| 6 | **Conversión de la cohorte / índice mensual ponderado / citas / cumplimiento SLA**; después **lectura viva / foto del mes cerrado** | Cada indicador tiene población, fecha y finalidad propias. Una cita no es un prospecto; dos contratos no siempre son dos conversiones. Una lectura actual no reemplaza el resultado sellado de un mes. | Núcleos de conversión y citas en producción. El rótulo de conversión por analista tiene corrección frontend pendiente de publicación el 06/09. Primer sello automático previsto para 10/09; agosto parcial. Confirmar en vivo la ponderación de renovación, cuya nota del 04/09 aún la marcaba pendiente. |
| 7 | **Condiciones legacy actuales / catálogo versionado preparado** y **tasa recibida / política observada / excepción aprobada futura** | Muestra dónde se fija hoy la rentabilidad y qué parte del control de margen falta activar. Tener catálogo no significa vender ya con productos publicados. | Nota 06/09: cero productos publicados, altas por puente legacy. Rentabilidad R1+R2 productivos en observación; R3 interfaz y R4 obligación de política pendientes. Los siete CRUD gemelos antiguos se cerraron en F5.d: no confundirlos con selectores vivos. |
| 8 | **Funcionamiento actual / preparado apagado / propuesto**, con tres ramas futuras explícitas | Evita creer que un diseño ya protege la operación. Permite revisar activaciones y no solo detectar nombres duplicados. | Identidad multiempresa: instalada, banderas `false`. Rentabilidad: observa, todavía no impone. SLA recurrente/compromisos/prórrogas: solo diseño SLA-R2; conservar aparte el SLA existente de primera gestión y etapas. |

No todas estas bifurcaciones son defectos. Las separaciones por empresa, moneda, permiso, tipo de inversión y pregunta de negocio son deliberadas. Una divergencia requiere demostrar que dos rutas responden la **misma** pregunta y dan reglas incompatibles.

## Rótulos comerciales para familias de funciones

Estos nombres son localizadores documentales para el mapa técnico; contrastar sus firmas y estado con Supabase antes de afirmar que todas son las llamadas vigentes.

| Familia o función | Rótulo principal recomendado | Explicación breve que puede acompañar el nodo |
|---|---|---|
| `crm.mi_acceso_fn`, `private.rol_crm`, helpers de capacidades | **Comprueba acceso y alcance** | Decide si la persona está activa y qué trabajo o información le corresponde. |
| `private.es_analista_vigente`, `private.puede_registrar_ventas` | **Valida quién puede registrar una venta** | Aplica la regla común entre CRM y Portal; la autoridad de venta no equivale a poder ver toda la banca. |
| `crm-importar-leads`, puertas de importación | **Recibe solicitudes de información** | Lleva las entradas de formularios/hoja al trabajo del equipo, con trazabilidad. |
| `crm-convertir-lead`, reserva y efectos de conversión | **Convierte el prospecto en cliente Avance** | Coordina identidad/acceso y cierre sin duplicar la misma operación al reintentar. |
| Conversión cooperativa / `crm.cierres_externos` | **Registra inversión en Qorilazo o Prodelco** | Guarda el cierre comercial y su atribución en el carril de cooperativas. |
| `crear_contrato_con_cuenta_pdf_v2`, `public.crear_contrato` | **Registra la inversión Avance** | Crea el contrato y su cronograma mediante las puertas autorizadas. |
| `actualizar_contrato_con_cuenta_pdf_v3`, `public.actualizar_contrato` | **Corrige el contrato permitido** | Aplica límites de edición y mantiene coherencia con cuotas y documento. |
| `crm-contrato-pdf-v2`, `contrato_pdf_*` | **Prepara y entrega el documento del contrato** | Genera/almacena el PDF asociado. Un fallo de PDF no significa automáticamente que el contrato no exista. |
| `crm.operaciones_cartera` | **Conserva renovaciones y aumentos** | Enlaza contratos y conserva el desglose entre capital renovado y adicional. |
| `private.analista_atribuido_cadena`, `crm.atribucion_contrato_fn` | **Explica a quién cuenta la inversión** | Resuelve la atribución de una línea de upgrade y la muestra con su motivo. |
| `private.capital_episodios`, `private.capital_autorizada` | **Calculadora única del capital** | Todos los reportes reutilizan los mismos hechos; cada vista declara si pregunta por período o por saldo vigente. |
| `private.conversion_episodios`, capa de conversión | **Calculadora única de conversión** | Define qué episodios aportan, qué peso tienen y a quién corresponden. |
| `private.citas_episodios`, `crm.metricas_reuniones_fn` | **Cuenta las citas y sus resultados** | Parte de tareas de reunión; separa pactadas, realizadas, ausencias y cancelaciones. |
| `private.metricas_sla_global_core`, `crm.estado_sla_leads_fn` | **Mide atención y plazos actuales** | Conserva el SLA existente de primera gestión/cohortes y sus fotografías. |
| `private.sla_operacion_leads` / `sla_operacion_autorizada` | **Prioriza seguimiento y compromisos — propuesto** | Núcleo nuevo previsto para seguimiento recurrente, compromiso dominante y prórrogas; no implementado. |
| `crm.cerrar_periodo`, `ciclo_cierre_mes` | **Guarda el resultado oficial del mes** | Sella resultados para conservar la historia; las correcciones posteriores se registran como ajustes. |
| `crm.resolver_tasa_fn`, `crm.observacion_rentabilidad_fn` | **Compara la tasa con la política — observación** | Muestra cuánto se apartan las condiciones de la regla comercial, sin bloquear hoy el contrato. |
| `solicitar_tasa_fn`, `resolver_solicitud_tasa_fn`, `responder_tope_tasa_fn` | **Solicita y decide una excepción de tasa** | Flujo preparado para que Gerencia apruebe, rechace o proponga un tope; la obligatoriedad todavía es futura. |
| Auditores + `public.audit_log` | **Deja rastro de las operaciones** | Permite reconstruir quién hizo el cambio y qué cambió. |
| `notificar-pagos`, `ciclo-contratos`, `enviar-push`, `enviar-comunicado` | **Automatiza avisos y ciclo del contrato** | Los relojes y servicios mantienen vencimientos y comunicaciones sin depender de una pantalla abierta. |
| `crm-agenda-ics` | **Comparte la agenda por calendario** | Publica el calendario autorizado mediante su enlace específico. |

## Correcciones a interpretaciones históricas

1. La auditoría del 28/08 localizó capital en 16 funciones, leads en 21 y citas en 6. P-055 documenta la unificación posterior de capital y citas, con conversión ya canónica. Los conteos son **antes**, no diagnóstico nuevo.
2. La misma auditoría distingue versiones de una respuesta y cálculos duplicados: las tres versiones de distribución delegaban en una sola autorización. Tres nombres no prueban tres reglas.
3. Los roles del CRM y del Portal son dominios diferentes por diseño. La solución posterior unificó las capacidades y comprobaciones de vigencia; no eliminó los dos dominios.
4. Dos auditores alimentaban el mismo `audit_log` con convenciones de nombre diferentes. Es una diferencia documental a revisar; no debe dibujarse como dos bases de auditoría.
5. El contrato de capital del 29/08 todavía decía “no publicar antes del 10/09”. El estado posterior de P-055 registra la publicación del núcleo y consumidores el 30/08. Prima el checkpoint posterior.
6. Los nombres de RETOMAR-60 y varias notas conservan “pendiente” aunque el cuerpo registra entregas posteriores. Leer el estado más reciente dentro del documento.
7. El catálogo de productos y el control de rentabilidad son trabajos separados por decisión de Miguel del 06/09. No dibujar el catálogo como prerrequisito vigente de R1/R2.

## Fuentes documentales (vault)

Todas las rutas siguientes parten de `BASE DE CONOCIMINETO/AVANCECORP/`.

| Código | Nota y localización | Uso |
|---|---|---|
| F01 | `Inicio.md` | Contexto general, idioma comercial y fuentes canónicas. |
| F02 | `Arquitectura del portal.md` | Stack y servicios; resumen antiguo, tablas y versiones requieren lectura viva. |
| F03 | `Acceso y roles del CRM.md`, secciones acceso, Gerencia y rol comercial | Separación de accesos y ámbitos. No copiar cuentas o claves de la nota. |
| F04 | `Terminología comercial del CRM.md`, L3–24 | Analista visible, identificadores técnicos heredados. |
| F05 | `PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica.md`, L9–67 | Estado productivo 0/1/3/4/5/6; primer cierre; atribución pendiente. |
| F06 | `Auditoria servidor Supabase - duplicacion y deuda (2026-08-28).md`, L48–99, L295–301, L338–368 | Antecedente de duplicación, servicios y distinciones legítimas; no estado actual por defecto. |
| F07 | `Capa semantica del servidor - plan por nucleos (episodios).md`, L1–16 | Molde núcleo → ventana → presentación; reemplazado como plan por P-055. |
| F08 | `Contrato de la capa semantica - Capital (F4, 2026-08-29).md`, L8–45 | Capital, fuentes, monedas, AUM y pipeline. |
| F09 | `Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30).md`, L79–119 | Estado F6 y diferencia vista de 45 días frente a métrica mensual. |
| F10 | `Gestión comercial de clientes - renovaciones y upgrades.md`, L13–29, L74–107 | Postventa, renovación, capital adicional y conversión. Ponderación con estado pendiente en esa nota. |
| F11 | `Contrato de la atribucion por cadena de upgrade (2026-08-30).md`, L8–86 | Dos podios deliberados; responsable vs analista vs registrador; cadena de upgrade. |
| F12 | `Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31).md`, L18–96, L164–199, L279–342 | Modelo objetivo de identidad y dominios; documento F0 sin implementación por sí mismo. |
| F13 | `Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01).md`, L58–95, L163–204 | Avance/cooperativas, Portal y decisiones comerciales. |
| F14 | `RETOMAR-60 - F2.b E3 (b5) construida y ensayada, pendiente del ! (2026-09-05).md`, L9–27, L57–102 | Checkpoint actualizado al 06/09: instalaciones apagadas, D17–19 y D20 pendiente. |
| F15 | `RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05).md`, L44–58 | Idempotencia publicada y separación contrato/PDF. |
| F16 | `Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06.md`, L7–38, L56–151, L165–179 | Política comercial, R1/R2 observación, R3/R4 futuros, catálogo fuera de alcance. |
| F17 | `Nucleo operativo SLA - arquitectura y consumidores 2026-09-06.md`, L3–17 | Núcleo SLA nuevo propuesto y reutilización de fuentes existentes. |
| F18 | `Plan final SLA - seguimiento compromisos y etapas 2026-09-06.md`, L3–23 | SLA-R2 sin implementación; parámetros recomendados, no aprobaciones pasadas. |
| F19 | `Conversion por analista - separar cohorte e indice mensual 2026-09-06.md`, L3–17 | Cohorte frente a índice mensual; frontend pendiente de publicación. |
| F20 | `Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04.md`, L15–29, L54–69 | Cartera publicada, demos excluidos, ámbito Avance y límites de lectura. |
| F21 | `Inventario de indicadores de Gerencia - Citas y operacion.md`, L25–43 | Citas como tareas y diferencias entre cita, lead y conversión. |

### Límite de esta contribución

Es una síntesis de negocio y decisiones para acompañar el mapa. El mapa final debe usar el inventario nuevo del servidor para sus cantidades, funciones vivas, banderas, permisos, dependencias y fecha de corte. La ausencia de un consumidor en el frontend no demuestra que una función esté muerta: también puede usarla otro servicio, un calendario o un reloj del servidor.
