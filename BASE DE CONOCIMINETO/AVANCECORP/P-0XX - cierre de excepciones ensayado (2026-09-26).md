# P-0XX — cierre de excepciones ensayado

CRM y portal siguen publicados y Miguel confirmó que ve las cuentas del CRM
en el portal. El objetivo permanece abierto por tres diferencias históricas y
dos avisos adicionales del advisor. El PR documental #107 ya está integrado.

Miguel autorizó ensayar SECURITY INVOKER en las dos entradas de pantalla,
conservando los autorizadores privados como SECURITY DEFINER. También confirmó
el beneficiario corregido en la ficha del caso de titularidad. La pausa posterior
se revocó con «sigue»; ninguna de estas respuestas autoriza esta nueva ejecución
productiva ni la reparación excepcional de una celda bancaria legada.

## Ensayo del 26/09

Rama propia `p0xx-cuentas-unificadas-20260925` (`hhpjiygytwoayxymziqo`), con
datos ficticios. Migración `20260926145330_p0xx_cuentas_wrappers_invoker.sql`:
dos entradas INVOKER, guards privados DEFINER y hechos/tablas sin acceso API.
SQL y reversa PASS; HTTP dirigido 10 PASS; matriz contratos HTTP/RLS 287 PASS.
Desaparecen exactamente los dos avisos de P-0XX; cero hallazgos nuevos de
seguridad o rendimiento. El esquema private sigue fuera de la API.

Conciliación preparada: dos versiones nuevas por formato y titular confirmado;
propuesta de corregir un banco mal nombrado en el legado. Los dígitos y CCI se
conservan. Los contratos mantienen su cuenta histórica inmutable. El actor
propuesto es ADMINISTRADOR AVANCE CORP, con ledger y auditoría identificables.

El ensayo sintético termina en ROLLBACK: primera ejecución 2 versiones + 1
nombre de banco, repetición 0 + 0, reversa PASS. Un segundo caso que falla
revierte el primero; una cuenta usada en un contrato posterior impide revertir
la conciliación. Se conservaron todos los vínculos contractuales.

## Siguiente paso

Revisar y autorizar los SQL concretos de permisos y conciliación en producción,
incluida la excepción de una sola escritura bancaria en perfiles. Aplicar,
verificar cero diferencias válidas y cero avisos nuevos y actualizar reportes.
No hace falta reconstruir ni publicar el frontend para estos ajustes.

La revisión independiente no se completó: los dos intentos del wrapper de
Claude no devolvieron un VERDICT válido. No se presenta como PASS. La evidencia
de publicación anterior conserva su alcance; no se repitió el build frontend.

Acta: `CRM-Avance-Corp/supabase/scripts/p0xx/CIERRE-EXCEPCIONES.md`.
SQL productivo y evidencia nominal, privados:
`_DEV_NO_SUBIR/releases/p0xx-crm-publicado/`.

Relacionado: [[P-0XX - publicación y conciliación pendiente (2026-09-25)]],
[[Cuentas bancarias por contrato]], [[Cuentas bancarias - ledger vs casillas del perfil]].
