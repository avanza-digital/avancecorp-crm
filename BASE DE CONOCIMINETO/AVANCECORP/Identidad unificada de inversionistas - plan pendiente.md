---
tags: [crm, inversionistas, identidad, cartera, cooperativas, arquitectura]
actualizado: 2026-08-31
estado: propuesta-conceptual-pendiente-de-aprobacion-f0
---

# Identidad unificada de inversionistas — plan pendiente

## Idea rectora

> **Una persona, una ficha y un solo lead; puede tener muchas inversiones, y cada inversión conserva su empresa, responsable e historial.**

El CRM debe unificar la **identidad comercial** de la persona, sin mezclar las
operaciones legales ni el Portal de Avance Corp. Una persona puede invertir en
Avance, COOPAC Qorilazo y COOPAC Prodelco en momentos distintos; sigue siendo
una sola relación comercial y debe verse en una única ficha 360.

## Separación de conceptos

| Concepto | Significado | Fuente actual |
|---|---|---|
| Inversionista | Quién es la persona | Falta una identidad neutral |
| Seguimiento comercial | Relación única de captación y gestión | un solo `crm.leads` por persona |
| Inversión Avance | Contrato legal y capital en Avance | `public.contratos` |
| Inversión externa | Cierre real en una cooperativa | `crm.cierres_externos` |
| Portal | Capacidad opcional de acceso del cliente | `public.perfiles` + Auth |

Un inversionista externo no recibe Auth, contraseña, correo de bienvenida ni
perfil Portal. Si posteriormente invierte en Avance, se vincula un perfil a la
misma identidad; no se crea una segunda persona.

## Arquitectura objetivo

```text
crm.inversionistas
│
├── crm.leads (único lead de la persona)
│   └── crm.cierres_externos
│
└── public.perfiles (solo si existe Portal Avance)
    └── public.contratos
        └── crm.operaciones_cartera
```

La tabla neutral será inicialmente un **ancla de identidad**, no otra ficha
maestra con datos duplicados. Contendrá: `id`, `tipo_documento`,
`documento_normalizado`, estado, creación/actualización y la ruta auditada de
fusión (`fusionado_en`, `inversionista_canonico_id`).

La identidad se resuelve solo por coincidencia exacta de:

```text
tipo_documento + documento_normalizado
```

Nunca se une automáticamente por nombre, teléfono o correo. La unicidad se
aplica solo a identidades activas/canónicas. Una fusión jamás borra la historia.

## Reglas ya propuestas

### Captación y conversión

- `crm.leads.inversionista_id` puede ser NULL durante captación.
- Debe estar presente al confirmar una conversión.
- La conversión busca o crea la identidad dentro de la transacción de base de
  datos; el flujo Avance mantiene su reserva existente porque Auth no comparte
  la transacción PostgreSQL.
- Un cierre externo conserva directamente `inversionista_id`, además de su
  `lead_id`, porque es un hecho económico permanente.
- Los documentos/nombres de `crm.cierres_externos` siguen siendo fotografías
  de lo registrado por la cooperativa; no se reescriben al corregir contacto.

### Oportunidades

- Exactamente un lead total por inversionista, incluyendo estados vivos,
  convertidos y descartados.
- Toda nueva gestión reutiliza el mismo lead y añade historial; nunca crea una
  segunda fila para la persona.
- Las múltiples inversiones viven en contratos, cierres externos y operaciones
  de cartera, no en leads adicionales.
- `no_contactar` debe bloquear aunque cambie el teléfono.
- La naturaleza y el origen de cada nueva gestión se registran como historial
  del mismo lead, sin agregar otro lead al divisor.

### Conversión y atribución

Se propone que un inversionista obtenga como máximo una conversión por mes:

> La primera inversión u operación elegible confirmada durante el mes recibe
> la conversión.

Las demás operaciones de ese mes conservan todo su capital, producción y
Analista de venta, pero no agregan una segunda conversión. El desempate debe
ser determinista: fecha de confirmación → fecha de registro → identificador.
Si gana un referido, conserva su ponderación vigente. Esta regla debe ser
aprobada antes de cambiar [[Conversion unica en todo el CRM - plan de migraciones]].

### Contacto actual

La primera versión proyecta el contacto, no lo duplica:

1. perfil Avance vigente, si existe;
2. en su defecto, el último lead convertido y confiable.

Los snapshots contractuales y de cooperativas no se modifican.

### Traslado entre empresas

El traslado todavía no está modelado: `crm.operaciones_cartera` enlaza solo
contratos Avance. La primera entrega puede registrar una clasificación comercial
de traslado declarado, pero no cerrará ni moverá automáticamente la inversión
de origen. Una fase posterior debe modelar la relación económica formal:

```text
inversión origen → movimiento económico → inversión destino
```

Debe cubrir Avance→cooperativa, cooperativa→Avance y cooperativa→cooperativa.

## Fronteras de servidor

No se crearán funciones sueltas de búsqueda, resolución o cálculo. Cada pieza
debe pertenecer al dominio de identidad y estar registrada con consumidores,
permisos y pruebas.

Se mantienen con su significado actual:

- `crm.cartera_pagina_fn`: lista de oportunidades/leads; no se convierte en
  cartera postventa.
- `crm.clientes_basicos_fn` y `crm.cliente_detalle_fn`: clientes Avance y
  detalle de `public.perfiles`; no se sobrecargan con UUID de inversionista.
- `crm.convertir_lead`, `crm.convertir_lead_externo` y
  `public.crear_contrato`: puertas canónicas de escritura.
- `private.capital_episodios` y `private.conversion_episodios`: calculadoras
  únicas de capital y conversión.

El dominio nuevo necesita, como contratos explícitos y no como utilidades
sueltas:

- una primitiva privada de identidad para las puertas de escritura;
- una ventana privada de visibilidad por rol;
- una lista postventa de inversionistas;
- una Ficha 360 neutral de inversionista.

La ficha neutral conserva el aislamiento bancario: banca, domicilio y Portal
solo se consultan en la rama Avance autorizada.

## La Ficha de cliente Avance se conserva

La [[Ficha comercial 360 de clientes - plan|Ficha comercial 360 existente]]
**no se elimina ni se sustituye**. Su contrato actual sigue siendo el detalle
seguro de un cliente de Avance (`public.perfiles`): contratos Avance, gestiones
postventa, tareas, domicilio y banca bajo sus permisos vigentes.

La futura Ficha 360 de inversionista será la capa comercial superior para ver
la relación multientidad. Cuando la persona también sea cliente Avance, mostrará
su bloque Avance y reutilizará/abrirá la ficha segura actual para los datos y
acciones exclusivos de Avance. Un inversionista solo de cooperativa nunca
recibe esa rama bancaria ni Portal.

```text
Ficha 360 de inversionista (nueva)
├── Identidad, oportunidades e inversiones de todas las empresas
├── Qorilazo / Prodelco: detalle comercial externo
└── Avance Corp: acceso a la Ficha de cliente existente
    ├── contratos y postventa Avance
    └── domicilio, banca y Portal con permisos actuales
```

## Plan por fases

### F0 — Contrato y censo, sin alterar datos

Definir y aprobar:

- documentos válidos, identidades sin documento y fusiones/correcciones;
- regla de primera conversión mensual y su atribución;
- oportunidad viva, no-contactar y captación frente a cartera;
- autoridad de nombre, teléfono y correo;
- alcance exacto de traslado;
- alcance inicial de empresas (Avance/Qorilazo/Prodelco o catálogo ampliable).

Medir de solo lectura documentos duplicados, coincidencias inequívocas,
ambigüedades y el cambio previsto de conversiones históricas.

### F1 — Identidad y backfill seguro

Crear el ancla `crm.inversionistas`, enlaces nullable a leads/perfiles y enlace
directo a cierres externos. Vincular solo coincidencias documentales exactas;
no fusionar ambigüedades automáticamente. Añadir restricciones después de la
reconciliación y negar accesos directos desde la API.

### F2 — Puertas canónicas de escritura

Adaptar disponibilidad, alta manual/automática de leads, conversión Avance,
conversión externa, vinculación de perfil y consistencia de contratos. Toda
escritura debe llegar por las puertas existentes, que usan la misma primitiva
privada de identidad.

### F3 — Núcleos semánticos

`private.capital_episodios` incorpora inversionista, empresa y operación;
debe mantener paridad monetaria exacta. `private.conversion_episodios` incorpora
inversionista, naturaleza de oportunidad y la deduplicación mensual aprobada;
su cambio es deliberado y debe venir con un oráculo del delta esperado.

### F4 — Lectura postventa

Mantener Leads sin cambio de significado. Crear la lista postventa de
inversionistas y la Ficha 360 neutral; agrupar inversiones por empresa y moneda
sin mezclar capital Avance con capital externo. La Ficha de cliente Avance se
mantiene como detalle seguro y especializado; la ficha neutral la complementa,
no la reemplaza.

### F5 — Interfaz comercial

Desde Mi cartera se abre el inversionista y se registra la nueva gestión o
inversión sobre su único lead. El servidor reutiliza siempre esa fila, añade el
historial correspondiente y usa la ruta Avance o cooperativa para la inversión.

### F6 — Traslados formales

Crear el ledger o relación económica formal de origen/destino antes de afirmar
que un traslado movió capital entre empresas.

## Validaciones obligatorias

- Dos conversiones simultáneas del mismo documento crean un solo inversionista.
- Un inversionista puede tener varias inversiones y exactamente un lead total.
- Un externo no obtiene perfil Portal; una persona Avance+cooperativa mantiene
  una sola identidad.
- Capital de ambas ventas cuenta completo; solo la primera gana conversión.
- Un referido ganador mantiene su peso.
- Las correcciones de contacto no cambian snapshots históricos.
- La banca no se expone fuera de la rama Avance autorizada.
- Capital conserva paridad exacta y no nacen calculadoras paralelas.

## Relacionadas

- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[Plan maestro de ejecucion - identidad unificada de inversionistas (2026-08-31)]]
- [[Cierres en cooperativas Qorilazo y Prodelco - plan]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Ficha comercial 360 de clientes - plan]]
- [[Capa semantica del servidor - plan por nucleos (episodios)]]
- [[Conversion unica en todo el CRM - plan de migraciones]]
- [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]]
- [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]]
- [[Atribucion de upgrades y sus renovaciones (decision 2026-08-30)]]
