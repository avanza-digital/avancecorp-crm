---
tags: [crm, contratos, pdf, mancomunadas, retomar]
fecha: 2026-09-14
actualizado: 2026-09-14T20:30:00-05:00
estado: construida-pendiente-de-aprobacion-y-publicacion
---

# Plantilla v9 del PDF — los co-titulares salen en el contrato

**Pedido de Miguel (14/09/2026):** cuando la cuenta es mancomunada, el contrato debe nombrar a
las dos personas y llevar la firma de las dos al final. Anula la decisión de julio de conservar
los co-titulares solo en el CRM («por decisión legal no aparecen en el PDF»).

## Decisiones de Miguel (14/09)

1. Del co-titular salen **solo nombre y documento** (es lo que se guarda; el domicilio y el correo
   del contrato siguen siendo los del titular principal).
2. **Solo contratos nuevos.** Los 17 PDF ya sellados de contratos mancomunados no se tocan: un PDF
   sellado es un documento cerrado y el sistema garantiza que se descarga byte a byte como se firmó.
   Si algún día se quiere el co-titular en uno de esos, es una corrección formal por contrato.
3. **Firmas:** primera fila igual que hoy (titular principal + Avance Corp); debajo, una línea de
   firma por co-titular, con nombre, documento y el rótulo **EL ASOCIADO**, de dos en dos.

## Qué cambia en el documento

- **Comparecencia** (primer párrafo tras «de la otra parte;»): «**NOMBRE**, con **DNI N° X** y con
  domicilio en **DOMICILIO**; y **NOMBRE CO-TITULAR**, con **DNI N° Y**, quienes actúan de manera
  conjunta y a quienes se les denominará EL ASOCIADO, bajo los términos y condiciones siguientes:».
  No se afirma ningún domicilio del co-titular (no lo tenemos) y la cláusula 14.1 sigue siendo cierta.
- **Firmas**: un solo bloque indivisible; con 1 co-titular el contrato sigue en 8 hojas, con 5 (tope
  del CRM) pasa a 9.
- **Sin co-titular no cambia nada**: idéntico a la v8 píxel a píxel (8/8 hojas) y en texto (22 233
  caracteres, mismo hash).

## Por qué es una versión nueva

Cada PDF se sella con su versión de plantilla y el sistema promete «misma versión ⇒ mismos bytes».
Todo cambio visible sube la versión (v9 = `contrato-aep-17-v9`) con su migración
(`20260915005752`), su registrador, su reversa y su banco de ensayo, siguiendo la receta de la
[[Bug de plazo contractual en PDF por fin de mes (2026-09-01)|v7]] y de la v8. Los datos ya
viajaban: el snapshot del PDF lleva `cotitulares` desde la v2; solo la plantilla los ignoraba.

## Estado

- **Construida y ensayada el 14/09** (edge 52/52, front 29/29 + typecheck, banco local 45/45,
  registrador y reversa probados). **Nada publicado.**
- **Compuerta**: muestras en PDF (con y sin co-titular, datos ficticios) enviadas a Miguel; por la
  regla del 07/09 ([[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]]) hace falta
  su aprobación del texto y la ubicación antes de publicar.
- **Publicación** (con su `!`, en ventana muerta): edge → migración → registrador → front. Después:
  el contrato mancomunado que hoy tiene el PDF pendiente sale con los dos titulares; los sellados
  antiguos se siguen descargando iguales.

## Foto de producción el 14/09

19 contratos mancomunados, todos con exactamente 1 co-titular; 8 del régimen nuevo; 17 con PDF
sellado (v2 a v8) y 1 con reserva pendiente. Ningún co-titular coincide con su titular principal.

## Trampas cazadas

- `supabase functions download` devuelve código transpilado: no sirve para contrastar la edge viva
  por hash. Se usó la API de gestión (`/functions/<slug>/body`, multipart) y los 9 módulos vivos
  eran byte a byte iguales a HEAD.
- La copia mecánica de la migración (v7→v8, v8→v9) pierde la v7 de las listas de los CHECK y deja al
  oráculo con una «versión inventada» (v9) que ya es válida.
- El fixture demo del CRM listaba a la titular principal también como co-titular: habría impreso a
  la misma persona dos veces.

Relacionadas: [[Cuentas mancomunadas]] · [[PDF de contrato (generador) — plan]] · [[Inicio]]
