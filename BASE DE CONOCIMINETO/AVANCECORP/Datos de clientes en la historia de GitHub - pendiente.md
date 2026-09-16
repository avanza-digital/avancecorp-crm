# Datos de clientes en la historia de GitHub — PENDIENTE (rescatado 2026-09-16)

> Rescatado de `avanza-digital/avancecorp-portal` (el monorepo mal nombrado) ANTES de
> borrarlo, porque era el ÚNICO sitio donde esto estaba escrito. Respaldo completo del
> repo en `DESARROLLO/RESPALDO-monorepo-historico-avancecorp/`.
>
> Estado al 2026-09-16: los cuatro repos que menciona SIGUEN EXISTIENDO y son privados.
> `avanzadigitald/avancecorp-crm` se retiró ese día (duplicado de la organización,
> respaldado), lo que reduce a tres los repos por limpiar.

---

# Pendientes de Avance Corp

> **URGENTE — el material de cliente está en tres repositorios más de GitHub.**
> Ver el punto 0. El ticket a Support cubría uno solo.

---

## 0. El mismo material vive en tres repos más (2026-08-03)

Se creía que `FUSION_alta_3_analistas.md` (5 nombres de clientes reales) y
`ESTADOS E CUENTA DE EJMPLO/660451MBSCT5.pdf` estaban sólo en
`avanza-digital/avanza-platform`. **No.** Comprobado ref por ref, los dos blobs
—`94d418c9…` y `4f9c6c6b…`— son alcanzables desde ramas remotas de:

| Repositorio (GitHub) | Dónde | Visibilidad |
|---|---|---|
| `avanzadigitald/avancecorp-crm` | **`main`** | privado |
| `avanzadigitald/cliente-avancecorp` | **`main`** | privado |
| `avanzadigitald/avanza-platform` | rama `avancecorp-desktop` | privado |
| `avanza-digital/avanza-platform` | ya inalcanzable, purga pedida | privado |

Los tres primeros están en la cuenta **personal** `avanzadigitald`, no en la
organización. Los cuatro son privados: no hubo exposición pública.

**Lo que cambia:** en dos de ellos el material está en la rama por defecto, así
que **no alcanza con borrar una rama**. Hay que reescribir la historia
(`git-filter-repo`, igual que se hizo en el monorepo) y recién después pedirle a
Support que purgue los objetos inalcanzables — Support no purga lo que sigue
referenciado. Un ticket por repositorio.

Estado local al 3-ago: los tres árboles de trabajo ya están limpios (nombres
redactados, carpetas de estados borradas), pero eso son **cambios sin commitear**
y no toca la historia de ninguno.

---

Cosas comprobadas contra producción que quedaron sin cerrar. Ninguna es
urgente; todas son de las que en seis meses nadie recuerda si se pueden tocar.

Proyecto Supabase: `dctqcbznekcyxhjujuci` (PortalAvanceCorp).

---

## 1. La fusión asesor → analista quedó a medio camino

`FUSION_asesor_analista_LIMPIEZA_FINAL.sql` (escrito el 2026-06-05) **nunca se
ejecutó.** Comprobado contra producción el 2026-08-03, por cuatro huellas
independientes que coinciden:

| Lo que el SQL haría | Estado real hoy |
|---|---|
| Paso 3 · crear `asesores_backup_fusion_20260605` | la tabla no existe |
| Paso 4 · sacar la rama vieja de `obtener_mi_asesor()` | sigue leyendo `public.asesores` |
| Paso 5 · `ALTER TABLE perfiles DROP COLUMN asesor_id` | la columna sigue, con 4 clientes poblados |
| Paso 5 · borrar la tabla `asesores` | sigue viva, **10 filas** |

**La condición que el propio archivo ponía ya se cumplió:** los 5 clientes que
tenían de asesor al registro viejo fueron reasignados al perfil analista el
2026-06-14 03:27:48 UTC — está en `public.audit_log`, los cinco en la misma
operación, de `NULL` al perfil nuevo. Y el chequeo de seguridad del propio
guion (paso 2, «clientes legacy sin migrar») devuelve **0**: no hay nadie
colgado. Está en condiciones de correrse.

### Qué queda mientras tanto

- Una tabla `public.asesores` con 10 filas de datos de contacto de personas
  (nombre, correo, teléfono, WhatsApp) que ya no debería usar nadie. Dato
  personal vivo en una tabla sin dueño declarado.
- `public.obtener_mi_asesor()` es **`SECURITY DEFINER`** y todavía referencia
  esa tabla. Es la parte que más pesa: una función que corre con los permisos
  de quien la definió y lee una tabla que el modelo nuevo dio por muerta. No es
  un agujero conocido, pero es superficie que nadie está mirando.
- `perfiles.asesor_id` sigue existiendo con su FK. Cuatro clientes lo tienen
  poblado *además* de `asesor_perfil_id`: dos fuentes de verdad para el mismo
  hecho, y ninguna regla que las obligue a coincidir.

### Antes de correrlo

El SQL trae sus propias precondiciones en la cabecera (los 3 analistas creados,
los 5 clientes reasignados, el frontend y la edge desplegados). Las dos
primeras están cumplidas y verificadas; **las de despliegue no se comprobaron.**
Es reversible hasta el `DROP` final —el paso 3 respalda la tabla antes de
borrarla—, pero conviene decidirlo con calma y no en medio de otra cosa.

---

## 2. `public_html` es un gitlink roto

Apunta a `fb76307b151e478b0d5d80f86973cfb00913efc1`, objeto que no existe en
este repositorio, y **no hay `.gitmodules` en ninguna parte de la historia**. Ya
estaba roto antes de la mudanza; la mudanza sólo lo trasladó. Un clon limpio lo
arrastra igual.

## 3. La rama no está en `main`

La historia vive en `import-desde-monorepo`, no en `main`, porque el ruleset
`proteccion-main` es de **organización** y exige el check `verify`, que en un
repositorio vacío no puede correr nunca — ni por empuje ni por PR. La salida
acordada no es debilitar el ruleset sino que el repo plantilla nazca con
`verify.yml` adentro. Está anotado como bloqueante en el monorepo
(`docs/fase-3/pendientes.md`).
