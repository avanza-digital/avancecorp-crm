# Las tres definiciones de autoridad (2026-08-29)

Inventario medido contra producción el 29/08/2026, a raíz de una pregunta de Miguel: *«creo que tenemos un conflicto de admin en el servidor, dos definiciones de admin en conflicto»*. **Tiene razón, y son tres, no dos.**

Relacionado: [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] · [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]]

---

## El censo

- `public.perfiles`: **418 filas** — 390 cliente, 19 analista, 5 comercial, 3 admin, 1 superadmin. **Cero** `directorio` y cero `operaciones` (Carlos Valles pasó a `admin` ese mismo día).
- `crm.equipo`: **26 filas**, 22 activas — 17 vendedor, 2 supervisor, 2 gerencia, 1 coordinador.

## Las tres familias de porteros

**A · El rol del Portal** (`public.perfiles.rol`). No mira el CRM en absoluto.

| Portero | Criterio | Personas |
|---|---|---|
| `es_admin()` | rol en (admin, superadmin) y activo | **4** |
| `es_superadmin()` | rol = superadmin | 1 |
| `es_gestor_cartera()` | `es_admin() OR es_operaciones()` | 4 |
| `es_analista()` | rol = analista | 19 |
| `es_directorio()`, `es_operaciones()` | — | **0 (código muerto)** |

**B · La membresía del CRM** (`crm.equipo.rol_crm` + activo).

| Portero | Criterio | Personas |
|---|---|---|
| `private.rol_crm()` | rol_crm si equipo.activo Y perfil.activo | 22 |
| `es_gerencia_crm_activa()` | rol_crm = gerencia | **2** |
| `puede_gestionar_contratos_crm()` | vendedor, supervisor o gerencia | 21 |
| `membresia_crm_revocada()` | existe fila con activo=false | 4 |

**C · Los híbridos** — 6 funciones mezclan ambos mundos con un `o`: `crear_contrato`, `actualizar_contrato`, `reasignar_analista_contrato`, `puede_gestionar_cuentas_cliente`, `cliente_detalle_fn`, `atribucion_contrato_fn`.

**Reparto:** 24 funciones se gobiernan solo por el Portal, **114 solo por el CRM**, 6 mezclan. Solo dos tablas tienen políticas de los dos mundos: `public.perfiles` y `crm.reasignaciones_analista`.

---

## Los choques, con nombre propio

**Funciones gemelas** — mismo nombre, dos esquemas, criterios distintos:

| Capacidad | Puerta del Portal | Puerta del CRM |
|---|---|---|
| Crear contrato con producto | `es_admin() OR es_analista()` → 23 personas | `puede_gestionar_contratos_crm()` → 21 |
| Editar contrato (y con cuenta) | ídem | ídem |
| Catálogo de productos | `es_admin() OR es_analista()` | `rol_crm IS NOT NULL OR es_lector_global()` |

Las dos puertas están vivas: el portal llama a las de `public`, el CRM a las de `crm`.

**Unilaterales:** `cerrar_contrato` y `bandeja_actividad` solo Portal · `actualizar_cliente_gerencia` solo CRM · `marcar_contrato_demo` vive en `public` pero se gatea solo por el CRM · en `public.perfiles`, gerencia del CRM **lee** clientes pero **no puede escribirlos** (la política de escritura solo mira el Portal).

---

## 🔴 Lo peligroso, hoy

1. **Una revocación a medias.** Una analista tiene la membresía del CRM apagada pero sigue **activa como analista en el Portal**. Las funciones la bloquean (`membresia_crm_revocada`), pero **las políticas de tabla solo miran `es_analista()`**: sigue **leyendo contratos, cronogramas y fichas de sus clientes, y editando perfiles de cliente** por acceso directo. La misma persona está revocada y no revocada según por dónde entre.
2. **Dos admin del Portal sin existencia en el CRM.** Máxima autoridad para crear, editar y cerrar contratos, ver todos los perfiles y leer la auditoría — e invisibles para el CRM: `rol_crm()` nulo les cierra leads, tareas, actividades y equipo.
3. **Escalada eligiendo la puerta.** Los 18 analistas del Portal que además son vendedores o supervisores del CRM tienen dos radios de alcance para la misma acción: por el Portal, «mis clientes»; por el CRM, lo que dé la visibilidad de su equipo — para los dos supervisores, **todo su equipo**.
4. **Latente:** `cerrar_contrato` y las cuentas de pago exigen rol de Portal. Hoy las dos gerencias del CRM son además admin, así que no se nota; **el día que exista una gerencia que no sea admin del Portal, podrá reasignar analistas y corregir clientes pero no cerrar contratos**.

---

## Qué hacer

No es un retoque: es una fase. La forma natural es **meterla en la Fase 5** (que ya es «cerrar puertas») en tres pasos:

1. **Cerrar la revocación a medias**: que las políticas de tabla del Portal consulten también `membresia_crm_revocada()`. Es el único punto con efecto inmediato sobre datos reales.
2. **Una sola pregunta por capacidad**: cada acción de negocio decide por un solo criterio, y la puerta gemela que sobre se retira por el camino seguro de la Fase 7 (cerrar, observar, borrar).
3. **Decidir el par de cada persona**: los dos admin sin CRM y los analistas con doble alcance.
