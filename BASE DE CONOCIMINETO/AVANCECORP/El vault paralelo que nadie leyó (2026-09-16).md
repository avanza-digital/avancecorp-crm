---
tags: [vault, conocimiento, repo, higiene]
actualizado: 2026-09-16
---

# El vault paralelo que nadie leyó (2026-09-16)

Revisando qué sobraba en el repo del CRM aparecieron **17 notas en
`CRM-Avance-Corp/BASE DE CONOCIMINETO/AVANCECORP/`** — un segundo vault creado en agosto
dentro del subproyecto. **16 no existían en el vault real.** No eran copias sobrantes: era
conocimiento que nunca se leyó, porque Obsidian solo abre la carpeta de la raíz.

Entre lo rescatado: el asiento de Operaciones del Portal, el régimen documental del contrato,
el puente de Analista Portal→CRM, el centro de rescate de descartes, la meta de conversión
predeterminada y el plan del motor de búsqueda de ayuda del vendedor.

## La decisión que importó

Una sola nota colisionaba de nombre: «Configuración operativa CRM 2026-08-07». **No era un
duplicado.** La de la raíz cuenta lo que quedó desplegado el 08/08; la del CRM son las
decisiones previas del 07/08 (quién administra qué, Superadmin Portal vs Gerencia, el SLA
versionado por ciclo) y dice explícitamente «no se aplicó ni desplegó nada en producción».
Dos hechos distintos del mismo tema. Entró como
«Configuración operativa CRM — decisiones (2026-08-07).md» sin tocar la original.

> Ante una colisión de nombre en el vault, comparar contenido antes de pisar. Puede ser otro
> hecho, no otra versión.

## Sobre adelgazar el repo

Borrar archivos del HEAD **no libera nada**: la historia conserva los blobs. Solo se limpiaría
reescribiendo historia, y eso exige force push sobre `avancecorp/main`, que está prohibido
(ver [[Dos ramas paralelas del CRM - la integracion pendiente]]). Lo que sí funcionó fue
`git gc --prune=now`: **`.git` pasó de 242 MB a 100 MB** sin tocar un solo archivo ni la
historia, y es puramente local — GitHub no cambia. El pack real siempre fueron ~45 MB; el
resto eran 9 112 objetos sueltos sin compactar.

Se borraron además 8 archivos sueltos de la raíz (5 capturas y 3 HTML de propuesta) con cero
referencias en todo el repo. Por higiene de la raíz, no por espacio.

Todo en el commit `b988006`, ya en `avancecorp/main`.

## Regla

Toda nota nueva va a `BASE DE CONOCIMINETO/AVANCECORP/` y a ningún otro sitio. Si algún script
o skill escribe notas, comprobar a qué ruta apunta: esto se descubrió por accidente, un mes
tarde. Relacionado con [[Inicio]].
