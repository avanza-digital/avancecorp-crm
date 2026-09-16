# Lead propio del supervisor

Miguel autorizó el 2026-09-16 permitir al supervisor crear y convertir sus
propios leads. En **Nuevo lead → Responsable comercial** aparece
**Yo — lead propio**. Debe seleccionarlo explícitamente; Sin asignar continúa
siendo la bandeja de reparto, y se mantienen los analistas de su equipo.

El responsable es `vendedor_id`, no el autor `creado_por`. La sesión proporciona
el id propio aunque el supervisor no tenga analistas a cargo. La ficha muestra
su nombre y permite convertir con la capacidad contractual vigente. El cliente,
contrato y Cartera conservan esa responsabilidad. No se amplía la toma de leads
existentes ni el origen Referido, que sigue reservado al analista.

No hizo falta cambiar SQL ni Edge: el servidor ya autorizaba esta propiedad.
La producción del supervisor se conserva en el total de capital y en el bloque
de Gerencia **Producción fuera del ranking**, sin puesto de analista. Un lead
manual de oficina mantiene aporte cero al KPI de conversión de leads recibidos.

Ver [[Produccion fuera del ranking (decision 2026-09-02)]] y
[[Deploy a Hostinger]]. Evidencia de verificación y alcance en
`CRM-Avance-Corp/supabase/scripts/supervisor-propio/README.md`.

Estado: implementación y pruebas completas; publicación pendiente de verificar.
