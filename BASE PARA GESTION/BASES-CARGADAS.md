# Bases cargadas: el supervisor carga bases antiguas, las reparte y ve si se trabajan

> Pedido de Miguel (03/10/2026): «que los supervisores carguen bases antiguas y puedan repartirlas a sus analistas, en
> bloques o de manera individual, sencillo: darle 40 a un analista y 30 a otro; y que puedan hacer seguimiento a esas
> bases, si las están trabajando o no». Es parte del módulo «Base para gestión». Plan, nada escrito todavía.

## Decisiones de Miguel (03/10/2026)

| # | Pregunta | Decisión |
|---|---|---|
| E1 | ¿Qué es una base antigua? | **Las dos cosas:** un archivo Excel/CSV con contactos que no están en el CRM, **o** un lote armado con leads viejos que ya están en el CRM (descartados o sin gestión de meses anteriores). Las dos entradas terminan en el mismo reparto. |
| E2 | Contacto del archivo que ya existe (mismo teléfono o DNI) | **Se salta y se informa.** Nunca se crea un duplicado. El informe dice por qué: ya es lead de otro analista, ya es cliente o tiene «No insistir». |
| E3 | ¿Cómo la trabaja el analista? | **Dentro de su Base para gestión**, con la etiqueta de la base (p. ej. «Feria 2025») y las mismas reglas: intentos, rellamada (máx. 10 días), 3 intentos → 30 días de descanso. |
| E4 | ¿Quién carga y reparte? | **El supervisor, a SU equipo; gerencia, a cualquiera.** Igual que el Centro de rescate. |

Regla que ya vale y se aplica aquí también (B6, Miguel 03/10): un lead con **seguimiento activo** (intento ≤ 7 días o
rellamada vigente) sale en gris «En gestión por X hasta el día Y» y el servidor no deja repartirlo.

## Cómo se ve (flujo del supervisor)

1. **Bases** (pantalla nueva, en el menú del supervisor y de gerencia): hoja con una fila por base. Columnas: Base ·
   Origen (archivo / CRM) · Cargada · Leads · Sin repartir · Repartidos · Sin tocar · Trabajados · Citas · Avance (%).
   Cada número se abre en su lista (regla «todo número se abre»).
2. **Cargar base** → dos caminos:
   - **Subir archivo** (.xlsx o .csv, hasta 2000 filas): se suelta el archivo, el CRM reconoce las columnas (nombre,
     teléfono, DNI, distrito, comentario) y muestra una vista previa. Al confirmar, el **servidor** valida y responde con
     el informe: «38 cargados · 2 ya estaban (1 de Juan, 1 cliente) · 1 con No insistir · 3 sin teléfono válido».
   - **Armar desde el CRM**: filtros por mes del descarte, motivo, etapa máxima y analista anterior; se ve el conteo y se
     guarda como base con nombre. Los leads con seguimiento activo quedan fuera, en gris.
3. **Repartir** (sencillo): la lista de analistas del equipo con una casilla de **cantidad** al lado de cada uno
   (Ana 40 · Luis 30) y el contador «70 de 85 por repartir». Atajo «En partes iguales». **Individual:** marcar filas de
   la base y «Asignar a…» un analista. El reparto es atómico: o entran todos o ninguno.
4. **Seguimiento**: dentro de cada base, una fila por analista: asignados · sin tocar · trabajados (≥ 1 intento) ·
   en descanso · citas logradas · último intento. «Sin tocar hace 3 días» se marca en rojo. Se puede **recoger** lo que
   un analista no tocó y repartirlo a otro (los que tienen seguimiento activo no se mueven).
5. **El analista** no cambia de pantalla: los leads de la base le aparecen en su Base para gestión, con la etiqueta de la
   base en una columna y un selector «Base: Todas · Feria 2025 (40)» junto al de «Mes».

## Servidor (LEVEL 3: datos, permisos y carga masiva; circuito: banco Docker → gate RLS → auditor-rls → Codex → `!`)

| Paso | Qué | Notas |
|---|---|---|
| **B7 Esquema** | `crm.bases_carga` (la base: nombre, origen `archivo`/`crm`, creada por, totales del informe) y `crm.base_carga_leads` (qué lead está en qué base, a quién se asignó, cuándo, por quién). RLS ON, deny-by-default, sin DELETE; auditoría. | `crm.leads` lleva grants POR COLUMNA: si se agrega una columna (p. ej. `base_carga_id`), sus grants explícitos. Origen nuevo del lead para lo que viene de archivo (`base_cargada`), con su etiqueta en el front. |
| **B8 Cargar** | `crm.cargar_base_archivo(nombre, filas jsonb)`: valida (≤ 2000 filas, teléfono normalizado, DNI), descarta duplicados con la **regla de identidad que ya existe** (la misma de alta de leads), crea los leads sin dueño dentro de la base y devuelve el informe. `crm.armar_base_crm(nombre, filtros)`: arma la base con leads existentes elegibles. | Idempotente por id de operación (un doble clic no carga dos veces). El navegador lee el Excel; el servidor decide. |
| **B9 Repartir** | `crm.repartir_base(base_id, reparto jsonb)`: en bloque (`[{analista, cantidad}]`) o individual (`[{lead, analista}]`); valida que el analista sea del equipo (gerencia: cualquiera), rechaza leads con seguimiento activo (B6) y ya repartidos. `crm.recoger_de_base(base_id, analista)`: devuelve a «sin repartir» lo que no se tocó. | Todo o nada. Deja rastro en el ledger de asignaciones. |
| **B10 Seguimiento** | `crm.seguimiento_bases()` (una fila por base) y `crm.seguimiento_base(base_id)` (una fila por analista), con los conteos de arriba. `crm.obtener_base_gestion` incluye los leads de base asignados al analista (con `base_nombre`). | Medir con datos reales: gerencia ya recibe 1069 filas en la base. |

## Pantalla

| Paso | Qué |
|---|---|
| **F5 Bases (supervisor)** | Pantalla «Bases»: hoja de bases con avance; «Cargar base» (archivo / desde el CRM) con vista previa e informe; reparto por cantidades y por selección; seguimiento por analista; recoger. Lector de Excel cargado solo cuando se usa (dependencia nueva, liviana). |
| **F6 Analista** | Columna «Base» y selector de base en su hoja, junto al de «Mes». |

## Orden propuesto

B5 + B6 (en curso) → F2–F4 del plan original → **B7–B10 + F5–F6**. Cada paso con su plan corto, banco, gate y Codex;
lo aplica Miguel con `!`. Se publica primero el servidor y después la pantalla.

## Abierto (se decide en el F0 de este paso, con evidencia)

- Tope por archivo (propuesto: 2000 filas) y columnas obligatorias (propuesto: nombre + teléfono).
- Si un lead de base que el analista no tocó en N días vuelve solo a «sin repartir» o solo se marca en rojo
  (propuesto: solo se marca; el supervisor decide recoger).
