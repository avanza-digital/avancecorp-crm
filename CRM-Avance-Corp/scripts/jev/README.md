# Jev para conducir una auditoría

Seis herramientas que usan **Jev** (TypeSafe) sobre el **texto de los hallazgos**
de una auditoría. Nacieron el 21/09/2026 para terminar la auditoría de
conversiones sin gastar ~750 agentes Opus en verificar 252 hallazgos.

**La frontera, que no se cruza:** Jev no juzga dinero, conversión, permisos ni
cierre de mes (decidido el 20/09, vault *Temperatura del lead*). Aquí lee
títulos, evidencia citada e impacto declarado. Los porcentajes los siguen
calculando SQL y la sonda de paridad.

## Qué funciona y qué no (medido el 21/09, no prometido)

| Herramienta | Estado | Medida |
|---|---|---|
| **Agrupar hallazgos repetidos** | ✅ úsala | Con confianza ≥ 0.80, las 12 agrupaciones revisadas a mano eran correctas. Por debajo aparecen los errores. De 252 pendientes, **26 son caras de C1–C8**. |
| **Selector de contexto (rerank)** | ✅ úsala | Pregunta con respuesta conocida y 8 extractos: los 2 que la contienen salieron 1.º y 2.º. |
| **Revisiones estancadas** | ✅ úsala | Dos hilos reales: el estancado dio `aporta_nuevo` 0.11 / `pide_lo_mismo` 0.79; el vivo, 0.63 / 0.11. |
| **Requisitos sin evidencia** | ⚠️ señal, no veredicto | **AUC 0.47** (azar) contra los 41 veredictos humanos. Con las reglas del negocio delante, 0.61. NO descarta nada. |
| **Selector de pruebas adversarias** | ❌ no la uses todavía | En 246 de 252 hallazgos la elección de lente no llegó a 0.80. La pregunta no discrimina con solo título + evidencia. |
| **Problema resuelto** | ⏳ sin medir | Escrita y probada en frío; falta el primer arreglo real para contrastarla. |

Por qué falla la que falla: casi todo lo que los verificadores humanos
refutaron el 21/09 se refutó **por negocio** («está decidido así»), y esa
decisión no está en el texto del hallazgo. Meter las reglas decididas en el
estado (`reglas.mjs`) sube el AUC de 0.47 a 0.61 — mejor que el azar, aún
insuficiente para cerrar un hallazgo. Decidir «¿esto es un defecto?» exige leer
el cuerpo entero de la función, y eso no cabe en el estado.

## Uso

```
node scripts/jev/auditor.mjs triaje    <hallazgos.json> [--salida f.json] [--paralelo 10] [--limite n]
node scripts/jev/auditor.mjs contexto  "<pregunta>" <extractos.json> [--corte 2]
node scripts/jev/auditor.mjs estancada <hilo.json>
node scripts/jev/auditor.mjs resuelto  <hallazgo.json> <cambio.json|diff.patch>
node scripts/jev/auditor.mjs calibrar  <triaje.json> <veredictos.tsv>
```

252 hallazgos tardan ~8 s con `--paralelo 10`. Ningún comando escribe en la
base ni en producción.

**La clave** se lee de `TYPESAFE_API_KEY` o de `~/.config/typesafe/key` (600).
Nunca viaja por argumento ni se imprime, ni siquiera en un error.
🔴 La key actual se pegó en un chat el 20/09: hay que rotarla.

## Volver a calibrar (obligatorio si cambian las preguntas o el modelo)

1. `docs/auditorias/conversion-2026-09-21/evidencia/jev/set-etiquetado.json`
   tiene 41 hallazgos con veredicto humano (≥ 2 de 3 lentes = sostenido).
2. Correr `triaje` sobre él y calcular el AUC contra `_humano_sostenido`.
3. Subir un umbral **solo** si la medida lo sostiene. Los de hoy
   (`UMBRALES` en `preguntas.mjs`) llevan su medición escrita al lado.

`npm run test:jev` prueba la política entera sin red ni clave.
