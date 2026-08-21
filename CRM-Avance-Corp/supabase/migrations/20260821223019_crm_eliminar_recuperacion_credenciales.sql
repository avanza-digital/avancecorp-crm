begin;

-- El CRM ya no ofrece recuperacion ni definicion de contrasena por correo.
-- Las identidades nuevas se crean confirmadas desde la Edge `crm-usuarios`,
-- con el documento normalizado como clave. Al retirar esta RPC desaparece la
-- ultima superficie Data API que preparaba un envio de recovery.
--
-- No se modifica Auth global, public.perfiles ni ninguna funcion del Portal.
drop function if exists crm.preparar_recuperacion_usuario_fn(uuid, uuid);

commit;
