-- =====================================================================
-- 08. Alerta de sobrecarga: horas extra altas varios meses seguidos (SQL Server)
-- Pregunta: ¿quién hizo más de 40 horas extra al mes durante 3 meses
--           seguidos o más en el último año? (riesgo de fatiga y accidentes)
-- Técnica: "huecos e islas". Si a un número de mes correlativo se le resta
--          ROW_NUMBER(), los meses consecutivos dan el mismo resultado y
--          forman una misma racha.
-- La versión con parámetros es dbo.usp_alerta_horas_extra (02_procedimientos.sql).
-- =====================================================================
WITH umbral AS (
    SELECT valor AS horas FROM dbo.parametros WHERE clave = 'umbral_horas_extra_mes'
),
meses_altos AS (
    SELECT pl.id_colaborador,
           pl.periodo,
           pl.horas_extra,
           YEAR(pl.fecha_periodo) * 12 + MONTH(pl.fecha_periodo) AS mes_correlativo
    FROM dbo.planilla_mensual AS pl
    CROSS JOIN umbral AS u
    WHERE pl.horas_extra > u.horas
      AND pl.fecha_periodo >= '20251001'
),
islas AS (
    SELECT id_colaborador, periodo, horas_extra,
           mes_correlativo - ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY mes_correlativo) AS isla
    FROM meses_altos
),
rachas AS (
    SELECT id_colaborador,
           MIN(periodo)                              AS desde,
           MAX(periodo)                              AS hasta,
           COUNT(*)                                  AS meses_seguidos,
           ROUND(AVG(CAST(horas_extra AS FLOAT)), 1) AS horas_extra_promedio
    FROM islas
    GROUP BY id_colaborador, isla
    HAVING COUNT(*) >= 3
)
SELECT r.id_colaborador, v.area, v.cargo, v.turno, r.desde, r.hasta, r.meses_seguidos, r.horas_extra_promedio,
       CASE WHEN r.hasta = '2026-09' THEN N'Sigue' ELSE N'Terminó' END AS situacion
FROM rachas AS r
JOIN dbo.v_colaboradores AS v ON v.id_colaborador = r.id_colaborador
ORDER BY r.meses_seguidos DESC, r.horas_extra_promedio DESC;
