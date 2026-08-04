---
tags: [crm, leads, enfriamiento, disponibilidad, p047, p048]
actualizado: 2026-08-04
---

# Disponibilidad y enfriamiento de leads (P-047 y P-048)

## P-047 — contrato de servidor vigente

En el proyecto Supabase `dctqcbznekcyxhjujuci` existe en producción:

`crm.verificar_disponibilidad_lead(p_telefono text, p_dni text default null) returns jsonb`

Estados del contrato: `libre`, `en_bolsa`, `tomado`, `enfriamiento`,
`ya_es_cliente`, `no_contactar` y `error` con
`detalle='telefono_invalido'`. La política de enfriamiento conserva siete
motivos en servidor; P04 solo endurece quién puede consultar la RPC y no cambia
sus plazos ni el orden de decisión. Ver [[Acceso y roles del CRM]].

La verificación es **consultiva**. Los candados únicos de la base siguen siendo
la garantía transaccional frente a carreras; no se debe convertir P-047 en una
RPC de inserción ni duplicar sus reglas en TypeScript sin una decisión de
negocio nueva.

## P-048 — integración frontend completa en rama local

Objetivo: conectar la RPC al formulario existente de creación de leads sin DDL,
policies, wrappers en `public` ni configuración de PostgREST.

Paso 0 bloqueante: desde el mismo cliente del formulario ejecutar
`supabase.schema('crm').rpc('verificar_disponibilidad_lead',
{ p_telefono: '900000001' })` y exigir `{estado:'libre'}`. Si el esquema no está
expuesto, detenerse y reportar; no crear un atajo.

Reglas acordadas:

- verificar teléfono al perder foco y DNI al cambiar si tiene ocho dígitos;
- debounce de 400 ms e ignorar respuestas fuera de orden;
- `libre` habilita y no muestra mensaje; los demás estados muestran el mensaje
  de negocio acordado y bloquean;
- revalidar inmediatamente antes del INSERT;
- mapear una carrera `23505` a «Este contacto acaba de ser registrado por otro
  usuario»;
- ante red o timeout del precheck, permitir el submit normal: la verificación es
  de cortesía y no debe detener al vendedor;
- no conservar el JSON en cliente más allá de renderizar el estado actual y no
  agregar dependencias.

Verificación requerida: casos reales `en_bolsa` y `tomado`; normalización con
espacios y `+51`; estados sin dato real simulados y rotulados como tales; caída
simulada del RPC demostrando que el alta sigue habilitada.

P-048 se ejecuta **después de cerrar P04**, punto por punto. Relacionado:
[[F0 Cimientos BD del CRM]].

## Cierre local P-048 — 2026-08-04

Implementación completada en la rama `feat/p048-disponibilidad-leads`, todavía
sin release a producción. Se integró el mismo cliente Supabase del formulario,
contrato runtime estricto para los siete estados, presentación sin retener el
JSON, debounce/cancelación/orden de respuestas, revalidación antes del INSERT y
confirmación del commit antes de anunciar éxito.

La degradación es fail-open únicamente para transporte (`status=0`,
`PGRST000`–`PGRST003`) o timeout. Contrato inválido, permisos, Supabase ausente,
esquema no expuesto, RPC ausente y todo fallo desconocido bloquean por defecto.
La carrera `23505` solo se traduce para `uq_leads_telefono_vivo` y
`uq_leads_dni_vivo`; un rechazo revierte el optimista inmediatamente.

Riesgo residual aceptado del diseño consultivo: la revalidación y el INSERT no
son una única transacción. Los duplicados vivos sí quedan protegidos por índices
únicos; `no_contactar`, `ya_es_cliente` y `enfriamiento` no son todavía vetos
atómicos de escritura. Si negocio decide que deben ser prohibiciones duras aun
bajo concurrencia o caída del precheck, hará falta un trigger/RPC transaccional
de servidor en una fase posterior.

Verificación local:

- gate completo de la app: lint, TypeScript, cobertura y build limpios;
- 90 archivos / 1151 pruebas en la corrida integral final; cobertura focal de
  P-048 y persistencia: 4 archivos / 85 pruebas;
- Playwright: 68 escenarios aprobados y 38 omitidos por los gates previstos de
  sesión real del entorno local;
- smoke autenticado contra producción desde el cliente compartido: `libre`,
  `en_bolsa`, `tomado`, teléfono con espacios y teléfono con `+51`, sin imprimir
  PII ni secretos;
- estados restantes, caída de red, timeout, respuesta fuera de orden,
  revalidación cambiante y carrera `23505` cubiertos de forma simulada.

Siguiente gate: prueba de piloto real con Miguel y, solo mediante
`/release-crm`, construir/verificar el artefacto y desplegar el frontend.
