---
tags: [crm, rendimiento, cartera, f8]
actualizado: 2026-09-15
estado: medicion-terminada-optimizacion-pendiente
---

# Rendimiento ligero — Cartera y Hoy

Miguel autorizó una prueba breve. Al no haber navegador conectado, eligió expresamente **seguir con servidor y consultas**. No pidió implementar las correcciones en esta tarea.

## Resultado

39 invocaciones reales de los RPC/núcleos, sin errores SQL, con transacciones revertidas. Tres muestras principales por operación/rol: Cartera 1,249 s Gerencia / 0,320 s Vladimir; búsqueda «MARIA» 1,221 / 0,289 s; ficha 2,723 / 0,820 s (medianas). La búsqueda de Vladimir no tuvo coincidencias; una adicional «a» sí devolvió sus 21 personas en 0,295 s.

El contraste de **la misma persona** dio 2,722 s Gerencia / 0,840 s Analista. Cada respuesta tuvo una inversión y 2.072 bytes. Las consultas exploratorias que alimentan Hoy respondieron en 0,022–0,500 s, sin medir toda la pantalla.

El núcleo `private.cartera_f5_personas_visibles()` midió 1,216 s para las 492 personas de Gerencia. La ficha lo llama al entrar y al salir; el coste de generar el conjunto visible es una causa probable importante. No se ha desglosado todo el trabajo interno ni implementado una mejora.

## Límites

- Los tiempos son SQL: no incluyen red del usuario, login ni renderizado.
- Hostinger/hcdn exigió desafío JavaScript (403) a las tres peticiones de diagnóstico; no se midió la entrega del CRM ni se aumentó la carga HTTP. No demuestra una caída para usuarios.
- Dos llamadas enviadas juntas se ejecutaron sin solaparse en el servidor. **Concurrencia real y etapa de tres usuarios NOT RUN**. No afirmar capacidad para varios usuarios.
- Salud inicial/final sin esperas de locks ni transacciones inactivas. Cero sesiones de la prueba al terminar. Son cortes puntuales, sin monitoreo de CPU/memoria.
- La ficha puede mantener su bloqueo operativo real hasta el ROLLBACK. No se observaron las esperas de otros usuarios durante cada lote; los cortes finales no acreditan ausencia total de impacto. Futuras mediciones: una ficha por transacción o banco aislado.
- Sin cambios de datos económicos, configuración, esquema o producto. Sin nueva publicación ni cierre de G7/F8.

Informe, JSON saneado, método y revisión independiente:
`CRM-Avance-Corp/supabase/scripts/rendimiento-ligero/2026-09-15/`.

Claude devolvió `CHANGES_REQUESTED` sin P0/P1: coincidió con la prioridad de la ficha y pidió precisiones del informe. Se incorporaron límites de bloqueos, resumen completo/base explícitos, trazabilidad de sondas y alcance de la mejora. No hubo segunda revisión ni PASS final de Claude.

## Próxima mejora propuesta

Optimizar la lectura y comprobación individual **dentro del núcleo canónico**, manteniendo las comprobaciones actuales de permisos/fusiones/demo. Antes de publicar una futura solución, ensayarla en banco aislado, comprobar igualdad de respuestas/capacidades y repetir la medición. No eliminar la revalidación final ni introducir lectores financieros paralelos para ganar velocidad.

Relacionadas: [[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]], [[F8 - ensayo remoto y correccion de conflictos (2026-09-15)]], [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
