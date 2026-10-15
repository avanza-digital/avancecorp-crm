# Formulario 3 — fase 4: publicación en preparación

Fecha local 14/10/2026. Codex PRIMARY. **Aún no publicado**. La fase deja el CRM listo para una importación controlada posterior; no carga filas reales ni activa n8n.

## Fuente y comprobaciones

Preparación en copia local aislada `/private/tmp/formulario3-fase4-publicacion`, rama `main` siguiendo `avancecorp/main`. Se preserva el árbol original con trabajo ajeno. Base integrada inicial `2cf798a2ff6df438afeac86eea842436153c3eee`. Las 44 huellas de fases 1–2 coinciden con lo probado en fase 3. El build vivo previo es `build-20261014T031546721Z`, commit `e791502ff6961a9ef71b434bdb50a1748e744331`; ZIP y manifiesto de recuperación conservados.

Checks: app 420 archivos/6.707 tests con lint, tipos y build; scripts; preflights Edge, seed y RLS; 3 E2E específicos en Docker local; 25 pruebas n8n; 6 del gate SQL. Detalle y límites en `verificacion.json` y logs. Los preflights seed/RLS usan valores ficticios offline y no equivalen a sesiones de producción.

El verificador incorpora dos consultas administrativas opcionales de solo lectura, con referencia explícita igual a SUPABASE_URL y timeout acotado; no amplía permisos de negocio. Diez mediciones completas: **exit 0 sin `--estricto`**, dos divergencias preexistentes; modo estricto daría 1. Sello 0 y conversión 6,3 % en cinco caminos. El FAIL original de fase 3 permanece intacto. Criterio y resolución de Claude: `revision-resolucion.md`.

## Rama autorizada

Miguel autorizó crear y retirar `formulario3-fase4-20261014`, US$0,01344/h. Primer intento vacío `weghjrfzvyobcmbzllwy` falló al reproducir el historial anterior y fue eliminado. Reemplazo como copia actual en la misma organización: `oemmpccapplmiygcpvxr`, ID `e21928a2-725f-4f9a-aeaa-f749a0c69185`. Sus 12 tareas programadas quedaron desactivadas. Se aplicaron únicamente las dos migraciones ensayadas; 98 pruebas SQL y 18 HTTP pasaron. Las 476 migraciones anteriores y 23 funciones Edge son idénticas al padre. Se retirará al concluir. Las otras ramas no se modifican.

## Condiciones de publicación y recuperación

1. Verificar nuevamente huellas vivas y que el diff de migraciones de rama sea exclusivamente Formulario 3.
2. Repetir contratos/permisos, compatibilidad y advisors en la rama; mantener fixtures fuera de producción.
3. Publicar base y comprobar columna/grants, firma única de cartera con 15 argumentos y lectura PostgREST; después Edge y por último frontend.
4. Construir desde Main limpio e igual al remoto; ejecutar `release:crm`, verificar manifiesto y preflight obligatorio que exige contener el commit vivo.
5. Comprobar versión y assets HTTP, más lecturas de API. Conservar esquema aditivo e historial al recuperar frontend. No ejecutar una reversa de SQL automática.

## n8n y privacidad

Principal `BjI5m1PKVWhO0NDb`, versión `29940eb5-d36c-49c7-bf7f-686b66cc3f76`: inactivo, envío falso y HTTP deshabilitado; credencial original `YNRHr2PjhfLXnKff`. Aviso productivo manual **52 PASS**: Gmail confirmó envío a Miguel. Esto no es una importación ni sustituye la prueba automática de fase 3.

Política operativa: no conservar contenido de ejecuciones correctas y limitar a **7 días** el de ejecuciones fallidas. El ajuste efectivo de poda del VPS aún no está comprobado; deberá verificarse antes de la primera fila real, o deshabilitar el guardado de contenido fallido. No se presenta el valor por defecto como configuración confirmada. Los recibos de importación se conservan para evitar reprocesados; no se vacían con la poda de ejecuciones.

[Plan visual en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34). Publicación, primera fila y activación son estados distintos.

Compatibilidad del ZIP anterior: dos E2E con sesiones reales de Vendedor y Gerencia pasaron en Docker contra la rama nueva (Cartera, ficha, Pipeline). Se corrigió únicamente el cierre del proxy de pruebas; no se modificó el ZIP. Los logs originales conservan sus espacios de formato y los 44 archivos ensayados conservan sus bytes. El diff de código actual supera la comprobación de espacios.
