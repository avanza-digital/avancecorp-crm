# F4.1 — Evaluación y decisión de no activación

24/09/2026. **Decisión: conservar TypeSafe apagado y continuar F5.** Se cierra
la evaluación disponible con el resultado de no activación admitido en el
[plan de ejecución](../EJECUCION-F4-1-F6-2026-09-24.md). No se declara una
integración productiva terminada ni utilidad comercial demostrada.

## Evidencia y alcance

Reanálisis del [ensayo conservado del 21/09](ensayo-aislado-2026-09-21.json):
20 casos sintéticos, Jev `jev-1.13.0`, referencia escrita por Codex, sin etiquetas
humanas independientes ni resultados por equipo. No se enviaron datos reales del
CRM. Este reanálisis no llama al proveedor ni lee claves. La conformidad manual
cerrada por Miguel no cambia la naturaleza de esta evidencia.

| Medida | Resultado | Intervalo Wilson 95 % |
|---|---:|---:|
| Coincidencia con la referencia sintética | 19/20 · 95 % | 76,39–99,11 % |
| Precisión de las alertas | 9/10 · 90 % | 59,58–98,21 % |
| Contradicciones detectadas | 9/9 · 100 % | 70,09–100 % |
| Falsas alertas entre negativos | 1/11 · 9,09 % | 1,62–37,74 % |
| Contradicciones omitidas | 0 | Muestra de 9 positivos |

Los intervalos describen la incertidumbre de esta muestra; no permiten
generalizar a notas reales seleccionadas de otra manera. La falsa alerta `c04`
clasificó información insuficiente como posible contradicción. No se cambió el
umbral para esconder este error. El 9,09 % supera el criterio **provisional** de
5 % de falsas alertas y la muestra no alcanza el tamaño por equipo propuesto.

Latencia conservada por caso: p50 **948 ms**, p95 **1.031 ms**, máximo **1.079 ms**;
lote **4.601 ms**. Cuantiles por rango más próximo; no es una prueba de carga ni
una medición nueva del servicio.

Con 12.328 tokens de entrada y 1.102 de salida, el coste referencial del lote es
**USD 0,000517776** y por caso **USD 0,0000258888**, usando USD 0,042 por millón de
tokens de entrada y salida gratuita de la [documentación del proveedor](https://docs.typesafe.ai/models),
consultada el 24/09. Es una estimación a esa tarifa, no una factura ni prueba del
precio cobrado el 21/09.

## Condiciones para reabrir la activación

- Referencia independiente válida por equipo, con ajuste y validación separados
  por lead, y calidad medida sobre el conjunto reservado.
- Rotación acreditada de la credencial previamente expuesta; ejecución solo en
  servidor. No se reutilizó ni se imprimió esa credencial.
- Minimización, conservación y condiciones de transferencia resueltas antes de
  enviar notas reales; no se presupone retención cero por usar la API.
- Verificación de permisos, revocación, caché obsoleta, reintentos y caída del
  proveedor cuando exista una integración candidata.

## Reproducción y estado

Desde `CRM-Avance-Corp`:

```sh
node scripts/gestion-diaria-typesafe/auditar-ensayo.mjs
npm run test:gestion-diaria-typesafe
```

El primer comando recalcula la [evidencia JSON](evaluacion-f41-2026-09-24.json),
incluido SHA-256 del ensayo original, matriz completa y denominadores.

- **PASS:** reanálisis sin red; sumas, clases, unicidad y denominadores comprobados.
- **PASS:** 38 pruebas existentes del piloto, 0 fallos, ejecutadas el 24/09.
- **NOT RUN:** validación independiente con notas reales por equipo; no existe
  una referencia válida ni están resueltas las condiciones anteriores.
- **NOT RUN:** integración y activación productivas; decisión explícita de
  mantener la función apagada. No bloquea F5.
