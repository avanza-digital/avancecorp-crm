# F8 — mejoras publicadas y punto de retoma

Continúa [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]] y [[F8 - piloto nominal activado (2026-09-14)]].

**Publicado y verificado.** Cartera, Ficha 360 y plazo/rentabilidad anual manual COOPAC están en el CRM. Commit de producto `95804fc`, build `build-20260915T021656174Z`. La publicación conservó el PDF v9 aprobado en otra tarea. No se calculan comisiones.

La prueba HTTP detectó un bloqueo al confirmar/corregir una revisión antigua: PostgREST 14.5 reintentaba 40001 indefinidamente. La migración `20260915015315` cambia cuatro rechazos de negocio a PT409. Las revisiones obsoletas responden HTTP409 en unos 160–175 ms. Claude PASS; dos confirmaciones simultáneas producen una sola inversión.

Tres migraciones publicadas, 291 entradas en total y las 288 anteriores intactas. Fuente `20260914213634` → registro `20260915010349`; fuente `20260914213928` → `20260915010350`; corrección `20260915015315` conserva versión. 645 funciones/ACL iguales al banco, siete huellas de datos y control nominal intactos.

3.582 pruebas frontend PASS, ensayos específicos SQL/Auth/Storage y comprobación productiva de Cartera/ficha en los cuatro roles (1,1–3,9 segundos mediante SQL con ROLLBACK). HTTP verificó 92 archivos; once PNG son optimizados por CDN. No había navegador conectado para revisión visual nueva.

La rama propia fue eliminada y confirmada ausente el 15/09 a las 02:26:51 UTC (14/09, 21:26 Lima). Sus credenciales temporales están retiradas. Los dos bancos de esta entrega costaron aproximadamente US$0,04 en total, dentro del máximo US$1. No se tocó banco-f7.

**Retoma:** revisar con Miguel la ficha del cliente real del piloto y sus observaciones. G7-R01 tiene corrección técnica publicada; siguen pendientes el recorrido visual real y conformidad G7. La ventana nominal termina el 21/09 a las 13:23 Lima; comprobar vigencia al retomar.

Acta, artefacto y evidencia: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ajustes-2026-09-15/PUBLICACION.md`. El inventario de otros 40001 es un pendiente separado que requiere análisis por recorrido, sin reemplazos globales automáticos. La matriz RLS general con otra semilla permanece NOT RUN; la matriz específica pasó.
