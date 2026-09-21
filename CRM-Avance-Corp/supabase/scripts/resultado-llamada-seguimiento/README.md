# Resultado y próxima acción — ensayo local

La autorización recibida de Miguel fue «Sí, probar únicamente en local».
El único destino de estos ensayos es `gestion_diaria_f4_vista_chvrqh` en el
contenedor `supabase_db_avancecorp-f5-bank`. Se reutiliza el banco fijo de F4.
No se crean bases, no se acepta una URL remota y no se publica nada.

La candidata `20260921153654_crm_resultado_llamada_seguimiento.sql` ya fue
instalada en esta copia. Desde la raíz del repositorio:

```sh
node CRM-Avance-Corp/supabase/scripts/resultado-llamada-seguimiento/ensayar.mjs
```

`ensayar.mjs` exige v4 instalada. Ejecuta el oráculo con rol real
`authenticated` (las altas del fixture usan postgres), las regresiones F2/F3/F4,
los 48 mutantes F1–F3, nueve incluidos en F4 y cinco nuevos v4.
Ensaya quitar y reinstalar v4 dentro de una transacción con datos v4 reales:
compara huellas completas de actividad, tarea y lead. Todo el fixture termina
en ROLLBACK; la instalación v4 anterior permanece. El censo analítico no cambia.
La salida contiene resultados y SHA; `verificacion.json` conserva la corrida
acreditada. El runner no escribe archivos ni instala dependencias.

F1 histórico (`gestion-diaria/test-gestion-diaria-registro.sql`) falla en J,
«metadata con claves fuera de la lista blanca». Se reprodujo con v4 retirada
y tras reinstalarla: su whitelist es anterior a la ampliación F3. No modificar
la producción ni relajar el oráculo viejo para anunciar PASS. El gate F1 y sus
diez mutantes sí pasan.

`reversa.sql` verifica la candidata y el gate antes de actuar, restaura literalmente
el gate F2 y retira solamente las tres funciones nuevas. No borra historia ni
tareas. En producción exigiría antes coordinar el frontend y resolver los
guardados v4 inciertos; ejecutarla no está autorizado por el permiso local.

Acta y respuesta a Claude:
`docs/gestion-diaria/RESULTADO-LLAMADA-SEGUIMIENTO.md`.
