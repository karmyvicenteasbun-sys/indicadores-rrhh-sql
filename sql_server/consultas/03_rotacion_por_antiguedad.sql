-- =====================================================================
-- 03. Renuncias según la antigüedad (versión SQL Server)
-- Pregunta: ¿en qué momento de la relación laboral se va la gente?
-- Técnicas: tabla de tramos con VALUES, CROSS APPLY para calcular la
--           antigüedad una sola vez, JOIN por rangos, SUM() OVER () para
--           porcentajes y tasa por exposición (meses-persona).
-- La tasa divide las renuncias de cada tramo por los meses-persona que la
-- gente pasó en ese tramo: corrige que hay más gente antigua que nueva.
-- =====================================================================
WITH tramos AS (
    SELECT orden, tramo, desde, hasta
    FROM (VALUES (1, N'Menos de 3 meses', 0, 3),
                 (2, N'3 a 6 meses', 3, 6),
                 (3, N'6 a 12 meses', 6, 12),
                 (4, N'1 a 2 años', 12, 24),
                 (5, N'2 a 5 años', 24, 60),
                 (6, N'Más de 5 años', 60, 100000)) AS t (orden, tramo, desde, hasta)
),
exposicion AS (
    SELECT t.orden, SUM(p.dias_trabajados) / 30.0 AS meses_persona
    FROM dbo.planilla_mensual AS p
    JOIN dbo.colaboradores    AS c ON c.id_colaborador = p.id_colaborador
    CROSS APPLY (SELECT CASE WHEN p.fecha_periodo > c.fecha_ingreso
                             THEN DATEDIFF(DAY, c.fecha_ingreso, p.fecha_periodo) / 30.44
                             ELSE 0 END AS meses) AS ant
    JOIN tramos AS t ON ant.meses >= t.desde AND ant.meses < t.hasta
    GROUP BY t.orden
),
renuncias AS (
    SELECT t.orden, COUNT(*) AS renuncias
    FROM dbo.colaboradores AS c
    CROSS APPLY (SELECT DATEDIFF(DAY, c.fecha_ingreso, c.fecha_egreso) / 30.44 AS meses) AS ant
    JOIN tramos AS t ON ant.meses >= t.desde AND ant.meses < t.hasta
    WHERE c.tipo_egreso = N'Renuncia voluntaria'
    GROUP BY t.orden
)
SELECT t.tramo,
       COALESCE(r.renuncias, 0)                                                         AS renuncias,
       ROUND(1.0 * COALESCE(r.renuncias, 0) / SUM(COALESCE(r.renuncias, 0)) OVER (), 3) AS pct_de_renuncias,
       ROUND(e.meses_persona, 0)                                                        AS meses_persona,
       ROUND(12.0 * COALESCE(r.renuncias, 0) / e.meses_persona, 3)                      AS tasa_anual_de_renuncia
FROM tramos AS t
JOIN exposicion     AS e ON e.orden = t.orden
LEFT JOIN renuncias AS r ON r.orden = t.orden
ORDER BY t.orden;
