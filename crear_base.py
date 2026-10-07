"""
Crea rrhh.db (SQLite) a partir de los CSV de la carpeta datos/.

1. Ejecuta sql/00_esquema.sql (tablas, restricciones, índices y vista).
2. Normaliza: áreas, niveles y cargos van a sus propias tablas.
3. Carga colaboradores, planilla mensual, ausencias y parámetros.
4. Revisa la integridad: claves foráneas y que los días de ausencia del
   detalle coincidan con los de la planilla.

Uso:
    python crear_base.py
"""

import sqlite3
from pathlib import Path

import pandas as pd

CARPETA = Path(__file__).resolve().parent
BASE = CARPETA / "rrhh.db"
DATOS = CARPETA / "datos"

# Mismo orden que en generar_datos.py
AREAS = ["Producción", "Logística y Distribución", "Ventas", "Mantenimiento", "Calidad", "Administración y Finanzas"]
NIVELES = ["Operativo", "Técnico y supervisión", "Profesional y jefatura"]

PARAMETROS = [
    ("aportes_patronales", 0.1671, "Aportes patronales sobre el total ganado"),
    ("provision_aguinaldo", 1 / 12, "Provisión mensual de aguinaldo"),
    ("provision_indemnizacion", 1 / 12, "Provisión mensual de indemnización"),
    ("recargo_horas_extra", 2.0, "La hora extra se paga al doble"),
    ("horas_mes", 240, "Horas de un mes de trabajo (30 días x 8 horas)"),
    ("horas_jornada", 8, "Horas de una jornada"),
    ("cobertura_operativos_lineas", 0.70,
     "Parte de los días de ausencia de operativos de Producción y Logística que se cubre con horas extra"),
    ("cobertura_operativos_otras", 0.30,
     "Parte de los días de ausencia de operativos de otras áreas que se cubre con horas extra"),
    ("umbral_horas_extra_mes", 40, "Horas extra al mes a partir de las que se considera sobrecarga"),
]


def main():
    BASE.unlink(missing_ok=True)
    colaboradores = pd.read_csv(DATOS / "colaboradores.csv")
    planilla = pd.read_csv(DATOS / "planilla_mensual.csv")
    ausencias = pd.read_csv(DATOS / "ausencias.csv")

    with sqlite3.connect(BASE) as con:
        con.execute("PRAGMA foreign_keys = ON")
        con.executescript((CARPETA / "sql" / "00_esquema.sql").read_text(encoding="utf-8"))

        con.executemany("INSERT INTO areas VALUES (?, ?)", list(enumerate(AREAS, 1)))
        con.executemany("INSERT INTO niveles VALUES (?, ?)", list(enumerate(NIVELES, 1)))
        cargos = (colaboradores[["cargo", "area", "nivel"]].drop_duplicates()
                  .assign(orden_area=lambda d: d["area"].map(AREAS.index),
                          orden_nivel=lambda d: d["nivel"].map(NIVELES.index))
                  .sort_values(["orden_area", "orden_nivel", "cargo"]).reset_index(drop=True))
        cargos["id_cargo"] = range(1, len(cargos) + 1)
        con.executemany("INSERT INTO cargos VALUES (?, ?, ?, ?)", [
            (int(f.id_cargo), f.cargo, AREAS.index(f.area) + 1, NIVELES.index(f.nivel) + 1)
            for f in cargos.itertuples()])

        tabla = colaboradores.merge(cargos[["cargo", "area", "id_cargo"]], on=["cargo", "area"])
        columnas = ["id_colaborador", "id_cargo", "turno", "fecha_ingreso", "fecha_egreso", "tipo_egreso",
                    "edad_ingreso", "distancia_km", "compa_ratio", "evaluacion_desempeno", "haber_basico_actual_bs"]
        tabla = tabla[columnas].astype(object).where(tabla[columnas].notna(), None)
        con.executemany(f"INSERT INTO colaboradores VALUES ({', '.join('?' * len(columnas))})",
                        tabla.itertuples(index=False, name=None))

        con.executemany(f"INSERT INTO planilla_mensual VALUES ({', '.join('?' * planilla.shape[1])})",
                        planilla.itertuples(index=False, name=None))
        con.executemany(f"INSERT INTO ausencias VALUES ({', '.join('?' * ausencias.shape[1])})",
                        ausencias.itertuples(index=False, name=None))
        con.executemany("INSERT INTO parametros VALUES (?, ?, ?)", PARAMETROS)

        # Controles de integridad
        errores_fk = con.execute("PRAGMA foreign_key_check").fetchall()
        descuadres = con.execute("""
            SELECT COUNT(*)
            FROM planilla_mensual AS p
            LEFT JOIN (SELECT id_colaborador, strftime('%Y-%m', fecha_inicio) AS periodo, SUM(dias) AS dias
                       FROM ausencias GROUP BY 1, 2) AS a
                   ON a.id_colaborador = p.id_colaborador AND a.periodo = p.periodo
            WHERE p.dias_ausencia <> COALESCE(a.dias, 0)""").fetchone()[0]
        if errores_fk or descuadres:
            raise RuntimeError(f"Integridad: {len(errores_fk)} errores de claves foráneas, {descuadres} meses descuadrados")

        for tabla_nombre in ["areas", "niveles", "cargos", "colaboradores", "planilla_mensual", "ausencias", "parametros"]:
            filas = con.execute(f"SELECT COUNT(*) FROM {tabla_nombre}").fetchone()[0]
            print(f"{tabla_nombre:<18}{filas:>8,} filas")
    print(f"Base creada: {BASE.name}. Integridad: OK")


if __name__ == "__main__":
    main()
