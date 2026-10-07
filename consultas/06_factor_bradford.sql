-- =====================================================================
-- 06. Factor de Bradford: ausencias cortas y frecuentes
-- Pregunta: ¿dónde se concentran los días de ausencia del último año?
-- Técnicas: LEFT JOIN para incluir a quien no faltó, NTILE() para
--           repartir a las personas en grupos y SUM() OVER () para el peso.
-- Factor de Bradford = episodios² × días. Pesa más faltar 6 veces 1 día
-- que faltar una vez 6 días seguidos, porque las ausencias cortas y
-- repetidas desordenan más la operación.
-- Solo personas activas al 30/09/2026; ausencias de oct-2025 a sep-2026.
-- =====================================================================
WITH ultimo_anio AS (
    SELECT id_colaborador, COUNT(*) AS episodios, SUM(dias) AS dias
    FROM ausencias
    WHERE fecha_inicio BETWEEN '2025-10-01' AND '2026-09-30'
    GROUP BY id_colaborador
),
personas AS (
    SELECT v.id_colaborador,
           COALESCE(u.episodios, 0)                      AS episodios,
           COALESCE(u.dias, 0)                           AS dias,
           COALESCE(u.episodios * u.episodios * u.dias, 0) AS factor_bradford
    FROM v_colaboradores AS v
    LEFT JOIN ultimo_anio AS u ON u.id_colaborador = v.id_colaborador
    WHERE v.fecha_egreso IS NULL
),
con_grupo AS (
    SELECT *, NTILE(20) OVER (ORDER BY factor_bradford DESC, id_colaborador) AS veintil
    FROM personas
),
grupos AS (
    SELECT CASE WHEN veintil = 1 THEN '1. El 5% con mayor factor'
                WHEN veintil <= 4 THEN '2. El 15% siguiente'
                ELSE '3. El 80% restante' END AS grupo,
           id_colaborador, episodios, dias, factor_bradford
    FROM con_grupo
)
SELECT grupo,
       COUNT(*)                                            AS personas,
       SUM(episodios)                                      AS episodios,
       SUM(dias)                                           AS dias_ausencia,
       ROUND(1.0 * SUM(dias) / SUM(SUM(dias)) OVER (), 3)  AS pct_de_los_dias,
       ROUND(1.0 * SUM(dias) / COUNT(*), 1)                AS dias_por_persona,
       MIN(factor_bradford)                                AS factor_minimo,
       MAX(factor_bradford)                                AS factor_maximo
FROM grupos
GROUP BY grupo
ORDER BY grupo;
