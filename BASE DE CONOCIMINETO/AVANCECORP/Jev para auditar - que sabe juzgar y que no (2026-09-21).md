---
tags: [auditoria, jev, typesafe, conversion, herramientas]
fecha: 2026-09-21
---

# Jev para auditar: qué sabe juzgar y qué no (21/09/2026)

Miguel pidió terminar la [[Auditoria de conversiones - capas backend a frontend (2026-09-21)|auditoría
de conversiones]] apoyándose en **Jev** (TypeSafe) para seis papeles: elegir la
prueba adversarial, detectar requisitos sin evidencia, agrupar hallazgos
repetidos, elegir el contexto del auditor, detectar revisiones estancadas y
revisar si un problema quedó resuelto. Quedaban 252 hallazgos sin verificar y
terminarlos con agentes costaba ~750 agentes Opus.

La herramienta vive en `CRM-Avance-Corp/scripts/jev/` (`npm run test:jev`, ya
dentro de `check:scripts`). Lo que sigue es lo **medido**, no lo prometido.

## La frontera se respetó

Igual que en [[Temperatura del lead - señal de TypeSafe para ordenar Mi dia (2026-09-20)|temperatura
del lead]]: **Jev no juzga dinero, conversión, permisos ni cierre de mes**. Aquí
solo lee el TEXTO de los hallazgos —título, evidencia citada, impacto
declarado— y nunca una cifra del negocio. Los porcentajes los siguieron
calculando SQL y la sonda.

## Tres papeles funcionan, dos no, uno sin medir

| Papel | Veredicto | Cómo se midió |
|---|---|---|
| **Agrupar repetidos** | ✅ con confianza ≥ **0.80** | Las 12 agrupaciones con esa confianza, revisadas a mano, eran correctas. De 252 pendientes, **26 resultaron caras de C1–C8**. |
| **Elegir contexto (rerank)** | ✅ | Pregunta con respuesta conocida y 8 extractos: los 2 que la contenían salieron 1.º y 2.º. |
| **Revisión estancada** | ✅ | Dos hilos reales: el estancado (C3, 5 rondas repitiendo) dio `aporta_nuevo` 0.11; el vivo (C2, con contraejemplo nuevo), 0.63. |
| **Requisitos sin evidencia** | ⚠️ señal, nunca veredicto | **AUC 0.47 — azar** contra los 41 veredictos humanos. |
| **Elegir la prueba adversarial** | ❌ no sirve hoy | En 246 de 252 la elección de lente no llegó a 0.80. |
| **Problema resuelto** | ⏳ sin medir | Falta el primer arreglo real. |

## La lección que vale más que la herramienta

**Lo que los humanos refutaron, lo refutaron por NEGOCIO, no por código.** De
los 41 hallazgos con veredicto, 26 cayeron porque «eso está decidido así»: el
referido pesa 0.15, el mes calendario manda sobre el rango, la cosecha es otra
pregunta con su propio rótulo. Ninguna de esas decisiones estaba en el texto
del hallazgo, así que el modelo no podía saberlas: por eso la pregunta por la
evidencia salió al azar.

Metiendo las reglas decididas en el estado (`scripts/jev/reglas.mjs`) el AUC
sube de **0.47 a 0.61**: mejor que el azar, insuficiente para cerrar nada. La
conclusión es dura y útil: **decidir «¿esto es un defecto?» exige leer el cuerpo
entero de la función**, y eso no cabe en el estado de una pregunta. Jev sirve
para **ordenar, agrupar y enrutar** una auditoría, no para dictar su veredicto.

Corolario práctico: el catálogo de reglas decididas es, él solo, un activo. Es
lo que le faltaba a cada revisor nuevo —humano, Codex o modelo— para no volver
a levantar por tercera vez un hallazgo que ya se cerró.

## Umbral medido ≠ umbral del manual

El manual de TypeSafe propone 0.8 / 0.2 para los Noul y no fija uno para la
confianza de un Choice. Aquí el umbral de agrupación es **0.80**: a 0.60 se
colaron errores claros («un mes sin metas publicadas no se puede sellar nunca»
agrupado como C1 con 0.60, que es otro defecto distinto). Y la primera regla
de «revisión estancada» era demasiado estricta: exigía además `pide_lo_mismo ≥
0.8` y dejó pasar el hilo estancado por una centésima (0.79). Las dos correcciones
salieron de medir, no de discutir. Todo umbral lleva su medición escrita al lado
en `preguntas.mjs`; si cambian las preguntas o el modelo, se vuelve a medir.

## Velocidad

252 hallazgos triados en **7.9 s** (`--paralelo 10`); los 41 del set etiquetado,
en 2.9 s. El 21/09, esos mismos 41 costaron ~1 hora de agentes Opus.

## Deuda

🔴 **Rotar la key de TypeSafe**: se pegó en un chat el 20/09. La herramienta la
lee de `~/.config/typesafe/key` (600) o de `TYPESAFE_API_KEY`, nunca por
argumento y nunca la imprime, ni en un error.

Relacionado: [[Auditoria de conversiones - capas backend a frontend (2026-09-21)]] ·
[[Temperatura del lead - señal de TypeSafe para ordenar Mi dia (2026-09-20)]] ·
[[Conversion mensual - definicion cerrada]]
