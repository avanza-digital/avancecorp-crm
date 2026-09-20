---
tags: [crm, escalabilidad, leads, agenda, buscador, fase-4, sin-topes]
actualizado: 2026-09-20
estado: 4a y 4b CONSTRUIDAS, ENSAYADAS Y REVISADAS (auditor-rls + Codex aplicados; SQL 20260920045202 sin instalar) · quedan 4c, 4d y 4e
---

# Leads sin foto inicial — Fase 4 del plan «sin topes» (2026-09-20)

Continúa [[Actividad reciente sin registro entero - Fase 3 del plan sin topes (2026-09-19)]],
[[Tareas sin tope - Fase 2 del plan sin topes (2026-09-19)]] y
[[Historial por lead sin topes - Fase 1 (2026-09-19)]]. Relacionado con
[[Plan de escalabilidad del CRM a data gigante]] (F3) y [[Mapa de capas del servidor CRM - 2026-09-17]].

## Objetivo (fijado por Miguel el 19/09, noche)

Que ninguna pantalla dependa de la foto inicial de leads: cada una pide al servidor lo que
muestra con las RPC existentes, el arranque no baja leads en sesión real, y mueren
`MAX_LEADS_AMBITO`, el puente (5 000) y su alarma (4 000).

## Lo que se midió antes de tocar nada

- 1 983 leads activos (+398/semana): la alarma del puente sonaría en ~5 semanas.
- 19 archivos del front leen `ambito.leads`: búsqueda global, Pipeline, Leads, bandejas de
  Equipo/Derivaciones/Hoy·Supervisor, Agenda y Citas de gerencia, higiene de Hoy·Vendedor,
  dedup del store, abrir ficha, alertas y (desde el 19/09) las consultas de Gestión Diaria.
- Citas de gerencia en sesión real ya era por RPC (`useCitasGerencia`): solo la demo usa la foto.
- `crm.leads` tiene índices trigram en nombre, teléfono y DNI y `cartera_pagina_fn` ya filtra
  por `p_texto` (mínimo 2 caracteres; teléfono/DNI a partir de 3 dígitos): la búsqueda global no
  necesitaba servidor nuevo.

## 4a — Buscador global por servidor (front, sin SQL)

- `buscarLeadsGlobal` (`data/crm-api.ts`) → `crm.cartera_pagina_fn` con `p_texto` y `p_limite` 8,
  INVOKER bajo RLS; `useBusquedaGlobal` (clave bajo `leads`; sin `keepPreviousData`: solo se pinta la lista
  de la consulta del texto actual).
- La barra pide con el texto asentado 300 ms y solo por encima del mínimo (`textoBuscable`);
  estados: buscando, bajo mínimo, error con Enter o «Reintentar»; región viva persistente que
  anuncia el desenlace («N resultados», «Sin resultados», «Buscando…»);
  `aria-activedescendant` en el combobox (deuda previa saldada). La demo sigue con su foto local.
- Revisor a11y aplicado (Enter reintenta, región persistente, error solo cuando no reintenta,
  `text-destructive-text`). 29 tests del topbar + 5 MSW.

## 4b — La Agenda sin la foto (1 migración aditiva + front)

- **Servidor** `20260920045202_crm_tareas_pendientes_lead_embebido.sql`: `create or replace` del
  núcleo de la Fase 2 para embeber, por tarea, ocho columnas más del lead bajo `leads_select`
  (teléfono, monto, moneda, vendedor, supervisor, correo, `no_contactar`, teléfono alternativo);
  la base comprueba las once columnas por grant; 18 mutantes (17 de la Fase 2 + uno que deja a
  `authenticated` solo id/nombre/etapa por columna). Puerta, índice y gate no cambian; payload
  `version: 1` (claves nuevas en la RESPUESTA, opcionales para el front → orden de publicación
  libre). Ensayo local PASS (copia con la Fase 2 instalada antes): gate, 18/18 mutantes, matriz
  de 11 roles, valores = `crm.leads` bajo la misma sesión, caso «tarea visible, lead no» con las
  diez claves en nulo. `auditor-rls`: sin fuga de PII, sin P0/P1; hallazgos aplicados.
- **Front**: `leadDeTarea` (`lib/agenda-vistas.ts`) arma un `LeadDeAgenda` desde la tarea; la
  Agenda en sesión real usa ese recorte en filtros, agrupado por persona («el lead manda», y si
  no es visible manda la tarea), recordatorio por WhatsApp, capital en juego y acciones de
  contacto (`LeadContactable`), sin consultar `ambito.leads` ni el gate `idsAmbito` (la RLS ya puso
  el alcance; una tarea con lead no visible se lista sin capital ni recordatorio). La tarjeta
  flotante del lead solo con un `Lead` completo (demo): con el recorte no se inventa origen ni alta.

## Decisiones

- **`no_contactar` es fail-closed:** sin el dato (servidor anterior) se asume que NO se puede
  contactar; la veta legal nunca se pierde por una clave ausente.
- **Correo y teléfono alternativo van embebidos** porque las acciones de contacto de la tarjeta
  y el panel de resultado de llamada de Gestión Diaria los usan; sin ellos la Agenda real habría
  perdido los botones de llamar/WhatsApp (regresión visible en la pantalla diaria del analista).
- **`LeadContactable`** (tipo nuevo) es lo que necesitan las acciones de contacto; un `Lead`
  completo lo cumple. Cambio de tipo, sin comportamiento, en `gestion-diaria/registrar-resultado.tsx`.
- La tarjeta flotante desaparece en la Agenda real (la ficha sigue a un clic): es la única
  diferencia visible aceptada.

## Lo que falta

1. PR sobre `main` → **[Miguel]** `!` con la migración → md5 en
   prod → registrador → `!` → fusionar → `/release-crm` → acta, mapa de capas, `main` el mismo día.
2. **4c** bandejas (Equipo parkeados, Derivaciones, Hoy·Supervisor) con `leads_por_repartir`.
3. **4d** Pipeline por columna (`cartera_filtrada_fn` por etapa + cursor, tiles de
   `resumen_cartera_fn`), Leads y cartera paginada sin foto, higiene de Hoy·Vendedor
   (`cola_accion_v2_fn`/`resumen_tareas_fn`), dedup del store (`verificar_disponibilidad_lead`).
4. **4e** arranque sin leads: `cargarReal`, `ambito` → módulo demo, `abrirLead` por id, alertas
   (`fotoConfiable`), Gestión Diaria (`gestion-diaria-queries.ts` resuelve nombre/etapa desde la
   foto: coordinar), logout endurecido antes de tocar `epocaRef`; borrar `MAX_LEADS_AMBITO`, puente,
   alarma, fila MSW y ruta E2E.
5. **Seguimientos de la revisión de Codex (20/09):**
   - La búsqueda por servidor pierde la tolerancia a tildes que tenía el filtro local (`ILIKE`
     sin `unaccent`): en prod 249 de 1 983 leads activos llevan tilde o ñ y `unaccent` está
     instalado → migración aparte sobre `cartera_pagina_fn`/`cartera_filtrada_fn` (unaccent +
     índice de expresión); la pantalla Leads tiene hoy la misma limitación. **Decisión de Miguel.**
   - Requisito de la 4e: los escritores del store (`registrarLlamada`, `registrarActividad`,
     `tareasDe`, cerrar tarea) resuelven el lead por pertenencia a la foto; sin foto deben
     resolverlo por id bajo RLS. Hoy no es regresión (la foto sigue cargándose).
   - Aplicados: la barra solo pinta la lista de la consulta del texto ACTUAL (Enter ya no
     elige un resultado del texto anterior; sin `keepPreviousData`); la lectura puntual de una
     tarea conserva el lead embebido (`conservarLeadEmbebido`); `leads` se cancela antes de
     invalidarse; sin teléfono no se ofrece «Llamar».
6. Deuda ajena anotada por el auditor: `telefono_alternativo` nació sin ACL por columna propia
   (molde `20260919211105`); el test `gestion-diaria/registro-actividad.test.tsx` dependía del
   reloj (fijado al día del fixture en esta PR).

## Lecciones

- `String.prototype.replace` con `$'` en el reemplazo: un cuerpo SQL con `$b$'` se rompió al
  editar el archivo desde Node; reconstruido con un replacer de función. Contar `$function$`,
  `$postflight$` y `notify` después de editar una migración a máquina.
- El BEFORE INSERT de `crm.tareas` copia la tenencia del lead: el caso «tarea visible, lead no»
  se siembra re-apuntando la tarea DESPUÉS (como admin), no insertándola ya divergente.
- Un test que mira `new Date()` caduca a medianoche de Lima: fijar el reloj al día del fixture.
