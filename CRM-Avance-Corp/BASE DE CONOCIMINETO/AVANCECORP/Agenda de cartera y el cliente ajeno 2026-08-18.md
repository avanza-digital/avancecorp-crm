# Agenda de cartera y el cliente ajeno — 2026-08-18

Relacionado con [[Apertura del mundo leads a la fuerza de ventas 2026-08-18]],
[[Verificación y toma de lead libre]], [[Como se mide la conversion del asesor]] y
[[Acceso y roles del CRM]].

Documento visual (flujos) entregado a Miguel:
https://claude.ai/code/artifact/8b5eaa8e-1de1-462f-9d4d-733a51f2a749

## La pregunta de Miguel

«¿Cómo agendo una reunión con alguien que ya es cliente? En la agenda solo hay
leads» — y, después: «¿y si un asesor llama al cliente de OTRO, saca reunión y de
paso le entra un depósito? En la práctica eso es posible».

Aclaración suya que cierra una puerta: **da igual si el cliente fue lead alguna
vez**; lo que quiere es gestionar su cartera. Eso descarta «reabrir el lead del
que vino» (serviría para 2 de 338 clientes).

## Hallazgo mayor: la puerta ya está construida

La agenda del CRM es UNA tabla, `crm.tareas`, y una reunión es una tarea de
`tipo='reunion'`. Esa tabla nació el 2026-07-18 con **dos sujetos posibles** y el
comentario lo dice a la cara:

> «Exactamente UN sujeto: lead (venta) o perfil de cliente (postventa/cobranza,
> fase posterior — la columna nace hoy para no pagar otro ciclo de gate)»
> (`20260718180001_crm_tareas_agenda.sql:36-39` y el CHECK `tareas_un_solo_sujeto` en :80)

La rama de cliente está **viva en el servidor y muerta en la pantalla**: el front
siempre manda `lead_id`, `agenda.tsx:683` descarta lo que no cuelga de un lead y
`hoy/vendedor.tsx:662,713` filtra dos veces. La RLS de tareas es por TENENCIA (no
por lead), el cierre de tarea ya contempla el caso cliente y el feed ICS une por
`vendedor_id` sin tocar leads: **media obra hecha**.

⚠️ Con 2 leads en prod y ambos convertidos, HOY no puede agendar **nadie** — ni
con clientes ajenos ni con los propios. La agenda tiene 0 tareas pendientes.

## Decisiones de Miguel (2026-08-18)

| Decisión | Elección |
|---|---|
| ¿Las visitas a clientes cuentan en los paneles de gerencia? | **Que cuenten juntas** (mismo panel de agenda y tablero de Reuniones) |
| ¿Quién puede agendar con un cliente? | **Solo su asesor** (y gerencia) |

Consecuencia declarada de la primera: agosto deja de ser comparable con julio, y
obliga al candado 2 (si no, el `distinct on (lead_id)` del tablero de Reuniones
aplasta TODAS las visitas de cliente en una fila fantasma).

## Fase 1 — lo que hay que construir

**Servidor (una migración, servidor PRIMERO: la clave nueva viaja en el REQUEST).**
1. **Candado de cartera**: hoy `tareas_insert` valida `lead_id` y NO mira
   `perfil_id` (`20260807123000:116-154`), y el BEFORE trigger solo mira el lead
   (`20260718180001:123-133`) → cualquiera con rol CRM podría agendar sobre un
   perfil ajeno; solo lo esconde el filtro de la pantalla. Al encender la UI deja
   de estar escondido → el guard va en la MISMA migración. Predicado: el del
   servidor de contratos (`asesor_perfil_id = uid or (asesor_perfil_id is null and
   creado_por = uid)`, espejo de `clientes-vista.ts:29`), cubre 338/338.
2. **Contar una por una**: `ultima_realizada` de `metricas_reuniones_fn` hace
   `distinct on (lead_id)` (`20260805180000:1026`). `metricas_agenda_fn`
   (`20260727032429:394-427`) ya contaría las visitas sola (filtra por
   `vendedor_id is not null`).

**Front.** Botón «Agendar» en la ficha de cliente de `mi-cartera.tsx` (junto a
Corregir y +Contrato) · diálogo prellenado (reunión, próximo día hábil 10:00,
modalidad, ventana legal L–S reutilizando `tituloSugerido`/`fueraDeVentanaLegal`
de `lead-drawer.tsx:462-481`) · quitar los filtros de `agenda.tsx` y
`hoy/vendedor.tsx` · la tarjeta debe pintar el nombre del CLIENTE (hoy todos los
datos de la tarjeta salen del lead).

**Fase 2 (aparte):** la bitácora del cliente. `crm.actividades.lead_id` es NOT
NULL — un cliente no puede acumular historia sin abrirle sitio.

## El cliente ajeno: qué pasa HOY (medido)

El caso **no tiene camino**: choca tres veces, y las tres son muros duros.

1. **No lo encuentra.** `clientes_basicos_fn` filtra por
   `asesor_perfil_id in vendedor_ids_visibles(uid)` y para un vendedor eso es solo
   él. El buscador global le dice «búscalo en Cartera» y en Cartera no está: el
   CRM le manda dos veces donde nunca lo va a encontrar.
2. **Única puerta que confirma que existe**: la verificación por teléfono (F1)
   devuelve `ya_es_cliente` → «Esta persona ya es cliente y está a cargo de
   PIERINA LEVANO PURIZACA», con CERO acciones (`disponibilidad-lead.ts:96-102`
   excluye ese veredicto de tomable y de recordable).
3. **El depósito, rechazado**: 42501 «Cliente no encontrado o fuera de tu cartera»
   (el mensaje viejo «Solo puedes crear contratos para clientes de tu cartera» ya
   NO existe en prod), y el botón «+ Contrato» ni se pinta.

### Números de producción (18-ago)

- 338 clientes activos · 401 contratos · 336 de 338 clientes **nunca fueron lead**.
- **9 traspasos de cliente entre asesores en 70 días** (~1 cada 8 días), TODOS a
  mano por un admin del PORTAL, **ninguno con motivo** (`audit_log` no tiene esa
  columna; 15 de 31 cambios de dueño ni siquiera guardan QUIÉN).
- Contratos registrados por un asesor que NO era el dueño en ese momento: **CERO**.
  El sistema nunca lo permitió. Los 22 que hoy difieren son cargas del superadmin
  o reasignaciones POSTERIORES.

### 🔴 Hallazgos colaterales (independientes de la agenda)

1. **Un depósito, dos marcadores que se contradicen.** Cuota y metas atribuyen a
   **quien REGISTRA** (`contratos.creado_por`; hoy 376/376, porque la rama del
   lead enlazado está muerta: `crm.leads.contrato_id` = 0 filas). Capital colocado
   y cartera atribuyen al **asesor del cliente** (`perfiles.asesor_perfil_id`).
   **21 de 397 contratos vivos ya le cuentan a personas distintas.** La conversión
   (el %) va por un tercer camino, el ledger inmutable `lead_asignaciones`.
2. **El CRM manda a una puerta cerrada.** `lead-drawer.tsx:1810-1815` dice «pídele
   a Gerencia que te lo reasigne en el portal», pero la única gerencia CRM activa
   (CARLOS VALLES) tiene `rol_portal='directorio'` → no es `es_admin()` → no puede.
   Solo GLORIA y ADMINISTRADOR AVANCE CORP.
3. **El ranking del cockpit del portal** (`directorio_ranking_analistas`) agrupa
   por `asesor_perfil_id` **sin ventana de mes**: se reordena entero, hacia atrás,
   el día que se reasigna un cliente.
4. La nota del vault «Conversion mensual - definicion cerrada» está **RANCIA**
   (dice «todavía NO implementada»; A/D/D8/B están en prod desde el 11-13 ago).

## Las cuatro salidas (panel de 4 diseños + 3 jueces)

| | Regla | Quién cobra | Veredicto |
|---|---|---|---|
| **A · Un cliente, un dueño** | El depósito lo registra quien tiene al cliente ese día; para cobrarlo tú, pides el traspaso ANTES | todo al que registra | ✅ **empezar por aquí** — cero tablas, cero RPC; duele que es todo-o-nada |
| **B · Pase declarado** | Lo declaras sin pedir permiso; el dueño se entera al toque; 50/50 y **el cierre se lo cuenta el dueño** | capital 50/50, marcador al dueño | ✅ **la que ganó** (2 de 3 jueces) — cara: 2 tablas, 3 RPC, toca el motor del dinero |
| **C · Pase libre** | Abres tú un pase de 30 días y cobras el depósito entero | todo al visitante | ❌ paga la cosecha de renovaciones ajenas; el permiso que reutiliza abre **6** puertas (cuentas bancarias, editar contratos ajenos, PDF históricos) |
| **D · Pase con permiso 70/30** | Pides pase al dueño; si autoriza, 70/30 | 70 visitante / 30 dueño | ❌ el dueño se vuelve rentista; cruza CRM+portal+motor del dinero; 48 h de espera |

**Recomendación entregada:** A ahora → traspaso decente (motivo + aviso + arreglar
la puerta cerrada) → alinear los dos marcadores → B cuando el traspaso ya no
alcance, con **la renovación ajena pagada 100 % al dueño** (injerto exigido por
el juez de negocio; la categoría ya viaja en la CTE de atribución).

## ⏳ Esperando a Miguel (3 decisiones de negocio)

1. ¿El depósito de un cliente ajeno se parte o se lo lleva quien lo trae?
2. ¿Adelantarse a la renovación de un cliente ajeno cuenta como venta nueva?
3. ¿Quién autoriza un traspaso de cliente?

Nada de esto está construido. La Fase 1 (agendar con clientes) no depende de esas
tres respuestas y puede arrancar sola.
