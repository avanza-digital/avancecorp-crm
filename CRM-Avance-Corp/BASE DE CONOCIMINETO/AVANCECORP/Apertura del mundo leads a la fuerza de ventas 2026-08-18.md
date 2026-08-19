# Apertura del mundo leads a la fuerza de ventas — 2026-08-18

Relacionado con [[Verificación y toma de lead libre]], [[Acceso y roles del CRM]],
[[Limpieza de la cola de leads 2026-08-18]] y [[Deploy a Hostinger]].

## La decisión

Miguel ordenó **abrir la llave**: Hoy, Pipeline, Leads y Agenda dejan de estar
ocultos para vendedores y supervisores. El CRM salió a producción en julio solo
con Clientes y Contratos; desde entonces el único que veía el circuito completo
en producción era el **piloto** (su propia cuenta, rol vendedor).

El interruptor es uno solo y siempre lo fue: `FUNCIONES_LEADS_APROBADAS` en
`app/src/lib/config.ts`. El piloto (`CUENTAS_PILOTO_LEADS`) **se borra** al
abrirla, como decía su propio comentario: no se deja creciendo.

## El agujero que solo aparece al abrirla

`hoy` es la **única vista de leads que no exige capacidad**. Con la llave
cerrada nadie lo notaba porque el gate la cerraba para todos; al abrirla, el
**coordinador** (Rosa) se llevaba «Hoy» de regalo en su menú y un buscador de
leads que nunca encuentra nada — su ámbito de leads es ∅ (espejo exacto de
`private.vendedor_ids_visibles`) y su único destino es «Repartir leads».

Cerrado en dos capas:

1. `config.ts` — la lista de roles pasa a ser **cerrada**: gerencia y directorio
   siempre, vendedor y supervisor por la llave, **el resto no**. Así el rol
   ausente o desconocido conserva el mínimo privilegio que ya tenía.
2. `vistas.ts` — el corte del router (`esVistaLeads && (!leadsVisibles || rol ===
   'coordinador')`), defensa en profundidad.

## Lo que van a NOTAR los asesores

**Su pantalla de aterrizaje cambia de «Mi cartera» a «Hoy».** No es un efecto
secundario: `VISTA_BASE_POR_ROL` siempre dijo que con el gate abierto vendedor y
supervisor aterrizan en «Hoy». Es lo primero que verán al entrar.

Con `crm.leads` vacía ([[Limpieza de la cola de leads 2026-08-18]]), ese «Hoy»
arranca en estados vacíos hasta que el puente traiga leads nuevos y Rosa los
reparta.

## Las suites que llevaban un mes dormidas

`acciones-real.spec.ts` y `cartera-keyset.spec.ts` se aparcaron el 2026-07-16
**esperando exactamente este día**. Al despertarlas, 9 de 16 fallaban — ninguna
por un defecto del producto, todas porque el producto siguió avanzando:

| Lo que rompió | Cuándo cambió |
|---|---|
| El botón de la cartera de leads se llama **«Leads»** (y para gerencia choca con «Repartir leads» → `exact`) | Fase 6, 2026-07-21 |
| El alta manual ya **no ofrece LANDING/FORMULARIO** (regla D8) | 2026-08-11 |
| Convertir pregunta **primero «¿Dónde invirtió?»** (cooperativas) | 2026-08-13 |
| Con la carga inicial caída **no hay menú lateral** que esperar | — |

Lección para el vault: **una suite aparcada se pudre**. Aparcarla contra el
contrato nuevo no la salva; lo que la salva es despertarla el día que se abre lo
que esperaba, y presupuestar la reparación como parte del trabajo.

Además, 19 pruebas de navegador daban por hecho el aterrizaje viejo: ahora
navegan a propósito con el helper `irAMiCartera`.

## Estado

- Commit **`7029fcd`** en la rama `feat/abrir-llave-leads` (nacida de `704d25e`,
  el commit VIVO en producción). Construido en un worktree limpio para no
  arrastrar el trabajo en curso de las otras dos sesiones (PDF v2 y reparto).
- Gate: **2.044/2.044** unitarias · **102 e2e** en verde (26 saltadas, todas por
  la retirada de Fase 6) · lint, tipos, build, verificador de bundle y jscpd.
- **3 mutantes muertos**: cerrar la llave, colar al coordinador en `config.ts`,
  quitarle el corte al router.
- ✅ **EN PRODUCCIÓN** desde el 2026-08-18 ~17:57 (hora de Lima): 33.º release
  **`crm-20260818T225705Z-e979b4907029`**, commit `e979b49`. Vivo verificado AL
  BYTE (index.html + JS principal + CSS + el chunk `mi-cartera`), la llave leída
  en el fichero SERVIDO (abre para gerencia/directorio/vendedor/supervisor y
  para nadie más) y el ZIP en 404. Registro en [[Deploy a Hostinger]].

## La trampa: el ledger mintió y casi cuesta un rollback

El primer artefacto (`crm-20260818T224758Z-7029fcd18aea`, commit `7029fcd`) se
construyó sobre `704d25e` — el último release ANOTADO. Pero lo que estaba VIVO
era `crm-20260818T201312Z-80942d8c7b50`: un release de la **sesión paralela de
contratos** (PDF v3, corrección y borrado seguro) publicado a las ~15:13 de Lima
y jamás anotado. **Publicar el mío habría borrado ese trabajo de producción.**

Se detectó comparando el **sha256 del `index.html` vivo contra los manifiestos
locales ANTES de subir nada**. La regla que queda: el ledger es una ayuda, el
**hash es la prueba** — identificar lo vivo por hash es el primer paso del
deploy, no el último. Solución: rebasar sobre `80942d8`, repetir el gate entero
y verificar DENTRO del bundle nuevo que su cadena «Contrato corregido y PDF
actualizado» seguía ahí.

## Rojo heredado (no es de esta llave)

3 pruebas de navegador de la corrección de contratos (`contrato-crear:69`,
`contrato-detalle:118`, `:157`) fallan **también en `80942d8`** — el commit que
ya estaba en producción antes de este deploy. Comprobado ejecutándolas en un
worktree limpio de ese commit. La más clara: el toast «Contrato corregido y
cronograma regenerado.» no aparece. Es de la sesión de contratos, y queda dicho
en vez de mudo.

## Cabo suelto honesto

El piloto validó en producción el camino del **vendedor**. El del **supervisor**
nunca tuvo una cuenta piloto viva: lo respaldan el gate de RLS y las unitarias,
no una sesión real. Merece una mirada el primer día.
