# Publicación de tasa del upgrade — 07/10/2026

Publicación autorizada por el usuario: «publiquemos» y «Sí, probar y publicar».
Se confirmó la rama temporal a US$0,01344/h y su eliminación al terminar.

Estado de este commit: candidato probado; despliegue aún pendiente del cierre
de la matriz RLS y la suite E2E completa. El acta se actualizará con el resultado
real, el commit publicado y la verificación de los archivos servidos.

## Candidato

- Main integrado con `avancecorp/main` en `0bc837bb`.
- Migración única: `20261007180108_crm_upgrade_tasa_flexible.sql`.
- SHA-256: `725975473de374c3159ae5795a443418cd1a24f5c1c43f6c871f8f16255bd2b0`.
- Rama de ensayo: `upgrade-tasa-20261007` (`ezemlzywbtzrbunsbeza`).
- Las 436 migraciones previas se conservaron literalmente. El único SQL nuevo
  registrado coincide con el archivo probado.
- `npm run check`: PASS, 6.364 tests; `test.sql` remoto: PASS con rollback.
- Respaldo vivo: `crm-20261007T152928Z-e511d30504f2.zip` y su manifiesto.

La configuración productiva sigue en observación, solicitudes desactivadas.
El cambio no activa enforcement ni modifica los contratos anteriores.
