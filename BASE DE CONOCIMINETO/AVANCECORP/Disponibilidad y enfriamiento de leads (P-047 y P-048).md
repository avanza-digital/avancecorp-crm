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

La verificación es **consultiva** y sigue separada de la escritura. P-047 no se
convirtió en una RPC de inserción ni se duplicaron sus reglas en TypeScript: la
fase atómica de P-048 reutiliza su cuerpo canónico privado desde otra RPC de
mutación. Los índices únicos continúan como última defensa.

## P-048 — primera integración frontend

La primera etapa conectó la consulta P-047 al formulario existente de creación
de leads sin DDL, policies, wrappers en `public` ni configuración de PostgREST.

Paso 0 bloqueante: desde el mismo cliente del formulario ejecutar
`supabase.schema('crm').rpc('verificar_disponibilidad_lead',
{ p_telefono: '900000001' })` y exigir `{estado:'libre'}`. Si el esquema no está
expuesto, detenerse y reportar; no crear un atajo.

Reglas acordadas:

- verificar teléfono al perder foco y DNI al cambiar si tiene ocho dígitos;
- debounce de 400 ms e ignorar respuestas fuera de orden;
- `libre` habilita y no muestra mensaje; los demás estados muestran el mensaje
  de negocio acordado y bloquean;
- revalidar inmediatamente antes de guardar para dar feedback temprano;
- mapear una carrera `23505` a «Este contacto acaba de ser registrado por otro
  usuario»;
- ante red o timeout del precheck, permitir el submit normal: la consulta es de
  cortesía; la RPC de escritura vuelve a decidir en servidor;
- no conservar el JSON en cliente más allá de renderizar el estado actual y no
  agregar dependencias.

Verificación requerida: casos reales `en_bolsa` y `tomado`; normalización con
espacios y `+51`; estados sin dato real simulados y rotulados como tales; caída
simulada del RPC demostrando que el alta sigue habilitada.

P-048 se ejecuta **después de cerrar P04**, punto por punto. Relacionado:
[[F0 Cimientos BD del CRM]].

## Alta manual atómica P-048 — cierre local 2026-08-04

La evolución local añade
`crm.crear_lead_si_disponible(...) returns jsonb`. El precheck de blur y la
revalidación inmediata siguen dando feedback temprano, pero son **solo UX**: la
autoridad final toma locks, reconsulta P-047 e inserta dentro de una misma
transacción. El frontend ya guarda mediante esta RPC y solo anuncia éxito tras
la confirmación del commit.

La degradación es fail-open únicamente para transporte (`status=0`,
`PGRST000`–`PGRST003`) o timeout. Contrato inválido, permisos, Supabase ausente,
esquema no expuesto, RPC ausente y todo fallo desconocido bloquean por defecto.
La carrera `23505` de los índices únicos vivos queda como defensa final ante un
escritor fuera del protocolo; un rechazo revierte el optimista inmediatamente.

### Contrato transaccional

- `private.bloquear_contactos_lead` toma advisory locks de transacción por todas
  las llaves normalizadas de teléfono/DNI, ordenadas antes de bloquear;
- la RPC vuelve a comprobar P04 después de cualquier espera, deriva
  `creado_por`, autoasignación/bandeja y ámbito, y ejecuta el cuerpo canónico de
  P-047 después de adquirir los locks;
- `p_id` es la identidad optimista y la llave de idempotencia: un reintento
  inmediato del mismo payload confirma la fila ya creada; reutilizarlo con datos
  distintos, o después de que la fila cambió por otra operación, falla cerrado;
- `trg_leads_00_disponibilidad_insert` hace que todo escritor de `crm.leads`
  comparta los locks. Si hay sesión humana también impone el veredicto P-047 para
  proteger un bundle anterior que aún use INSERT directo;
- `trg_leads_00_disponibilidad_update` coordina cambios de teléfono, DNI,
  `no_contactar`, etapa, activo y motivo de descarte con altas simultáneas; si
  una sesión humana cambia teléfono/DNI, aplica el mismo cuerpo P-047 excluyendo
  la propia fila, para que editar no permita saltar los vetos. Antes congela
  ambos identificadores si esa misma fila porta `no_contactar` o enfriamiento
  vigente: el veto no puede mudarse y dejar libre el dato anterior;
- el importador con `service_role` no puede ejecutar la RPC humana, pero el
  trigger lo serializa. Conserva deliberadamente su semántica especializada:
  permite determinados reingresos y hereda `no_contactar` en vez de aplicar
  todos los vetos del alta manual;
- `EXECUTE` de la RPC pertenece solo a `authenticated`; `anon` y `service_role`
  están revocados.

La atomicidad afirmada es respecto de escritores de `crm.leads`. La migración no
toca objetos de `public`, por lo que un alta de cliente o cambio de su identidad
en `public.perfiles` exactamente concurrente todavía puede competir con la
lectura `ya_es_cliente`. Universalizar ese protocolo exige una decisión
posterior del portal y del CRM; no se disfraza como resuelto aquí.

El INSERT directo de `authenticated` tampoco se revoca todavía. Durante la
adopción, el trigger lo convierte en un camino protegido para clientes antiguos;
la revocación del privilegio y el retiro de la policy quedan para una fase
posterior, cuando se haya comprobado que no existen bundles activos sin la RPC.

Verificación local:

- `supabase/scripts/test-creacion-lead-atomica.sql` es el oráculo autocontenido
  sobre PostgreSQL vacío/desechable: pasó con el token terminal
  `CREACION_LEAD_ATOMICA_TX_OK`;
- validó ACL, autoridad derivada, estados P-047, idempotencia, P04/ámbito, el
  trigger de compatibilidad, la inmovilidad de teléfono/DNI bajo vetos propios y
  conexiones `dblink` reales para carreras por teléfono, DNI, rollback, INSERT
  legacy y revocación P04 durante una espera;
- gate integral de la app: 90 archivos / 1168 pruebas, lint, TypeScript y
  cobertura en verde; build de producción correcto;
- foco P-048: 4 archivos / 102 pruebas;
- Playwright: 68 escenarios aprobados y 38 omitidos por gates intencionales;
- scripts Node y `git diff --check`, en verde.

Estado (corregido 2026-08-16 — la nota quedó RANCIA desde el deploy y Codex lo
cazó): P-048 está **EN PRODUCCIÓN**, registrada en Supabase como
`20260804213726` (timestamp remoto ≠ archivo local, mismo patrón que P04), con
el impl de 3 argumentos vivo (md5 `7063fc89…`) y el alta manual restringida
(`20260811210049`) también registrada. Verificado contra
`supabase_migrations.schema_migrations` y `pg_proc` en vivo. Desde F1 del plan
[[Verificación y toma de lead libre]] (2026-08-16), el estado `tomado` gana
`ultima_conversacion_en` (solo conversaciones reales) y el wrapper asienta el
registro anti-pesca `crm.verificaciones_lead`.
