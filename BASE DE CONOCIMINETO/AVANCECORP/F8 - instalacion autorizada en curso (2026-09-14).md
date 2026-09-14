---
tags: [crm, multiempresa, f8, instalacion]
actualizado: 2026-09-14
---

# F8 — instalación autorizada en curso

**Estado posterior: pausada por Miguel; rama propia eliminada.** Punto vigente:
[[F8 - pausa segura de instalacion (2026-09-14)]]. Lo siguiente conserva el
registro de autorización y del inicio del ensayo.

Miguel respondió «siii» a la presentación de los dos SQL exactos y la pregunta
de probarlos en rama aislada e instalarlos manteniendo F8 apagada si pasan los
controles. **La aprobación ya está recibida; no volver a pedirla** para estas
versiones. Continúa [[F8 - instalacion apagada preparada (2026-09-13)]].

- Control: `20260913215240_crm_f8_piloto_controlado.sql`, SHA-256
  `0807e59bcaccfbce8d7af02dc67fcfa8a64686305aaa976d4840af16c86c18fe`.
- Exclusión demo: `20260914025926_crm_f8_excluir_fuentes_demo.sql`, SHA-256
  `0f7daa10f1e1ac1d71501795d0f0d45c64e58fa263426c7e27a56f5c0e73dc08`.
- Coste confirmado vigente: US$0,01344/h, igual al autorizado. Rama exclusiva
  `multiempresa-f8-instalacion-20260913`, ref `nyfufsyrtukwhbaezley`, ID
  `cf0f8eb1-1930-47f2-b81a-f8e8e46b54af`, creada el 14/09 a las 04:48:46 UTC.
- El replay volvió a detenerse tras 86 migraciones, última `20260811210049`.
  El padre tiene 279. Se prepara la reconstrucción equivalente sin copiar
  clientes ni movimientos reales. Los dos jobs Cron de la rama se desactivaron.

Estado en este punto: **ensayo en curso; F8 todavía no instalada en producción**.
No configurar miembros ni encender el piloto con esta autorización. No repetir
el lote de siete personas/diez enlaces reales ya aplicado.

Trabajo: `/private/tmp/avancecorp-f5-publicacion`, rama `codex/f8-piloto`.
Preparación guardada y respaldada: commit `53c4e58`. Archivos temporales del
ensayo en `/private/tmp/avancecorp-f8-instalacion-20260913/` (0700; accesos 0600).
No imprimir credenciales ni subir ese directorio a Git. La CLI usa un acceso
temporal de lectura al padre: seleccionar explícitamente `--role=postgres`
para pg_dump y renovar su caducidad antes de una nueva conexión si hace falta.

Sigue el procedimiento de instalación versionado: reconstrucción/paridad,
pruebas SQL y Auth/Data API, advisors, revisión de evidencia nueva, Main único
verificado, merge exclusivo con el resto conservado, comprobación posterior y
eliminación de la rama temporal. Las otras ramas no pertenecen a F8.

Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
