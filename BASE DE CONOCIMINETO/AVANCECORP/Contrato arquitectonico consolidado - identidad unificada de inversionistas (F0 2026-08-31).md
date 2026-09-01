---
tags: [crm, inversionistas, identidad, cartera, cooperativas, arquitectura, f0]
actualizado: 2026-08-31
estado: contrato-consolidado-pendiente-de-aprobacion-de-miguel
revisores: [Camila, Claude-Code, Codex]
---

# Contrato arquitectónico consolidado — identidad unificada de inversionistas

## 0. Estado, alcance y evidencia

Este documento consolida la revisión independiente de **Claude Code**, la revisión adversarial de **Codex** y la decisión arquitectónica final de **Camila**. Es un contrato de F0: **no contiene una implementación aplicada** y no autoriza migraciones, cambios de producción ni publicación.

La revisión contrastó el árbol actual, las migraciones, las puertas de escritura, los núcleos semánticos y las decisiones del vault. CodeGraph se usó primero para ubicación; su índice no cubre con fiabilidad todas las migraciones del 29–31/08, por lo que las conclusiones recientes se verificaron además contra los archivos fuente.

La nota raíz documentada como `Bienvenido.md` no existe; el punto de entrada real es [[Inicio]].

## 1. Veredicto ejecutivo

La unificación es viable y debe hacerse **sin convertir Portal, Leads, contratos y cierres externos en una sola cosa**.

> **Una persona, una ficha y un solo lead; puede tener muchas inversiones, y cada inversión conserva su empresa, responsable, moneda, documento histórico e historial.**

La pieza estructural faltante es una identidad neutral: `crm.inversionistas`. Sin ella, una misma persona se representa de maneras incompatibles:

- en captación, como `crm.leads`;
- en Avance, como `public.perfiles` y sus contratos;
- en cooperativas, como un lead convertido y `crm.cierres_externos`;
- en postventa Avance, como `crm.operaciones_cartera` enlazada al perfil.

La identidad neutral **no sustituye** esas entidades. Las conecta.

La implementación F1 queda bloqueada hasta que:

1. Miguel apruebe este contrato como paquete;
2. se ejecute el censo F0 de solo lectura;
3. el delta previsto de conversiones se presente y coincida con la regla aprobada;
4. se respete el calendario y las huellas vigentes de los núcleos.

## 2. Separación de dominios

| Dominio | Pregunta que responde | Entidad |
|---|---|---|
| Identidad comercial | ¿Quién es la persona? | `crm.inversionistas` |
| Identificadores | ¿Con qué documento se demuestra esa identidad? | `crm.inversionista_identificadores` |
| Relación comercial | ¿Quién administra hoy la relación? | responsable vigente del inversionista |
| Relación de captación | ¿Cuál es el único seguimiento comercial de la persona? | un solo `crm.leads` por inversionista |
| Acceso Portal | ¿Puede entrar al Portal de Avance? | `public.perfiles` + Auth |
| Inversión Avance | ¿Qué contrato legal tiene con Avance? | `public.contratos` |
| Operación postventa Avance | ¿Renovó o aumentó una línea? | `crm.operaciones_cartera` |
| Inversión cooperativa | ¿Qué cierre realizó en Qorilazo o Prodelco? | `crm.cierres_externos` |
| Atribución | ¿A quién cuenta cada venta o línea? | snapshots y política de atribución existentes |
| Métrica | ¿Cuánto capital/conversión aporta? | núcleos `private.*_episodios` |

Regla de lenguaje:

> **El lead administra el único seguimiento comercial de la persona. Inversionistas administra la identidad. Contratos, cierres y operaciones administran sus múltiples inversiones. Los núcleos administran las cifras.**

## 3. Arquitectura objetivo

```text
crm.inversionistas
│
├── crm.inversionista_identificadores
│     └── documento fuerte, normalizado, vigente/histórico y auditado
│
├── responsable de relación vigente
│     └── historial de reasignaciones
│
├── crm.leads
│     └── único lead y seguimiento comercial de la persona
│
├── perfil_id opcional ───────────────► public.perfiles + Auth
│                                         └── public.contratos
│                                               └── crm.operaciones_cartera
│
└── crm.cierres_externos
      ├── Qorilazo
      └── Prodelco
```

### Relaciones exactas

| Fuente | Enlace con inversionista | Contrato |
|---|---|---|
| `crm.leads` | `inversionista_id` directo y nullable | Puede ser NULL durante captación; debe existir al convertir y será `UNIQUE` cuando no sea NULL para impedir un segundo lead de la persona. |
| `crm.cierres_externos` | `inversionista_id` directo | Obligatorio al cierre; `lead_id` se conserva. |
| `public.perfiles` | enlace inverso mediante `crm.inversionistas.perfil_id` | Opcional y único; no se agrega una columna nueva al Portal. |
| `public.contratos` | derivado por `cliente_id → perfil_id` | No se agrega `inversionista_id`; se conserva el contrato legal. |
| `crm.operaciones_cartera` | derivado por su cliente/contratos | No se reemplaza `cliente_id` ni se reescribe el ledger. |
| `crm.lead_asignaciones` | derivado por `lead_id` | Sigue siendo el episodio histórico de captación. |
| Núcleos | dimensión derivada `inversionista_id` | Conservan las claves originales del hecho. |

`crm.leads.contrato_id` queda **intocable**: no se reutiliza como identidad ni como vínculo nuevo.

F1 debe crear una restricción o índice único parcial sobre `crm.leads(inversionista_id) where inversionista_id is not null`. Antes de activarlo, el backfill debe detectar cualquier persona vinculada a más de un lead, escoger un único lead sobreviviente mediante revisión controlada y trasladar o referenciar el historial sin perderlo. F2 debe reutilizar ese lead bajo concurrencia; nunca insertar otro para el mismo `inversionista_id`.

## 4. Modelo de identidad aprobado por recomendación

### 4.1 `crm.inversionistas`

La tabla principal es un ancla estable y una relación comercial, no un duplicado completo del perfil o del lead.

Campos conceptuales obligatorios:

- `id`;
- `estado`: `activo`, `fusionado` o `bloqueado`;
- `perfil_id` opcional, único para identidades activas;
- `responsable_relacion_id` opcional durante backfill y obligatorio para operar comercialmente;
- `no_contactar` y su auditoría de activación/desactivación;
- `inversionista_canonico_id` y `fusionado_en` para fusiones;
- creación, actualización y autoría.

No contiene nombre, teléfono ni correo como una cuarta copia maestra en F1. La ficha proyecta el contacto desde fuentes vigentes con procedencia visible.

### 4.2 `crm.inversionista_identificadores`

Los documentos no deben modelarse como un único texto reemplazable en la tabla principal. Una persona puede corregir un documento, sustituirlo o conservar uno anterior como alias histórico.

Cada identificador registra:

- `inversionista_id`;
- `tipo_documento`: DNI, CE o PASAPORTE;
- `documento_normalizado`;
- estado `vigente` o `historico`;
- verificación y fuente;
- vigencia temporal;
- creación y autoría.

Solo un identificador documental **vigente, verificado y no fusionado** puede resolver automáticamente identidad. La unicidad se aplica a:

```text
(tipo_documento, documento_normalizado) WHERE vigente
```

Teléfono, correo y nombre **no son identificadores fuertes** y nunca fusionan automáticamente personas.

### 4.3 Identidad sin documento

La primera versión no crea una identidad operativa sin documento verificado.

- Un lead puede existir sin `inversionista_id` durante captación.
- Ninguna inversión puede confirmarse sin documento válido.
- Históricos sin documento o con formato inválido quedan en una cola de reconciliación.
- Nombre, teléfono o correo pueden generar candidatos para revisión, nunca una unión automática.
- No se crean identidades provisionales que después puedan bloquear o mezclar por error a dos personas.

### 4.4 Corrección y fusión

Corregir un documento no reescribe cierres, contratos ni titulares históricos. Se modifica la vigencia del identificador mediante una puerta auditada.

Una fusión:

1. es exclusiva de Gerencia;
2. exige motivo y previsualización de impacto;
3. bloquea ambas identidades en orden determinista;
4. elige una identidad canónica;
5. reorienta únicamente enlaces operativos vivos;
6. conserva todos los hechos y snapshots;
7. registra una fila append-only de fusión;
8. nunca borra la identidad perdedora;
9. nunca reescribe un mes sellado.

## 5. Autoridad de contacto

La identidad neutral no inventa una nueva fuente maestra de contacto en F1.

La proyección de contacto actual usa este orden:

1. perfil Avance vigente y autorizado, si existe;
2. último lead vinculado con datos confiables;
3. si no existe fuente actual, snapshot más reciente solo como dato informativo y marcado como histórico.

Cada campo devuelto por la Ficha 360 debe indicar su fuente y fecha. Una corrección de contacto se ejecuta por la puerta del dominio que es autoridad en ese momento; nunca modifica snapshots contractuales o cooperativos.

El correo comercial y el correo de Auth pueden coincidir, pero no significan lo mismo. Cambiar el contacto comercial no cambia automáticamente el login del Portal.

## 6. Responsabilidades y atribución

Se separan tres papeles:

1. **Responsable de relación:** administra hoy la ficha y la siguiente oportunidad.
2. **Analista de venta:** recibe la atribución de una inversión concreta según los snapshots y selectores existentes.
3. **Responsable de línea:** aplica a contratos y cadenas de upgrade/renovación según la política ya firmada.

Reglas:

- Solo existe un responsable de relación vigente por inversionista.
- Cambiarlo exige una puerta de reasignación con motivo e historial.
- Cambiar el responsable de relación no mueve atribuciones históricas.
- Una venta nueva puede atribuirse a un analista distinto si la puerta existente lo permite.
- La adopción por cadena de upgrade continúa siguiendo al contrato, no a la persona.
- `creado_por`, responsable de relación y analista atribuido nunca se confunden.

Backfill recomendado:

- identidad con perfil Avance: responsable inicial = `asesor_perfil_id` vigente;
- solo cooperativa: responsable inicial = vendedor snapshot del cierre vigente más reciente;
- conflicto o responsable inactivo: revisión de Gerencia antes de habilitar acciones.

## 7. Oportunidades

### 7.1 Oportunidad viva

```text
oportunidad viva = lead activo AND etapa no terminal
```

`no_contactar` no vuelve terminal una oportunidad ni permite abrir otra. La unicidad se protege con un índice único parcial por `inversionista_id`, permitiendo NULL durante captación.

Máximo:

> **Una oportunidad viva por inversionista.**

Si una solicitud concurrente intenta crear otra:

- una operación gana;
- la otra relee la oportunidad existente y la devuelve;
- nunca crea un duplicado.

### 7.2 Naturaleza

Cada oportunidad registra explícitamente:

- `captacion`: proviene de una entrada comercial nueva y conserva la regla vigente del divisor;
- `cartera`: nace desde la relación existente y no agrega otro lead al divisor.

La naturaleza se guarda como snapshot. No se infiere por la pantalla ni por el origen textual.

### 7.3 Disponibilidad y `no_contactar`

El veto `no_contactar` se eleva al nivel de inversionista:

- bloquea toda oportunidad nueva y todo seguimiento, incluso si cambia el teléfono;
- los leads vinculados heredan el veto;
- el backfill centraliza cualquier veto histórico activo;
- levantarlo exige la puerta y auditoría legal correspondiente.

La búsqueda por teléfono o correo puede avisar que existe una coincidencia posible, pero solo el documento exacto vincula automáticamente la oportunidad a una identidad.

## 8. Conversión y concurrencia

### 8.1 Primitiva privada

Todas las puertas usan una única primitiva privada de resolución de identidad:

```text
private.inversionista_resolver(tipo_documento, documento)
```

Contrato:

- normaliza y valida;
- busca el identificador vigente;
- crea de forma idempotente si no existe;
- el índice único arbitra carreras;
- ante conflicto, relee la identidad ganadora;
- no tiene `EXECUTE` para la API;
- no fusiona por datos débiles.

### 8.2 Conversión Avance

- La identidad se resuelve dentro de `crm.convertir_lead`.
- El perfil Portal se vincula a la identidad.
- PostgreSQL y Auth siguen sin compartir transacción.
- `crm.conversion_reservas` conserva su función de idempotencia y compensación.
- Un reintento reutiliza Auth, perfil e inversionista existentes; no crea otra persona.
- La edge continúa enviando el correo únicamente después de confirmar el servidor.

### 8.3 Conversión cooperativa

- `crm.convertir_lead_externo` resuelve la identidad dentro de su transacción.
- El cierre nace con `lead_id` e `inversionista_id`.
- No crea Auth, perfil Portal ni correo.
- Documento y nombre del cierre siguen siendo fotografías de la cooperativa.

La reserva existente por `lead_id` continúa impidiendo que el mismo lead cierre simultáneamente por Avance y cooperativa. Dos inversiones legítimas de la misma persona no se bloquean entre sí: la deduplicación de conversión se resuelve en el núcleo, no prohibiendo hechos económicos.

## 9. Conversión mensual consolidada

### 9.1 Regla recomendada

> **Un inversionista aporta como máximo una conversión por mes. El primer episodio elegible confirmado gana.**

Orden determinista:

1. fecha de confirmación económica;
2. fecha de registro;
3. identificador estable del episodio.

Participan en la elección:

- conversión de lead Avance;
- conversión de lead cooperativa;
- renovación, aumento o upgrade elegible de cartera.

No participan en el divisor las oportunidades de naturaleza `cartera`.

### 9.2 Efectos

- El episodio ganador conserva su analista y la ponderación de referido vigente.
- Los demás episodios del mes conservan capital, producción, empresa, analista e historial, pero aportan cero conversiones adicionales.
- Los episodios perdedores siguen visibles; no se eliminan del núcleo.
- La selección es por inversionista, no por perfil, lead ni contrato.

### 9.3 Anulación

Para conservar la regla ya firmada de ATR-4 —«la anulación baja la conversión, siempre»—:

- el ganador original se determina incluyendo el episodio posteriormente anulado;
- si se anula, su aporte pasa a cero;
- **no asciende un segundo episodio del mismo mes**;
- en mes abierto, la lectura refleja el cero;
- en mes sellado, la foto permanece y el ajuste/sanción existente registra la disminución;
- el capital conserva la semántica de ATR-4 y no se altera por esta elección.

Esta decisión evita que una segunda operación neutralice silenciosamente una sanción.

### 9.4 Sellados y fusiones

- Ningún backfill o fusión recalcula pagos o fotos de meses sellados.
- El censo debe mostrar el delta de la lente viva y separar explícitamente meses abiertos de sellados.
- Una fusión durante un mes abierto requiere previsualización del ganador resultante.
- La deduplicación usa `p_periodo` del núcleo; no inventa otro calendario.

## 10. Capital y empresas

`private.capital_episodios` gana dimensiones, no una segunda calculadora:

- `inversionista_id`;
- `empresa`: `avance`, `qorilazo`, `prodelco`;
- claves originales del contrato/cierre;
- moneda, monto, estado, analista y registrador ya existentes.

Invariantes:

- todas las inversiones aportan su capital según la política vigente;
- capital Avance y capital colocado en cooperativas se presentan separados;
- PEN y USD nunca se suman;
- los cierres externos dejan de depender de `lead.perfil_id` para identificar a la persona;
- `crm.ajustes_mes_cerrado` sigue siendo ajuste del analista, no capital económico;
- no nace ninguna suma paralela fuera de `private.capital_episodios`.

Las empresas iniciales son las tres actuales. Las claves son estables y la interfaz queda preparada para un catálogo futuro, pero F1–F5 no generaliza silenciosamente cierres a empresas no aprobadas.

## 11. Lectura postventa y Ficha 360 neutral

No se cambian de significado:

- `crm.cartera_pagina_fn`: sigue listando oportunidades/leads;
- `crm.clientes_basicos_fn`: sigue listando clientes Avance;
- `crm.cliente_detalle_fn`: sigue mostrando detalle Avance;
- `public.crear_contrato`: sigue siendo puerta legal de contratos;
- las funciones actuales de cuentas bancarias conservan sus permisos.

Nacen dos fronteras:

```text
crm.inversionistas_pagina_fn(...)
crm.inversionista_ficha_fn(p_inversionista_id)
```

La lista postventa pagina identidades, no leads. La ficha neutral devuelve:

- identidad y contacto mínimo con procedencia;
- responsable de relación;
- oportunidades históricas y vigente;
- inversiones agrupadas por empresa y moneda;
- contratos y operaciones Avance;
- cierres cooperativos;
- próximos vencimientos;
- historial visible;
- banderas de reconciliación o datos incompletos.

La banca, domicilio, cronograma y capacidad Portal se consultan por las fronteras Avance existentes y solo cuando el actor ya está autorizado.

### Visibilidad

- Vendedor: identidades cuyo responsable de relación sea él.
- Supervisor: identidades de responsables vigentes dentro de su árbol.
- Gerencia: alcance global y acciones autorizadas.
- Directorio: identidad e inversiones en modo consulta; sin contacto sensible, domicilio, banca ni mutaciones.
- Un analista que hizo una venta histórica no conserva acceso perpetuo si ya no administra la relación.

La ventana privada de visibilidad se implementa una sola vez y alimenta lista y ficha; no se copian predicados de rol en funciones sueltas.

## 12. Historial comercial

F1–F5 no fusiona físicamente `crm.actividades`, `crm.actividades_cliente` ni los ledgers económicos.

La Ficha 360 construye una línea de tiempo de lectura sobre las fuentes existentes. Toda nueva gestión comercial reutiliza el único lead de la persona, incluso si está convertido o descartado; se registra el nuevo hecho en su historial y, cuando corresponda, en contratos, cierres u operaciones. Nunca se crea un segundo lead ni una actividad huérfana.

## 13. Censo y backfill

### 13.1 Censo F0 obligatorio y de solo lectura

Debe medir:

- perfiles con documento válido, inválido o ausente;
- cierres externos por tipo/documento;
- leads convertidos con y sin perfil;
- duplicados exactos por tipo/documento;
- mismo número usado con tipos diferentes;
- múltiples perfiles para una identidad fuerte;
- responsables de relación ambiguos o inactivos;
- vetos `no_contactar` que deban centralizarse;
- coincidencias solo por teléfono/correo/nombre;
- delta de conversiones por inversionista/mes;
- impacto de fusiones en meses abiertos y sellados;
- capital por empresa/moneda antes y después, que debe ser idéntico.

### 13.2 Clases

- **A — automática:** perfil cliente con documento válido y único.
- **B — automática:** cierre externo con documento válido y único.
- **C — automática:** lead convertido hereda la identidad inequívoca de su perfil o cierre.
- **D — automática:** lead DNI coincide exactamente con un único identificador DNI vigente.
- **E — revisión humana:** sin documento, formato inválido, colisión, tipo contradictorio, múltiples perfiles, responsable ambiguo.
- **F — candidata solamente:** teléfono, correo o nombre coincidente; nunca se enlaza automáticamente.

### 13.3 Orden de backfill

1. Crear tablas deny-by-default e índices de identidad.
2. Crear columnas nullable.
3. Ejecutar el censo sin enlazar.
4. Revisar clases E/F.
5. Crear identidades A/B.
6. Enlazar C/D.
7. Asignar responsable de relación y centralizar `no_contactar`.
8. Repetir censo y comprobar ausencia de conflictos.
9. Validar constraints.
10. Hacer obligatorio `cierres_externos.inversionista_id`.
11. Activar las puertas canónicas.

Se conserva un mapa auditable de backfill con fuente, fila, identidad, regla, confianza, revisor y fecha. Nada ambiguo se fusiona automáticamente.

## 14. Seguridad

- `crm.inversionistas`, identificadores, fusiones y backfill nacen con RLS activa.
- Cero grants directos a Data API; acceso por RPC con autorización explícita.
- Primitivas privadas sin `EXECUTE` para `anon`, `authenticated` ni `service_role` salvo necesidad documentada.
- El documento completo no se copia a logs genéricos.
- Toda corrección/fusión/reasignación deja auditoría propia.
- La ficha neutral no hereda automáticamente permisos del Portal.
- La revocación CRM prevalece donde corresponda según los porteros vigentes.
- Cada función nueva entra al censo de autorización y a los trinquetes existentes.

## 15. Traslados entre empresas

F1–F5 no afirma que un traslado movió dinero.

F6 diseñará un ledger económico separado:

```text
inversión origen → movimiento económico → inversión destino
```

Debe contener inversionista, instrumentos origen/destino, empresas, monto, moneda, fecha valor, estado, referencias, autor y aprobador. Cubrirá Avance→cooperativa, cooperativa→Avance y cooperativa→cooperativa.

Antes de F6 solo puede registrarse una intención o clasificación comercial, claramente rotulada como tal y sin cerrar ni mover automáticamente la inversión de origen.

## 16. Plan por fases y gates

### F0 — contrato y censo

- Aprobar este contrato.
- Ejecutar censo de solo lectura.
- Presentar conflictos y delta de conversiones.
- No alterar datos.

**Gate:** aprobación de Miguel y censo reconciliado.

### F1 — identidad, responsabilidad y backfill

- Crear ancla, identificadores, fusiones y responsabilidad.
- Añadir enlaces nullable.
- Backfill A–D; E/F quedan pendientes.
- RLS, auditoría y tipos.

**Gate:** dos altas simultáneas del mismo documento producen una identidad; capital idéntico; cero fusiones ambiguas.

### F2 — puertas canónicas

Adaptar:

- disponibilidad y creación atómica de leads;
- conversión Avance;
- conversión externa;
- vinculación del perfil;
- creación de contrato cuando deba verificar identidad;
- fusión, corrección y reasignación.

**Gate:** carreras, reintentos de Auth, Avance/cooperativa sobre el mismo lead, `no_contactar` y una oportunidad viva.

### F3 — núcleos semánticos

- Añadir inversionista/empresa a capital con paridad exacta.
- Extender conversión a inversionista/mes y naturaleza de oportunidad.
- Conservar ATR-1/2/4, sellados y atribución por cadena.

**Gate:** paridad monetaria byte a byte; delta de conversión exactamente igual al aprobado; meses sellados intactos.

### F4 — lectura postventa

- Lista neutral paginada.
- Ficha 360 neutral.
- Línea de tiempo agregada de lectura.
- Rama Avance separada para banca/Portal.

**Gate:** matriz de roles, PII y banca; fronteras antiguas sin cambio de firma ni significado.

### F5 — interfaz comercial

- Abrir inversionista desde Mi cartera.
- Registrar una nueva intención o inversión sobre el mismo lead.
- Reutilizar siempre el único lead; nunca crear otro para la misma persona.
- Elegir destino Avance/Qorilazo/Prodelco.
- Mostrar inversiones por empresa y moneda.

**Gate:** E2E concurrente, pérdida de sesión, reintento, accesibilidad, demo/real y release verificado.

### F6 — traslados formales

- Contrato contable/legal propio.
- Ledger origen/destino.
- Reglas de cierre y reversión.

**Gate:** aprobación comercial, operativa y legal independiente.

## 17. Invariantes no negociables

1. Una persona puede tener varios leads, contratos y cierres, pero una sola identidad activa por documento fuerte vigente.
2. Un externo no obtiene Portal por existir como inversionista.
3. Un perfil Portal no es la identidad neutral.
4. Un cierre externo conserva `lead_id` e `inversionista_id`.
5. Contratos y operaciones conservan sus enlaces legales actuales.
6. Exactamente un solo lead total por inversionista; la restricción incluye leads vivos, convertidos y descartados.
7. `no_contactar` bloquea a la persona, no solo un teléfono.
8. Solo el documento exacto vincula automáticamente identidades.
9. Fusiones y correcciones nunca borran historia.
10. Snapshots nunca se reescriben por cambiar el contacto actual.
11. Responsable de relación y analista de venta son conceptos distintos.
12. Capital de todas las inversiones cuenta según su política vigente.
13. Máximo una conversión por inversionista/mes.
14. El ganador anulado no promociona un suplente.
15. Referidos conservan su ponderación.
16. PEN y USD nunca se suman.
17. Capital Avance y cooperativo no se presentan como un solo AUM.
18. Solo los núcleos privados calculan capital y conversión.
19. Meses sellados y fotos de pago no se reescriben.
20. La banca solo se obtiene por la rama Avance autorizada.
21. `cartera_pagina_fn`, `clientes_basicos_fn` y `cliente_detalle_fn` no cambian de significado.
22. Ningún traslado económico existe sin ledger formal.

## 18. Riesgos reconocidos

- El índice de CodeGraph está rezagado para migraciones recientes; no debe usarse solo como evidencia de F1.
- `crm.leads` solo representa DNI de ocho dígitos; CE/pasaporte se resuelven al convertir hasta que exista una decisión separada para ampliar captación.
- `public.perfiles` tiene reglas documentales más débiles que el cierre externo; el censo puede revelar colisiones.
- Auth y PostgreSQL no son una sola transacción; la reserva durable y la idempotencia siguen siendo necesarias.
- El cambio de «por cliente» a «por inversionista» puede reducir conversiones del mismo mes; el delta se mide antes de implementar.
- La Ficha 360 neutral puede filtrar PII si su visibilidad se deriva de vendedores históricos en vez del responsable actual; por eso la responsabilidad de relación es explícita.
- El núcleo de capital actual no identifica bien a una persona externa cuando depende de `lead.perfil_id`; F3 debe corregir la dimensión sin alterar montos.
- F1+ no debe adelantarse a los trabajos calendarizados que reescriben los mismos núcleos.

## 19. Decisión solicitada a Miguel

La recomendación consolidada cierra las preguntas de F0 de esta manera:

- identidad operativa solo con documento fuerte;
- identificadores históricos auditados;
- contacto proyectado, no cuarta copia maestra;
- un responsable de relación;
- una oportunidad viva;
- `no_contactar` por persona;
- captación entra al divisor y cartera no;
- primera conversión del inversionista en el mes gana;
- ganador anulado no se reemplaza;
- tres empresas iniciales, sin generalización prematura;
- fusión solo por Gerencia;
- traslados económicos diferidos a F6.

La aprobación de este documento autoriza únicamente preparar y ejecutar el **censo F0 de solo lectura**. La migración F1 requerirá una autorización posterior, con el SQL mostrado previamente, según [[Inicio]].

## 20. Relacionadas

- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Cierres en cooperativas Qorilazo y Prodelco - plan]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Ficha comercial 360 de clientes - plan]]
- [[Conversion unica en todo el CRM - plan de migraciones 2]]
- [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]]
- [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]]
- [[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
- [[Las tres definiciones de autoridad (2026-08-29)]]
