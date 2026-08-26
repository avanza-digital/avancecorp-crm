# Dos ramas paralelas del CRM — la integración pendiente

**Descubierto el 2026-08-26** al intentar publicar el front. Es un problema de
organización del trabajo, no de código, y va a seguir mordiendo hasta que se
resuelva.

Relacionado: [[Los dos numeros del lead - del origen al CRM]]

---

## El hecho

Lo que está VIVO en producción (`b3f6e98`, el 38.º release, del 25/08) **no es
antepasado** de la rama en la que se trabaja (`wip/workspace-20260823-completo`).
Son dos historias paralelas.

```
git merge-base --is-ancestor b3f6e98 <rama de trabajo>   →  falso
```

Construir y publicar el front desde la rama de trabajo **borraría de producción**
los 15 commits que solo existen en el release: todo el «Hoy del supervisor»
F1–F4.4, la jornada del vendedor y la paginación de Derivar.

Ese control (paso 2 del procedimiento de deploy, en [[Deploy a Hostinger]]) es lo
único que lo impidió. Sin él se habría publicado.

## Por qué la integración NO es mecánica

El merge da **14 ficheros en conflicto**, y la mitad son las MISMAS pantallas
reescritas por los dos lados:

| Fichero | Cambió en la rama de trabajo | Cambió en el release vivo |
|---|---|---|
| `hoy/vendedor.tsx` | 684+ / 287− | 444+ / 132− |
| `hoy/supervisor.tsx` | 58+ / 102− | 387+ / 219− |
| `supervisor.test.tsx` | 101+ / 9− | 592+ / 15− |
| `derivaciones.tsx` | 80+ / 56− | 36+ / 12− |
| `test-rls.mjs` | 526+ | 547+ |

No es «quedarse con lo de uno». **Cada rama tiene una parte de las mismas
funciones y le falta la otra.** Medido por las señales visibles del vendedor:

| Señal | Rama de trabajo | Release vivo |
|---|---|---|
| «Tu siguiente movimiento» | ✅ | ✅ |
| «Después en tu agenda» | ✅ | ✅ |
| «Tu cartera en contexto» | ✅ | ✅ |
| **«Hoy, tres cosas»** | ❌ | ✅ |
| **«Nuevo aquí»** | ❌ | ✅ |

Resolver a mano 313 líneas en conflicto de `vendedor.tsx` entre dos
implementaciones parciales de la misma pantalla es la forma más probable de
quitarle en silencio una función a los vendedores que hoy la están usando.

## La decisión de Miguel (2026-08-26)

**No se integra a ciegas.** Se para aquí, no se publica el front, y la
integración se hace cuando termine el trabajo en curso de la otra sesión — con
quien conozca las dos implementaciones delante.

## Lo que SÍ está en producción y no depende de esto

Todo el servidor de «los dos números del lead»: el CHECK que acepta fijos e
internacionales, la columna cruda, la página de la cartera y el conector. Se
publicaron por su cuenta porque no pasan por el bundle del front.

## Para quien retome esto

1. El orden correcto es **integrar primero, construir después**. Nunca al revés.
2. El worktree de release se monta con `git worktree add --detach <ruta> <commit>`
   y hay que **copiar `app/.env` dentro** o el login de producción se apaga
   (lección de [[codigo-retomar-47]]).
3. El control de ascendencia del paso 2 del deploy **no es burocracia**: es lo
   que evitó borrar el trabajo de un mes.
