# SERVIDOR CRM — mapa de Avance Corp

Este mapa explica cómo está organizado el servidor del CRM, qué hace cada parte para el negocio y dónde un mismo proceso se divide en caminos diferentes. Está basado en la lectura del servidor Supabase y su código desplegado del **6 de septiembre de 2026, hora de Lima**.

**[Abrir la carpeta SERVIDOR CRM en Figma](https://www.figma.com/files/team/1673045681873340799/folder/650628787)** · **[Abrir el tablero completo](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df)**

## Por dónde empezar

| Sección del tablero | Qué vas a entender |
|---|---|
| [Portada y guía](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=10-347) | Cómo recorrer el mapa y reconocer el estado de cada pieza. |
| [Vista general del servidor](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=1-2) | Cómo se conectan CRM, Portal, base de datos, accesos, archivos y servicios. |
| [Recorrido comercial](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-349) | El camino desde un prospecto hasta cliente, inversión, seguimiento y resultados. |
| [Calculadoras compartidas](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-352) | De dónde salen los resultados de conversión, capital y citas. |
| [Versiones y caminos alternativos](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-355) | Qué parte se usa hoy, qué conserva piezas anteriores y qué está preparado pero apagado. |
| [Glosario de 24 capacidades](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=18-347) | Para qué sirve cada grupo de funciones, explicado en términos comerciales. |
| [Ocho puntos para revisar](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=19-347) | Lugares concretos que conviene observar para simplificar mantenimiento o evitar interpretaciones equivocadas. |
| [Funciones sueltas y conexiones pendientes](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=32-395) | No contactar, período comercial, resumen de Agenda y puerta común de capital; flechas discontinuas para las conexiones pendientes. |
| [Candidatas a retiro y falsas alarmas](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=34-395) | Diez puertas para revisar, funciones preparadas, herramientas manuales y dependencia externa por aclarar. |

## Qué se encontró

El inventario del área revisada contiene **88 tablas, 3 vistas, 476 funciones de base de datos, 16 Edge Functions, 9 tareas programadas activas y 3 almacenes de archivos**. Las 476 funciones incluyen auxiliares, disparadores automáticos y variantes de firma: no equivalen a 476 funciones comerciales independientes.

Las 16 Edge Functions figuran desplegadas como `ACTIVE`; una de ellas, `diagnostico-push`, está retirada funcionalmente y responde 410. El nombre de despliegue por sí solo no demuestra que una pieza esté en uso.

Los tres interruptores de activación `resolver_en_puertas`, `inversiones_escritura` y `ficha_360_neutral` están en `false`. **La estructura y las funciones de identidad unificada existen; las rutas controladas por esos interruptores están apagadas hoy.** La política de rentabilidad está en modo observación, versión 1.

## Cinco bifurcaciones importantes

| Decisión o separación | Qué significa para el negocio | Qué mirar en el mapa |
|---|---|---|
| **Avance o cooperativa** | Un cierre en Avance puede llevar a cliente del Portal y luego contrato/cuotas. Un cierre en cooperativa conserva su registro comercial externo. | Dos destinos de inversión con consecuencias distintas; la conversión del prospecto y el registro del contrato son pasos separados. |
| **Qué resultado se quiere medir** | Prospectos que cerraron, índice mensual, dinero del período, capital vigente y citas responden preguntas distintas. | Las pantallas combinan calculadoras compartidas; cifras diferentes no prueban por sí solas un cálculo duplicado o erróneo. |
| **Versión actual o pieza anterior reutilizada** | La pantalla de Distribución usa V3, que todavía utiliza motores internos V2 y base. | Las puertas antiguas V1/V2 están cerradas al usuario, pero sus piezas internas siguen participando. No se deben marcar todas como abandonadas. |
| **Camino vigente o preparado apagado** | Varias operaciones de alta e identidad conservan dos recorridos y un interruptor decide cuál se utiliza. | Separar lo instalado de lo activado; los tres interruptores observados están apagados. |
| **Operación registrada o resultado complementario listo** | Un contrato puede existir con su PDF pendiente. Un aviso tomado por el servidor puede no haberse entregado todavía por correo o push. | Estados separados para contrato/PDF y para proceso de aviso/entrega. Esto ayuda a evitar reintentos mal interpretados. |

Una bifurcación puede ser una regla deliberada de negocio. Para llamarla problema hay que comprobar que dos caminos intentan responder la misma pregunta y aplican reglas incompatibles.

## Cuatro conclusiones

1. **CRM y Portal comparten el mismo servidor Supabase.** Las áreas `crm`, `public` y `private` organizan trabajo comercial, información compartida y reglas internas. No son tres servidores distintos; `public` tampoco significa acceso libre a cualquier dato.
2. **Existen calculadoras compartidas de conversión, capital y citas.** Las pantallas las combinan según su pregunta. También quedan cadenas de versiones y controles aplicados en distintos puntos que merecen verse claramente antes de simplificarlos.
3. **Parte de la evolución ya está instalada, con activación pendiente.** La identidad unificada no está ausente: sus caminos están condicionados por interruptores apagados. Rentabilidad observa; el nuevo núcleo de seguimiento SLA propuesto no apareció en el catálogo vivo revisado.
4. **El mapa permite localizar responsabilidades y posibles duplicaciones de mantenimiento.** Por ejemplo, comunicados delega push a otro servicio, mientras pagos y vencimientos tienen envíos propios. La lectura no demuestra que esos caminos fallen ni que una entrega haya llegado a su destinatario.

## Leyenda en lenguaje sencillo

| Término | Significado |
|---|---|
| Tabla | Lista de una clase de información, como prospectos o contratos. |
| RPC / función de base de datos | Trabajo con nombre que se encarga al servidor: registrar, comprobar o calcular. |
| Calculadora / núcleo | Regla compartida que produce un resultado para varias pantallas. |
| Edge Function | Encargado que coordina accesos, importación, archivos o servicios externos. |
| Auth y permisos | Quién está conectado y qué información o acciones le corresponden. |
| Cron | Reloj que inicia un trabajo automáticamente. |
| Storage | Almacén de archivos. |
| Bandera | Interruptor que activa un camino preparado. |
| Instalado / apagado / propuesto | Existe en el servidor / su interruptor no lo habilita / es un diseño todavía sin esa implementación comprobada. |

## Evidencia y alcance

| Archivo | Para qué sirve |
|---|---|
| [funciones-sueltas-y-conexiones-pendientes.md](./funciones-sueltas-y-conexiones-pendientes.md) | Diagnóstico de conexiones, explicación comercial, clasificación y límites antes de retirar algo. |
| [inventario-produccion.json](./inventario-produccion.json) | Inventario de objetos de base de datos y funciones Edge desplegadas. |
| [evidencia-sql.json](./evidencia-sql.json) | Consultas de catálogo y cuerpos de funciones del servidor que respaldan el mapa. |
| [evidencia-distribucion-dependencias.json](./evidencia-distribucion-dependencias.json) | Evidencia de permisos y conexiones entre Distribución y calculadoras. |
| [verificacion-distribucion-nucleos.md](./verificacion-distribucion-nucleos.md) | Explica las conexiones comprobadas y evita confundir una ruta posible con una ruta que realmente toma esa versión. |
| [analisis-edge-produccion.md](./analisis-edge-produccion.md) | Explicación de las 16 Edge Functions, integraciones, decisiones y estados. |
| [analisis-codigo.md](./analisis-codigo.md) | Relación entre las pantallas, sus solicitudes y las operaciones del servidor. |
| [contexto-comercial.md](./contexto-comercial.md) | Significado comercial y antecedentes documentales; el estado vivo se toma del inventario y la verificación actual. |

Se leyeron metadatos, permisos y cuerpos de funciones, junto con código local y conocimiento del proyecto. No se modificó el servidor ni se ejecutaron operaciones comerciales. **No se midió tráfico ni entrega de mensajes**, por lo que una conexión dibujada no acredita frecuencia de uso ni éxito de cada ejecución. Este trabajo es un mapa de arquitectura y bifurcaciones; **no es una auditoría completa de seguridad**.
