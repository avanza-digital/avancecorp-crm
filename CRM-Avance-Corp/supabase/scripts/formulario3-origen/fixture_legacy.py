"""La misma inversión real, nacida mientras A aún guarda el origen legado."""
from pathlib import Path


def conversiones_antes():
    texto = (Path(__file__).parent / 'conversiones.sql').read_text()
    viejo = "'ALTA MANUAL F3','985002001','formulario_3',1000,'PEN'"
    assert texto.count(viejo) == 1
    texto = texto.replace(viejo, viejo.replace("'formulario_3'", "'formulario'"))
    texto = texto.replace("origen='formulario_3'", "origen='formulario'")
    texto = texto.replace('cierres_formulario_3=3', 'cierres_formulario=3')
    texto = texto.replace("'{empresa,cierres,formulario_3}'", "'{empresa,cierres,formulario}'")
    texto = texto.replace("::date,'formulario_3'", "::date,'formulario'")
    texto = texto.replace("='formulario_3'", "='formulario'").replace("<>'formulario_3'", "<>'formulario'")
    # Esta asignación de campaña solo prepara el legado, como el importador
    # previo: la sesión humana ya terminó y todavía no hay inversión.
    marcador = "select crm.importar_lead_fn(jsonb_build_object"
    assert texto.count(marcador) == 1
    return texto.replace(marcador,
        "update crm.leads set campania_origen='Formulario 3' where telefono='+51985002001';\n" + marcador)
