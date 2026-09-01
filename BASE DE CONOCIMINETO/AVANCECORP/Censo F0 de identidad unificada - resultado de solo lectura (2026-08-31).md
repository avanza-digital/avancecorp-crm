---
tags: [crm, inversionistas, identidad, censo, f0, produccion]
fecha: 2026-08-31
observado_en_lima: 2026-08-31 16:10:26
estado: ejecutado-solo-lectura-pendiente-de-decision-f1
---

# Censo F0 de identidad unificada — resultado de solo lectura (2026-08-31)

## Veredicto

El censo F0 autorizado por Miguel se ejecutó contra la base linked en una transacción con `transaction_read_only = on` y `ROLLBACK`. No creó tablas, no migró, no enlazó ni modificó datos.

La base es apta para preparar F1, pero F1 no debe aplicarse todavía. Antes hay que resolver una cola pequeña de excepciones y decidir el tratamiento del cierre cooperativo demo de S/100,000.

Resultado principal:

- **402 identidades documentales automáticas**: 392 clase A desde perfiles cliente y 10 clase B solo cooperativa.
- **2 claves documentales en revisión E** por coincidir también con perfiles de otro rol.
- **2 perfiles cliente adicionales en revisión E**: uno sin documento y uno con documento inválido.
- **Delta de conversión ponderada: 0** en los cuatro meses con episodios medidos.
- **Paridad de capital: 0 diferencias**, con 487 episodios antes y después del enriquecimiento.

## Evidencia y artefactos

- Consulta: `CRM-Avance-Corp/supabase/scripts/censo-f0-identidad-inversionistas.sql`
- Verificador: `CRM-Avance-Corp/supabase/scripts/verificar-censo-f0-identidad.mjs`
- Resultado agregado completo: `artifacts/censo-f0-identidad-inversionistas-2026-08-31.json`
- Verificador estático: 76 comprobaciones aprobadas.
- Núcleo `private.conversion_episodios`: huella viva coincide con el pin.
- Núcleo `private.capital_episodios`: huella viva coincide con el pin.
- Salida: 54 métricas agregadas, sin DNI, teléfonos, correos, nombres ni UUID individuales.

## Inventario observado

### Perfiles cliente

- 396 perfiles cliente activos.
- 394 con documento válido:
  - 385 DNI;
  - 8 CE;
  - 1 pasaporte.
- 1 sin documento.
- 1 con documento inválido.
- 2 claves de clientes también aparecen en perfiles de otro rol; quedan en revisión humana, no en backfill automático.
- 0 documentos repetidos entre múltiples perfiles cliente.
- 0 valores usados con tipos documentales distintos.

### Leads

- 831 leads totales.
- 636 oportunidades vivas en la foto final.
- 170 descartados.
- 25 convertidos:
  - 15 por Avance con perfil;
  - 10 por cooperativa sin perfil;
  - 0 huérfanos;
  - 0 con perfil y cierre externo simultáneamente.
- Existe 1 diferencia entre el DNI registrado en el lead y el documento heredado desde la fuente de conversión. El enlace por perfil/cierre sigue siendo inequívoco, pero la diferencia debe revisarse antes del backfill definitivo.

El conteo de leads cambió durante las corridas de revisión —de 637 a 636 vivos y de 169 a 170 descartados— por actividad normal concurrente del CRM. La foto canónica de este informe es la de las 16:10:26.

### Cooperativas

- Qorilazo: 8 cierres, 7 vigentes y 1 anulado.
- Prodelco: 2 cierres, ambos vigentes.
- 0 empresas inesperadas.
- Los 10 documentos cooperativos son DNI.
- No existe hoy ninguna convergencia documental entre un perfil Avance y un cierre cooperativo.

`crm.cierres_externos` no tiene `es_demo`. El cierre conocido de **S/100,000 DEMO** entra en el conteo histórico de episodios, pero está **anulado** y el núcleo le atribuye monto vigente cero.

### Errata F0.5 — 2026-08-31 17:36 Lima

La primera interpretación restó incorrectamente S/100,000 al stock vigente de Qorilazo. La cola individual F0.5 confirmó, sin exponer PII, que el candidato demo está anulado. Por tanto:

- Qorilazo vigente real observado por el núcleo: **S/305,800**.
- Prodelco vigente observado: **S/10,000**.
- Cooperativas vigentes observadas: **S/315,800**.
- El episodio demo anulado se conserva con monto de capital vigente **S/0**.

No corresponde restar S/100,000 de S/305,800. La deuda pendiente es marcar explícitamente demo/real para que el episodio histórico no se confunda visualmente, no corregir el capital vigente.

## Clases de backfill

| Clase | Resultado | Tratamiento |
|---|---:|---|
| A | 392 claves | Elegibles para identidad automática desde perfil cliente. |
| B | 10 claves | Elegibles para identidad automática externa, sin Portal. |
| C | 25 leads convertidos | 15 heredan perfil; 10 heredan cierre externo. |
| D | 0 leads | Ningún lead no convertido coincide hoy con una identidad DNI censada. |
| E | 2 claves + 2 perfiles documentales | Revisión humana; no crear/enlazar automáticamente. |
| F | 2 candidatos | Uno por teléfono y uno por nombre; solo señal débil, jamás unión automática. |

Además existen 5 leads con DNI válido pero sin una identidad ya censada. La identidad nacería al convertir; no se enlazan ahora.

## Responsabilidad y `no_contactar`

Sobre las 402 identidades automáticas:

- 397 tienen responsable potencial:
  - 388 desde el asesor del perfil;
  - 9 desde el vendedor del cierre externo vigente más reciente.
- 5 quedan sin responsable.
- 0 responsables detectados como inactivos.
- 0 conflictos perfil contra cierre.

Hay 4 leads con `no_contactar` que todavía no pueden vincularse a una identidad fuerte. No se encontró una identidad documental con veto y, simultáneamente, una oportunidad viva sin veto.

## Conversión mensual

Se comparó la regla viva con la regla propuesta de máximo una conversión por identidad y mes:

- factor de referido real por mes;
- primer episodio confirmado como ganador;
- ganador anulado sin suplente;
- clases E y episodios sin identidad fuerte excluidos de la deduplicación.

Resultado:

- 57.9 conversiones ponderadas bajo la regla viva.
- 57.9 bajo la regla por identidad/mes.
- **Delta total: 0.**
- 0 meses afectados.
- 0 combinaciones Avance + cooperativa de una misma identidad en el mismo mes.
- 0 combinaciones operación + otro episodio de una misma identidad en el mismo mes.
- 2 episodios de agosto todavía no tienen identidad documental resoluble; conservan su aporte actual hasta revisión y no producen deduplicación.

Por tanto, con los datos resolubles actuales, la nueva dimensión no modifica ninguna cifra de conversión. Esto no sustituye el oráculo de F3: debe repetirse justo antes de publicar porque los datos son vivos.

## Capital

El núcleo devolvió 487 episodios. El enriquecimiento con empresa e identidad simulada también devolvió 487:

- diferencia de filas: 0;
- diferencia de monto: 0;
- cardinalidad 1:1: aprobada.

Totales observados, sin mezclar monedas:

| Empresa | Episodios | PEN stock | USD stock | PEN nulo/anulado |
|---|---:|---:|---:|---:|
| Avance | 477 | 18,270,913.12 | 996,443.33 | 0 |
| Qorilazo | 8 | 305,800.00 | 0 | 0 en 1 episodio anulado |
| Prodelco | 2 | 10,000.00 | 0 | 0 |

Hay 2 episodios Avance sin identidad documental resoluble:

- S/100,000;
- US$10,000.

No se suman entre sí. Deben mapearse a los dos perfiles documentales pendientes antes de hacer obligatorio el vínculo.

La paridad medida es de enriquecimiento F0. No afirma que una función futura de F3 ya exista o esté probada.

## Gate antes de F1

Preparar F1 solo después de producir una cola de revisión, sin PII en el reporte ejecutivo, para:

1. perfil cliente sin documento;
2. perfil cliente con documento inválido;
3. dos claves cliente que también existen en perfiles de otro rol;
4. cinco identidades automáticas sin responsable potencial;
5. cuatro vetos `no_contactar` sin identidad fuerte;
6. un lead convertido cuyo DNI difiere de la fuente heredada;
7. dos episodios de conversión sin identidad resoluble;
8. dos episodios de capital Avance sin identidad resoluble;
9. decisión sobre cómo excluir o marcar el cierre cooperativo demo de S/100,000.

Después de resolver o acordar el tratamiento de esa cola, corresponde diseñar la migración F1 y sus pruebas, pero mostrar el SQL a Miguel antes de aplicar cualquier cambio.

## Relacionadas

- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]]
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Inicio]]
