-- =====================================================================
-- 03. Renuncias según la antigüedad
-- Pregunta: ¿en qué momento de la relación laboral se va la gente?
-- Técnicas: tabla de tramos con VALUES, JOIN por rangos, SUM() OVER ()
--           para porcentajes y tasa por exposición (meses-persona).
-- La tasa divide las renuncias de cada tramo por los meses-persona que la
-- gente pasó en ese tramo: corrige que hay más gente antigua que nueva.
-- =====================================================================
WITH tramos (orden, tramo, desde, hasta) AS (
    VALUES (1, 'Menos de 3 meses', 0, 3),
           (2, '3 a 6 meses', 3, 6),
           (3, '6 a 12 meses', 6, 12),
           (4, '1 a 2 años', 12, 24),
           (5, '2 a 5 años', 24, 60),
           (6, 'Más de 5 años', 60, 100000)
),
exposicion AS (
    SELECT t.orden, SUM(p.dias_trabajados) / 30.0 AS meses_persona
    FROM planilla_mensual AS p
    JOIN colaboradores    AS c ON c.id_colaborador = p.id_colaborador
    JOIN tramos           AS t
      ON MAX(julianday(p.fecha_periodo) - julianday(c.fecha_ingreso), 0) / 30.44 >= t.desde
     AND MAX(julianday(p.fecha_periodo) - julianday(c.fecha_ingreso), 0) / 30.44 <  t.hasta
    GROUP BY t.orden
),
renuncias AS (
    SELECT t.orden, COUNT(*) AS renuncias
    FROM colaboradores AS c
    JOIN tramos        AS t
      ON (julianday(c.fecha_egreso) - julianday(c.fecha_ingreso)) / 30.44 >= t.desde
     AND (julianday(c.fecha_egreso) - julianday(c.fecha_ingreso)) / 30.44 <  t.hasta
    WHERE c.tipo_egreso = 'Renuncia voluntaria'
    GROUP BY t.orden
)
SELECT t.tramo,
       COALESCE(r.renuncias, 0)                                        AS renuncias,
       ROUND(1.0 * COALESCE(r.renuncias, 0) / SUM(COALESCE(r.renuncias, 0)) OVER (), 3) AS pct_de_renuncias,
       ROUND(e.meses_persona, 0)                                       AS meses_persona,
       ROUND(12.0 * COALESCE(r.renuncias, 0) / e.meses_persona, 3)     AS tasa_anual_de_renuncia
FROM tramos AS t
JOIN exposicion     AS e ON e.orden = t.orden
LEFT JOIN renuncias AS r ON r.orden = t.orden
ORDER BY t.orden;
