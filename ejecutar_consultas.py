"""
Ejecuta cada consulta de consultas/*.sql sobre rrhh.db, guarda el resultado en
resultados/<consulta>.csv y arma los gráficos del README en img/.

Si rrhh.db no existe, la crea primero con crear_base.py.

Uso:
    python ejecutar_consultas.py
"""

import sqlite3
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import crear_base
import graficos as g

CARPETA = Path(__file__).resolve().parent
RESULTADOS = CARPETA / "resultados"
IMG = CARPETA / "img"


def ejecutar():
    if not crear_base.BASE.exists():
        crear_base.main()
    RESULTADOS.mkdir(exist_ok=True)
    tablas = {}
    with sqlite3.connect(crear_base.BASE) as con:
        for archivo in sorted((CARPETA / "consultas").glob("*.sql")):
            tabla = pd.read_sql_query(archivo.read_text(encoding="utf-8"), con)
            tabla.to_csv(RESULTADOS / f"{archivo.stem}.csv", index=False, encoding="utf-8")
            tablas[archivo.stem[:2]] = tabla
            print(f"{archivo.name:<40}{len(tabla):>5} filas")
    return tablas


def grafico_costo(costo):
    total = costo["costo_total_bs"].sum()
    cobertura = costo["costo_cobertura_bs"].sum() / total
    fig, ax = g.figura(alto=4.8, ejes=(0.25, 0.10, 0.62, 0.60))
    g.encabezado(fig, f"El ausentismo cuesta {g.bs_compacto(total)} al año; la mitad es cubrir los puestos",
                 "Costo del último año por área: días pagados sin trabajar y horas extra para cubrir la ausencia")
    y = np.arange(len(costo))[::-1]
    ax.barh(y, costo["costo_dias_pagados_bs"], height=0.5, color=g.CATEGORICOS[0], label="Días pagados sin trabajar")
    ax.barh(y, costo["costo_cobertura_bs"], left=costo["costo_dias_pagados_bs"], height=0.5,
            color=g.CATEGORICOS[1], edgecolor=g.SUPERFICIE, linewidth=2, label="Cobertura con horas extra")
    for yi, valor in zip(y, costo["costo_total_bs"]):
        ax.text(valor + total * 0.006, yi, g.bs(valor), va="center", fontsize=10.5, color=g.TINTA_2)
    ax.set_yticks(y)
    ax.set_yticklabels(costo["area"])
    ax.set_xticks([])
    ax.spines["bottom"].set_visible(False)
    ax.set_xlim(0, costo["costo_total_bs"].max() * 1.22)
    ax.legend(loc="lower right", fontsize=10, ncols=1)
    g.pie(fig)
    g.guardar(fig, IMG / "01_costo_ausentismo.png")
    print(f"  Costo del ausentismo: {g.bs(total)} ({g.porcentaje(cobertura)} en cobertura)")


def grafico_dias(dias):
    fig, ax = g.figura(alto=4.6, ejes=(0.07, 0.13, 0.88, 0.60))
    lunes = dias.loc[dias["dia"] == "Lunes", "pct_de_las_faltas"].iloc[0]
    g.encabezado(fig, f"Los lunes concentran el {g.porcentaje(lunes)} de las faltas injustificadas",
                 "Faltas injustificadas del último año según el día. Si fueran parejas, cada día tendría el 17%")
    colores = [g.AZUL if d in ("Lunes", "Viernes") else g.GRIS for d in dias["dia"]]
    g.columnas(ax, dias["dia"], dias["pct_de_las_faltas"].values, colores,
               textos=[g.porcentaje(v) for v in dias["pct_de_las_faltas"]], y_max=0.36)
    ax.axhline(1 / 6, color=g.TINTA_2, linewidth=1, linestyle=(0, (3, 3)), zorder=0)
    ax.text(5.45, 1 / 6 + 0.008, "Reparto parejo", ha="right", va="bottom", fontsize=10, color=g.TINTA_2)
    g.pie(fig)
    g.guardar(fig, IMG / "02_faltas_por_dia.png")


def grafico_rotacion(rotacion):
    fig, ax = g.figura(alto=5.0, ejes=(0.08, 0.13, 0.72, 0.60))
    empresa = rotacion[rotacion["area"] == "Toda la empresa"]
    logistica = rotacion[rotacion["area"] == "Logística y Distribución"]
    g.encabezado(fig, f"Logística pierde el {g.porcentaje(logistica['rotacion_voluntaria_12m'].iloc[-1])} "
                      "de su gente por año y sigue subiendo",
                 "Rotación voluntaria de los últimos 12 meses, medida cada mes. En gris, las demás áreas")
    for area, datos in rotacion.groupby("area"):
        if area in ("Toda la empresa", "Logística y Distribución"):
            continue
        ax.plot(pd.to_datetime(datos["periodo"]), datos["rotacion_voluntaria_12m"], color=g.GRILLA, linewidth=1.2)
    for datos, color, nombre in [(empresa, g.TINTA_2, "Toda la empresa"), (logistica, g.AZUL, "Logística")]:
        x = pd.to_datetime(datos["periodo"])
        ax.plot(x, datos["rotacion_voluntaria_12m"], color=color, linewidth=2)
        ax.plot(x.iloc[-1], datos["rotacion_voluntaria_12m"].iloc[-1], "o", markersize=8, color=color,
                markeredgecolor=g.SUPERFICIE, markeredgewidth=2)
        ax.text(x.iloc[-1] + pd.Timedelta(days=20), datos["rotacion_voluntaria_12m"].iloc[-1],
                f"{nombre} {g.porcentaje(datos['rotacion_voluntaria_12m'].iloc[-1], 1)}",
                va="center", fontsize=10.5, color=g.TINTA_2)
    meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    marcas = pd.date_range("2024-10-01", "2026-07-01", freq="3MS")
    ax.set_xticks(marcas)
    ax.set_xticklabels([f"{meses[m.month - 1]} {str(m.year)[2:]}" for m in marcas])
    ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: g.porcentaje(v)))
    ax.tick_params(axis="y", colors=g.TENUE, labelsize=10)
    ax.set_ylim(0, 0.40)
    ax.grid(axis="y")
    ax.set_axisbelow(True)
    g.pie(fig)
    g.guardar(fig, IMG / "03_rotacion_movil.png")


def grafico_antes_de_renunciar(antes):
    etiquetas = ["Últimos 3 meses\nantes de renunciar", "Meses anteriores de\nquienes renunciaron", "Quienes no\nrenunciaron"]
    ultimo = antes["ausentismo"].iloc[0]
    resto = antes["ausentismo"].iloc[2]
    fig, ax = g.figura(alto=4.6, ejes=(0.10, 0.17, 0.80, 0.55))
    g.encabezado(fig, f"Antes de renunciar, la gente falta {g.miles(ultimo / resto, 1)} veces más",
                 "Ausentismo (días de ausencia / días en planilla), oct-2023 a sep-2026")
    g.columnas(ax, etiquetas, antes["ausentismo"].values, [g.AZUL, g.GRIS, g.GRIS],
               textos=[g.porcentaje(v, 1) for v in antes["ausentismo"]], grosor_px=70)
    g.pie(fig)
    g.guardar(fig, IMG / "04_ausencias_antes_de_renunciar.png")


def main():
    tablas = ejecutar()
    g.aplicar_estilo()
    IMG.mkdir(exist_ok=True)
    grafico_costo(tablas["07"])
    grafico_dias(tablas["05"])
    grafico_rotacion(tablas["02"])
    grafico_antes_de_renunciar(tablas["09"])
    print("Gráficos guardados en img/")


if __name__ == "__main__":
    main()
