"""
Arma la base en SQL Server y comprueba que las 9 consultas T-SQL den lo mismo
que la versión SQLite (resultados/*.csv).

1. Ejecuta sql_server/00_esquema.sql (tablas, restricciones, índices y vista).
2. Carga los CSV de datos/ desde Python (sirve aunque el servidor no pueda
   leer la carpeta; si puede, también está sql_server/01_cargar_datos.sql).
3. Ejecuta sql_server/02_procedimientos.sql y dbo.usp_validar_integridad.
4. Corre cada consulta de sql_server/consultas/ y la compara con resultados/.

Requisitos: pip install pyodbc pandas, y el "ODBC Driver 17/18 for SQL Server".
Usar una base vacía creada para esto (CREATE DATABASE rrhh): el script borra
y vuelve a crear sus tablas.

Uso:
    python sql_server/probar_sql_server.py "DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;DATABASE=rrhh;Trusted_Connection=yes;TrustServerCertificate=yes"
"""

import re
import sys
from pathlib import Path

import pandas as pd
import pyodbc

CARPETA = Path(__file__).resolve().parent
PROYECTO = CARPETA.parent
sys.path.insert(0, str(PROYECTO))
from crear_base import AREAS, NIVELES, PARAMETROS  # noqa: E402  (mismos supuestos que SQLite)


def lotes(archivo):
    """Separa un script en lotes por las líneas GO, como SSMS."""
    texto = archivo.read_text(encoding="utf-8")
    return [lote for lote in re.split(r"^\s*GO\s*$", texto, flags=re.MULTILINE | re.IGNORECASE) if lote.strip()]


def ejecutar_script(con, archivo):
    cur = con.cursor()
    for lote in lotes(archivo):
        cur.execute(lote)
        while cur.nextset():
            pass
    con.commit()


def sin_nulos(df):
    return [tuple(None if pd.isna(v) else v for v in fila) for fila in df.itertuples(index=False, name=None)]


def cargar(con):
    datos = PROYECTO / "datos"
    colaboradores = pd.read_csv(datos / "colaboradores.csv")
    planilla = pd.read_csv(datos / "planilla_mensual.csv")
    ausencias = pd.read_csv(datos / "ausencias.csv")

    cargos = (colaboradores[["cargo", "area", "nivel"]].drop_duplicates()
              .assign(orden_area=lambda d: d["area"].map(AREAS.index),
                      orden_nivel=lambda d: d["nivel"].map(NIVELES.index))
              .sort_values(["orden_area", "orden_nivel", "cargo"]).reset_index(drop=True))
    cargos["id_cargo"] = range(1, len(cargos) + 1)
    tabla = colaboradores.merge(cargos[["cargo", "area", "id_cargo"]], on=["cargo", "area"])
    columnas = ["id_colaborador", "id_cargo", "turno", "fecha_ingreso", "fecha_egreso", "tipo_egreso",
                "edad_ingreso", "distancia_km", "compa_ratio", "evaluacion_desempeno", "haber_basico_actual_bs"]

    cur = con.cursor()
    cur.fast_executemany = True
    cur.executemany("INSERT INTO dbo.areas VALUES (?, ?)", list(enumerate(AREAS, 1)))
    cur.executemany("INSERT INTO dbo.niveles VALUES (?, ?)", list(enumerate(NIVELES, 1)))
    cur.executemany("INSERT INTO dbo.cargos VALUES (?, ?, ?, ?)", [
        (int(f.id_cargo), f.cargo, AREAS.index(f.area) + 1, NIVELES.index(f.nivel) + 1) for f in cargos.itertuples()])
    cur.executemany(f"INSERT INTO dbo.colaboradores VALUES ({', '.join('?' * len(columnas))})", sin_nulos(tabla[columnas]))
    cur.executemany(f"INSERT INTO dbo.planilla_mensual VALUES ({', '.join('?' * planilla.shape[1])})", sin_nulos(planilla))
    cur.executemany(f"INSERT INTO dbo.ausencias VALUES ({', '.join('?' * ausencias.shape[1])})", sin_nulos(ausencias))
    cur.executemany("INSERT INTO dbo.parametros VALUES (?, ?, ?)", PARAMETROS)
    con.commit()


def iguales(obtenido, esperado):
    if list(obtenido.columns) != list(esperado.columns) or len(obtenido) != len(esperado):
        return False
    for col in esperado.columns:
        a, b = obtenido[col].reset_index(drop=True), esperado[col].reset_index(drop=True)
        if pd.api.types.is_numeric_dtype(b) and not b.isna().all():
            if (pd.to_numeric(a).astype(float) - b).abs().max() > 1e-6:
                return False
        elif not (a.astype(str) == b.astype(str)).all():
            return False
    return True


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with pyodbc.connect(sys.argv[1], autocommit=False) as con:
        ejecutar_script(con, CARPETA / "00_esquema.sql")
        cargar(con)
        ejecutar_script(con, CARPETA / "02_procedimientos.sql")

        print(pd.read_sql("EXEC dbo.usp_validar_integridad", con).to_string(index=False), "\n")

        todo_bien = True
        for archivo in sorted((CARPETA / "consultas").glob("*.sql")):
            obtenido = pd.read_sql(archivo.read_text(encoding="utf-8"), con)
            esperado = pd.read_csv(PROYECTO / "resultados" / f"{archivo.stem}.csv")
            ok = iguales(obtenido, esperado)
            todo_bien &= ok
            print(f"{archivo.name:<40}{len(obtenido):>5} filas  {'igual a SQLite' if ok else 'DISTINTO'}")
    print("\nTodo coincide con la versión SQLite." if todo_bien else "\nHay diferencias: revisar las consultas marcadas.")


if __name__ == "__main__":
    main()
