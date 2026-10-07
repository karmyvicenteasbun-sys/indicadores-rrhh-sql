"""
Estilo y funciones de apoyo para los gráficos del proyecto.

Criterios: marcas finas, grilla discreta, un solo color para una sola serie,
gris para el contexto y el color de acento solo donde está la historia.
"""

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyBboxPatch, Rectangle

# Paleta
SUPERFICIE = "#fcfcfb"
TINTA = "#0b0b0b"
TINTA_2 = "#52514e"
TENUE = "#898781"
GRILLA = "#e1e0d9"
EJE = "#c3c2b7"
AZUL = "#2a78d6"    # acento / una sola serie / "menos riesgo"
ROJO = "#e34948"    # "más riesgo"
GRIS = "#c3c2b7"    # contexto (de-énfasis)
CATEGORICOS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
CRITICO = "#d03b3b"   # variación desfavorable (siempre con flecha y texto)
FAVORABLE = "#006300" # variación favorable (siempre con flecha y texto)
AZULES = ["#cde2fb", "#b7d3f6", "#9ec5f4", "#86b6ef", "#6da7ec", "#5598e7",
          "#3987e5", "#2a78d6", "#256abf", "#1c5cab", "#184f95", "#104281", "#0d366b"]

FUENTE = "Datos ficticios generados para este ejemplo."


def aplicar_estilo():
    mpl.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Carlito", "Calibri", "Segoe UI", "Liberation Sans", "Arial", "DejaVu Sans"],
        "font.size": 11,
        "figure.facecolor": SUPERFICIE,
        "axes.facecolor": SUPERFICIE,
        "savefig.facecolor": SUPERFICIE,
        "axes.edgecolor": EJE,
        "axes.linewidth": 0.8,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.spines.left": False,
        "axes.grid": False,
        "grid.color": GRILLA,
        "grid.linewidth": 0.8,
        "xtick.color": TENUE,
        "ytick.color": TINTA_2,
        "xtick.labelsize": 10,
        "ytick.labelsize": 11,
        "xtick.major.size": 0,
        "ytick.major.size": 0,
        "axes.labelcolor": TINTA_2,
        "text.color": TINTA,
        "legend.frameon": False,
        "figure.dpi": 110,
        "savefig.dpi": 160,
    })


# --- Formatos (estilo boliviano: punto de miles, coma decimal) --------------
def miles(valor, decimales=0):
    texto = f"{valor:,.{decimales}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def bs(valor):
    return f"Bs {miles(valor)}"


def bs_compacto(valor):
    if abs(valor) >= 1_000_000:
        return f"Bs {miles(valor / 1_000_000, 1)} M"
    if abs(valor) >= 1_000:
        return f"Bs {miles(valor / 1_000, 0)} mil"
    return bs(valor)


def porcentaje(valor, decimales=0):
    return f"{miles(valor * 100, decimales)}%"


# --- Lienzo -------------------------------------------------------------------
def figura(ancho=10, alto=5.2, ejes=(0.08, 0.13, 0.88, 0.64)):
    """Figura con espacio arriba para título y subtítulo y abajo para la fuente."""
    fig = plt.figure(figsize=(ancho, alto))
    ax = fig.add_axes(ejes)
    return fig, ax


def encabezado(fig, titulo, subtitulo=None):
    fig.text(0.02, 0.955, titulo, fontsize=16, fontweight="bold", color=TINTA, va="top")
    if subtitulo:
        fig.text(0.02, 0.885, subtitulo, fontsize=11.5, color=TINTA_2, va="top", linespacing=1.35)


def pie(fig, texto=FUENTE):
    fig.text(0.02, 0.025, texto, fontsize=9, color=TENUE, va="bottom")


def guardar(fig, ruta):
    fig.savefig(ruta)
    return ruta


# --- Barras con el extremo de dato redondeado (4 px) y la base recta ----------
def _unidades_por_px(ax):
    ax.figure.canvas.draw()
    caja = ax.get_window_extent()
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    return abs(x1 - x0) / caja.width, abs(y1 - y0) / caja.height


def _barra(ax, base, valor, centro, grosor, color, rx, ry, horizontal=True):
    inicio, fin = sorted((base, valor))
    largo = fin - inicio
    if largo <= 0:
        return
    if horizontal:
        origen, ancho, alto, radio, aspecto = (inicio, centro - grosor / 2), largo, grosor, rx, ry / rx
    else:
        origen, ancho, alto, radio, aspecto = (centro - grosor / 2, inicio), grosor, largo, rx, ry / rx
    if (horizontal and largo <= rx) or (not horizontal and largo <= ry):
        ax.add_patch(Rectangle(origen, ancho, alto, facecolor=color, edgecolor="none", lw=0))
        return
    ax.add_patch(FancyBboxPatch(origen, ancho, alto, boxstyle=f"round,pad=0,rounding_size={radio}",
                                mutation_aspect=aspecto, facecolor=color, edgecolor="none", lw=0))
    # Se cuadra el extremo pegado a la línea base
    if horizontal:
        x_recto = inicio if valor >= base else fin - rx
        ax.add_patch(Rectangle((x_recto, centro - grosor / 2), rx, grosor, facecolor=color, edgecolor="none", lw=0))
    else:
        y_recto = inicio if valor >= base else fin - ry
        ax.add_patch(Rectangle((centro - grosor / 2, y_recto), grosor, ry, facecolor=color, edgecolor="none", lw=0))


def barras_horizontales(ax, etiquetas, valores, colores, textos=None, grosor_px=18, radio_px=4,
                        x_min=None, x_max=None, base=0.0):
    """Barras horizontales de arriba hacia abajo en el orden recibido."""
    n = len(valores)
    posiciones = np.arange(n)[::-1]
    ax.set_ylim(-0.6, n - 0.4)
    if x_min is None:
        x_min = min(min(valores), base)
    if x_max is None:
        x_max = max(max(valores), base) * 1.18
    ax.set_xlim(x_min, x_max)
    ux, uy = _unidades_por_px(ax)
    grosor = grosor_px * uy
    for y, valor, color in zip(posiciones, valores, colores):
        _barra(ax, base, valor, y, grosor, color, radio_px * ux, radio_px * uy, horizontal=True)
    ax.set_yticks(posiciones)
    ax.set_yticklabels(etiquetas)
    ax.spines["bottom"].set_visible(False)
    ax.set_xticks([])
    if textos is not None:
        separacion = 6 * ux
        for y, valor, texto in zip(posiciones, valores, textos):
            alineacion = "left" if valor >= base else "right"
            x = valor + separacion if valor >= base else valor - separacion
            ax.text(x, y, texto, va="center", ha=alineacion, fontsize=10.5, color=TINTA_2)
    return posiciones


def columnas(ax, etiquetas, valores, colores, textos=None, grosor_px=34, radio_px=4, y_max=None):
    """Columnas verticales con el valor sobre cada una."""
    n = len(valores)
    posiciones = np.arange(n)
    ax.set_xlim(-0.6, n - 0.4)
    ax.set_ylim(0, y_max if y_max is not None else max(valores) * 1.2)
    ux, uy = _unidades_por_px(ax)
    grosor = grosor_px * ux
    for x, valor, color in zip(posiciones, valores, colores):
        _barra(ax, 0, valor, x, grosor, color, radio_px * ux, radio_px * uy, horizontal=False)
    ax.set_xticks(posiciones)
    ax.set_xticklabels(etiquetas)
    ax.tick_params(axis="x", colors=TINTA_2, labelsize=10.5)
    ax.set_yticks([])
    if textos is not None:
        for x, valor, texto in zip(posiciones, valores, textos):
            ax.text(x, valor + 6 * uy, texto, ha="center", va="bottom", fontsize=10.5, color=TINTA_2)
    return posiciones
