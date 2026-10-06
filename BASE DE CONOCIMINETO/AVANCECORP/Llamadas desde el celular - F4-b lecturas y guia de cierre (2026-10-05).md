---
tags: [crm, llamadas-celular, f4b, decisiones]
fecha: 2026-10-05
---
# Llamadas desde el celular - F4-b lecturas y guía de cierre (2026-10-05)

F4-b es la pantalla del analista para las llamadas del celular: la pestaña «Celular», «Qué pasó hoy» y la marca
«Celular» en «¿Qué hice hoy?». Todo está escrito y **sin aplicar**; nada llega a producción hasta que Miguel cierre
el #190.

## Dónde está cada cosa
- **#190**: las siete migraciones, la Edge, el gate y las guías. Lo cierra Miguel en su banco.
- **#193**: parte A de F4-b. El id de la llamada viaja del enlace de la macro hasta la encuesta. Solo pantalla.
- **#195**: la octava (`20261005201010`, dos lecturas) y la novena (`20261005224330`, la enmienda), apiladas sobre el #190.
- **#197** (borrador): la pestaña «Celular», apilada sobre el #193. Solo funciona en la demo hasta tener los tipos.
- **Guía ejecutable para el agente de Miguel**: `CRM-Avance-Corp/docs/plans/llamadas-celular/CIERRE-PARA-EL-AGENTE-DE-MIGUEL.md`.
  Dice qué correr, en qué orden y qué contestar en el PR. Se escribió porque el ida y vuelta de comentarios no cerraba.

## Decisiones de Jhosep (05/10)
- **La v5 solo cuando la encuesta trae el id** de la llamada; sin id, la v4 de siempre.
- **La marca «Celular» va en una puerta aparte**: no se cambia `registro_actividad_fn`, que usan otras pantallas.
- **«Qué pasó hoy» = lo RESUELTO hoy en Lima**, aunque la llamada sea de ayer. Una registrada cuenta desde la hora del
  enlace; una descartada, desde la hora del descarte. La cifra del día no cambia: cuenta por la fecha del resultado.
- **Paginar como la bandeja**, `{filas, siguiente}`, con dos índices.
- **Registrada ayer, deshecha y corregida hoy: cuenta hoy.** Si se deshace y no se corrige, no sale en ninguna lista.
  Es un límite anotado: la marca y el historial sí la muestran.
- **Instalar no es activar**: en producción se aplican las migraciones y la Edge, pero C1 no se da de alta hasta
  F4-b + F4-d.

## Lecciones
- **«Hoy» siempre es ambiguo: hay que decir hoy de QUÉ.** La octava medía lo recibido hoy. Miguel lo detectó: una
  llamada de ayer resuelta hoy no salía en ninguna lista.
- **El cursor de una página se devuelve tal cual, como texto.** La base guarda microsegundos y JavaScript milisegundos:
  pasarlo por `Date` salta filas empatadas.
- **Una migración commiteada no se edita**: la revisión de la octava se resolvió con una novena que retira la firma
  vieja (dos firmas con el mismo nombre confunden a PostgREST).

## Relacionado
- [[Llamadas desde el celular - quinta, F4-a y Edge (2026-10-05)]]
- [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]]
- Plan: `CRM-Avance-Corp/docs/plans/llamadas-celular/F4B-PLAN-CORTO.md`. Ledger: `supabase/migrations/MIGRACIONES.md`.
